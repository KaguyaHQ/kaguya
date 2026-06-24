defmodule Kaguya.Uploads do
  @moduledoc """
  Provides functions for managing file uploads, including generating presigned URLs and processing uploaded files.
  """

  alias Kaguya.ImageProcessor
  require Logger

  # Hard cap for VNDB XML exports. Real-world exports observed in our backfill
  # cache top out around 825 KB; 1.5 MB leaves ~2x headroom for the largest
  # legitimate user while keeping XML-bomb blast radius small. Enforced
  # server-side in VndbProcessor before parsing, plus a matching client-side
  # hint in the dropzone for fast feedback.
  #
  # NOTE: We do not enforce this at the S3/R2 layer because Cloudflare R2 does
  # not implement the S3 "POST Object" operation (returns 501), so a presigned
  # POST policy with `content-length-range` is not an option here. The temp
  # bucket has a 1-day lifecycle rule that auto-deletes oversized junk if a
  # malicious client ever PUTs one and then walks away.
  @max_vndb_xml_bytes 1_500_000

  @doc """
  Returns the maximum allowed size (in bytes) for an uploaded VNDB XML export.
  """
  def max_vndb_xml_bytes, do: @max_vndb_xml_bytes

  @doc """
  Generates a presigned URL for uploading files to a temporary location.
  """
  def generate_upload_url do
    upload_id = UUIDv7.generate()
    generate_temporary_url(upload_id)
  end

  @doc """
  Uploads a local file to the temporary uploads bucket and returns the staged upload ID.
  """
  def stage_local_file(path) when is_binary(path) do
    with {:ok, %{upload_url: url, upload_id: upload_id}} <- generate_upload_url(),
         {:ok, body} <- File.read(path),
         {:ok, %Req.Response{status: status}} when status in 200..299 <-
           Req.put(url, Keyword.merge([body: body], upload_req_options())) do
      {:ok, upload_id}
    else
      {:ok, %Req.Response{status: status}} ->
        {:error, "Upload failed with status #{status}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, inspect(reason)}

      other ->
        {:error, inspect(other)}
    end
  end

  @doc """
  Generate multiple presigned URLs in one call.
  """
  def generate_upload_urls(count) when is_integer(count) and count > 0 do
    urls =
      1..count
      |> Enum.map(fn _ ->
        upload_id = UUIDv7.generate()

        case generate_temporary_url(upload_id) do
          {:ok, %{upload_url: url, upload_id: id}} -> %{upload_url: url, upload_id: id}
          {:error, reason} -> %{error: inspect(reason)}
        end
      end)

    {:ok, urls}
  end

  @doc """
  Processes image uploads (avatar, banner, list cover, etc.).

  Avatar and banner are enqueued onto the ImageVariantWorker, which
  generates variants in the background and then performs the atomic swap
  on the user row once variants are confirmed on S3. The mutation
  returns immediately (~50ms) instead of blocking on libvips and S3
  PUTs (~1-2s). Frontend behavior is unchanged: the existing edit-
  profile flow already fires this without awaiting and expects the
  user to refresh manually after the swap completes.

  The :vn_cover, :vn_screenshot, and :character clauses below are dead
  paths after Phase 2 — the canonical entry points are now
  Covers.upload_cover, Screenshots.upload_screenshot, and
  CharacterImages.upload_image, which enqueue the worker themselves.
  Kept here for backwards compatibility with any straggling callers
  during the rollout; removed in Phase 4 cleanup.
  """
  def process_image_upload(upload_id, image_type, user_id) do
    case image_type do
      :avatar ->
        %{type: "avatar", user_id: user_id, id: upload_id}
        |> Kaguya.Uploads.ImageVariantWorker.new()
        |> Oban.insert!()

        {:ok, true}

      :banner ->
        %{type: "banner", user_id: user_id, id: upload_id}
        |> Kaguya.Uploads.ImageVariantWorker.new()
        |> Oban.insert!()

        {:ok, true}

      :vn_cover ->
        ImageProcessor.process_cover_upload(upload_id)

      :vn_screenshot ->
        ImageProcessor.process_screenshot_upload(upload_id)

      :character ->
        ImageProcessor.process_character_image_upload(upload_id)
    end
  end

  @doc """
  Processes a staged avatar/banner upload synchronously.

  Edit-profile uses this during the explicit "Save changes" commit. The same
  processor backs the Oban worker, so variant generation, atomic user-row swap,
  and temp cleanup stay identical to the background path.
  """
  def process_profile_image_upload(upload_id, image_type, user_id)
      when image_type in [:avatar, :banner] do
    args = %{"type" => Atom.to_string(image_type), "user_id" => user_id, "id" => upload_id}

    case Kaguya.Uploads.ImageVariantProcessor.process(args) do
      :ok -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_temporary_url(upload_id) do
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)
    key = "users/temp/#{upload_id}"
    config = ExAws.Config.new(:s3)

    ExAws.S3.presigned_url(config, :put, bucket, key, expires_in: 300)
    |> case do
      {:ok, url} ->
        {:ok, %{upload_url: url, upload_id: upload_id}}

      {:error, reason} ->
        Logger.error("Failed to generate presigned URL: #{inspect(reason)}")
        {:error, "Failed to generate presigned URL"}
    end
  end

  defp upload_req_options do
    Application.get_env(:kaguya, :upload_req_options, [])
  end
end
