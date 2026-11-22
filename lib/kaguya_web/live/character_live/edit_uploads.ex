defmodule KaguyaWeb.CharacterLive.Edit.Uploads do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, upload_errors: 1, upload_errors: 2]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, uploaded_entries: 2]

  alias Kaguya.Uploads, as: StageUploads

  def stage(socket, form) do
    config = socket.assigns.uploads.character_image

    cond do
      upload_errors(config) != [] or Enum.any?(config.entries, &(upload_errors(config, &1) != [])) ->
        {:error, socket, "Choose a supported image under 10 MB."}

      elem(uploaded_entries(socket, :character_image), 1) != [] ->
        {:error, socket, "Wait for the image to finish uploading."}

      true ->
        stage_complete(socket, form)
    end
  end

  defp stage_complete(socket, form) do
    results =
      consume_uploaded_entries(socket, :character_image, fn %{path: path}, entry ->
        result =
          case Map.fetch(socket.assigns.staged_uploads, entry.ref) do
            {:ok, id} -> {:ok, id}
            :error -> StageUploads.stage_local_file(path)
          end

        {:postpone, {entry.ref, result}}
      end)

    case results do
      [] ->
        {:ok, socket, nil}

      [{ref, {:ok, id}}] ->
        socket = assign(socket, :staged_uploads, Map.put(socket.assigns.staged_uploads, ref, id))

        {:ok, socket,
         %{
           id: id,
           flags: %{
             is_image_nsfw: form["image_nsfw"],
             is_image_suggestive: form["image_suggestive"]
           }
         }}

      [{_ref, {:error, reason}}] ->
        {:error, socket, "Unable to upload image: #{reason}"}
    end
  end

  def complete(socket) do
    consume_uploaded_entries(socket, :character_image, fn _, _ -> {:ok, :done} end)
    socket
  end

  def error_message(:too_large), do: "Image must be under 10 MB."
  def error_message(:not_accepted), do: "Choose a JPG, PNG, or WebP image."
  def error_message(:too_many_files), do: "Choose one character image."
  def error_message(_error), do: "Image upload failed. Please try again."
end
