defmodule Kaguya.Sync.DumpSync.Images.CharacterProcessing do
  @moduledoc """
  Processes character images into WebP variants and uploads to R2.

  1 variant: 240w at quality 80.
  R2 key: `characters/{uuid}-240w.webp`
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Images.{ImagePath, ImageProcessing}
  alias Kaguya.Characters.CharacterImage

  @variants [%{suffix: "240w", width: 240}]

  @quality 80
  @concurrency 50

  @doc """
  Process pending character images.

  Returns `{count, details}` where `details` is a list of
  `%{id: image_id, vndb_id: char_vndb_id, ch_id: vndb_image_id}` maps for reporting.
  """
  def run(base_dir, dry_run) do
    pending =
      from(c in Kaguya.Characters.Character,
        where: not is_nil(c.vndb_image_id) and is_nil(c.primary_image_id),
        select: {c.id, c.vndb_id, c.vndb_image_id, c.is_image_nsfw, c.is_image_suggestive}
      )
      |> Repo.all()

    Logger.info("CharacterProcessing: #{length(pending)} images to process")

    if dry_run or pending == [] do
      {length(pending), []}
    else
      do_process(pending, base_dir)
    end
  end

  defp do_process(pending, base_dir) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    # Pre-load existing character_ids to avoid per-item DB check
    existing_char_ids =
      from(ci in CharacterImage, select: ci.character_id)
      |> Repo.all()
      |> MapSet.new()

    # Phase A: decode + upload (CPU + R2, parallelized)
    rows =
      pending
      |> Enum.reject(fn {char_uuid, _, _, _, _} ->
        MapSet.member?(existing_char_ids, char_uuid)
      end)
      |> Task.async_stream(
        fn {char_uuid, vndb_id, vndb_image_id, is_nsfw, is_suggestive} ->
          process_and_upload(
            char_uuid,
            vndb_id,
            vndb_image_id,
            is_nsfw,
            is_suggestive,
            base_dir,
            bucket,
            now
          )
        end,
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
      DumpSync.chunked_insert(CharacterImage, Enum.map(rows, & &1.row),
        on_conflict: :nothing,
        conflict_target: [:id]
      )

    details = Enum.map(rows, & &1.detail)

    # Bulk set primary_image_id
    bulk_set_primary_image(details, now)

    Logger.info("CharacterProcessing: uploaded #{length(rows)}, inserted #{count} images")
    {count, details}
  end

  defp process_and_upload(
         char_uuid,
         vndb_id,
         vndb_image_id,
         is_nsfw,
         is_suggestive,
         base_dir,
         bucket,
         _now
       ) do
    file_path = ImagePath.absolute_path(base_dir, vndb_image_id)

    case File.read(file_path) do
      {:ok, binary} ->
        case ImageProcessing.generate_variants(binary, @variants, @quality) do
          {:ok, [variant]} ->
            image_id = ImageProcessing.image_id(vndb_image_id)
            ImageProcessing.upload_variants([variant], bucket, "characters/#{image_id}-")

            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {:ok,
             %{
               row: %{
                 id: image_id,
                 character_id: char_uuid,
                 width: variant.width,
                 height: variant.height,
                 is_image_nsfw: is_nsfw || false,
                 is_image_suggestive: is_suggestive || false,
                 inserted_at: now,
                 updated_at: now
               },
               detail: %{
                 id: image_id,
                 vndb_id: vndb_id,
                 ch_id: vndb_image_id,
                 char_uuid: char_uuid
               }
             }}

          {:ok, _} ->
            :skip

          {:error, reason} ->
            Logger.warning("CharacterProcessing: failed for #{vndb_image_id}: #{inspect(reason)}")
            :skip
        end

      {:error, _} ->
        :skip
    end
  end

  defp bulk_set_primary_image(details, now) do
    details
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      values =
        Enum.map_join(chunk, ", ", fn %{char_uuid: char_uuid, id: image_id} ->
          "('#{char_uuid}'::uuid, '#{image_id}'::uuid)"
        end)

      Repo.query!(
        """
          UPDATE characters c
          SET primary_image_id = v.image_id, updated_at = $1
          FROM (VALUES #{values}) AS v(char_id, image_id)
          WHERE c.id = v.char_id AND c.primary_image_id IS NULL
        """,
        [now]
      )
    end)
  end
end
