defmodule KaguyaWeb.Comments.DiscussionAdapter do
  @moduledoc """
  Post-backed implementation for the reusable LiveView comments component.
  """

  @behaviour KaguyaWeb.Comments.Adapter

  import Ecto.Query

  alias Kaguya.Discussions
  alias Kaguya.Discussions.{Comment, CommentLike}
  alias Kaguya.Repo
  alias Kaguya.Users
  alias KaguyaWeb.Discussions.Paths, as: DiscussionPaths

  @default_page_size 20

  @impl true
  def resource_type, do: :post_comment

  @impl true
  def load(post_id, viewer, opts) do
    page = int(Map.get(opts, :page, 1), 1)
    page_size = int(Map.get(opts, :page_size, @default_page_size), @default_page_size)
    viewer_id = user_id(viewer)
    focus_comment_id = blank_to_nil(Map.get(opts, :focus_comment_id))

    with {:ok, post} <- Discussions.get_post_for_view(post_id, viewer_id, viewer || %{}),
         {:ok, result} <-
           load_comments(post, focus_comment_id, viewer, viewer_id, page, page_size) do
      comments = Repo.preload(result.items, :user)
      liked_ids = liked_ids(comments, viewer_id)
      share_base_path = canonical_post_path(post)

      normalized_comments =
        Enum.map(comments, &normalize_comment(&1, liked_ids, share_base_path))

      {:ok,
       result
       |> Map.put(:items, normalized_comments)
       |> Map.put(:pagination, normalize_pagination(result.pagination, page, page_size))
       |> Map.put(:comments_count, post.comments_count || length(comments))}
    end
  end

  defp load_comments(post, nil, viewer, viewer_id, page, page_size) do
    with {:ok, %{items: comments, pagination: pagination}} <-
           Discussions.list_comments_for_post(
             post.id,
             post.comments_count || 0,
             %{page: page, page_size: page_size, sort_by: :oldest},
             viewer || viewer_id
           ) do
      {:ok, %{items: comments, pagination: pagination, focused_comment_id: nil}}
    end
  end

  defp load_comments(post, focus_comment_id, viewer, _viewer_id, _page, page_size) do
    with {:ok, focused_comment} <-
           Discussions.get_comment_for_post(post.id, focus_comment_id, viewer),
         {:ok, %{items: descendants, pagination: pagination}} <-
           Discussions.list_comment_descendants_for_comment(post.id, focused_comment.id, %{
             page_size: page_size,
             viewer: viewer
           }) do
      {:ok,
       %{
         items: [focused_comment | descendants],
         pagination: pagination,
         focused_comment_id: focused_comment.id
       }}
    end
  end

  @impl true
  def create(post_id, viewer, attrs) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_can_comment(post_id, viewer),
         {:ok, comment} <-
           Discussions.create_comment(%{
             post_id: post_id,
             user_id: user_id,
             parent_comment_id: blank_to_nil(Map.get(attrs, :parent_comment_id)),
             content: Map.get(attrs, :content)
           }) do
      liked_ids = liked_ids([comment], user_id)
      {:ok, comment |> Repo.preload(:user) |> normalize_comment(liked_ids)}
    end
  end

  @impl true
  def update(comment_id, viewer, attrs) do
    with {:ok, user_id} <- require_user(viewer),
         {:ok, comment} <-
           Discussions.update_comment(comment_id, user_id, Map.get(attrs, :content)) do
      liked_ids = liked_ids([comment], user_id)
      {:ok, comment |> Repo.preload(:user) |> normalize_comment(liked_ids)}
    end
  end

  @impl true
  def delete(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Discussions.delete_comment(comment_id, user_id)
  end

  @impl true
  def like(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer), do: Discussions.like_comment(comment_id, user_id)
  end

  @impl true
  def unlike(comment_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         do: Discussions.unlike_comment(comment_id, user_id)
  end

  @impl true
  def hide(comment_id, viewer, attrs) do
    with :ok <- require_moderator(viewer) do
      Discussions.hide_comment(
        comment_id,
        attrs
        |> Map.put_new(:actor_id, user_id(viewer))
        |> Map.put_new(:reason, "Hidden by moderator")
      )
    end
  end

  @impl true
  def unhide(comment_id, viewer) do
    with :ok <- require_moderator(viewer), do: Discussions.unhide_comment(comment_id)
  end

  @impl true
  def pin(comment_id, viewer) do
    with :ok <- require_moderator(viewer),
         do: Discussions.admin_moderate_comment(comment_id, %{is_pinned: true})
  end

  @impl true
  def unpin(comment_id, viewer) do
    with :ok <- require_moderator(viewer),
         do: Discussions.admin_moderate_comment(comment_id, %{is_pinned: false})
  end

  @impl true
  def can_comment?(post_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_discussion_privilege(viewer),
         {:ok, post} <- Discussions.get_post_for_viewer(post_id, user_id, viewer || %{}),
         :ok <- ensure_not_locked(post),
         :ok <- ensure_not_deleted(post) do
      true
    else
      _ -> false
    end
  end

  @impl true
  def can_moderate?(%{mod_discussions: true}), do: true
  def can_moderate?(%{role: :admin}), do: true
  def can_moderate?(%{role: "admin"}), do: true
  def can_moderate?(_viewer), do: false

  defp ensure_can_comment(post_id, viewer) do
    with {:ok, user_id} <- require_user(viewer),
         :ok <- ensure_discussion_privilege(viewer),
         {:ok, post} <- Discussions.get_post_for_viewer(post_id, user_id, viewer || %{}),
         :ok <- ensure_not_locked(post) do
      ensure_not_deleted(post)
    end
  end

  defp ensure_discussion_privilege(%{can_discuss: false}), do: {:error, :forbidden}
  defp ensure_discussion_privilege(_viewer), do: :ok

  defp ensure_not_locked(%{is_locked: true}), do: {:error, :locked}
  defp ensure_not_locked(_post), do: :ok

  defp ensure_not_deleted(%{deleted_at: nil}), do: :ok
  defp ensure_not_deleted(_post), do: {:error, :not_found}

  defp require_moderator(viewer) do
    if can_moderate?(viewer), do: :ok, else: {:error, :forbidden}
  end

  defp liked_ids(_comments, nil), do: MapSet.new()
  defp liked_ids([], _viewer_id), do: MapSet.new()

  defp liked_ids(comments, viewer_id) do
    ids = Enum.map(comments, & &1.id)

    CommentLike
    |> where([l], l.post_comment_id in ^ids and l.user_id == ^viewer_id)
    |> select([l], l.post_comment_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp normalize_comment(comment, liked_ids, share_base_path \\ nil)

  defp normalize_comment(%Comment{} = comment, liked_ids, share_base_path) do
    %{
      id: comment.id,
      short_id: comment.short_id,
      parent_comment_id: comment.parent_comment_id,
      content: comment.content || "",
      likes_count: comment.likes_count || 0,
      liked_by_me: MapSet.member?(liked_ids, comment.id),
      is_pinned: comment.is_pinned || false,
      is_edited: comment.is_edited || false,
      hidden_at: comment.hidden_at,
      # Only top-level non-hidden comments can be pinned (matches
      # `ensure_top_level_pin/2` + `check_not_hidden_for_pin/2` in
      # `Kaguya.Discussions`). Surfaced so the comments component can show
      # the Pin/Unpin menu item only when it would actually succeed.
      pin_eligible: is_nil(comment.parent_comment_id) and is_nil(comment.hidden_at),
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at,
      share_url: comment_share_url(share_base_path, comment.short_id),
      user: normalize_user(comment.user)
    }
  end

  # Reddit-style canonical comment URL: /discussions/p/<post>/<slug>/c/<comment>.
  # We always anchor on the standalone post path even when the viewer reached
  # the comment via an entity-scoped route, so a single shared URL points to
  # the same place no matter where it was copied from. Origin uses
  # `:frontend_url` (the public kaguya.io host) rather than `Endpoint.url()`,
  # which resolves to the API subdomain (api.kaguya.io) in prod.
  defp comment_share_url(base_path, short_id)
       when is_binary(base_path) and is_binary(short_id),
       do: frontend_url() <> base_path <> "/c/" <> short_id

  defp comment_share_url(_base_path, _short_id), do: nil

  defp frontend_url do
    :kaguya
    |> Application.get_env(:frontend_url, "https://kaguya.io")
    |> String.trim_trailing("/")
  end

  defp canonical_post_path(%{short_id: short_id, slug: slug}) when is_binary(short_id),
    do: DiscussionPaths.standalone_post_url(short_id, slug)

  defp canonical_post_path(_post), do: nil

  defp normalize_user(%Kaguya.Users.User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      role: user.role,
      # Surfaced so the comment header can render the "MOD" badge next to
      # the username — matches `DiscussionModBadge.tsx` (`role === "admin"`
      # || `modDiscussions === true`). Other adapters don't set this field
      # so the badge stays scoped to discussion comments.
      is_discussion_moderator: user.role == :admin or user.mod_discussions == true,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp normalize_user(_user), do: nil

  defp normalize_pagination(pagination, page, page_size) do
    total_count = Kaguya.Pagination.resolve_count(pagination) || 0

    total_pages =
      Kaguya.Pagination.resolve_total_pages(pagination) ||
        max(div(total_count + page_size - 1, page_size), 1)

    extra_fields =
      pagination
      |> Map.drop([:page, :page_size, :total_pages, :total_count, :_count_query, :_count_ref])

    Map.merge(extra_fields, %{
      page: Map.get(pagination, :page) || page,
      page_size: Map.get(pagination, :page_size) || page_size,
      total_pages: total_pages,
      total_count: total_count
    })
  end

  defp require_user(%{id: id}) when is_binary(id), do: {:ok, id}
  defp require_user(_viewer), do: {:error, :unauthenticated}

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_viewer), do: nil

  defp int(value, _default) when is_integer(value) and value > 0, do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
