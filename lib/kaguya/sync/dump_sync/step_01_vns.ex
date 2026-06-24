defmodule Kaguya.Sync.DumpSync.VNs do
  @moduledoc """
  Syncs VN core data from VNDB dump: titles, ratings, descriptions, image flags,
  release-derived fields (has_ero, release_date, min_age).

  Step 1: Updates existing VNs and imports new VNs (excluding banned).
  Reads in batches of 5000 from the dump, transforms fields to match Kaguya schema,
  and bulk-writes via Repo.insert_all with ON CONFLICT.

  Title resolution uses the same 7-level priority as update_vn_titles_from_vndb.exs:
    1. Official English title
    2. Official Japanese latin (romanized)
    3. Official Japanese title
    4. Official other language title (no latin)
    5. Official other language latin
    6. Non-official latin
    7. Non-official title

  New VNs are inserted with real slugs (on_conflict: :nothing).
  Existing VNs are updated with only @vn_replace_fields (slug is never touched).

  Supporting data (titles, image flags, release stats) is loaded per-batch
  to keep memory bounded.
  """

  require Logger

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbFieldMapper
  alias Kaguya.Sync.DumpSync.SyncProtection
  alias Kaguya.Utils.SlugUtils
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle, VnExternalLink}

  @batch_size 5000

  # Fields that get updated on conflict for existing VNs.
  # Notably excludes: :id, :vndb_id, :slug, :inserted_at
  # is_image_nsfw/is_image_suggestive excluded — set by CoverProcessing (step 08c)
  # based on our selected primary cover, not VNDB's default cover
  # Content fields — skipped for user-edited entities
  @vn_content_fields [
    :title,
    :description,
    :development_status,
    :length_category,
    :length_minutes,
    :original_language,
    :release_date,
    :min_age,
    :has_ero,
    :is_avn,
    :aliases,
    :title_category
  ]

  # VNDB tag IDs for the "3D-rendered art" cluster — discriminator for AVN
  # vs 2D-anime EVN. See migration 20260428200000.
  @avn_render_tags ~w(g2693 g3723 g3722)

  # Reference fields — always synced (VNDB external data, not user-editable)
  @vn_reference_fields [
    :vndb_rating,
    :vndb_vote_count,
    :temp_image_url,
    :updated_at
  ]

  @vn_replace_fields @vn_content_fields ++ @vn_reference_fields

  def run(
        %{
          vndb: vndb,
          dry_run: dry_run,
          vn_mapping: vn_mapping,
          banned_ids: banned_ids,
          category_map: category_map
        } = ctx
      ) do
    target_ids = ctx[:target_vndb_ids]

    user_edited_ids = SyncProtection.user_edited_vndb_ids(:visual_novel, VisualNovel)

    if MapSet.size(user_edited_ids) > 0,
      do:
        Logger.info(
          "#{MapSet.size(user_edited_ids)} user-edited VNs protected from content overwrite"
        )

    if target_ids do
      Logger.info("Importing #{length(target_ids)} targeted VN(s)...")

      process_targeted_vns(
        vndb,
        target_ids,
        vn_mapping,
        banned_ids,
        category_map,
        user_edited_ids
      )
    else
      Logger.info("Loading VNs from VNDB dump...")
      total_count = count_vns(vndb)
      Logger.info("Total VNs in dump: #{total_count}")

      if dry_run do
        dry_run_vns(vndb, vn_mapping, banned_ids)
      else
        process_vn_batches(vndb, vn_mapping, banned_ids, category_map, user_edited_ids)
      end
    end
  end

  # ── Targeted Import ─────────────────────────────────────────────────────────
  # Imports only specific VNs by VNDB ID — reuses all build/transform logic.

  defp process_targeted_vns(
         vndb,
         target_ids,
         vn_mapping,
         banned_ids,
         category_map,
         user_edited_vn_ids
       ) do
    now = DumpSync.now()
    phs = DumpSync.placeholders(target_ids)

    vns =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, olang::text, COALESCE(c_image, image) as image,
               c_average, c_votecount, description, devstatus, length, c_length, alias
        FROM vn WHERE id IN (#{phs})
        """,
        target_ids
      )

    if vns == [] do
      Logger.info("No VNs found in dump for targeted IDs")
      {:ok, 0}
    else
      vn_ids = Enum.map(vns, & &1.id)
      titles_map = load_titles_for(vndb, vn_ids)
      image_ids = vns |> Enum.map(& &1.image) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      image_flags_map = load_image_flags_for(vndb, image_ids)
      release_stats_map = load_release_stats_for(vndb, vn_ids)
      avn_styled_ids = load_avn_render_styles_for(vndb, vn_ids)

      valid_vns = Enum.reject(vns, fn vn -> MapSet.member?(banned_ids, vn_vndb_id(vn)) end)

      {existing_vns, new_vns} =
        Enum.split_with(valid_vns, fn vn -> Map.has_key?(vn_mapping, vn_vndb_id(vn)) end)

      new_slug_map = generate_vn_slugs(new_vns, titles_map, release_stats_map)

      new_rows =
        Enum.map(
          new_vns,
          &build_vn_row(
            &1,
            titles_map,
            image_flags_map,
            release_stats_map,
            avn_styled_ids,
            new_slug_map,
            category_map,
            now
          )
        )

      new_count =
        DumpSync.chunked_insert(VisualNovel, new_rows,
          on_conflict: :nothing,
          conflict_target: [:vndb_id]
        )

      existing_rows =
        Enum.map(
          existing_vns,
          &build_vn_row(
            &1,
            titles_map,
            image_flags_map,
            release_stats_map,
            avn_styled_ids,
            %{},
            category_map,
            now
          )
        )

      existing_count =
        SyncProtection.protected_upsert(
          VisualNovel,
          existing_rows,
          user_edited_vn_ids,
          & &1.vndb_id,
          full_replace_fields: @vn_replace_fields,
          reference_replace_fields: @vn_reference_fields,
          conflict_target: [:vndb_id]
        )

      new_vn_uuid_map = Map.new(new_rows, fn r -> {r.vndb_id, r.id} end)
      upsert_vn_titles(valid_vns, titles_map, vn_mapping, new_vn_uuid_map, user_edited_vn_ids)

      write_create_revisions_for_new_vns(new_vns, new_vn_uuid_map)

      Enum.each(valid_vns, fn vn ->
        titles = Map.get(titles_map, vn.id, [])
        title = resolve_title(titles, vn.olang) || "Unknown"

        Logger.info(
          "  #{if Map.has_key?(vn_mapping, vn_vndb_id(vn)), do: "↻", else: "+"} #{vn_vndb_id(vn)}: #{title}"
        )
      end)

      Report.record(
        :vns,
        new_count,
        existing_count,
        Enum.map(new_vns, fn vn ->
          titles = Map.get(titles_map, vn.id, [])

          %{
            id: vn_vndb_id(vn),
            title: resolve_title(titles, vn.olang) || "Unknown",
            slug: Map.get(new_slug_map, vn_vndb_id(vn), "—")
          }
        end)
      )

      Logger.info("Targeted VN import: #{new_count} new, #{existing_count} updated")
      {:ok, new_count + existing_count}
    end
  end

  # ── Create Revisions for New VNs ────────────────────────────────────────────
  #
  # Writes a :create revision for each VN that was actually inserted (distinct
  # from existing VNs). We verify by looking up vndb_id → uuid in the DB — the
  # on_conflict: :nothing insert silently skips duplicates, so the `new_rows`
  # UUIDs may differ from what's actually in the table. This reconciliation
  # avoids writing a hist snapshot against a uuid that isn't there.
  defp write_create_revisions_for_new_vns([], _new_vn_uuid_map), do: :ok

  defp write_create_revisions_for_new_vns(new_vns, new_vn_uuid_map) do
    # Keep only VNs whose intended UUID actually ended up in the DB.
    intended_vndb_ids = Enum.map(new_vns, &vn_vndb_id/1)

    import Ecto.Query

    actual =
      from(v in VisualNovel,
        where: v.vndb_id in ^intended_vndb_ids,
        select: {v.vndb_id, v.id}
      )
      |> Kaguya.Repo.all()
      |> Map.new()

    entries =
      Enum.flat_map(new_vns, fn vn ->
        vndb_id = vn_vndb_id(vn)
        intended_uuid = Map.get(new_vn_uuid_map, vndb_id)
        actual_uuid = Map.get(actual, vndb_id)

        # Only write a revision if the UUID we intended to insert actually
        # landed — otherwise a prior run already has a revision for this VN
        # under a different UUID and writing another would double-count.
        if intended_uuid && intended_uuid == actual_uuid do
          [
            %{
              entity_type: :visual_novel,
              entity_id: actual_uuid,
              action: :create,
              source: :vndb_sync,
              changed_fields: [],
              summary: "Imported from VNDB dump"
            }
          ]
        else
          []
        end
      end)

    # Extra idempotency: skip any VN that already has a :create revision
    # (e.g. a VN manually added via the API before this sync noticed it).
    # Prior edit/revert rows are tolerated — we only want to avoid a
    # duplicate create.
    entries =
      if entries == [] do
        entries
      else
        existing =
          from(c in Kaguya.Revisions.Change,
            where:
              c.entity_type == :visual_novel and c.action == :create and
                c.entity_id in ^Enum.map(entries, & &1.entity_id),
            select: c.entity_id
          )
          |> Kaguya.Repo.all()
          |> MapSet.new()

        Enum.reject(entries, fn e -> MapSet.member?(existing, e.entity_id) end)
      end

    case Kaguya.Revisions.bulk_create_system_changes(entries) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to write VN create revisions: #{inspect(reason)}")
        :ok
    end
  end

  # ── Dry Run ──────────────────────────────────────────────────────────────────
  # Lists new VNs without writing anything. No full diff — just new vs existing counts.

  defp dry_run_vns(vndb, vn_mapping, banned_ids) do
    new_vns = collect_new_vns(vndb, vn_mapping, banned_ids)

    dump_count = count_vns(vndb)
    banned_count = MapSet.size(banned_ids)
    existing_count = dump_count - banned_count - length(new_vns)

    Logger.info("[DRY RUN] ═══ VN Report ═══")

    Logger.info(
      "[DRY RUN] Dump: #{dump_count} total, #{banned_count} banned, #{existing_count} existing, #{length(new_vns)} new"
    )

    if new_vns != [] do
      Logger.info("[DRY RUN] ── New VNs ──")

      Enum.each(new_vns, fn vn ->
        Logger.info("[DRY RUN]   + #{vn.vndb_id}: #{vn.title}")
      end)
    end

    Logger.info("[DRY RUN] ════════════════")
    {:ok, existing_count + length(new_vns)}
  end

  defp collect_new_vns(vndb, vn_mapping, banned_ids) do
    do_collect_new(vndb, vn_mapping, banned_ids, 0, [])
  end

  defp do_collect_new(vndb, vn_mapping, banned_ids, offset, acc) do
    vns =
      DumpSync.query_vndb!(vndb, """
      SELECT id, olang::text
      FROM vn
      ORDER BY id
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if vns == [] do
      acc
    else
      new_vns =
        Enum.reject(vns, fn vn ->
          MapSet.member?(banned_ids, vn_vndb_id(vn)) or
            Map.has_key?(vn_mapping, vn_vndb_id(vn))
        end)

      new_entries =
        if new_vns != [] do
          # Load titles only for new VNs in this batch
          new_ids = Enum.map(new_vns, & &1.id)
          titles_map = load_titles_for(vndb, new_ids)

          Enum.map(new_vns, fn vn ->
            titles = Map.get(titles_map, vn.id, [])
            title = resolve_title(titles, vn.olang) || "Unknown"
            %{vndb_id: vn_vndb_id(vn), title: title}
          end)
        else
          []
        end

      do_collect_new(vndb, vn_mapping, banned_ids, offset + @batch_size, acc ++ new_entries)
    end
  end

  # ── Live Run ─────────────────────────────────────────────────────────────────

  defp process_vn_batches(vndb, vn_mapping, banned_ids, category_map, user_edited_vn_ids) do
    now = DumpSync.now()

    {total_count, _, new_total, updated_total, new_ids} =
      do_batches(
        vndb,
        vn_mapping,
        banned_ids,
        category_map,
        user_edited_vn_ids,
        now,
        0,
        0,
        0,
        0,
        []
      )

    Report.record(:vns, new_total, updated_total, new_ids)

    Logger.info(
      "VN sync complete: #{total_count} upserted (#{new_total} new, #{updated_total} updated)"
    )

    extlink_count = sync_vn_extlinks(vndb)
    Logger.info("VN extlinks sync complete: #{extlink_count} manual + wikidata-derived")

    {:ok, total_count + extlink_count}
  end

  defp do_batches(
         vndb,
         vn_mapping,
         banned_ids,
         category_map,
         user_edited_vn_ids,
         now,
         offset,
         acc,
         new_acc,
         updated_acc,
         ids_acc
       ) do
    vns =
      DumpSync.query_vndb!(vndb, """
      SELECT id, olang::text, COALESCE(c_image, image) as image,
             c_average, c_votecount, description, devstatus, length, c_length,
             alias
      FROM vn
      ORDER BY id
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if vns == [] do
      {acc, offset, new_acc, updated_acc, ids_acc}
    else
      Logger.info("Processing VN batch at offset #{offset} (#{length(vns)} rows)...")

      # Load supporting data for just this batch
      vn_ids = Enum.map(vns, & &1.id)
      titles_map = load_titles_for(vndb, vn_ids)

      image_ids = vns |> Enum.map(& &1.image) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      image_flags_map = load_image_flags_for(vndb, image_ids)

      release_stats_map = load_release_stats_for(vndb, vn_ids)
      avn_styled_ids = load_avn_render_styles_for(vndb, vn_ids)

      # Filter out banned, keep both existing and new
      valid_vns = Enum.reject(vns, fn vn -> MapSet.member?(banned_ids, vn_vndb_id(vn)) end)

      # Separate new vs existing for slug generation
      {existing_vns, new_vns} =
        Enum.split_with(valid_vns, fn vn -> Map.has_key?(vn_mapping, vn_vndb_id(vn)) end)

      # Log new VNs
      if new_vns != [] do
        Enum.each(new_vns, fn vn ->
          titles = Map.get(titles_map, vn.id, [])
          title = resolve_title(titles, vn.olang) || "Unknown"
          Logger.info("  + NEW: #{vn_vndb_id(vn)} — #{title}")
        end)
      end

      # Insert new VNs with real slugs (year-based suffixes for collisions)
      new_slug_map = generate_vn_slugs(new_vns, titles_map, release_stats_map)

      new_rows =
        Enum.map(
          new_vns,
          &build_vn_row(
            &1,
            titles_map,
            image_flags_map,
            release_stats_map,
            avn_styled_ids,
            new_slug_map,
            category_map,
            now
          )
        )

      new_count =
        DumpSync.chunked_insert(VisualNovel, new_rows,
          on_conflict: :nothing,
          conflict_target: [:vndb_id]
        )

      # Update existing VNs — only @vn_replace_fields, slug is never touched
      existing_rows =
        Enum.map(
          existing_vns,
          &build_vn_row(
            &1,
            titles_map,
            image_flags_map,
            release_stats_map,
            avn_styled_ids,
            %{},
            category_map,
            now
          )
        )

      existing_count =
        SyncProtection.protected_upsert(
          VisualNovel,
          existing_rows,
          user_edited_vn_ids,
          & &1.vndb_id,
          full_replace_fields: @vn_replace_fields,
          reference_replace_fields: @vn_reference_fields,
          conflict_target: [:vndb_id]
        )

      Logger.info("  Batch done: #{new_count} new, #{existing_count} updated")
      count = new_count + existing_count

      # Build vndb_id → uuid map for new VNs from the rows we just inserted
      new_vn_uuid_map = Map.new(new_rows, fn r -> {r.vndb_id, r.id} end)

      # Upsert vn_titles for all valid VNs in this batch
      upsert_vn_titles(valid_vns, titles_map, vn_mapping, new_vn_uuid_map, user_edited_vn_ids)

      # Write :create revisions for newly inserted VNs. Deferred until after
      # titles are upserted so the hist snapshot captures them.
      write_create_revisions_for_new_vns(new_vns, new_vn_uuid_map)

      batch_new_ids =
        Enum.map(new_vns, fn vn ->
          vndb_id = vn_vndb_id(vn)
          titles = Map.get(titles_map, vn.id, [])
          title = resolve_title(titles, vn.olang) || "Unknown"
          slug = Map.get(new_slug_map, vndb_id, "—")
          %{id: vndb_id, title: title, slug: slug}
        end)

      do_batches(
        vndb,
        vn_mapping,
        banned_ids,
        category_map,
        user_edited_vn_ids,
        now,
        offset + @batch_size,
        acc + count,
        new_acc + new_count,
        updated_acc + existing_count,
        ids_acc ++ batch_new_ids
      )
    end
  end

  defp build_vn_row(
         vn,
         titles_map,
         image_flags_map,
         release_stats_map,
         avn_styled_ids,
         new_slug_map,
         category_map,
         now
       ) do
    vndb_id = vn_vndb_id(vn)
    titles = Map.get(titles_map, vn.id, [])

    title = resolve_title(titles, vn.olang) || "Unknown"
    desc = VndbFieldMapper.clean_description(vn.description)
    dev_status = VndbFieldMapper.map_development_status(vn.devstatus)
    length_min = nullify_zero(vn.c_length)

    length_cat =
      VndbFieldMapper.map_length_category(vn.length) ||
        VndbFieldMapper.length_category_from_minutes(length_min)

    olang = vn.olang
    {is_nsfw, is_suggestive} = get_image_flags(vn.image, image_flags_map)
    vndb_rating = compute_rating(vn.c_average)
    vndb_vote_count = vn.c_votecount
    temp_image_url = build_cover_url(vn.image)

    # Release-derived fields (from release_stats CTE)
    rs = Map.get(release_stats_map, vn.id, %{})
    release_date = Map.get(rs, :release_date)
    min_age = Map.get(rs, :min_age)
    has_ero = Map.get(rs, :has_ero, false)

    is_avn = olang == "en" and has_ero and MapSet.member?(avn_styled_ids, vn.id)

    aliases = VndbFieldMapper.parse_latin_aliases(vn.alias)

    # New VNs: real slug from new_slug_map, inserted via on_conflict: :nothing.
    # Existing VNs: called with empty slug_map, so falls back to UUID placeholder.
    # Placeholder satisfies NOT NULL but is discarded — existing path uses
    # on_conflict: {:replace, @vn_replace_fields} which excludes :slug.
    slug = Map.get(new_slug_map, vndb_id) || UUIDv7.generate()

    %{
      id: UUIDv7.generate(),
      vndb_id: vndb_id,
      title: title,
      slug: slug,
      description: desc,
      development_status: dev_status,
      length_category: length_cat,
      length_minutes: length_min,
      original_language: olang,
      release_date: release_date,
      min_age: min_age,
      has_ero: has_ero,
      is_avn: is_avn,
      is_image_nsfw: is_nsfw,
      is_image_suggestive: is_suggestive,
      vndb_rating: vndb_rating,
      vndb_vote_count: vndb_vote_count,
      aliases: aliases,
      temp_image_url: temp_image_url,
      title_category: Map.get(category_map, vndb_id, :vn),
      inserted_at: now,
      updated_at: now
    }
  end

  defp generate_vn_slugs([], _titles_map, _release_stats_map), do: %{}

  defp generate_vn_slugs(new_vns, titles_map, release_stats_map) do
    slug_items =
      Enum.map(new_vns, fn vn ->
        titles = Map.get(titles_map, vn.id, [])
        title = resolve_title(titles, vn.olang) || "vn-#{vn.id}"
        rs = Map.get(release_stats_map, vn.id, %{})
        release_date = Map.get(rs, :release_date)
        year = if release_date, do: release_date.year
        %{title: title, vn: vn, year: year}
      end)

    slugged =
      SlugUtils.build_unique_slugs(slug_items, VisualNovel, :slug, & &1.title,
        year_fun: & &1.year
      )

    Map.new(slugged, fn s -> {vn_vndb_id(s.vn), s._slug} end)
  end

  # ── Title Resolution ───────────────────────────────────────────────────────
  #
  # 7-level priority matching update_vn_titles_from_vndb.exs (the correction script).
  # Works directly with atom-keyed dump title rows — no API format conversion needed.
  #
  # For non-English, non-Japanese titles: picks latin romanization when available,
  # otherwise the native-script title. This matches the CASE expression in the
  # correction script's `chosen` column.

  defp resolve_title([], _olang), do: nil

  defp resolve_title(titles, _olang) do
    # Try each priority level in order, return first non-blank match
    find_title(titles, [
      # 1. Official English title
      &(official?(&1) and &1.lang == "en"),
      # 2. Official Japanese latin
      &(official?(&1) and &1.lang == "ja" and non_blank?(&1.latin)),
      # 3. Official Japanese title
      &(official?(&1) and &1.lang == "ja"),
      # 4. Official other language title (no latin available)
      &(official?(&1) and !non_blank?(&1.latin)),
      # 5. Official other language latin
      &(official?(&1) and non_blank?(&1.latin)),
      # 6. Non-official latin
      &(!official?(&1) and non_blank?(&1.latin)),
      # 7. Non-official title (fallback)
      fn _t -> true end
    ])
  end

  defp find_title(_titles, []), do: nil

  defp find_title(titles, [match_fn | rest]) do
    case Enum.find(titles, match_fn) do
      nil ->
        find_title(titles, rest)

      t ->
        # For priorities 2, 5, 6: prefer latin. Otherwise: title.
        value = pick_title_value(t, match_fn)

        if non_blank?(value),
          do: VndbFieldMapper.sanitize_utf8(value),
          else: find_title(titles, rest)
    end
  end

  # If the match was based on having a non-blank latin, use latin. Otherwise use title.
  defp pick_title_value(t, _match_fn) do
    cond do
      # Official JA with latin → use latin (priority 2)
      official?(t) and t.lang == "ja" and non_blank?(t.latin) -> t.latin
      # Official non-EN with latin → use latin (priority 5)
      official?(t) and t.lang != "en" and non_blank?(t.latin) -> t.latin
      # Non-official with latin → use latin (priority 6)
      !official?(t) and non_blank?(t.latin) -> t.latin
      # Otherwise → use title
      true -> t.title
    end
  end

  defp official?(%{official: true}), do: true
  defp official?(_), do: false

  # ── VN Titles Upsert ──────────────────────────────────────────────────────

  defp upsert_vn_titles(valid_vns, titles_map, vn_mapping, new_vn_uuid_map, user_edited_vn_ids) do
    title_rows =
      Enum.flat_map(valid_vns, fn vn ->
        vndb_id = vn_vndb_id(vn)
        vn_uuid = Map.get(vn_mapping, vndb_id) || Map.get(new_vn_uuid_map, vndb_id)

        if vn_uuid && not MapSet.member?(user_edited_vn_ids, vndb_id) do
          titles = Map.get(titles_map, vn.id, [])

          Enum.map(titles, fn t ->
            %{
              id: UUIDv7.generate(),
              visual_novel_id: vn_uuid,
              lang: t.lang,
              official: t.official || false,
              title: VndbFieldMapper.sanitize_utf8(t.title) || "Unknown",
              latin: if(non_blank?(t.latin), do: VndbFieldMapper.sanitize_utf8(t.latin))
            }
          end)
        else
          []
        end
      end)

    if title_rows != [] do
      DumpSync.chunked_insert(VNTitle, title_rows,
        on_conflict: {:replace, [:official, :title, :latin]},
        conflict_target: [:visual_novel_id, :lang]
      )
    end
  end

  # ── Per-Batch Data Loading ─────────────────────────────────────────────────

  defp load_titles_for(_vndb, []), do: %{}

  defp load_titles_for(vndb, vn_ids) do
    placeholders = Enum.map_join(1..length(vn_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, lang::text, official, title, latin
        FROM vn_titles
        WHERE id IN (#{placeholders})
        """,
        vn_ids
      )

    Enum.group_by(rows, & &1.id)
  end

  defp load_image_flags_for(_vndb, []), do: %{}

  defp load_image_flags_for(vndb, image_ids) do
    placeholders = Enum.map_join(1..length(image_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, c_sexual_avg, c_violence_avg, c_votecount
        FROM images
        WHERE id IN (#{placeholders})
        """,
        image_ids
      )

    Map.new(rows, fn r -> {r.id, r} end)
  end

  defp load_avn_render_styles_for(_vndb, []), do: MapSet.new()

  defp load_avn_render_styles_for(vndb, vn_ids) do
    placeholders = Enum.map_join(1..length(vn_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT DISTINCT vid
        FROM tags_vn
        WHERE vid IN (#{placeholders})
          AND tag = ANY($#{length(vn_ids) + 1}::text[])
          AND NOT ignore
          AND vote > 0
        """,
        vn_ids ++ [@avn_render_tags]
      )

    MapSet.new(rows, & &1.vid)
  end

  defp load_release_stats_for(_vndb, []), do: %{}

  defp load_release_stats_for(vndb, vn_ids) do
    placeholders = Enum.map_join(1..length(vn_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT rv.vid,
               MIN(r.released) AS first_release_raw,
               MIN(r.minage) AS min_age,
               BOOL_OR(r.has_ero) AS has_ero
        FROM releases_vn rv
        JOIN releases r ON r.id = rv.id
        WHERE rv.vid IN (#{placeholders})
        GROUP BY rv.vid
        """,
        vn_ids
      )

    Map.new(rows, fn r ->
      {r.vid,
       %{
         release_date: DumpSync.parse_vndb_date(r.first_release_raw),
         min_age: r.min_age,
         has_ero: r.has_ero || false
       }}
    end)
  end

  defp count_vns(vndb) do
    [[count]] = DumpSync.query_vndb_raw!(vndb, "SELECT COUNT(*) FROM vn")
    count
  end

  # ── Transform Helpers ───────────────────────────────────────────────────────

  defp get_image_flags(nil, _map), do: {false, false}

  defp get_image_flags(image_id, image_flags_map) do
    case Map.get(image_flags_map, image_id) do
      nil ->
        {false, false}

      img ->
        sexual = (img.c_sexual_avg || 0) / 100.0
        votecount = img.c_votecount || 0
        VndbFieldMapper.compute_image_flags(sexual, votecount)
    end
  end

  defp compute_rating(nil), do: nil
  defp compute_rating(0), do: nil

  defp compute_rating(c_average) when is_integer(c_average) do
    Decimal.div(Decimal.new(c_average), Decimal.new(100))
  end

  defp compute_rating(c_average) when is_float(c_average) do
    Decimal.div(Decimal.new(round(c_average)), Decimal.new(100))
  end

  defp build_cover_url(nil), do: nil

  defp build_cover_url(image_id) when is_binary(image_id) do
    case Regex.run(~r/^cv(\d+)$/, image_id) do
      [_, num_str] ->
        num = String.to_integer(num_str)
        suffix = rem(num, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
        "https://t.vndb.org/cv/#{suffix}/#{num}.jpg"

      _ ->
        nil
    end
  end

  defp nullify_zero(nil), do: nil
  defp nullify_zero(0), do: nil
  defp nullify_zero(val), do: val

  defp non_blank?(nil), do: false
  defp non_blank?(""), do: false
  defp non_blank?(s) when is_binary(s), do: String.trim(s) != ""
  defp non_blank?(_), do: false

  defp vn_vndb_id(%{id: id}) when is_integer(id), do: "v#{id}"
  defp vn_vndb_id(%{id: <<"v", _::binary>> = id}), do: id
  defp vn_vndb_id(%{id: id}), do: "v#{id}"

  # ── VN External Links ─────────────────────────────────────────────────────
  #
  # Two-phase import mirroring how VNDB displays VN extlinks:
  #   1. Manual extlinks from vn_extlinks table (wikidata, renai, encubed, wp)
  #   2. Wikidata-derived links from the wikidata cache table
  #
  # For VNs, VNDB uses wikidata almost exclusively for reference links.
  # Manual extlinks just provide the wikidata pointer and a few niche sites.

  @vn_wikidata_fields [
    {"enwiki", "enwiki", false},
    {"jawiki", "jawiki", false},
    {"mobygames_game", "mobygames_game", false},
    {"gamefaqs_game", "gamefaqs_game", false},
    {"igdb_game", "igdb_game", false},
    {"howlongtobeat", "howlongtobeat", false},
    {"pcgamingwiki", "pcgamingwiki", false},
    {"acdb_source", "acdb_source", false},
    {"vgmdb_product", "vgmdb_product", false},
    {"indiedb_game", "indiedb_game", false}
  ]

  @extlink_batch_size 5000

  defp sync_vn_extlinks(vndb) do
    Logger.info("Syncing VN external links...")

    vn_uuid_map = load_vn_vndb_to_uuid()
    now = DumpSync.now()

    # Phase 1: Manual extlinks from vn_extlinks table
    manual_count = sync_vn_manual_extlinks(vndb, vn_uuid_map, now)
    Logger.info("  Manual VN extlinks: #{manual_count}")

    # Phase 2: Wikidata-derived links
    wd_count = sync_vn_wikidata_links(vndb, vn_uuid_map, now)
    Logger.info("  Wikidata-derived VN extlinks: #{wd_count}")

    manual_count + wd_count
  end

  defp sync_vn_manual_extlinks(vndb, vn_uuid_map, now) do
    do_vn_extlink_batches(vndb, vn_uuid_map, now, 0, 0)
  end

  defp do_vn_extlink_batches(vndb, vn_uuid_map, now, offset, acc) do
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT ve.id AS vn_id, e.site::text, e.value
      FROM vn_extlinks ve
      JOIN extlinks e ON e.id = ve.link
      ORDER BY ve.id, e.site
      LIMIT #{@extlink_batch_size} OFFSET #{offset}
      """)

    if rows == [] do
      acc
    else
      insert_rows =
        Enum.flat_map(rows, fn row ->
          case Map.get(vn_uuid_map, row.vn_id) do
            nil ->
              []

            uuid ->
              # Remap deprecated "wp" → "enwiki" so wikidata enrichment can upsert over it
              site = if row.site == "wp", do: "enwiki", else: row.site

              [
                %{
                  vn_id: uuid,
                  site: site,
                  value: String.slice(row.value || "", 0, 1000),
                  inserted_at: now,
                  updated_at: now
                }
              ]
          end
        end)
        |> Enum.uniq_by(fn r -> {r.vn_id, r.site} end)

      # Preserve any locally curated extlink already occupying
      # this site slot. Dump sync should only backfill missing VNDB links,
      # not overwrite local ownership of `(vn_id, site)`.
      count =
        DumpSync.chunked_insert(VnExternalLink, insert_rows,
          on_conflict: :nothing,
          conflict_target: [:vn_id, :site]
        )

      do_vn_extlink_batches(vndb, vn_uuid_map, now, offset + @extlink_batch_size, acc + count)
    end
  end

  defp sync_vn_wikidata_links(vndb, vn_uuid_map, now) do
    # Query VNs that have a wikidata extlink → join with wikidata cache
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT ve.id AS vn_id, w.*
      FROM vn_extlinks ve
      JOIN extlinks e ON e.id = ve.link
      JOIN wikidata w ON w.id = e.value::int
      WHERE e.site::text = 'wikidata'
      """)

    insert_rows =
      Enum.flat_map(rows, fn row ->
        case Map.get(vn_uuid_map, row.vn_id) do
          nil -> []
          uuid -> build_vn_wikidata_rows(uuid, row, now)
        end
      end)
      |> Enum.uniq_by(fn r -> {r.vn_id, r.site} end)

    # Preserve existing local links on site conflict. This keeps dump
    # sync append-only for VN extlinks until we have provenance on rows.
    DumpSync.chunked_insert(VnExternalLink, insert_rows,
      on_conflict: :nothing,
      conflict_target: [:vn_id, :site]
    )
  end

  defp build_vn_wikidata_rows(vn_uuid, wd_row, now) do
    Enum.flat_map(@vn_wikidata_fields, fn {wd_col, site, _fallback?} ->
      value = extract_wikidata_value(wd_row, wd_col)

      case value do
        nil ->
          []

        val ->
          [
            %{
              vn_id: vn_uuid,
              site: site,
              value: String.slice(to_string(val), 0, 1000),
              inserted_at: now,
              updated_at: now
            }
          ]
      end
    end)
  end

  # Wikidata values are either scalars (enwiki/jawiki) or arrays; take first element.
  defp extract_wikidata_value(row, column) do
    raw = Map.get(row, String.to_atom(column)) || Map.get(row, column)

    case raw do
      nil -> nil
      "" -> nil
      [] -> nil
      [first | _] -> first
      val when is_binary(val) and val != "" -> val
      val when is_integer(val) -> to_string(val)
      _ -> nil
    end
  end

  defp load_vn_vndb_to_uuid do
    import Ecto.Query

    from(v in VisualNovel, where: not is_nil(v.vndb_id), select: {v.vndb_id, v.id})
    |> Kaguya.Repo.all()
    |> Map.new()
  end
end
