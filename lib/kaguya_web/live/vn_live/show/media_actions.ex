defmodule KaguyaWeb.VNLive.Show.MediaActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]
  import KaguyaWeb.VN.Formatters, only: [year: 1]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def toggle_cover_like(socket, %{"cover-id" => cover_id}) do
    toggle_media_like(socket, :covers, cover_id, :cover)
  end

  def toggle_screenshot_like(socket, %{"screenshot-id" => screenshot_id}) do
    toggle_media_like(socket, :screenshots, screenshot_id, :screenshot)
  end

  def open_media_lightbox(socket, params) do
    entries = media_lightbox_entries(socket.assigns.active_tab, socket.assigns.tabs)
    image_url = params["url"]
    index = Enum.find_index(entries, &(Map.get(&1, :src) == image_url)) || 0

    entries =
      if entries == [] do
        [
          %{
            id: image_url,
            src: image_url,
            alt: params["title"] || socket.assigns.display_vn.title
          }
        ]
      else
        entries
      end

    {:noreply,
     assign(socket,
       media_lightbox: put_media_lightbox_entry(%{entries: entries}, index)
     )}
  end

  def close_media_lightbox(socket, _params),
    do: {:noreply, assign(socket, media_lightbox: nil)}

  def previous_media(socket, _params),
    do: {:noreply, shift_media_lightbox(socket, -1)}

  def next_media(socket, _params),
    do: {:noreply, shift_media_lightbox(socket, 1)}

  defp toggle_media_like(socket, tab, item_id, kind) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        {liked?, socket} =
          Data.update_tab_item(socket, tab, item_id, fn item ->
            liked? = item.liked_by_me

            {liked?,
             %{
               item
               | liked_by_me: !liked?,
                 likes_count: max(0, item.likes_count + if(liked?, do: -1, else: 1))
             }}
          end)

        result =
          case kind do
            :cover -> PageData.toggle_cover_like(item_id, liked?, user)
            :screenshot -> PageData.toggle_screenshot_like(item_id, liked?, user)
          end

        case result do
          {:ok, _} -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to like media")}
    end
  end

  defp shift_media_lightbox(socket, offset) do
    case socket.assigns.media_lightbox do
      %{entries: entries, index: index} = lightbox when length(entries) > 1 ->
        next_index = rem(index + offset + length(entries), length(entries))
        assign(socket, media_lightbox: put_media_lightbox_entry(lightbox, next_index))

      _ ->
        socket
    end
  end

  defp put_media_lightbox_entry(%{entries: entries} = lightbox, index) do
    count = length(entries)
    safe_index = min(max(index, 0), max(count - 1, 0))
    entry = Enum.at(entries, safe_index) || %{}

    lightbox
    |> Map.merge(entry)
    |> Map.merge(%{index: safe_index, count: count})
  end

  defp media_lightbox_entries(active_tab, tabs) when active_tab in [:covers, :screenshots] do
    case Map.get(tabs, active_tab) do
      {:ok, items} ->
        items
        |> Enum.with_index()
        |> Enum.map(&media_lightbox_entry(active_tab, &1, length(items)))
        |> Enum.reject(&(is_nil(&1.src) || &1.src == ""))

      _ ->
        []
    end
  end

  defp media_lightbox_entries(_active_tab, _tabs), do: []

  defp media_lightbox_entry(:covers, {cover, index}, count) do
    %{
      id: Map.get(cover, :id) || "cover-#{index}",
      src: image_src(cover, [:large, :medium, :small]),
      alt: cover_label(cover),
      title: "Cover #{index + 1} of #{count}"
    }
  end

  defp media_lightbox_entry(:screenshots, {screenshot, index}, count) do
    %{
      id: Map.get(screenshot, :id) || "screenshot-#{index}",
      src: image_src(screenshot, [:large, :medium, :small]),
      alt: screenshot_label(screenshot),
      title: "Screenshot #{index + 1} of #{count}"
    }
  end

  defp media_lightbox_entry(_tab, _item, _count), do: nil

  defp cover_label(cover) do
    Enum.filter([Map.get(cover, :language), year(Map.get(cover, :release_date))], & &1)
    |> Enum.join(" · ")
    |> case do
      "" -> "Cover"
      label -> label
    end
  end

  defp screenshot_label(%{is_nsfw: true}), do: "NSFW screenshot"
  defp screenshot_label(%{is_brutal: true}), do: "Brutal screenshot"
  defp screenshot_label(_), do: "Screenshot"

  defp image_src(entity, preferred_sizes) do
    images = Map.get(entity, :images) || Map.get(entity, "images") || %{}

    Enum.find_value(preferred_sizes, fn size ->
      Map.get(images, size) || Map.get(images, to_string(size))
    end)
  end
end
