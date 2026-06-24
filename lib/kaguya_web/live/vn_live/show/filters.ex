defmodule KaguyaWeb.VNLive.Show.Filters do
  @moduledoc false

  @sort_options ["MOST_LIKED", "NEWEST", "OLDEST"]

  def sort_options, do: @sort_options

  def current_path(slug, sort, reviews) do
    page = if reviews, do: reviews.pagination.page, else: 1
    "/vn/#{slug}?page=#{page}&sort=#{sort}"
  end

  def parse_page(nil), do: 1

  def parse_page(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  def normalize_sort(value) when value in @sort_options, do: value
  def normalize_sort(_), do: "MOST_LIKED"

  def sort_atom("NEWEST"), do: :newest
  def sort_atom("OLDEST"), do: :oldest
  def sort_atom(_), do: :most_liked

  def default_release_filters(%{languages: languages, platforms: platforms}, existing_filters) do
    %{
      language: preferred_filter(existing_filters[:language], languages, "en"),
      platform: preferred_filter(existing_filters[:platform], platforms, "win")
    }
  end

  def default_release_filters(releases, existing_filters) do
    languages = release_codes(releases, :languages)
    platforms = release_codes(releases, :platforms)

    %{
      language: preferred_filter(existing_filters[:language], languages, "en"),
      platform: preferred_filter(existing_filters[:platform], platforms, "win")
    }
  end

  def release_codes(releases, key) do
    releases
    |> Enum.flat_map(&(Map.get(&1, key) || []))
    |> Enum.uniq()
  end

  def preferred_filter(current, available, preferred) do
    cond do
      current in available -> current
      preferred in available -> preferred
      available != [] -> hd(available)
      true -> nil
    end
  end

  def normalize_release_filters(filters) do
    %{
      language: blank_to_nil(filters["language"] || filters[:language]),
      platform: blank_to_nil(filters["platform"] || filters[:platform])
    }
  end

  @empty_release_filters %{language: nil, platform: nil}

  @doc """
  Seeds release filters from the client's saved preference, passed through the
  LiveSocket connect params as a JSON string (see `app.js`). Returns the empty
  filter on a disconnected mount or any malformed value, so the server renders
  the saved selection on first paint instead of round-tripping a correction.
  """
  def connect_param_release_filters(socket) do
    with %{"release_filter_prefs" => raw} when is_binary(raw) <-
           Phoenix.LiveView.get_connect_params(socket) || %{},
         {:ok, %{} = prefs} <- Jason.decode(raw) do
      normalize_release_filters(prefs)
    else
      _ -> @empty_release_filters
    end
  end

  def blank_to_nil(value) when value in [nil, "", "__all__"], do: nil
  def blank_to_nil(value), do: value
end
