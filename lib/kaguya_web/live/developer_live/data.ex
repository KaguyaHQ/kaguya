defmodule KaguyaWeb.DeveloperLive.Data do
  @moduledoc """
  View-model assembly for migrated developer pages.
  """

  import Ecto.Query

  alias Kaguya.Authorization
  alias Kaguya.Discussions
  alias Kaguya.Pagination
  alias Kaguya.Producers
  alias Kaguya.Repo
  alias Kaguya.Social
  alias Kaguya.Users

  @works_page_size 30
  @followers_limit 20
  @discussions_limit 5

  def works_page_size, do: @works_page_size
  def followers_limit, do: @followers_limit

  def load_show_page(slug, params, current_user) do
    page = parse_page(Map.get(params, "page"))

    with {:ok, producer} <- Producers.get_producer_by_slug(slug, viewer_opts(current_user)),
         {:ok, %{items: visual_novels, pagination: pagination}} <-
           Producers.get_visual_novels_for_producer(producer.id, page, @works_page_size),
         {:ok, discussions_page} <-
           Discussions.list_posts_for_entity(:producer, producer.id, %{
             viewer_id: viewer_id(current_user),
             limit: @discussions_limit
           }) do
      {:ok,
       %{
         slug: slug,
         page: page,
         producer: hydrate_producer(producer, current_user),
         visual_novels: visual_novels,
         pagination: resolve_pagination(pagination, visual_novels),
         discussions: normalize_discussions(discussions_page.items, producer.slug)
       }}
    end
  end

  def load_followers_page(slug, cursor, current_user) do
    with {:ok, producer} <- Producers.get_producer_by_slug(slug, viewer_opts(current_user)),
         {:ok, followers} <-
           Social.list_producer_followers(producer.id, cursor: cursor, limit: @followers_limit) do
      {:ok,
       %{
         producer: hydrate_producer(producer, current_user),
         followers: normalize_followers(followers.items, current_user),
         next_cursor: followers.next_cursor,
         has_next: followers.has_next
       }}
    end
  end

  def update_follow_state(%{id: id} = producer, current_user) do
    producer
    |> Map.put(:is_followed_by_me, follows?(current_user, id))
    |> Map.put(:follower_count, producer_follower_count(id))
  end

  def update_user_follow_state(followers, target_id, current_user) do
    Enum.map(followers, fn
      %{user: %{id: ^target_id} = user} = follower ->
        put_in(follower, [:user], put_user_follow_state(user, current_user))

      follower ->
        follower
    end)
  end

  defdelegate can_moderate_db?(user), to: Authorization

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> value
      _ -> 1
    end
  end

  def parse_page(_), do: 1

  defp hydrate_producer(producer, current_user) do
    producer
    |> Map.put(:is_followed_by_me, follows?(current_user, producer.id))
    |> Map.put(:can_edit, Producers.can_edit_producer?(producer, current_user))
    |> Map.put(:can_moderate_db, can_moderate_db?(current_user))
  end

  defp normalize_discussions([], _slug), do: []

  defp normalize_discussions(posts, slug) do
    posts
    |> Repo.preload([:user])
    |> Enum.map(fn post ->
      %{
        id: post.id,
        title: post.title || "Discussion",
        url: "/developer/#{slug}/discussions/#{post.short_id}",
        comments_count: post.comments_count || 0,
        likes_count: post.likes_count || 0,
        inserted_at: post.inserted_at,
        is_pinned: post.is_pinned,
        is_locked: post.is_locked,
        user: normalize_user(post.user)
      }
    end)
  end

  defp normalize_followers(items, current_user) do
    viewer_id = viewer_id(current_user)
    user_ids = items |> Enum.map(& &1.user.id) |> Enum.reject(&is_nil/1)

    followed_ids =
      if viewer_id, do: Social.batch_followed_ids(viewer_id, user_ids), else: MapSet.new()

    Enum.map(items, fn item ->
      user = item.user

      %{
        id: item.id,
        followed_at: item.followed_at,
        user:
          user
          |> normalize_user()
          |> Map.put(:follow_state, follow_state(user, viewer_id, followed_ids))
          |> Map.put(:is_followed_by_me, MapSet.member?(followed_ids, user.id))
      }
    end)
  end

  defp normalize_user(nil), do: nil

  defp normalize_user(user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username || "Unknown",
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp put_user_follow_state(%{id: id} = user, current_user) do
    viewer_id = viewer_id(current_user)
    state = Social.follow_state(viewer_id, id)

    user
    |> Map.put(:follow_state, state)
    |> Map.put(:is_followed_by_me, state == :following)
  end

  defp follow_state(%{id: id}, viewer_id, _followed_ids) when id == viewer_id, do: :self

  defp follow_state(%{id: id}, _viewer_id, followed_ids) do
    if MapSet.member?(followed_ids, id), do: :following, else: :not_following
  end

  defp resolve_pagination(pagination, visual_novels) do
    count = Pagination.resolve_count(pagination) || length(visual_novels)
    total_pages = Pagination.resolve_total_pages(pagination) || 1

    pagination
    |> Map.put(:total_count, count)
    |> Map.put(:total_pages, max(total_pages, 1))
  end

  defp follows?(%{id: viewer_id}, producer_id),
    do: Social.follows_producer?(viewer_id, producer_id)

  defp follows?(_, _), do: false

  defp producer_follower_count(producer_id) do
    Repo.one(
      from p in Kaguya.Producers.Producer, where: p.id == ^producer_id, select: p.follower_count
    ) || 0
  end

  defp viewer_id(%{id: id}) when is_binary(id), do: id
  defp viewer_id(_), do: nil

  defp viewer_opts(current_user) do
    if can_moderate_db?(current_user), do: [include_hidden: true], else: []
  end
end
