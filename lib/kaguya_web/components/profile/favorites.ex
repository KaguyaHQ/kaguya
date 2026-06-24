defmodule KaguyaWeb.Components.Profile.Favorites do
  @moduledoc """
  Favorites tab read/edit rendering.

  The edit surface mirrors the production `FavoritesEditor` shape while keeping
  persistence and search in the LiveView.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.VN.Cards
  alias KaguyaWeb.SharedComponents.Cover, as: SharedCover

  attr :profile, :map, required: true
  attr :favorites, :map, required: true
  attr :editing, :boolean, default: false
  attr :draft_favorites, :map, required: true
  attr :favorites_limit, :integer, required: true
  attr :editor_error, :string, default: nil
  attr :search, :map, required: true

  def favorites_body(assigns) do
    favorite_vns = assigns.favorites.visual_novels || []
    favorite_characters = assigns.favorites.characters || []
    has_any? = favorite_vns != [] or favorite_characters != []

    assigns =
      assigns
      |> assign(:favorite_vns, favorite_vns)
      |> assign(:favorite_characters, favorite_characters)
      |> assign(:is_mine, assigns.profile.viewer.is_mine)
      |> assign(:has_any?, has_any?)

    ~H"""
    <section class="mx-auto mt-8 max-w-[988px] px-4 pt-2 pb-6 sm:py-6 lg:mt-10 lg:px-6 lg:pt-0">
      <%= if @editing do %>
        <.editor
          draft_favorites={@draft_favorites}
          favorites_limit={@favorites_limit}
          editor_error={@editor_error}
          search={@search}
        />
      <% else %>
        <div :if={@is_mine and @has_any?} class="mb-6 flex items-center justify-end">
          <button
            type="button"
            phx-click="open_editor"
            class="text-style-body2Regular text-[rgb(var(--foreground-tertiary))] transition-colors hover:text-[rgb(var(--foreground-secondary))]"
          >
            Edit favorites
          </button>
        </div>

        <div class="flex flex-col gap-10">
          <.favorite_vns_section items={@favorite_vns} is_mine={@is_mine} />
          <.favorite_characters_section items={@favorite_characters} is_mine={@is_mine} />
        </div>
      <% end %>
    </section>
    """
  end

  attr :draft_favorites, :map, required: true
  attr :favorites_limit, :integer, required: true
  attr :editor_error, :string, default: nil
  attr :search, :map, required: true

  defp editor(assigns) do
    ~H"""
    <div>
      <div class="mb-8">
        <div class="mb-2 flex items-center justify-between gap-4">
          <h1 class="text-style-body1Medium text-[rgb(var(--foreground-primary))]">Edit favorites</h1>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="cancel_editor"
              class="text-style-body2Medium px-3 py-1.5 text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="save_editor"
              class="text-style-body2Medium rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-4 py-1.5 text-white transition-colors hover:bg-[rgb(var(--button-background-brand-hover))]"
            >
              Save
            </button>
          </div>
        </div>
        <p class="text-style-captionRegular text-[rgb(var(--foreground-tertiary))]">
          Move items to reorder
        </p>
        <p
          :if={@editor_error}
          role="alert"
          class="text-style-body2Regular mt-2 text-[rgb(var(--foreground-error))]"
        >
          {@editor_error}
        </p>
      </div>

      <div class="flex flex-col gap-10">
        <.editable_section
          title="Favorite Visual Novels"
          type={:visual_novels}
          items={@draft_favorites.visual_novels}
          limit={@favorites_limit}
        />

        <.editable_section
          title="Favorite Characters"
          type={:characters}
          items={@draft_favorites.characters}
          limit={@favorites_limit}
        />
      </div>

      <.search_dialog search={@search} />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :type, :atom, required: true
  attr :items, :list, required: true
  attr :limit, :integer, required: true

  defp editable_section(assigns) do
    assigns =
      assigns
      |> assign(:count, length(assigns.items || []))
      |> assign(:kind, kind_for(assigns.type))
      |> assign(:grid_id, "favorites-grid-#{assigns.type}")
      |> assign(:fallback_id, "favorites-fallback-#{assigns.type}")
      |> assign(:items_json, Jason.encode!(items_for_island(assigns.items, assigns.type)))

    ~H"""
    <section>
      <div class="mb-4 flex items-center gap-3">
        <h2 class="text-style-body1Medium text-[rgb(var(--foreground-primary))]">{@title}</h2>
        <span class="text-style-captionRegular text-[rgb(var(--foreground-tertiary))]">
          {@count}/{@limit}
        </span>
      </div>

      <%!--
        React + dnd-kit island. `phx-update="ignore"` hands the DOM inside
        this node fully to the island so drag interactions stay smooth and
        Phoenix patches don't fight with React. State flows in via the
        `data-items` JSON; the hook re-syncs the SortableContext on each
        re-render.
      --%>
      <div
        id={@grid_id}
        phx-hook="FavoritesDnd"
        phx-update="ignore"
        data-kind={@kind}
        data-limit={@limit}
        data-items={@items_json}
        data-island-src={~p"/assets/js/favorites_dnd_island.js"}
      >
      </div>

      <%!--
        No-JS / accessibility fallback. Rendered outside the React-owned
        container so they don't conflict with the island's DOM ownership.
        These chevron controls remain functional when JS is disabled or
        the island bundle fails to load.
      --%>
      <noscript>
        <div
          id={@fallback_id}
          class="mt-4 grid grid-cols-4 gap-4 sm:grid-cols-5 sm:gap-6 lg:gap-8"
        >
          <.editable_item
            :for={{item, index} <- Enum.with_index(@items)}
            item={item}
            type={@type}
            index={index}
            count={@count}
          />

          <button
            :if={@count < @limit}
            type="button"
            phx-click="open_favorite_search"
            phx-value-type={@type}
            class="group flex aspect-2/3 items-center justify-center rounded-[4px] border border-dashed border-[rgb(var(--border-divider))] text-[rgb(var(--border-divider))] transition-colors hover:border-[rgb(var(--border-strong-divider))] hover:text-[rgb(var(--foreground-secondary))]"
            aria-label={"Add #{@title}"}
          >
            <Lucide.plus class="size-6" aria-hidden />
          </button>
        </div>
      </noscript>
    </section>
    """
  end

  # Build the JSON payload the React island consumes. The island needs
  # enough to render a cover/character image — id, title, slug, and the
  # responsive image map (with image_url fallback).
  defp items_for_island(items, type) do
    items
    |> List.wrap()
    |> Enum.map(&item_for_island(&1, type))
  end

  defp item_for_island(item, :visual_novels) do
    %{
      id: to_string(item.id),
      title: Map.get(item, :title) || "",
      slug: Map.get(item, :slug),
      images: normalize_images(Map.get(item, :images)),
      image_url: Map.get(item, :image_url),
      has_ero: Map.get(item, :has_ero) || false,
      is_image_nsfw: Map.get(item, :is_image_nsfw) || false,
      is_image_suggestive: Map.get(item, :is_image_suggestive) || false
    }
  end

  defp item_for_island(item, :characters) do
    %{
      id: to_string(item.id),
      name: Map.get(item, :name) || "",
      title: Map.get(item, :name) || "",
      slug: Map.get(item, :slug),
      images: normalize_images(Map.get(item, :images)),
      image_url: Map.get(item, :image_url),
      is_image_nsfw: Map.get(item, :is_image_nsfw) || false,
      is_image_suggestive: Map.get(item, :is_image_suggestive) || false
    }
  end

  defp normalize_images(nil), do: %{}

  defp normalize_images(%{} = images) do
    images
    |> Enum.flat_map(fn
      {key, value} when is_binary(value) and value != "" -> [{to_string(key), value}]
      _ -> []
    end)
    |> Map.new()
  end

  defp normalize_images(_), do: %{}

  defp kind_for(:visual_novels), do: "visual_novels"
  defp kind_for(:characters), do: "characters"

  attr :item, :map, required: true
  attr :type, :atom, required: true
  attr :index, :integer, required: true
  attr :count, :integer, required: true

  defp editable_item(assigns) do
    assigns =
      assigns
      |> assign(:item_id, to_string(assigns.item.id))
      |> assign(:title, item_title(assigns.item))

    ~H"""
    <div
      class="group/fav relative select-none"
      data-favorite-item
      data-id={@item_id}
      data-key={@item_id}
      data-index={@index}
    >
      <.editable_art item={@item} type={@type} />

      <button
        type="button"
        phx-click="remove_favorite"
        phx-value-type={@type}
        phx-value-id={@item_id}
        class="absolute -top-1.5 -right-1.5 z-10 flex size-5 items-center justify-center rounded-full bg-black/70 text-white opacity-100 backdrop-blur-xs transition-opacity sm:opacity-0 sm:group-hover/fav:opacity-100 sm:focus-visible:opacity-100"
        aria-label={"Remove #{@title} from favorites"}
      >
        <Lucide.x class="size-2.5" aria-hidden />
      </button>

      <div class="absolute inset-x-1 bottom-1 z-10 flex justify-between gap-1 opacity-100 transition-opacity sm:opacity-0 sm:group-hover/fav:opacity-100 sm:focus-within:opacity-100">
        <button
          type="button"
          phx-click="move_favorite"
          phx-value-type={@type}
          phx-value-id={@item_id}
          phx-value-direction="up"
          disabled={@index == 0}
          class="flex size-7 items-center justify-center rounded-full bg-black/70 text-white backdrop-blur-xs transition hover:bg-black/90 disabled:cursor-not-allowed disabled:opacity-35"
          aria-label={"Move #{@title} up"}
        >
          <Lucide.chevron_up class="size-4" aria-hidden />
        </button>
        <button
          type="button"
          phx-click="move_favorite"
          phx-value-type={@type}
          phx-value-id={@item_id}
          phx-value-direction="down"
          disabled={@index == @count - 1}
          class="flex size-7 items-center justify-center rounded-full bg-black/70 text-white backdrop-blur-xs transition hover:bg-black/90 disabled:cursor-not-allowed disabled:opacity-35"
          aria-label={"Move #{@title} down"}
        >
          <Lucide.chevron_down class="size-4" aria-hidden />
        </button>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :type, :atom, required: true

  defp editable_art(assigns) do
    ~H"""
    <%= if @type == :visual_novels do %>
      <Cards.cover
        vn={@item}
        sizes="(max-width: 640px) 90px, 170px"
        class="aspect-2/3 w-full rounded-[4px] object-cover"
        fallback_class="rounded-[4px]"
      />
    <% else %>
      <Cards.character_image
        character={@item}
        sizes="(max-width: 640px) 90px, 170px"
        class="aspect-2/3 w-full object-cover"
        rounded="rounded-[4px]"
      />
    <% end %>
    """
  end

  attr :items, :list, required: true
  attr :is_mine, :boolean, required: true

  defp favorite_vns_section(assigns) do
    ~H"""
    <section>
      <h2 class="text-style-body1Medium mb-4 text-[rgb(var(--foreground-primary))]">
        Favorite Visual Novels
      </h2>

      <%= if @items != [] do %>
        <SharedCover.cover_tooltip_provider id="favorite-vns-cover-tooltip">
          <div class="grid grid-cols-4 gap-4 sm:grid-cols-5 sm:gap-6 lg:gap-8">
            <.link :for={vn <- @items} navigate={vn_path(vn)} class="block" aria-label={vn.title}>
              <Cards.cover
                vn={vn}
                sizes="(max-width: 640px) 25vw, (max-width: 1024px) 140px, 170px"
                class="aspect-2/3 w-full rounded-[4px] object-cover object-center"
                fallback_class="rounded-[4px]"
              />
            </.link>
          </div>
        </SharedCover.cover_tooltip_provider>
      <% else %>
        <.empty_state is_mine={@is_mine} />
      <% end %>
    </section>
    """
  end

  attr :items, :list, required: true
  attr :is_mine, :boolean, required: true

  defp favorite_characters_section(assigns) do
    ~H"""
    <section>
      <h2 class="text-style-body1Medium mb-4 text-[rgb(var(--foreground-primary))]">
        Favorite Characters
      </h2>

      <%= if @items != [] do %>
        <div class="grid grid-cols-4 gap-4 sm:grid-cols-5 sm:gap-6 lg:gap-8">
          <%= for character <- @items do %>
            <%= if character_path(character) do %>
              <.link navigate={character_path(character)} class="block" aria-label={character.name}>
                <Cards.character_image
                  character={character}
                  sizes="(max-width: 640px) 25vw, (max-width: 1024px) 140px, 170px"
                  class="aspect-2/3 w-full object-cover"
                  rounded="rounded-[4px]"
                />
              </.link>
            <% else %>
              <Cards.character_image
                character={character}
                sizes="(max-width: 640px) 25vw, (max-width: 1024px) 140px, 170px"
                class="aspect-2/3 w-full object-cover"
                rounded="rounded-[4px]"
              />
            <% end %>
          <% end %>
        </div>
      <% else %>
        <.empty_state is_mine={@is_mine} />
      <% end %>
    </section>
    """
  end

  attr :is_mine, :boolean, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="py-8 text-center">
      <%= if @is_mine do %>
        <button
          type="button"
          phx-click="open_editor"
          class="text-style-body2Regular text-[rgb(var(--foreground-tertiary))] transition-colors hover:text-[rgb(var(--foreground-secondary))]"
        >
          Add your favorites
        </button>
      <% else %>
        <p class="text-style-body2Regular text-[rgb(var(--foreground-tertiary))]">
          No favorites added yet
        </p>
      <% end %>
    </div>
    """
  end

  attr :search, :map, required: true

  defp search_dialog(assigns) do
    assigns =
      assigns
      |> assign(:open, Map.get(assigns.search, :open, false))
      |> assign(:type, Map.get(assigns.search, :type))
      |> assign(:step, Map.get(assigns.search, :step))
      |> assign(:query, Map.get(assigns.search, :query, ""))
      |> assign(:results, Map.get(assigns.search, :results, []))
      |> assign(:characters, Map.get(assigns.search, :characters, []))
      |> assign(:selected_vn, Map.get(assigns.search, :selected_vn))
      |> assign(:error, Map.get(assigns.search, :error))

    ~H"""
    <div
      :if={@open}
      class="fixed inset-0 z-100 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
      phx-window-keydown="close_favorite_search"
      phx-key="Escape"
    >
      <button
        type="button"
        phx-click="close_favorite_search"
        class="absolute inset-0 cursor-default"
        aria-label="Close favorites search"
      >
      </button>

      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="favorite-search-title"
        class="relative flex max-h-[88vh] w-full max-w-[480px] flex-col overflow-hidden rounded-t-[16px] bg-[rgb(var(--surface-base))] shadow-2xl sm:rounded-[16px]"
      >
        <div class="flex items-center gap-2 px-6 pt-6 pr-12 pb-4">
          <button
            :if={@type == :characters and @step == :character_select}
            type="button"
            phx-click="back_to_character_vn_search"
            class="flex size-7 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))]"
            aria-label="Back"
          >
            <Lucide.chevron_left class="size-5 text-[rgb(var(--foreground-primary))]" aria-hidden />
          </button>
          <h2
            id="favorite-search-title"
            class="line-clamp-1 text-left text-xl font-medium text-[rgb(var(--foreground-primary))]"
          >
            {dialog_title(@type, @step, @selected_vn)}
          </h2>
        </div>

        <%= if @type == :visual_novels or @step == :vn_search do %>
          <div class="px-6 pb-6">
            <.form
              for={%{}}
              as={:favorite_search}
              id="favorite-search-form"
              phx-change="search_favorite"
              phx-submit="search_favorite"
              class="relative"
            >
              <.search_icon
                class="pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2 text-[rgb(var(--foreground-tertiary))]"
                aria-hidden
              />
              <input
                type="search"
                name="favorite_search[query]"
                value={@query}
                placeholder="Search visual novels"
                autocomplete="off"
                phx-debounce="350"
                class="h-11 w-full rounded-full border-none bg-[rgb(var(--surface-elevated))] pr-4 pl-11 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:ring-0 focus:outline-none"
                data-modal-initial-focus
              />
            </.form>
            <div class="mt-4 max-h-[320px] min-h-[280px] overflow-y-auto">
              <.search_message :if={@error} message="Something went wrong" />
              <div
                :if={!@error and String.trim(@query || "") == ""}
                class="h-[280px]"
                aria-hidden="true"
              />
              <.search_message
                :if={!@error and String.trim(@query || "") != "" and @results == []}
                message="No matches"
              />
              <div :if={!@error and @results != []} class="space-y-1">
                <.vn_search_row
                  :for={vn <- @results}
                  vn={vn}
                  select_event={
                    if(@type == :characters, do: "select_character_search_vn", else: "add_favorite")
                  }
                  type={@type}
                />
              </div>
            </div>
          </div>
        <% else %>
          <div class="px-6 pb-6">
            <div class="max-h-[400px] min-h-[320px] overflow-y-auto">
              <.search_message :if={@error} message="Something went wrong" />
              <.search_message :if={!@error and @characters == []} message="No characters found" />
              <div :if={!@error and @characters != []} class="grid grid-cols-3 gap-3 sm:grid-cols-4">
                <button
                  :for={character <- @characters}
                  type="button"
                  phx-click="add_favorite"
                  phx-value-type="characters"
                  phx-value-id={character.id}
                  class="group flex flex-col items-center rounded-lg p-2 transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:outline-none"
                >
                  <Cards.character_image
                    character={character}
                    sizes="(max-width: 640px) 90px, 110px"
                    class="aspect-2/3 w-full rounded-[8px] object-cover transition-all group-hover:ring-2 group-hover:ring-[rgb(var(--foreground-primary))]/50"
                    rounded="rounded-[8px]"
                  />
                  <span class="mt-2 line-clamp-1 w-full text-center text-xs font-medium text-[rgb(var(--foreground-primary))]">
                    {character.name}
                  </span>
                  <span
                    :if={character[:role]}
                    class="mt-1 text-[10px] text-[rgb(var(--foreground-tertiary))] uppercase"
                  >
                    {role_label(character[:role])}
                  </span>
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :message, :string, required: true

  defp search_message(assigns) do
    ~H"""
    <div class="flex h-[280px] items-center justify-center text-sm text-[rgb(var(--foreground-tertiary))]">
      {@message}
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :select_event, :string, required: true
  attr :type, :atom, required: true

  defp vn_search_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@select_event}
      phx-value-type={@type}
      phx-value-id={@vn.id}
      class="flex w-full items-center gap-4 rounded-lg p-3 text-left transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:outline-none"
    >
      <div class="h-[84px] w-14 shrink-0 overflow-hidden rounded-md bg-[rgb(var(--surface-elevated))]">
        <Cards.cover
          vn={@vn}
          sizes="56px"
          class="h-[84px] w-14 rounded-md object-cover"
          fallback_class="h-[84px] w-14 rounded-md"
        />
      </div>
      <span class="min-w-0 flex-1">
        <span class="line-clamp-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
          {@vn.title}
        </span>
        <span
          :if={@vn[:producers]}
          class="mt-1 line-clamp-1 text-xs text-[rgb(var(--foreground-tertiary))]"
        >
          {@vn.producers}
        </span>
      </span>
    </button>
    """
  end

  defp item_title(%{title: title}) when is_binary(title), do: title
  defp item_title(%{name: name}) when is_binary(name), do: name
  defp item_title(_), do: "favorite"

  defp dialog_title(:visual_novels, _step, _selected_vn), do: "Add visual novel"

  defp dialog_title(:characters, :character_select, %{title: title}) when is_binary(title),
    do: title

  defp dialog_title(:characters, _step, _selected_vn), do: "Add character"
  defp dialog_title(_, _, _), do: "Add favorite"

  defp role_label(:main), do: "Main"
  defp role_label(:primary), do: "Primary"
  defp role_label(:side), do: "Side"
  defp role_label(:appears), do: "Appears"
  defp role_label(value) when is_binary(value), do: String.capitalize(value)
  defp role_label(_), do: nil

  defp vn_path(%{slug: slug}) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  defp vn_path(_), do: "#"

  defp character_path(%{slug: slug}) when is_binary(slug) and slug != "", do: "/character/#{slug}"
  defp character_path(_), do: nil
end
