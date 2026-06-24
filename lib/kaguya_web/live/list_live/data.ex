defmodule KaguyaWeb.ListLive.Data do
  @moduledoc """
  View-model assembly for the LiveView list pages.

  This module is intentionally web-facing glue: authorization and persistence
  stay in `Kaguya.Lists`, while LiveViews get stable maps they can render or
  pass to small JS islands.
  """

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListLike}
  alias Kaguya.Repo
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.TitleCategory

  @list_page_size 100

  @default_tiers [
    %{id: "tier-s", label: "S", color: "#f87171", position: 1},
    %{id: "tier-a", label: "A", color: "#fb923c", position: 2},
    %{id: "tier-b", label: "B", color: "#facc15", position: 3},
    %{id: "tier-c", label: "C", color: "#4ade80", position: 4},
    %{id: "tier-d", label: "D", color: "#60a5fa", position: 5}
  ]

  def list_page_size, do: @list_page_size
  def default_tiers, do: @default_tiers

  def viewer_id(%{id: id}) when is_binary(id), do: id
  def viewer_id(_viewer), do: nil

  def logged_in?(viewer), do: not is_nil(viewer_id(viewer))

  def same_user?(%{id: id}, id) when is_binary(id), do: true
  def same_user?(_viewer, _id), do: false

  def can_moderate_lists?(%{mod_lists: true}), do: true
  def can_moderate_lists?(%{role: :admin}), do: true
  def can_moderate_lists?(%{role: "admin"}), do: true
  def can_moderate_lists?(_viewer), do: false

  def can_publish_public_lists?(%{can_list: false}), do: false
  def can_publish_public_lists?(_viewer), do: true

  def load_index_page(viewer) do
    viewer_id = viewer_id(viewer)
    allowed = TitleCategory.allowed_categories(viewer || %{})

    with {:ok, most_liked} <-
           Lists.list_most_liked_lists_for_viewer(viewer_id, nil, 3, allowed_categories: allowed),
         {:ok, recently_liked} <-
           Lists.list_recently_liked_lists_for_viewer(viewer_id, 10, allowed_categories: allowed),
         {:ok, recent} <-
           Lists.list_recent_lists_for_viewer(viewer_id, nil, 8, allowed_categories: allowed),
         {:ok, hidden_gems} <- Lists.list_hidden_gem_lists_for_viewer(viewer_id) do
      {:ok,
       %{
         popular_lists: hydrate_index_lists(most_liked.items, 5),
         recently_liked_lists: hydrate_index_lists(recently_liked, 5),
         recent_lists: hydrate_index_lists(recent.items, 5),
         hidden_gem_lists: hydrate_index_lists(hidden_gems, 5),
         is_logged_in: logged_in?(viewer)
       }}
    end
  end

  def load_show_page(username, slug, page, viewer, opts \\ []) do
    viewer_id = viewer_id(viewer)
    comments_page = Keyword.get(opts, :comments_page, 1)

    with {:ok, list} <- Lists.get_list_by_slug_for_view(slug, viewer_id),
         list <- Repo.preload(list, :user),
         :ok <- verify_username(list, username),
         hidden? <- hidden_for_viewer?(list, viewer),
         {:ok, tiers} <- load_tiers(list, hidden?),
         {:ok, visual_novels} <- load_visual_novels(list, page, viewer, hidden?),
         {:ok, comments} <- load_comments(list, comments_page, viewer, hidden?) do
      {:ok,
       %{
         list: normalize_list(list),
         raw_list: list,
         user: normalize_user(list.user),
         visual_novels: visual_novels.items,
         pagination: visual_novels.pagination,
         tiers: tiers,
         comments: comments.items,
         comments_pagination: comments.pagination,
         is_mine: same_user?(viewer, list.user_id),
         is_logged_in: logged_in?(viewer),
         is_hidden_for_viewer: hidden?,
         can_moderate_lists: can_moderate_lists?(viewer),
         liked_by_me: liked_by_me?(list.id, viewer_id),
         my_read_count: if(viewer_id, do: Lists.get_list_read_count(list.id, viewer_id), else: 0),
         page_size: @list_page_size
       }}
    end
  end

  def load_editor_page(username, slug, viewer) do
    viewer_id = viewer_id(viewer)

    with viewer_id when is_binary(viewer_id) <- viewer_id,
         {:ok, list} <- Lists.get_list_by_slug_for_view(slug, viewer_id),
         list <- Repo.preload(list, :user),
         :ok <- verify_username(list, username),
         :ok <- verify_owner(list, viewer_id),
         {:ok, tiers} <- Lists.list_tiers_for_list(list),
         {:ok, items} <- Lists.list_all_vns_for_list(list) do
      items = enrich_items(items, viewer_id)

      {:ok,
       %{
         list: normalize_list(list),
         raw_list: list,
         user: normalize_user(list.user),
         visual_novels: items,
         tiers: normalize_tiers(tiers),
         layout: layout_payload(list, tiers, items),
         is_mine: true,
         is_logged_in: true
       }}
    else
      nil -> {:error, :unauthenticated}
      error -> error
    end
  end

  def new_form_payload(viewer) do
    %{
      list: %{
        id: nil,
        name: "",
        slug: nil,
        description: "",
        is_public: true,
        is_ranked: false,
        display_mode: "grid",
        vns_count: 0
      },
      visual_novels: [],
      tiers: @default_tiers,
      layout: %{display_mode: "grid", tiers: @default_tiers, items: []},
      is_mine: logged_in?(viewer),
      is_logged_in: logged_in?(viewer)
    }
  end

  def search_visual_novels(query, viewer, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 8)

    VisualNovels.search_visual_novels(query, page, page_size,
      include_nukige: Map.get(viewer || %{}, :show_nukige, true),
      include_adjacent: Map.get(viewer || %{}, :show_adjacent, true)
    )
  end

  def layout_payload(list, tiers, items) do
    %{
      display_mode: list.display_mode || "grid",
      tiers: normalize_tiers(tiers),
      items:
        Enum.map(items, fn item ->
          %{
            visual_novel_id: item.visual_novel.id,
            position: item.position,
            tier_id: item.tier_id,
            tier_position: item.tier_position,
            visual_novel: item.visual_novel
          }
        end)
    }
  end

  def normalize_layout_attrs(%{"display_mode" => _} = attrs) do
    %{
      display_mode: Map.get(attrs, "display_mode"),
      tiers: normalize_submitted_tiers(Map.get(attrs, "tiers", [])),
      items: normalize_submitted_items(Map.get(attrs, "items", []))
    }
  end

  def normalize_layout_attrs(%{display_mode: _} = attrs) do
    %{
      display_mode: Map.get(attrs, :display_mode),
      tiers: normalize_submitted_tiers(Map.get(attrs, :tiers, [])),
      items: normalize_submitted_items(Map.get(attrs, :items, []))
    }
  end

  def normalize_layout_attrs(_attrs), do: %{display_mode: "grid", tiers: [], items: []}

  def normalize_form_attrs(attrs) when is_map(attrs) do
    %{
      name: Map.get(attrs, "name") || Map.get(attrs, :name),
      description: Map.get(attrs, "description") || Map.get(attrs, :description),
      is_public: bool(Map.get(attrs, "is_public", Map.get(attrs, :is_public, true))),
      is_ranked: bool(Map.get(attrs, "is_ranked", Map.get(attrs, :is_ranked, false))),
      display_mode: Map.get(attrs, "display_mode") || Map.get(attrs, :display_mode) || "grid"
    }
  end

  def normalize_list(%List{} = list) do
    %{
      id: list.id,
      name: list.name,
      slug: list.slug,
      description: list.description,
      is_public: list.is_public,
      is_ranked: list.is_ranked,
      display_mode: list.display_mode,
      vns_count: list.vns_count || 0,
      likes_count: list.likes_count || 0,
      comments_count: list.comments_count || 0,
      hidden_at: list.hidden_at,
      is_hidden: not is_nil(list.hidden_at),
      last_activity_at: list.last_activity_at,
      inserted_at: list.inserted_at,
      updated_at: list.updated_at
    }
  end

  def normalize_user(%User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  def normalize_user(_user),
    do: %{id: nil, username: nil, display_name: nil, avatar_urls: %{}, avatar_url: nil}

  defp hydrate_index_lists(lists, page_size) do
    lists = Repo.preload(lists, :user)

    vns_by_list =
      lists
      |> Enum.map(&{&1.id, &1.vns_count || 0})
      |> Lists.batch_list_vns_for_lists(page_size)

    Enum.map(lists, fn list ->
      vns =
        vns_by_list
        |> Map.get(list.id, %{items: []})
        |> Map.get(:items, [])
        |> Enum.map(fn item ->
          %{item | visual_novel: normalize_visual_novel(item.visual_novel)}
        end)

      list
      |> normalize_list()
      |> Map.put(:user, normalize_user(list.user))
      |> Map.put(:visual_novels, vns)
    end)
  end

  defp verify_username(%{user: %{username: username}}, username_param)
       when is_binary(username) and is_binary(username_param) do
    if String.downcase(username) == String.downcase(username_param),
      do: :ok,
      else: {:error, :not_found}
  end

  defp verify_username(_list, _username), do: {:error, :not_found}

  defp verify_owner(%{user_id: user_id}, user_id), do: :ok
  defp verify_owner(_list, _viewer_id), do: {:error, :not_found}

  defp hidden_for_viewer?(%{hidden_at: nil}, _viewer), do: false

  defp hidden_for_viewer?(%{user_id: owner_id}, %{id: owner_id}) when not is_nil(owner_id),
    do: false

  defp hidden_for_viewer?(_list, viewer), do: not can_moderate_lists?(viewer)

  defp load_tiers(_list, true), do: {:ok, []}

  defp load_tiers(list, false) do
    with {:ok, tiers} <- Lists.list_tiers_for_list(list), do: {:ok, normalize_tiers(tiers)}
  end

  defp load_visual_novels(_list, page, _viewer, true) do
    {:ok, %{items: [], pagination: empty_pagination(page, @list_page_size)}}
  end

  defp load_visual_novels(%{display_mode: "tier"} = list, _page, viewer, false) do
    viewer_id = viewer_id(viewer)
    allowed = visible_categories(list, viewer, viewer_id)

    with {:ok, items} <- Lists.list_all_vns_for_list(list, allowed_categories: allowed) do
      total = length(items)

      {:ok,
       %{
         items: enrich_items(items, viewer_id),
         pagination: %{page: 1, page_size: max(total, 1), total_count: total, total_pages: 1}
       }}
    end
  end

  defp load_visual_novels(list, page, viewer, false) do
    viewer_id = viewer_id(viewer)
    allowed = visible_categories(list, viewer, viewer_id)

    with {:ok, %{items: items, pagination: pagination}} <-
           Lists.list_vns_for_list(list, page, @list_page_size, allowed_categories: allowed) do
      {:ok, %{items: enrich_items(items, viewer_id), pagination: pagination}}
    end
  end

  defp visible_categories(%{user_id: owner_id}, _viewer, owner_id) when not is_nil(owner_id),
    do: nil

  defp visible_categories(_list, viewer, _viewer_id),
    do: TitleCategory.allowed_categories(viewer || %{})

  defp load_comments(_list, page, _viewer, true) do
    {:ok, %{items: [], pagination: empty_pagination(page, 10)}}
  end

  defp load_comments(list, page, viewer, false) do
    Lists.list_comments_for_list(list.id, list.comments_count || 0, %{
      page: page,
      page_size: 10,
      sort_by: :oldest,
      viewer_id: viewer_id(viewer)
    })
  end

  defp enrich_items(items, nil) do
    Enum.map(items, &enrich_item(&1, %{}))
  end

  defp enrich_items(items, viewer_id) do
    statuses =
      items
      |> Enum.map(& &1.visual_novel.id)
      |> reading_statuses_for(viewer_id)

    Enum.map(items, &enrich_item(&1, statuses))
  end

  defp enrich_item(%{visual_novel: vn} = item, statuses) do
    status = Map.get(statuses, vn.id)

    %{
      item
      | visual_novel:
          Map.merge(normalize_visual_novel(vn), %{
            my_reading_status: normalize_reading_status(status)
          })
    }
  end

  defp reading_statuses_for([], _viewer_id), do: %{}

  defp reading_statuses_for(vn_ids, viewer_id) do
    Repo.all(
      from(rs in ReadingStatus,
        where: rs.user_id == ^viewer_id and rs.visual_novel_id in ^vn_ids,
        select: {rs.visual_novel_id, rs}
      )
    )
    |> Map.new()
  end

  defp normalize_visual_novel(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: VisualNovels.build_image_urls(vn),
      average_rating: vn.average_rating,
      ratings_count: vn.ratings_count,
      has_ero: VisualNovels.cover_nsfw?(vn),
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp normalize_reading_status(nil), do: nil

  defp normalize_reading_status(status) do
    %{
      id: status.id,
      status: status.status && status.status |> to_string() |> String.upcase(),
      date_started: status.date_started,
      date_finished: status.date_finished,
      note: status.note,
      library_added_at: status.library_added_at
    }
  end

  defp normalize_tiers([]), do: []

  defp normalize_tiers(tiers) do
    tiers
    |> Enum.map(fn tier ->
      %{
        id: tier.id,
        label: tier.label,
        color: tier.color,
        position: tier.position
      }
    end)
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  defp normalize_submitted_tiers(tiers) when is_list(tiers) do
    Enum.map(tiers, fn tier ->
      %{
        id: Map.get(tier, "id") || Map.get(tier, :id),
        label: Map.get(tier, "label") || Map.get(tier, :label),
        color: Map.get(tier, "color") || Map.get(tier, :color),
        position: int(Map.get(tier, "position") || Map.get(tier, :position))
      }
    end)
  end

  defp normalize_submitted_tiers(_tiers), do: []

  defp normalize_submitted_items(items) when is_list(items) do
    Enum.map(items, fn item ->
      %{
        visual_novel_id: Map.get(item, "visual_novel_id") || Map.get(item, :visual_novel_id),
        position: int(Map.get(item, "position") || Map.get(item, :position)),
        tier_id: Map.get(item, "tier_id") || Map.get(item, :tier_id),
        tier_position:
          optional_int(Map.get(item, "tier_position") || Map.get(item, :tier_position))
      }
    end)
  end

  defp normalize_submitted_items(_items), do: []

  defp liked_by_me?(_list_id, nil), do: false

  defp liked_by_me?(list_id, viewer_id) do
    Repo.exists?(from(ll in ListLike, where: ll.list_id == ^list_id and ll.user_id == ^viewer_id))
  end

  defp empty_pagination(page, page_size) do
    %{page: page, page_size: page_size, total_count: 0, total_pages: 0}
  end

  defp bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp bool(_value), do: false

  defp int(value) when is_integer(value), do: value
  defp int(value) when is_binary(value), do: String.to_integer(value)
  defp int(_value), do: nil

  defp optional_int(nil), do: nil
  defp optional_int(""), do: nil
  defp optional_int(value), do: int(value)
end
