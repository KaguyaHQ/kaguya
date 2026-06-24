defmodule KaguyaWeb.DiscussionLive.Data do
  @moduledoc """
  Data loading and normalization for migrated discussion LiveViews.

  LiveView calls the Phoenix context directly and keeps data loading in the
  page layer explicit.
  """

  import Ecto.Query

  alias Kaguya.Characters.Character
  alias Kaguya.Discussions
  alias Kaguya.Discussions.{Category, PostLike}
  alias Kaguya.Producers.Producer
  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @posts_page_size 20

  def load_index_page(params, current_user) do
    sort_by = sort_by(Map.get(params, "sort"))
    viewer_id = current_user && current_user.id

    with {:ok, posts_page} <- list_posts_page(nil, sort_by, nil, viewer_id),
         {:ok, pinned_posts} <- Discussions.list_pinned_posts(nil, viewer_id) do
      {:ok,
       %{
         sort: sort_url(sort_by),
         posts: posts_page.items |> preload_posts() |> Enum.map(&normalize_post/1),
         pinned_posts: pinned_posts |> preload_posts() |> Enum.map(&normalize_post/1),
         has_next: posts_page.has_next,
         next_cursor: posts_page.next_cursor,
         categories: categories(),
         can_discuss: can_discuss?(current_user),
         can_moderate_discussions: can_moderate_discussions?(current_user)
       }}
    end
  end

  def load_category_page(slug, params, current_user) do
    with {:ok, category} <- category_by_slug(slug),
         sort_by <- sort_by(Map.get(params, "sort")),
         viewer_id <- current_user && current_user.id,
         {:ok, posts_page} <- list_posts_page(category.type, sort_by, nil, viewer_id),
         {:ok, pinned_posts} <- Discussions.list_pinned_posts(category.type, viewer_id) do
      {:ok,
       %{
         category: category,
         sort: sort_url(sort_by),
         posts: posts_page.items |> preload_posts() |> Enum.map(&normalize_post/1),
         pinned_posts: pinned_posts |> preload_posts() |> Enum.map(&normalize_post/1),
         has_next: posts_page.has_next,
         next_cursor: posts_page.next_cursor,
         categories: categories(),
         can_discuss: can_discuss?(current_user),
         can_moderate_discussions: can_moderate_discussions?(current_user)
       }}
    end
  end

  def load_more_posts(category_type, sort, cursor, current_user) do
    sort_by = sort_by(sort)
    viewer_id = current_user && current_user.id

    with {:ok, posts_page} <- list_posts_page(category_type, sort_by, cursor, viewer_id) do
      {:ok,
       %{
         posts: posts_page.items |> preload_posts() |> Enum.map(&normalize_post/1),
         has_next: posts_page.has_next,
         next_cursor: posts_page.next_cursor
       }}
    end
  end

  def load_post_page(short_id, current_user) do
    viewer_id = current_user && current_user.id

    with {:ok, post} <-
           Discussions.get_post_by_short_id_for_view(short_id, viewer_id, current_user || %{}) do
      post =
        post
        |> Repo.preload([:user, :last_comment_user])
        |> attach_entities()

      {:ok,
       %{
         post: normalize_post_detail(post, liked_post?(post.id, viewer_id), current_user),
         can_discuss: can_discuss?(current_user),
         can_moderate_discussions: can_moderate_discussions?(current_user)
       }}
    end
  end

  def categories do
    Category.categories()
    |> Enum.sort_by(fn {_type, config} -> config.position end)
    |> Enum.map(fn {type, config} ->
      %{
        type: type,
        name: config.name,
        slug: config.slug,
        admin_only: config.admin_only
      }
    end)
  end

  def category_by_slug(slug) do
    categories()
    |> Enum.find(&(&1.slug == slug))
    |> case do
      nil -> {:error, :not_found}
      category -> {:ok, category}
    end
  end

  defp sort_by(:newest), do: :newest
  defp sort_by(:most_liked), do: :most_liked
  defp sort_by(:recent_activity), do: :recent_activity
  defp sort_by("newest"), do: :newest
  defp sort_by("most-liked"), do: :most_liked
  defp sort_by(_sort), do: :recent_activity

  defp sort_url(:newest), do: "newest"
  defp sort_url(:most_liked), do: "most-liked"
  defp sort_url(_sort), do: "recent"

  defp list_posts_page(category_type, sort_by, cursor, viewer_id) do
    Discussions.list_posts(%{
      category_type: category_type,
      sort_by: sort_by,
      cursor: cursor,
      viewer_id: viewer_id,
      limit: @posts_page_size
    })
  end

  defp preload_posts([]), do: []

  defp preload_posts(posts) do
    posts = Repo.preload(posts, [:user, :last_comment_user])

    recent_users_by_post_id =
      Discussions.recent_comment_users_by_post_ids(Enum.map(posts, & &1.id))

    entity_maps = load_entity_maps(posts)

    Enum.map(posts, fn post ->
      post
      |> Map.put(:recent_comment_users, Map.get(recent_users_by_post_id, post.id, []))
      |> Map.put(:entity, entity_for_post(post, entity_maps))
    end)
  end

  defp attach_entities(post) do
    entity_maps = load_entity_maps([post])
    recent_comment_users = Discussions.recent_comment_users_by_post_ids([post.id])

    post
    |> Map.put(:entity, entity_for_post(post, entity_maps))
    |> Map.put(:recent_comment_users, Map.get(recent_comment_users, post.id, []))
  end

  defp load_entity_maps(posts) do
    ids_by_type =
      posts
      |> Enum.group_by(& &1.category_type, & &1.entity_id)
      |> Map.new(fn {type, ids} -> {type, ids |> Enum.reject(&is_nil/1) |> Enum.uniq()} end)

    %{
      visual_novel: load_map(VisualNovel, Map.get(ids_by_type, :visual_novel, [])),
      producer: load_map(Producer, Map.get(ids_by_type, :producer, [])),
      character: load_map(Character, Map.get(ids_by_type, :character, [])),
      user: load_map(User, Map.get(ids_by_type, :user, []))
    }
  end

  defp load_map(_schema, []), do: %{}

  defp load_map(schema, ids) do
    Repo.all(from(e in schema, where: e.id in ^ids))
    |> Map.new(&{&1.id, &1})
  end

  defp entity_for_post(%{category_type: type, entity_id: id}, maps)
       when type in [:visual_novel, :producer, :character, :user],
       do: get_in(maps, [type, id])

  defp entity_for_post(_post, _maps), do: nil

  defp normalize_post(post) do
    activity_at = post.last_comment_at || post.inserted_at

    %{
      id: post.id,
      title: display_title(post),
      content_preview: content_preview(post.content),
      comments_count: post.comments_count || 0,
      likes_count: post.likes_count || 0,
      activity_at: activity_at,
      activity_from_now: SharedTime.calendar_custom(activity_at),
      inserted_at: post.inserted_at,
      is_pinned: post.is_pinned,
      is_locked: post.is_locked,
      is_removed: !!post.hidden_at,
      url: post_url(post),
      user: normalize_user(post.user),
      last_comment_user: normalize_user(post.last_comment_user),
      recent_comment_users: Enum.map(post.recent_comment_users || [], &normalize_user/1),
      entity_tag: entity_tag(post)
    }
  end

  defp normalize_post_detail(post, liked_by_me, current_user) do
    post
    |> normalize_post()
    |> Map.merge(%{
      short_id: post.short_id,
      slug: post.slug,
      content: post.content,
      hidden_at: post.hidden_at,
      hidden_reason: post.hidden_reason,
      deleted_at: post.deleted_at,
      deleted_by_type: post.deleted_by_type,
      is_edited: post.is_edited,
      liked_by_me: liked_by_me,
      can_modify:
        Discussions.can_modify?(
          post,
          current_user && current_user.id,
          current_user && current_user.role
        )
    })
  end

  defp display_title(%{hidden_at: hidden_at, title: title})
       when not is_nil(hidden_at) and title in [nil, ""],
       do: "Removed post"

  defp display_title(%{title: title}), do: title

  defp content_preview(nil), do: nil

  defp content_preview(content) do
    content
    |> String.replace(~r/\|\|[\s\S]*?\|\|/, "[spoiler]")
    |> String.replace(~r/```[\s\S]*?```/, " ")
    |> String.replace(~r/`([^`]+)`/, "\\1")
    |> String.replace(~r/!\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/(\*\*|__)(.+?)\1/, "\\2")
    |> String.replace(~r/(\*|_)(.+?)\1/, "\\2")
    |> String.replace(~r/~~(.+?)~~/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 300)
    |> blank_to_nil()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp entity_tag(%{category_type: :visual_novel, entity: %{slug: slug, title: title}}),
    do: %{href: "/vn/#{slug}", label: title}

  defp entity_tag(%{category_type: :producer, entity: %{slug: slug, name: name}}),
    do: %{href: "/developer/#{slug}", label: name}

  defp entity_tag(%{category_type: :character, entity: %{slug: slug, name: name}}),
    do: %{href: "/character/#{slug}", label: name}

  defp entity_tag(%{category_type: :user, entity: %{username: username}}),
    do: %{href: "/@#{username}", label: "@#{username}"}

  defp entity_tag(_post), do: nil

  defp normalize_user(nil), do: nil

  defp normalize_user(user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      role: user.role,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp liked_post?(_post_id, nil), do: false

  defp liked_post?(post_id, user_id) do
    Repo.exists?(from(l in PostLike, where: l.post_id == ^post_id and l.user_id == ^user_id))
  end

  def post_url(%{category_type: :visual_novel, entity: %{slug: entity_slug}, short_id: short_id}),
    do: "/vn/#{entity_slug}/discussions/#{short_id}"

  def post_url(%{category_type: :producer, entity: %{slug: entity_slug}, short_id: short_id}),
    do: "/developer/#{entity_slug}/discussions/#{short_id}"

  def post_url(%{category_type: :character, entity: %{slug: entity_slug}, short_id: short_id}),
    do: "/character/#{entity_slug}/discussions/#{short_id}"

  def post_url(%{category_type: :user, entity: %{username: username}, short_id: short_id}),
    do: "/@#{username}/discussions/#{short_id}"

  def post_url(%{short_id: short_id, slug: slug}),
    do: "/discussions/p/#{short_id}/#{slug || "post"}"

  defp can_discuss?(%{can_discuss: true}), do: true
  defp can_discuss?(_user), do: false

  # Match the comment adapter's `can_moderate?/1`: site admins inherit
  # discussion moderation rights even without the explicit
  # `mod_discussions` flag set. Without this, an admin viewing someone
  # else's post sees no mod actions on the dropdown.
  defp can_moderate_discussions?(%{mod_discussions: true}), do: true
  defp can_moderate_discussions?(%{role: :admin}), do: true
  defp can_moderate_discussions?(%{role: "admin"}), do: true
  defp can_moderate_discussions?(_user), do: false
end
