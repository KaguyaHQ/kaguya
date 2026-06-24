defmodule KaguyaWeb.Comments.ReviewAdapter do
  @moduledoc """
  Review-backed implementation of `KaguyaWeb.Comments.Adapter`.

  Bridges `KaguyaWeb.CommentsComponent` to the `Kaguya.Reviews` context so the
  same component that powers list comments can power review comments without
  any duplication.

  Visibility / authorization rules mirror the Next.js single-review page:

    * Anonymous viewers see public (non-hidden) comments only.
    * Comment authors can see their own hidden comments.
    * Moderators (`mod_reviews: true` or `role: :admin`) see everything.
    * Locked reviews disallow new comments, replies, and edits even from the
      review author (matches `Kaguya.Reviews.check_not_locked/1`).
  """

  @behaviour KaguyaWeb.Comments.Adapter

  import Ecto.Query

  alias Kaguya.Pagination
  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.{Review, ReviewComment, ReviewCommentLike}
  alias Kaguya.Users

  @default_page_size 10

  @impl true
  def resource_type, do: :vn_review_comment

  @impl true
  def load(review_id, viewer, opts) do
    page = int(Map.get(opts, :page, 1), 1)
    page_size = int(Map.get(opts, :page_size, @default_page_size), @default_page_size)
    # Default to `:oldest` to match Next.js `VNReviewComments.tsx` which hard-codes
    # `sortBy = SortBy.Oldest` for review threads (oldest-first reads more like a
    # conversation; "most_liked" is a list-comments idiom).
    sort_by = atomize_sort(Map.get(opts, :sort_by, :oldest))
    viewer_id = user_id(viewer)

    with {:ok, review} <-
           Reviews.get_review_for_viewer(review_id, viewer_id, viewer_perms(viewer)) do
      query =
        ReviewComment
        |> where([c], c.vn_review_id == ^review.id)
        |> filter_visible_to(viewer)
        |> apply_sorting(sort_by)

      total_count = Repo.aggregate(query, :count, :id)
      {comments, pagination} = Pagination.paginate(query, page, page_size, total_count)
      comments = Repo.preload(comments, :user)
      liked_ids = liked_ids(comments, viewer_id)

      {:ok,
       %{
         items: Enum.map(comments, &normalize_comment(&1, liked_ids)),
         pagination: normalize_pagination(pagination, page, page_size),
         comments_count: review.comments_count || total_count
       }}
    end
  end

  @impl true
  def create(review_id, viewer, attrs) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_can_review(viewer),
         {:ok, comment} <-
           Reviews.create_review_comment(%{
             vn_review_id: review_id,
             user_id: user_id,
             parent_comment_id: blank_to_nil(Map.get(attrs, :parent_comment_id)),
             content: Map.get(attrs, :content)
           }) do
      {:ok, comment |> Repo.preload(:user) |> normalize_comment(MapSet.new())}
    end
  end

  @impl true
  def update(comment_id, viewer, attrs) do
    with {:ok, user_id} <- require_user(viewer),
         {:ok, comment} <-
           Reviews.update_review_comment(comment_id, user_id, Map.get(attrs, :content)) do
      liked_set = liked_ids([comment], user_id)
      {:ok, comment |> Repo.preload(:user) |> normalize_comment(liked_set)}
    end
  end

  @impl true
  def delete(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Reviews.delete_review_comment(comment_id, user_id)
  end

  @impl true
  def like(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Reviews.like_review_comment(comment_id, user_id)
  end

  @impl true
  def unlike(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Reviews.unlike_review_comment(comment_id, user_id)
  end

  @impl true
  def hide(comment_id, viewer, attrs) do
    with :ok <- require_moderator(viewer) do
      Reviews.hide_review_comment(
        comment_id,
        attrs
        |> Map.put_new(:actor_id, user_id(viewer))
        |> Map.put_new(:reason, "Hidden by moderator")
      )
    end
  end

  @impl true
  def unhide(comment_id, viewer) do
    with :ok <- require_moderator(viewer), do: Reviews.unhide_review_comment(comment_id)
  end

  @impl true
  def can_comment?(review_id, viewer) do
    with {:ok, _user_id} <- require_user(viewer),
         :ok <- ensure_can_review(viewer),
         {:ok, review} <-
           Reviews.get_review_for_viewer(review_id, user_id(viewer), viewer_perms(viewer)),
         :ok <- ensure_not_locked(review) do
      true
    else
      _ -> false
    end
  end

  @impl true
  def can_moderate?(%{mod_reviews: true}), do: true
  def can_moderate?(%{role: :admin}), do: true
  def can_moderate?(%{role: "admin"}), do: true
  def can_moderate?(_viewer), do: false

  # ---------------------------------------------------------------------------
  # Privates
  # ---------------------------------------------------------------------------

  defp filter_visible_to(query, viewer) do
    cond do
      can_moderate?(viewer) ->
        query

      is_binary(user_id(viewer)) ->
        viewer_id = user_id(viewer)
        where(query, [c], is_nil(c.hidden_at) or c.user_id == ^viewer_id)

      true ->
        where(query, [c], is_nil(c.hidden_at))
    end
  end

  defp apply_sorting(query, :oldest), do: order_by(query, [c], asc: c.inserted_at, asc: c.id)

  defp apply_sorting(query, :most_liked),
    do: order_by(query, [c], desc: c.likes_count, desc: c.inserted_at)

  defp apply_sorting(query, _), do: order_by(query, [c], desc: c.inserted_at, desc: c.id)

  defp liked_ids(_comments, nil), do: MapSet.new()
  defp liked_ids([], _viewer_id), do: MapSet.new()

  defp liked_ids(comments, viewer_id) do
    ids = Enum.map(comments, & &1.id)

    ReviewCommentLike
    |> where([l], l.vn_review_comment_id in ^ids and l.user_id == ^viewer_id)
    |> select([l], l.vn_review_comment_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp normalize_comment(%ReviewComment{} = comment, liked_ids) do
    %{
      id: comment.id,
      parent_comment_id: comment.parent_comment_id,
      content: comment.content || "",
      likes_count: comment.likes_count || 0,
      liked_by_me: MapSet.member?(liked_ids, comment.id),
      is_edited: comment.is_edited || false,
      hidden_at: comment.hidden_at,
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at,
      user: normalize_user(comment.user)
    }
  end

  defp normalize_user(%Kaguya.Users.User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      role: user.role,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp normalize_user(_), do: nil

  defp normalize_pagination(pagination, page, page_size) do
    total_count = Pagination.resolve_count(pagination) || 0

    total_pages =
      Pagination.resolve_total_pages(pagination) ||
        max(div(total_count + page_size - 1, page_size), 1)

    %{
      page: Map.get(pagination, :page) || page,
      page_size: Map.get(pagination, :page_size) || page_size,
      total_pages: total_pages,
      total_count: total_count
    }
  end

  defp ensure_can_review(%{can_review: false}), do: {:error, :forbidden}
  defp ensure_can_review(_viewer), do: :ok

  defp ensure_not_locked(%Review{is_locked: true}), do: {:error, :locked}
  defp ensure_not_locked(_review), do: :ok

  defp require_user(%{id: id}) when is_binary(id), do: {:ok, id}
  defp require_user(_viewer), do: {:error, :unauthenticated}

  defp require_moderator(viewer) do
    if can_moderate?(viewer), do: :ok, else: {:error, :forbidden}
  end

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_viewer), do: nil

  defp viewer_perms(nil), do: %{}

  defp viewer_perms(viewer) when is_map(viewer) do
    viewer
    |> Map.take([:mod_reviews, :role])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp atomize_sort(value) when is_atom(value), do: value
  defp atomize_sort("newest"), do: :newest
  defp atomize_sort("oldest"), do: :oldest
  defp atomize_sort("most_liked"), do: :most_liked
  defp atomize_sort("MOST_LIKED"), do: :most_liked
  defp atomize_sort("OLDEST"), do: :oldest
  defp atomize_sort("NEWEST"), do: :newest
  defp atomize_sort(_), do: :newest

  defp int(value, _default) when is_integer(value) and value > 0, do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp int(_value, default), do: default
end
