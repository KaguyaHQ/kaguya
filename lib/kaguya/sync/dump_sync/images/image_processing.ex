defmodule Kaguya.Sync.DumpSync.Images.ImageProcessing do
  @moduledoc """
  Shared image processing: resize to WebP variants and upload to R2.

  Used by CoverProcessing, CharacterProcessing, and ScreenshotProcessing.
  """

  require Logger

  alias Kaguya.Sync.DumpSync.Images.ImageMapping

  @doc """
  Get or create a UUID for the given VNDB image ID.

  Delegates to ImageMapping for persistent, resumable UUID assignments.
  On first call, generates a UUIDv7 and stores it in ETS.
  On subsequent calls (including after restart with flush file), returns the same UUID.
  """
  def image_id(vndb_image_id) do
    ImageMapping.get_or_create(vndb_image_id)
  end

  @doc """
  Generate resized WebP variants from an image binary.

  Strict: if any variant fails, the entire image fails.
  Returns `{:ok, variants}` or `{:error, reason}`.
  Each variant is `%{suffix, width, height, data}`.
  """
  def generate_variants(binary, variant_specs, quality) do
    case Image.from_binary(binary) do
      {:ok, img} ->
        original_width = Image.width(img)

        results =
          Enum.map(variant_specs, fn %{suffix: suffix, width: target_width} ->
            scale =
              if target_width >= original_width, do: 1.0, else: target_width / original_width

            with {:ok, resized} <- Image.resize(img, scale),
                 {:ok, webp} <- Image.write(resized, :memory, suffix: ".webp", quality: quality) do
              {:ok,
               %{
                 suffix: suffix,
                 width: Image.width(resized),
                 height: Image.height(resized),
                 data: webp
               }}
            else
              error -> {:error, error}
            end
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(results, fn {:ok, v} -> v end)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Upload binary data to R2 as `image/webp`.
  """
  def upload_to_r2(bucket, key, data) do
    case ExAws.S3.put_object(bucket, key, data, content_type: "image/webp")
         |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("R2 upload failed for #{key}: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Upload all variants to R2.

  `key_prefix` should end with the separator, e.g. `"visual_novels/{uuid}-"`.
  Each variant is uploaded as `{key_prefix}{suffix}.webp`.
  """
  def upload_variants(variants, bucket, key_prefix) do
    Enum.each(variants, fn v ->
      upload_to_r2(bucket, "#{key_prefix}#{v.suffix}.webp", v.data)
    end)
  end
end
