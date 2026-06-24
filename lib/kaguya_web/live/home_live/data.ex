defmodule KaguyaWeb.HomeLive.Data do
  @moduledoc """
  Data assembly for the signed-in home page.

  LiveView talks to contexts directly. This module returns stable render maps
  so components do not depend on Ecto structs or side effects.
  """

  import Ecto.Query

  alias Kaguya.Activities
  alias Kaguya.Discussions
  alias Kaguya.Discussions.{Post, PostLike}
  alias Kaguya.Feed
  alias Kaguya.Lists
  alias Kaguya.Producers.Producer
  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review, ReviewLike}
  alias Kaguya.Social
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @feed_limit 15
  @activity_limit 20
  # Reviews and lists are excluded from the activity stream everywhere
  # — they have their own first-class slot in the home feed and the
  # `/reviews` / `/lists` pages. Mirrors `excludeActions` in the Next.js
  # `HomeActivityFeed.tsx` (see commits 888d4373 and ab1ac169).
  @activity_excluded_actions [:reviewed, :created_list]
  @list_cover_count 11

  def feed_limit, do: @feed_limit
  def activity_limit, do: @activity_limit

  def load_initial_page(viewer) do
    with {:ok, feed} <- load_feed(viewer, nil, @feed_limit),
         {:ok, activity} <- load_activity(viewer, :global, nil, @activity_limit) do
      {:ok,
       %{
         feed: feed,
         activity: activity,
         activity_type: :global,
         has_follows?: has_follows?(viewer),
         mobile_tab: :feed
       }}
    end
  end

  # Determines whether the Friends scope is reachable. The Friends/Global
  # filter is hidden for users who follow nobody — its only state would
  # be an empty list, so the control wouldn't earn its place.
  defp has_follows?(%{id: id}) when is_binary(id),
    do: Social.get_following_count(id) > 0

  defp has_follows?(_), do: false

  def load_feed(viewer, cursor, limit \\ @feed_limit) do
    viewer_id = viewer_id(viewer)
    allowed = TitleCategory.allowed_categories(viewer || %{})

    with {:ok, page} <- Feed.get_feed(viewer_id, cursor, limit, allowed_categories: allowed) do
      {:ok,
       %{
         items: normalize_feed_items(page.items, viewer_id),
         next_cursor: page.next_cursor,
         has_next: page.has_next
       }}
    end
  end

  def load_activity(viewer, type, cursor, limit) do
    viewer_id = viewer_id(viewer)

    opts = [
      allowed_categories: TitleCategory.allowed_categories(viewer || %{}),
      screenshot_prefs: screenshot_prefs_for(viewer),
      exclude_actions: @activity_excluded_actions
    ]

    result =
      case type do
        :following when is_binary(viewer_id) ->
          Activities.list_following_activities(viewer_id, cursor, limit, opts)

        :following ->
          {:ok, %{entries: [], next_cursor: nil, has_next: false}}

        _global ->
          Activities.list_global_activities(viewer_id, cursor, limit, opts)
      end

    with {:ok, page} <- result do
      page = Activities.preload_entry_associations(page)
      {:ok, normalize_activity_page(page, viewer_id)}
    end
  end

  def normalize_feed_items(items, viewer_id) do
    items
    |> preload_feed_items()
    |> hydrate_feed_items(viewer_id)
  end

  defp preload_feed_items(items) do
    reviews = items |> Enum.filter(&match?(%Review{}, &1)) |> Repo.preload([:user, :visual_novel])
    lists = items |> Enum.filter(&match?(%Lists.List{}, &1)) |> Repo.preload(:user)
    posts = items |> Enum.filter(&match?(%Post{}, &1)) |> preload_posts()

    loaded =
      (reviews ++ lists ++ posts)
      |> Map.new(&{{struct_type(&1), &1.id}, &1})

    Enum.map(items, &Map.fetch!(loaded, {struct_type(&1), &1.id}))
  end

  defp hydrate_feed_items(items, viewer_id) do
    review_ratings = review_ratings(items)
    liked_reviews = liked_review_ids(items, viewer_id)
    liked_posts = liked_post_ids(items, viewer_id)
    list_covers = list_covers(items)

    Enum.map(items, fn
      %Review{} = review ->
        {:review,
         normalize_review(review,
           rating: Map.get(review_ratings, {review.user_id, review.visual_novel_id}),
           liked_by_me: MapSet.member?(liked_reviews, review.id)
         )}

      %Lists.List{} = list ->
        {:list, normalize_list(list, Map.get(list_covers, list.id, []))}

      %Post{} = post ->
        {:post, normalize_post(post, MapSet.member?(liked_posts, post.id))}
    end)
  end

  defp normalize_activity_page(page, viewer_id) do
    rows = Enum.flat_map(page.entries, & &1.members)
    review_ratings = review_ratings(Enum.map(rows, & &1.review) |> Enum.reject(&is_nil/1))

    liked_reviews =
      liked_review_ids(Enum.map(rows, & &1.review) |> Enum.reject(&is_nil/1), viewer_id)

    list_covers = list_covers(Enum.map(rows, & &1.list) |> Enum.reject(&is_nil/1))

    entries =
      Enum.map(page.entries, fn entry ->
        %{
          id: entry.id,
          group_size: entry.group_size,
          members:
            Enum.map(entry.members, fn activity ->
              normalize_activity(activity, review_ratings, liked_reviews, list_covers)
            end)
        }
      end)

    %{
      entries: entries,
      next_cursor: page.next_cursor,
      has_next: page.has_next
    }
  end

  defp normalize_activity(activity, review_ratings, liked_reviews, list_covers) do
    # :user / :visual_novel on reviews and :user on lists are batched in
    # Kaguya.Activities.preload_entry_associations, so no per-row preload here.
    review =
      if activity.review do
        normalize_review(activity.review,
          rating:
            Map.get(review_ratings, {activity.review.user_id, activity.review.visual_novel_id}),
          liked_by_me: MapSet.member?(liked_reviews, activity.review.id)
        )
      end

    list =
      if activity.list do
        normalize_list(activity.list, Map.get(list_covers, activity.list.id, []))
      end

    %{
      id: activity.id,
      action: activity.action,
      entity_type: activity.entity_type,
      entity_id: activity.entity_id,
      metadata: activity.metadata || %{},
      inserted_at: activity.inserted_at,
      inserted_label: SharedTime.calendar_custom(activity.inserted_at),
      actor: normalize_user(activity.actor),
      review: review,
      list: list,
      followed_user: normalize_user(activity.followed_user),
      followed_producer: normalize_producer(activity.followed_producer),
      entity_ref: normalize_entity_ref(activity.entity_ref)
    }
  end

  defp preload_posts([]), do: []

  defp preload_posts(posts) do
    posts = Repo.preload(posts, [:user, :last_comment_user])
    entity_maps = load_entity_maps(posts)

    Enum.map(posts, fn post ->
      Map.put(post, :entity, entity_for_post(post, entity_maps))
    end)
  end

  defp load_entity_maps(posts) do
    ids_by_type =
      posts
      |> Enum.group_by(& &1.category_type, & &1.entity_id)
      |> Map.new(fn {type, ids} -> {type, ids |> Enum.reject(&is_nil/1) |> Enum.uniq()} end)

    %{
      visual_novel: load_map(VisualNovel, Map.get(ids_by_type, :visual_novel, [])),
      producer: load_map(Producer, Map.get(ids_by_type, :producer, [])),
      user: load_map(User, Map.get(ids_by_type, :user, []))
    }
  end

  defp load_map(_schema, []), do: %{}

  defp load_map(schema, ids) do
    Repo.all(from(e in schema, where: e.id in ^ids))
    |> Map.new(&{&1.id, &1})
  end

  defp entity_for_post(%{category_type: type, entity_id: id}, maps)
       when type in [:visual_novel, :producer, :user],
       do: get_in(maps, [type, id])

  defp entity_for_post(_post, _maps), do: nil

  defp normalize_review(review, opts) do
    %{
      id: review.id,
      content: review.content,
      comments_count: review.comments_count || 0,
      likes_count: review.likes_count || 0,
      liked_by_me: Keyword.get(opts, :liked_by_me, false),
      rating: rating_or_nil(Keyword.get(opts, :rating)),
      is_spoiler: review.is_spoiler,
      source: review.source,
      inserted_at: review.inserted_at,
      user: normalize_user(review.user),
      visual_novel: normalize_vn(review.visual_novel)
    }
  end

  defp normalize_list(list, covers) do
    %{
      id: list.id,
      name: list.name,
      slug: list.slug,
      description: list.description,
      likes_count: list.likes_count || 0,
      vns_count: list.vns_count || 0,
      is_public: list.is_public,
      inserted_at: list.inserted_at,
      last_activity_at: list.last_activity_at,
      activity_at: list.last_activity_at || list.inserted_at,
      activity_label: SharedTime.calendar_custom(list.last_activity_at || list.inserted_at),
      action_text: list_action_text(list),
      user: normalize_user(list.user),
      visual_novels: covers
    }
  end

  defp normalize_post(post, liked_by_me) do
    activity_at = post.last_comment_at || post.inserted_at

    %{
      id: post.id,
      title: post.title,
      slug: post.slug,
      short_id: post.short_id,
      content_preview: text_preview(strip_spoilers(post.content), 420),
      comments_count: post.comments_count || 0,
      likes_count: post.likes_count || 0,
      liked_by_me: liked_by_me,
      is_pinned: post.is_pinned,
      is_locked: post.is_locked,
      category_type: post.category_type,
      inserted_at: post.inserted_at,
      activity_at: activity_at,
      activity_label: SharedTime.calendar_custom(activity_at),
      user: normalize_user(post.user),
      entity: normalize_post_entity(post),
      url: post_url(post)
    }
  end

  defp normalize_post_entity(%{category_type: :visual_novel, entity: %VisualNovel{} = vn}),
    do: %{
      type: :visual_novel,
      href: "/vn/#{vn.slug}",
      label: vn.title,
      visual_novel: normalize_vn(vn)
    }

  defp normalize_post_entity(%{category_type: :producer, entity: %Producer{} = producer}),
    do: %{type: :producer, href: "/developer/#{producer.slug}", label: producer.name}

  defp normalize_post_entity(%{category_type: :user, entity: %User{} = user}) do
    user = normalize_user(user)
    %{type: :user, href: "/@#{user.username}", label: user.display_name, user: user}
  end

  defp normalize_post_entity(%{category_type: category}) do
    %{
      type: :category,
      href: "/discussions/#{category_slug(category)}",
      label: category_label(category)
    }
  end

  defp normalize_user(nil), do: nil

  defp normalize_user(%User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      avatar_url: avatar_urls[:small],
      avatar_urls: avatar_urls
    }
  end

  defp normalize_user(%{id: _} = user) do
    avatar_urls =
      case Map.get(user, :avatar_urls) || Map.get(user, "avatarUrls") do
        %{} = urls -> urls
        _ -> Users.build_avatar_urls(Map.get(user, :avatar_id))
      end

    %{
      id: Map.get(user, :id),
      username: Map.get(user, :username),
      display_name:
        Map.get(user, :display_name) || Map.get(user, :displayName) || Map.get(user, :username),
      avatar_url: avatar_urls[:small] || avatar_urls["small"],
      avatar_urls: avatar_urls
    }
  end

  defp normalize_vn(nil), do: nil

  defp normalize_vn(%VisualNovel{} = vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: VisualNovels.build_image_urls(vn),
      has_ero: VisualNovels.cover_nsfw?(vn),
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp normalize_vn(%{} = vn), do: vn

  defp normalize_producer(nil), do: nil

  defp normalize_producer(%Producer{} = producer),
    do: %{id: producer.id, name: producer.name, slug: producer.slug}

  defp normalize_producer(%{} = producer),
    do: %{id: producer[:id], name: producer[:name], slug: producer[:slug]}

  defp normalize_entity_ref(nil), do: nil
  defp normalize_entity_ref(%{} = ref), do: ref

  defp review_ratings(items) do
    keys =
      items
      |> Enum.filter(&match?(%Review{}, &1))
      |> Enum.map(&{&1.user_id, &1.visual_novel_id})
      |> Enum.uniq()

    if keys == [] do
      %{}
    else
      user_ids = Enum.map(keys, &elem(&1, 0))
      vn_ids = Enum.map(keys, &elem(&1, 1))

      Repo.all(
        from(r in Rating,
          where: r.user_id in ^user_ids and r.visual_novel_id in ^vn_ids,
          select: {{r.user_id, r.visual_novel_id}, r.rating}
        )
      )
      |> Map.new()
    end
  end

  defp liked_review_ids(_items, nil), do: MapSet.new()

  defp liked_review_ids(items, viewer_id) do
    ids =
      items
      |> Enum.filter(&match?(%Review{}, &1))
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    if ids == [] do
      MapSet.new()
    else
      Repo.all(
        from(l in ReviewLike,
          where: l.vn_review_id in ^ids and l.user_id == ^viewer_id,
          select: l.vn_review_id
        )
      )
      |> MapSet.new()
    end
  end

  defp liked_post_ids(_items, nil), do: MapSet.new()

  defp liked_post_ids(items, viewer_id) do
    ids =
      items
      |> Enum.filter(&match?(%Post{}, &1))
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    if ids == [] do
      MapSet.new()
    else
      Repo.all(
        from(l in PostLike,
          where: l.post_id in ^ids and l.user_id == ^viewer_id,
          select: l.post_id
        )
      )
      |> MapSet.new()
    end
  end

  defp list_covers(items) do
    list_tuples =
      items
      |> Enum.filter(&match?(%Lists.List{}, &1))
      |> Enum.map(&{&1.id, &1.vns_count || 0})

    list_tuples
    |> Lists.batch_list_vns_for_lists(@list_cover_count)
    |> Map.new(fn {list_id, page} ->
      covers =
        page.items
        |> Enum.map(fn item ->
          item.visual_novel
          |> normalize_vn()
          |> Map.merge(%{
            position: item.position,
            tier_id: item.tier_id,
            tier_position: item.tier_position
          })
        end)

      {list_id, covers}
    end)
  end

  defp post_url(%{
         category_type: :visual_novel,
         entity: %VisualNovel{slug: slug},
         short_id: short_id
       }),
       do: "/vn/#{slug}/discussions/#{short_id}"

  defp post_url(%{category_type: :producer, entity: %Producer{slug: slug}, short_id: short_id}),
    do: "/developer/#{slug}/discussions/#{short_id}"

  defp post_url(%{category_type: :user, entity: %User{username: username}, short_id: short_id}),
    do: "/@#{username}/discussions/#{short_id}"

  defp post_url(%{short_id: short_id, slug: slug}),
    do: "/discussions/p/#{short_id}/#{slug || "post"}"

  defp list_action_text(%{inserted_at: inserted, last_activity_at: last}) do
    if near?(inserted, last), do: "listed", else: "updated"
  end

  defp near?(nil, _), do: true
  defp near?(_, nil), do: true
  defp near?(a, b), do: abs(DateTime.diff(to_datetime(a), to_datetime(b), :second)) < 60

  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp text_preview(nil, _limit), do: nil

  defp text_preview(content, limit) do
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
    |> String.slice(0, limit)
    |> blank_to_nil()
  end

  defp strip_spoilers(nil), do: nil
  defp strip_spoilers(content), do: String.replace(content, ~r/\|\|[\s\S]*?\|\|/, "[spoiler]")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp rating_or_nil(nil), do: nil
  defp rating_or_nil(value) when is_number(value), do: Float.round(value * 1.0, 2)
  defp rating_or_nil(_), do: nil

  defp category_label(:announcements), do: "Announcements"
  defp category_label(:site_discussions), do: "Feedback"
  defp category_label(:general), do: "General"

  defp category_label(category),
    do: category |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp category_slug(category) do
    Discussions.Category.categories()
    |> Map.get(category)
    |> case do
      %{slug: slug} -> slug
      _ -> to_string(category)
    end
  end

  defp screenshot_prefs_for(%{} = user) do
    %{
      show_nsfw: Map.get(user, :show_nsfw_screenshots, false),
      show_brutal: Map.get(user, :show_brutal_screenshots, false)
    }
  end

  defp screenshot_prefs_for(_), do: %{show_nsfw: false, show_brutal: false}

  defp viewer_id(%{id: id}) when is_binary(id), do: id
  defp viewer_id(_viewer), do: nil

  defp struct_type(%Review{}), do: :review
  defp struct_type(%Lists.List{}), do: :list
  defp struct_type(%Post{}), do: :post
end
