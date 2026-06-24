defmodule Kaguya.Friends do
  @moduledoc """
  Social activity for a visual novel — what the viewer's followed users
  have done (statuses, ratings, reviews) on a given VN.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.CursorPagination
  alias Kaguya.Social.UserFollow
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Reviews.{Rating, Review}

  @visible_statuses [:read, :currently_reading, :want_to_read, :on_hold, :did_not_finish]

  # ── Friend Activity ───────────────────────────────────────────

  @doc """
  Returns friend activity for a VN: items (user + status + rating + has_review),
  grouped status counts, and total count.
  """
  def list_friend_activity(viewer_id, vn_id, limit \\ 10) do
    following_sq = following_subquery(viewer_id)

    items =
      from(rs in ReadingStatus,
        where: rs.visual_novel_id == ^vn_id,
        where: rs.user_id in subquery(following_sq),
        where: rs.status != :not_interested,
        join: u in assoc(rs, :user),
        left_join: r in Rating,
        on: r.user_id == rs.user_id and r.visual_novel_id == rs.visual_novel_id,
        left_join: rev in Review,
        on: rev.user_id == rs.user_id and rev.visual_novel_id == rs.visual_novel_id,
        order_by: [desc: rs.updated_at],
        limit: ^limit,
        select: %{
          user: u,
          reading_status: rs.status,
          rating: r.rating,
          has_review: not is_nil(rev.id),
          updated_at: rs.updated_at
        }
      )
      |> Repo.all()

    raw_counts =
      from(rs in ReadingStatus,
        where: rs.visual_novel_id == ^vn_id,
        where: rs.user_id in subquery(following_sq),
        where: rs.status != :not_interested,
        group_by: rs.status,
        select: {rs.status, count(rs.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Normalize keys to uppercase strings matching the public status values,
    # and always include every visible status so clients don't need null-checks.
    status_counts =
      @visible_statuses
      |> Map.new(fn s -> {status_to_key(s), Map.get(raw_counts, s, 0)} end)

    total_count = raw_counts |> Map.values() |> Enum.sum()

    {:ok, %{items: items, status_counts: status_counts, total_count: total_count}}
  end

  # ── Friend Reviews ────────────────────────────────────────────

  @doc """
  Cursor-paginated reviews from followed users for a given VN.
  """
  def list_friend_reviews(viewer_id, vn_id, opts) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 5)
    following_sq = following_subquery(viewer_id)

    decoded_cursor = CursorPagination.decode_cursor(cursor, [:datetime])

    query =
      from(rev in Review,
        left_join: rat in Rating,
        on: rat.user_id == rev.user_id and rat.visual_novel_id == rev.visual_novel_id,
        where: rev.visual_novel_id == ^vn_id,
        where: rev.user_id in subquery(following_sq),
        where: is_nil(rev.hidden_at),
        preload: [:user],
        select_merge: %{rating: rat.rating}
      )

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(query, :inserted_at, decoded_cursor, limit, :desc)

    {:ok,
     %{
       items: items,
       next_cursor: CursorPagination.encode_cursor(next_cursor),
       has_next: has_next
     }}
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp status_to_key(status), do: status |> Atom.to_string() |> String.upcase()

  defp following_subquery(viewer_id) do
    from(uf in UserFollow,
      where: uf.follower_id == ^viewer_id,
      select: uf.followed_id
    )
  end
end
