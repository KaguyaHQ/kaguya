defmodule Kaguya.Sync.DumpSync.Images.CoverProcessing do
  @moduledoc """
  Processes VN cover images into WebP variants and uploads to R2.

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
  Process pending VN covers.

  Returns `{count, details}` where `details` is a list of
  `%{id: image_id, vndb_id: vndb_vn_id, cv_id: cv_id}` maps for reporting.
  """
  def run(cover_selections, vn_mapping, base_dir, dry_run) do
    pending = build_pending(cover_selections, vn_mapping)
    # Build a reverse mapping for report details
    uuid_to_vndb = Map.new(vn_mapping, fn {vndb_id, uuid} -> {uuid, vndb_id} end)

    Logger.info("CoverProcessing: #{length(pending)} covers to process")

    if dry_run or pending == [] do
      {length(pending), []}
    else
      do_process(pending, base_dir, uuid_to_vndb)
    end
  end

  defp build_pending(cover_selections, vn_mapping) do
    cover_selections
    |> Enum.flat_map(fn {vndb_id, %{cv_id: cv_id} = selection} ->
      case Map.get(vn_mapping, vndb_id) do
        nil -> []
        vn_uuid -> [{vn_uuid, cv_id, selection}]
      end
    end)
    |> then(fn triples ->
      vn_uuids = Enum.map(triples, &elem(&1, 0))

      still_pending =
        from(vn in Kaguya.VisualNovels.VisualNovel,
          where: vn.id in ^vn_uuids and is_nil(vn.primary_image_id),
          select: vn.id
        )
        |> Repo.all()
        |> MapSet.new()

      Enum.filter(triples, fn {vn_uuid, _, _} -> MapSet.member?(still_pending, vn_uuid) end)
    end)
  end

  defp do_process(pending, base_dir, uuid_to_vndb) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    # Phase A: decode + upload (CPU + R2, parallelized)
    rows =
      pending
      |> Enum.group_by(fn {_vn_uuid, cv_id, _sel} -> cv_id end)
      |> Task.async_stream(
        fn {cv_id, triples} ->
          process_cover_group(cv_id, triples, base_dir, bucket, now)
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

    details = resolve_persisted_details(rows, uuid_to_vndb)

    # Bulk set primary_image_id + VN-level NSFW flags
    updated_vn_ids = bulk_set_primary_image(details, now)

    # Write one :edit revision per VN whose primary cover was set so the
    # new cover + metadata shows up in the VN's edit history.
    write_cover_revisions(updated_vn_ids)

    Logger.info("CoverProcessing: uploaded #{length(rows)}, inserted #{count} covers")
    {count, details}
  end

  defp write_cover_revisions([]), do: :ok

  defp write_cover_revisions(vn_ids) do
    entries =
      Enum.map(vn_ids, fn vn_id ->
        %{
          entity_type: :visual_novel,
          entity_id: vn_id,
          action: :edit,
          source: :vndb_sync,
          changed_fields: ["cover", "covers_metadata"],
          summary: "Cover set during VNDB image sync"
        }
      end)

    case Kaguya.Revisions.bulk_create_system_changes(entries) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("CoverProcessing: failed to write cover revisions: #{inspect(reason)}")
        :ok
    end
  end

  # Decode once per cv_id, upload per VN so each image_id has R2 files.
  defp process_cover_group(cv_id, triples, base_dir, bucket, now) do
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

            Enum.map(triples, fn {vn_uuid, _, selection} ->
              image_id = ImageProcessing.image_id("#{cv_id}:#{vn_uuid}")
              ImageProcessing.upload_variants(variants, bucket, "visual_novels/#{image_id}-")

              {is_nsfw, is_suggestive} =
                compute_image_flags(selection.c_sexual_avg, selection.c_votecount)

              %{
                row: %{
                  id: image_id,
                  visual_novel_id: vn_uuid,
                  vndb_cv_id: cv_id,
                  width: width,
                  height: height,
                  vndb_votes: Map.get(selection, :vndb_votes, 0),
                  language: Map.get(selection, :language),
                  release_date: Map.get(selection, :release_date),
                  is_image_nsfw: is_nsfw,
                  is_image_suggestive: is_suggestive,
                  likes_count: 0,
                  inserted_at: now,
                  updated_at: now
                },
                cv_id: cv_id
              }
            end)

          {:error, reason} ->
            Logger.warning("CoverProcessing: failed for #{cv_id}: #{inspect(reason)}")
            []
        end

      {:error, _} ->
        []
    end
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

  # Returns the list of VN UUIDs whose primary_image_id was actually set by
  # this pass (i.e. the WHERE clause matched). Used to scope revision writes
  # to VNs that really changed — a rerun won't produce duplicate revisions.
  defp bulk_set_primary_image(details, now) do
    details
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      values =
        Enum.map_join(chunk, ", ", fn d ->
          "('#{d.vn_uuid}'::uuid, '#{d.id}'::uuid, #{d.is_image_nsfw}, #{d.is_image_suggestive})"
        end)

      %{rows: rows} =
        Repo.query!(
          """
            UPDATE visual_novels vn
            SET primary_image_id = v.image_id,
                is_image_nsfw = v.is_nsfw,
                is_image_suggestive = v.is_suggestive,
                updated_at = $1
            FROM (VALUES #{values}) AS v(vn_id, image_id, is_nsfw, is_suggestive)
            WHERE vn.id = v.vn_id AND vn.primary_image_id IS NULL
            RETURNING vn.id
          """,
          [now]
        )

      Enum.map(rows, fn [id] -> id end)
    end)
  end

  # On reruns, `on_conflict: :nothing` can skip inserts because the
  # `(visual_novel_id, vndb_cv_id)` pair already exists under an older UUID.
  # Always resolve the persisted `vn_images.id` before wiring it into the
  # parent FK so we never point at an in-memory UUID that wasn't inserted.
  defp resolve_persisted_details(rows, uuid_to_vndb) do
    pairs = Enum.map(rows, fn %{row: row} -> {row.visual_novel_id, row.vndb_cv_id} end)
    vn_ids = Enum.map(pairs, &elem(&1, 0)) |> Enum.uniq()
    cv_ids = Enum.map(pairs, &elem(&1, 1)) |> Enum.uniq()

    ids_by_pair =
      from(img in Image,
        where: img.visual_novel_id in ^vn_ids and img.vndb_cv_id in ^cv_ids,
        select: {{img.visual_novel_id, img.vndb_cv_id}, img.id}
      )
      |> Repo.all()
      |> Map.new()

    pending_vn_ids =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: is_nil(vn.primary_image_id),
        where: vn.id in ^vn_ids,
        select: vn.id
      )
      |> Repo.all()
      |> MapSet.new()

    rows
    |> Enum.flat_map(fn %{row: row, cv_id: cv_id} ->
      case Map.get(ids_by_pair, {row.visual_novel_id, row.vndb_cv_id}) do
        nil ->
          []

        persisted_id ->
          if MapSet.member?(pending_vn_ids, row.visual_novel_id) do
            vndb_id = Map.get(uuid_to_vndb, row.visual_novel_id, "?")

            [
              %{
                id: persisted_id,
                vndb_id: vndb_id,
                cv_id: cv_id,
                vn_uuid: row.visual_novel_id,
                is_image_nsfw: row.is_image_nsfw,
                is_image_suggestive: row.is_image_suggestive
              }
            ]
          else
            []
          end
      end
    end)
  end
end
