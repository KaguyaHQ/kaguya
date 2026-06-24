defmodule Kaguya.Sync.DumpSync.Images.ScreenshotProcessing do
  @moduledoc """
  Processes VN screenshots into WebP variants, uploads to R2, and inserts DB records.

  Queries the VNDB dump directly for screenshots, filters out:
  - Screenshots already in kaguya's `vn_screenshots` table
  - Screenshots listed in `banned_sf_ids` (hard block — e.g. WD14 moderation hits)

  Classifies each remaining screenshot using VNDB's own verdict formula
  (`lib/VNWeb/Images/Lib.pm:45-47`, `minvotes=1`):
  - `is_nsfw  = c_votecount < 1 OR c_sexual_avg   > 40` (not-Safe: Suggestive/Explicit)
  - `is_brutal = c_votecount < 1 OR c_violence_avg > 40` (not-Tame: Violent/Brutal)

  3 variants: 320w, 640w, 1280w at quality 75.
  R2 key: `visual_novels/screenshots/{uuid}-{suffix}.webp`
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Images.{ImagePath, ImageProcessing}
  alias Kaguya.Screenshots.{Screenshot, BannedSfId}

  @variants [
    %{suffix: "320w", width: 320},
    %{suffix: "640w", width: 640},
    %{suffix: "1280w", width: 1280}
  ]

  @quality 75
  @concurrency 50

  @doc """
  Identify pending screenshots from the VNDB dump.

  Returns `{unique_items, pending_sf_ids}` where:
  - `unique_items` is the deduplicated list for processing
  - `pending_sf_ids` is the list of sf_id strings to download
  """
  def identify_pending(vndb, vn_mapping) do
    vndb_screenshots = load_vndb_screenshots(vndb, Map.keys(vn_mapping))

    existing_sf_ids = load_existing_sf_ids()
    banned_sf_ids = load_banned_sf_ids()

    pending =
      Enum.reject(vndb_screenshots, fn s ->
        MapSet.member?(existing_sf_ids, s.sf_id) or
          MapSet.member?(banned_sf_ids, s.sf_id)
      end)

    unique = deduplicate_by_sf_id(pending)

    Logger.info(
      "ScreenshotProcessing: #{length(vndb_screenshots)} from dump, " <>
        "#{MapSet.size(existing_sf_ids)} already exist, " <>
        "#{MapSet.size(banned_sf_ids)} banned, #{length(unique)} to process"
    )

    pending_sf_ids = Enum.map(unique, & &1.sf_id)
    {unique, pending_sf_ids}
  end

  @doc """
  Process and insert screenshots: resize to WebP, upload to R2, insert DB records.

  Returns `{count, details}` where `details` is a list of
  `%{id: image_id, sf_id: sf_id, vndb_id: vndb_vn_id}` maps for reporting.
  """
  def run(unique, vn_mapping, base_dir, dry_run) do
    if dry_run or unique == [] do
      {length(unique), []}
    else
      do_process(unique, vn_mapping, base_dir)
    end
  end

  # ── VNDB Queries ──────────────────────────────────────────────────────────

  defp load_vndb_screenshots(vndb, vndb_ids) do
    vndb_ids
    |> Enum.chunk_every(5000)
    |> Enum.flat_map(fn chunk ->
      placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

      DumpSync.query_vndb_raw!(
        vndb,
        """
          SELECT vs.id AS vn_vndb_id, vs.scr AS sf_id, i.width, i.height,
                 i.c_votecount, i.c_sexual_avg, i.c_violence_avg
          FROM vn_screenshots vs
          JOIN images i ON i.id = vs.scr
          WHERE vs.id IN (#{placeholders})
        """,
        chunk
      )
    end)
    |> Enum.map(fn [vn_vndb_id, sf_id, width, height, votecount, sexual_avg, violence_avg] ->
      %{
        vndb_id: vn_vndb_id,
        sf_id: sf_id,
        width: width,
        height: height,
        is_nsfw: nsfw?(votecount, sexual_avg),
        is_brutal: brutal?(votecount, violence_avg)
      }
    end)
  end

  # VNDB verdict formula (Lib.pm:45-47, minvotes=1): unrated → worst-case.
  # c_sexual_avg / c_violence_avg are 0-200 scale; >40 = "not Safe/Tame".
  defp nsfw?(votecount, sexual_avg),
    do: (votecount || 0) < 1 or (sexual_avg || 0) > 40

  defp brutal?(votecount, violence_avg),
    do: (votecount || 0) < 1 or (violence_avg || 0) > 40

  defp load_existing_sf_ids do
    from(s in Screenshot,
      where: not is_nil(s.vndb_sf_id),
      select: s.vndb_sf_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_banned_sf_ids do
    from(b in BannedSfId, select: b.vndb_sf_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp deduplicate_by_sf_id(rows) do
    rows
    |> Enum.group_by(& &1.sf_id)
    |> Enum.map(fn {_sf_id, group} ->
      first = hd(group)
      vndb_ids = group |> Enum.map(& &1.vndb_id) |> Enum.uniq()
      Map.put(first, :vndb_ids, vndb_ids)
    end)
  end

  # ── Processing ────────────────────────────────────────────────────────────

  defp do_process(unique, vn_mapping, base_dir) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    # Phase A: decode + upload (CPU + R2, parallelized)
    rows =
      unique
      |> Task.async_stream(
        fn item -> process_single(item, vn_mapping, base_dir, bucket, now) end,
        max_concurrency: @concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, entry}} -> [entry]
        _ -> []
      end)

    # Phase B: bulk insert (single DB round-trip per chunk)
    count =
      DumpSync.chunked_insert(Screenshot, Enum.map(rows, & &1.row),
        on_conflict: :nothing,
        conflict_target: [:vndb_sf_id]
      )

    details = Enum.map(rows, & &1.detail)

    Logger.info("ScreenshotProcessing: uploaded #{length(rows)}, inserted #{count} screenshots")
    {count, details}
  end

  defp process_single(item, vn_mapping, base_dir, bucket, now) do
    file_path = ImagePath.absolute_path(base_dir, item.sf_id)
    vndb_vn_id = hd(item.vndb_ids)
    vn_uuid = Map.get(vn_mapping, vndb_vn_id)

    if is_nil(vn_uuid) do
      :skip
    else
      process_and_upload(item, vndb_vn_id, vn_uuid, file_path, bucket, now)
    end
  end

  defp process_and_upload(item, vndb_vn_id, vn_uuid, file_path, bucket, now) do
    case File.read(file_path) do
      {:ok, binary} ->
        case ImageProcessing.generate_variants(binary, @variants, @quality) do
          {:ok, variants} ->
            image_id = ImageProcessing.image_id(item.sf_id)

            ImageProcessing.upload_variants(
              variants,
              bucket,
              "visual_novels/screenshots/#{image_id}-"
            )

            {:ok,
             %{
               row: %{
                 id: image_id,
                 visual_novel_id: vn_uuid,
                 vndb_sf_id: item.sf_id,
                 width: item.width,
                 height: item.height,
                 is_nsfw: item.is_nsfw,
                 is_brutal: item.is_brutal,
                 inserted_at: now,
                 updated_at: now
               },
               detail: %{id: image_id, sf_id: item.sf_id, vndb_id: vndb_vn_id}
             }}

          {:error, reason} ->
            Logger.warning("ScreenshotProcessing: failed for #{item.sf_id}: #{inspect(reason)}")
            :skip
        end

      {:error, _} ->
        :skip
    end
  end
end
