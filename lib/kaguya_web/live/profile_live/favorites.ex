defmodule KaguyaWeb.ProfileLive.Favorites do
  @moduledoc """
  `/@:username/favorites` — VN + character favorites.

  Mirrors `../personal/legacy-next-app/src/components/profile/FavoritesTab.tsx` for the
  read-only favorites surface:

    * ordered favorite VNs and characters
    * owner-only edit/add affordances
    * favorite quotes intentionally hidden, matching the production tab
  """

  use KaguyaWeb.ProfileLive, tab: :favorites, title_suffix: "Favorites"

  import Ecto.Query

  alias Kaguya.Characters.{Character, CharacterFavorite, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}
  alias KaguyaWeb.Components.Profile.Favorites, as: FavoritesComponents
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.ListLive.Data, as: ListData

  @search_page_size 8
  @empty_search %{
    open: false,
    type: nil,
    step: :vn_search,
    query: "",
    results: [],
    characters: [],
    selected_vn: nil,
    error: nil
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Phoenix.Component.assign(:state, :loading)
     |> Phoenix.Component.assign(:profile, nil)
     |> Phoenix.Component.assign(:favorites, %{visual_novels: [], characters: []})
     |> Phoenix.Component.assign(:draft_favorites, %{visual_novels: [], characters: []})
     |> Phoenix.Component.assign(:favorites_limit, 0)
     |> Phoenix.Component.assign(:editing, false)
     |> Phoenix.Component.assign(:editor_error, nil)
     |> Phoenix.Component.assign(:search, @empty_search)
     |> Phoenix.Component.assign(:permissions, %{any?: false})
     |> Phoenix.Component.assign(:page_title, "Profile · Kaguya")
     |> Phoenix.Component.assign(:current_tab, :favorites)
     |> Phoenix.Component.assign(:root?, false)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    with {:ok, profile} <- Data.load_header(username, viewer),
         {:ok, user} <- Users.get_user(profile.id) do
      favorites = load_favorites(user, viewer)

      {:noreply,
       socket
       |> Phoenix.Component.assign(:state, :ready)
       |> Phoenix.Component.assign(:profile, profile)
       |> Phoenix.Component.assign(:favorites, favorites)
       |> Phoenix.Component.assign(:draft_favorites, favorites)
       |> Phoenix.Component.assign(:favorites_limit, User.favorites_limit(user))
       |> Phoenix.Component.assign(:editing, false)
       |> Phoenix.Component.assign(:editor_error, nil)
       |> Phoenix.Component.assign(:search, @empty_search)
       |> Phoenix.Component.assign(:permissions, Data.viewer_permissions(viewer))
       |> Phoenix.Component.assign(:page_title, Data.page_title(profile, "Favorites"))
       |> Phoenix.Component.assign(KaguyaWeb.SEO.noindex())}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:state, :not_found)
         |> Phoenix.Component.assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />
      <FavoritesComponents.favorites_body
        profile={@profile}
        favorites={@favorites}
        editing={@editing}
        draft_favorites={@draft_favorites}
        favorites_limit={@favorites_limit}
        editor_error={@editor_error}
        search={@search}
      />
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("open_editor", _params, socket) do
    if editable?(socket) do
      {:noreply,
       socket
       |> assign(:editing, true)
       |> assign(:draft_favorites, socket.assigns.favorites)
       |> assign(:editor_error, nil)
       |> assign(:search, @empty_search)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:draft_favorites, socket.assigns.favorites)
     |> assign(:editor_error, nil)
     |> assign(:search, @empty_search)}
  end

  def handle_event("save_editor", _params, socket) do
    if editable?(socket) do
      save_editor(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "move_favorite",
        %{"type" => raw_type, "id" => id, "direction" => direction},
        socket
      ) do
    with true <- editable?(socket),
         {:ok, type} <- parse_type(raw_type) do
      {:noreply, update_draft(socket, type, &move_item(&1, id, direction))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "reorder_favorite",
        %{"kind" => raw_kind, "from" => from, "to" => to},
        socket
      ) do
    with true <- editable?(socket),
         {:ok, type} <- parse_kind(raw_kind),
         {:ok, from_idx} <- cast_index(from),
         {:ok, to_idx} <- cast_index(to) do
      {:noreply, update_draft(socket, type, &move(&1, from_idx, to_idx))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_favorite", %{"type" => raw_type, "id" => id}, socket) do
    with true <- editable?(socket),
         {:ok, type} <- parse_type(raw_type) do
      {:noreply,
       socket
       |> update_draft(type, fn items ->
         Enum.reject(items, &(to_string(&1.id) == to_string(id)))
       end)
       |> assign(:editor_error, nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_favorite_search", %{"type" => raw_type}, socket) do
    with true <- editable?(socket),
         {:ok, type} <- parse_type(raw_type),
         true <- draft_count(socket, type) < socket.assigns.favorites_limit do
      {:noreply,
       assign(socket, :search, %{
         @empty_search
         | open: true,
           type: type,
           step: :vn_search
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_favorite_search", _params, socket) do
    {:noreply, assign(socket, :search, @empty_search)}
  end

  def handle_event("search_favorite", %{"favorite_search" => %{"query" => query}}, socket) do
    if editable?(socket) do
      {:noreply, assign_search(socket, query)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_character_search_vn", %{"id" => vn_id}, socket) do
    with true <- editable?(socket),
         %{type: :characters} <- socket.assigns.search,
         %VisualNovel{} = vn <- VisualNovels.get_visual_novel(vn_id) do
      {:noreply,
       assign(socket, :search, %{
         @empty_search
         | open: true,
           type: :characters,
           step: :character_select,
           selected_vn: normalize_search_vn(vn),
           characters: load_characters_for_vn(vn.id, draft_ids(socket, :characters))
       })}
    else
      _ ->
        {:noreply,
         assign(socket, :search, Map.put(socket.assigns.search, :error, "Something went wrong"))}
    end
  end

  def handle_event("back_to_character_vn_search", _params, socket) do
    if editable?(socket) do
      {:noreply,
       assign(socket, :search, %{
         @empty_search
         | open: true,
           type: :characters,
           step: :vn_search
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_favorite", %{"type" => raw_type, "id" => id}, socket) do
    with true <- editable?(socket),
         {:ok, type} <- parse_type(raw_type) do
      add_favorite(socket, type, id)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(event, params, socket) do
    super(event, params, socket)
  end

  defp save_editor(socket) do
    with {:ok, user} <- Users.get_user(socket.assigns.profile.id),
         attrs <- %{
           favorite_visual_novels: draft_ids(socket, :visual_novels),
           favorite_characters: draft_ids(socket, :characters)
         },
         {:ok, updated} <- Users.update_user(user, attrs) do
      favorites = load_favorites(updated, socket.assigns[:current_user])

      {:noreply,
       socket
       |> assign(:favorites, favorites)
       |> assign(:draft_favorites, favorites)
       |> assign(:favorites_limit, User.favorites_limit(updated))
       |> assign(:editing, false)
       |> assign(:editor_error, nil)
       |> assign(:search, @empty_search)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :editor_error, changeset_error(changeset))}

      _ ->
        {:noreply, assign(socket, :editor_error, "Failed to save favorites")}
    end
  end

  defp add_favorite(socket, type, id) do
    cond do
      draft_has?(socket, type, id) ->
        {:noreply, assign(socket, :search, @empty_search)}

      draft_count(socket, type) >= socket.assigns.favorites_limit ->
        {:noreply, assign(socket, :editor_error, "#{type_label(type)} is full")}

      true ->
        case load_favorite_item(type, id) do
          {:ok, item} ->
            {:noreply,
             socket
             |> update_draft(type, &(&1 ++ [item]))
             |> assign(:editor_error, nil)
             |> assign(:search, @empty_search)}

          :error ->
            {:noreply, assign(socket, :editor_error, "Could not add favorite")}
        end
    end
  end

  defp assign_search(socket, query) do
    search = socket.assigns.search

    if search.open and (search.type == :visual_novels or search.step == :vn_search) do
      case search_visual_novels(query, socket.assigns[:current_user]) do
        {:ok, results} ->
          assign(socket, :search, %{search | query: query, results: results, error: nil})

        :error ->
          assign(socket, :search, %{
            search
            | query: query,
              results: [],
              error: "Something went wrong"
          })
      end
    else
      socket
    end
  end

  defp search_visual_novels(query, viewer) do
    trimmed = String.trim(query || "")

    if trimmed == "" do
      {:ok, []}
    else
      case ListData.search_visual_novels(trimmed, viewer, page: 1, page_size: @search_page_size) do
        {:ok, %{items: items}} -> {:ok, Enum.map(items, &normalize_search_vn/1)}
        _ -> :error
      end
    end
  end

  defp load_favorite_item(:visual_novels, id) do
    case VisualNovels.get_visual_novel(id) do
      %VisualNovel{} = vn -> {:ok, decorate_vn(vn)}
      _ -> :error
    end
  end

  defp load_favorite_item(:characters, id) do
    case Repo.get(Character, id) do
      %Character{hidden_at: nil} = character -> {:ok, decorate_character(character)}
      _ -> :error
    end
  end

  defp load_characters_for_vn(vn_id, excluded_ids) do
    query =
      from vc in VNCharacter,
        join: c in Character,
        on: c.id == vc.character_id,
        where: vc.visual_novel_id == ^vn_id,
        where: vc.spoiler_level <= 0,
        where: is_nil(c.hidden_at),
        order_by: [
          asc:
            fragment(
              "CASE ? WHEN 'main' THEN 0 WHEN 'primary' THEN 1 WHEN 'side' THEN 2 ELSE 3 END",
              vc.role
            ),
          asc: c.name
        ],
        select: %{character: c, role: vc.role}

    query =
      if excluded_ids == [] do
        query
      else
        where(query, [_vc, c], c.id not in ^excluded_ids)
      end

    query
    |> Repo.all()
    |> Enum.map(fn %{character: character, role: role} ->
      character
      |> decorate_character()
      |> Map.put(:role, role)
    end)
  end

  defp update_draft(socket, type, fun) do
    draft = socket.assigns.draft_favorites
    assign(socket, :draft_favorites, Map.update!(draft, type, fun))
  end

  defp move_item(items, id, direction) do
    index = Enum.find_index(items, &(to_string(&1.id) == to_string(id)))

    cond do
      is_nil(index) ->
        items

      direction == "up" and index > 0 ->
        move(items, index, index - 1)

      direction == "down" and index < length(items) - 1 ->
        move(items, index, index + 1)

      true ->
        items
    end
  end

  @doc false
  # Move the element at `from` to position `to`, shifting the
  # intervening elements (matches @dnd-kit's `arrayMove` semantics).
  # Out-of-range indices are clamped; identical from/to is a no-op.
  defp move(items, from, to) do
    length = length(items)

    cond do
      length == 0 ->
        items

      from < 0 or from >= length ->
        items

      from == to ->
        items

      true ->
        clamped_to = to |> max(0) |> min(length - 1)
        {item, rest} = List.pop_at(items, from)
        List.insert_at(rest, clamped_to, item)
    end
  end

  defp parse_kind(value) when value in ["vn", "visual_novels"], do: {:ok, :visual_novels}
  defp parse_kind(value) when value in ["character", "characters"], do: {:ok, :characters}
  defp parse_kind(_), do: :error

  defp cast_index(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp cast_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp cast_index(_), do: :error

  defp draft_count(socket, type), do: length(Map.get(socket.assigns.draft_favorites, type, []))

  defp draft_ids(socket, type) do
    socket.assigns.draft_favorites
    |> Map.get(type, [])
    |> Enum.map(& &1.id)
  end

  defp draft_has?(socket, type, id) do
    socket.assigns.draft_favorites
    |> Map.get(type, [])
    |> Enum.any?(&(to_string(&1.id) == to_string(id)))
  end

  defp editable?(socket) do
    match?(%{viewer: %{is_mine: true}}, socket.assigns[:profile]) and
      socket.assigns[:editing] in [true, false]
  end

  defp parse_type(value) when value in [:visual_novels, "visual_novels"],
    do: {:ok, :visual_novels}

  defp parse_type(value) when value in [:characters, "characters"], do: {:ok, :characters}
  defp parse_type(_), do: :error

  defp type_label(:visual_novels), do: "Favorite Visual Novels"
  defp type_label(:characters), do: "Favorite Characters"

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message -> "#{Phoenix.Naming.humanize(field)} #{message}" end)
    end)
    |> List.first()
    |> case do
      nil -> "Failed to save favorites"
      message -> message
    end
  end

  defp load_favorites(user, viewer) do
    is_mine = is_map(viewer) and Map.get(viewer, :id) == user.id
    allowed = if is_mine, do: nil, else: TitleCategory.allowed_categories(viewer || %{})

    %{
      visual_novels: load_favorite_vns(user.favorite_visual_novels, allowed),
      characters: load_favorite_characters(user.id)
    }
  end

  defp load_favorite_vns(nil, _allowed), do: []
  defp load_favorite_vns([], _allowed), do: []

  defp load_favorite_vns(ids, allowed) when is_list(ids) do
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
    Character
    |> join(:inner, [c], cf in CharacterFavorite, on: cf.character_id == c.id)
    |> where([_c, cf], cf.user_id == ^user_id)
    |> order_by([_c, cf], asc: cf.position, asc: cf.inserted_at)
    |> Repo.all()
    |> Enum.map(&decorate_character/1)
  end

  defp maybe_filter_category(query, nil), do: query

  defp maybe_filter_category(query, allowed) do
    where(query, [vn], vn.title_category in ^allowed)
  end

  defp decorate_vn(%VisualNovel{} = vn) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      hasEro: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp decorate_character(%Character{} = character) do
    %{
      id: character.id,
      name: character.name,
      slug: character.slug,
      images: VisualNovels.build_character_image_urls(character),
      is_image_nsfw: character.is_image_nsfw,
      is_image_suggestive: character.is_image_suggestive
    }
  end

  defp normalize_search_vn(%VisualNovel{} = vn) do
    vn
    |> decorate_vn()
    |> Map.put(:image_url, image_url(VisualNovels.build_image_urls(vn)))
  end

  defp normalize_search_vn(%{} = item) do
    image_url = Map.get(item, :image_url) || Map.get(item, "image_url")

    %{
      id: Map.get(item, :id) || Map.get(item, "id"),
      title: Map.get(item, :title) || Map.get(item, "title"),
      slug: Map.get(item, :slug) || Map.get(item, "slug"),
      image_url: image_url,
      images: image_map(Map.get(item, :images) || Map.get(item, "images"), image_url),
      producers: Map.get(item, :producers) || Map.get(item, "producers"),
      has_ero: Map.get(item, :has_ero) || Map.get(item, "has_ero"),
      hasEro: Map.get(item, :has_ero) || Map.get(item, "has_ero")
    }
  end

  defp image_map(images, _image_url) when is_map(images) and map_size(images) > 0, do: images

  defp image_map(_images, image_url),
    do: %{small: image_url, medium: image_url, large: image_url, xl: image_url}

  defp image_url(images) when is_map(images) do
    images[:small] || images["small"] || images[:medium] || images["medium"] || images[:large] ||
      images["large"]
  end

  defp image_url(_), do: nil
end
