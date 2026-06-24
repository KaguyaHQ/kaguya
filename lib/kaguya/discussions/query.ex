defmodule Kaguya.Discussions.Query do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Users.User

  def filter_hidden(query, nil) do
    from(q in query, where: is_nil(q.hidden_at) and is_nil(q.deleted_at))
  end

  def filter_hidden(query, viewer_id) do
    from(q in query,
      where:
        (is_nil(q.hidden_at) and is_nil(q.deleted_at)) or
          (q.user_id == ^viewer_id and is_nil(q.deleted_at))
    )
  end

  # For comment listings: keep deleted comments (frontend renders tombstones),
  # but still filter mod-hidden comments for non-owners.
  def filter_hidden_comments(query, %{mod_discussions: true}), do: query
  def filter_hidden_comments(query, %{role: :admin}), do: query
  def filter_hidden_comments(query, %User{role: :admin}), do: query
  def filter_hidden_comments(query, %User{mod_discussions: true}), do: query

  def filter_hidden_comments(query, nil) do
    from(q in query, where: is_nil(q.hidden_at))
  end

  def filter_hidden_comments(query, viewer_id) do
    viewer_id = viewer_id(viewer_id)

    if is_nil(viewer_id) do
      filter_hidden_comments(query, nil)
    else
      from(q in query, where: is_nil(q.hidden_at) or q.user_id == ^viewer_id)
    end
  end

  def viewer_id(nil), do: nil
  def viewer_id(%{id: id}), do: id
  def viewer_id(%User{id: id}), do: id
  def viewer_id(id), do: id

  def maybe_filter_category(query, nil), do: query

  def maybe_filter_category(query, category_type),
    do: from(t in query, where: t.category_type == ^category_type)

  def maybe_filter_entity(query, nil), do: query

  def maybe_filter_entity(query, entity_id),
    do: from(t in query, where: t.entity_id == ^entity_id)

  def apply_comment_sorting(query, :newest), do: order_by(query, [c], desc: c.inserted_at)
  def apply_comment_sorting(query, :oldest), do: order_by(query, [c], asc: c.inserted_at)
  def apply_comment_sorting(query, :most_liked), do: order_by(query, [c], desc: c.likes_count)
  def apply_comment_sorting(query, _), do: order_by(query, [c], desc: c.inserted_at)

  def cursor_config(:recent_activity), do: {[:last_comment_at, :id], [:datetime, :string]}
  def cursor_config(:newest), do: {[:inserted_at, :id], [:datetime, :string]}
  def cursor_config(:most_liked), do: {[:likes_count, :id], [:int, :string]}
  def cursor_config(_), do: {[:last_comment_at, :id], [:datetime, :string]}
end
