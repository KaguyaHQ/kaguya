defmodule KaguyaWeb.SEO.JsonLd do
  @moduledoc """
  Schema.org JSON-LD payload builders for SEO parity with the Next.js
  frontend at /Users/zero/work/kaguya.

  Each builder returns a plain map. Encode with
  `Jason.encode!(map, escape: :html_safe)` before injecting into a
  `<script type="application/ld+json">` tag.
  """

  @base_url "https://kaguya.io"

  def website do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "url" => @base_url <> "/",
      "name" => "Kaguya",
      "alternateName" => "kaguya.io"
    }
  end

  def video_game(vn) do
    base = %{
      "@context" => "https://schema.org",
      "@type" => "VideoGame",
      "@id" => @base_url <> "/vn/#{vn.slug}",
      "name" => Map.get(vn, :title),
      "description" => Map.get(vn, :description),
      "image" => vn_image(vn),
      "gamePlatform" => "PC",
      "genre" => "Visual Novel",
      "author" => video_game_authors(vn)
    }

    case aggregate_rating(vn) do
      nil -> base
      rating -> Map.put(base, "aggregateRating", rating)
    end
    |> drop_nil_values()
  end

  def organization(producer) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "@id" => @base_url <> "/developer/#{producer.slug}",
      "name" => Map.get(producer, :name),
      "description" => Map.get(producer, :description),
      "url" => @base_url <> "/developer/#{producer.slug}"
    }
  end

  def item_list(list, owner, items, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 100)
    total_count = Keyword.get(opts, :total_count, length(items))

    list_name = Map.get(list, :name) || humanize_slug(Map.get(list, :slug))

    description =
      case nonempty(Map.get(list, :description)) do
        nil ->
          "#{total_count} visual novels in \"#{list_name}\" on Kaguya. " <>
            "Explore the full list and discover new reads."

        desc ->
          desc
      end

    url = @base_url <> "/@#{owner.username}/list/#{list.slug}"

    base = %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "@id" => url,
      "name" => list_name,
      "description" => description,
      "url" => url,
      "numberOfItems" => total_count,
      "itemListOrder" => "http://schema.org/ItemListOrderDescending",
      "itemListElement" => list_items(items, page, page_size)
    }

    case owner do
      %{} = o ->
        Map.put(base, "author", %{
          "@type" => "Person",
          "name" => owner_json_ld_name(o)
        })

      _ ->
        base
    end
  end

  # ---------- helpers ----------

  defp vn_image(vn) do
    images = Map.get(vn, :images) || %{}

    Map.get(images, :medium) ||
      Map.get(images, :large) ||
      Map.get(images, :small) ||
      Map.get(images, :xl)
  end

  defp video_game_authors(vn) do
    (Map.get(vn, :producers) || [])
    |> Enum.map(fn p ->
      name = get_in(p, [:producer, :name])
      %{"@type" => "Organization", "name" => name}
    end)
  end

  defp aggregate_rating(vn) do
    count = Map.get(vn, :ratings_count) || 0

    if is_integer(count) and count > 0 do
      avg = Map.get(vn, :average_rating) || 0
      reviews_count = Map.get(vn, :reviews_count) || 0

      base = %{
        "@type" => "AggregateRating",
        "ratingValue" => format_rating(avg),
        "ratingCount" => count
      }

      if reviews_count > 0,
        do: Map.put(base, "reviewCount", reviews_count),
        else: base
    end
  end

  defp format_rating(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp format_rating(_), do: "0.0"

  defp list_items(items, page, page_size) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, idx} ->
      vn = Map.get(entry, :visual_novel) || %{}
      position = (page - 1) * page_size + idx

      item =
        %{"@type" => "CreativeWork", "name" => Map.get(vn, :title)}
        |> maybe_put_work_url(vn)
        |> maybe_put_item_image(vn)

      %{"@type" => "ListItem", "position" => position, "item" => item}
    end)
  end

  defp maybe_put_work_url(item, %{slug: slug}) when is_binary(slug) and slug != "" do
    url = @base_url <> "/vn/#{slug}"

    item
    |> Map.put("@id", url)
    |> Map.put("url", url)
  end

  defp maybe_put_work_url(item, _), do: item

  defp maybe_put_item_image(item, vn) do
    case get_in(vn, [:images, :medium]) do
      image when is_binary(image) and image != "" -> Map.put(item, "image", image)
      _ -> item
    end
  end

  defp owner_json_ld_name(%{display_name: name, username: username}) do
    if is_binary(name) and String.trim(name) != "", do: name, else: username || "Kaguya user"
  end

  defp owner_json_ld_name(%{username: username}) when is_binary(username), do: username
  defp owner_json_ld_name(_), do: "Kaguya user"

  defp humanize_slug(slug) when is_binary(slug) do
    slug
    |> String.split("-")
    |> Enum.map_join(" ", fn
      "" ->
        ""

      part ->
        first = String.first(part)
        rest = String.slice(part, 1..-1//1) || ""
        String.upcase(first) <> rest
    end)
  end

  defp humanize_slug(_), do: ""

  defp nonempty(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp nonempty(_), do: nil

  # JSON.stringify on undefined fields drops them; we mirror that for parity
  # by removing top-level nil values from the schema map. Nested nil values
  # remain (matches Next.js JSON.stringify treatment of `null`).
  defp drop_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
