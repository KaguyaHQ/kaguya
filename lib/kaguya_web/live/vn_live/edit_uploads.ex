defmodule KaguyaWeb.VNLive.Edit.Uploads do
  @moduledoc false
  alias Kaguya.Uploads, as: StageUploads
  alias Kaguya.VisualNovels
  alias KaguyaWeb.VNLive.Edit.Form
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, uploaded_entries: 2]
  import Phoenix.Component, only: [assign: 3]

  @uploads [new_covers: :cover, new_screenshots: :screenshot]

  # Keep LiveView files until the DB transaction succeeds. Successful staging is
  # cached on the socket so validation failures can be retried without reuploading.
  def stage(socket, form) do
    if Enum.any?(@uploads, fn {name, _} -> elem(uploaded_entries(socket, name), 1) != [] end) do
      {:error, socket, "Wait for the images to finish uploading."}
    else
      stage_complete(socket, form)
    end
  end

  defp stage_complete(socket, form) do
    results =
      Enum.flat_map(@uploads, fn {name, type} ->
        consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
          key = {name, entry.ref}

          result =
            case Map.get(socket.assigns.staged_uploads, key) do
              nil -> StageUploads.stage_local_file(path)
              id -> {:ok, id}
            end

          {:postpone, {key, type, result}}
        end)
      end)

    staged =
      Enum.reduce(results, socket.assigns.staged_uploads, fn
        {key, _, {:ok, id}}, cache -> Map.put(cache, key, id)
        _, cache -> cache
      end)

    socket = assign(socket, :staged_uploads, staged)

    case Enum.find(results, fn {_, _, result} -> match?({:error, _}, result) end) do
      {_, _, {:error, reason}} ->
        {:error, socket, Form.normalize_upload_error(reason)}

      nil ->
        media =
          Enum.map(results, fn {{name, ref}, type, {:ok, id}} ->
            flags = flags(form, name, ref)
            %{id: id, ref: ref, type: type, flags: flags}
          end)

        {:ok, socket, merge_media(form, media), media}
    end
  end

  defp flags(form, :new_covers, ref) do
    %{is_image_nsfw: get_in(form, ["pending_covers", ref, "is_image_nsfw"]) == true}
  end

  defp flags(form, :new_screenshots, ref) do
    %{
      is_nsfw: get_in(form, ["pending_screenshots", ref, "is_nsfw"]) == true,
      is_brutal: get_in(form, ["pending_screenshots", ref, "is_brutal"]) == true
    }
  end

  defp merge_media(form, media) do
    Enum.reduce(media, form, fn item, acc ->
      key = if item.type == :cover, do: "covers", else: "screenshots"

      urls =
        if item.type == :cover,
          do: VisualNovels.build_image_urls(item.id),
          else: VisualNovels.build_screenshot_urls(item.id)

      row =
        item.flags
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
        |> Map.merge(%{
          "id" => item.id,
          "thumbnail_url" => urls[:medium] || urls[:large],
          "removed" => false
        })

      acc = Map.update!(acc, key, &(&1 ++ [row]))

      if item.type == :cover and acc["primary_cover_id"] == "upload:#{item.ref}",
        do: Map.put(acc, "primary_cover_id", item.id),
        else: acc
    end)
    |> Form.normalize_primary_cover()
  end

  def complete(socket) do
    Enum.each(@uploads, fn {name, _} ->
      consume_uploaded_entries(socket, name, fn _, _ -> {:ok, :done} end)
    end)

    socket
  end
end
