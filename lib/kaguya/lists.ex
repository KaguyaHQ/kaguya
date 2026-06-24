defmodule Kaguya.Lists do
  @moduledoc """
  Context for VN lists (public/private curated lists).
  """

  import Ecto.Query
  alias Kaguya.CursorPagination
  alias Kaguya.Repo
  alias Kaguya.Social
  alias Kaguya.Social.Likes
  alias Kaguya.Users.User
  alias Kaguya.Lists.{List, ListItem, ListLike, ListComment, ListCommentLike}
  alias Kaguya.Comments
  alias Kaguya.Utils.TextPreview
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Pagination
  alias Kaguya.Activities
  alias Kaguya.Lists.Layout
  alias Kaguya.Lists.Query

  @min_search_length 2

  @curated_list_slugs ["vndb-top-50", "egs-top-50", "top-50", "2ch-hk-vn-rec-list"]

  @staff_pick_slugs [
    "hopium-of-translation-and-or-i-learn-enough",
    "yuri",
    "denpa-and-or-horror"
  ]

  # Trending
  @base_epoch 1_740_890_930
  @time_scale 86_400.0

  # ============================================================================
  # Layout / Items API (delegated to Kaguya.Lists.Layout)
  # ============================================================================

  defdelegate save_list_layout(list_id, user_id, attrs), to: Layout
  defdelegate list_vns_for_list(list, page, page_size, opts \\ []), to: Layout
  defdelegate list_all_vns_for_list(list, opts \\ []), to: Layout
  defdelegate list_tiers_for_list(list_or_id), to: Layout
  defdelegate batch_list_tiers_for_lists(list_ids), to: Layout
  defdelegate batch_list_vns_for_lists(list_tuples, page_size), to: Layout

  # ============================================================================
  # List CRUD
  # ============================================================================

  @doc """
  Gets a list by ID (viewer-aware).
  """
  def get_list(id, viewer_id \\ nil, viewer \\ %{}) do
    case Repo.get(List, id) do
      nil -> {:error, :not_found}
      %List{} = list -> authorize_list_visibility(list, viewer_id, viewer)
    end
  end

  @doc """
  Gets a list by ID for the owner (strict ownership check).
  """
  def get_list_for_owner(id, user_id) do
    case Repo.get_by(List, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      list -> {:ok, list}
    end
  end

  @doc """
  Gets a list by slug (viewer-aware).

  Note: VN list slugs are expected to be globally unique (client routes use `/lists/:slug`).
  """
  def get_list_by_slug(slug, viewer_id \\ nil, viewer \\ %{}) do
    case Repo.get_by(List, slug: slug) do
      nil -> {:error, :not_found}
      %List{} = list -> authorize_list_visibility(list, viewer_id, viewer)
    end
  end

  @doc """
  View-only fetchers for the single-list page. Hidden lists are returned
  (so direct links keep working); private lists are still gated to owner.
  """
  def get_list_for_view(id, viewer_id \\ nil) do
    case Repo.get(List, id) do
      nil -> {:error, :not_found}
      %List{} = list -> authorize_list_view(list, viewer_id)
    end
  end

  def get_list_by_slug_for_view(slug, viewer_id \\ nil) do
    case Repo.get_by(List, slug: slug) do
      nil -> {:error, :not_found}
      %List{} = list -> authorize_list_view(list, viewer_id)
    end
  end

  defp authorize_list_view(%{user_id: owner_id, is_public: is_public} = list, viewer_id) do
    if is_public or viewer_id == owner_id, do: {:ok, list}, else: {:error, :not_found}
  end

  @doc """
  Gets multiple lists by slugs (viewer-aware). Returns only visible lists.
  """
  def get_lists_by_slugs(slugs, viewer_id \\ nil, viewer \\ %{}) when is_list(slugs) do
    List
    |> where([l], l.slug in ^slugs and is_nil(l.hidden_at))
    |> Repo.all()
    |> Enum.filter(fn list ->
      case authorize_list_visibility(list, viewer_id, viewer) do
        {:ok, _} -> true
        _ -> false
      end
    end)
    |> sort_by_input_order(slugs)
  end

  defp sort_by_input_order(lists, slugs) do
    index = slugs |> Enum.with_index() |> Map.new()
    Enum.sort_by(lists, fn l -> Map.get(index, l.slug, 999) end)
  end

  @doc """
  Gets a list by user + slug (viewer-aware).
  """
  def get_list_by_user_slug(owner_id, slug, viewer_id \\ nil, viewer \\ %{}) do
    case Repo.get_by(List, user_id: owner_id, slug: slug) do
      nil -> {:error, :not_found}
      %List{} = list -> authorize_list_visibility(list, viewer_id, viewer)
    end
  end

  @doc """
  Lists all lists for a user.
  """
  def list_lists_for_user(user_id, page \\ 1, page_size \\ 20) do
    query =
      List
      |> where([l], l.user_id == ^user_id)
      |> order_by([l], desc: l.updated_at)

    {lists, pagination} = Pagination.paginate(query, page, page_size)
    {:ok, %{items: lists, pagination: pagination}}
  end

  @doc """
  Gets lists for a specific user, showing only public lists unless viewer is the owner.
  Supports pagination and sorting options.
  """
  def list_user_lists(
        owner_id,
        viewer_id,
        %{page: page, page_size: page_size, sort_by: sort_by} = params
      ) do
    skip_count = Map.get(params, :skip_count, false)
    allowed = Map.get(params, :allowed_categories)

    lists_query =
      List
      |> where([l], l.user_id == ^owner_id)
      |> maybe_hide_private_lists(owner_id, viewer_id)
      |> Query.filter_by_allowed_categories(allowed)
      |> apply_sorting(sort_by)

    total = if skip_count, do: :skip, else: nil
    {lists, pagination} = Pagination.paginate(lists_query, page, page_size, total)
    lists = Enum.map(lists, &scrub_hidden_list_for_profile(&1, viewer_id))

    {:ok, %{items: lists, pagination: pagination}}
  end

  @doc """
  Returns all lists owned by the user, each annotated with whether `vn_id` is a member.
  Used for "Add to List" dialogs.
  """
  def list_my_lists_with_membership(user_id, vn_id) do
    query =
      from l in List,
        where: l.user_id == ^user_id,
        left_join: li in ListItem,
        on: li.list_id == l.id and li.visual_novel_id == ^vn_id,
        order_by: [asc: l.is_public, desc: l.updated_at],
        select: %{l | contains_vn: not is_nil(li.visual_novel_id)}

    {:ok, Repo.all(query)}
  end

  @doc """
  Count lists for a user (includes non-public lists).
  """
  def count_lists_for_user(owner_id) do
    List
    |> where([l], l.user_id == ^owner_id)
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_hide_private_lists(query, owner_id, viewer_id)
       when owner_id == viewer_id,
       do: query

  defp maybe_hide_private_lists(query, _owner_id, _viewer_id) do
    where(query, [l], l.is_public == true)
  end

  defp apply_sorting(query, sort_by) do
    case sort_by do
      :likes_desc -> order_by(query, [l], desc: l.likes_count, desc: l.id)
      :last_activity_at_desc -> order_by_last_activity(query)
      :updated_at_desc -> order_by_last_activity(query)
      _ -> order_by_last_activity(query)
    end
  end

  defp order_by_last_activity(query) do
    order_by(query, [l], desc: coalesce(l.last_activity_at, l.inserted_at), desc: l.id)
  end

  @doc """
  Creates a list.
  """
  def create_list(attrs \\ %{}) do
    result =
      Repo.transact(fn ->
        raw_vn_ids = Map.get(attrs, :vn_ids, [])
        vn_ids = normalize_vn_ids(raw_vn_ids)
        list_attrs = Map.delete(attrs, :vn_ids)
        list_changeset = List.changeset(%List{}, list_attrs)

        with {:ok, vn_ids} <- ensure_vn_ids_present(vn_ids, list_changeset),
             {:ok, vn_ids} <- ensure_visual_novels_exist(vn_ids, list_changeset),
             {:ok, list} <- Repo.insert(list_changeset),
             {:ok, _tiers} <- Layout.maybe_ensure_default_tiers(list),
             # Return the updated list (with vns_count/last_activity_at set).
             {:ok, true} <- Layout.set_list_items_in_transaction(list.id, vn_ids) do
          get_list(list.id, list.user_id)
        end
      end)

    with {:ok, list} <- result do
      if list.is_public do
        Activities.record_activity(%{
          user_id: list.user_id,
          action: :created_list,
          entity_type: "list",
          entity_id: list.id,
          metadata: %{
            list_name: list.name,
            list_slug: list.slug,
            list_username: list_creator_username(list),
            list_display_name: list_creator_display_name(list)
          }
        })
      end

      {:ok, list}
    end
  end

  @doc """
  Creates a list and persists its full layout in one transaction.

  LiveView form flows use this instead of calling `create_list/1` followed by
  `save_list_layout/3`, so invalid tier/item payloads do not leave behind a
  partially-created list.
  """
  def create_list_with_layout(user_id, attrs, layout_attrs)
      when is_binary(user_id) and is_map(attrs) and is_map(layout_attrs) do
    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> put_layout_vn_ids(layout_attrs)

    result =
      Repo.transact(fn ->
        raw_vn_ids = Map.get(attrs, :vn_ids, [])
        vn_ids = normalize_vn_ids(raw_vn_ids)
        list_attrs = Map.delete(attrs, :vn_ids)
        list_changeset = List.changeset(%List{}, list_attrs)

        with {:ok, vn_ids} <- ensure_vn_ids_present(vn_ids, list_changeset),
             {:ok, vn_ids} <- ensure_visual_novels_exist(vn_ids, list_changeset),
             {:ok, list} <- Repo.insert(list_changeset),
             {:ok, _tiers} <- Layout.maybe_ensure_default_tiers(list),
             {:ok, true} <- Layout.set_list_items_in_transaction(list.id, vn_ids) do
          Layout.save_list_layout(list.id, user_id, layout_attrs)
        end
      end)

    with {:ok, list} <- result do
      if list.is_public do
        Activities.record_activity(%{
          user_id: list.user_id,
          action: :created_list,
          entity_type: "list",
          entity_id: list.id,
          metadata: %{
            list_name: list.name,
            list_slug: list.slug,
            list_username: list_creator_username(list),
            list_display_name: list_creator_display_name(list)
          }
        })
      end

      {:ok, list}
    end
  end

  defp normalize_vn_ids(nil), do: []

  defp normalize_vn_ids(vn_ids) when is_list(vn_ids) do
    vn_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_vn_ids(vn_id), do: normalize_vn_ids([vn_id])

  defp put_layout_vn_ids(attrs, layout_attrs) do
    case Map.get(attrs, :vn_ids) do
      nil -> Map.put(attrs, :vn_ids, layout_visual_novel_ids(layout_attrs))
      [] -> Map.put(attrs, :vn_ids, layout_visual_novel_ids(layout_attrs))
      _vn_ids -> attrs
    end
  end

  defp layout_visual_novel_ids(%{items: items}) when is_list(items) do
    Enum.map(items, &Map.get(&1, :visual_novel_id))
  end

  defp layout_visual_novel_ids(%{"items" => items}) when is_list(items) do
    Enum.map(items, &(Map.get(&1, :visual_novel_id) || Map.get(&1, "visual_novel_id")))
  end

  defp layout_visual_novel_ids(_layout_attrs), do: []

  defp ensure_vn_ids_present(vn_ids, changeset \\ Ecto.Changeset.change(%List{})) do
    case vn_ids do
      [] ->
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :visual_novel_ids,
           "must contain at least one visual novel"
         )}

      ids ->
        {:ok, ids}
    end
  end

  @doc false
  # Public so `Kaguya.Lists.Layout` can re-use it. Not part of the user-facing API.
  def ensure_visual_novels_exist(vn_ids, changeset \\ Ecto.Changeset.change(%List{}))
      when is_list(vn_ids) do
    existing_ids =
      from(vn in VisualNovel, where: vn.id in ^vn_ids, select: vn.id)
      |> Repo.all()
      |> MapSet.new()

    missing =
      vn_ids
      |> Enum.reject(&MapSet.member?(existing_ids, &1))

    case missing do
      [] ->
        {:ok, vn_ids}

      _ ->
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :visual_novel_ids,
           "contains unknown visual novels"
         )}
    end
  end

  @doc """
  Updates a list.
  """
  def update_list(id, attrs) do
    Repo.transact(fn ->
      with {:ok, list} <- get_list_for_owner(id, attrs.user_id),
           {:ok, list} <- list |> List.changeset(attrs) |> Repo.update(),
           {:ok, _tiers} <- Layout.maybe_ensure_default_tiers(list) do
        {:ok, list}
      else
        error -> error
      end
    end)
  end

  @doc """
  Updates a list's metadata and full layout in one transaction.
  """
  def update_list_with_layout(id, user_id, attrs, layout_attrs)
      when is_binary(id) and is_binary(user_id) and is_map(attrs) and is_map(layout_attrs) do
    Repo.transact(fn ->
      attrs = Map.put(attrs, :user_id, user_id)

      with {:ok, list} <- get_list_for_owner(id, user_id),
           {:ok, list} <- list |> List.changeset(attrs) |> Repo.update(),
           {:ok, _tiers} <- Layout.maybe_ensure_default_tiers(list) do
        Layout.save_list_layout(id, user_id, layout_attrs)
      end
    end)
  end

  @doc """
  Deletes a list.
  """
  def delete_list(id, user_id) do
    with {:ok, list} <- get_list_for_owner(id, user_id),
         {:ok, _} <- Repo.delete(list) do
      Activities.delete_activities_for_entity("list", id)
      {:ok, true}
    end
  end

  # ============================================================================
  # VN <-> List Operations
  # ============================================================================

  @doc """
  Adds VNs to a list.
  """
  def add_vns_to_list(list_id, vn_ids, user_id) when is_list(vn_ids) and vn_ids != [] do
    vn_ids = normalize_vn_ids(vn_ids)

    with {:ok, _list} <- get_list_for_owner(list_id, user_id),
         {:ok, vn_ids} <- ensure_visual_novels_exist(vn_ids),
         {:ok, _count} <- Layout.add_items_to_list(list_id, vn_ids) do
      {:ok, true}
    end
  end

  def add_vns_to_list(_list_id, _vn_ids, _user_id), do: {:ok, 0}

  @doc """
  Removes VNs from a list.
  """
  def remove_vns_from_list(list_id, vn_ids, user_id) when is_list(vn_ids) do
    with {:ok, _list} <- get_list_for_owner(list_id, user_id) do
      Layout.remove_items_from_list(list_id, vn_ids)
    end
  end

  @doc """
  Replaces the entire ordered VN membership for a list.
  Replaces all items atomically, preserving the given order.
  """
  def set_list_vns(list_id, ordered_vn_ids, user_id) when is_list(ordered_vn_ids) do
    normalized_ids = normalize_vn_ids(ordered_vn_ids)

    with {:ok, _list} <- get_list_for_owner(list_id, user_id),
         {:ok, vn_ids} <- ensure_vn_ids_present(normalized_ids),
         {:ok, vn_ids} <- ensure_visual_novels_exist(vn_ids) do
      Layout.set_list_items(list_id, vn_ids)
    end
  end

  @doc """
  Lists all VN lists that contain a specific visual novel.

  """
  def list_lists_for_vn(vn, cursor \\ nil, limit \\ 10, viewer_id \\ nil, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)
    cursor_parsed = parse_cursor(cursor)

    query =
      Query.visible(List)
      |> Query.for_vn(vn.id)
      |> Query.visible_to(viewer_id)
      |> Query.filter_by_allowed_categories(allowed)
      |> order_by([l], desc: l.likes_count, desc: l.id)

    {items, next_cursor, has_next} =
      CursorPagination.paginate_by_cursor(query, [:likes_count, :id], cursor_parsed, limit, :desc)

    {:ok, %{items: items, next_cursor: format_cursor(next_cursor), has_next: has_next}}
  end

  # ============================================================================
  # Discovery Queries (viewer-aware)
  # ============================================================================

  def search_lists(query, page, page_size, viewer_id \\ nil, opts \\ %{}) do
    page_size = page_size || 20

    normalized =
      query
      |> TextPreview.extract_text()
      |> to_string()
      |> String.trim()

    cond do
      normalized == "" ->
        empty_paginated_result(page_size)

      String.length(normalized) < @min_search_length ->
        empty_paginated_result(page_size)

      true ->
        limit = page_size |> max(1) |> min(50)
        allowed = Map.get(opts, :allowed_categories)
        base_scope = list_discovery_scope(viewer_id, allowed)
        pattern = "%" <> escape_like(normalized) <> "%"

        search_query =
          from [l] in base_scope,
            where:
              ilike(l.name, ^pattern) or
                ilike(l.description, ^pattern) or
                ilike(l.slug, ^pattern)

        search_query =
          case Map.get(opts, :sort_by, :likes_desc) do
            :updated_at_desc ->
              order_by(search_query, [l],
                desc: coalesce(l.last_activity_at, l.inserted_at),
                desc: l.id
              )

            :last_activity_at_desc ->
              order_by(search_query, [l],
                desc: coalesce(l.last_activity_at, l.inserted_at),
                desc: l.id
              )

            _ ->
              from [l] in search_query,
                order_by: [desc: l.likes_count, desc: l.inserted_at, desc: l.id]
          end

        {items, pagination} = Pagination.paginate(search_query, page, limit)
        {:ok, %{items: items, pagination: pagination}}
    end
  end

  def list_hidden_gem_lists do
    list_hidden_gem_lists_for_viewer(nil)
  end

  def curated_list_progress(user_id, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    lists =
      from(l in List,
        where: l.slug in ^@curated_list_slugs and l.is_public == true
      )
      |> Repo.all()
      |> Enum.sort_by(fn list ->
        Enum.find_index(@curated_list_slugs, &(&1 == list.slug))
      end)
      |> Enum.map(fn list ->
        {read_count, total} = count_read_in_list(user_id, list.id, allowed)
        %{list: %{list | vns_count: total}, read_count: read_count}
      end)

    lists
  end

  defp count_read_in_list(user_id, list_id, allowed) do
    base =
      from(li in ListItem,
        join: vn in Kaguya.VisualNovels.VisualNovel,
        on: vn.id == li.visual_novel_id,
        where: li.list_id == ^list_id
      )

    base = if allowed, do: where(base, [_li, vn], vn.title_category in ^allowed), else: base

    total = Repo.aggregate(base, :count, :visual_novel_id) || 0

    read_count =
      base
      |> join(:inner, [li, _vn], rs in ReadingStatus,
        on: rs.visual_novel_id == li.visual_novel_id and rs.user_id == ^user_id
      )
      |> where([_li, _vn, rs], rs.status == :read)
      |> Repo.aggregate(:count, :visual_novel_id) || 0

    {read_count, total}
  end

  def list_hidden_gem_lists_for_viewer(_viewer_id) do
    lists =
      from(l in List,
        where: l.slug in ^@staff_pick_slugs and l.is_public == true
      )
      |> Repo.all()
      |> Enum.sort_by(fn list ->
        Enum.find_index(@staff_pick_slugs, &(&1 == list.slug))
      end)

    {:ok, lists}
  end

  def list_recently_liked_lists do
    list_recently_liked_lists_for_viewer(nil)
  end

  def list_recently_liked_lists_for_viewer(viewer_id, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    query =
      from [l] in list_discovery_scope(viewer_id, allowed),
        join: ll in ListLike,
        on: ll.list_id == l.id,
        group_by: l.id,
        order_by: [desc: max(ll.inserted_at)],
        limit: ^min(limit, 50),
        select: l

    {:ok, Repo.all(query)}
  end

  def list_recent_lists(cursor \\ nil, limit \\ 10) do
    list_recent_lists_for_viewer(nil, cursor, limit)
  end

  def list_recent_lists_for_viewer(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    list_discovery_scope(viewer_id, allowed)
    |> select([l], l)
    |> CursorPagination.paginate([:inserted_at, :id], [:datetime, :string], cursor, limit, :desc)
    |> format_cursor_response()
  end

  def list_most_liked_lists(cursor \\ nil, limit \\ 10) do
    list_most_liked_lists_for_viewer(nil, cursor, limit)
  end

  def list_most_liked_lists_for_viewer(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    list_discovery_scope(viewer_id, allowed)
    |> where([l], l.likes_count > 0)
    |> select([l], l)
    |> CursorPagination.paginate([:likes_count, :id], [:int, :string], cursor, limit, :desc)
    |> format_cursor_response()
  end

  def list_trending_lists(cursor \\ nil, limit \\ 10) do
    list_trending_lists_for_viewer(nil, cursor, limit)
  end

  def list_trending_lists_for_viewer(viewer_id, cursor \\ nil, limit \\ 10, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    list_discovery_scope(viewer_id, allowed)
    |> select([l], l)
    |> CursorPagination.paginate([:trending_score, :id], [:float, :string], cursor, limit, :desc)
    |> format_cursor_response()
  end

  @doc """
  Returns public lists for sitemap indexing (surface-aware: list + user must be public).
  """
  def list_public_lists_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      Query.visible(List)
      |> join(:inner, [l], u in User, on: u.id == l.user_id)
      |> where([l, u], not is_nil(u.username))
      |> order_by([l, _u], desc: l.updated_at, desc: l.id)
      |> select([l, u], %{
        id: l.id,
        slug: l.slug,
        user_id: l.user_id,
        username: u.username,
        updated_at: l.updated_at
      })

    Pagination.paginate(query, page, page_size)
  end

  # ============================================================================
  # Like Operations
  # ============================================================================

  @doc """
  Likes a list.
  """
  def like_list(list_id, user_id) do
    result =
      Repo.transact(fn ->
        with {:ok, list} <- get_list(list_id, user_id),
             {:ok, inserted?} <-
               Likes.create_like(ListLike, %{list_id: list.id, user_id: user_id}) do
          if inserted? do
            with {updated_count, _} when updated_count > 0 <-
                   Likes.increment_likes(List, list.id),
                 {:ok, _} <- update_trending_score(list.id),
                 {:ok, _notification} <-
                   Social.create_notification(%{
                     user_id: list.user_id,
                     action: :like,
                     entity_type: :list,
                     entity_id: list.id,
                     actor_id: user_id,
                     metadata: build_list_metadata(list)
                   }) do
              {:ok, list}
            end
          else
            {:ok, :already_liked}
          end
        end
      end)

    with {:ok, %List{} = list} <- result do
      if list.is_public do
        Activities.record_activity(%{
          user_id: user_id,
          action: :liked_list,
          entity_type: "list",
          entity_id: list.id,
          metadata: %{
            list_name: list.name,
            list_slug: list.slug,
            list_username: list_creator_username(list),
            list_display_name: list_creator_display_name(list)
          }
        })
      end

      {:ok, true}
    else
      {:ok, :already_liked} -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Unlikes a list.
  """
  def unlike_list(list_id, user_id) do
    result =
      Repo.transact(fn ->
        with {:ok, _list} <- get_list(list_id, user_id),
             {n, _} when n > 0 <- Likes.delete_like(ListLike, list_id: list_id, user_id: user_id),
             {1, _} <- Likes.decrement_likes(List, list_id),
             {:ok, _} <- update_trending_score(list_id) do
          {:ok, true}
        else
          {0, _} -> {:ok, true}
          other -> other
        end
      end)

    with {:ok, true} <- result do
      Activities.delete_activity(user_id, :liked_list, "list", list_id)
      {:ok, true}
    end
  end

  @doc """
  Checks if a user has liked a list.
  """
  def liked_list?(list_id, user_id) do
    Likes.liked?(ListLike, list_id: list_id, user_id: user_id)
  end

  # ----------------------------------------------------------------------------
  # Trending score (likes-only for now; comments can be introduced later)
  # ----------------------------------------------------------------------------

  def recalc_trending_score(%List{} = list) do
    likes = Map.get(list, :likes_count, 0) || 0
    engagement = max(likes, 1)
    engagement_log = :math.log10(engagement)

    time_offset =
      case Map.get(list, :inserted_at) do
        %DateTime{} = inserted_at -> (DateTime.to_unix(inserted_at) - @base_epoch) / @time_scale
        _ -> 0.0
      end

    engagement_log + time_offset
  end

  defp update_trending_score(list_id) do
    case Repo.get(List, list_id) do
      nil ->
        {:error, :not_found}

      list ->
        new_score = recalc_trending_score(list)

        list
        |> Ecto.Changeset.change(trending_score: new_score)
        |> Repo.update()
    end
  end

  # ----------------------------------------------------------------------------
  # Presentation helpers (notifications, future UI)
  # ----------------------------------------------------------------------------

  defp build_list_metadata(%List{} = list) do
    %{
      list_name: list.name,
      list_slug: list.slug,
      list_cover_urls: list_cover_urls(list),
      list_creator_username: list_creator_username(list)
    }
  end

  defp list_cover_urls(%List{id: list_id}) do
    from(vn in VisualNovel,
      join: li in ListItem,
      on: li.visual_novel_id == vn.id,
      where: li.list_id == ^list_id,
      order_by: li.position,
      limit: 5,
      select: vn
    )
    |> Repo.all()
    |> Enum.map(&Kaguya.VisualNovels.build_image_urls(&1)[:small])
    |> Enum.reject(&is_nil/1)
  end

  defp list_creator_username(%List{user: %User{username: username}}), do: username

  defp list_creator_username(%List{user_id: user_id}) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.username)
  end

  defp list_creator_display_name(%List{user: %User{display_name: name}}), do: name

  defp list_creator_display_name(%List{user_id: user_id}) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.display_name)
  end

  @doc """
  Count how many items in a VN list the user has completed (status == :read).
  """
  def get_list_read_count(list_id, user_id) do
    ReadingStatus
    |> join(:inner, [rs], li in ListItem, on: li.visual_novel_id == rs.visual_novel_id)
    |> where([rs, li], rs.user_id == ^user_id and li.list_id == ^list_id and rs.status == ^:read)
    |> select([rs, _li], count(rs.id))
    |> Repo.one() ||
      0
  end

  @doc """
  Gets VN lists liked by some user, with pagination.
  """
  def list_liked_lists_for_user(user_id, page, page_size, viewer_id \\ nil, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    query =
      Query.visible(List)
      |> Query.visible_to(viewer_id)
      |> Query.filter_by_allowed_categories(allowed)
      |> join(:inner, [l], ll in ListLike, on: ll.list_id == l.id and ll.user_id == ^user_id)
      |> order_by([l, ll], desc: ll.inserted_at)
      |> select([l], l)

    {lists, pagination} = Pagination.paginate(query, page, page_size)
    {:ok, %{items: lists, pagination: pagination}}
  end

  # ============================================================================
  # List Comment Operations
  # ============================================================================

  defp vn_list_comment_config do
    %{
      comment_schema: ListComment,
      parent_schema: List,
      entity_type: :list,
      comment_changeset: &ListComment.changeset(%ListComment{}, &1),
      parent_id_field: & &1.list_id,
      get_parent: fn attrs ->
        case get_list(attrs.list_id, Map.get(attrs, :user_id)) do
          {:ok, list} -> list
          _ -> raise Ecto.NoResultsError
        end
      end,
      get_parent_owner: & &1.user_id,
      build_metadata: &build_list_comment_metadata/2
    }
  end

  @doc """
  Creates a comment on a VN list.
  """
  def create_list_comment(attrs) do
    with {:ok, list} <- get_list(attrs.list_id, Map.get(attrs, :user_id)),
         {:ok, comment} <- Comments.create_comment(vn_list_comment_config_for(list), attrs) do
      record_list_comment_activity(comment)
      {:ok, comment}
    end
  end

  @doc """
  Gets a list comment by ID.
  """
  def get_list_comment(id), do: Comments.get_comment(ListComment, id)

  @doc """
  Returns a paginated list of comments for a VN list.
  """
  def list_comments_for_list(list_id, comments_count, params) do
    Comments.list_comments_for(ListComment, :list_id, list_id, comments_count, params)
  end

  @doc """
  Updates a list comment.
  """
  def update_list_comment(comment_id, user_id, content) do
    Comments.update_comment(ListComment, comment_id, user_id, %{content: content, is_edited: true})
  end

  @doc """
  Deletes a list comment.
  """
  def delete_list_comment(comment_id, user_id) do
    # Collect subtree IDs before deletion so we can clean up all activities
    subtree_ids = Comments.collect_subtree_ids(ListComment, comment_id)

    with {:ok, true} <-
           Comments.delete_comment(ListComment, List, comment_id, user_id, :list_id) do
      Enum.each(subtree_ids, fn id ->
        Activities.delete_activities_for_entity("list_comment", id)
      end)

      {:ok, true}
    end
  end

  @doc """
  Checks if a user has liked a list comment.
  """
  def liked_list_comment?(list_comment_id, user_id) do
    Likes.liked?(ListCommentLike, vn_list_comment_id: list_comment_id, user_id: user_id)
  end

  @doc """
  Likes a list comment, increments its like count, and sends a notification.
  """
  def like_list_comment(list_comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- get_list_comment(list_comment_id),
           {:ok, _} <- check_comment_visible(comment, user_id),
           {:ok, list} <- get_list(comment.list_id, user_id),
           {:ok, inserted?} <-
             Likes.create_like(ListCommentLike, %{
               vn_list_comment_id: list_comment_id,
               user_id: user_id
             }) do
        if inserted? do
          with {updated_count, _} when updated_count > 0 <-
                 Likes.increment_likes(ListComment, list_comment_id),
               {:ok, _} <-
                 Social.create_notification(%{
                   user_id: comment.user_id,
                   action: :like,
                   entity_type: :comment,
                   entity_id: list_comment_id,
                   actor_id: user_id,
                   metadata: build_list_comment_metadata(list, comment)
                 }) do
            {:ok, true}
          end
        else
          {:ok, true}
        end
      end
    end)
  end

  @doc """
  Unlikes a list comment and decrements its like count.
  """
  def unlike_list_comment(list_comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- get_list_comment(list_comment_id),
           {:ok, _} <- check_comment_visible(comment, user_id),
           {:ok, _list} <- get_list(comment.list_id, user_id),
           {1, _} <-
             Likes.delete_like(ListCommentLike,
               vn_list_comment_id: list_comment_id,
               user_id: user_id
             ),
           {1, _} <- Likes.decrement_likes(ListComment, list_comment_id) do
        {:ok, true}
      end
    end)
  end

  defp build_list_comment_metadata(%List{} = list, %ListComment{} = comment) do
    %{
      text_preview: comment.content |> TextPreview.truncate_on_words(),
      list_name: list.name,
      list_slug: list.slug,
      list_cover_urls: list_cover_urls(list),
      list_creator_username: list_creator_username(list),
      parent_entity_type: "list"
    }
  end

  defp record_list_comment_activity(comment) do
    list = Repo.get(List, comment.list_id) |> Repo.preload(:user)

    metadata =
      if list do
        username = list_creator_username(list)

        %{
          parent_entity_type: "list",
          parent_entity_id: list.id,
          text_preview: comment.content |> TextPreview.truncate_on_words(),
          list_name: list.name,
          list_slug: list.slug,
          list_username: username
        }
      else
        %{
          parent_entity_type: "list",
          text_preview: comment.content |> TextPreview.truncate_on_words()
        }
      end

    Activities.record_activity(%{
      user_id: comment.user_id,
      action: :commented,
      entity_type: "list_comment",
      entity_id: comment.id,
      metadata: metadata
    })
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp authorize_list_visibility(
         %{user_id: owner_id, is_public: is_public, hidden_at: hidden_at} = list,
         viewer_id,
         viewer
       ) do
    cond do
      # Owner always sees their own content
      viewer_id == owner_id ->
        {:ok, list}

      # mod_lists or admin can see hidden lists
      not is_nil(hidden_at) and
          (Map.get(viewer, :mod_lists, false) or Map.get(viewer, :role) == :admin) ->
        {:ok, list}

      # Hidden by admin
      not is_nil(hidden_at) ->
        {:error, :not_found}

      # Private lists are only visible to the owner
      not is_public ->
        {:error, :not_found}

      # Public list: visible to everyone
      true ->
        {:ok, list}
    end
  end

  defp list_discovery_scope(viewer_id, allowed_categories) do
    Query.visible(List)
    |> Query.visible_to(viewer_id)
    |> Query.filter_by_allowed_categories(allowed_categories)
  end

  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp empty_paginated_result(page_size) do
    {:ok,
     %{
       items: [],
       pagination: %{
         page: 1,
         page_size: page_size,
         total_pages: 0,
         total_count: 0
       }
     }}
  end

  defp format_cursor_response({items, next_cursor, has_next}) do
    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  # Helper to parse an incoming composite cursor string "likes:id" into a tuple.
  defp parse_cursor(nil), do: nil

  defp parse_cursor(cursor_str) when is_binary(cursor_str) do
    case String.split(cursor_str, ":") do
      [likes_str, id] ->
        {String.to_integer(likes_str), id}

      _ ->
        nil
    end
  end

  # Helper to format the composite tuple back into a string.
  defp format_cursor(nil), do: nil
  defp format_cursor({likes, id}), do: "#{likes}:#{id}"

  # ============================================================================
  # Content Hiding
  # ============================================================================

  def hide_list(list_id, attrs \\ %{}) do
    attrs = normalize_moderation_attrs(attrs)

    case Repo.get(List, list_id) do
      nil ->
        {:error, :not_found}

      list ->
        Repo.transact(fn ->
          with {:ok, updated} <-
                 list
                 |> Ecto.Changeset.change(
                   hidden_at: DateTime.utc_now() |> DateTime.truncate(:second)
                 )
                 |> Repo.update(),
               :ok <- maybe_create_removal_comment(list, attrs) do
            {:ok, updated}
          end
        end)
    end
  end

  def unhide_list(list_id) do
    case Repo.get(List, list_id) do
      nil ->
        {:error, :not_found}

      list ->
        list
        |> Ecto.Changeset.change(hidden_at: nil)
        |> Repo.update()
    end
  end

  def hide_list_comment(comment_id, attrs \\ %{}) do
    Comments.hide_comment_subtree(ListComment, List, comment_id, :list_id, attrs)
  end

  def unhide_list_comment(comment_id) do
    Comments.unhide_comment_subtree(ListComment, List, comment_id, :list_id)
  end

  defp check_comment_visible(%{hidden_at: nil} = comment, _viewer_id), do: {:ok, comment}

  defp check_comment_visible(%{user_id: uid} = comment, uid) when not is_nil(uid),
    do: {:ok, comment}

  defp check_comment_visible(_comment, _viewer_id), do: {:error, :not_found}

  defp scrub_hidden_list_for_profile(%{hidden_at: nil} = list, _viewer_id), do: list
  defp scrub_hidden_list_for_profile(%{user_id: uid} = list, uid) when not is_nil(uid), do: list

  defp scrub_hidden_list_for_profile(%List{} = list, _viewer_id) do
    %{
      list
      | name: nil,
        description: nil,
        vns_count: 0,
        likes_count: 0,
        comments_count: 0,
        trending_score: 0.0,
        last_activity_at: nil,
        is_ranked: false,
        display_mode: "grid"
    }
  end

  defp normalize_moderation_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_moderation_attrs(reason) when is_binary(reason), do: %{reason: reason}
  defp normalize_moderation_attrs(_attrs), do: %{}

  defp maybe_create_removal_comment(list, attrs) do
    if truthy?(Map.get(attrs, :add_comment) || Map.get(attrs, "add_comment")) do
      case Map.get(attrs, :actor_id) || Map.get(attrs, "actor_id") do
        nil ->
          :ok

        actor_id ->
          content =
            Map.get(attrs, :comment) || Map.get(attrs, "comment") || Map.get(attrs, :reason) ||
              Map.get(attrs, "reason")

          if is_binary(content) and String.trim(content) != "" do
            case Comments.create_comment(vn_list_comment_config_for(list), %{
                   list_id: list.id,
                   user_id: actor_id,
                   content: content
                 }) do
              {:ok, _comment} -> :ok
              {:error, reason} -> {:error, reason}
            end
          else
            :ok
          end
      end
    else
      :ok
    end
  end

  defp vn_list_comment_config_for(list) do
    %{vn_list_comment_config() | get_parent: fn _attrs -> list end}
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
