defmodule KaguyaWeb.VNLive.Edit.Uploads do
  @moduledoc false

  alias Kaguya.Covers
  alias Kaguya.Screenshots
  alias Kaguya.Uploads, as: StageUploads
  alias Kaguya.VisualNovels
  alias KaguyaWeb.VNLive.Edit.Form

  def consume_screenshot_uploads(socket, form) do
    results =
      Phoenix.LiveView.consume_uploaded_entries(socket, :new_screenshots, fn %{path: path},
                                                                             _entry ->
        with {:ok, upload_id} <- StageUploads.stage_local_file(path),
             {:ok, screenshot} <-
               Screenshots.upload_screenshot(
                 socket.assigns.vn.id,
                 upload_id,
                 socket.assigns.current_user.id
               ) do
          {:ok,
           %{
             "id" => screenshot.id,
             "thumbnail_url" => VisualNovels.build_screenshot_urls(screenshot.id)[:medium],
             "is_nsfw" => screenshot.is_nsfw == true,
             "is_brutal" => screenshot.is_brutal == true,
             "removed" => false
           }}
        else
          {:error, reason} ->
            {:postpone, Form.normalize_upload_error(reason)}
        end
      end)

    merge_uploaded_rows(form, "screenshots", results)
  end

  def consume_cover_uploads(socket, form) do
    results =
      Phoenix.LiveView.consume_uploaded_entries(socket, :new_covers, fn %{path: path}, _entry ->
        with {:ok, upload_id} <- StageUploads.stage_local_file(path),
             {:ok, cover} <-
               Covers.upload_cover(
                 socket.assigns.vn.id,
                 upload_id,
                 socket.assigns.current_user.id
               ) do
          {:ok,
           %{
             "id" => cover.id,
             "thumbnail_url" => VisualNovels.build_image_urls(cover.id)[:large],
             "is_image_nsfw" => cover.is_image_nsfw == true,
             "removed" => false
           }}
        else
          {:error, reason} ->
            {:postpone, Form.normalize_upload_error(reason)}
        end
      end)

    form
    |> merge_uploaded_rows("covers", results)
    |> case do
      {:ok, updated_form} ->
        {:ok, Form.normalize_primary_cover(updated_form)}

      {:error, {:upload_failed, updated_form, message}} ->
        {:error, {:upload_failed, Form.normalize_primary_cover(updated_form), message}}
    end
  end

  def finalize_pending_uploads(socket, form) do
    with {:ok, form} <- consume_screenshot_uploads(socket, form) do
      consume_cover_uploads(socket, form)
    end
  end

  def merge_uploaded_rows(form, key, results) do
    {rows, errors} =
      Enum.reduce(results, {[], []}, fn
        %{} = row, {rows, errors} -> {rows ++ [row], errors}
        reason, {rows, errors} when is_binary(reason) -> {rows, errors ++ [reason]}
        _other, acc -> acc
      end)

    updated_form =
      if rows == [] do
        form
      else
        Map.update!(form, key, &(&1 ++ rows))
      end

    case errors do
      [] -> {:ok, updated_form}
      [message | _] -> {:error, {:upload_failed, updated_form, message}}
    end
  end
end
