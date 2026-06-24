defmodule Kaguya.Comments do
  @moduledoc """
  Provides common CRUD operations for comments, generalized across multiple types.
  """

  alias Kaguya.Repo
  alias Kaguya.Moderation.Reasons
  import Ecto.Query
  alias Kaguya.Social
  alias Kaguya.Pagination
  alias Kaguya.CursorPagination

  @doc """
  Generic function to get a comment by schema and id.
  """
  def get_comment(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment}
    end
  end

  @doc """
  Returns a paginated and sorted list of comments for a given parent.
  """
  def list_comments_for(
        comment_schema,
        parent_field,
        parent_id,
        comments_count,
        %{page: page, page_size: page_size} = params
      ) do
    sort_by = Map.get(params, :sort_by, :newest)
    viewer_id = Map.get(params, :viewer_id)

    query =
      comment_schema
      |> where([c], field(c, ^parent_field) == ^parent_id)
      |> filter_hidden_comments(viewer_id)
      |> apply_sorting(sort_by)

    {comments, pagination} = Pagination.paginate(query, page, page_size, comments_count)
    {:ok, %{items: comments, pagination: pagination}}
  end

  @doc """
  Returns a cursor-paginated list of comments for a given parent.
  """
  def list_comments_for_cursor(comment_schema, parent_field, parent_id, params) do
    cursor = Map.get(params, :cursor)
    limit = Map.get(params, :limit, 20)
    sort_by = Map.get(params, :sort_by, :oldest)
    viewer_id = Map.get(params, :viewer_id)

    query =
      comment_schema
      |> where([c], field(c, ^parent_field) == ^parent_id)
      |> filter_hidden_comments(viewer_id)

    {fields, types, order} = comment_cursor_config(sort_by)

    {items, next_cursor, has_next} =
      CursorPagination.paginate(query, fields, types, cursor, limit, order)

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  defp comment_cursor_config(:newest), do: {[:inserted_at, :id], [:datetime, :string], :desc}
  defp comment_cursor_config(:oldest), do: {[:inserted_at, :id], [:datetime, :string], :asc}
  defp comment_cursor_config(_), do: {[:inserted_at, :id], [:datetime, :string], :asc}

  defp filter_hidden_comments(query, nil) do
    where(query, [c], is_nil(c.hidden_at))
  end

  defp filter_hidden_comments(query, viewer_id) do
    where(query, [c], is_nil(c.hidden_at) or c.user_id == ^viewer_id)
  end

  defp apply_sorting(query, sort_by) do
    case sort_by do
      :newest -> order_by(query, [c], desc: c.inserted_at)
      :oldest -> order_by(query, [c], asc: c.inserted_at)
      :most_liked -> order_by(query, [c], desc: c.likes_count)
      _ -> order_by(query, [c], desc: c.inserted_at)
    end
  end

  @doc """
  Creates a comment generically using the provided config.
  """
  def create_comment(config, attrs, opts \\ []) do
    after_create = Keyword.get(opts, :after_create, fn _comment, _parent -> :ok end)

    should_run_side_effects =
      Keyword.get(opts, :should_run_side_effects, fn comment ->
        # Default: If the comment has a `:status` field, only run side effects when active.
        # If it does not, run side effects (maintains backwards compatibility for other schemas).
        case Map.get(comment, :status) do
          nil -> true
          :active -> true
          "active" -> true
          _ -> false
        end
      end)

    Repo.transact(fn ->
      with {:ok, comment} <- Repo.insert(config.comment_changeset.(attrs)),
           {:ok, parent} <- {:ok, config.get_parent.(attrs)},
           :ok <- ensure_after_create(after_create, comment, parent) do
        if should_run_side_effects.(comment) do
          with {count, _} <-
                 update_comment_count(config.parent_schema, config.parent_id_field.(attrs), 1),
               true <- count > 0 do
            if comment.parent_comment_id do
              parent_comment = Repo.get!(config.comment_schema, comment.parent_comment_id)

              Social.create_notification(%{
                user_id: parent_comment.user_id,
                action: :reply,
                entity_type: Map.get(config, :reply_entity_type, :comment),
                entity_id: parent_comment.id,
                actor_id: comment.user_id,
                metadata: config.build_metadata.(parent, comment),
                idempotency_key: "comment:reply:" <> to_string(comment.id)
              })
            else
              Social.create_notification(%{
                user_id: config.get_parent_owner.(parent),
                action: :new_comment,
                entity_type: config.entity_type,
                entity_id: parent.id,
                actor_id: comment.user_id,
                metadata: config.build_metadata.(parent, comment),
                idempotency_key: "comment:new:" <> to_string(comment.id)
              })
            end
          else
            _ -> {:error, :no_update}
          end
        end

        {:ok, comment}
      else
        _ -> {:error, :no_update}
      end
    end)
  end

  @doc """
  Updates a comment generically.
  """
  def update_comment(schema, comment_id, user_id, attrs) do
    case Repo.get_by(schema, id: comment_id, user_id: user_id) do
      nil -> {:error, :not_found}
      comment -> comment |> schema.changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Deletes a comment generically.
  """
  def delete_comment(schema, parent_schema, comment_id, user_id, parent_id_field) do
    case Repo.get_by(schema, id: comment_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      comment ->
        Repo.transact(fn ->
          with {:ok, delete_count} <- delete_comment_subtree(schema, comment.id),
               {count, _} <-
                 update_comment_count(
                   parent_schema,
                   Map.get(comment, parent_id_field),
                   -delete_count
                 ) do
            if count > 0, do: {:ok, true}, else: {:error, :no_update}
          end
        end)
    end
  end

  @doc """
  Collects all comment IDs in a subtree (the comment + all nested replies).
  Used for activity cleanup before deletion.
  """
  def collect_subtree_ids(schema, comment_id) do
    base = from c in schema, where: c.id == ^comment_id, select: c.id

    recursive =
      from c in schema,
        join: ct in "comment_tree",
        on: c.parent_comment_id == ct.id,
        select: c.id

    comment_tree = base |> union_all(^recursive)

    query =
      schema
      |> recursive_ctes(true)
      |> with_cte("comment_tree", as: ^comment_tree)
      |> join(:inner, [c], ct in "comment_tree", on: c.id == ct.id)
      |> select([c, _ct], c.id)

    Repo.all(query)
  end

  defp update_comment_count(schema, id, delta) do
    Repo.update_all(from(s in schema, where: s.id == ^id), inc: [comments_count: delta])
  end

  # Deletes the target comment and its entire reply subtree in one set-based DELETE so we get
  # an accurate row count without raw SQL. Works even with `on_delete: :delete_all` FKs because
  # all rows are part of the same delete statement.
  defp delete_comment_subtree(schema, comment_id) do
    base = from c in schema, where: c.id == ^comment_id

    recursive =
      from c in schema,
        join: ct in "comment_tree",
        on: c.parent_comment_id == ct.id,
        select: c

    comment_tree =
      base
      |> union_all(^recursive)

    delete_query =
      schema
      |> recursive_ctes(true)
      |> with_cte("comment_tree", as: ^comment_tree)
      |> join(:inner, [c], ct in "comment_tree", on: c.id == ct.id)
      |> select([c, _ct], c)

    {count, _} = Repo.delete_all(delete_query)

    {:ok, count}
  end

  @doc """
  Hides a comment and its entire subtree. Decrements the parent's comments_count.
  All newly hidden comments share the same hidden_at timestamp so unhide can
  distinguish them from independently hidden children. If an already-hidden
  subtree root is hidden again, its matching subtree is re-stamped so unhide of
  the original parent does not revive the independently moderated branch.
  """
  def hide_comment_subtree(
        comment_schema,
        parent_schema,
        comment_id,
        parent_id_field,
        attrs \\ %{}
      ) do
    attrs = normalize_moderation_attrs(attrs)

    with {:ok, reason} <- Reasons.normalize_optional(Map.get(attrs, :reason)),
         {:ok, mod_note} <- Reasons.normalize_optional(Map.get(attrs, :mod_note)) do
      subtree_ids = collect_subtree_ids(comment_schema, comment_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case Repo.get(comment_schema, comment_id) do
        nil ->
          {:error, :not_found}

        comment ->
          {:ok, hidden_count} =
            Repo.transact(fn ->
              {hidden_count, _} =
                hide_visible_comments(
                  comment_schema,
                  subtree_ids,
                  comment_id,
                  now,
                  reason,
                  mod_note
                )

              if not is_nil(comment.hidden_at) do
                restamp_hidden_comments(
                  comment_schema,
                  subtree_ids,
                  comment_id,
                  comment.hidden_at,
                  now,
                  reason,
                  mod_note
                )
              end

              if hidden_count > 0 do
                update_comment_count(
                  parent_schema,
                  Map.get(comment, parent_id_field),
                  -hidden_count
                )
              end

              {:ok, hidden_count}
            end)

          {:ok, hidden_count}
      end
    end
  end

  defp hide_visible_comments(comment_schema, subtree_ids, comment_id, now, reason, mod_note) do
    Repo.update_all(
      from(c in comment_schema,
        where: c.id in ^subtree_ids and is_nil(c.hidden_at),
        update: [set: ^hidden_update_fields(comment_schema, comment_id, now, reason, mod_note)]
      ),
      []
    )
  end

  defp restamp_hidden_comments(
         comment_schema,
         subtree_ids,
         comment_id,
         previous_hidden_at,
         now,
         reason,
         mod_note
       ) do
    Repo.update_all(
      from(c in comment_schema,
        where: c.id in ^subtree_ids and c.hidden_at == ^previous_hidden_at,
        update: [set: ^hidden_update_fields(comment_schema, comment_id, now, reason, mod_note)]
      ),
      []
    )
  end

  defp hidden_update_fields(comment_schema, comment_id, now, reason, mod_note) do
    fields = comment_schema.__schema__(:fields)

    [hidden_at: now]
    |> maybe_put_hidden_field(fields, :hidden_reason, comment_id, reason)
    |> maybe_put_hidden_field(fields, :hidden_mod_note, comment_id, mod_note)
  end

  defp maybe_put_hidden_field(updates, fields, field, comment_id, value) do
    if field in fields do
      Keyword.put(
        updates,
        field,
        dynamic(
          [c],
          fragment(
            "CASE WHEN ? = ? THEN ? ELSE NULL END",
            c.id,
            type(^comment_id, :binary_id),
            ^value
          )
        )
      )
    else
      updates
    end
  end

  @doc """
  Unhides a comment and children that were hidden at the same time (same hidden_at).
  Independently hidden children (different hidden_at) stay hidden.
  """
  def unhide_comment_subtree(comment_schema, parent_schema, comment_id, parent_id_field) do
    case Repo.get(comment_schema, comment_id) do
      nil ->
        {:error, :not_found}

      %{hidden_at: nil} ->
        {:ok, 0}

      comment ->
        subtree_ids = collect_subtree_ids(comment_schema, comment_id)
        hidden_at = comment.hidden_at

        # Only unhide comments with the exact same hidden_at as the parent
        {unhidden_count, _} =
          Repo.update_all(
            from(c in comment_schema,
              where: c.id in ^subtree_ids and c.hidden_at == ^hidden_at
            ),
            set: unhide_update_fields(comment_schema)
          )

        if unhidden_count > 0 do
          update_comment_count(parent_schema, Map.get(comment, parent_id_field), unhidden_count)
        end

        {:ok, unhidden_count}
    end
  end

  defp unhide_update_fields(comment_schema) do
    fields = comment_schema.__schema__(:fields)

    [hidden_at: nil]
    |> maybe_put_nil_hidden_field(fields, :hidden_reason)
    |> maybe_put_nil_hidden_field(fields, :hidden_mod_note)
  end

  defp maybe_put_nil_hidden_field(updates, fields, field) do
    if field in fields, do: Keyword.put(updates, field, nil), else: updates
  end

  defp ensure_after_create(callback, comment, parent) do
    case callback.(comment, parent) do
      :ok -> :ok
      {:ok, _} -> :ok
      other -> {:error, {:after_create_failed, other}}
    end
  end

  defp normalize_moderation_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_moderation_attrs(reason) when is_binary(reason), do: %{reason: reason}
  defp normalize_moderation_attrs(_attrs), do: %{}
end
