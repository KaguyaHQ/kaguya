defmodule KaguyaWeb.Comments.ListAdapter do
  @moduledoc """
  List-backed implementation for the reusable LiveView comments component.
  """

  @behaviour KaguyaWeb.Comments.Adapter

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListComment, ListCommentLike}
  alias Kaguya.Pagination
  alias Kaguya.Repo
  alias Kaguya.Users

  @default_page_size 10

  @impl true
  def resource_type, do: :vn_list_comment

  @impl true
  def load(list_id, viewer, opts) do
    page = int(Map.get(opts, :page, 1), 1)
    page_size = int(Map.get(opts, :page_size, @default_page_size), @default_page_size)
    viewer_id = user_id(viewer)

    with {:ok, list} <- Lists.get_list_for_view(list_id, viewer_id) do
      if hidden_for_viewer?(list, viewer) do
        {:ok, %{items: [], pagination: empty_pagination(page, page_size), comments_count: 0}}
      else
        query =
          ListComment
          |> where([c], c.list_id == ^list_id)
          |> filter_visible_to(viewer)
          |> order_by([c], asc: c.inserted_at, asc: c.id)

        total_count = Repo.aggregate(query, :count, :id)
        {comments, pagination} = Pagination.paginate(query, page, page_size, total_count)
        comments = Repo.preload(comments, :user)
        liked_ids = liked_ids(comments, viewer_id)

        {:ok,
         %{
           items: Enum.map(comments, &normalize_comment(&1, liked_ids)),
           pagination: normalize_pagination(pagination, page, page_size),
           comments_count: list.comments_count || total_count
         }}
      end
    end
  end

  @impl true
  def create(list_id, viewer, attrs) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_can_comment(list_id, viewer),
         {:ok, comment} <-
           Lists.create_list_comment(%{
             list_id: list_id,
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
           Lists.update_list_comment(comment_id, user_id, Map.get(attrs, :content)) do
      liked_ids = liked_ids([comment], user_id)

      {:ok, comment |> Repo.preload(:user) |> normalize_comment(liked_ids)}
    end
  end

  @impl true
  def delete(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Lists.delete_list_comment(comment_id, user_id)
  end

  @impl true
  def like(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer), do: Lists.like_list_comment(comment_id, user_id)
  end

  @impl true
  def unlike(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Lists.unlike_list_comment(comment_id, user_id)
  end

  @impl true
  def hide(comment_id, viewer, attrs) do
    with :ok <- require_moderator(viewer) do
      Lists.hide_list_comment(
        comment_id,
        Map.put(attrs, :reason, Map.get(attrs, :reason, "Hidden by moderator"))
      )
    end
  end

  @impl true
  def unhide(comment_id, viewer) do
    with :ok <- require_moderator(viewer), do: Lists.unhide_list_comment(comment_id)
  end

  @impl true
  def can_comment?(list_id, viewer) do
    with {:ok, _user_id} <- require_user(viewer),
         :ok <- ensure_can_comment(list_id, viewer) do
      true
    else
      _ -> false
    end
  end

  @impl true
  def can_moderate?(%{mod_lists: true}), do: true
  def can_moderate?(%{role: :admin}), do: true
  def can_moderate?(%{role: "admin"}), do: true
  def can_moderate?(_viewer), do: false

  defp ensure_can_comment(list_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_comment_privilege(viewer),
         {:ok, list} <- Lists.get_list(list_id, user_id, viewer) do
      ensure_not_hidden_for_viewer(list, viewer)
    end
  end

  defp ensure_comment_privilege(viewer) do
    if Map.get(viewer || %{}, :can_list, true), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_not_hidden_for_viewer(list, viewer) do
    if hidden_for_viewer?(list, viewer), do: {:error, :not_found}, else: :ok
  end

  defp require_moderator(viewer) do
    if can_moderate?(viewer), do: :ok, else: {:error, :forbidden}
  end

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

  defp hidden_for_viewer?(%List{hidden_at: nil}, _viewer), do: false

  defp hidden_for_viewer?(%List{user_id: owner_id}, %{id: owner_id}) when not is_nil(owner_id),
    do: false

  defp hidden_for_viewer?(_list, viewer), do: not can_moderate?(viewer)

  defp liked_ids(_comments, nil), do: MapSet.new()
  defp liked_ids([], _viewer_id), do: MapSet.new()

  defp liked_ids(comments, viewer_id) do
    ids = Enum.map(comments, & &1.id)

    ListCommentLike
    |> where([l], l.vn_list_comment_id in ^ids and l.user_id == ^viewer_id)
    |> select([l], l.vn_list_comment_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp normalize_comment(%ListComment{} = comment, liked_ids) do
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

  defp normalize_user(_user), do: nil

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

  defp empty_pagination(page, page_size),
    do: %{page: page, page_size: page_size, total_pages: 1, total_count: 0}

  defp require_user(%{id: id}) when is_binary(id), do: {:ok, id}
  defp require_user(_viewer), do: {:error, :unauthenticated}

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_viewer), do: nil

  defp int(value, _default) when is_integer(value) and value > 0, do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
