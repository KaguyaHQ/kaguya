defmodule Kaguya.Discussions.Comments do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Comments, as: GenericComments
  alias Kaguya.CursorPagination
  alias Kaguya.Pagination
  alias Kaguya.Repo
  alias Kaguya.Activities
  alias Kaguya.Discussions.{Comment, Counters, Pins, Policy, Post, Posts, Query, SideEffects}

  @max_pinned_comments_per_post 3
  @focused_comment_max_depth 5
  @focused_comment_max_descendants 200

  def create_comment(attrs) do
    post_id = attrs.post_id

    with {:ok, post} <- Posts.get_post_for_viewer(post_id, attrs.user_id),
         :ok <- Policy.check_not_deleted(post),
         :ok <- Policy.check_not_locked(post),
         :ok <- Policy.check_parent_comment_for_post(attrs, post_id) do
      after_create = fn _comment, _parent ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.update_all(
          from(t in Post, where: t.id == ^post_id),
          set: [last_comment_at: now, last_comment_user_id: attrs.user_id]
        )

        :ok
      end

      with {:ok, comment} <-
             GenericComments.create_comment(SideEffects.post_comment_config(post), attrs,
               after_create: after_create
             ) do
        SideEffects.record_comment_activity(comment, post)
        {:ok, comment}
      end
    end
  end

  def get_comment(id), do: GenericComments.get_comment(Comment, id)

  def get_comment_for_post(post_id, comment_id, viewer \\ nil) do
    query =
      from(c in Comment,
        where: c.post_id == ^post_id and c.id == ^comment_id and is_nil(c.deleted_at)
      )
      |> Query.filter_hidden_comments(viewer)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment}
    end
  end

  def get_comment_by_short_id_for_post(post_id, short_id, viewer \\ nil)
      when is_binary(short_id) do
    query =
      from(c in Comment,
        where: c.post_id == ^post_id and c.short_id == ^short_id and is_nil(c.deleted_at)
      )
      |> Query.filter_hidden_comments(viewer)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment}
    end
  end

  def list_comment_descendants_for_comment(post_id, parent_comment_id, params \\ %{}) do
    viewer = Map.get(params, :viewer) || Map.get(params, :viewer_id)
    page_size = Map.get(params, :page_size, 20)
    max_depth = non_negative_int(Map.get(params, :max_depth), @focused_comment_max_depth)
    max_descendants = non_negative_int(Map.get(params, :limit), @focused_comment_max_descendants)

    query =
      from(c in Comment, where: c.post_id == ^post_id and is_nil(c.deleted_at))
      |> Query.filter_hidden_comments(viewer)

    {comments, truncated?} =
      [parent_comment_id]
      |> list_bounded_thread_descendants(query, max_depth, max_descendants)

    comments = prune_orphaned_descendants(comments, parent_comment_id)

    pagination = %{
      page: 1,
      page_size: page_size,
      total_count: length(comments),
      total_pages: 1,
      truncated?: truncated?
    }

    {:ok, %{items: comments, pagination: pagination}}
  end

  def update_comment(comment_id, user_id, content) do
    with {:ok, comment} <- Policy.get_comment_by_owner(comment_id, user_id),
         :ok <- Policy.check_not_deleted(comment) do
      GenericComments.update_comment(Comment, comment_id, user_id, %{
        content: content,
        is_edited: true
      })
    end
  end

  def admin_moderate_comment(comment_id, attrs) do
    with {:ok, comment} <- get_comment(comment_id),
         :ok <- Policy.check_not_deleted(comment),
         :ok <- Pins.check_comment_not_hidden_for_pin(comment, attrs),
         :ok <- Pins.ensure_top_level_comment_pin(comment, attrs) do
      case Map.get(attrs, :is_pinned) do
        true -> pin_comment(comment)
        false -> unpin_comment(comment)
        _ -> {:ok, comment}
      end
    end
  end

  def delete_comment(comment_id, user_id) do
    with {:ok, comment} <- Policy.get_comment_by_owner(comment_id, user_id),
         :ok <- Policy.check_not_deleted(comment) do
      soft_delete_comment(comment, :user)
    end
  end

  defp soft_delete_comment(comment, deleted_by_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    post_id = comment.post_id
    was_visible = is_nil(comment.hidden_at)

    result =
      Repo.transact(fn ->
        with {:ok, _} <-
               comment
               |> Ecto.Changeset.change(
                 deleted_at: now,
                 deleted_by_type: deleted_by_type,
                 is_pinned: false,
                 pinned_at: nil
               )
               |> Repo.update() do
          if was_visible do
            from(t in Post, where: t.id == ^post_id)
            |> Repo.update_all(inc: [comments_count: -1])
          end

          {:ok, true}
        end
      end)

    with {:ok, true} <- result do
      Activities.delete_activities_for_entity("post_comment", comment.id)
      if post_id, do: Counters.recalculate_last_comment(post_id)
      {:ok, true}
    end
  end

  def list_comments_for_post(post_id, comments_count, params, viewer_id \\ nil) do
    sort_by = Map.get(params, :sort_by, :newest)
    page = Map.get(params, :page, 1)
    page_size = Map.get(params, :page_size, 20)

    # `Query.filter_hidden_comments/2` only excludes `hidden_at` — soft-deleted
    # rows (set by `soft_delete_comment/2`) still come through unless we
    # also filter `deleted_at`. Without this an author who deletes their
    # own comment still sees the stale row on the next page load.
    base =
      from(c in Comment, where: c.post_id == ^post_id and is_nil(c.deleted_at))
      |> Query.filter_hidden_comments(viewer_id)

    # Mirror the cursor-paginated version: on the first page we prepend
    # pinned top-level comments (capped by @max_pinned_comments_per_post)
    # and exclude them from the paginated body so they don't show up twice.
    # Without this the LiveView discussion adapter would silently ignore
    # pin state — comments stayed in their natural sort order even after
    # a mod hit Pin.
    pinned_parents = if page == 1, do: list_pinned_parent_comments(base), else: []

    paginated_query =
      base
      |> exclude_pinned_parent_comments()
      |> Query.apply_comment_sorting(sort_by)

    {rest, pagination} = Pagination.paginate(paginated_query, page, page_size, comments_count)

    {:ok, %{items: pinned_parents ++ rest, pagination: pagination}}
  end

  def list_comments_for_post_cursor(post_id, params) do
    viewer = Map.get(params, :viewer)
    viewer_id = Map.get(params, :viewer_id) || Query.viewer_id(viewer)
    sort_by = Map.get(params, :sort_by, :oldest)
    cursor = Map.get(params, :cursor)
    limit = Map.get(params, :limit, 20)

    query =
      from(c in Comment, where: c.post_id == ^post_id)
      |> Query.filter_hidden_comments(viewer || viewer_id)

    if sort_by == :most_liked do
      list_most_liked_parent_comment_threads_with_pins(query, params, cursor, limit)
    else
      pinned_comments = if is_nil(cursor), do: list_pinned_parent_comments(query), else: []
      query = exclude_pinned_parent_comments(query)

      list_flat_comments_for_post_cursor(query, params, cursor, limit, pinned_comments)
    end
  end

  defp list_flat_comments_for_post_cursor(query, params, cursor, limit, pinned_comments) do
    sort_by = Map.get(params, :sort_by, :oldest)

    {fields, types, order} = comment_cursor_config(sort_by)

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        query,
        fields,
        types,
        cursor,
        limit,
        order
      )

    {:ok, %{items: pinned_comments ++ items, next_cursor: next_cursor, has_next: has_next}}
  end

  defp list_most_liked_parent_comment_threads_with_pins(query, params, cursor, limit) do
    pinned_parents = if is_nil(cursor), do: list_pinned_parent_comments(query), else: []
    pinned_replies = list_thread_replies(Enum.map(pinned_parents, & &1.id), query)
    query = exclude_pinned_parent_comments(query)

    with {:ok, page} <-
           list_most_liked_parent_comment_threads(query, Map.put(params, :limit, limit)) do
      {:ok, %{page | items: pinned_parents ++ pinned_replies ++ page.items}}
    end
  end

  defp list_pinned_parent_comments(query) do
    query
    |> where(
      [c],
      is_nil(c.parent_comment_id) and c.is_pinned == true and is_nil(c.hidden_at) and
        is_nil(c.deleted_at)
    )
    |> order_by([c], desc_nulls_last: c.pinned_at, desc: c.inserted_at, desc: c.id)
    |> limit(^@max_pinned_comments_per_post)
    |> Repo.all()
  end

  defp exclude_pinned_parent_comments(query) do
    where(query, [c], c.is_pinned == false or not is_nil(c.parent_comment_id))
  end

  defp comment_cursor_config(:newest), do: {[:inserted_at, :id], [:datetime, :string], :desc}
  defp comment_cursor_config(:oldest), do: {[:inserted_at, :id], [:datetime, :string], :asc}
  defp comment_cursor_config(_), do: {[:inserted_at, :id], [:datetime, :string], :asc}

  defp list_most_liked_parent_comment_threads(query, params) do
    parent_query = from(c in query, where: is_nil(c.parent_comment_id))

    {parents, next_cursor, has_next} =
      CursorPagination.paginate(
        parent_query,
        [:likes_count, :id],
        [:int, :string],
        Map.get(params, :cursor),
        Map.get(params, :limit, 20),
        :desc
      )

    parent_ids = Enum.map(parents, & &1.id)

    replies = list_thread_replies(parent_ids, query)

    {:ok, %{items: parents ++ replies, next_cursor: next_cursor, has_next: has_next}}
  end

  defp list_thread_replies([], _query), do: []

  defp list_thread_replies(parent_ids, query) do
    base = from(c in Comment, where: c.id in ^parent_ids, select: c.id)

    recursive =
      from c in Comment,
        join: ct in "comment_tree",
        on: c.parent_comment_id == ct.id,
        select: c.id

    comment_tree = base |> union_all(^recursive)

    query
    |> recursive_ctes(true)
    |> with_cte("comment_tree", as: ^comment_tree)
    |> join(:inner, [c], ct in "comment_tree", on: c.id == ct.id)
    |> where([c, _ct], c.id not in ^parent_ids)
    |> order_by([c, _ct], asc: c.inserted_at, asc: c.id)
    |> Repo.all()
  end

  defp list_bounded_thread_descendants(parent_ids, query, max_depth, max_descendants) do
    do_list_bounded_thread_descendants(parent_ids, query, max_depth, max_descendants, [])
  end

  defp non_negative_int(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> default
    end
  end

  defp non_negative_int(_value, default), do: default

  defp do_list_bounded_thread_descendants([], _query, _depth_left, _remaining, acc),
    do: {acc, false}

  defp do_list_bounded_thread_descendants(_parent_ids, _query, _depth_left, 0, acc),
    do: {acc, true}

  defp do_list_bounded_thread_descendants(parent_ids, query, 0, _remaining, acc) do
    has_more? =
      query
      |> where([c], c.parent_comment_id in ^parent_ids)
      |> limit(1)
      |> Repo.exists?()

    {acc, has_more?}
  end

  defp do_list_bounded_thread_descendants(parent_ids, query, depth_left, remaining, acc) do
    children =
      query
      |> where([c], c.parent_comment_id in ^parent_ids)
      |> order_by([c], asc: c.inserted_at, asc: c.id)
      |> limit(^(remaining + 1))
      |> Repo.all()

    {children, truncated?} = Enum.split(children, remaining)

    if truncated? != [] do
      {acc ++ children, true}
    else
      children
      |> Enum.map(& &1.id)
      |> do_list_bounded_thread_descendants(
        query,
        depth_left - 1,
        remaining - length(children),
        acc ++ children
      )
    end
  end

  defp prune_orphaned_descendants(comments, root_id) do
    {_visible_ids, visible_comments} =
      Enum.reduce(comments, {MapSet.new([root_id]), []}, fn comment, {visible_ids, acc} ->
        if MapSet.member?(visible_ids, comment.parent_comment_id) do
          {MapSet.put(visible_ids, comment.id), [comment | acc]}
        else
          {visible_ids, acc}
        end
      end)

    Enum.reverse(visible_comments)
  end

  def pin_comment(%Comment{} = comment) do
    now = DateTime.utc_now()

    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "post-comment-pins:#{comment.post_id}"
      ])

      other_pinned_ids =
        Comment
        |> where(
          [c],
          c.post_id == ^comment.post_id and is_nil(c.parent_comment_id) and c.is_pinned == true and
            is_nil(c.hidden_at) and is_nil(c.deleted_at) and
            c.id != ^comment.id
        )
        |> order_by([c], desc_nulls_last: c.pinned_at, desc: c.inserted_at, desc: c.id)
        |> select([c], c.id)
        |> Repo.all()

      ids_to_unpin = Enum.drop(other_pinned_ids, @max_pinned_comments_per_post - 1)

      unless ids_to_unpin == [] do
        Comment
        |> where([c], c.id in ^ids_to_unpin)
        |> Repo.update_all(set: [is_pinned: false, pinned_at: nil])
      end

      comment
      |> Ecto.Changeset.change(is_pinned: true, pinned_at: now)
      |> Repo.update()
    end)
  end

  def unpin_comment(%Comment{} = comment) do
    comment
    |> Ecto.Changeset.change(is_pinned: false, pinned_at: nil)
    |> Repo.update()
  end

  def unpin_comments([]), do: :ok

  def unpin_comments(comment_ids) do
    Comment
    |> where([c], c.id in ^comment_ids and c.is_pinned == true)
    |> Repo.update_all(set: [is_pinned: false, pinned_at: nil])

    :ok
  end
end
