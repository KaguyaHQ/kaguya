defmodule KaguyaWeb.ProfileLive.Data do
  @moduledoc """
  View-model assembly for the `/@:username` LiveView family.

  Loads the header view-model (shared by every profile tab) and exposes the
  viewer-permission flags consumed by the moderation panel. Each tab calls
  `load_header/2` first, then layers its own tab-private loader on top.

  Mirrors `KaguyaWeb.ListLive.Data` in style: authorization and persistence
  stay in `Kaguya.*` contexts; this module is web-facing glue that returns
  stable, render-ready maps.
  """

  import Ecto.Query

  alias Kaguya.{Library, Lists, Repo, Reviews, Shelves, Social, Users, VNTags}
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}

  # ---------------------------------------------------------------------------
  # Viewer helpers (mirror ListLive.Data — keep the surface consistent)
  # ---------------------------------------------------------------------------

  def viewer_id(%{id: id}) when is_binary(id), do: id
  def viewer_id(_viewer), do: nil

  def logged_in?(viewer), do: not is_nil(viewer_id(viewer))

  def same_user?(%{id: id}, id) when is_binary(id), do: true
  def same_user?(_viewer, _id), do: false

  @doc """
  Strip the `@` prefix from the URL segment. Routes are declared as
  `/@:username`; LiveView surfaces the param including the `@`.
  """
  def parse_username("@" <> rest), do: rest
  def parse_username(value) when is_binary(value), do: value
  def parse_username(_), do: ""

  # ---------------------------------------------------------------------------
  # Header loader
  # ---------------------------------------------------------------------------

  @doc """
  Loads the header view-model for a profile page.

  Returns `{:ok, view_model}` or `{:error, :not_found}` so the LiveView can
  branch into the 404 state. The view-model is the single source of truth
  for every header/nav prop — tabs should not re-derive these.
  """
  def load_header(username, viewer) when is_binary(username) do
    case Users.get_user_by_username(username) do
      {:ok, %User{} = user} -> {:ok, build_header(user, viewer)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def load_header(_, _), do: {:error, :not_found}

  defp build_header(%User{} = user, viewer) do
    viewer_id = viewer_id(viewer)
    is_mine = viewer_id == user.id

    allowed_categories =
      if is_mine, do: nil, else: TitleCategory.allowed_categories(viewer || %{})

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      role: user.role,
      bio: user.bio,
      avatar_urls: Users.build_avatar_urls(user.avatar_id),
      banner_urls: Users.build_banner_urls(user.banner_id),
      social_links: normalize_social_links(user.social_links),
      ratings_count: user.vn_ratings_count,
      ratings_dist: user.vn_ratings_dist,
      average_rating: user.vn_average_rating,
      inserted_at: user.inserted_at,
      counts: %{
        followers: Social.get_follower_count(user.id),
        following: Social.get_following_count(user.id),
        vns: Shelves.count_active_library_vns(user.id, allowed_categories),
        reviews: reviews_count_for(user, is_mine, viewer),
        lists: Lists.count_lists_for_user(user.id),
        tag_votes: VNTags.count_tag_votes_by_user(user.id),
        edits: user.edit_count || 0
      },
      viewer: %{
        id: viewer_id,
        is_mine: is_mine,
        is_logged_in: not is_nil(viewer_id),
        follow_state: Social.follow_state(viewer_id, user.id),
        is_followed_by_me: Social.follow_state(viewer_id, user.id) == :following
      }
    }
  end

  defp reviews_count_for(%User{vn_reviews_count: count}, true, _viewer), do: count || 0

  defp reviews_count_for(%User{id: user_id}, false, viewer) do
    allowed = TitleCategory.allowed_categories(viewer || %{})
    Reviews.count_reviews_for_user_filtered(user_id, allowed)
  end

  defp normalize_social_links(nil), do: %{instagram: nil, twitter: nil, tiktok: nil, website: nil}

  defp normalize_social_links(%{} = links) do
    %{
      instagram: Map.get(links, :instagram) || Map.get(links, "instagram"),
      twitter: Map.get(links, :twitter) || Map.get(links, "twitter"),
      tiktok: Map.get(links, :tiktok) || Map.get(links, "tiktok"),
      website: Map.get(links, :website) || Map.get(links, "website")
    }
  end

  # ---------------------------------------------------------------------------
  # Viewer permission flags (drive moderation panel visibility)
  # ---------------------------------------------------------------------------

  @doc """
  Flags consumed by the moderation panel trigger. Mirrors the Next.js
  `usePermissions()` hook.
  """
  def viewer_permissions(nil), do: %{any?: false}

  def viewer_permissions(viewer) when is_map(viewer) do
    is_admin = admin?(viewer)

    flags = %{
      is_admin: is_admin,
      can_moderate_db: is_admin or truthy(viewer, :mod_db),
      can_moderate_discussions: is_admin or truthy(viewer, :mod_discussions),
      can_moderate_reviews: is_admin or truthy(viewer, :mod_reviews),
      can_moderate_lists: is_admin or truthy(viewer, :mod_lists),
      can_manage_users: is_admin or truthy(viewer, :mod_users)
    }

    Map.put(flags, :any?, Enum.any?(Map.values(flags)))
  end

  defp admin?(%{role: :admin}), do: true
  defp admin?(%{role: "admin"}), do: true
  defp admin?(_), do: false

  defp truthy(map, key), do: Map.get(map, key) == true

  # ---------------------------------------------------------------------------
  # Misc normalizers
  # ---------------------------------------------------------------------------

  @doc """
  Normalize a User struct into the minimal shape used by row-level renders
  (e.g. activity items, follow cards, review headers). Mirrors
  `KaguyaWeb.ListLive.Data.normalize_user/1`.
  """
  def normalize_user(%User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small],
      role: user.role
    }
  end

  def normalize_user(_user) do
    %{
      id: nil,
      username: nil,
      display_name: nil,
      avatar_urls: %{},
      avatar_url: nil,
      role: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Followers / following page loader
  # ---------------------------------------------------------------------------

  @doc """
  Loads one cursor page for `/@:username/followers`.

  Mirrors Next's `FollowersVn` query: each user row carries profile identity,
  VN/review counts, viewer follow state, and up to four `READ` library covers.
  """
  def load_followers(username, cursor, limit, viewer) do
    with {:ok, page} <- Social.list_followers(username, cursor, limit) do
      {:ok, decorate_follow_page(page, viewer)}
    end
  end

  @doc """
  Loads one cursor page for `/@:username/following`.
  """
  def load_following(username, cursor, limit, viewer) do
    with {:ok, page} <- Social.list_following(username, cursor, limit) do
      {:ok, decorate_follow_page(page, viewer)}
    end
  end

  defp decorate_follow_page(page, viewer) do
    items =
      page.items
      |> Enum.reject(&is_nil/1)
      |> hydrate_follow_users(viewer)

    %{
      items: items,
      next_cursor: page.next_cursor,
      has_next: page.has_next
    }
  end

  defp hydrate_follow_users(users, viewer) do
    viewer_id = viewer_id(viewer)
    allowed = TitleCategory.allowed_categories(viewer || %{})
    user_ids = Enum.map(users, & &1.id)

    vns_counts = follow_library_counts(user_ids, allowed, viewer_id)
    review_counts = follow_review_counts(user_ids, allowed, viewer_id, users)
    followed_ids = followed_ids(viewer_id, user_ids)

    Enum.map(users, fn user ->
      self? = user.id == viewer_id
      avatar_urls = Users.build_avatar_urls(user.avatar_id)

      %{
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username || "Unknown",
        avatar_urls: avatar_urls,
        avatar_url: avatar_urls[:medium] || avatar_urls[:small],
        vns_count: Map.get(vns_counts, user.id, 0),
        reviews_count: Map.get(review_counts, user.id, 0),
        follow_state: follow_state(user, viewer_id, followed_ids),
        is_followed_by_me: MapSet.member?(followed_ids, user.id),
        library_visual_novels: read_library_preview(user.id, if(self?, do: nil, else: allowed))
      }
    end)
  end

  defp follow_library_counts([], _allowed, _viewer_id), do: %{}

  defp follow_library_counts(user_ids, allowed, viewer_id) do
    {own_ids, other_ids} = Enum.split_with(user_ids, &(&1 == viewer_id))

    own_counts =
      Map.new(own_ids, fn id -> {id, Shelves.count_active_library_vns(id, nil)} end)

    Map.merge(own_counts, library_counts_query(other_ids, allowed))
  end

  defp library_counts_query([], _allowed), do: %{}

  defp library_counts_query(user_ids, allowed) do
    ReadingStatus
    |> where([s], s.user_id in ^user_ids)
    |> where([s], s.status not in [:not_interested, :want_to_read])
    |> join(:inner, [s], vn in VisualNovel, on: vn.id == s.visual_novel_id)
    |> maybe_filter_category(allowed)
    |> group_by([s], s.user_id)
    |> select([s], {s.user_id, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp follow_review_counts([], _allowed, _viewer_id, _users), do: %{}

  defp follow_review_counts(user_ids, allowed, viewer_id, users) do
    {own_ids, other_ids} = Enum.split_with(user_ids, &(&1 == viewer_id))
    users_by_id = Map.new(users, &{&1.id, &1})

    own_counts =
      Map.new(own_ids, fn id ->
        user = Map.get(users_by_id, id)
        {id, (user && user.vn_reviews_count) || 0}
      end)

    Map.merge(own_counts, review_counts_query(other_ids, allowed))
  end

  defp review_counts_query([], _allowed), do: %{}

  defp review_counts_query(user_ids, allowed) do
    Review
    |> where([r], r.user_id in ^user_ids and is_nil(r.hidden_at))
    |> join(:inner, [r], vn in VisualNovel, on: vn.id == r.visual_novel_id)
    |> maybe_filter_category(allowed)
    |> group_by([r], r.user_id)
    |> select([r], {r.user_id, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp read_library_preview(user_id, allowed) do
    args = %{status: :read, page: 1, page_size: 4}

    case Library.list_library_visual_novels(user_id, args, allowed_categories: allowed) do
      {:ok, {entries, _pagination}} ->
        Enum.map(entries, &normalize_follow_vn/1)

      _ ->
        []
    end
  end

  defp normalize_follow_vn(%{visual_novel: %VisualNovel{} = vn}) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp followed_ids(nil, _target_ids), do: MapSet.new()
  defp followed_ids(_viewer_id, []), do: MapSet.new()
  defp followed_ids(viewer_id, target_ids), do: Social.batch_followed_ids(viewer_id, target_ids)

  defp follow_state(%{id: id}, viewer_id, _followed_ids) when id == viewer_id, do: :self

  defp follow_state(%{id: id}, _viewer_id, followed_ids) do
    if MapSet.member?(followed_ids, id), do: :following, else: :not_following
  end

  defp maybe_filter_category(query, nil), do: query

  defp maybe_filter_category(query, allowed_categories) do
    where(query, [_row, vn], vn.title_category in ^allowed_categories)
  end

  @doc """
  Page title for any profile route. Tab modules append their own suffix
  (e.g. `" — Activity"`).
  """
  def page_title(profile, suffix \\ nil)

  def page_title(%{display_name: name}, suffix) when is_binary(name) do
    if suffix, do: "#{name} — #{suffix} · Kaguya", else: "#{name} · Kaguya"
  end

  def page_title(_, _), do: "Profile · Kaguya"
end
