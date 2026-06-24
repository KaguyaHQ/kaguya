defmodule Kaguya.ImageProcessor do
  @moduledoc "Resize + upload variants, then hand off to ImageSwapper."

  alias Kaguya.{Images, ImageStorage, ImageSwapper}
  require Logger

  # ─── PUBLIC ENTRY POINT ──────────────────────────────────────────
  @doc "Process a user avatar upload."
  def process_avatar_upload(upload_id, user_id) do
    pipeline(upload_id, :avatar, fn _meta ->
      ImageSwapper.swap_user_image(user_id, :avatar, upload_id)
    end)
  end

  @doc "Process a user banner upload."
  def process_banner_upload(upload_id, user_id) do
    pipeline(upload_id, :banner, fn _meta ->
      ImageSwapper.swap_user_image(user_id, :banner, upload_id)
    end)
  end

  @doc "Process a VN cover upload. Returns {:ok, %{width, height}} on success."
  def process_cover_upload(upload_id) do
    pipeline(upload_id, :vn_cover, fn meta -> {:ok, meta} end)
  end

  @doc "Process a VN screenshot upload. Returns {:ok, %{width, height}} on success."
  def process_screenshot_upload(upload_id) do
    pipeline(upload_id, :vn_screenshot, fn meta -> {:ok, meta} end)
  end

  @doc "Process a character image upload. Returns {:ok, %{width, height}} on success."
  def process_character_image_upload(upload_id) do
    pipeline(upload_id, :character, fn meta -> {:ok, meta} end)
  end

  @doc """
  Generate and upload variants for an upload_id. Returns the source
  image's dimensions and mime on success so the caller can backfill the
  row's width/height/original_format columns and (optionally) archive
  the original. Idempotent — re-running with the same id overwrites the
  same S3 keys, so retries from Oban are safe.

  Called from ImageVariantWorker after the row already exists (for
  vn_cover/vn_screenshot/character) or before the swap (for avatar/banner).
  """
  def generate_variants_for(type, upload_id)
      when type in [:avatar, :banner, :vn_cover, :vn_screenshot, :character, :producer] do
    temp_key = Images.temp_key(upload_id)
    variants = Images.variants(type)

    with {:ok, raw} <- ImageStorage.fetch_temp_image(temp_key),
         {:ok, %{mime: mime}} <- ImageStorage.get_image_metadata(raw),
         {:ok, %{width: w, height: h}} <-
           generate_and_upload_variants(raw, upload_id, type, variants) do
      {:ok, %{width: w, height: h, mime: mime}}
    else
      {:error, reason} = err ->
        Logger.error(
          "ImageProcessor.generate_variants_for #{type}/#{upload_id} failed: #{inspect(reason)}"
        )

        err
    end
  end

  # CORE pipeline
  defp pipeline(upload_id, type, swap_callback) do
    temp_key = Images.temp_key(upload_id)
    variants = Images.variants(type)

    with {:ok, raw} <- ImageStorage.fetch_temp_image(temp_key),
         {:ok, meta} <- ImageStorage.get_image_metadata(raw),
         {:ok, _context} <- generate_and_upload_variants(raw, upload_id, type, variants),
         {:ok, result} <- swap_callback.(meta) do
      {:ok, result}
    else
      {:error, reason} = err ->
        Logger.error("ImageProcessor.#{type} failed: #{inspect(reason)}")
        err
    end
  end

  # ─── VARIANT GENERATION ─────────────────────────────────────────
  defp generate_and_upload_variants(raw, upload_id, type, variants) do
    with {:ok, image} <- Image.from_binary(raw),
         {:ok, uploaded} <- upload_variants(variants, image, upload_id, type) do
      # libvips already decoded the source image; reading dimensions
      # from the Image struct is O(1), no extra work.
      {:ok, %{variants: uploaded, width: Image.width(image), height: Image.height(image)}}
    end
  end

  defp upload_variants(variants, image, upload_id, type) do
    max_config = Application.get_env(:kaguya, :image_variant_concurrency, 3)
    max_concurrency = variants |> length() |> min(max_config) |> max(1)

    variants
    |> Task.async_stream(&upload_variant(&1, image, upload_id, type),
      max_concurrency: max_concurrency,
      timeout: 120_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, variant}}, {:ok, acc} -> {:cont, {:ok, [variant | acc]}}
      {:ok, {:error, err}}, _ -> {:halt, {:error, err}}
      {:exit, err}, _ -> {:halt, {:error, err}}
    end)
    |> case do
      {:ok, uploaded} -> {:ok, Enum.sort_by(uploaded, & &1.width)}
      other -> other
    end
  end

  defp upload_variant(%{suffix: suffix} = variant, image, upload_id, type) do
    with {:ok, thumb, %{width: width, height: height}} <- create_thumbnail(image, variant),
         {:ok, key} <- ImageStorage.upload_resized_image(thumb, type, upload_id, suffix) do
      {:ok,
       %{
         key: key,
         suffix: suffix,
         width: width,
         height: height,
         aspect_ratio: Map.get(variant, :aspect_ratio)
       }}
    end
  end

  # ─── THUMBNAILING ────────────────────────────────────────────────
  # Covers/avatars/banners: crop to exact dimensions (center crop)
  # Screenshots: resize to fit within dimensions, preserving aspect ratio
  def create_thumbnail(image, %{w: target_width, h: target_height, fit: true}) do
    dim = "#{target_width}x#{target_height}"

    with {:ok, thumb} <- Image.thumbnail(image, dim, resize: :down),
         {:ok, binary} <- Image.write(thumb, :memory, suffix: ".webp", quality: 75) do
      w = Image.width(thumb)
      h = Image.height(thumb)
      {:ok, binary, %{width: w, height: h}}
    end
  end

  def create_thumbnail(image, %{w: target_width, h: target_height}) do
    dim = "#{target_width}x#{target_height}"

    with {:ok, thumb} <- Image.thumbnail(image, dim, crop: :center),
         {:ok, binary} <- Image.write(thumb, :memory, suffix: ".webp", quality: 75) do
      {:ok, binary, %{width: target_width, height: target_height}}
    end
  end
end
