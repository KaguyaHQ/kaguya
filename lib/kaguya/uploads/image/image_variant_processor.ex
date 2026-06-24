defmodule Kaguya.Uploads.ImageVariantProcessor do
  @moduledoc """
  Processes a staged image upload into permanent variants.

  This module owns the reusable work. Oban calls it asynchronously through
  `Kaguya.Uploads.ImageVariantWorker`; edit-profile can call it synchronously
  when the user explicitly saves pending avatar/banner changes.
  """

  alias Kaguya.{
    CharacterImages,
    Covers,
    ImageProcessor,
    ImageStorage,
    ImageSwapper,
    Images,
    ProducerImages,
    Screenshots
  }

  @doc """
  Generates variants, applies any DB side effects, and cleans up the staged
  temp object on success.
  """
  def process(args) when is_map(args) do
    case do_process(args) do
      :ok ->
        cleanup_temp(args)
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  # ── VN / character / producer — variants only, row already exists ──

  defp do_process(%{"type" => "vn_cover", "id" => id, "vn_id" => vn_id}) do
    with {:ok, %{width: w, height: h, mime: mime}} <-
           ImageProcessor.generate_variants_for(:vn_cover, id),
         :ok <- archive_original_if_enabled(:vn_cover, id, mime) do
      Covers.update_dimensions(id, w, h)
      Covers.purge_vn_cdn(vn_id)
      :ok
    end
  end

  defp do_process(%{"type" => "vn_screenshot", "id" => id, "vn_id" => vn_id}) do
    with {:ok, %{width: w, height: h, mime: mime}} <-
           ImageProcessor.generate_variants_for(:vn_screenshot, id),
         :ok <- archive_original_if_enabled(:vn_screenshot, id, mime) do
      Screenshots.update_dimensions(id, w, h)
      Covers.purge_vn_cdn(vn_id)
      :ok
    end
  end

  defp do_process(%{"type" => "character_image", "id" => id}) do
    with {:ok, %{width: w, height: h, mime: mime}} <-
           ImageProcessor.generate_variants_for(:character, id),
         :ok <- archive_original_if_enabled(:character, id, mime) do
      CharacterImages.update_dimensions(id, w, h)
      :ok
    end
  end

  defp do_process(%{"type" => "producer_image", "id" => id}) do
    with {:ok, %{width: w, height: h, mime: mime}} <-
           ImageProcessor.generate_variants_for(:producer, id),
         :ok <- archive_original_if_enabled(:producer, id, mime) do
      ProducerImages.update_dimensions(id, w, h)
      :ok
    end
  end

  # ── Avatar / banner — variants then atomic swap ──

  defp do_process(%{"type" => "avatar", "user_id" => user_id, "id" => id}) do
    with {:ok, _meta} <- ImageProcessor.generate_variants_for(:avatar, id),
         {:ok, _} <- ImageSwapper.swap_user_image(user_id, :avatar, id) do
      :ok
    end
  end

  defp do_process(%{"type" => "banner", "user_id" => user_id, "id" => id}) do
    with {:ok, _meta} <- ImageProcessor.generate_variants_for(:banner, id),
         {:ok, _} <- ImageSwapper.swap_user_image(user_id, :banner, id) do
      :ok
    end
  end

  defp do_process(args) do
    {:error, "ImageVariantProcessor: unknown args shape #{inspect(args)}"}
  end

  defp archive_original_if_enabled(type, id, mime) do
    if Images.archive_original?(type) do
      ImageStorage.archive_original(type, id, mime)
    else
      :ok
    end
  end

  defp cleanup_temp(%{"id" => id}), do: delete_temp(id)
  defp cleanup_temp(_), do: :ok

  defp delete_temp(id) do
    _ = ImageStorage.delete(Images.temp_key(id))
    :ok
  end
end
