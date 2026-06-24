defmodule Kaguya.Sync.DumpSync.Releases do
  @moduledoc """
  Syncs releases, extlinks, and VN-producer junctions from VNDB dump.

  Step 6: Processes in batches of release IDs.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.{VndbFieldMapper, VndbStorefrontMapper}
  alias Kaguya.Releases.{ReleaseTitleHelper, Release, ReleaseExtlink}
  alias Kaguya.Producers.VNProducer

  @batch_size 1000

  @release_content_fields [
    :title,
    :display_title,
    :latin_title,
    :original_language,
    :release_date,
    :release_type,
    :patch,
    :freeware,
    :official,
    :has_ero,
    :uncensored,
    :voiced,
    :minage,
    :engine,
    :platforms,
    :languages,
    :mtl_languages,
    :producers,
    :notes,
    :reso_x,
    :reso_y,
    :media
  ]

  @release_reference_fields [:updated_at]
  @release_replace_fields @release_content_fields ++ @release_reference_fields

  alias Kaguya.Sync.DumpSync.SyncProtection

  def run(
        %{
          vndb: vndb,
          dry_run: dry_run,
          vn_mapping: vn_mapping,
          producer_mapping: producer_mapping
        } = ctx
      ) do
    Logger.info("Loading releases from VNDB dump...")

    # Load lookup tables
    engines = load_engines(vndb)
    Logger.info("Loaded #{map_size(engines)} engines")

    producers = load_producer_names(vndb)
    Logger.info("Loaded #{map_size(producers)} producer names")

    # Get release_id → [{vn_vndb_id, rtype}] mapping for our VNs
    # Targeted import: only load releases for target VNs
    our_vndb_ids = ctx[:target_vndb_ids] || Map.keys(vn_mapping)
    release_vn_map = load_release_vn_map(vndb, our_vndb_ids)

    # Filter out superseded releases — keep only the latest version of each chain
    superseded_ids = load_superseded_release_ids(vndb)
    {release_vn_map, superseded_count} = filter_superseded(release_vn_map, superseded_ids)

    release_ids = Map.keys(release_vn_map)

    Logger.info(
      "Found #{length(release_ids)} releases for our VNs (#{superseded_count} superseded filtered)"
    )

    if dry_run do
      Logger.info("[DRY RUN] Would process #{length(release_ids)} releases")
      {:ok, length(release_ids)}
    else
      # Load VN title variants from VNDB dump for display_title computation
      # Targeted import: only load for target VNs (avoids iterating all 59K)
      scoped_mapping =
        if ctx[:target_vndb_ids], do: Map.take(vn_mapping, our_vndb_ids), else: vn_mapping

      vn_titles = load_vn_title_variants(vndb, scoped_mapping)

      # Load existing pairs to track new vs updated
      existing_releases = load_existing_release_pairs()
      existing_vn_producers = load_existing_vn_producer_pairs()

      Logger.info(
        "Existing releases: #{MapSet.size(existing_releases)}, VN-producers: #{MapSet.size(existing_vn_producers)}"
      )

      protected_release_ids = SyncProtection.user_edited_vndb_ids(:release, Release)

      if MapSet.size(protected_release_ids) > 0,
        do:
          Logger.info(
            "#{MapSet.size(protected_release_ids)} user-edited releases protected from content overwrite"
          )

      {total_releases, total_extlinks, new_rel_ids} =
        release_ids
        |> Enum.chunk_every(@batch_size)
        |> Enum.with_index(1)
        |> Enum.reduce({0, 0, []}, fn {batch_ids, batch_num}, {rel_acc, ext_acc, ids_acc} ->
          {rel_count, ext_count, batch_new_ids} =
            process_batch(
              vndb,
              batch_ids,
              release_vn_map,
              vn_mapping,
              engines,
              producers,
              existing_releases,
              vn_titles,
              protected_release_ids
            )

          Logger.info("Release batch #{batch_num}: #{rel_count} releases, #{ext_count} extlinks")
          {rel_acc + rel_count, ext_acc + ext_count, ids_acc ++ batch_new_ids}
        end)

      new_rel_count = length(new_rel_ids)
      updated_rel_count = total_releases - new_rel_count

      # Derive VN-producer junctions from release producers
      protected_vn_uuids = SyncProtection.user_edited_ids(:visual_novel)

      {producer_count, new_prod_count} =
        sync_vn_producers(
          vndb,
          release_ids,
          release_vn_map,
          vn_mapping,
          producer_mapping,
          existing_vn_producers,
          protected_vn_uuids
        )

      Report.record(:releases, new_rel_count, updated_rel_count, Enum.uniq(new_rel_ids))
      Report.record(:release_extlinks, 0, total_extlinks)
      Report.record(:vn_producers, new_prod_count, producer_count - new_prod_count)

      Logger.info(
        "Release sync complete: #{total_releases} releases (#{new_rel_count} new), #{total_extlinks} extlinks, #{producer_count} VN-producers (#{new_prod_count} new)"
      )

      {:ok, total_releases + total_extlinks + producer_count}
    end
  end

  # ── Batch Processing ────────────────────────────────────────────────────────

  defp process_batch(
         vndb,
         release_ids,
         release_vn_map,
         vn_mapping,
         engines,
         producers,
         existing_releases,
         vn_titles,
         protected_release_ids
       ) do
    titles = load_titles(vndb, release_ids)
    platforms = load_platforms(vndb, release_ids)
    extlinks = load_extlinks(vndb, release_ids)
    rel_producers = load_release_producers(vndb, release_ids)
    media = load_media(vndb, release_ids)
    releases = load_releases(vndb, release_ids)

    now = DumpSync.now()

    # Build release rows — one per (release_id, vn_uuid) pair
    {release_rows, new_ids} =
      Enum.reduce(releases, {[], []}, fn rel, {rows_acc, ids_acc} ->
        release_id = rel.id
        vn_vndb_ids = Map.get(release_vn_map, release_id, [])

        Enum.reduce(vn_vndb_ids, {rows_acc, ids_acc}, fn {vid, rtype}, {r_acc, i_acc} ->
          case Map.get(vn_mapping, vid) do
            nil ->
              {r_acc, i_acc}

            vn_uuid ->
              rel_titles = Map.get(titles, release_id, [])
              {title, latin_title} = resolve_title(rel_titles, rel.olang)

              row =
                build_release_row(
                  rel,
                  release_id,
                  vn_uuid,
                  rtype,
                  title,
                  latin_title,
                  Map.get(platforms, release_id, []),
                  rel_titles,
                  Map.get(rel_producers, release_id, []),
                  Map.get(media, release_id, []),
                  engines,
                  producers,
                  vn_titles,
                  now
                )

              is_new = not MapSet.member?(existing_releases, {release_id, vn_uuid})
              new_id = if is_new, do: [%{id: release_id, title: title, vn: vid}], else: []
              {[Map.put(row, :id, UUIDv7.generate()) | r_acc], new_id ++ i_acc}
          end
        end)
      end)

    rel_count = upsert_releases(release_rows, protected_release_ids)

    ext_count =
      if release_rows != [] and map_size(extlinks) > 0 do
        # Build UUID map after releases are upserted so new rows are included
        release_uuid_map = get_release_uuid_map(release_ids)

        upsert_extlinks(
          extlinks,
          release_vn_map,
          vn_mapping,
          release_uuid_map,
          protected_release_ids,
          now
        )
      else
        0
      end

    # Write :create revisions for releases that were actually inserted
    # (distinct from existing ones). We rebuild the UUID map after the
    # upsert so we only reference UUIDs that made it into the DB.
    if release_rows != [] do
      release_uuid_map = get_release_uuid_map(release_ids)

      write_create_revisions_for_new_releases(
        release_rows,
        new_ids,
        release_vn_map,
        vn_mapping,
        release_uuid_map
      )
    end

    {rel_count, ext_count, new_ids}
  end

  # Writes :create revisions for releases that were new in this batch.
  # `new_ids` tracks inserted {vndb_release_id, vn_vndb_id} pairs; the UUID
  # map resolves them to actual release UUIDs post-insert.
  defp write_create_revisions_for_new_releases(
         _release_rows,
         [],
         _release_vn_map,
         _vn_mapping,
         _uuid_map
       ),
       do: :ok

  defp write_create_revisions_for_new_releases(
         _release_rows,
         new_ids,
         _release_vn_map,
         vn_mapping,
         release_uuid_map
       ) do
    entries =
      Enum.flat_map(new_ids, fn %{id: release_vndb_id, vn: vn_vndb_id} ->
        vn_uuid = Map.get(vn_mapping, vn_vndb_id)

        case vn_uuid && Map.get(release_uuid_map, {release_vndb_id, vn_uuid}) do
          nil ->
            []

          release_uuid ->
            [
              %{
                entity_type: :release,
                entity_id: release_uuid,
                action: :create,
                source: :vndb_sync,
                changed_fields: [],
                summary: "Imported from VNDB dump"
              }
            ]
        end
      end)

    # Only write for releases that don't already have a :create revision
    # (idempotency guard — release_rows get upserted on sync re-runs).
    # We filter on action == :create specifically so a release that was
    # manually created via the API and subsequently edited still gets
    # no duplicate create revision, but prior edit rows don't block us.
    entries =
      if entries == [] do
        entries
      else
        existing =
          from(c in Kaguya.Revisions.Change,
            where:
              c.entity_type == :release and c.action == :create and
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
        Logger.warning("Failed to write release create revisions: #{inspect(reason)}")
        :ok
    end
  end

  defp build_release_row(
         rel,
         release_id,
         vn_uuid,
         rtype,
         title,
         latin_title,
         plats,
         rel_titles,
         rel_prods,
         rel_media,
         engines,
         producers,
         vn_titles,
         now
       ) do
    engine_name = if rel.engine, do: Map.get(engines, rel.engine), else: nil

    vn_title_variants = Map.get(vn_titles, vn_uuid, [])

    display_title =
      if vn_title_variants != [],
        do: ReleaseTitleHelper.compute_display_title(title, vn_title_variants),
        else: title

    languages = rel_titles |> Enum.map(& &1.lang) |> Enum.uniq() |> Enum.sort()

    mtl_languages =
      rel_titles |> Enum.filter(& &1.mtl) |> Enum.map(& &1.lang) |> Enum.uniq() |> Enum.sort()

    producer_json =
      Enum.map(rel_prods, fn p ->
        name = Map.get(producers, p.pid, %{name: to_string(p.pid)})

        %{
          "vndb_id" => p.pid,
          "name" => name.name,
          "developer" => p.developer,
          "publisher" => p.publisher
        }
      end)

    %{
      vndb_id: release_id,
      visual_novel_id: vn_uuid,
      title: title,
      display_title: display_title,
      latin_title: latin_title,
      original_language: to_string(rel.olang),
      release_date: DumpSync.parse_vndb_date(rel.released),
      release_type: to_string(rtype),
      patch: rel.patch,
      freeware: rel.freeware,
      official: rel.official,
      has_ero: rel.has_ero,
      uncensored: rel.uncensored,
      voiced: rel.voiced,
      minage: rel.minage,
      engine: engine_name,
      platforms: plats |> Enum.map(&to_string/1) |> Enum.sort(),
      languages: languages |> Enum.map(&to_string/1),
      mtl_languages: mtl_languages |> Enum.map(&to_string/1),
      producers: producer_json,
      notes: VndbFieldMapper.clean_release_notes(rel.notes),
      reso_x: if(is_integer(rel.reso_x) and rel.reso_x > 0, do: rel.reso_x, else: nil),
      reso_y: if(is_integer(rel.reso_y) and rel.reso_y > 0, do: rel.reso_y, else: nil),
      media:
        Enum.map(rel_media, fn %{medium: m, qty: q} ->
          %{
            "medium" => to_string(m),
            "label" => VndbStorefrontMapper.media_label(to_string(m)),
            "qty" => q
          }
        end),
      inserted_at: now,
      updated_at: now
    }
  end

  defp upsert_releases([], _protected_ids), do: 0

  defp upsert_releases(rows, protected_ids) do
    SyncProtection.protected_upsert(Release, rows, protected_ids, & &1.vndb_id,
      full_replace_fields: @release_replace_fields,
      reference_replace_fields: @release_reference_fields,
      conflict_target: [:vndb_id, :visual_novel_id]
    )
  end

  defp upsert_extlinks(
         extlinks_by_release,
         release_vn_map,
         vn_mapping,
         release_uuid_map,
         protected_release_ids,
         now
       ) do
    rows =
      Enum.flat_map(extlinks_by_release, fn {release_id, links} ->
        # Skip extlinks for user-edited releases
        if MapSet.member?(protected_release_ids, release_id) do
          []
        else
          vn_vndb_ids = Map.get(release_vn_map, release_id, [])

          Enum.flat_map(vn_vndb_ids, fn {vid, _rtype} ->
            case Map.get(vn_mapping, vid) do
              nil ->
                []

              vn_uuid ->
                case Map.get(release_uuid_map, {release_id, vn_uuid}) do
                  nil ->
                    []

                  release_uuid ->
                    Enum.flat_map(links, fn {site, value} ->
                      url = VndbStorefrontMapper.build_url(site, value)
                      label = VndbStorefrontMapper.label(site)

                      if url do
                        base = [{release_uuid, site, label, url}]

                        if site == "steam" do
                          base ++
                            [
                              {release_uuid, "steamdb", "SteamDB",
                               "https://steamdb.info/app/#{value}"}
                            ]
                        else
                          base
                        end
                      else
                        []
                      end
                    end)
                end
            end
          end)
        end
      end)
      |> Enum.uniq_by(fn {release_uuid, site, _label, url} -> {release_uuid, site, url} end)

    insert_rows =
      Enum.map(rows, fn {release_uuid, site, label, url} ->
        %{
          id: UUIDv7.generate(),
          vn_release_id: release_uuid,
          site: site,
          label: label,
          url: url,
          inserted_at: now,
          updated_at: now
        }
      end)

    DumpSync.chunked_insert(ReleaseExtlink, insert_rows,
      on_conflict: {:replace, [:label, :updated_at]},
      conflict_target: [:vn_release_id, :site, :url]
    )
  end

  # ── VN-Producer Junctions from Release Data ─────────────────────────────────

  defp sync_vn_producers(
         vndb,
         release_ids,
         release_vn_map,
         vn_mapping,
         producer_mapping,
         existing_vn_producers,
         protected_vn_uuids
       ) do
    now = DumpSync.now()

    # Load all release producers with release dates in chunks
    producer_rows =
      release_ids
      |> Enum.chunk_every(5000)
      |> Enum.flat_map(fn chunk ->
        placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

        DumpSync.query_vndb_raw!(
          vndb,
          """
          SELECT rp.id, rp.pid, rp.developer, rp.publisher, r.released
          FROM releases_producers rp
          JOIN releases r ON r.id = rp.id
          WHERE rp.id IN (#{placeholders})
          """,
          chunk
        )
      end)

    # Build VN-producer entries with role and release date
    vn_producer_entries =
      Enum.flat_map(producer_rows, fn [release_id, pid, is_dev, is_pub, released] ->
        vn_vndb_ids = Map.get(release_vn_map, release_id, [])
        producer_uuid = Map.get(producer_mapping, pid)

        if producer_uuid do
          Enum.flat_map(vn_vndb_ids, fn {vid, _rtype} ->
            with vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, vid),
                 false <- MapSet.member?(protected_vn_uuids, vn_uuid) do
              role =
                cond do
                  is_dev and is_pub -> "developer_publisher"
                  is_dev -> "developer"
                  is_pub -> "publisher"
                  true -> "publisher"
                end

              release_date = if is_dev, do: DumpSync.parse_vndb_date(released), else: nil
              [{vn_uuid, producer_uuid, role, release_date}]
            else
              _ -> []
            end
          end)
        else
          []
        end
      end)
      # Deduplicate, preferring developer roles and tracking earliest dev release
      |> Enum.group_by(fn {vn, prod, _role, _date} -> {vn, prod} end)
      |> Enum.map(fn {{vn, prod}, entries} ->
        roles = entries |> Enum.map(fn {_, _, role, _} -> role end) |> Enum.uniq()

        role =
          cond do
            "developer_publisher" in roles -> "developer_publisher"
            "developer" in roles and "publisher" in roles -> "developer_publisher"
            "developer" in roles -> "developer"
            true -> "publisher"
          end

        earliest =
          entries
          |> Enum.map(fn {_, _, _, date} -> date end)
          |> Enum.reject(&is_nil/1)
          |> Enum.min(Date, fn -> nil end)

        {vn, prod, role, earliest}
      end)

    new_count =
      Enum.count(vn_producer_entries, fn {vn, prod, _role, _date} ->
        not MapSet.member?(existing_vn_producers, {vn, prod})
      end)

    insert_rows =
      Enum.map(vn_producer_entries, fn {vn_uuid, prod_uuid, role, earliest} ->
        %{
          visual_novel_id: vn_uuid,
          producer_id: prod_uuid,
          role: role,
          earliest_release_date: earliest,
          inserted_at: now,
          updated_at: now
        }
      end)

    total =
      DumpSync.chunked_insert(VNProducer, insert_rows,
        on_conflict: {:replace, [:role, :earliest_release_date, :updated_at]},
        conflict_target: [:visual_novel_id, :producer_id]
      )

    {total, new_count}
  end

  # ── Data Loading from VNDB Dump ─────────────────────────────────────────────

  defp load_engines(vndb) do
    {:ok, result} = Postgrex.query(vndb, "SELECT id, name FROM engines", [])
    Map.new(result.rows, fn [id, name] -> {id, name} end)
  end

  defp load_producer_names(vndb) do
    {:ok, result} = Postgrex.query(vndb, "SELECT id, name, latin FROM producers", [])
    Map.new(result.rows, fn [id, name, latin] -> {id, %{name: latin || name}} end)
  end

  defp load_release_vn_map(vndb, our_vndb_ids) do
    our_vndb_ids
    |> Enum.chunk_every(5000)
    |> Enum.reduce(%{}, fn chunk, acc ->
      placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

      {:ok, result} =
        Postgrex.query(
          vndb,
          "SELECT id, vid, rtype::text FROM releases_vn WHERE vid IN (#{placeholders})",
          chunk
        )

      Enum.reduce(result.rows, acc, fn [rid, vid, rtype], inner ->
        Map.update(inner, rid, [{vid, rtype}], &[{vid, rtype} | &1])
      end)
    end)
  end

  defp load_releases(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        "SELECT id, olang::text, released, voiced, minage, has_ero, patch, freeware, uncensored, official, engine, notes, reso_x, reso_y FROM releases WHERE id IN (#{placeholders})",
        release_ids
      )

    Enum.map(result.rows, fn [
                               id,
                               olang,
                               released,
                               voiced,
                               minage,
                               has_ero,
                               patch,
                               freeware,
                               uncensored,
                               official,
                               engine,
                               notes,
                               reso_x,
                               reso_y
                             ] ->
      %{
        id: id,
        olang: olang,
        released: released,
        voiced: voiced,
        minage: minage,
        has_ero: has_ero,
        patch: patch,
        freeware: freeware,
        uncensored: uncensored,
        official: official,
        engine: engine,
        notes: notes,
        reso_x: reso_x,
        reso_y: reso_y
      }
    end)
  end

  defp load_titles(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        "SELECT id, lang::text, mtl, title, latin FROM releases_titles WHERE id IN (#{placeholders})",
        release_ids
      )

    result.rows
    |> Enum.map(fn [id, lang, mtl, title, latin] ->
      {id, %{lang: lang, mtl: mtl, title: title, latin: latin}}
    end)
    |> Enum.group_by(fn {id, _} -> id end, fn {_, t} -> t end)
  end

  defp load_platforms(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        "SELECT id, platform::text FROM releases_platforms WHERE id IN (#{placeholders})",
        release_ids
      )

    result.rows
    |> Enum.group_by(fn [id, _] -> id end, fn [_, platform] -> platform end)
  end

  defp load_extlinks(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        """
        SELECT re.id, e.site::text, e.value
        FROM releases_extlinks re
        JOIN extlinks e ON e.id = re.link
        WHERE re.id IN (#{placeholders})
        """,
        release_ids
      )

    result.rows
    |> Enum.group_by(fn [id, _, _] -> id end, fn [_, site, value] -> {site, value} end)
  end

  defp load_media(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        "SELECT id, medium::text, qty FROM releases_media WHERE id IN (#{placeholders})",
        release_ids
      )

    result.rows
    |> Enum.map(fn [id, medium, qty] -> {id, %{medium: medium, qty: qty}} end)
    |> Enum.group_by(fn {id, _} -> id end, fn {_, m} -> m end)
  end

  defp load_release_producers(vndb, release_ids) do
    placeholders = Enum.map_join(1..length(release_ids), ", ", &"$#{&1}")

    {:ok, result} =
      Postgrex.query(
        vndb,
        "SELECT id, pid, developer, publisher FROM releases_producers WHERE id IN (#{placeholders})",
        release_ids
      )

    result.rows
    |> Enum.map(fn [id, pid, dev, pub] -> {id, %{pid: pid, developer: dev, publisher: pub}} end)
    |> Enum.group_by(fn {id, _} -> id end, fn {_, p} -> p end)
  end

  defp get_release_uuid_map(release_ids) do
    import Ecto.Query

    release_ids
    |> Enum.chunk_every(5000)
    |> Enum.reduce(%{}, fn chunk, acc ->
      from(r in Release,
        where: r.vndb_id in ^chunk,
        select: {r.vndb_id, r.visual_novel_id, r.id}
      )
      |> Kaguya.Repo.all()
      |> Enum.reduce(acc, fn {vndb_id, vn_uuid, uuid}, inner ->
        Map.put(inner, {vndb_id, vn_uuid}, uuid)
      end)
    end)
  end

  # ── Existing ID Loaders ───────────────────────────────────────────────────

  defp load_existing_release_pairs do
    import Ecto.Query

    from(r in Release, select: {r.vndb_id, r.visual_novel_id})
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end

  defp load_existing_vn_producer_pairs do
    import Ecto.Query

    from(vp in VNProducer, select: {vp.visual_novel_id, vp.producer_id})
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end

  # ── VN Title Loading ────────────────────────────────────────────────────────

  defp load_vn_title_variants(vndb, vn_mapping) do
    vndb_ids = Map.keys(vn_mapping)

    # Load all title variants from VNDB dump's vn_titles table
    vndb_id_to_titles =
      vndb_ids
      |> Enum.chunk_every(5000)
      |> Enum.reduce(%{}, fn chunk, acc ->
        placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

        {:ok, result} =
          Postgrex.query(
            vndb,
            "SELECT id, title, latin FROM vn_titles WHERE id IN (#{placeholders})",
            chunk
          )

        Enum.reduce(result.rows, acc, fn [id, title, latin], inner ->
          variants = [title, latin] |> Enum.reject(&is_nil/1)
          Map.update(inner, id, variants, &(variants ++ &1))
        end)
      end)

    # Map vndb_id → uuid and deduplicate title variants
    Map.new(vn_mapping, fn {vndb_id, uuid} ->
      variants = Map.get(vndb_id_to_titles, vndb_id, []) |> Enum.uniq()
      {uuid, variants}
    end)
  end

  # ── Superseded Release Filtering ────────────────────────────────────────────

  @doc false
  def load_superseded_release_ids(vndb) do
    DumpSync.query_vndb_raw!(vndb, "SELECT DISTINCT rid FROM releases_supersedes")
    |> Enum.map(fn [rid] -> rid end)
    |> MapSet.new()
  end

  defp filter_superseded(release_vn_map, superseded_ids) do
    {filtered, removed} =
      Enum.reduce(release_vn_map, {%{}, 0}, fn {release_id, vns}, {acc, count} ->
        if MapSet.member?(superseded_ids, release_id) do
          {acc, count + 1}
        else
          {Map.put(acc, release_id, vns), count}
        end
      end)

    {filtered, removed}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp resolve_title(titles, olang) do
    olang_title = Enum.find(titles, fn t -> t.lang == to_string(olang) end)
    primary = olang_title || List.first(titles) || %{title: "Unknown", latin: nil}

    title = primary.latin || primary.title || "Unknown"

    latin_title =
      if primary.latin && primary.title && primary.latin != primary.title,
        do: primary.title,
        else: nil

    {title, latin_title}
  end
end
