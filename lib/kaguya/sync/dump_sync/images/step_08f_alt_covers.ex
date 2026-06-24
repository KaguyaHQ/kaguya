defmodule Kaguya.Sync.DumpSync.Images.AltCoverProcessing do
  @moduledoc """
  Selects, processes, uploads, and inserts alternative VN cover images.

  Queries the VNDB dump for all `pkgfront`/`dig` release covers with at least
  one preference vote, filters out already-imported cv_ids, then generates
  WebP variants and uploads to R2.

  4 variants: 128w, 256w, 512w, 1024w at quality 75.
  R2 key: `visual_novels/{uuid}-{suffix}.webp`
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Images.{ImagePath, ImageProcessing}
  alias Kaguya.VisualNovels.Image

  @variants [
    %{suffix: "128w", width: 128},
    %{suffix: "256w", width: 256},
    %{suffix: "512w", width: 512},
    %{suffix: "1024w", width: 1024}
  ]

  @quality 75
  @concurrency 50

  @doc """
  Identify pending alt covers from the VNDB dump.

  Returns `{pending_items, pending_cv_ids}` where:
  - `pending_items` is the list of items to process
  - `pending_cv_ids` is the unique cv_id strings for downloading
  """
  def identify_pending(vndb, vn_mapping) do
    vndb_covers = load_vndb_alt_covers(vndb, Map.keys(vn_mapping))

    existing_pairs = load_existing_pairs()

    pending =
      Enum.reject(vndb_covers, fn item ->
        MapSet.member?(existing_pairs, {item.vndb_id, item.cv_id})
      end)

    pending_cv_ids = pending |> Enum.map(& &1.cv_id) |> Enum.uniq()

    Logger.info(
      "AltCoverProcessing: #{length(vndb_covers)} from dump, " <>
        "#{MapSet.size(existing_pairs)} already exist, #{length(pending)} to process"
    )

    {pending, pending_cv_ids}
  end

  @doc """
  Process and insert alt covers: resize to WebP, upload to R2, insert DB records.

  Returns `{count, details}` where `details` is a list of
  `%{id: image_id, vndb_id: vndb_vn_id, cv_id: cv_id}` maps for reporting.
  """
  def run(pending, vn_mapping, base_dir, dry_run) do
    if dry_run or pending == [] do
      {length(pending), []}
    else
      do_process(pending, vn_mapping, base_dir)
    end
  end

  # ── VNDB Queries ──────────────────────────────────────────────────────────

  defp load_vndb_alt_covers(vndb, vndb_ids) do
    vndb_ids
    |> Enum.chunk_every(5000)
    |> Enum.flat_map(fn chunk ->
      placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

      DumpSync.query_vndb_raw!(
        vndb,
        """
          SELECT rv.vid AS vndb_id, ri.img AS cv_id, i.width, i.height,
                 i.c_sexual_avg, i.c_votecount,
                 COUNT(DISTINCT iv.uid) AS vndb_votes,
                 COALESCE(
                   MIN(CASE WHEN array_length(ri.lang, 1) = 1 THEN ri.lang[1]::text END),
                   MIN(r.olang::text)
                 ) AS language,
                 MIN(r.released) AS min_released
          FROM releases_vn rv
          JOIN releases_images ri ON ri.id = rv.id
          JOIN releases r ON r.id = ri.id
          JOIN images i ON i.id = ri.img
          JOIN vn_image_votes iv ON iv.vid = rv.vid AND iv.img = ri.img
          WHERE rv.vid IN (#{placeholders})
            AND ri.itype IN ('pkgfront', 'dig')
          GROUP BY rv.vid, ri.img, i.width, i.height, i.c_sexual_avg, i.c_votecount
        """,
        chunk
      )
    end)
    |> Enum.map(fn [
                     vndb_id,
                     cv_id,
                     width,
                     height,
                     c_sexual_avg,
                     c_votecount,
                     vndb_votes,
                     language,
                     min_released
                   ] ->
      %{
        vndb_id: vndb_id,
        cv_id: cv_id,
        width: width,
        height: height,
        c_sexual_avg: c_sexual_avg,
        c_votecount: c_votecount,
        vndb_votes: vndb_votes,
        language: language,
        release_date: DumpSync.parse_vndb_date(min_released)
      }
    end)
  end

  defp load_existing_pairs do
    from(vi in Image,
      join: vn in assoc(vi, :visual_novel),
      where: not is_nil(vi.vndb_cv_id) and not is_nil(vn.vndb_id),
      select: {vn.vndb_id, vi.vndb_cv_id}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # ── Processing ────────────────────────────────────────────────────────────

  defp do_process(pending, vn_mapping, base_dir) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    # Phase A: decode + upload (CPU + R2, parallelized)
    # Returns row maps ready for bulk insert
    rows =
      pending
      |> Enum.group_by(& &1.cv_id)
      |> Task.async_stream(
        fn {cv_id, items} ->
          process_cover_group(cv_id, items, vn_mapping, base_dir, bucket, now)
        end,
        max_concurrency: @concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, results} when is_list(results) -> results
        _ -> []
      end)

    # Phase B: bulk insert (single DB round-trip per chunk)
    count =
      DumpSync.chunked_insert(Image, Enum.map(rows, & &1.row),
        on_conflict: :nothing,
        conflict_target: [:visual_novel_id, :vndb_cv_id]
      )

    details = Enum.map(rows, & &1.detail)

    Logger.info("AltCoverProcessing: uploaded #{length(rows)}, inserted #{count} alt covers")
    {count, details}
  end

  defp process_cover_group(cv_id, items, vn_mapping, base_dir, bucket, now) do
    file_path = ImagePath.absolute_path(base_dir, cv_id)

    case File.read(file_path) do
      {:ok, binary} ->
        case ImageProcessing.generate_variants(binary, @variants, @quality) do
          {:ok, variants} ->
            {width, height} =
              case List.last(variants) do
                nil -> {0, 0}
                v -> {v.width, v.height}
              end

            Enum.flat_map(items, fn item ->
              vn_uuid = Map.get(vn_mapping, item.vndb_id)
              upload_and_build_row(item, vn_uuid, cv_id, width, height, variants, bucket, now)
            end)

          {:error, reason} ->
            Logger.warning("AltCoverProcessing: failed for #{cv_id}: #{inspect(reason)}")
            []
        end

      {:error, _} ->
        []
    end
  end

  defp upload_and_build_row(_item, nil, _cv_id, _w, _h, _variants, _bucket, _now), do: []

  defp upload_and_build_row(item, vn_uuid, cv_id, width, height, variants, bucket, now) do
    image_id = ImageProcessing.image_id("#{cv_id}:#{vn_uuid}")
    ImageProcessing.upload_variants(variants, bucket, "visual_novels/#{image_id}-")

    {is_nsfw, is_suggestive} = compute_image_flags(item.c_sexual_avg, item.c_votecount)

    [
      %{
        row: %{
          id: image_id,
          visual_novel_id: vn_uuid,
          vndb_cv_id: cv_id,
          width: width,
          height: height,
          vndb_votes: item.vndb_votes,
          language: item.language,
          release_date: item.release_date,
          is_image_nsfw: is_nsfw,
          is_image_suggestive: is_suggestive,
          likes_count: 0,
          inserted_at: now,
          updated_at: now
        },
        detail: %{id: image_id, vndb_id: item.vndb_id, cv_id: cv_id}
      }
    ]
  end

  # Same thresholds as VndbFieldMapper.compute_image_flags/2
  # VNDB dump c_sexual_avg is 0-200 (avg * 100), so 130 = API 1.3, 50 = API 0.5
  defp compute_image_flags(nil, _), do: {false, false}
  defp compute_image_flags(_, nil), do: {false, false}

  defp compute_image_flags(c_sexual_avg, c_votecount) do
    if c_votecount >= 3 do
      is_nsfw = c_sexual_avg > 130
      is_suggestive = c_sexual_avg > 50 and not is_nsfw
      {is_nsfw, is_suggestive}
    else
      {false, false}
    end
  end
end
