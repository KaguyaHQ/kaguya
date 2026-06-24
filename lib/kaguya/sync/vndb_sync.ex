defmodule Kaguya.Sync.VndbSync do
  @moduledoc """
  Weekly VNDB sync — discovers and imports new VNs.

  Composable steps:
    - `collect_next_vn_ids/1` — scan VNDB API, return vndb_ids after a cursor
    - `import_vns/1`          — fetch, insert, enrich, and index a batch of VNs
    - `run/0`                 — orchestrate: collect → chunk → import

  Progress is written to `priv/sync_progress.log` for monitoring.
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.{VndbApiClient, VndbFieldMapper, VndbEnrichment}
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle, BannedVndbId}
  alias Kaguya.Utils.SlugUtils

  @import_batch_size 50
  @progress_file "priv/sync_progress.log"

  # ── Orchestrator ──────────────────────────────────────────────────────────

  @doc """
  Full weekly sync: collect new VN IDs, then import in batches.
  Progress is written to `priv/sync_progress.log`.
  """
  def run do
    started_at = System.monotonic_time(:second)
    init_progress_file()
    log_progress("=== VNDB Sync started at #{DateTime.utc_now()} ===")

    log_progress("Phase 1: Collecting new VN IDs...")
    new_ids = collect_next_vn_ids()
    log_progress("Found #{length(new_ids)} new VNs to import")

    if new_ids == [] do
      log_progress("Nothing to import. Done.")
      :ok
    else
      log_progress("Phase 2: Importing in batches of #{@import_batch_size}...")
      stats = import_in_batches(new_ids)
      duration = System.monotonic_time(:second) - started_at

      log_progress(
        "=== Sync complete in #{duration}s — " <>
          "#{stats.vns} VNs, #{stats.chars} characters, #{stats.tags} tags ==="
      )

      :ok
    end
  end

  # ── Step 1: Collect ───────────────────────────────────────────────────────

  @doc """
  Scan VNDB API and return vndb_ids to import.

  Options:
    - `:from`        — start scanning from this vndb_id (e.g. "v50000").
                       Defaults to "v1" (beginning).
    - `:skip_local`  — when true, returns ALL vndb_ids from the API without
                       filtering against local DB. Useful for building a full
                       ID list. Default: false.

  ## Examples

      # Find new VNs not in our DB
      collect_next_vn_ids()

      # Get all vndb_ids after v60000 (regardless of local DB)
      collect_next_vn_ids(from: "v60000", skip_local: true)

      # Find new VNs starting from a known cursor
      collect_next_vn_ids(from: "v50000")
  """
  def collect_next_vn_ids(opts \\ []) do
    skip_local = Keyword.get(opts, :skip_local, false)
    from = Keyword.get(opts, :from)

    {local_ids, banned_ids} =
      if skip_local do
        {MapSet.new(), load_banned_ids()}
      else
        local = load_local_vndb_ids()
        banned = load_banned_ids()

        Logger.info(
          "[VndbSync] Loaded #{MapSet.size(local)} local VNs, #{MapSet.size(banned)} banned"
        )

        {local, banned}
      end

    stream_opts = if from, do: [from: from], else: []

    VndbApiClient.stream_all_vns(stream_opts)
    |> Enum.reduce([], fn
      {:error, reason}, acc ->
        Logger.error("[VndbSync] Scan stopped due to API error: #{inspect(reason)}")
        acc

      page, acc when is_list(page) ->
        ids =
          page
          |> Enum.map(& &1["id"])
          |> Enum.reject(fn id ->
            MapSet.member?(banned_ids, id) or
              (not skip_local and MapSet.member?(local_ids, id))
          end)

        acc ++ ids
    end)
  end

  # ── Step 2: Import ───────────────────────────────────────────────────────

  @doc """
  Import a batch of VNs by vndb_id.
  Fetches full data, inserts VN rows with proper slugs, enriches
  (tags/characters/relations/developers/releases), and indexes in Meilisearch.

  Returns `%{vns: count, chars: count, tags: count}`.
  """
  def import_vns([]), do: %{vns: 0, chars: 0, tags: 0}

  def import_vns(vndb_ids) when is_list(vndb_ids) do
    case VndbApiClient.get_vns_by_ids(vndb_ids) do
      {:ok, []} ->
        Logger.warning("[VndbSync] No VN data returned for #{length(vndb_ids)} IDs")
        %{vns: 0, chars: 0, tags: 0}

      {:ok, vn_data_list} ->
        # Capture which VNs already existed before insert so we only write
        # :create revisions for genuinely new rows.
        existing_before =
          vndb_ids
          |> Enum.chunk_every(500)
          |> Enum.flat_map(fn chunk ->
            import Ecto.Query

            from(v in VisualNovel, where: v.vndb_id in ^chunk, select: v.vndb_id)
            |> Repo.all()
          end)
          |> MapSet.new()

        vn_count = insert_vns(vn_data_list)
        vn_id_map = load_vn_id_map(vndb_ids)
        upsert_vn_titles_from_api(vn_data_list, vn_id_map)

        %{tags: tags_count, chars: chars_count} =
          VndbEnrichment.enrich_vns(vn_data_list, vn_id_map, vndb_ids)

        # Revisions: :create for newly-inserted VNs, :edit for existing ones
        # whose content just got refreshed from the API.
        write_weekly_sync_revisions(vn_id_map, existing_before)

        Kaguya.VisualNovels.BrowseSections.refresh()

        %{vns: vn_count, chars: chars_count, tags: tags_count}

      {:error, reason} ->
        Logger.error("[VndbSync] Failed to fetch VN data: #{inspect(reason)}")
        %{vns: 0, chars: 0, tags: 0}
    end
  end

  # ── VN Insertion ─────────────────────────────────────────────────────────

  @replace_fields [
    :title,
    :description,
    :development_status,
    :length_category,
    :length_minutes,
    :original_language,
    :release_date,
    :is_image_nsfw,
    :is_image_suggestive,
    :vndb_rating,
    :vndb_vote_count,
    :aliases,
    :temp_image_url,
    :updated_at
  ]

  # Writes a :create revision for each brand-new VN and an :edit revision
  # for each existing one that just got re-imported from VNDB. Callers must
  # capture the set of existing vndb_ids *before* insert_vns/1 so we can
  # distinguish new vs updated after the upsert.
  defp write_weekly_sync_revisions(vn_id_map, existing_before) do
    # existing_before is a MapSet of vndb_ids; for each vn in vn_id_map,
    # emit :create if not in existing_before, else :edit.
    entries =
      Enum.map(vn_id_map, fn {vndb_id, uuid} ->
        if MapSet.member?(existing_before, vndb_id) do
          %{
            entity_type: :visual_novel,
            entity_id: uuid,
            action: :edit,
            source: :vndb_sync,
            changed_fields: [],
            summary: "Refreshed from VNDB (weekly sync)"
          }
        else
          %{
            entity_type: :visual_novel,
            entity_id: uuid,
            action: :create,
            source: :vndb_sync,
            changed_fields: [],
            summary: "Imported from VNDB"
          }
        end
      end)

    case Kaguya.Revisions.bulk_create_system_changes(entries) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[VndbSync] Failed to write revisions: #{inspect(reason)}")
        :ok
    end
  end

  defp insert_vns(vn_data_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(vn_data_list, fn vn ->
        title =
          VndbFieldMapper.resolve_title(vn["titles"], vn["olang"]) || vn["title"] || "Untitled"

        {is_nsfw, is_suggestive} = VndbFieldMapper.image_flags_from_vn(vn)

        aliases = VndbFieldMapper.parse_latin_aliases(vn["aliases"])

        %{
          id: UUIDv7.generate(),
          vndb_id: vn["id"],
          title: title,
          aliases: aliases,
          description: VndbFieldMapper.clean_description(vn["description"]),
          development_status: VndbFieldMapper.map_development_status(vn["devstatus"]),
          length_minutes: vn["length_minutes"],
          length_category:
            VndbFieldMapper.map_length_category(vn["length"]) ||
              VndbFieldMapper.length_category_from_minutes(vn["length_minutes"]),
          original_language: vn["olang"],
          release_date: VndbFieldMapper.parse_api_release_date(vn["released"]),
          is_image_nsfw: is_nsfw,
          is_image_suggestive: is_suggestive,
          vndb_rating: VndbFieldMapper.convert_api_rating(vn["average"]),
          vndb_vote_count: vn["votecount"],
          temp_image_url: VndbFieldMapper.image_url_from_vn(vn),
          inserted_at: now,
          updated_at: now
        }
      end)

    year_fun = fn row ->
      case row[:release_date] do
        %Date{year: y} -> y
        _ -> nil
      end
    end

    slugged =
      SlugUtils.build_unique_slugs(rows, VisualNovel, :slug, & &1.title, year_fun: year_fun)
      |> Enum.map(fn row -> row |> Map.put(:slug, row._slug) |> Map.delete(:_slug) end)

    slugged
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} =
        Repo.insert_all(VisualNovel, chunk,
          on_conflict: {:replace, @replace_fields},
          conflict_target: [:vndb_id]
        )

      acc + count
    end)
  end

  defp upsert_vn_titles_from_api(vn_data_list, vn_id_map) do
    title_rows =
      Enum.flat_map(vn_data_list, fn vn ->
        vn_uuid = Map.get(vn_id_map, vn["id"])

        if vn_uuid do
          (vn["titles"] || [])
          |> Enum.map(fn t ->
            %{
              id: UUIDv7.generate(),
              visual_novel_id: vn_uuid,
              lang: t["lang"],
              official: t["official"] == true,
              title: t["title"] || "Unknown",
              latin: t["latin"]
            }
          end)
        else
          []
        end
      end)

    if title_rows != [] do
      title_rows
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(VNTitle, chunk,
          on_conflict: {:replace, [:official, :title, :latin]},
          conflict_target: [:visual_novel_id, :lang]
        )
      end)
    end
  end

  # ── Batch Helper ─────────────────────────────────────────────────────────

  defp import_in_batches(vndb_ids) do
    total_batches = ceil(length(vndb_ids) / @import_batch_size)

    vndb_ids
    |> Enum.chunk_every(@import_batch_size)
    |> Enum.with_index(1)
    |> Enum.reduce(%{vns: 0, chars: 0, tags: 0}, fn {batch, i}, acc ->
      log_progress(
        "Batch #{i}/#{total_batches}: importing #{length(batch)} VNs (#{List.first(batch)}..#{List.last(batch)})"
      )

      batch_stats = import_vns(batch)

      log_progress(
        "Batch #{i}/#{total_batches}: done — #{batch_stats.vns} VNs, #{batch_stats.chars} chars, #{batch_stats.tags} tags"
      )

      %{
        vns: acc.vns + batch_stats.vns,
        chars: acc.chars + batch_stats.chars,
        tags: acc.tags + batch_stats.tags
      }
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp load_local_vndb_ids do
    Repo.all(from v in VisualNovel, where: not is_nil(v.vndb_id), select: v.vndb_id)
    |> MapSet.new()
  end

  defp load_banned_ids do
    banned = Repo.all(from b in BannedVndbId, select: b.vndb_id)
    # Skip VNDB ids whose source VN was merged into a canonical — re-fetching
    # them would resurrect the deleted source row. Mirrors `DumpSync.load_banned_ids/0`.
    MapSet.new(banned ++ Kaguya.VisualNovels.Merge.merged_vndb_ids())
  end

  defp load_vn_id_map(vndb_ids) do
    Repo.all(from v in VisualNovel, where: v.vndb_id in ^vndb_ids, select: {v.vndb_id, v.id})
    |> Map.new()
  end

  # ── Progress File ────────────────────────────────────────────────────────

  defp init_progress_file do
    File.write!(@progress_file, "")
  end

  defp log_progress(message) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()
    line = "[#{timestamp}] #{message}\n"
    File.write!(@progress_file, line, [:append])
    Logger.info("[VndbSync] #{message}")
  end
end
