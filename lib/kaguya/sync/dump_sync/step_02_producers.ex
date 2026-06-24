defmodule Kaguya.Sync.DumpSync.Producers do
  @moduledoc """
  Syncs producer entities from VNDB dump.

  Step 2: Producer definitions (~27K rows, processed in batches).
  New producers are inserted with real slugs (on_conflict: :nothing).
  Existing producers are updated with only @producer_replace_fields (slug is never touched).
  """

  require Logger

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbFieldMapper
  alias Kaguya.Utils.SlugUtils
  alias Kaguya.Producers.{Producer, ProducerExternalLink}

  @batch_size 5000

  @producer_content_fields [:name, :description, :producer_type, :language]
  @producer_reference_fields [:updated_at]
  @producer_replace_fields @producer_content_fields ++ @producer_reference_fields

  alias Kaguya.Sync.DumpSync.SyncProtection

  def run(%{vndb: vndb, dry_run: dry_run, vn_mapping: vn_mapping} = _ctx) do
    protected_ids = SyncProtection.user_edited_vndb_ids(:producer, Producer)

    if MapSet.size(protected_ids) > 0,
      do:
        Logger.info(
          "#{MapSet.size(protected_ids)} user-edited producers protected from content overwrite"
        )

    Logger.info("Loading producers from VNDB dump...")

    total = count_producers(vndb)
    Logger.info("Total producers in dump: #{total}")

    # Pre-compute which producers have at least one release linked to an importable VN.
    # Producers linked only to banned/non-imported VNs are skipped entirely.
    importable_producer_ids = load_importable_producer_ids(vndb, vn_mapping)
    skipped = total - MapSet.size(importable_producer_ids)

    Logger.info(
      "Importable producers: #{MapSet.size(importable_producer_ids)} (#{skipped} skipped — no importable VN links)"
    )

    if dry_run do
      Logger.info("[DRY RUN] Would process #{MapSet.size(importable_producer_ids)} producers")

      Logger.info(
        "[DRY RUN] Would skip #{skipped} producers (linked only to banned/non-imported VNs)"
      )

      {:ok, total}
    else
      existing = load_existing_producer_vndb_ids()

      {count, new_total, updated_total, new_ids} =
        do_producer_batches(
          vndb,
          existing,
          importable_producer_ids,
          protected_ids,
          0,
          0,
          0,
          0,
          []
        )

      Report.record(:producers, new_total, updated_total, new_ids)

      Logger.info(
        "Producer sync complete: #{count} upserted (#{new_total} new, #{updated_total} updated), #{skipped} skipped (no importable VNs)"
      )

      extlink_count = sync_producer_extlinks(vndb)
      Report.record(:producer_extlinks, 0, extlink_count)
      Logger.info("Producer extlinks sync complete: #{extlink_count} upserted")

      wd_count = sync_producer_wikidata_links(vndb)
      Logger.info("Producer wikidata-derived links: #{wd_count} upserted")

      {:ok, count + extlink_count + wd_count}
    end
  end

  defp do_producer_batches(
         vndb,
         existing_ids,
         importable_ids,
         protected_ids,
         offset,
         acc,
         new_acc,
         updated_acc,
         ids_acc
       ) do
    producers =
      DumpSync.query_vndb!(vndb, """
      SELECT id, name, latin, type::text, lang::text, description
      FROM producers
      ORDER BY id
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if producers == [] do
      {acc, new_acc, updated_acc, ids_acc}
    else
      # Filter to producers that have at least one importable VN link
      producers = Enum.filter(producers, fn p -> MapSet.member?(importable_ids, p.id) end)

      if producers == [] do
        do_producer_batches(
          vndb,
          existing_ids,
          importable_ids,
          protected_ids,
          offset + @batch_size,
          acc,
          new_acc,
          updated_acc,
          ids_acc
        )
      else
        Logger.info(
          "Processing producer batch at offset #{offset} (#{length(producers)} importable)..."
        )

        now = DumpSync.now()

        {existing_producers, new_producers} =
          Enum.split_with(producers, fn p -> MapSet.member?(existing_ids, p.id) end)

        # Insert new producers with real slugs
        new_slug_map = generate_producer_slugs(new_producers)
        new_rows = Enum.map(new_producers, &build_producer_row(&1, new_slug_map, now))

        new_count =
          DumpSync.chunked_insert(Producer, new_rows,
            on_conflict: :nothing,
            conflict_target: [:vndb_id]
          )

        write_create_revisions_for_new_producers(new_producers, new_rows)

        # Update existing producers — protected entities only get reference fields
        existing_rows = Enum.map(existing_producers, &build_producer_row(&1, %{}, now))

        existing_count =
          SyncProtection.protected_upsert(Producer, existing_rows, protected_ids, & &1.vndb_id,
            full_replace_fields: @producer_replace_fields,
            reference_replace_fields: @producer_reference_fields,
            conflict_target: [:vndb_id]
          )

        batch_new_ids =
          Enum.map(new_producers, fn p ->
            name = VndbFieldMapper.sanitize_utf8(p.latin || p.name) || "Unknown"
            slug = Map.get(new_slug_map, p.id, "—")
            %{id: p.id, name: name, slug: slug}
          end)

        do_producer_batches(
          vndb,
          existing_ids,
          importable_ids,
          protected_ids,
          offset + @batch_size,
          acc + new_count + existing_count,
          new_acc + new_count,
          updated_acc + existing_count,
          ids_acc ++ batch_new_ids
        )
      end
    end
  end

  # Writes a :create revision for each producer that was actually inserted
  # (not a conflict). Looks up which intended UUIDs match the DB so a second
  # run doesn't double-write revisions for the same producer.
  defp write_create_revisions_for_new_producers([], _new_rows), do: :ok

  defp write_create_revisions_for_new_producers(new_producers, new_rows) do
    import Ecto.Query

    intended_map = Map.new(new_rows, fn r -> {r.vndb_id, r.id} end)
    intended_vndb_ids = Enum.map(new_producers, & &1.id)

    actual =
      from(p in Producer,
        where: p.vndb_id in ^intended_vndb_ids,
        select: {p.vndb_id, p.id}
      )
      |> Kaguya.Repo.all()
      |> Map.new()

    entries =
      Enum.flat_map(new_producers, fn p ->
        intended_uuid = Map.get(intended_map, p.id)
        actual_uuid = Map.get(actual, p.id)

        if intended_uuid && intended_uuid == actual_uuid do
          [
            %{
              entity_type: :producer,
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

    # Extra idempotency: skip any producer that already has a :create
    # revision (e.g. a producer manually added via the API before this
    # sync noticed it). Prior edit/revert rows are tolerated — we only
    # want to avoid a duplicate create.
    entries =
      if entries == [] do
        entries
      else
        existing =
          from(c in Kaguya.Revisions.Change,
            where:
              c.entity_type == :producer and c.action == :create and
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
        Logger.warning("Failed to write producer create revisions: #{inspect(reason)}")
        :ok
    end
  end

  defp build_producer_row(p, slug_map, now) do
    vndb_id = p.id
    name = VndbFieldMapper.sanitize_utf8(p.latin || p.name) || "Unknown Producer"

    # New producers: real slug from slug_map, inserted via on_conflict: :nothing.
    # Existing producers: called with empty slug_map, so falls back to UUID placeholder.
    # Placeholder satisfies NOT NULL but is discarded — existing path uses
    # on_conflict: {:replace, @producer_replace_fields} which excludes :slug.
    slug = Map.get(slug_map, vndb_id) || UUIDv7.generate()

    %{
      id: UUIDv7.generate(),
      vndb_id: vndb_id,
      name: name,
      description: VndbFieldMapper.clean_description(p.description),
      producer_type: VndbFieldMapper.map_producer_type(p.type),
      language: p.lang,
      slug: slug,
      inserted_at: now,
      updated_at: now
    }
  end

  defp generate_producer_slugs([]), do: %{}

  defp generate_producer_slugs(new_producers) do
    slug_items =
      Enum.map(new_producers, fn p ->
        name = VndbFieldMapper.sanitize_utf8(p.latin || p.name) || "producer-#{p.id}"
        %{title: name, producer: p}
      end)

    slugged = SlugUtils.build_unique_slugs(slug_items, Producer, :slug, & &1.title)
    Map.new(slugged, fn s -> {s.producer.id, s._slug} end)
  end

  # ── Producer External Links ─────────────────────────────────────────────

  defp sync_producer_extlinks(vndb) do
    Logger.info("Syncing producer external links...")

    # Build vndb_id → uuid mapping for all producers
    producer_uuid_map = load_producer_vndb_to_uuid()

    now = DumpSync.now()

    # Stream extlinks in batches using OFFSET/LIMIT
    do_extlink_batches(vndb, producer_uuid_map, now, 0, 0)
  end

  defp do_extlink_batches(vndb, producer_uuid_map, now, offset, acc) do
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT pe.id AS producer_id, e.site::text, e.value
      FROM producers_extlinks pe
      JOIN extlinks e ON e.id = pe.link
      ORDER BY pe.id, e.site
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if rows == [] do
      acc
    else
      insert_rows =
        Enum.flat_map(rows, fn row ->
          case Map.get(producer_uuid_map, row.producer_id) do
            nil ->
              []

            uuid ->
              # Remap deprecated "wp" → "enwiki" so wikidata enrichment can upsert over it
              site = if row.site == "wp", do: "enwiki", else: row.site

              [
                %{
                  producer_id: uuid,
                  site: site,
                  value: String.slice(row.value || "", 0, 1000),
                  inserted_at: now,
                  updated_at: now
                }
              ]
          end
        end)
        |> Enum.uniq_by(fn r -> {r.producer_id, r.site} end)

      # Preserve any locally curated extlink already occupying
      # this site slot. Dump sync should only backfill missing VNDB links,
      # not overwrite local ownership of `(producer_id, site)`.
      count =
        DumpSync.chunked_insert(ProducerExternalLink, insert_rows,
          on_conflict: :nothing,
          conflict_target: [:producer_id, :site]
        )

      do_extlink_batches(vndb, producer_uuid_map, now, offset + @batch_size, acc + count)
    end
  end

  defp load_producer_vndb_to_uuid do
    import Ecto.Query

    from(p in Producer, where: not is_nil(p.vndb_id), select: {p.vndb_id, p.id})
    |> Kaguya.Repo.all()
    |> Map.new()
  end

  defp count_producers(vndb) do
    [[count]] = DumpSync.query_vndb_raw!(vndb, "SELECT COUNT(*) FROM producers")
    count
  end

  defp load_existing_producer_vndb_ids do
    import Ecto.Query

    from(p in Producer, where: not is_nil(p.vndb_id), select: p.vndb_id)
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end

  # Returns the set of producer IDs (raw dump format) that have at least one
  # release linked to an importable (non-banned, existing) VN.
  defp load_importable_producer_ids(vndb, vn_mapping) do
    DumpSync.query_vndb_raw!(vndb, """
      SELECT DISTINCT rp.pid, rv.vid
      FROM releases_producers rp
      JOIN releases_vn rv ON rv.id = rp.id
    """)
    |> Enum.reduce(MapSet.new(), fn [pid, vid], acc ->
      if Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, pid)
      else
        acc
      end
    end)
  end

  # ── Wikidata-derived Links ─────────────────────────────────────────────
  #
  # VNDB caches Wikidata properties in a `wikidata` table (included in the dump).
  # Their API/website merges these with manual extlinks at display time:
  #   - enwiki/jawiki: always shown (Wikipedia sitelinks)
  #   - twitter, mobygames_company, gamefaqs_company, pixiv_user, soundcloud:
  #     shown only when no manual link exists for that site (fallback)
  #
  # We flatten these into producer_external_links during import so we don't
  # need a separate wikidata cache table.

  # Wikidata column → {extlink site key, fallback?}
  # Fallback means: only insert if no manual link exists (on_conflict: :nothing)
  @producer_wikidata_fields [
    {"enwiki", "enwiki", false},
    {"jawiki", "jawiki", false},
    {"twitter", "twitter", true},
    {"mobygames_company", "mobygames_comp", true},
    {"gamefaqs_company", "gamefaqs_comp", true},
    {"pixiv_user", "pixiv", true},
    {"soundcloud", "scloud", true}
  ]

  defp sync_producer_wikidata_links(vndb) do
    Logger.info("Enriching producer links from wikidata cache...")

    producer_uuid_map = load_producer_vndb_to_uuid()
    now = DumpSync.now()

    # Query: join producers that have a wikidata extlink → wikidata cache table
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT pe.id AS producer_id, w.*
      FROM producers_extlinks pe
      JOIN extlinks e ON e.id = pe.link
      JOIN wikidata w ON w.id = e.value::int
      WHERE e.site::text = 'wikidata'
      """)

    # Build insert rows: always-shown links + fallback links
    {always_rows, fallback_rows} =
      Enum.reduce(rows, {[], []}, fn row, {always_acc, fallback_acc} ->
        case Map.get(producer_uuid_map, row.producer_id) do
          nil ->
            {always_acc, fallback_acc}

          uuid ->
            {a, f} = build_wikidata_link_rows(uuid, row, now)
            {always_acc ++ a, fallback_acc ++ f}
        end
      end)

    # Preserve existing local links on site conflict. Without row-level
    # provenance, dump sync should be append-only for producer extlinks.
    always_count =
      DumpSync.chunked_insert(
        ProducerExternalLink,
        Enum.uniq_by(always_rows, fn r -> {r.producer_id, r.site} end),
        on_conflict: :nothing,
        conflict_target: [:producer_id, :site]
      )

    # Fallback links: skip if manual link already exists
    fallback_count =
      DumpSync.chunked_insert(
        ProducerExternalLink,
        Enum.uniq_by(fallback_rows, fn r -> {r.producer_id, r.site} end),
        on_conflict: :nothing,
        conflict_target: [:producer_id, :site]
      )

    always_count + fallback_count
  end

  defp build_wikidata_link_rows(producer_uuid, wd_row, now) do
    Enum.reduce(@producer_wikidata_fields, {[], []}, fn {wd_col, site, fallback?},
                                                        {always, fallback} ->
      value = extract_wikidata_value(wd_row, wd_col)

      case value do
        nil ->
          {always, fallback}

        val ->
          link = %{
            producer_id: producer_uuid,
            site: site,
            value: String.slice(to_string(val), 0, 1000),
            inserted_at: now,
            updated_at: now
          }

          if fallback?,
            do: {always, [link | fallback]},
            else: {[link | always], fallback}
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
end
