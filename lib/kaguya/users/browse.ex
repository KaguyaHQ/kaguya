defmodule Kaguya.Users.Browse do
  @moduledoc """
  Read‐only, cursor‐paginated user browse functions.
  """

  import Ecto.Query
  alias Kaguya.CursorPagination
  alias Kaguya.Users.User
  alias Kaguya.Social.UserFollow
  alias Kaguya.Reviews.Review

  @like_weight 6
  @review_weight 8

  @doc """
  Returns a `%{items: [...], next_cursor: cursor, has_next: bool}` map
  suitable for `:user_connection`. Filters out `current_id` if given.
  """
  def list_users(%{limit: lim, cursor: cur, sort_by: sort}, current_id \\ nil) do
    limit = lim |> max(1) |> min(25)

    sort_query =
      case sort do
        :newest -> newest_query()
        :most_followed -> most_followed_query()
        _ -> most_active_query()
      end

    query =
      sort_query
      |> subquery()
      |> join(:inner, [q], u in User, on: u.id == q.user_id)
      |> where(
        [_q, u],
        not is_nil(u.favorite_visual_novels) and
          fragment("array_length(?, 1) > 1", u.favorite_visual_novels)
      )
      |> maybe_exclude_current(current_id)
      |> select(
        [q, u],
        %{user: u, cursor_score: q.cursor_score, cursor_id: q.cursor_id}
      )

    {fields, types} = cursor_fields(sort)

    {rows, next_cur, has_next} =
      CursorPagination.paginate(query, fields, types, cur, limit, :desc)

    users = Enum.map(rows, & &1.user)
    {:ok, %{items: users, next_cursor: next_cur, has_next: has_next}}
  end

  # ────────────────────────────────────────────────────────────
  # Query builders: each returns a map %{user, cursor_score, cursor_id}
  # ────────────────────────────────────────────────────────────
  defp cursor_fields(:newest), do: {[:cursor_score, :cursor_id], [:datetime, :string]}
  defp cursor_fields(:most_followed), do: {[:cursor_score, :cursor_id], [:int, :string]}
  defp cursor_fields(:most_active), do: {[:cursor_score, :cursor_id], [:int, :string]}

  defp maybe_exclude_current(query, nil), do: query

  defp maybe_exclude_current(query, current_id) do
    where(query, [_, u], u.id != ^current_id)
  end

  defp newest_query do
    from u in User,
      order_by: [desc: u.inserted_at, desc: u.id],
      select: %{user_id: u.id, cursor_score: u.inserted_at, cursor_id: u.id}
  end

  defp most_followed_query do
    followers_q =
      from uf in UserFollow,
        group_by: uf.followed_id,
        select: %{user_id: uf.followed_id, cnt: count(uf.follower_id)}

    from u in User,
      join: f in subquery(followers_q),
      on: f.user_id == u.id,
      order_by: [desc: f.cnt, desc: u.id],
      select: %{user_id: u.id, cursor_score: f.cnt, cursor_id: u.id}
  end

  defp most_active_query, do: most_active_vn_query()

  # VN surface: only VN activity matters
  defp most_active_vn_query do
    vn_reviews_q =
      from vnr in Review,
        group_by: vnr.user_id,
        select: %{user_id: vnr.user_id, cnt: count(vnr.id), likes: sum(vnr.likes_count)}

    from u in User,
      left_join: vnr in subquery(vn_reviews_q),
      on: vnr.user_id == u.id,
      order_by: [
        desc:
          fragment(
            "COALESCE(?, 0) * ? + COALESCE(?, 0) * ?",
            vnr.likes,
            ^@like_weight,
            vnr.cnt,
            ^@review_weight
          ),
        desc: u.id
      ],
      select: %{
        user_id: u.id,
        cursor_score:
          fragment(
            "COALESCE(?, 0) * ? + COALESCE(?, 0) * ?",
            vnr.likes,
            ^@like_weight,
            vnr.cnt,
            ^@review_weight
          ),
        cursor_id: u.id
      }
  end
end
