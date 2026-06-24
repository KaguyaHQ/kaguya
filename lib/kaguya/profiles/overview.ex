defmodule Kaguya.Profiles.Overview do
  @moduledoc """
  One-shot batched view-model loader for the `/@:username` overview LiveView.

  Builds the profile overview shape directly from Phoenix contexts. All fields
  the overview tab renders come from this single `profile_overview/2` call.
  """

  import Ecto.Query

  alias Kaguya.Repo

  alias Kaguya.Activities
  alias Kaguya.Characters.{Character, CharacterFavorite}
  alias Kaguya.Library
  alias Kaguya.Lists
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Social
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VisualNovels.TitleCategory

  @doc """
  Builds the view-model for the `/@:username` overview LiveView in one pass.

  Returns a normalized map; entry shapes match what the overview template
  expects so the LiveView can render without re-mapping.
  """
  def profile_overview(%User{} = user, viewer \\ nil) do
    user_id = user.id
    is_mine = is_map(viewer) and Map.get(viewer, :id) == user_id
    allowed = if is_mine, do: nil, else: TitleCategory.allowed_categories(viewer || %{})

    %{
      favorite_visual_novels: load_favorite_vns(user.favorite_visual_novels, allowed),
      favorite_characters: load_favorite_characters(user_id),
      vn_finished: load_status_vns(user_id, :read, 6, allowed, with_rating: true),
      vn_currently_reading: load_status_vns(user_id, :currently_reading, 4, allowed),
      vn_want_to_read: load_status_vns(user_id, :want_to_read, 8, allowed),
      want_to_read_count: status_count(user_id, :want_to_read, allowed),
      shelves: load_user_shelves(user_id),
      popular_lists: load_popular_lists(user, viewer, allowed),
      popular_reviews: load_user_reviews(user_id, viewer, :most_liked, allowed),
      recent_reviews: load_user_reviews(user_id, viewer, :newest, allowed),
      following_preview: load_following_preview(user_id),
      recent_activity: load_recent_activity(user_id, viewer, allowed),
      ratings: %{
        count: user.vn_ratings_count || 0,
        average: user.vn_average_rating || 0.0,
        dist: user.vn_ratings_dist || List.duplicate(0, 10)
      }
    }
  end

  defp load_favorite_vns([], _allowed), do: []
  defp load_favorite_vns(nil, _allowed), do: []

  defp load_favorite_vns(ids, allowed) when is_list(ids) do
    ids = Enum.take(ids, 4)

    query =
      VisualNovel
      |> where([vn], vn.id in ^ids)
      |> maybe_filter_category(allowed)

    by_id = query |> Repo.all() |> Map.new(&{&1.id, &1})

    ids
    |> Enum.map(&Map.get(by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&decorate_vn/1)
  end

  defp load_favorite_characters(user_id) do
    from(c in Character,
      join: cf in CharacterFavorite,
      on: cf.character_id == c.id,
      where: cf.user_id == ^user_id,
      order_by: [asc: cf.position, asc: cf.inserted_at],
      limit: 4
    )
    |> Repo.all()
    |> Enum.map(&decorate_character/1)
  end

  defp load_status_vns(user_id, status, limit, allowed, opts \\ []) do
    with_rating = Keyword.get(opts, :with_rating, false)

    pairs =
      VisualNovel
      |> join(:inner, [vn], rs in ReadingStatus,
        on: rs.visual_novel_id == vn.id and rs.user_id == ^user_id and rs.status == ^status,
        as: :reading_status
      )
      |> maybe_filter_category(allowed)
      |> order_status_vns(status)
      |> limit(^limit)
      |> select([vn, reading_status: rs], {vn, rs})
      |> Repo.all()

    vn_ids = Enum.map(pairs, fn {vn, _rs} -> vn.id end)

    ratings =
      if with_rating and vn_ids != [],
        do: Library.batch_ratings_for_user(user_id, vn_ids),
        else: %{}

    reviews =
      if with_rating and vn_ids != [],
        do: Library.batch_reviews_for_user(user_id, vn_ids),
        else: %{}

    Enum.map(pairs, fn {vn, _rs} ->
      decorate_status_vn(vn, with_rating, ratings, reviews)
    end)
  end

  defp decorate_status_vn(vn, false, _ratings, _reviews), do: decorate_vn(vn)

  defp decorate_status_vn(vn, true, ratings, reviews) do
    Map.merge(decorate_vn(vn), %{
      rating: Map.get(ratings, vn.id),
      review_id: review_id(Map.get(reviews, vn.id))
    })
  end

  defp review_id(%Review{id: id}), do: id
  defp review_id(nil), do: nil

  defp order_status_vns(query, :read),
    do:
      order_by(query, [reading_status: rs],
        desc_nulls_last: rs.date_finished,
        desc: rs.library_added_at
      )

  defp order_status_vns(query, _status),
    do: order_by(query, [reading_status: rs], desc: rs.library_added_at)

  defp status_count(user_id, status, allowed) do
    VisualNovel
    |> join(:inner, [vn], rs in ReadingStatus,
      on: rs.visual_novel_id == vn.id and rs.user_id == ^user_id and rs.status == ^status
    )
    |> maybe_filter_category(allowed)
    |> Repo.aggregate(:count, :id)
  end

  defp load_user_shelves(user_id) do
    case Shelves.list_shelves_for_user(user_id) do
      {:ok, shelves} ->
        Enum.map(shelves, fn s ->
          %{id: s.id, name: s.name, slug: s.slug, vns_count: s.vns_count}
        end)

      _ ->
        []
    end
  end

  defp load_popular_lists(%User{} = user, viewer, _allowed) do
    viewer_id = viewer && Map.get(viewer, :id)

    {:ok, %{items: lists}} =
      Lists.list_user_lists(user.id, viewer_id, %{
        page: 1,
        page_size: 2,
        sort_by: :likes_desc,
        skip_count: true
      })

    lists = Repo.preload(lists, :user)

    list_ids = Enum.map(lists, & &1.id)
    covers_by_list = load_list_covers(list_ids)

    Enum.map(lists, fn list ->
      covers = Map.get(covers_by_list, list.id, [])

      %{
        id: list.id,
        name: list.name,
        slug: list.slug,
        description: list.description,
        is_public: list.is_public,
        vns_count: list.vns_count,
        likes_count: list.likes_count,
        username: user.username,
        user: normalize_list_owner(list.user, user),
        cover_urls: covers,
        visual_novels: Enum.map(covers, &%{visual_novel: &1})
      }
    end)
  end

  defp load_list_covers([]), do: %{}

  defp load_list_covers(list_ids) do
    rows =
      from(li in Lists.ListItem,
        join: vn in VisualNovel,
        on: vn.id == li.visual_novel_id,
        where: li.list_id in ^list_ids,
        order_by: [asc: li.list_id, asc: li.position],
        select: {li.list_id, vn}
      )
      |> Repo.all()

    rows
    |> Enum.group_by(fn {lid, _vn} -> lid end, fn {_lid, vn} -> vn end)
    |> Map.new(fn {lid, vns} ->
      covers =
        vns
        |> Enum.take(5)
        |> Enum.map(fn vn ->
          %{
            id: vn.id,
            title: vn.title,
            slug: vn.slug,
            images: VisualNovels.build_image_urls(vn),
            has_ero: vn.has_ero,
            is_image_nsfw: Map.get(vn, :is_image_nsfw, false),
            is_image_suggestive: Map.get(vn, :is_image_suggestive, false)
          }
        end)

      {lid, covers}
    end)
  end

  defp normalize_list_owner(%User{} = user, _fallback) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      avatar_url: avatar_urls[:small],
      avatar_urls: avatar_urls
    }
  end

  defp normalize_list_owner(_, %User{} = fallback) do
    %{
      id: fallback.id,
      username: fallback.username,
      display_name: fallback.username,
      avatar_url: nil,
      avatar_urls: %{}
    }
  end

  defp load_user_reviews(user_id, viewer, sort_by, allowed) do
    viewer_id = viewer && Map.get(viewer, :id)

    {:ok, %{items: items}} =
      Reviews.list_reviews_for_user(
        user_id,
        %{page: 1, page_size: 2, sort_by: sort_by, skip_count: true},
        viewer_id,
        allowed_categories: allowed
      )

    vn_ids = items |> Enum.map(& &1.visual_novel_id) |> Enum.reject(&is_nil/1)

    vns_by_id =
      VisualNovel
      |> where([vn], vn.id in ^vn_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    review_ids = Enum.map(items, & &1.id)
    liked_ids = Reviews.liked_review_ids_in(viewer_id, review_ids) |> MapSet.new()

    items
    |> Enum.map(&Map.put(&1, :visual_novel, Map.get(vns_by_id, &1.visual_novel_id)))
    |> Repo.preload(:user)
    |> Enum.map(&decorate_review/1)
    |> Enum.map(&Map.put(&1, :liked_by_me, MapSet.member?(liked_ids, &1.id)))
  end

  defp load_following_preview(user_id) do
    case Social.list_following_by_user_id(user_id, nil, 12) do
      {:ok, %{items: items}} -> Enum.map(items, &decorate_following_user/1)
      _ -> []
    end
  end

  defp load_recent_activity(user_id, viewer, allowed) do
    allowed_categories = allowed || [:vn, :nukige, :adjacent]

    {:ok, conn} =
      Activities.list_activities_for_user(user_id,
        limit: 5,
        viewer_id: viewer && Map.get(viewer, :id),
        allowed_categories: allowed_categories
      )

    %{items: items} = Activities.preload_associations(conn)

    Enum.map(items, &decorate_activity/1)
  end

  # nil = no filtering (own library), list = filter by viewer's allowed categories
  defp maybe_filter_category(query, nil), do: query

  defp maybe_filter_category(query, allowed),
    do: where(query, [vn], vn.title_category in ^allowed)

  # ------------------------------------------------------------------
  # Decorators (turn schemas into stable, render-ready maps)
  # ------------------------------------------------------------------

  defp decorate_vn(%VisualNovel{} = vn) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp decorate_character(%Character{} = c) do
    %{
      id: c.id,
      name: c.name,
      slug: c.slug,
      images: VisualNovels.build_character_image_urls(c),
      is_image_nsfw: Map.get(c, :is_image_nsfw, false),
      is_image_suggestive: Map.get(c, :is_image_suggestive, false)
    }
  end

  defp decorate_review(%Review{} = r) do
    vn = Map.get(r, :visual_novel)

    %{
      id: r.id,
      content: r.content,
      rating: Map.get(r, :rating),
      likes_count: r.likes_count || 0,
      comments_count: r.comments_count || 0,
      is_spoiler: r.is_spoiler || false,
      is_edited: r.is_edited || false,
      inserted_at: r.inserted_at,
      liked_by_me: false,
      user: decorate_review_user(r.user),
      visual_novel: vn && decorate_vn(vn)
    }
  end

  defp decorate_review_user(%User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      avatar_urls: avatar_urls,
      avatar_url: Map.get(avatar_urls, :small)
    }
  end

  defp decorate_review_user(_), do: nil

  defp decorate_following_user(%User{} = u) do
    avatar_urls = Users.build_avatar_urls(u.avatar_id)

    %{
      id: u.id,
      username: u.username,
      display_name: u.display_name || u.username,
      avatar_urls: avatar_urls,
      avatar_url: Map.get(avatar_urls, :small)
    }
  end

  defp decorate_following_user(nil), do: nil

  defp decorate_activity(activity) do
    %{
      id: activity.id,
      action: activity.action,
      metadata: activity.metadata || %{},
      inserted_at: activity.inserted_at,
      entity_type: activity.entity_type,
      entity_id: activity.entity_id,
      entity_ref: Map.get(activity, :entity_ref),
      followed_user: decorate_following_user(Map.get(activity, :followed_user)),
      followed_producer: decorate_followed_producer(Map.get(activity, :followed_producer))
    }
  end

  defp decorate_followed_producer(nil), do: nil

  defp decorate_followed_producer(producer) do
    %{
      id: producer.id,
      name: Map.get(producer, :name),
      slug: Map.get(producer, :slug)
    }
  end
end
