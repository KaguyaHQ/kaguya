defmodule Kaguya.ImageStorage do
  @moduledoc "Thin wrapper around ExAws for upload / fetch."
  alias ExAws.S3
  alias Kaguya.Images
  require Logger

  def fetch_temp_image(temp_key) do
    case S3.get_object(Images.bucket(), temp_key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      error -> {:error, "Failed to fetch temporary image: #{inspect(error)}"}
    end
  end

  @doc """
  Upload source bytes to the temporary upload location used by ImageVariantWorker.
  """
  def upload_temp_image(upload_id, binary, content_type \\ "application/octet-stream") do
    key = Images.temp_key(upload_id)

    case S3.put_object(Images.bucket(), key, binary, content_type: content_type)
         |> ExAws.request() do
      {:ok, _} ->
        Logger.warning("S3 temp upload ok: #{key}")
        {:ok, key}

      {:error, reason} ->
        Logger.error("S3 temp upload failed for #{key}: #{inspect(reason)}")
        {:error, "Failed to upload temporary image"}
    end
  end

  def get_image_metadata(image_data) do
    case ExImageInfo.info(image_data) do
      {mime, w, h, _} when mime in ~w|image/jpeg image/png image/webp| ->
        {:ok, %{mime: mime, width: w, height: h}}

      {mime, _, _, _} ->
        {:error, "Unsupported image format: #{mime}"}

      nil ->
        {:error, "Could not extract image metadata"}
    end
  end

  # Still public because ImageProcessor calls it
  def upload_resized_image(binary, type, upload_id, suffix) do
    key = Images.key(type, upload_id, suffix)
    opts = [content_type: "image/webp"]

    case S3.put_object(Images.bucket(), key, binary, opts) |> ExAws.request() do
      {:ok, _} ->
        Logger.warning("S3 upload ok: #{key}")
        {:ok, key}

      {:error, reason} ->
        Logger.error("S3 upload failed for #{key}: #{inspect(reason)}")
        {:error, "Failed to upload resized image"}
    end
  end

  @doc """
  Archive the user-uploaded source bytes by server-side copying the temp
  object to its permanent key under the bucket-wide `archive/`
  namespace. The copy preserves the raw bytes verbatim and stamps the
  source mime onto the destination's Content-Type so the format is
  recoverable from S3 metadata.

  The destination key is extensionless — archives are write-once for
  preservation, never served directly to users, so a deterministic
  `<id>` key is enough to retrieve them later for re-processing.

  Idempotent — re-running with the same `upload_id` overwrites the same
  key, so Oban retries are safe.
  """
  def archive_original(type, upload_id, mime) do
    bucket = Images.bucket()
    src = Images.temp_key(upload_id)
    dst = Images.archive_key(type, upload_id)

    case S3.put_object_copy(bucket, dst, bucket, src,
           content_type: mime,
           metadata_directive: "REPLACE"
         )
         |> ExAws.request() do
      {:ok, _} ->
        Logger.warning("S3 archive ok: #{dst}")
        :ok

      {:error, reason} ->
        Logger.error("S3 archive failed for #{dst}: #{inspect(reason)}")
        {:error, "Failed to archive original image"}
    end
  end

  @doc """
  Delete a single object given its full key.
  """
  def delete(key) do
    case S3.delete_object(Images.bucket(), key) |> ExAws.request() do
      {:ok, _} ->
        Logger.warning("S3 delete ok: #{key}")
        :ok

      {:error, reason} ->
        Logger.warning("S3 delete failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
