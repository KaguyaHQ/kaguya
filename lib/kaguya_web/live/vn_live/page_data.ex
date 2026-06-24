defmodule KaguyaWeb.VNLive.PageData do
  @moduledoc """
  View-model assembler for the VN detail page (`KaguyaWeb.VNLive.Show`)
  and its sibling `Similar` LV.

  Composes reads across domain contexts (Reviews, Lists, Discussions,
  Covers, Screenshots, Series, Similarities, VNTags, Shelves, …) and
  shapes the result into render-ready maps (slugs, hrefs, ISO datetimes,
  avatar URLs). Also holds the write commands the page triggers; those
  are slated to move into their domain contexts in a follow-up.

  Lives under `KaguyaWeb.VNLive` because "page" is a web concept: this
  module knows about pagination, sort orders, viewer bundles, and the
  exact field shapes consumed by `vn_live/show/components.ex`. Domain
  contexts in `lib/kaguya/` should stay free of those concerns.

  Pure shape mapping (`normalize_review/1`, `normalize_cover/1`, …)
  lives in `__MODULE__.Normalizer`. Anything that touches the DB stays
  in this module.
  """

  import Ecto.Query

  alias Kaguya.{
    Covers,
    Discussions,
    Lists,
    Repo,
    Reviews,
    Screenshots,
    Series,
    Shelves,
    Similarities,
    VNTags,
    VisualNovels
  }

  alias Kaguya.Reviews.Ratings
  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Releases.Release
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Users
  alias Kaguya.VisualNovels.VNPageCache
  alias __MODULE__.Normalizer

  def get_public_page(slug, viewer \\ nil, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    sort = Keyword.get(opts, :sort, :most_liked)

    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(viewer)) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn, build_public_page(vn, viewer, page, sort)}
    end
  end

  @doc """
  Re-fetches just the reviews slice for the VN page: the paginated
  reviews list plus the denormalized VN counters that change when a
  review is added or removed (`reviews_count`, `average_rating`,
  `ratings_count`, `ratings_dist`).

  Use this — not `get_public_page/3` — from LV handlers that mutate a
  single review. Refreshing only the slice that actually changed
  avoids ~20 DB queries for sections (discussions, characters,
  covers, recommendations, …) that a one-review write cannot affect.
  """
  def get_reviews_page(slug, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    sort = Keyword.get(opts, :sort, :most_liked)

    with {:ok, vn} <- require_vn(slug) do
      {:ok, reviews} =
        Reviews.list_public_reviews_by_vn_id(vn.id, %{
          page: page,
          page_size: 10,
          sort_by: sort
        })

      reviews = %{reviews | items: Repo.preload(reviews.items, :user)}

      {:ok,
       %{
         reviews: Normalizer.normalize_reviews(reviews),
         counters: %{
           reviews_count: vn.reviews_count || 0,
           average_rating: vn.average_rating,
           ratings_count: vn.ratings_count || 0,
           ratings_dist: Kaguya.RatingDistribution.convert_ratings_dist(vn.ratings_dist)
         }
       }}
    end
  end

  def get_viewer_bundle(slug, %{id: _} = viewer) when is_binary(slug) do
    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(viewer)) do
      nil -> {:error, :not_found}
      vn -> {:ok, build_viewer_bundle(vn, viewer)}
    end
  end

  def get_tab(slug_or_vn, tab, viewer, filters \\ %{})

  def get_tab(slug_or_vn, :covers, viewer, _filters) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      viewer_id = viewer && viewer.id
      {:ok, covers} = Covers.list_covers_for_vn(vn.id, viewer_id)
      {:ok, Enum.map(covers, &Normalizer.normalize_cover/1)}
    end
  end

  def get_tab(slug_or_vn, :screenshots, viewer, _filters) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      viewer_id = viewer && viewer.id
      {:ok, screenshots} = Screenshots.list_screenshots_for_vn(vn.id, viewer_id)
      {:ok, Enum.map(screenshots, &Normalizer.normalize_screenshot/1)}
    end
  end

  def get_tab(slug_or_vn, :quotes, viewer, _filters) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      viewer_id = viewer && viewer.id

      {:ok,
       vn.id
       |> Kaguya.Characters.Quotes.list_quotes_for_vn(user_id: viewer_id)
       |> Enum.map(&Normalizer.normalize_quote/1)}
    end
  end

  def get_tab(slug_or_vn, :releases, viewer, filters) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      filter_options = release_filter_options_for_vn(vn.id)
      filters = normalize_release_filters(filters, filter_options)

      {:ok,
       %{
         items: Enum.map(releases_for_vn(vn.id, filters), &Normalizer.normalize_release/1),
         filter_options: filter_options,
         filters: filters
       }}
    end
  end

  def get_tab(slug_or_vn, :tags, viewer, _filters) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      {:ok, tags_for_vn(vn.id)}
    end
  end

  def get_tab(_slug_or_vn, _tab, _viewer, _filters), do: {:error, :not_found}

  def get_discussions(slug_or_vn, viewer) do
    with {:ok, vn} <- resolve_vn(slug_or_vn, viewer) do
      viewer_id = viewer && viewer.id

      {:ok, discussions} =
        Discussions.list_posts_for_entity(:visual_novel, vn.id, %{viewer_id: viewer_id, limit: 5})

      discussions = %{discussions | items: Repo.preload(discussions.items, :user)}

      {:ok, Normalizer.normalize_discussions(discussions.items)}
    end
  end

  @doc """
  Same as `get_viewer_bundle/2` but skips the slug→VN lookup when the
  caller already has the VN struct (e.g. `VNLive.Show.handle_params/3`
  loads it via `get_public_page/3`, then asks for the viewer bundle on
  the same VN — no need to look it up again).
  """
  # First-paint async path: returns ONLY the controls-critical part
  # (viewer + viewer_vn). Friend activity/reviews are fetched separately via
  # `friends_for_vn/2` so the sidebar controls don't wait on social queries
  # they don't need. See `maybe_start_friends_async` in the LiveView.
  def viewer_bundle_for_vn(%{id: _} = vn, %{id: user_id} = viewer) do
    {:ok,
     %{
       viewer: Normalizer.normalize_user(viewer),
       viewer_vn: build_viewer_vn(vn, user_id),
       my_votes: build_my_votes(vn, user_id)
     }}
  end

  # The viewer's own tag/recommendation votes, pulled out of the public core
  # so that core can be cached viewer-independently (Phase 2a). These overlay
  # the vote-less core in `show/data.ex` (`assign_viewer_bundle`) once the
  # first-paint bundle lands, restoring the per-viewer vote highlights.
  # Two independent reads → run them concurrently.
  defp build_my_votes(vn, user_id) do
    [tag_votes, recommendation_votes] =
      Task.await_many([
        Task.async(fn -> VNTags.user_votes_for_vn(user_id, vn.id) end),
        Task.async(fn -> Similarities.user_votes_for_vn(vn, user_id) end)
      ])

    %{tags: tag_votes, recommendations: recommendation_votes}
  end

  # The friend (social) slice of the page, loaded on its own async so it can
  # stream in after the controls have already hydrated.
  def friends_for_vn(%{id: vn_id}, %{id: user_id}) do
    [friend_activity, friend_reviews] =
      Task.await_many([
        Task.async(fn -> friend_activity(vn_id, user_id) end),
        Task.async(fn -> friend_reviews(vn_id, user_id) end)
      ])

    {:ok, %{friend_activity: friend_activity, friend_reviews: friend_reviews}}
  end

  # Full bundle (controls + friends) for the post-interaction mutation paths
  # (`get_viewer_bundle`), where everything is needed in one shot.
  defp build_viewer_bundle(vn, %{id: user_id} = viewer) do
    %{
      viewer: Normalizer.normalize_user(viewer),
      viewer_vn: build_viewer_vn(vn, user_id),
      friend_activity: friend_activity(vn.id, user_id),
      friend_reviews: friend_reviews(vn.id, user_id)
    }
  end

  def get_similar_page(slug, viewer \\ nil, opts \\ []) do
    limit = Keyword.get(opts, :limit, 72)
    viewer_id = viewer && viewer.id
    allowed = Kaguya.VisualNovels.TitleCategory.allowed_categories(viewer || %{})

    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(viewer)) do
      nil ->
        {:error, :not_found}

      vn ->
        {:ok,
         %{
           vn: normalize_vn(vn),
           recommendations:
             Normalizer.normalize_recommendations(
               Similarities.list_similar_vns_with_votes(vn,
                 limit: limit,
                 user_id: viewer_id,
                 allowed_categories: allowed
               )
             )
         }}
    end
  end

  def set_reading_status(slug, %{id: user_id} = viewer, status) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, status} <- reading_status_atom(status),
         {:ok, _} <-
           Shelves.set_reading_status(user_id, vn.id, %{
             status: status
           }) do
      # Reading status feeds the public core's readers/want-to-read rosters
      # and counts, so the cached core must be dropped.
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def clear_reading_status(slug, %{id: user_id} = viewer) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, _} <- Shelves.delete_reading_status(user_id, vn.id) do
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def set_rating(slug, %{id: user_id} = viewer, rating) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, _} <- upsert_rating(user_id, vn.id, rating) do
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def clear_rating(slug, %{id: user_id} = viewer) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, _} <- Ratings.delete_rating(vn.id, user_id) do
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def toggle_review_like(review_id, liked?, %{id: user_id}) do
    with {:ok, _} <-
           if(liked?,
             do: Reviews.unlike_review(review_id, user_id),
             else: Reviews.like_review(review_id, user_id)
           ),
         {:ok, review} <- Reviews.get_review(review_id) do
      {:ok, %{id: review.id, likes_count: review.likes_count || 0, liked_by_me: !liked?}}
    end
  end

  def save_review(slug, %{id: user_id} = viewer, attrs) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, existing} <- Reviews.get_review_by_vn_and_user(vn.id, user_id),
         {:ok, _log} <- save_log_state(user_id, vn.id, attrs),
         {:ok, _review} <- maybe_upsert_review(existing, user_id, vn.id, attrs) do
      # Touches the cached reviews slice, review/rating counters, and (via the
      # log's reading status) the readers rosters.
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def delete_review(slug, %{id: user_id} = viewer, review_id) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, _deleted} <- Reviews.delete_review(review_id, user_id) do
      VNPageCache.invalidate(vn.id)
      get_viewer_bundle(slug, viewer)
    end
  end

  def list_shelves_for_user(%{id: user_id}) do
    with {:ok, shelves} <- Shelves.list_shelves_for_user(user_id) do
      {:ok, Enum.map(shelves, &Normalizer.normalize_shelf/1)}
    end
  end

  def save_shelves_for_vn(slug, %{id: user_id} = viewer, shelf_ids) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, current_shelves} <- Shelves.list_user_shelves_for_vn(user_id, vn.id) do
      current_ids = MapSet.new(Enum.map(current_shelves, & &1.id))
      next_ids = MapSet.new(shelf_ids)
      add_ids = MapSet.difference(next_ids, current_ids) |> MapSet.to_list()
      remove_ids = MapSet.difference(current_ids, next_ids) |> MapSet.to_list()

      with {:ok, _} <- maybe_add_to_shelves(user_id, add_ids, [vn.id]),
           {:ok, _} <- maybe_remove_from_shelves(user_id, remove_ids, [vn.id]) do
        get_viewer_bundle(slug, viewer)
      end
    end
  end

  def create_shelf_for_vn(slug, %{id: user_id} = viewer, name) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, shelf} <- Shelves.create_shelf(%{user_id: user_id, name: String.trim(name)}),
         {:ok, _} <- Shelves.add_vns_to_shelves(user_id, [shelf.id], [vn.id]) do
      get_viewer_bundle(slug, viewer)
    end
  end

  def vote_recommendation(slug, %{id: user_id} = viewer, similar_vn_id, vote, opts \\ []) do
    with {:ok, vn} <- require_vn(slug),
         :ok <- require_can_edit(viewer),
         {:ok, _} <- apply_similarity_vote(vn.id, similar_vn_id, user_id, vote) do
      refresh_recommendations(vn, viewer, opts)
    end
  end

  def add_recommendation(slug, %{id: user_id} = viewer, similar_slug, opts \\ []) do
    with {:ok, vn} <- require_vn(slug),
         :ok <- require_can_edit(viewer),
         {:ok, similar_vn} <- require_vn(String.trim(similar_slug)),
         true <- vn.id != similar_vn.id || {:error, :same_visual_novel},
         {:ok, _} <- Similarities.create_vn_similarity(vn.id, similar_vn.id, user_id) do
      refresh_recommendations(vn, viewer, opts)
    end
  end

  def add_recommendation_by_id(slug, %{id: user_id} = viewer, similar_vn_id, opts \\ []) do
    with {:ok, vn} <- require_vn(slug),
         :ok <- require_can_edit(viewer),
         {:ok, similar_vn} <- require_vn_by_id(similar_vn_id),
         true <- vn.id != similar_vn.id || {:error, :same_visual_novel},
         {:ok, _} <- Similarities.create_vn_similarity(vn.id, similar_vn.id, user_id) do
      refresh_recommendations(vn, viewer, opts)
    end
  end

  def vote_tag(slug, %{id: user_id} = viewer, tag_id, value) do
    with {:ok, vn} <- require_vn(slug),
         :ok <- require_can_edit(viewer),
         {:ok, value} <- tag_vote_value(value),
         {:ok, _} <- VNTags.vote_vn_tag(user_id, vn.id, tag_id, value) do
      refresh_tags(vn.id, user_id)
    end
  end

  def search_tag_candidates(_slug, viewer, query, exclude_ids \\ []) do
    with :ok <- require_can_edit(viewer) do
      VNTags.search_tag_candidates(query, exclude_ids, 15)
    end
  end

  def clear_tag_vote(slug, %{id: user_id} = viewer, tag_id) do
    with {:ok, vn} <- require_vn(slug),
         :ok <- require_can_edit(viewer),
         {:ok, _} <- VNTags.clear_vn_tag_vote(user_id, vn.id, tag_id) do
      refresh_tags(vn.id, user_id)
    end
  end

  def search_recommendation_candidates(slug, viewer, query) do
    trimmed = String.trim(query || "")

    if String.length(trimmed) < 2 do
      {:ok, []}
    else
      allowed = Kaguya.VisualNovels.TitleCategory.allowed_categories(viewer || %{})
      opts = recommendation_search_opts(allowed)

      with {:ok, current_vn} <- require_vn(slug),
           {:ok, %{items: items}} <- VisualNovels.search_visual_novels(trimmed, 1, 8, opts) do
        {:ok,
         items
         |> Enum.reject(&(to_string(&1.id) == to_string(current_vn.id)))
         |> Enum.map(&Normalizer.normalize_search_result/1)}
      end
    end
  end

  def toggle_cover_like(cover_id, liked?, %{id: user_id}) do
    if liked?,
      do: Covers.unlike_cover(cover_id, user_id),
      else: Covers.like_cover(cover_id, user_id)
  end

  def toggle_screenshot_like(screenshot_id, liked?, %{id: user_id}) do
    if liked?,
      do: Screenshots.unlike_screenshot(screenshot_id, user_id),
      else: Screenshots.like_screenshot(screenshot_id, user_id)
  end

  def toggle_quote_like(quote_id, liked?, %{id: user_id}) do
    if liked?,
      do: Kaguya.Characters.Quotes.unlike_quote(quote_id, user_id),
      else: Kaguya.Characters.Quotes.like_quote(quote_id, user_id)
  end

  def create_quote(slug, %{id: user_id}, text, character_id \\ nil) do
    with {:ok, vn} <- require_vn(slug),
         {:ok, quote} <-
           Kaguya.Characters.Quotes.create_quote(%{
             visual_novel_id: vn.id,
             character_id: blank_to_nil(character_id),
             quote: String.trim(text),
             created_by: user_id
           }) do
      {:ok, Normalizer.normalize_quote(quote)}
    end
  end

  # The public VN page core. Cached because it carries no per-user state:
  # tag/recommendation vote highlights and the viewer's private lists are
  # *not* baked in — they hydrate via the `:vn_viewer` async bundle
  # (`my_votes`, built by `build_my_votes/2`). What remains varies only by
  # content prefs (`allowed`) and mod visibility (`privileged?`), both bounded
  # (~4 pref combos × 2), so a handful of entries per VN serve every viewer.
  # This is an origin-side cache; a LiveView page can't carry `s-maxage`. See
  # docs/migrations/nextjs-liveview/plans/vn-page-performance-plan.md.
  defp build_public_page(vn, viewer, page, sort) do
    allowed = Kaguya.VisualNovels.TitleCategory.allowed_categories(viewer || %{})
    privileged? = privileged?(viewer)
    key = {:vn_page, vn.id, page, sort, allowed, privileged?}

    VNPageCache.fetch(key, fn -> build_public_page_payload(vn, allowed, page, sort) end)
  end

  defp build_public_page_payload(vn, allowed, page, sort) do
    # Intentionally nil: the cached core is viewer-independent, so per-user
    # vote highlights and private lists are dropped here and hydrate via the
    # viewer bundle's `my_votes`.
    viewer_id = nil

    {:ok, reviews} =
      Reviews.list_public_reviews_by_vn_id(vn.id, %{page: page, page_size: 10, sort_by: sort})

    reviews = %{reviews | items: Repo.preload(reviews.items, :user)}

    {:ok, lists} = Lists.list_lists_for_vn(vn, nil, 3, viewer_id, allowed_categories: allowed)
    lists = %{lists | items: Repo.preload(lists.items, :user)}

    list_vns =
      lists.items
      |> Enum.map(&{&1.id, &1.vns_count || 0})
      |> Lists.batch_list_vns_for_lists(5)

    %{
      vn: normalize_vn(vn),
      reviews: Normalizer.normalize_reviews(reviews),
      characters: characters_for_vn(vn.id),
      series: normalize_series(Series.get_series_for_vn(vn.id)),
      related: Normalizer.normalize_relations(public_similar_relations(vn.id)),
      recommendations:
        Normalizer.normalize_recommendations(
          Similarities.list_similar_vns_with_votes(vn,
            limit: 10,
            user_id: viewer_id,
            allowed_categories: allowed
          )
        ),
      popular_lists:
        Enum.map(lists.items, &Normalizer.normalize_list(&1, Map.get(list_vns, &1.id)))
    }
  end

  defp build_viewer_vn(vn, user_id) do
    # These five reads are independent, so fan them out concurrently rather
    # than paying five sequential round-trips. Runs inside the `:vn_viewer`
    # async task; in tests the sandbox is in shared mode (ConnCase,
    # async: false), so the spawned tasks share the checked-out connection.
    [
      {:ok, my_rating},
      {:ok, my_reading_status},
      {:ok, my_review_likes},
      {:ok, my_shelves},
      my_review
    ] =
      Task.await_many([
        Task.async(fn -> Ratings.get_user_rating(vn.id, user_id) end),
        Task.async(fn -> Shelves.get_reading_status(user_id, vn.id) end),
        Task.async(fn -> Reviews.liked_review_ids_for_vn_id(user_id, vn.id) end),
        Task.async(fn -> Shelves.list_user_shelves_for_vn(user_id, vn.id) end),
        Task.async(fn -> Reviews.get_review_by_vn_and_user(vn.id, user_id) end)
      ])

    my_shelves = unwrap_ok(my_shelves)

    %{
      my_rating: my_rating,
      my_reading_status: Normalizer.normalize_reading_status(my_reading_status),
      my_review: Normalizer.normalize_my_review(my_review),
      my_shelves: Enum.map(my_shelves, &Normalizer.normalize_shelf/1),
      my_review_likes: my_review_likes,
      average_rating: vn.average_rating,
      ratings_count: vn.ratings_count,
      ratings_dist: Kaguya.RatingDistribution.convert_ratings_dist(vn.ratings_dist)
    }
  end

  defp viewer_opts(%{role: role}) when role in [:moderator, :admin], do: [include_hidden: true]
  defp viewer_opts(_), do: []

  # Whether the viewer sees hidden content. A cache-key dimension for the
  # public core (`build_public_page`) so a mod's view never leaks into a
  # regular user's cached entry, and vice versa.
  defp privileged?(%{role: role}) when role in [:moderator, :admin], do: true
  defp privileged?(_), do: false

  defp require_vn(slug) do
    case VisualNovels.get_visual_novel_by_slug(slug) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp require_vn_by_id(id) do
    case VisualNovels.get_visual_novel(id) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp resolve_vn(%{id: _} = vn, _viewer), do: {:ok, vn}

  defp resolve_vn(slug, viewer) when is_binary(slug) do
    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(viewer)) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp upsert_rating(user_id, vn_id, rating) do
    case Ratings.get_user_rating(vn_id, user_id) do
      {:ok, nil} -> Ratings.create_rating(user_id, vn_id, rating)
      {:ok, _existing} -> Ratings.update_rating(vn_id, user_id, rating)
      other -> other
    end
  end

  # The "VN itself" view-model. Stays in PageData because it orchestrates
  # 8 sub-queries (readers/want_to_read counts and rosters, featured
  # screenshot lookup, producers, tags, available-on links) — all of
  # which are real DB work, not pure shape mapping.
  #
  # Viewer-independent by construction: it carries NO per-viewer state, so the
  # cached public core is safe to share across users. The viewer's own tag
  # votes are overlaid separately (`Data.overlay_tag_votes/2`); this payload
  # never bakes `my_vote` in. See docs/architecture/liveview-render-staging.md.
  defp normalize_vn(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      description: vn.description || "",
      release_date: vn.release_date && Date.to_iso8601(vn.release_date),
      average_rating: vn.average_rating,
      ratings_count: vn.ratings_count || 0,
      ratings_dist: Kaguya.RatingDistribution.convert_ratings_dist(vn.ratings_dist),
      reviews_count: vn.reviews_count || 0,
      readers_count: readers_count(vn.id),
      want_to_read_count: want_to_read_count(vn.id),
      readers: Normalizer.normalize_users(readers(vn.id)),
      want_to_readers: Normalizer.normalize_users(want_to_readers(vn.id)),
      length_category: vn.length_category,
      length_minutes: vn.length_minutes,
      vndb_url: if(vn.vndb_id, do: "https://vndb.org/#{vn.vndb_id}"),
      images: VisualNovels.build_image_urls(vn),
      has_ero: VisualNovels.cover_nsfw?(vn),
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive,
      featured_screenshot: featured_screenshot_payload(vn.featured_screenshot_id),
      producers:
        Enum.map(VisualNovels.get_vn_producers(vn.id), &Normalizer.normalize_vn_producer/1),
      tags: tags_for_vn(vn.id),
      available_on_links:
        Kaguya.Releases.batch_load_available_on_links(nil, [vn.id]) |> Map.get(vn.id, []),
      content_score: vn.content_score,
      is_hidden: not is_nil(vn.hidden_at),
      is_locked: vn.is_locked
    }
  end

  # Backdrop renderer needs `is_nsfw` / `is_brutal` so it can suppress
  # the hero when the viewer's screenshot preferences would hide that
  # screenshot. Featured screenshots are rare on any given VN, so the
  # single tiny lookup costs less than threading the whole screenshot
  # row through normalize_public_vn.
  defp featured_screenshot_payload(nil), do: %{}

  defp featured_screenshot_payload(screenshot_id) do
    flags =
      case Repo.get(Kaguya.Screenshots.Screenshot, screenshot_id) do
        nil -> %{is_nsfw: false, is_brutal: false}
        s -> %{is_nsfw: !!s.is_nsfw, is_brutal: !!s.is_brutal}
      end

    screenshot_id
    |> VisualNovels.build_screenshot_urls()
    |> Map.merge(flags)
  end

  # Stays in PageData because `series_entries/1` is a DB call.
  defp normalize_series(nil), do: nil

  defp normalize_series(series),
    do: %{id: series.id, slug: series.slug, name: series.name, entries: series_entries(series.id)}

  # Builds the VN page's "Related" section. Filters out unofficial relations,
  # self-references, and prequel/sequel entries (those belong in the series
  # "More" section). Also drops any extra relation pointing at a VN that's
  # already covered by a prequel/sequel link.
  defp public_similar_relations(vn_id) do
    official_non_self =
      vn_id
      |> VisualNovels.get_related_vns()
      |> Enum.filter(&(&1.is_official == true))
      |> Enum.reject(fn r -> r.related_vn && r.related_vn.id == vn_id end)

    more_ids =
      official_non_self
      |> Enum.filter(&(&1.relation_type in ["prequel", "sequel"]))
      |> Enum.map(& &1.related_vn.id)
      |> MapSet.new()

    official_non_self
    |> Enum.reject(
      &(&1.relation_type in ["prequel", "sequel"] or MapSet.member?(more_ids, &1.related_vn.id))
    )
  end

  defp unwrap_ok({:ok, value}), do: value
  defp unwrap_ok(value), do: value

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp upsert_review(nil, user_id, vn_id, attrs),
    do: Reviews.create_review(user_id, vn_id, review_attrs(attrs))

  defp upsert_review(review, user_id, _vn_id, attrs),
    do: Reviews.update_review(review.id, user_id, review_attrs(attrs))

  defp maybe_upsert_review(nil, user_id, vn_id, attrs) do
    if present?(attrs["content"] || attrs[:content]) do
      upsert_review(nil, user_id, vn_id, attrs)
    else
      {:ok, nil}
    end
  end

  defp maybe_upsert_review(review, user_id, vn_id, attrs) do
    if present?(attrs["content"] || attrs[:content]) do
      upsert_review(review, user_id, vn_id, attrs)
    else
      {:ok, review}
    end
  end

  defp save_log_state(user_id, vn_id, attrs) do
    with {:ok, _rating} <- maybe_save_rating(user_id, vn_id, attrs["rating"] || attrs[:rating]) do
      maybe_save_status(user_id, vn_id, attrs)
    end
  end

  defp maybe_save_rating(user_id, vn_id, nil), do: maybe_clear_rating(user_id, vn_id)
  defp maybe_save_rating(user_id, vn_id, ""), do: maybe_clear_rating(user_id, vn_id)

  defp maybe_save_rating(user_id, vn_id, value) do
    case Float.parse(to_string(value)) do
      {rating, ""} -> upsert_rating(user_id, vn_id, rating)
      _ -> {:error, :invalid_rating}
    end
  end

  defp maybe_clear_rating(user_id, vn_id) do
    case Ratings.get_user_rating(vn_id, user_id) do
      {:ok, nil} -> {:ok, true}
      {:ok, _rating} -> Ratings.delete_rating(vn_id, user_id)
      error -> error
    end
  end

  defp maybe_save_status(user_id, vn_id, attrs) do
    with {:ok, status} <- reading_status_atom(attrs["status"] || attrs[:status] || "READ") do
      Shelves.set_reading_status(user_id, vn_id, %{
        status: status,
        date_started: parse_date(attrs["date_started"] || attrs[:date_started]),
        date_finished: parse_date(attrs["date_finished"] || attrs[:date_finished]),
        note: blank_to_nil(attrs["note"] || attrs[:note])
      })
    end
  end

  defp reading_status_atom(status)
       when status in [
              :read,
              :did_not_finish,
              :on_hold,
              :want_to_read,
              :currently_reading,
              :not_interested
            ],
       do: {:ok, status}

  defp reading_status_atom(status) do
    case status |> to_string() |> String.trim() |> String.upcase() do
      "READ" -> {:ok, :read}
      "CURRENTLY_READING" -> {:ok, :currently_reading}
      "READING" -> {:ok, :currently_reading}
      "WANT_TO_READ" -> {:ok, :want_to_read}
      "ON_HOLD" -> {:ok, :on_hold}
      "PAUSED" -> {:ok, :on_hold}
      "DID_NOT_FINISH" -> {:ok, :did_not_finish}
      "DROPPED" -> {:ok, :did_not_finish}
      "NOT_INTERESTED" -> {:ok, :not_interested}
      _ -> {:error, :invalid_status}
    end
  end

  defp review_attrs(attrs) do
    %{
      content: attrs["content"] || attrs[:content] || "",
      is_spoiler:
        attrs["is_spoiler"] in ["true", true, "on"] or attrs[:is_spoiler] in ["true", true, "on"]
    }
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp parse_date(value) when value in [nil, ""], do: nil

  defp parse_date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp maybe_add_to_shelves(_user_id, [], _vn_ids), do: {:ok, %{success: true}}

  defp maybe_add_to_shelves(user_id, shelf_ids, vn_ids),
    do: Shelves.add_vns_to_shelves(user_id, shelf_ids, vn_ids)

  defp maybe_remove_from_shelves(_user_id, [], _vn_ids), do: {:ok, %{success: true}}

  defp maybe_remove_from_shelves(user_id, shelf_ids, vn_ids),
    do: Shelves.remove_vns_from_shelves(user_id, shelf_ids, vn_ids)

  defp apply_similarity_vote(vn_id, similar_vn_id, user_id, vote)
       when vote in ["1", 1, :up, "up"] do
    Similarities.upvote_vn_similarity(vn_id, similar_vn_id, user_id)
  end

  defp apply_similarity_vote(vn_id, similar_vn_id, user_id, vote)
       when vote in ["-1", -1, :down, "down"] do
    Similarities.downvote_vn_similarity(vn_id, similar_vn_id, user_id)
  end

  defp apply_similarity_vote(vn_id, similar_vn_id, user_id, _vote),
    do: Similarities.clear_vn_similarity_vote(vn_id, similar_vn_id, user_id)

  # Tail of the similarity-vote / add-recommendation mutations: the public
  # core's recommendation ordering and net votes just changed, so drop its
  # cache before returning the viewer-specific (vote-highlighted) refresh.
  defp refresh_recommendations(vn, viewer, opts) do
    limit = Keyword.get(opts, :limit, 10)
    user_id = viewer.id
    allowed = Kaguya.VisualNovels.TitleCategory.allowed_categories(viewer)

    VNPageCache.invalidate(vn.id)

    {:ok,
     Normalizer.normalize_recommendations(
       Similarities.list_similar_vns_with_votes(vn,
         limit: limit,
         user_id: user_id,
         allowed_categories: allowed
       )
     )}
  end

  # Tail of the tag-vote / clear-tag-vote mutations. Returns the vote-less tag
  # list plus the viewer's own votes as a separate map, so `Data.assign_tags/3`
  # can overlay them — the *same* single mechanism first paint uses
  # (`apply_my_votes/2` → `overlay_tag_votes/2`). `my_vote` is never baked into
  # the tag list; it is always overlaid.
  defp refresh_tags(vn_id, user_id) do
    VNPageCache.invalidate(vn_id)
    {:ok, {tags_for_vn(vn_id), VNTags.user_votes_for_vn(user_id, vn_id)}}
  end

  # Always vote-less. `my_vote` is never baked into a tag list here; it is
  # attached in exactly one place — `Data.overlay_tag_votes/2` — for every
  # surface that renders it. See docs/architecture/liveview-render-staging.md.
  defp tags_for_vn(vn_id) do
    case VNTags.list_tags_for_vn(vn_id, nil) do
      {:ok, tags} -> Enum.map(tags, &Normalizer.normalize_tag/1)
      _ -> []
    end
  end

  defp tag_vote_value(value) when is_integer(value) and value in 0..5, do: {:ok, value}

  defp tag_vote_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int in 0..5 -> {:ok, int}
      _ -> {:error, :invalid_tag_vote}
    end
  end

  defp tag_vote_value(_), do: {:error, :invalid_tag_vote}

  defp require_can_edit(%{can_edit: false}), do: {:error, :permission_denied}
  defp require_can_edit(%{id: _}), do: :ok

  defp recommendation_search_opts([:vn, :nukige, :adjacent]),
    do: [include_nukige: true, include_adjacent: true]

  defp recommendation_search_opts(allowed) do
    [
      include_nukige: :nukige in allowed,
      include_adjacent: :adjacent in allowed
    ]
  end

  defp readers_count(vn_id),
    do:
      Repo.aggregate(
        from(rs in ReadingStatus,
          where: rs.visual_novel_id == ^vn_id and rs.status == :currently_reading
        ),
        :count
      )

  defp want_to_read_count(vn_id),
    do:
      Repo.aggregate(
        from(rs in ReadingStatus,
          where: rs.visual_novel_id == ^vn_id and rs.status == :want_to_read
        ),
        :count
      )

  defp readers(vn_id),
    do:
      Repo.all(
        from(rs in ReadingStatus,
          join: u in Users.User,
          on: u.id == rs.user_id,
          where:
            rs.visual_novel_id == ^vn_id and rs.status == :currently_reading and
              not is_nil(u.avatar_id),
          order_by: [desc: rs.inserted_at],
          limit: 3,
          select: u
        )
      )

  defp want_to_readers(vn_id),
    do:
      Repo.all(
        from(rs in ReadingStatus,
          join: u in Users.User,
          on: u.id == rs.user_id,
          where:
            rs.visual_novel_id == ^vn_id and rs.status == :want_to_read and
              not is_nil(u.avatar_id),
          order_by: [desc: rs.inserted_at],
          limit: 3,
          select: u
        )
      )

  defp characters_for_vn(vn_id) do
    Repo.all(
      from vc in VNCharacter,
        join: c in Character,
        on: c.id == vc.character_id,
        where: vc.visual_novel_id == ^vn_id,
        where: vc.spoiler_level <= 0,
        where: is_nil(c.hidden_at),
        order_by: [
          asc:
            fragment(
              "CASE ? WHEN 'main' THEN 0 WHEN 'primary' THEN 1 WHEN 'side' THEN 2 ELSE 3 END",
              vc.role
            ),
          asc: c.name
        ],
        select: c
    )
    |> Enum.map(fn c ->
      %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        images: VisualNovels.build_character_image_urls(c),
        is_image_nsfw: Map.get(c, :is_image_nsfw, false),
        is_image_suggestive: Map.get(c, :is_image_suggestive, false)
      }
    end)
  end

  defp series_entries(series_id) do
    series = %Kaguya.VisualNovels.Series{id: series_id}
    {:ok, {items, _pagination}} = Series.list_vns_for_series(series, %{page: 1, page_size: 6})

    Enum.map(items, fn item ->
      %{
        position: item.position,
        visual_novel: %{
          id: item.visual_novel.id,
          slug: item.visual_novel.slug,
          title: item.visual_novel.title,
          images: VisualNovels.build_image_urls(item.visual_novel),
          is_image_nsfw: Map.get(item.visual_novel, :is_image_nsfw, false),
          is_image_suggestive: Map.get(item.visual_novel, :is_image_suggestive, false)
        }
      }
    end)
  end

  defp releases_for_vn(vn_id, filters) do
    query =
      from r in Release,
        where: r.visual_novel_id == ^vn_id,
        where: is_nil(r.hidden_at),
        order_by: [desc: r.release_date, asc: r.title],
        preload: [:extlinks]

    query =
      case blank_to_nil(filters[:language] || filters["language"]) do
        nil -> query
        language -> from(r in query, where: ^language == fragment("ANY(?)", r.languages))
      end

    query =
      case blank_to_nil(filters[:platform] || filters["platform"]) do
        nil -> query
        platform -> from(r in query, where: ^platform == fragment("ANY(?)", r.platforms))
      end

    Repo.all(query)
  end

  defp release_filter_options_for_vn(vn_id) do
    rows =
      Repo.all(
        from r in Release,
          where: r.visual_novel_id == ^vn_id,
          where: is_nil(r.hidden_at),
          select: %{languages: r.languages, platforms: r.platforms}
      )

    %{
      languages: rows |> Enum.flat_map(&(&1.languages || [])) |> Enum.uniq() |> Enum.sort(),
      platforms:
        rows
        |> Enum.flat_map(&(&1.platforms || []))
        |> Enum.uniq()
        |> Kaguya.Sync.VndbStorefrontMapper.sort_platforms()
    }
  end

  defp normalize_release_filters(filters, %{languages: languages, platforms: platforms}) do
    %{
      language:
        preferred_release_filter(filters[:language] || filters["language"], languages, "en"),
      platform:
        preferred_release_filter(filters[:platform] || filters["platform"], platforms, "win")
    }
  end

  defp preferred_release_filter(current, available, preferred) do
    current = blank_to_nil(current)

    cond do
      current in available -> current
      preferred in available -> preferred
      available != [] -> hd(available)
      true -> nil
    end
  end

  defp friend_activity(vn_id, user_id) do
    case Kaguya.Friends.list_friend_activity(user_id, vn_id, 10) do
      {:ok, %{items: items}} ->
        Enum.map(items, fn item ->
          %{
            user: Normalizer.normalize_user(item.user),
            reading_status: item.reading_status |> to_string() |> String.upcase(),
            rating: item.rating,
            has_review: item.has_review
          }
        end)

      _ ->
        []
    end
  end

  defp friend_reviews(vn_id, user_id) do
    case Kaguya.Friends.list_friend_reviews(user_id, vn_id, limit: 5) do
      {:ok, %{items: items}} -> Enum.map(items, &Normalizer.normalize_review/1)
      _ -> []
    end
  end
end
