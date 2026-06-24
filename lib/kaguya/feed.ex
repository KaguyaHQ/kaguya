defmodule Kaguya.Feed do
  @moduledoc """
  Activity feed for the visual novel surface.
  Combines VN reviews, VN lists, and discussion posts
  (ordered by last activity timestamp).
  """

  import Ecto.Query
  alias Kaguya.CursorPagination
  alias Kaguya.Repo
  alias Kaguya.Lists
  alias Kaguya.Reviews.Review
  alias Kaguya.Discussions.Post
  alias Kaguya.VisualNovels.VisualNovel

  # Categories surfaced in the VN home feed. `:user` posts are direct
  # user-to-user discussions and don't belong in a public discovery feed.
  @feed_post_categories ~w(general announcements site_discussions visual_novel producer character)a

  @doc """
  Returns a mixed feed of VN reviews, VN lists, and discussion posts,
  ordered by activity timestamp.

  - Reviews: ordered by inserted_at
  - Lists: ordered by last_activity_at (when VNs were added/removed)
  - Posts: ordered by last_comment_at (latest reply or original creation)
    — all categories except `:user`. VN-scoped posts are filtered by
    `allowed_categories`; non-VN posts pass through.

  Filters out non-public lists, hidden/deleted posts, and reviews/lists
  hidden from non-owners.

  Options:
    - `:allowed_categories` - list of title_category values to include (default: ["vn"])
  """
  def get_feed(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories, [:vn])

    reviews_query =
      Review
      |> join(:inner, [r], vn in VisualNovel, on: vn.id == r.visual_novel_id)
      |> filter_hidden_reviews(viewer_id)
      |> where([_r, vn], vn.title_category in ^allowed)
      |> select([r], %{
        type: ^"review",
        id: r.id,
        activity_at: r.inserted_at
      })

    lists_query =
      Lists.List
      |> where([l], l.is_public == true)
      |> filter_hidden_lists(viewer_id)
      |> where(
        [l],
        fragment(
          "EXISTS (SELECT 1 FROM list_items li JOIN visual_novels vn ON vn.id = li.visual_novel_id WHERE li.list_id = ? AND vn.title_category = ANY(?))",
          l.id,
          ^Enum.map(allowed, &to_string/1)
        )
      )
      |> select([l], %{
        type: ^"list",
        id: l.id,
        activity_at: coalesce(l.last_activity_at, l.inserted_at)
      })

    allowed_strings = Enum.map(allowed, &to_string/1)

    posts_query =
      Post
      |> where([p], p.category_type in ^@feed_post_categories)
      |> where([p], is_nil(p.deleted_at))
      |> filter_hidden_posts(viewer_id)
      |> where(
        [p],
        # Non-VN-scoped posts always pass; VN-scoped posts must reference a
        # VN whose title_category is in `allowed`.
        p.category_type != ^:visual_novel or
          fragment(
            "EXISTS (SELECT 1 FROM visual_novels vn WHERE vn.id = ? AND vn.title_category = ANY(?))",
            p.entity_id,
            ^allowed_strings
          )
      )
      |> select([p], %{
        type: ^"post",
        id: p.id,
        activity_at: coalesce(p.last_comment_at, p.inserted_at)
      })

    union_query =
      from u in subquery(reviews_query |> union_all(^lists_query) |> union_all(^posts_query)),
        select: %{
          type: u.type,
          id: u.id,
          activity_at: u.activity_at
        }

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(
        union_query,
        :activity_at,
        cursor,
        limit,
        :desc
      )

    full_items = preload_feed_items(items)
    {:ok, %{items: full_items, next_cursor: next_cursor, has_next: has_next}}
  end

  defp preload_feed_items(items) do
    grouped = Enum.group_by(items, & &1.type)

    reviews = load_by_ids(Review, grouped, "review")
    lists = load_by_ids(Lists.List, grouped, "list")
    posts = load_by_ids(Post, grouped, "post")

    id_map =
      (reviews ++ lists ++ posts)
      |> Map.new(&{&1.id, &1})

    Enum.map(items, fn %{id: id} ->
      Map.fetch!(id_map, id)
    end)
  end

  defp load_by_ids(schema, grouped, key) do
    case Map.get(grouped, key, []) do
      [] ->
        []

      items ->
        ids = Enum.map(items, & &1.id)
        Repo.all(from(r in schema, where: r.id in ^ids))
    end
  end

  defp filter_hidden_reviews(query, nil) do
    where(query, [r, _vn], is_nil(r.hidden_at))
  end

  defp filter_hidden_reviews(query, viewer_id) do
    where(query, [r, _vn], is_nil(r.hidden_at) or r.user_id == ^viewer_id)
  end

  defp filter_hidden_lists(query, nil) do
    where(query, [l], is_nil(l.hidden_at))
  end

  defp filter_hidden_lists(query, viewer_id) do
    where(query, [l], is_nil(l.hidden_at) or l.user_id == ^viewer_id)
  end

  defp filter_hidden_posts(query, nil) do
    where(query, [p], is_nil(p.hidden_at))
  end

  defp filter_hidden_posts(query, viewer_id) do
    where(query, [p], is_nil(p.hidden_at) or p.user_id == ^viewer_id)
  end
end
