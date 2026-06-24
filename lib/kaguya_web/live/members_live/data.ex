defmodule KaguyaWeb.MembersLive.Data do
  @moduledoc """
  View-model assembly for the migrated members page.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Social
  alias Kaguya.Users
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}

  @page_size 20
  @sorts %{
    "newest" => :newest,
    "most-active" => :most_active,
    "popular" => :most_followed
  }

  def page_size, do: @page_size

  def sort_from_slug(slug), do: Map.get(@sorts, slug, :most_active)
  def sort_to_slug(:newest), do: "newest"
  def sort_to_slug(:most_followed), do: "popular"
  def sort_to_slug(_sort), do: "most-active"

  def sort_label(:newest), do: "Newest"
  def sort_label(:most_followed), do: "Popular"
  def sort_label(_sort), do: "Most Active"

  def list_members(sort, cursor, viewer) do
    viewer_id = viewer_id(viewer)

    with {:ok, page} <-
           Users.Browse.list_users(%{limit: @page_size, cursor: cursor, sort_by: sort}, viewer_id) do
      {:ok,
       %{
         items: hydrate_users(page.items, viewer),
         next_cursor: page.next_cursor,
         has_next: page.has_next
       }}
    end
  end

  def search_members(query, viewer) do
    query = normalize_search(query)

    if searching?(query) do
      {:ok, hydrate_users(Users.search_users(query), viewer)}
    else
      {:ok, []}
    end
  end

  def searching?(query), do: String.length(normalize_search(query)) >= 2

  def normalize_search(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.trim_leading("@")
  end

  def normalize_search(_query), do: ""

  def update_follow_state(users, target_id, viewer) do
    Enum.map(users, fn
      %{id: ^target_id} = user -> put_follow_state(user, viewer)
      user -> user
    end)
  end

  defp hydrate_users(users, viewer) do
    users = Enum.reject(users, &is_nil/1)
    viewer_id = viewer_id(viewer)
    allowed = TitleCategory.allowed_categories(viewer || %{})
    user_ids = Enum.map(users, & &1.id)

    vns_by_id = favorite_vns_by_id(users)
    library_counts = library_counts(user_ids, allowed)
    review_counts = review_counts(user_ids, allowed)
    followed_ids = followed_ids(viewer_id, user_ids)

    Enum.map(users, fn user ->
      self? = user.id == viewer_id
      avatar_urls = Users.build_avatar_urls(user.avatar_id)

      favorite_visual_novels =
        user.favorite_visual_novels
        |> List.wrap()
        |> Enum.map(&Map.get(vns_by_id, &1))
        |> Enum.reject(&is_nil/1)
        |> maybe_filter_vns(if(self?, do: nil, else: allowed))
        |> Enum.take(4)
        |> Enum.map(&normalize_vn/1)

      %{
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username || "Unknown",
        avatar_url: avatar_urls[:medium] || avatar_urls[:small],
        avatar_urls: avatar_urls,
        favorite_visual_novels: favorite_visual_novels,
        vns_count: Map.get(library_counts, user.id, 0),
        reviews_count:
          if(self?, do: user.vn_reviews_count || 0, else: Map.get(review_counts, user.id, 0)),
        follow_state: follow_state(user, viewer_id, followed_ids),
        is_followed_by_me: MapSet.member?(followed_ids, user.id)
      }
    end)
  end

  defp put_follow_state(%{id: id} = user, viewer) do
    viewer_id = viewer_id(viewer)
    state = Social.follow_state(viewer_id, id)

    user
    |> Map.put(:follow_state, state)
    |> Map.put(:is_followed_by_me, state == :following)
  end

  defp viewer_id(%{id: id}) when is_binary(id), do: id
  defp viewer_id(_viewer), do: nil

  defp favorite_vns_by_id(users) do
    ids =
      users
      |> Enum.flat_map(&List.wrap(&1.favorite_visual_novels))
      |> Enum.uniq()

    from(vn in VisualNovel, where: vn.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp library_counts([], _allowed), do: %{}

  defp library_counts(user_ids, allowed) do
    ReadingStatus
    |> where([s], s.user_id in ^user_ids)
    |> where([s], s.status not in [:not_interested, :want_to_read])
    |> join(:inner, [s], vn in VisualNovel, on: vn.id == s.visual_novel_id)
    |> where([_s, vn], vn.title_category in ^allowed)
    |> group_by([s], s.user_id)
    |> select([s], {s.user_id, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp review_counts([], _allowed), do: %{}

  defp review_counts(user_ids, allowed) do
    Review
    |> where([r], r.user_id in ^user_ids and is_nil(r.hidden_at))
    |> join(:inner, [r], vn in VisualNovel, on: vn.id == r.visual_novel_id)
    |> where([_r, vn], vn.title_category in ^allowed)
    |> group_by([r], r.user_id)
    |> select([r], {r.user_id, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp followed_ids(nil, _target_ids), do: MapSet.new()
  defp followed_ids(_viewer_id, []), do: MapSet.new()
  defp followed_ids(viewer_id, target_ids), do: Social.batch_followed_ids(viewer_id, target_ids)

  defp follow_state(%{id: id}, viewer_id, _followed_ids) when id == viewer_id, do: :self

  defp follow_state(%{id: id}, _viewer_id, followed_ids) do
    if MapSet.member?(followed_ids, id), do: :following, else: :not_following
  end

  defp maybe_filter_vns(vns, nil), do: vns
  defp maybe_filter_vns(vns, allowed), do: Enum.filter(vns, &(&1.title_category in allowed))

  defp normalize_vn(%VisualNovel{} = vn) do
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
end
