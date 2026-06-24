defmodule Kaguya.VisualNovels do
  @moduledoc """
  Context for Visual Novel operations.
  """

  @behaviour Kaguya.Revisions.EntityContext

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Search

  alias Kaguya.VisualNovels.{
    Browse,
    VisualNovel,
    Relation,
    Version,
    VNTag,
    VNTitle,
    VnExternalLink
  }

  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.CursorPagination
  alias Kaguya.Pagination
  alias Kaguya.SearchIndex

  # ============================================================================
  # Visual Novel Queries
  # ============================================================================

  @doc """
  Gets a visual novel by ID.
  """
  def get_visual_novel(id, opts \\ []) do
    VisualNovel |> maybe_filter_hidden(opts) |> Repo.get(id)
  end

  @doc """
  Gets a visual novel by slug. Falls back to `slug_redirects` (entity
  type `:vn`): if the slug used to belong to a different VN that was
  merged or renamed, returns the surviving VN. Lets cached client URLs
  and external links survive merges/renames without 404ing.
  """
  def get_visual_novel_by_slug(slug, opts \\ []) do
    case VisualNovel
         |> maybe_filter_hidden(opts)
         |> where([vn], vn.slug == ^slug)
         |> Repo.one() do
      nil ->
        # Direct lookup missed — fall through `slug_redirects` for any
        # historical URL (merge sources, canonical renames, ad-hoc
        # admin renames). One table, every redirect path.
        case Kaguya.SlugRedirects.resolve(:vn, slug) do
          nil ->
            nil

          target_id ->
            VisualNovel
            |> maybe_filter_hidden(opts)
            |> where([vn], vn.id == ^target_id)
            |> Repo.one()
        end

      vn ->
        vn
    end
  end

  @doc """
  Resolve a slug to a VN id, falling through `slug_redirects` so callers
  that only need the id can transparently follow historical URLs without
  loading the whole VN row.
  """
  def resolve_vn_id_by_slug(slug) do
    case Repo.one(from v in VisualNovel, where: v.slug == ^slug, select: v.id, limit: 1) do
      nil -> Kaguya.SlugRedirects.resolve(:vn, slug)
      id -> id
    end
  end

  @doc """
  Bulk variant of `resolve_vn_id_by_slug/1`. Returns `%{slug => vn_id}`
  for every input slug that resolves either directly or via
  `slug_redirects`. Slugs with no match are absent from the returned map.
  """
  def resolve_vn_ids_by_slugs(slugs) when is_list(slugs) do
    direct =
      from(v in VisualNovel, where: v.slug in ^slugs, select: {v.slug, v.id})
      |> Repo.all()
      |> Map.new()

    missing = slugs -- Map.keys(direct)
    fallback = Kaguya.SlugRedirects.resolve_many(:vn, missing)

    Map.merge(direct, fallback)
  end

  @doc """
  Gets a visual novel by VNDB ID.
  """
  def get_visual_novel_by_vndb_id(vndb_id, opts \\ []) do
    VisualNovel
    |> maybe_filter_hidden(opts)
    |> where([vn], vn.vndb_id == ^vndb_id)
    |> Repo.one()
  end

  @doc """
  Lists visual novels with optional filters.
  """
  def list_visual_novels(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, :average_rating)

    VisualNovel
    |> visible()
    |> order_by_field(order_by)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns visible visual novels for sitemap indexing.
  """
  def list_visual_novels_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      from(vn in VisualNovel,
        where: is_nil(vn.hidden_at) and not is_nil(vn.slug),
        order_by: [desc: vn.updated_at, desc: vn.id],
        select: %{
          id: vn.id,
          slug: vn.slug,
          updated_at: vn.updated_at,
          primary_image_id: vn.primary_image_id,
          temp_image_url: vn.temp_image_url
        }
      )

    {items, pagination} = Pagination.paginate(query, page, page_size)

    items =
      Enum.map(items, fn item ->
        images = build_image_urls(item)
        Map.put(item, :image_url, images[:medium])
      end)

    {items, pagination}
  end

  @doc """
  Lists visual novels for the public browse page.

  This is the context-facing API used by browse surfaces.
  """
  def browse_visual_novels(opts \\ []), do: Browse.list(opts)

  defp order_by_field(query, :average_rating), do: order_by(query, [vn], desc: vn.average_rating)
  defp order_by_field(query, :title), do: order_by(query, [vn], asc: vn.title)
  defp order_by_field(query, :newest), do: order_by(query, [vn], desc: vn.inserted_at)
  defp order_by_field(query, _), do: order_by(query, [vn], desc: vn.average_rating)

  @doc """
  Counts total visual novels.
  """
  def count_visual_novels do
    VisualNovel |> visible() |> Repo.aggregate(:count, :id)
  end

  defp visible(query) do
    where(query, [vn], is_nil(vn.hidden_at))
  end

  defp maybe_filter_hidden(query, opts) do
    if Keyword.get(opts, :include_hidden, false), do: query, else: visible(query)
  end

  # ============================================================================
  # Search
  # ============================================================================

  @doc """
  Searches visual novels by title using Meilisearch.
  Empty/blank queries are cached since they always return the same default results.
  """
  def search_visual_novels(raw_query_string, page, page_size, opts \\ []) do
    query = normalize_search_query(raw_query_string)
    search_opts = build_category_filter_opts(opts)

    if query == "" do
      cached_search(
        :search_vns_default,
        "visual_novels",
        "",
        page,
        page_size,
        &parse_vn_hit/1,
        search_opts
      )
    else
      do_search_visual_novels(query, page, page_size, search_opts)
    end
  end

  defp do_search_visual_novels(query, page, page_size, search_opts) do
    with {:ok, response_body} <-
           Search.search_index("visual_novels", query, page, page_size, search_opts) do
      {:ok, format_search_results(response_body, page, page_size, &parse_vn_hit/1)}
    end
  end

  defp build_category_filter_opts(opts) do
    include_nukige = Keyword.get(opts, :include_nukige, false)
    include_adjacent = Keyword.get(opts, :include_adjacent, false)

    allowed = ["vn"]
    allowed = if include_nukige, do: allowed ++ ["nukige"], else: allowed
    allowed = if include_adjacent, do: allowed ++ ["adjacent"], else: allowed

    if allowed == ["vn", "nukige", "adjacent"] do
      []
    else
      quoted = Enum.map_join(allowed, ", ", &"\"#{&1}\"")
      [filter: "title_category IN [#{quoted}]"]
    end
  end

  defp parse_vn_hit(hit) do
    cover_sensitive = hit["has_ero"] == true

    has_explicit_cover_flags =
      Map.has_key?(hit, "is_image_nsfw") or Map.has_key?(hit, "is_image_suggestive")

    is_image_nsfw =
      hit["is_image_nsfw"] == true or (cover_sensitive and not has_explicit_cover_flags)

    is_image_suggestive = hit["is_image_suggestive"] == true

    %{
      id: hit["id"],
      title: hit["title"],
      slug: hit["slug"],
      image_url: hit["image_url"],
      images:
        build_image_urls(%{
          primary_image_id: hit["primary_image_id"],
          temp_image_url: hit["image_url"]
        }),
      producers: hit["producers"],
      has_ero: is_image_nsfw or is_image_suggestive,
      is_image_nsfw: is_image_nsfw,
      is_image_suggestive: is_image_suggestive
    }
  end

  @doc """
  Normalizes user-entered VN search text to match the compact prefix tokens
  stored in Meilisearch.

  Titles such as `I/O`, `D.C.`, `Muv-Luv`, and `Fate/stay night` are indexed
  with punctuation-stripped prefix tokens. Normalizing equivalent user input
  here keeps pickers and global VN search aligned with those indexed forms.
  """
  def normalize_search_query(q) when is_binary(q) do
    q
    |> String.trim()
    # Remove leading articles
    |> then(&Regex.replace(~r/^(?:the|a|an)\s+/i, &1, ""))
    # Remove hyphens that start a word (Meilisearch interprets -word as negative search)
    # e.g., "Rance X -Kessen-" -> "Rance X Kessen-"
    |> then(&Regex.replace(~r/(?<=\s)-(?=\S)|^-(?=\S)/, &1, ""))
    |> compact_single_letter_query()
    |> strip_search_punctuation()
  end

  def normalize_search_query(other), do: other

  defp compact_single_letter_query(query) do
    words = String.split(query, ~r/\s+/u, trim: true)

    if length(words) > 1 and Enum.all?(words, &(String.length(&1) == 1)) do
      Enum.join(words, "")
    else
      query
    end
  end

  defp strip_search_punctuation(query) do
    query
    |> then(&Regex.replace(~r/(?<=[\p{L}\p{Nd}])[^\p{L}\p{Nd}\s]+(?=[\p{L}\p{Nd}])/u, &1, ""))
    |> then(&Regex.replace(~r/(^|(?<=\s))[^\p{L}\p{Nd}\s]+|[^\p{L}\p{Nd}\s]+(?=\s|$)/u, &1, ""))
  end

  # Cache wrapper for empty search queries — avoids hitting Meilisearch for identical results.
  # 1-week TTL, keyed by {type, page, page_size}.
  defp cached_search(type, index, query, page, page_size, parse_fn, search_opts \\ []) do
    cache_key = {type, page, page_size, search_opts}

    case Cachex.fetch(:kaguya_cache, cache_key, fn ->
           case Search.search_index(index, query, page, page_size, search_opts) do
             {:ok, body} ->
               {:commit, format_search_results(body, page, page_size, parse_fn),
                expire: :timer.hours(24 * 7)}

             {:error, _} = err ->
               {:ignore, err}
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:commit, result} -> {:ok, result}
      {:ignore, err} -> err
    end
  end

  defp format_search_results(response_body, page, page_size, parse_fn) do
    %{
      items: Enum.map(response_body["hits"], parse_fn),
      pagination: %{
        page: page,
        page_size: page_size,
        total_pages: response_body["totalPages"],
        total_count: response_body["totalHits"]
      }
    }
  end

  @doc """
  Searches characters by name using Meilisearch.
  Empty/blank queries are cached since they always return the same default results.
  """
  def search_characters(query_string, page, page_size) do
    query = String.trim(query_string || "")

    if query == "" do
      cached_search(
        :search_chars_default,
        "characters",
        "",
        page,
        page_size,
        &parse_character_hit/1
      )
    else
      do_search_characters(query, page, page_size)
    end
  end

  defp do_search_characters(query, page, page_size) do
    with {:ok, response_body} <- Search.search_index("characters", query, page, page_size) do
      {:ok, format_search_results(response_body, page, page_size, &parse_character_hit/1)}
    end
  end

  defp parse_character_hit(hit) do
    %{
      id: hit["id"],
      name: hit["name"],
      slug: hit["slug"],
      images:
        build_character_image_urls(%{
          primary_image_id: hit["primary_image_id"],
          vndb_image_id: hit["vndb_image_id"]
        }),
      is_image_nsfw: hit["is_image_nsfw"] || false,
      is_image_suggestive: hit["is_image_suggestive"] || false
    }
  end

  @doc """
  Creates a visual novel.
  """
  def create_visual_novel(attrs) do
    %VisualNovel{}
    |> VisualNovel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a visual novel.
  """
  def update_visual_novel(%VisualNovel{} = vn, attrs) do
    vn
    |> VisualNovel.changeset(attrs)
    |> Repo.update()
  end

  # ============================================================================
  # Producer Queries
  # ============================================================================

  @doc """
  Gets a producer by ID.
  """
  def get_producer(id), do: Repo.get(Producer, id)

  @doc """
  Gets a producer by VNDB ID.
  """
  def get_producer_by_vndb_id(vndb_id) do
    Producer
    |> where([p], p.vndb_id == ^vndb_id)
    |> Repo.one()
  end

  @doc """
  Creates a producer.
  """
  def create_producer(attrs) do
    %Producer{}
    |> Producer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets or creates a producer by VNDB ID.
  """
  def get_or_create_producer(vndb_id, attrs) do
    case get_producer_by_vndb_id(vndb_id) do
      nil -> create_producer(Map.put(attrs, :vndb_id, vndb_id))
      producer -> {:ok, producer}
    end
  end

  @doc """
  Gets producers for a visual novel.
  """
  def get_producers_for_vn(visual_novel_id) do
    VNProducer
    |> where([vp], vp.visual_novel_id == ^visual_novel_id)
    |> preload(:producer)
    |> Repo.all()
    |> Enum.map(& &1.producer)
  end

  @doc """
  Gets vn-producer associations including role info.

  Sort is shared so every consumer (VN page, search index, list cards)
  renders producers in the
  same order: developer_publisher first, then developer, then publisher,
  then anything else; within a role, the producer credited on the
  earliest release wins, ties broken by name.
  """
  def get_vn_producers(visual_novel_id) do
    VNProducer
    |> join(:inner, [vp], p in assoc(vp, :producer))
    |> where([vp], vp.visual_novel_id == ^visual_novel_id)
    |> order_by([vp, p],
      asc:
        fragment(
          "CASE ? WHEN 'developer_publisher' THEN 0 WHEN 'developer' THEN 1 WHEN 'publisher' THEN 2 ELSE 3 END",
          vp.role
        ),
      asc_nulls_last: vp.earliest_release_date,
      asc: p.name
    )
    |> preload([_vp, p], producer: p)
    |> Repo.all()
  end

  @doc """
  Links a producer to a visual novel.
  """
  def link_producer(visual_novel_id, producer_id, attrs \\ %{}) do
    %VNProducer{}
    |> VNProducer.changeset(
      Map.merge(attrs, %{
        visual_novel_id: visual_novel_id,
        producer_id: producer_id
      })
    )
    |> Repo.insert(on_conflict: :nothing)
  end

  # ============================================================================
  # Relation Queries
  # ============================================================================

  @doc """
  Gets related VNs for a visual novel.
  """
  def get_related_vns(visual_novel_id) do
    Relation
    |> where([vr], vr.visual_novel_id == ^visual_novel_id)
    |> preload(:related_vn)
    |> Repo.all()
  end

  @doc """
  Gets VNs that relate to this one (inverse relations).
  """
  def get_inverse_related_vns(visual_novel_id) do
    Relation
    |> where([vr], vr.related_vn_id == ^visual_novel_id)
    |> preload(:visual_novel)
    |> Repo.all()
  end

  # ============================================================================
  # Tag Queries
  # ============================================================================

  @doc """
  Gets tags for a visual novel.
  """
  def get_vn_tags(visual_novel_id) do
    VNTag
    |> where([vt], vt.visual_novel_id == ^visual_novel_id)
    |> order_by([vt], desc: vt.relevance_score)
    |> preload(:tag)
    |> Repo.all()
  end

  # ============================================================================
  # Image URLs
  # ============================================================================

  @doc """
  Builds image URLs for a visual novel.
  """
  def build_image_urls(%VisualNovel{} = vn) do
    build_image_urls_from_attrs(%{
      primary_image_id: vn.primary_image_id,
      temp_image_url: vn.temp_image_url
    })
  end

  def build_image_urls(%{} = attrs) do
    image_id = Map.get(attrs, :primary_image_id)
    temp_url = Map.get(attrs, :temp_image_url)
    build_image_urls_from_attrs(%{primary_image_id: image_id, temp_image_url: temp_url})
  end

  def build_image_urls(nil), do: %{}

  def build_image_urls(image_id) do
    base_url = "https://images.kaguya.io/visual_novels"

    %{
      small: "#{base_url}/#{image_id}-128w.webp",
      medium: "#{base_url}/#{image_id}-256w.webp",
      large: "#{base_url}/#{image_id}-512w.webp",
      xl: "#{base_url}/#{image_id}-1024w.webp"
    }
  end

  @doc "Returns true if the VN's cover image is NSFW or suggestive."
  def cover_nsfw?(%{is_image_nsfw: nsfw, is_image_suggestive: suggestive}) do
    nsfw || false || (suggestive || false)
  end

  def cover_nsfw?(_), do: false

  defp build_image_urls_from_attrs(%{primary_image_id: image_id, temp_image_url: temp_url}) do
    cond do
      not is_nil(image_id) ->
        build_image_urls(image_id)

      is_binary(temp_url) ->
        build_temp_image_urls(temp_url)

      true ->
        %{}
    end
  end

  defp build_temp_image_urls(url) do
    %{
      small: url,
      medium: url,
      large: url,
      xl: url
    }
  end

  # ============================================================================
  # Character Image URLs
  # ============================================================================

  alias Kaguya.Characters.Character

  @doc """
  Builds image URLs for a character.
  Returns our CDN URLs if primary_image_id exists, otherwise builds VNDB temp URLs.
  """
  def build_character_image_urls(%Character{} = char) do
    build_character_image_urls_from_attrs(%{
      primary_image_id: char.primary_image_id,
      vndb_image_id: char.vndb_image_id
    })
  end

  def build_character_image_urls(%{} = attrs) do
    image_id = Map.get(attrs, :primary_image_id)
    vndb_id = Map.get(attrs, :vndb_image_id)
    build_character_image_urls_from_attrs(%{primary_image_id: image_id, vndb_image_id: vndb_id})
  end

  def build_character_image_urls(nil), do: %{}

  defp build_character_image_urls_from_attrs(%{
         primary_image_id: image_id,
         vndb_image_id: vndb_id
       }) do
    cond do
      not is_nil(image_id) ->
        build_character_cdn_urls(image_id)

      is_binary(vndb_id) and String.length(vndb_id) > 0 ->
        build_vndb_character_image_urls(vndb_id)

      true ->
        %{}
    end
  end

  defp build_character_cdn_urls(image_id) do
    base_url = "https://images.kaguya.io/characters"
    url = "#{base_url}/#{image_id}-240w.webp"

    %{small: url, large: url}
  end

  # VNDB character image URL format: https://s.vndb.org/ch/{last2digits}/{numericId}.jpg
  # vndb_image_id is stored as "ch12345" -> extract "12345" -> last 2 digits "45"
  defp build_vndb_character_image_urls(vndb_image_id) do
    numeric_id = vndb_image_id |> String.replace(~r/^ch/, "")

    case Integer.parse(numeric_id) do
      {num, ""} ->
        last_two = rem(num, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
        url = "https://s.vndb.org/ch/#{last_two}/#{num}.jpg"
        %{small: url, large: url}

      _ ->
        %{}
    end
  end

  # ============================================================================
  # Screenshot URLs
  # ============================================================================

  @doc "Build CDN URLs for a VN screenshot given its UUID."
  def build_screenshot_urls(screenshot_id) do
    base_url = "https://images.kaguya.io/visual_novels/screenshots"

    %{
      small: "#{base_url}/#{screenshot_id}-320w.webp",
      medium: "#{base_url}/#{screenshot_id}-640w.webp",
      large: "#{base_url}/#{screenshot_id}-1280w.webp"
    }
  end

  # ============================================================================
  # Rating Queries
  # ============================================================================

  @doc """
  Lists users who rated a visual novel with a specific rating.
  Returns paginated results with user, rating, rated_at, and optional review.
  """
  def list_users_who_rated_vn(vn_id, rating, cursor, limit) do
    query =
      Rating
      |> join(:inner, [r], u in assoc(r, :user))
      |> join(:left, [r], rev in Review,
        on: rev.user_id == r.user_id and rev.visual_novel_id == ^vn_id
      )
      |> where([r], r.visual_novel_id == ^vn_id and r.rating == ^rating)
      |> order_by([r], desc: r.id)
      |> select([r, u, rev], %{
        user: u,
        rating: r.rating,
        rated_at: r.updated_at,
        review: rev,
        id: r.id
      })

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(query, :id, cursor, limit, :desc)

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  # ============================================================================
  # Version History
  # ============================================================================

  @doc """
  Lists published versions for a VN, newest release_date first. Returns
  `{items, pagination_meta}` from `Kaguya.Pagination`. The computed fields
  (`isLatest` / `isQuickFix` / `daysSincePrevious`) are derived by
  `enrich_versions/1` below.
  """
  def list_published_versions(vn_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)

    Version
    |> where([v], v.visual_novel_id == ^vn_id and v.status == "published")
    |> order_by([v], desc_nulls_last: v.release_date, desc: v.id)
    |> Kaguya.Pagination.paginate(page, page_size)
  end

  @doc """
  Lists pending versions (mod queue), oldest first. Returns the same
  paginated shape as `list_published_versions/2`.
  """
  def list_pending_versions(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 50)

    Version
    |> where([v], v.status == "pending")
    |> order_by([v], asc: v.inserted_at, asc: v.id)
    |> preload(:visual_novel)
    |> Kaguya.Pagination.paginate(page, page_size)
  end

  @doc """
  Loads a version by id. Returns nil when not found.
  """
  def get_vn_version(id), do: Repo.get(Version, id)

  @doc """
  Mod edit — replaces editable content fields on a version row. Status
  flips happen via `approve_vn_version/2` / `reject_vn_version/3`, never
  through this changeset.
  """
  def update_vn_version(%Version{} = version, attrs) do
    Repo.transact(fn ->
      version
      |> Version.mod_edit_changeset(attrs)
      |> Repo.update()
    end)
  end

  @doc "Mod approval — flips status to 'published', stamps reviewer + time."
  def approve_vn_version(%Version{} = version, %{id: user_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    version
    |> Ecto.Changeset.change(%{
      status: "published",
      reviewed_by_user_id: user_id,
      reviewed_at: now
    })
    |> Repo.update()
  end

  @doc "Mod rejection — flips status to 'rejected', stamps reviewer + time + notes."
  def reject_vn_version(%Version{} = version, %{id: user_id}, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    version
    |> Ecto.Changeset.change(%{
      status: "rejected",
      reviewed_by_user_id: user_id,
      reviewed_at: now,
      review_notes: reason
    })
    |> Repo.update()
  end

  @doc """
  Adds the computed display fields (`is_latest`, `is_quick_fix`,
  `days_since_previous`) to a list of `Version` structs. The list is
  expected to already be ordered by `release_date DESC` (which
  `list_published_versions/2` produces).

  `is_quick_fix` threshold: <= 7 days since previous version AND
  `update_type == "bugfix"`.
  """
  @quick_fix_window_days 7

  def enrich_versions([]), do: []

  def enrich_versions(versions) do
    latest_date =
      versions
      |> Enum.map(& &1.release_date)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        dates -> Enum.max(dates, DateTime)
      end

    # versions are ordered newest-first; "previous" version of v[i] is v[i+1].
    versions
    |> Enum.with_index()
    |> Enum.map(fn {v, idx} ->
      previous = Enum.at(versions, idx + 1)
      days = days_between(v.release_date, previous && previous.release_date)

      %{
        version: v,
        is_latest: v.release_date != nil and v.release_date == latest_date,
        is_quick_fix:
          v.update_type == "bugfix" and days != nil and days <= @quick_fix_window_days,
        days_since_previous: days
      }
    end)
  end

  defp days_between(_current, nil), do: nil
  defp days_between(nil, _previous), do: nil

  defp days_between(%DateTime{} = current, %DateTime{} = previous) do
    DateTime.diff(current, previous, :second) |> div(86_400)
  end

  # ============================================================================
  # Edit / Revision Support
  # ============================================================================

  @doc """
  Loads a visual novel with associations needed for snapshotting.
  Returns nil if not found.
  """
  def get_for_edit(id) do
    case Repo.get(VisualNovel, id) do
      nil ->
        nil

      vn ->
        Repo.preload(vn, [:vn_titles, :vn_relations, :vn_screenshots, :vn_images, :external_links])
    end
  end

  @doc """
  Batch-loads multiple visual novels with the same preload set as
  `get_for_edit/1`. Used by the bulk revision writer to snapshot many
  entities in a single round-trip per preload instead of one per entity.
  """
  def batch_load_for_hist(ids) when is_list(ids) do
    from(v in VisualNovel, where: v.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:vn_titles, :vn_relations, :vn_screenshots, :vn_images, :external_links])
  end

  @doc """
  Creates a new visual novel from user input.
  Called by `Revisions.create_entity/4` inside a transaction.
  """
  def create_from_edit(attrs) do
    attrs = maybe_derive_title(attrs)

    with {:ok, vn} <- %VisualNovel{} |> VisualNovel.changeset(attrs) |> Repo.insert(),
         :ok <- sync_titles(vn, attrs),
         :ok <- sync_relations(vn, attrs),
         :ok <- sync_external_links(vn, attrs),
         :ok <- sync_vn_producers(vn, attrs) do
      reindex_search(vn.id)
      {:ok, vn}
    end
  end

  defp maybe_derive_title(%{title: title} = attrs) when is_binary(title) and title != "",
    do: attrs

  defp maybe_derive_title(attrs) do
    titles = Map.get(attrs, :titles, [])
    olang = Map.get(attrs, :original_language)

    main = if olang, do: Enum.find(titles, fn t -> t.lang == olang end)
    main = main || List.first(titles)

    case main do
      nil -> attrs
      t -> Map.put(attrs, :title, Map.get(t, :latin) || t.title)
    end
  end

  @doc """
  Applies edit changes to a visual novel and its related titles/relations.
  Called by `Revisions.submit_edit/6` inside a transaction.
  """
  def apply_edit(vn, changes) do
    with {:ok, vn} <- update_vn_fields(vn, changes),
         :ok <- sync_titles(vn, changes),
         :ok <- sync_relations(vn, changes),
         :ok <- sync_screenshots(vn, changes),
         :ok <- sync_covers(vn, changes),
         :ok <- sync_external_links(vn, changes),
         :ok <- sync_vn_producers(vn, changes),
         :ok <- set_primary_cover_from_edit(vn, changes),
         :ok <- remove_screenshots(vn, changes),
         :ok <- remove_covers(vn, changes) do
      reindex_search(vn.id)
      {:ok, vn}
    end
  end

  @edit_scalar_fields ~w(title description development_status length_category
                         original_language release_date min_age has_ero is_avn
                         title_category aliases)a

  defp update_vn_fields(vn, changes) do
    attrs = Map.take(changes, @edit_scalar_fields)

    if attrs == %{} do
      {:ok, vn}
    else
      vn
      |> VisualNovel.changeset(attrs)
      |> Repo.update()
    end
  end

  defp sync_titles(vn, changes) do
    case Map.get(changes, :titles) do
      nil ->
        :ok

      titles when is_list(titles) ->
        from(t in VNTitle, where: t.visual_novel_id == ^vn.id) |> Repo.delete_all()

        rows =
          Enum.map(titles, fn t ->
            %{
              id: UUIDv7.generate(),
              visual_novel_id: vn.id,
              lang: t.lang,
              title: t.title,
              latin: Map.get(t, :latin),
              official: Map.get(t, :official, true)
            }
          end)

        if rows != [], do: Repo.insert_all(VNTitle, rows)

        # Derive display title from original_language title (same as VNDB's olang logic)
        olang = Map.get(changes, :original_language) || vn.original_language
        derive_display_title(vn, titles, olang)
        :ok
    end
  end

  defp derive_display_title(_vn, _titles, nil), do: :ok

  defp derive_display_title(vn, titles, olang) do
    main = Enum.find(titles, fn t -> t.lang == olang end) || List.first(titles)

    if main do
      display = Map.get(main, :latin) || main.title

      if display && display != vn.title do
        vn |> VisualNovel.changeset(%{title: display}) |> Repo.update()
      end
    end
  end

  defp sync_relations(vn, changes) do
    case Map.get(changes, :relations) do
      nil ->
        :ok

      relations when is_list(relations) ->
        vn_ids = Enum.map(relations, & &1.related_vn_id) |> Enum.uniq()

        existing =
          from(v in VisualNovel, where: v.id in ^vn_ids, select: v.id)
          |> Repo.all()
          |> MapSet.new()

        missing = Enum.reject(vn_ids, &MapSet.member?(existing, &1))

        if missing != [] do
          {:error, "Related visual novel(s) not found: #{Enum.join(missing, ", ")}"}
        else
          replace_vn_relations(vn.id, relations)
          :ok
        end
    end
  end

  # Reciprocal relation_type pairs. VN relations are symmetric — when A says
  # "B is my sequel", B's record gets "A is my prequel". `alternative`,
  # `same_setting`, `shares_characters`, `same_series` are mutual (their own
  # reciprocal). DB constraint allows `original`, even though the user-facing
  # edit form doesn't list it as a selectable option — it's only ever written
  # as the reverse of `fandisc`.
  @reciprocal_types %{
    "sequel" => "prequel",
    "prequel" => "sequel",
    "fandisc" => "original",
    "original" => "fandisc",
    "side_story" => "parent_story",
    "parent_story" => "side_story",
    "alternative" => "alternative",
    "same_setting" => "same_setting",
    "shares_characters" => "shares_characters",
    "same_series" => "same_series"
  }

  defp reciprocal_relation_type(type), do: Map.get(@reciprocal_types, type, type)

  # Replaces vn_id's outgoing relations and keeps the reverse side in sync.
  #
  # Symmetric model: editing VN A's relations is editing the relation between
  # A and B in both directions. If the user removes B from A's list, B's row
  # (B → A) is also deleted. If the user adds C, both A → C and C → A are
  # written (forward and reverse). For pairs already present on both sides,
  # the reverse row is updated to match the new relation_type / is_official.
  #
  # `relations` is a list of maps with at least :related_vn_id, :relation_type,
  # and optionally :is_official.
  #
  # Public so `Kaguya.Revisions.Hist.VisualNovel.apply_hist/2` can re-use the
  # same symmetric-replace logic when restoring a revision.
  @doc false
  def replace_vn_relations(vn_id, relations) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Capture the current outgoing related VN ids, then compute the set the
    # user removed so we can clean up reverse rows.
    old_related_ids =
      from(r in Relation,
        where: r.visual_novel_id == ^vn_id,
        select: r.related_vn_id
      )
      |> Repo.all()
      |> MapSet.new()

    new_related_ids = MapSet.new(Enum.map(relations, & &1.related_vn_id))
    removed_ids = MapSet.difference(old_related_ids, new_related_ids) |> MapSet.to_list()

    # Delete the reverse rows for relations the user just removed.
    if removed_ids != [] do
      from(r in Relation,
        where: r.visual_novel_id in ^removed_ids and r.related_vn_id == ^vn_id
      )
      |> Repo.delete_all()
    end

    # Replace forward.
    from(r in Relation, where: r.visual_novel_id == ^vn_id) |> Repo.delete_all()

    forward_rows =
      Enum.map(relations, fn r ->
        %{
          visual_novel_id: vn_id,
          related_vn_id: r.related_vn_id,
          relation_type: r.relation_type,
          is_official: Map.get(r, :is_official, true),
          inserted_at: now,
          updated_at: now
        }
      end)

    if forward_rows != [], do: Repo.insert_all(Relation, forward_rows)

    # Upsert reverse rows. ON CONFLICT updates relation_type/is_official so
    # B's view stays consistent with A's edit when both sides existed already.
    reverse_rows =
      Enum.map(relations, fn r ->
        %{
          visual_novel_id: r.related_vn_id,
          related_vn_id: vn_id,
          relation_type: reciprocal_relation_type(r.relation_type),
          is_official: Map.get(r, :is_official, true),
          inserted_at: now,
          updated_at: now
        }
      end)

    if reverse_rows != [] do
      Repo.insert_all(Relation, reverse_rows,
        on_conflict: {:replace, [:relation_type, :is_official, :updated_at]},
        conflict_target: [:visual_novel_id, :related_vn_id]
      )
    end

    :ok
  end

  defp sync_external_links(vn, changes) do
    case Map.get(changes, :external_links) do
      nil ->
        :ok

      links when is_list(links) ->
        sites = Enum.map(links, & &1.site)

        if length(Enum.uniq(sites)) == length(sites) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          from(l in VnExternalLink, where: l.vn_id == ^vn.id) |> Repo.delete_all()

          rows =
            Enum.map(links, fn l ->
              %{vn_id: vn.id, site: l.site, value: l.value, inserted_at: now, updated_at: now}
            end)

          if rows != [], do: Repo.insert_all(VnExternalLink, rows)

          :ok
        else
          {:error, "Duplicate site entries in external_links"}
        end
    end
  end

  # List-replace: the supplied `producers` list becomes the canonical set of
  # vn_producers rows for the VN. `role` defaults to "developer" when omitted —
  # for user-created entries the dev is almost always the self-publisher, and
  # this matches the developer-first selection convention in Producers.primary_for_vn.
  defp sync_vn_producers(vn, changes) do
    case Map.get(changes, :producers) do
      nil ->
        :ok

      producers when is_list(producers) ->
        producer_ids = Enum.map(producers, & &1.producer_id)

        if length(Enum.uniq(producer_ids)) == length(producer_ids) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          from(p in VNProducer, where: p.visual_novel_id == ^vn.id) |> Repo.delete_all()

          rows =
            Enum.map(producers, fn p ->
              %{
                visual_novel_id: vn.id,
                producer_id: p.producer_id,
                role: Map.get(p, :role) || "developer",
                inserted_at: now,
                updated_at: now
              }
            end)

          if rows != [], do: Repo.insert_all(VNProducer, rows)

          :ok
        else
          {:error, "Duplicate producer entries"}
        end
    end
  end

  defp set_primary_cover_from_edit(vn, %{primary_cover_id: cover_id}) when not is_nil(cover_id) do
    Kaguya.Covers.set_primary_cover(vn.id, cover_id)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_primary_cover_from_edit(_vn, _changes), do: :ok

  defp sync_covers(vn, %{covers: covers}) when is_list(covers) and covers != [] do
    # Each entry: %{cover_id: ..., is_image_nsfw: ..., is_image_suggestive: ..., language: ..., release_date: ...}
    current_ids =
      from(i in Kaguya.VisualNovels.Image, where: i.visual_novel_id == ^vn.id, select: i.id)
      |> Repo.all()
      |> MapSet.new()

    for entry <- covers, MapSet.member?(current_ids, entry.cover_id) do
      updates =
        entry
        |> Map.take([:is_image_nsfw, :is_image_suggestive, :language, :release_date])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      if updates != [] do
        from(i in Kaguya.VisualNovels.Image, where: i.id == ^entry.cover_id)
        |> Repo.update_all(set: updates)
      end
    end

    :ok
  end

  defp sync_covers(_vn, _changes), do: :ok

  defp remove_screenshots(_vn, %{removed_screenshot_ids: ids}) when is_list(ids) and ids != [] do
    from(s in Screenshot, where: s.id in ^ids)
    |> Repo.delete_all()

    :ok
  end

  defp remove_screenshots(_vn, _changes), do: :ok

  defp remove_covers(vn, %{removed_cover_ids: ids}) when is_list(ids) and ids != [] do
    from(i in Kaguya.VisualNovels.Image, where: i.id in ^ids and i.visual_novel_id == ^vn.id)
    |> Repo.delete_all()

    :ok
  end

  defp remove_covers(_vn, _changes), do: :ok

  defp sync_screenshots(_vn, %{screenshots: nil}), do: :ok

  defp sync_screenshots(vn, %{screenshots: screenshots}) when is_list(screenshots) do
    # Each entry: %{screenshot_id: ..., is_nsfw: ..., is_brutal: ..., release_id: ...}
    # Only update metadata on screenshots belonging to this VN.
    current_ids =
      from(s in Screenshot, where: s.visual_novel_id == ^vn.id, select: s.id)
      |> Repo.all()
      |> MapSet.new()

    for entry <- screenshots, MapSet.member?(current_ids, entry.screenshot_id) do
      updates =
        entry
        |> Map.take([:is_nsfw, :is_brutal, :release_id])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      if updates != [] do
        from(s in Screenshot, where: s.id == ^entry.screenshot_id)
        |> Repo.update_all(set: updates)
      end
    end

    :ok
  end

  defp sync_screenshots(_vn, _changes), do: :ok

  # ============================================================================
  # Revision _hist — implementation lives in Kaguya.Revisions.Hist.VisualNovel.
  # Delegated here so `Kaguya.Revisions`' @entity_config dispatch
  # (`context.write_hist/2`, `context.apply_hist/2`, …) keeps working
  # without touching the dispatch table.
  # ============================================================================

  defdelegate write_hist(change_id, vn), to: Kaguya.Revisions.Hist.VisualNovel
  defdelegate bulk_write_hist(pairs), to: Kaguya.Revisions.Hist.VisualNovel
  defdelegate load_hist(change_id), to: Kaguya.Revisions.Hist.VisualNovel
  defdelegate bulk_load_hist(change_ids), to: Kaguya.Revisions.Hist.VisualNovel
  defdelegate apply_hist(vn, hist_data), to: Kaguya.Revisions.Hist.VisualNovel
  defdelegate changed_field_groups(vn, changes), to: Kaguya.Revisions.Hist.VisualNovel

  # Public so `Kaguya.Revisions.Hist.VisualNovel.apply_hist/2` can re-use the
  # same Meilisearch reindex path that `apply_edit/2` triggers.
  @doc false
  def reindex_search(vn_id) do
    vn =
      VisualNovel
      |> Repo.get(vn_id)
      |> Repo.preload([:primary_image, :vn_titles, vn_producers: :producer])

    cond do
      is_nil(vn) -> :ok
      vn.hidden_at != nil -> SearchIndex.remove_visual_novel(vn_id)
      true -> SearchIndex.index_visual_novels(vn)
    end
  rescue
    e ->
      require Logger

      Logger.warning(
        "[VisualNovels] Meilisearch reindex failed for VN #{vn_id}: #{Exception.message(e)}"
      )
  end
end
