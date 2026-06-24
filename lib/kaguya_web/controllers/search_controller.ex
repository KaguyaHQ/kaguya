defmodule KaguyaWeb.SearchController do
  use KaguyaWeb, :controller

  alias KaguyaWeb.ListLive.Data

  @max_page_size 24

  def visual_novels(conn, params) do
    query = params["q"] || params["query"] || ""
    page_size = params |> Map.get("page_size") |> parse_page_size()

    case Data.search_visual_novels(query, conn.assigns[:current_user],
           page: 1,
           page_size: page_size
         ) do
      {:ok, %{items: items, pagination: pagination}} ->
        json(conn, %{
          items: Enum.map(items, &normalize_result/1),
          pagination: %{
            total_count: Map.get(pagination, :total_count, 0),
            total_pages: Map.get(pagination, :total_pages, 0),
            page: Map.get(pagination, :page, 1),
            page_size: Map.get(pagination, :page_size, page_size)
          }
        })

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Search is temporarily unavailable"})
    end
  end

  defp parse_page_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int |> max(1) |> min(@max_page_size)
      :error -> @max_page_size
    end
  end

  defp parse_page_size(_value), do: @max_page_size

  defp normalize_result(item) do
    image_url = Map.get(item, :image_url) || Map.get(item, "image_url")

    %{
      id: Map.get(item, :id) || Map.get(item, "id"),
      slug: Map.get(item, :slug) || Map.get(item, "slug"),
      title: Map.get(item, :title) || Map.get(item, "title"),
      image_url: image_url,
      images: image_map(item, image_url),
      producers: producer_text(Map.get(item, :producers) || Map.get(item, "producers")),
      has_ero: bool(Map.get(item, :has_ero) || Map.get(item, "has_ero")),
      is_image_nsfw: bool(Map.get(item, :is_image_nsfw) || Map.get(item, "is_image_nsfw")),
      is_image_suggestive:
        bool(Map.get(item, :is_image_suggestive) || Map.get(item, "is_image_suggestive"))
    }
  end

  defp image_map(item, image_url) do
    case Map.get(item, :images) || Map.get(item, "images") do
      images when is_map(images) and map_size(images) > 0 ->
        images

      _ ->
        %{small: image_url, medium: image_url, large: image_url, xl: image_url}
    end
  end

  defp producer_text(producers) when is_list(producers) do
    producers
    |> Enum.map(fn
      %{name: name} -> name
      %{"name" => name} -> name
      value when is_binary(value) -> value
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp producer_text(value) when is_binary(value), do: value
  defp producer_text(_value), do: nil

  defp bool(true), do: true
  defp bool(_), do: false
end
