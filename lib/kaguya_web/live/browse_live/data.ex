defmodule KaguyaWeb.BrowseLive.Data do
  @moduledoc false

  alias Kaguya.{Characters, VisualNovels}

  @vn_page_size 48
  @character_page_size 30
  @section_page_size 36
  @max_vn_pages 10
  @max_character_pages 50

  @vn_sort_from_param %{
    "top-rated" => :average_rating_desc,
    "lowest-rated" => :average_rating_asc,
    "most-popular" => :total_ratings_desc,
    "least-popular" => :total_ratings_asc,
    "newest" => :release_date_desc,
    "oldest" => :release_date_asc,
    "relevance" => :relevance_desc
  }

  @vn_sort_options [
    {"Top Rated", "top-rated"},
    {"Lowest Rated", "lowest-rated"},
    {"Most Popular", "most-popular"},
    {"Least Popular", "least-popular"},
    {"Newest", "newest"},
    {"Oldest", "oldest"},
    {"Relevance", "relevance"}
  ]

  @character_sort_from_param %{
    "most-popular" => :most_popular,
    "name-a-z" => :name_asc,
    "name-z-a" => :name_desc,
    "recently-added" => :recently_added
  }

  @character_sort_options [
    {"Most Popular", "most-popular"},
    {"Name A-Z", "name-a-z"},
    {"Name Z-A", "name-z-a"},
    {"Recently Added", "recently-added"}
  ]

  @sections [
    %{
      id: :popular,
      title: "Popular",
      href: "/browse?sort=most-popular",
      sort_by: :total_ratings_desc,
      filters: %{}
    },
    %{
      id: :free_on_itch,
      title: "Free on Itch",
      href: "/browse?freeStores=itch&sort=most-popular",
      sort_by: :total_ratings_desc,
      filters: %{free_on_stores: ["itch"], ratings_count_gte: 1}
    },
    %{
      id: :romance,
      title: "Romance",
      href: "/browse?tags=romance",
      sort_by: nil,
      filters: %{include_tags: ["romance"]}
    },
    %{
      id: :otome,
      title: "Otome",
      href: "/browse?tags=otome-game",
      sort_by: nil,
      filters: %{include_tags: ["otome-game"]}
    },
    %{
      id: :avn,
      title: "AVNs",
      href: "/browse?isAvn=true&sort=most-popular",
      sort_by: :total_ratings_desc,
      filters: %{is_avn: true, ratings_count_gte: 1}
    }
  ]

  def load(:characters, params, current_user) do
    page = params |> Map.get("page") |> parse_page(@max_character_pages)
    sort_param = normalize_character_sort_param(Map.get(params, "sort"))

    result =
      Characters.list_characters(
        page: page,
        page_size: @character_page_size,
        sort: Map.fetch!(@character_sort_from_param, sort_param)
      )

    %{
      mode: :characters,
      current_user: current_user,
      page: page,
      page_size: @character_page_size,
      sort_param: sort_param,
      sort_options: @character_sort_options,
      result: result
    }
  end

  def load(:vn, params, current_user) do
    page = params |> Map.get("page") |> parse_page(@max_vn_pages)
    sort_param = normalize_vn_sort_param(Map.get(params, "sort"))
    filters = vn_filters(params, current_user)
    active? = filters_active?(filters) or not is_nil(sort_param)

    result =
      if active? do
        VisualNovels.browse_visual_novels(
          page: page,
          page_size: @vn_page_size,
          sort_by: sort_param && Map.fetch!(@vn_sort_from_param, sort_param),
          filters: filters
        )
      end

    sections =
      if active? do
        []
      else
        load_sections(current_user)
      end

    %{
      mode: :vn,
      current_user: current_user,
      page: page,
      sort_param: sort_param,
      sort_options: @vn_sort_options,
      filters: filters,
      filters_active?: active?,
      result: result,
      sections: sections
    }
  end

  def filters_active?(filters) do
    filters
    |> Map.drop([:include_nukige, :include_adjacent])
    |> Enum.any?(fn
      {_key, nil} -> false
      {_key, []} -> false
      {_key, ""} -> false
      {_key, _value} -> true
    end)
  end

  def vn_sort_options, do: @vn_sort_options
  def character_sort_options, do: @character_sort_options

  defp load_sections(current_user) do
    prefs = content_prefs(current_user)

    Enum.map(@sections, fn section ->
      result =
        VisualNovels.browse_visual_novels(
          page: 1,
          page_size: @section_page_size,
          sort_by: section.sort_by,
          filters: Map.merge(section.filters, prefs)
        )

      Map.put(section, :items, result.items)
    end)
  end

  defp vn_filters(params, current_user) do
    %{
      released_after_year: params |> Map.get("fromYear") |> parse_int(),
      released_before_year: params |> Map.get("toYear") |> parse_int(),
      average_rating_gte: params |> Map.get("minRating") |> parse_float(),
      average_rating_lte: params |> Map.get("maxRating") |> parse_float(),
      include_tags: params |> Map.get("tags") |> parse_string_list(),
      exclude_tags: params |> Map.get("excludeTags") |> parse_string_list(),
      ratings_count_gte: params |> Map.get("minRatings") |> parse_int(),
      ratings_count_lte: params |> Map.get("maxRatings") |> parse_int(),
      available_platforms: params |> Map.get("platforms") |> parse_string_list(),
      available_languages: params |> Map.get("languages") |> parse_string_list(),
      engines: params |> Map.get("engines") |> parse_string_list(),
      length_category: empty_to_nil(Map.get(params, "length")),
      original_languages: params |> Map.get("origLang") |> parse_string_list(),
      available_on_stores: params |> Map.get("stores") |> parse_string_list(),
      free_on_stores: params |> Map.get("freeStores") |> parse_string_list(),
      is_avn: params |> Map.get("isAvn") |> parse_bool()
    }
    |> Map.merge(content_prefs(current_user))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
    |> Map.new()
  end

  defp content_prefs(current_user) do
    %{
      include_nukige: Map.get(current_user || %{}, :show_nukige, true),
      include_adjacent: Map.get(current_user || %{}, :show_adjacent, true)
    }
  end

  defp parse_page(nil, _max), do: 1

  defp parse_page(value, max_page) do
    value
    |> parse_int()
    |> case do
      n when is_integer(n) and n > 0 -> min(n, max_page)
      _ -> 1
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp parse_float(value) when is_float(value) or is_integer(value), do: value / 1

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_float(_), do: nil

  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool(_), do: nil

  defp parse_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&parse_string_list(&1))
    |> Enum.uniq()
  end

  defp parse_string_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> []
      list -> list
    end
  end

  defp parse_string_list(_), do: []

  defp empty_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp empty_to_nil(_), do: nil

  defp normalize_vn_sort_param(sort) when is_map_key(@vn_sort_from_param, sort), do: sort
  defp normalize_vn_sort_param(_), do: nil

  defp normalize_character_sort_param(sort) when is_map_key(@character_sort_from_param, sort),
    do: sort

  defp normalize_character_sort_param(_), do: "most-popular"
end
