defmodule KaguyaWeb.ProfileLive.LibraryData do
  @moduledoc """
  View-model assembly for the `/@:username/library[/:shelf]` LiveView.

  Owns the URL → query mapping, the shelf URL ↔ internal value mapping,
  and the sort kebab ↔ context atom mapping. Per the profile migration
  plan (§6.3) only context calls are allowed — no Ecto in LiveView.
  """

  alias Kaguya.{Library, Pagination, Producers, Shelves}
  alias Kaguya.Shelves.Shelf
  alias Kaguya.VisualNovels.TitleCategory
  alias Kaguya.VisualNovels.VisualNovel

  @page_size 42
  @mobile_page_size 40

  # ---------------------------------------------------------------------------
  # Permanent shelf table — preserves production order/labels.
  # ---------------------------------------------------------------------------

  @permanent_shelves [
    %{value: "ALL", label: "All", slug: nil, status: nil},
    %{value: "CURRENTLY_READING", label: "Reading", slug: "reading", status: :currently_reading},
    %{value: "READ", label: "Read", slug: "read", status: :read},
    %{value: "WANT_TO_READ", label: "Wishlist", slug: "wishlist", status: :want_to_read},
    %{value: "ON_HOLD", label: "Paused", slug: "paused", status: :on_hold},
    %{
      value: "DID_NOT_FINISH",
      label: "Did Not Finish",
      slug: "did-not-finish",
      status: :did_not_finish
    },
    %{
      value: "NOT_INTERESTED",
      label: "Not Interested",
      slug: "not-interested",
      status: :not_interested
    }
  ]

  def permanent_shelves, do: @permanent_shelves

  def page_size, do: @page_size
  def mobile_page_size, do: @mobile_page_size

  # ---------------------------------------------------------------------------
  # Shelf URL/value mapping
  # ---------------------------------------------------------------------------

  @doc """
  Resolve the `:shelf` URL segment into a normalized %{kind, value} tuple.

  Returns one of:
    * `{:all}` — no segment given.
    * `{:status, atom_status}` — permanent shelf url.
    * `{:custom, slug}` — custom (user-defined) shelf slug.
  """
  def resolve_shelf(nil), do: {:all}
  def resolve_shelf(""), do: {:all}

  def resolve_shelf(segment) when is_binary(segment) do
    seg = String.downcase(segment)

    case Enum.find(@permanent_shelves, &(&1.slug == seg)) do
      nil -> {:custom, segment}
      %{value: "ALL"} -> {:all}
      shelf -> {:status, shelf.status}
    end
  end

  @doc """
  Map a shelf kind back to the value the frontend uses (e.g. `"READ"`,
  `"ALL"`, or a custom-shelf slug). Used by the shelf-tabs UI.
  """
  def shelf_value({:all}), do: "ALL"

  def shelf_value({:status, status}) do
    %{value: value} = Enum.find(@permanent_shelves, &(&1.status == status))
    value
  end

  def shelf_value({:custom, slug}), do: slug

  @doc "URL path segment for a given shelf — `nil` means root `/library`."
  def shelf_path_segment({:all}), do: nil

  def shelf_path_segment({:status, status}) do
    %{slug: slug} = Enum.find(@permanent_shelves, &(&1.status == status))
    slug
  end

  def shelf_path_segment({:custom, slug}), do: slug

  # ---------------------------------------------------------------------------
  # Sort kebab ↔ atom mapping
  # ---------------------------------------------------------------------------

  @sort_kebab_to_atom %{
    "most-popular" => :total_ratings_desc,
    "least-popular" => :total_ratings_asc,
    "highest-rated" => :average_rating_desc,
    "lowest-rated" => :average_rating_asc,
    "my-highest-rated" => :my_rating_desc,
    "my-lowest-rated" => :my_rating_asc,
    "newest-release" => :release_date_desc,
    "oldest-release" => :release_date_asc,
    "newest-added" => :date_added_desc,
    "oldest-added" => :date_added_asc,
    "recently-read" => :date_finished_desc,
    "oldest-read" => :date_finished_asc
  }

  @sort_atom_to_kebab Enum.into(@sort_kebab_to_atom, %{}, fn {k, v} -> {v, k} end)

  def parse_sort(nil), do: nil

  def parse_sort(value) when is_binary(value) do
    Map.get(@sort_kebab_to_atom, value)
  end

  def parse_sort(_), do: nil

  def sort_to_kebab(atom) when is_atom(atom), do: Map.get(@sort_atom_to_kebab, atom)
  def sort_to_kebab(_), do: nil

  # ---------------------------------------------------------------------------
  # URL params → state
  # ---------------------------------------------------------------------------

  @doc """
  Parses raw query params (the `params` map from `handle_params/3` minus
  `:username` / `:shelf`) into a normalized filter map. Unknown keys are
  ignored. Empty/blank strings become `nil` (the param is removed).
  """
  def parse_filters(params) when is_map(params) do
    %{
      page: parse_page(params["page"]),
      search: nilify(params["search"] || params["q"]),
      sort: parse_sort(params["sort"]),
      rating: parse_rating(params["rating"]),
      tag_slug: nilify(params["tag"]),
      producer_slug: nilify(params["producer"]),
      original_language: nilify(params["language"]),
      read_year: parse_int(params["readYear"]),
      release_year: parse_int(params["releaseYear"]),
      length_category: nilify(params["length"]),
      age_rating: nilify(params["ageRating"])
    }
  end

  defp nilify(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      v -> v
    end
  end

  defp nilify(_), do: nil

  defp parse_page(value) do
    case parse_int(value) do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: nil

  defp parse_rating(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, ""} when n >= 0.0 and n <= 5.0 -> n
      _ -> nil
    end
  end

  defp parse_rating(_), do: nil

  # ---------------------------------------------------------------------------
  # Encoding state back to URL query string (stable param order)
  # ---------------------------------------------------------------------------

  @param_keys [
    {:search, "search"},
    {:sort, "sort"},
    {:rating, "rating"},
    {:tag_slug, "tag"},
    {:producer_slug, "producer"},
    {:original_language, "language"},
    {:read_year, "readYear"},
    {:release_year, "releaseYear"},
    {:length_category, "length"},
    {:age_rating, "ageRating"},
    {:page, "page"}
  ]

  @doc """
  Encode the filter map as a query string. The `:sort` value can be an atom
  or a kebab string. Default values (page=1, blank strings, nil) are
  omitted.
  """
  def encode_query(filters) when is_map(filters) do
    @param_keys
    |> Enum.flat_map(fn {key, name} ->
      case filters[key] |> encode_value(key) do
        nil -> []
        value -> [{name, value}]
      end
    end)
    |> URI.encode_query()
  end

  defp encode_value(nil, _key), do: nil
  defp encode_value("", _key), do: nil

  defp encode_value(value, :sort) when is_atom(value), do: sort_to_kebab(value)
  defp encode_value(value, :sort), do: value
  defp encode_value(value, :rating) when is_float(value), do: format_rating(value)
  defp encode_value(value, :rating), do: to_string(value)
  defp encode_value(1, :page), do: nil
  defp encode_value(value, :page), do: to_string(value)
  defp encode_value(value, _key), do: to_string(value)

  defp format_rating(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      :erlang.float_to_binary(value, decimals: 1)
    end
  end

  @doc """
  Build a `push_patch` path for the library route. Strips empty params and
  preserves the shelf path segment in the route.
  """
  def build_path(username, shelf, filters) do
    qs = encode_query(filters)
    base = "/@" <> username <> "/library"

    base =
      case shelf_path_segment(shelf) do
        nil -> base
        seg -> base <> "/" <> seg
      end

    if qs == "", do: base, else: base <> "?" <> qs
  end

  # ---------------------------------------------------------------------------
  # Data loaders
  # ---------------------------------------------------------------------------

  @doc """
  Returns the full view-model for the library page body: header counts,
  current grid page, ratings distribution, tag list, and custom shelves.

  `profile` is the header view-model from `ProfileLive.Data.load_header/2`.
  `viewer` may be `nil` (signed-out).
  """
  def load_library(profile, viewer, shelf, filters, opts \\ []) do
    user_id = profile.id
    is_mine = profile.viewer.is_mine
    allowed_categories = allowed_categories(is_mine, viewer)
    page_size = Keyword.get(opts, :page_size, @page_size)

    status = shelf_status(shelf)
    shelf_slug = shelf_slug_for(shelf, user_id)

    args =
      filters
      |> Map.put(:status, status)
      |> Map.put(:shelf_slug, shelf_slug)
      |> Map.put(:sort_by, filters.sort)
      |> Map.put(:page_size, page_size)

    counts = Library.library_status_counts(user_id, nil, allowed_categories: allowed_categories)

    custom_shelves =
      case Shelves.list_shelves_for_user(user_id) do
        {:ok, list} -> list
        _ -> []
      end

    {grid, applied_producer} =
      load_grid(user_id, args,
        allowed_categories: allowed_categories,
        viewer_id: viewer_id(viewer)
      )

    %{
      counts: counts,
      custom_shelves: Enum.map(custom_shelves, &normalize_shelf/1),
      grid: grid,
      ratings_dist:
        Library.library_ratings_dist(
          user_id,
          %{status: status, shelf_slug: shelf_slug},
          allowed_categories: allowed_categories
        ),
      tags: Library.library_tags(user_id),
      applied_producer: applied_producer
    }
  end

  defp load_grid(user_id, args, opts) do
    case Library.list_library_visual_novels(user_id, args, opts) do
      {:ok, {entries, pagination}} ->
        vn_ids = Enum.map(entries, & &1.visual_novel.id)
        ratings = Library.batch_ratings_for_user(user_id, vn_ids)
        reviews = Library.batch_reviews_for_user(user_id, vn_ids)
        shelves = Library.batch_shelves_for_user(user_id, vn_ids)
        viewer_statuses = viewer_statuses_for(user_id, Keyword.get(opts, :viewer_id), vn_ids)

        items =
          Enum.map(entries, fn entry ->
            normalize_entry(entry, ratings, reviews, shelves, viewer_statuses)
          end)

        producer = applied_producer(args.producer_slug)
        total = Pagination.resolve_count(pagination) || length(items)
        page_size = Map.get(pagination, :page_size, @page_size)

        total_pages =
          Pagination.resolve_total_pages(pagination) || compute_total_pages(total, page_size)

        pagination =
          pagination
          |> Map.put(:total_count, total)
          |> Map.put(:total_pages, total_pages)

        {%{items: items, pagination: pagination}, producer}

      {:error, _} ->
        empty_grid()

      _ ->
        empty_grid()
    end
  end

  defp empty_grid do
    {%{
       items: [],
       pagination: %{page: 1, page_size: @page_size, total_pages: 0, total_count: 0}
     }, nil}
  end

  defp compute_total_pages(total, page_size)
       when is_integer(total) and is_integer(page_size) and page_size > 0 do
    div(total + page_size - 1, page_size)
  end

  defp compute_total_pages(_, _), do: 0

  defp shelf_status({:status, status}), do: status
  defp shelf_status(_), do: nil

  defp shelf_slug_for({:custom, slug}, _user_id), do: slug
  defp shelf_slug_for(_, _), do: nil

  defp allowed_categories(true, _viewer), do: nil
  defp allowed_categories(false, viewer), do: TitleCategory.allowed_categories(viewer || %{})

  defp viewer_id(%{id: id}) when is_binary(id), do: id
  defp viewer_id(_viewer), do: nil

  defp viewer_statuses_for(user_id, viewer_id, vn_ids)
       when is_binary(viewer_id) and viewer_id != user_id and vn_ids != [] do
    Library.batch_reading_statuses_for_user(viewer_id, vn_ids)
  end

  defp viewer_statuses_for(_user_id, _viewer_id, _vn_ids), do: %{}

  defp applied_producer(nil), do: nil
  defp applied_producer(""), do: nil

  defp applied_producer(slug) when is_binary(slug) do
    case Producers.get_producer_by_slug(slug) do
      {:ok, producer} -> %{name: producer.name, slug: producer.slug}
      {:error, :not_found} -> %{name: slug, slug: slug}
      _ -> %{name: slug, slug: slug}
    end
  rescue
    _ -> %{name: slug, slug: slug}
  end

  # ---------------------------------------------------------------------------
  # Entry / shelf normalizers (render-ready maps)
  # ---------------------------------------------------------------------------

  defp normalize_entry(
         %{visual_novel: %VisualNovel{} = vn, reading_status: rs},
         ratings,
         reviews,
         shelves,
         viewer_statuses
       ) do
    viewer_status = Map.get(viewer_statuses, vn.id)

    %{
      vn: %{
        id: vn.id,
        title: vn.title,
        slug: vn.slug,
        images: Kaguya.VisualNovels.build_image_urls(vn),
        is_image_nsfw: vn.is_image_nsfw,
        is_image_suggestive: vn.is_image_suggestive,
        my_reading_status: normalize_viewer_status(viewer_status),
        status: rs && rs.status
      },
      status: rs && rs.status,
      viewer_status: viewer_status && viewer_status.status,
      date_started: rs && rs.date_started,
      date_finished: rs && rs.date_finished,
      library_added_at: rs && rs.library_added_at,
      rating: Map.get(ratings, vn.id),
      review_id:
        case Map.get(reviews, vn.id) do
          %{id: id} -> id
          _ -> nil
        end,
      shelves:
        shelves
        |> Map.get(vn.id, [])
        |> Enum.map(&normalize_shelf/1)
    }
  end

  defp normalize_viewer_status(nil), do: nil

  defp normalize_viewer_status(status) do
    %{
      status: status.status,
      date_started: status.date_started,
      date_finished: status.date_finished
    }
  end

  defp normalize_shelf(%Shelf{} = shelf) do
    %{
      id: shelf.id,
      name: shelf.name,
      slug: shelf.slug,
      vns_count: shelf.vns_count || 0
    }
  end
end
