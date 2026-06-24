defmodule Kaguya.Reviews do
  @moduledoc """
  Context for Visual Novel reviews and ratings.
  """

  import Ecto.Query
  import Kaguya.Reviews.ActivityMetadata, only: [vn_metadata: 1, release_year: 1]

  alias Kaguya.Repo
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Reviews.{Review, Rating, ReviewLike, ReviewComment, ReviewCommentLike}
  alias Kaguya.Comments
  alias Kaguya.Reviews.RatingUpdater
  alias Kaguya.Reviews.UserStatsUpdater
  alias Kaguya.Social
  alias Kaguya.Social.Likes
  alias Kaguya.Utils.TextPreview
  alias Kaguya.CursorPagination
  alias Kaguya.Pagination
  alias Kaguya.Users.User
  alias Kaguya.Activities
  alias Kaguya.Cdn

  # Combined purge used by review + comment mutations: both the VN page
  # (which shows the reviews list) and the single-review page (which shows
  # the review body + comments). Takes a Review struct so it works after
  # the row has been deleted — we only need user_id + visual_novel_id to
  # resolve (slug, username).
  defp purge_all_for_review(%Review{user_id: user_id, visual_novel_id: vn_id}) do
    case Repo.one(
           from vn in VisualNovel,
             join: u in User,
             on: u.id == ^user_id,
             where: vn.id == ^vn_id,
             select: {vn.slug, u.username}
         ) do
      {vn_slug, username} when is_binary(vn_slug) and is_binary(username) ->
        Cdn.purge_vn_cache(vn_slug)
        Cdn.purge_review_page(username, vn_slug)
        :ok

      _ ->
        :ok
    end
  end

  # Comment-mutation purge: loads the parent review's (vn_slug, username)
  # and purges both cached pages.
  defp purge_all_for_review_id(review_id) do
    case Repo.one(
           from r in Review,
             join: vn in VisualNovel,
             on: vn.id == r.visual_novel_id,
             join: u in User,
             on: u.id == r.user_id,
             where: r.id == ^review_id,
             select: {vn.slug, u.username}
         ) do
      {vn_slug, username} when is_binary(vn_slug) and is_binary(username) ->
        Cdn.purge_vn_cache(vn_slug)
        Cdn.purge_review_page(username, vn_slug)
        :ok

      _ ->
        :ok
    end
  end

  # ============================================================================
  # Review Operations
  # ============================================================================

  @doc """
  Creates a review for a visual novel.
  """
  def create_review(user_id, visual_novel_id, attrs) do
    full_attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:visual_novel_id, visual_novel_id)

    result =
      Repo.transact(fn ->
        with {:ok, review} <- Repo.insert(Review.changeset(%Review{}, full_attrs)),
             {:ok, :incremented} <- RatingUpdater.adjust_vn_review_count(visual_novel_id, +1),
             {:ok, :incremented} <- UserStatsUpdater.adjust_user_vn_review_count(user_id, +1) do
          {:ok, review}
        end
      end)

    with {:ok, review} <- result do
      record_review_activity(user_id, review)
      purge_all_for_review(review)
      {:ok, review}
    end
  end

  @doc """
  Updates a review.
  """
  def update_review(review_id, user_id, attrs) do
    with {:ok, review} <- get_review_by_id_and_user(review_id, user_id) do
      params = Map.put(attrs, :is_edited, true)

      case review |> Review.changeset(params) |> Repo.update() do
        {:ok, updated} = ok ->
          purge_all_for_review(updated)
          ok

        err ->
          err
      end
    end
  end

  @doc """
  Deletes a review.
  """
  def delete_review(review_id, user_id) do
    with {:ok, review} <- get_review_by_id_and_user(review_id, user_id) do
      visual_novel_id = review.visual_novel_id

      result =
        Repo.transact(fn ->
          with {:ok, _deleted} <- Repo.delete(review),
               {:ok, :decremented} <- RatingUpdater.adjust_vn_review_count(visual_novel_id, -1),
               {:ok, :decremented} <- UserStatsUpdater.adjust_user_vn_review_count(user_id, -1) do
            {:ok, true}
          end
        end)

      with {:ok, true} <- result do
        Activities.delete_activities_for_entity("review", review_id)
        purge_all_for_review(review)
        {:ok, true}
      end
    end
  end

  @doc """
  Deletes a review as admin (no ownership check).
  """
  def admin_delete_review(review_id) do
    with {:ok, review} <- get_review(review_id) do
      visual_novel_id = review.visual_novel_id
      author_id = review.user_id

      result =
        Repo.transact(fn ->
          with {:ok, _deleted} <- Repo.delete(review),
               {:ok, :decremented} <- RatingUpdater.adjust_vn_review_count(visual_novel_id, -1),
               {:ok, :decremented} <- UserStatsUpdater.adjust_user_vn_review_count(author_id, -1) do
            {:ok, true}
          end
        end)

      with {:ok, true} <- result do
        Activities.delete_activities_for_entity("review", review_id)
        purge_all_for_review(review)
        {:ok, true}
      end
    end
  end

  @doc """
  Gets a review by ID.
  """
  def get_review(review_id) do
    case Repo.get(Review, review_id) do
      nil -> {:error, :not_found}
      review -> {:ok, review}
    end
  end

  def get_review_for_viewer(review_id, viewer_id \\ nil, viewer \\ %{}) do
    with {:ok, review} <- get_review(review_id) do
      check_visible(review, viewer_id, viewer)
    end
  end

  @doc """
  Gets a review by visual novel and user.
  """
  def get_review_by_vn_and_user(visual_novel_id, user_id) do
    case Repo.get_by(Review, visual_novel_id: visual_novel_id, user_id: user_id) do
      nil -> {:ok, nil}
      review -> {:ok, review}
    end
  end

  @doc """
  Gets a VN review by `vn_slug` and `user_id`. Returns hidden
  reviews as well — they're filtered out of feeds/lists but remain
  accessible via direct lookup.
  """
  def get_review_by_vn_slug_and_user_id(vn_slug, user_id) do
    case Kaguya.VisualNovels.resolve_vn_id_by_slug(vn_slug) do
      nil ->
        {:error, :not_found}

      vn_id ->
        case Repo.get_by(Review, visual_novel_id: vn_id, user_id: user_id) do
          nil -> {:error, :not_found}
          review -> {:ok, review}
        end
    end
  end

  @doc """
  Viewer-agnostic variant used by the edge-cached single-review page.
  Hidden reviews are returned as well — they're filtered out of feeds/lists
  but remain accessible via direct link.
  """
  def get_public_review_by_vn_and_user_slugs(vn_slug, username) do
    case Kaguya.VisualNovels.resolve_vn_id_by_slug(vn_slug) do
      nil ->
        {:ok, nil}

      vn_id ->
        query =
          from(r in Review,
            join: u in User,
            on: u.id == r.user_id,
            where: r.visual_novel_id == ^vn_id and u.username == ^username
          )

        {:ok, Repo.one(query)}
    end
  end

  @doc """
  Lists reviews for a visual novel.
  """
  def list_reviews_for_vn(visual_novel_id, params, viewer_id \\ nil) do
    %{page: page, page_size: page_size, sort_by: sort_by} = params
    sort_by = sort_by || :newest

    reviews_query =
      Review
      |> where([r], r.visual_novel_id == ^visual_novel_id)
      |> filter_hidden(viewer_id)
      |> join(:left, [r], rat in Rating,
        on: rat.user_id == r.user_id and rat.visual_novel_id == r.visual_novel_id
      )
      |> apply_review_sorting(sort_by)
      |> select_merge([r, rat], %{rating: rat.rating})

    {reviews, pagination} = Pagination.paginate(reviews_query, page, page_size)

    {:ok, %{items: reviews, pagination: pagination}}
  end

  @doc """
  Lists reviews for a user.
  """
  def list_reviews_for_user(user_id, params, viewer_id \\ nil, opts \\ []) do
    %{page: page, page_size: page_size, sort_by: sort_by} = params
    sort_by = sort_by || :newest
    allowed = Keyword.get(opts, :allowed_categories)

    reviews_query =
      Review
      |> where([r], r.user_id == ^user_id)
      |> maybe_filter_vn_category(allowed)
      |> join(:left, [r], rat in Rating,
        on: rat.user_id == r.user_id and rat.visual_novel_id == r.visual_novel_id
      )
      |> apply_review_sorting(sort_by)
      |> select_merge([r, rat], %{rating: rat.rating})

    total =
      case params do
        %{skip_count: true} -> :skip
        _ -> nil
      end

    {reviews, pagination} = Pagination.paginate(reviews_query, page, page_size, total)
    reviews = Enum.map(reviews, &scrub_hidden_review_for_profile(&1, viewer_id))

    {:ok, %{items: reviews, pagination: pagination}}
  end

  @doc """
  Counts VN reviews for a user.
  """
  def count_reviews_for_user(user_id) do
    from(r in Review, where: r.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  def count_reviews_for_user_filtered(user_id, allowed) do
    from(r in Review,
      join: vn in VisualNovel,
      on: vn.id == r.visual_novel_id,
      where: r.user_id == ^user_id and is_nil(r.hidden_at) and vn.title_category in ^allowed
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Lists recent VN reviews.
  """
  def list_recent_reviews(cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    Review
    |> where([r], is_nil(r.hidden_at))
    |> maybe_filter_vn_category(allowed)
    |> CursorPagination.paginate_by_cursor(:inserted_at, cursor, limit, :desc)
    |> format_paginated_response()
  end

  @doc """
  Lists recent VN reviews for a viewer.
  """
  def list_recent_reviews_for_viewer(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    Review
    |> filter_hidden(viewer_id)
    |> maybe_filter_vn_category(allowed)
    |> CursorPagination.paginate_by_cursor(:inserted_at, cursor, limit, :desc)
    |> format_paginated_response()
  end

  @doc """
  Lists trending VN reviews for a viewer.
  """
  def list_trending_reviews_for_viewer(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    Review
    |> filter_hidden(viewer_id)
    |> maybe_filter_vn_category(allowed)
    |> CursorPagination.paginate_by_cursor(:trending_score, cursor, limit, :desc)
    |> format_paginated_response()
  end

  @doc """
  Lists public reviews for a VN by slug. Viewer-agnostic — safe to edge-cache.
  Excludes all hidden reviews (no author-viewer exception). Skips category
  filtering since the VN-level page already gates category access.
  """
  def list_public_reviews_by_vn_slug(vn_slug, params) do
    case VisualNovels.get_visual_novel_by_slug(vn_slug) do
      %{id: vn_id} ->
        list_public_reviews_by_vn_id(vn_id, params)

      _ ->
        %{page: page, page_size: page_size} = params

        {:ok,
         %{
           items: [],
           pagination: %{page: page, page_size: page_size, total_count: 0, total_pages: 0}
         }}
    end
  end

  @doc """
  Same as `list_public_reviews_by_vn_slug/2` but skips the slug→id lookup
  when the caller already has the VN id.
  """
  def list_public_reviews_by_vn_id(vn_id, params) do
    %{page: page, page_size: page_size, sort_by: sort_by} = params
    sort_by = sort_by || :most_liked

    query =
      Review
      |> where([r], r.visual_novel_id == ^vn_id and is_nil(r.hidden_at))
      |> join(:left, [r], rat in Rating,
        on: rat.user_id == r.user_id and rat.visual_novel_id == r.visual_novel_id
      )
      |> apply_review_sorting(sort_by)
      |> select_merge([r, rat], %{rating: rat.rating})

    {reviews, pagination} = Pagination.paginate(query, page, page_size)
    {:ok, %{items: reviews, pagination: pagination}}
  end

  @doc """
  Returns the set of review IDs the given user has liked for a specific VN.
  Small overlay payload paired with the cached public reviews list.
  """
  def liked_review_ids_for_vn(user_id, vn_slug) when not is_nil(user_id) do
    case Kaguya.VisualNovels.resolve_vn_id_by_slug(vn_slug) do
      nil -> {:ok, []}
      vn_id -> liked_review_ids_for_vn_id(user_id, vn_id)
    end
  end

  def liked_review_ids_for_vn(_user_id, _vn_slug), do: {:ok, []}

  @doc """
  Same as `liked_review_ids_for_vn/2` but skips the slug→id lookup
  when the caller already has the VN id.
  """
  def liked_review_ids_for_vn_id(user_id, vn_id) when not is_nil(user_id) and not is_nil(vn_id) do
    ids =
      Repo.all(
        from(rl in ReviewLike,
          join: r in Review,
          on: r.id == rl.vn_review_id,
          where: rl.user_id == ^user_id and r.visual_novel_id == ^vn_id,
          select: rl.vn_review_id
        )
      )

    {:ok, ids}
  end

  def liked_review_ids_for_vn_id(_user_id, _vn_id), do: {:ok, []}

  @doc """
  Returns the subset of `review_ids` the given user has liked. Used by
  list/profile views to overlay `liked_by_me` onto a paginated reviews
  page in a single round-trip.
  """
  def liked_review_ids_in(nil, _review_ids), do: []
  def liked_review_ids_in(_user_id, []), do: []

  def liked_review_ids_in(user_id, review_ids) when is_list(review_ids) do
    Repo.all(
      from(rl in ReviewLike,
        where: rl.user_id == ^user_id and rl.vn_review_id in ^review_ids,
        select: rl.vn_review_id
      )
    )
  end

  defp get_review_by_id_and_user(review_id, user_id) do
    case Repo.get_by(Review, id: review_id, user_id: user_id) do
      nil -> {:error, :not_found}
      review -> {:ok, review}
    end
  end

  defp apply_review_sorting(query, sort_by) do
    case sort_by do
      :newest -> order_by(query, [r], desc: r.inserted_at)
      :oldest -> order_by(query, [r], asc: r.inserted_at)
      :most_liked -> order_by(query, [r], desc: r.likes_count)
      :trending -> order_by(query, [r], desc: r.trending_score)
      _ -> order_by(query, [r], desc: r.trending_score)
    end
  end

  defp format_paginated_response({items, next_cursor, has_next}) do
    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  # ============================================================================
  # Sitemap
  # ============================================================================

  @doc """
  Returns public reviews for sitemap indexing.
  Joins user and visual_novel to return username + vn_slug needed for URL generation.
  """
  def list_reviews_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      from(r in Review,
        join: u in User,
        on: u.id == r.user_id,
        join: vn in VisualNovel,
        on: vn.id == r.visual_novel_id,
        where:
          is_nil(r.hidden_at) and is_nil(vn.hidden_at) and not is_nil(u.username) and
            not is_nil(vn.slug),
        order_by: [desc: r.updated_at, desc: r.id],
        select: %{
          id: r.id,
          username: u.username,
          vn_slug: vn.slug,
          updated_at: r.updated_at
        }
      )

    Pagination.paginate(query, page, page_size)
  end

  # ============================================================================
  # Trending Score
  # ============================================================================

  @comment_weight 3
  @base_epoch 1_740_890_930
  @time_scale 86_400.0

  @doc """
  Recalculates trending score for a review.
  """
  def recalc_trending_score(review) do
    engagement = max(review.likes_count + @comment_weight * review.comments_count, 1)
    engagement_log = :math.log10(engagement)
    time_offset = (DateTime.to_unix(review.inserted_at) - @base_epoch) / @time_scale
    engagement_log + time_offset
  end

  @doc """
  Updates trending score for a VN review.
  """
  def update_trending_score(review_id) do
    with {:ok, review} <- get_review(review_id) do
      new_score = recalc_trending_score(review)

      review
      |> Ecto.Changeset.change(trending_score: new_score)
      |> Repo.update()
    end
  end

  # ============================================================================
  # Like Operations
  # ============================================================================

  @doc """
  Likes a VN review, increments its like count, updates trending score, and notifies the author.

  Idempotent: returns `{:ok, true}` if the like already existed.
  """
  def like_review(review_id, user_id) do
    result =
      Repo.transact(fn ->
        with {:ok, review} <- get_review_for_viewer(review_id, user_id),
             review = Repo.preload(review, [:visual_novel, :user]),
             {:ok, inserted?} <-
               Likes.create_like(ReviewLike, %{vn_review_id: review_id, user_id: user_id}) do
          if inserted? do
            with {updated_count, _} when updated_count > 0 <-
                   Likes.increment_likes(Review, review_id),
                 {:ok, _} <- update_trending_score(review_id),
                 {:ok, _} <-
                   Social.create_notification(%{
                     user_id: review.user_id,
                     action: :like,
                     entity_type: :review,
                     entity_id: review_id,
                     actor_id: user_id,
                     metadata: build_review_metadata(review)
                   }) do
              {:ok, review}
            end
          else
            {:ok, :already_liked}
          end
        end
      end)

    with {:ok, %Review{} = review} <- result do
      record_liked_review_activity(user_id, review)
      {:ok, true}
    else
      {:ok, :already_liked} -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Unlikes a VN review, decrements its like count, and updates trending score.
  """
  def unlike_review(review_id, user_id) do
    result =
      Repo.transact(fn ->
        with {:ok, _review} <- get_review_for_viewer(review_id, user_id),
             {1, _} <- Likes.delete_like(ReviewLike, vn_review_id: review_id, user_id: user_id),
             {1, _} <- Likes.decrement_likes(Review, review_id),
             {:ok, _} <- update_trending_score(review_id) do
          {:ok, true}
        end
      end)

    with {:ok, true} <- result do
      Activities.delete_activity(user_id, :liked_review, "review", review_id)
      {:ok, true}
    end
  end

  @doc """
  Checks if a user has liked a VN review.
  """
  def liked_review?(review_id, user_id) do
    Likes.liked?(ReviewLike, vn_review_id: review_id, user_id: user_id)
  end

  # ============================================================================
  # Review Comment Operations
  # ============================================================================

  defp vn_review_comment_config(review) do
    %{
      comment_schema: ReviewComment,
      parent_schema: Review,
      entity_type: :review,
      comment_changeset: &ReviewComment.changeset(%ReviewComment{}, &1),
      parent_id_field: & &1.vn_review_id,
      get_parent: fn _attrs -> review end,
      get_parent_owner: & &1.user_id,
      build_metadata: &build_vn_review_comment_metadata/2
    }
  end

  @doc """
  Creates a comment on a VN review.
  """
  def create_review_comment(attrs) do
    with {:ok, review} <- get_review_for_viewer(attrs.vn_review_id, Map.get(attrs, :user_id)),
         :ok <- check_not_locked(review) do
      review = Repo.preload(review, [:visual_novel, :user])

      with {:ok, comment} <- Comments.create_comment(vn_review_comment_config(review), attrs) do
        record_comment_activity(comment)
        purge_all_for_review(review)
        {:ok, comment}
      end
    end
  end

  def admin_lock_review(review_id) do
    with {:ok, review} <- get_review(review_id),
         {:ok, updated} <-
           review
           |> Ecto.Changeset.change(is_locked: true)
           |> Repo.update() do
      purge_all_for_review(updated)
      {:ok, updated}
    end
  end

  def admin_unlock_review(review_id) do
    with {:ok, review} <- get_review(review_id),
         {:ok, updated} <-
           review |> Ecto.Changeset.change(is_locked: false) |> Repo.update() do
      purge_all_for_review(updated)
      {:ok, updated}
    end
  end

  defp check_not_locked(%Review{is_locked: true}), do: {:error, "This review is locked."}
  defp check_not_locked(_review), do: :ok

  @doc """
  Gets a review comment by ID.
  """
  def get_review_comment(id), do: Comments.get_comment(ReviewComment, id)

  @doc """
  Updates a review comment.
  """
  def update_review_comment(comment_id, user_id, content) do
    case Comments.update_comment(ReviewComment, comment_id, user_id, %{
           content: content,
           is_edited: true
         }) do
      {:ok, updated} = ok ->
        purge_all_for_review_id(updated.vn_review_id)
        ok

      err ->
        err
    end
  end

  @doc """
  Deletes a review comment.
  """
  def delete_review_comment(comment_id, user_id) do
    # Collect subtree IDs before deletion so we can clean up all activities
    subtree_ids = Comments.collect_subtree_ids(ReviewComment, comment_id)

    # Capture the parent review id before delete so we can purge after.
    review_id =
      Repo.one(from c in ReviewComment, where: c.id == ^comment_id, select: c.vn_review_id)

    with {:ok, true} <-
           Comments.delete_comment(ReviewComment, Review, comment_id, user_id, :vn_review_id) do
      Enum.each(subtree_ids, fn id ->
        Activities.delete_activities_for_entity("review_comment", id)
      end)

      if review_id, do: purge_all_for_review_id(review_id)

      {:ok, true}
    end
  end

  @doc """
  Returns a paginated list of comments for a VN review.
  """
  def list_comments_for_review(review_id, comments_count, params) do
    Comments.list_comments_for(ReviewComment, :vn_review_id, review_id, comments_count, params)
  end

  @doc """
  Viewer-agnostic comments listing used by the edge-cached single-review
  page. Drops `viewer_id`, so `Comments.list_comments_for/5` filters strictly
  on `hidden_at IS NULL`.
  """
  def list_public_comments_for_review(review_id, params) do
    count = count_public_comments_for_review(review_id)

    Comments.list_comments_for(
      ReviewComment,
      :vn_review_id,
      review_id,
      count,
      Map.drop(params, [:viewer_id])
    )
  end

  defp count_public_comments_for_review(review_id) do
    from(c in ReviewComment,
      where: c.vn_review_id == ^review_id and is_nil(c.hidden_at)
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Overlay: review-comment IDs the given user has liked on a specific review.
  Small payload paired with the cached comments list.
  """
  def liked_review_comment_ids_for_review(user_id, review_id) when not is_nil(user_id) do
    ids =
      Repo.all(
        from(l in ReviewCommentLike,
          join: c in ReviewComment,
          on: c.id == l.vn_review_comment_id,
          where: l.user_id == ^user_id and c.vn_review_id == ^review_id,
          select: l.vn_review_comment_id
        )
      )

    {:ok, ids}
  end

  def liked_review_comment_ids_for_review(_user_id, _review_id), do: {:ok, []}

  @doc """
  Likes a review comment and increments the comment's like count.
  """
  def like_review_comment(review_comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- get_review_comment(review_comment_id),
           {:ok, _} <- check_visible(comment, user_id),
           {:ok, review} <- get_review_for_viewer(comment.vn_review_id, user_id),
           review = Repo.preload(review, [:visual_novel, :user]),
           {:ok, inserted?} <-
             Likes.create_like(ReviewCommentLike, %{
               vn_review_comment_id: review_comment_id,
               user_id: user_id
             }) do
        if inserted? do
          with {updated_count, _} when updated_count > 0 <-
                 Likes.increment_likes(ReviewComment, review_comment_id),
               {:ok, _} <-
                 Social.create_notification(%{
                   user_id: comment.user_id,
                   action: :like,
                   entity_type: :comment,
                   entity_id: review_comment_id,
                   actor_id: user_id,
                   metadata: build_vn_review_comment_metadata(review, comment)
                 }) do
            {:ok, true}
          end
        else
          {:ok, true}
        end
      end
    end)
  end

  @doc """
  Unlikes a review comment and decrements the comment's like count.
  """
  def unlike_review_comment(review_comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- get_review_comment(review_comment_id),
           {:ok, _} <- check_visible(comment, user_id),
           {:ok, _review} <- get_review_for_viewer(comment.vn_review_id, user_id),
           {1, _} <-
             Likes.delete_like(ReviewCommentLike,
               vn_review_comment_id: review_comment_id,
               user_id: user_id
             ),
           {1, _} <- Likes.decrement_likes(ReviewComment, review_comment_id) do
        {:ok, true}
      end
    end)
  end

  @doc """
  Checks if a user has liked a review comment.
  """
  def liked_review_comment?(review_comment_id, user_id) do
    Likes.liked?(ReviewCommentLike, vn_review_comment_id: review_comment_id, user_id: user_id)
  end

  # ----------------------------------------------------------------------------
  # Notification metadata helpers
  # ----------------------------------------------------------------------------

  defp build_review_metadata(%Review{} = review) do
    vn = review.visual_novel

    %{
      text_preview:
        review.content
        |> TextPreview.extract_text()
        |> TextPreview.truncate_on_words(),
      vn_review_path: review_path(review.user.username, vn.slug),
      vn_image_url: vn.temp_image_url,
      vn_title: vn.title
    }
  end

  defp build_vn_review_comment_metadata(%Review{} = review, %ReviewComment{} = comment) do
    vn = review.visual_novel

    %{
      text_preview:
        comment.content
        |> TextPreview.truncate_on_words(),
      vn_review_path: review_path(review.user.username, vn.slug),
      vn_image_url: vn.temp_image_url,
      vn_title: vn.title,
      parent_entity_type: "review"
    }
  end

  # ----------------------------------------------------------------------------
  # Activity helpers
  # ----------------------------------------------------------------------------

  defp record_review_activity(user_id, review) do
    vn = VisualNovels.get_visual_novel(review.visual_novel_id)
    user = Repo.get(User, user_id)

    metadata =
      if vn && user do
        Map.merge(vn_metadata(vn), %{
          vn_review_path: review_path(user.username, vn.slug),
          review_username: user.username
        })
      else
        vn_metadata(vn)
      end

    Activities.record_activity(%{
      user_id: user_id,
      action: :reviewed,
      entity_type: "review",
      entity_id: review.id,
      metadata: metadata
    })
  end

  defp record_liked_review_activity(user_id, %Review{} = review) do
    vn = review.visual_novel
    reviewer = review.user
    reviewer_rating = Repo.get_by(Rating, user_id: review.user_id, visual_novel_id: vn.id)

    Activities.record_activity(%{
      user_id: user_id,
      action: :liked_review,
      entity_type: "review",
      entity_id: review.id,
      metadata: %{
        review_user_id: review.user_id,
        review_username: reviewer.username,
        review_display_name: reviewer.display_name,
        review_rating: reviewer_rating && reviewer_rating.rating,
        vn_id: vn.id,
        vn_title: vn.title,
        vn_slug: vn.slug,
        vn_image_url: VisualNovels.build_image_urls(vn)[:small],
        vn_release_year: release_year(vn.release_date)
      }
    })
  end

  defp record_comment_activity(comment) do
    review = Repo.get(Review, comment.vn_review_id) |> Repo.preload([:visual_novel, :user])

    metadata =
      if review && review.visual_novel do
        vn = review.visual_novel

        %{
          parent_entity_type: "review",
          parent_entity_id: review.id,
          text_preview: comment.content |> TextPreview.truncate_on_words(),
          vn_review_path: review_path(review.user.username, vn.slug),
          review_username: review.user.username,
          review_display_name: review.user.display_name,
          vn_id: vn.id,
          vn_title: vn.title,
          vn_slug: vn.slug,
          vn_image_url: VisualNovels.build_image_urls(vn)[:small],
          vn_release_year: release_year(vn.release_date)
        }
      else
        %{
          parent_entity_type: "review",
          text_preview: comment.content |> TextPreview.truncate_on_words()
        }
      end

    Activities.record_activity(%{
      user_id: comment.user_id,
      action: :commented,
      entity_type: "review_comment",
      entity_id: comment.id,
      metadata: metadata
    })
  end

  defp review_path(username, vn_slug) when is_binary(username) and is_binary(vn_slug),
    do: "/@#{username}/reviews/#{vn_slug}"

  # ============================================================================
  # Content Hiding
  # ============================================================================

  def hide_review(review_id, attrs \\ %{}) do
    attrs = normalize_moderation_attrs(attrs)

    with {:ok, review} <- get_review(review_id) do
      result =
        Repo.transact(fn ->
          with {:ok, updated} <-
                 review
                 |> Ecto.Changeset.change(
                   hidden_at: DateTime.utc_now() |> DateTime.truncate(:second)
                 )
                 |> Repo.update(),
               :ok <- maybe_create_removal_comment(review, attrs) do
            {:ok, updated}
          end
        end)

      with {:ok, updated} <- result do
        purge_all_for_review(updated)
        {:ok, updated}
      end
    end
  end

  def unhide_review(review_id) do
    with {:ok, review} <- get_review(review_id) do
      case review
           |> Ecto.Changeset.change(hidden_at: nil)
           |> Repo.update() do
        {:ok, updated} = ok ->
          purge_all_for_review(updated)
          ok

        err ->
          err
      end
    end
  end

  def hide_review_comment(comment_id, attrs \\ %{}) do
    review_id =
      Repo.one(from c in ReviewComment, where: c.id == ^comment_id, select: c.vn_review_id)

    with {:ok, count} <-
           Comments.hide_comment_subtree(ReviewComment, Review, comment_id, :vn_review_id, attrs) do
      if review_id, do: purge_all_for_review_id(review_id)
      {:ok, count}
    end
  end

  def unhide_review_comment(comment_id) do
    review_id =
      Repo.one(from c in ReviewComment, where: c.id == ^comment_id, select: c.vn_review_id)

    with {:ok, count} <-
           Comments.unhide_comment_subtree(ReviewComment, Review, comment_id, :vn_review_id) do
      if review_id, do: purge_all_for_review_id(review_id)
      {:ok, count}
    end
  end

  defp check_visible(record, viewer_id), do: check_visible(record, viewer_id, %{})

  defp check_visible(%{hidden_at: nil} = record, _viewer_id, _opts), do: {:ok, record}
  defp check_visible(record, _viewer_id, %{mod_reviews: true}), do: {:ok, record}
  defp check_visible(record, _viewer_id, %{role: :admin}), do: {:ok, record}
  defp check_visible(%{user_id: uid} = record, uid, _opts) when not is_nil(uid), do: {:ok, record}
  defp check_visible(_record, _viewer_id, _opts), do: {:error, :not_found}

  defp scrub_hidden_review_for_profile(%{hidden_at: nil} = review, _viewer_id), do: review

  defp scrub_hidden_review_for_profile(%{user_id: uid} = review, uid) when not is_nil(uid),
    do: review

  defp scrub_hidden_review_for_profile(%Review{} = review, _viewer_id) do
    %{
      review
      | content: nil,
        likes_count: 0,
        comments_count: 0,
        trending_score: 0.0,
        is_edited: false,
        is_spoiler: false,
        is_locked: false,
        rating: nil
    }
  end

  defp filter_hidden(query, viewer_id, opts \\ %{}) do
    cond do
      Map.get(opts, :mod_reviews, false) -> query
      Map.get(opts, :role) == :admin -> query
      is_nil(viewer_id) -> from(q in query, where: is_nil(q.hidden_at))
      true -> from(q in query, where: is_nil(q.hidden_at) or q.user_id == ^viewer_id)
    end
  end

  defp maybe_filter_vn_category(query, nil), do: query

  defp maybe_filter_vn_category(query, allowed) do
    allowed_vn_ids =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: vn.title_category in ^allowed,
        select: vn.id
      )

    where(query, [r], r.visual_novel_id in subquery(allowed_vn_ids))
  end

  defp normalize_moderation_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_moderation_attrs(reason) when is_binary(reason), do: %{reason: reason}
  defp normalize_moderation_attrs(_attrs), do: %{}

  defp maybe_create_removal_comment(review, attrs) do
    if truthy?(Map.get(attrs, :add_comment) || Map.get(attrs, "add_comment")) do
      case Map.get(attrs, :actor_id) || Map.get(attrs, "actor_id") do
        nil ->
          :ok

        actor_id ->
          review = Repo.preload(review, [:visual_novel, :user])

          content =
            Map.get(attrs, :comment) || Map.get(attrs, "comment") || Map.get(attrs, :reason) ||
              Map.get(attrs, "reason")

          if is_binary(content) and String.trim(content) != "" do
            case Comments.create_comment(vn_review_comment_config(review), %{
                   vn_review_id: review.id,
                   user_id: actor_id,
                   content: content
                 }) do
              {:ok, _comment} -> :ok
              {:error, reason} -> {:error, reason}
            end
          else
            :ok
          end
      end
    else
      :ok
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
