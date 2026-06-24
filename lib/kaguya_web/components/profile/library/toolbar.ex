defmodule KaguyaWeb.Components.Profile.Library.Toolbar do
  @moduledoc """
  Library page toolbar — mobile status dropdown, mobile search/more button,
  and the desktop shelf pill tabs (plus the custom-labels dropdown).

  Renders `Profile.Library.ControlBar.sort_popover/1` in the mobile bar so
  sort stays a one-line affordance on phones.

  Events emitted: `select_shelf`, `clear_shelf`, `toggle_mobile_search`,
  `set_rating`, `clear_rating`, `set_tag`, `clear_tag` — handled by
  `KaguyaWeb.ProfileLive.Library`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu

  alias KaguyaWeb.Components.Profile.Library.ControlBar
  alias KaguyaWeb.ProfileLive.LibraryData

  attr :shelf, :any, required: true
  attr :filters, :map, required: true
  attr :counts, :map, required: true
  attr :custom_shelves, :list, required: true
  attr :tags, :list, required: true
  attr :profile, :map, required: true
  attr :fade_read, :boolean, required: true
  attr :show_dates, :boolean, required: true
  attr :mobile_search_open, :boolean, required: true

  def toolbar(assigns) do
    shelves =
      for shelf_def <- LibraryData.permanent_shelves(),
          count = count_for(assigns.counts, shelf_def),
          shelf_def.value == "ALL" or count > 0 do
        Map.put(shelf_def, :count, count)
      end

    active = LibraryData.shelf_value(assigns.shelf)
    active_def = Enum.find(shelves, &(&1.value == active)) || List.first(shelves)

    assigns =
      assigns
      |> assign(:shelves, shelves)
      |> assign(:active, active)
      |> assign(:active_def, active_def)

    ~H"""
    <%!-- Mobile shelf trigger (status label + count) --%>
    <div class="mb-4 flex items-center justify-between px-4 lg:hidden">
      <.menu
        id="library-mobile-shelf-selector"
        align="start"
        class="text-foreground-tertiary flex cursor-pointer items-center gap-1.5 text-sm font-medium tracking-wide uppercase"
      >
        <:trigger aria-label="Select shelf">
          {@active_def.label}
          <span class="text-foreground-tertiary font-normal tracking-normal normal-case">
            · {@active_def.count}
          </span>
          <Lucide.chevron_down class="size-4 shrink-0" aria-hidden />
        </:trigger>
        <div class="bg-surface-base border-border-divider flex w-56 flex-col rounded-[8px] border p-1 shadow-lg">
          <.menu_item
            :for={shelf_def <- @shelves}
            event="select_shelf"
            value={%{value: shelf_def.value}}
            class={shelf_menu_item_class(@active == shelf_def.value)}
            aria-current={if @active == shelf_def.value, do: "true"}
          >
            <span class="flex-1">{shelf_def.label}</span>
            <span class="text-foreground-secondary ml-auto text-xs">{shelf_def.count}</span>
          </.menu_item>
        </div>
      </.menu>

      <div class="flex items-center gap-1.5">
        <ControlBar.sort_popover id="library-sort-popover-mobile" shelf={@shelf} filters={@filters} />
        <button
          type="button"
          phx-click="toggle_mobile_search"
          aria-label="Search library"
          class="flex h-fit items-center gap-2 rounded-full border border-white/7 bg-white/4 px-[14px] py-1.5 text-[13px] leading-[21px] text-[rgb(var(--foreground-primary))] transition-colors duration-150 hover:bg-white/7"
        >
          <.search_icon class="size-4" aria-hidden />
        </button>
        <.mobile_more_menu
          filters={@filters}
          tags={@tags}
          custom_shelves={@custom_shelves}
          profile={@profile}
          active={@active}
          fade_read={@fade_read}
          show_dates={@show_dates}
        />
      </div>
    </div>

    <%!-- Mobile search field --%>
    <div :if={@mobile_search_open} class="overflow-hidden lg:hidden">
      <div class="px-4 pb-3">
        <form phx-change="search" phx-submit="search" class="relative">
          <.search_icon
            class="text-foreground-primary/50 pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
            aria-hidden
          />
          <input
            type="search"
            name="value"
            placeholder="Search library..."
            value={@filters.search || ""}
            phx-debounce="250"
            class="border-border-divider no-search-clear placeholder:text-foreground-primary/40 text-foreground-primary h-10 w-full rounded-lg border bg-transparent pr-10 pl-9 text-sm focus:ring-0 focus:outline-hidden"
            autofocus
          />
          <button
            :if={(@filters.search || "") != ""}
            type="button"
            phx-click="clear_search"
            class="hover:text-foreground-primary text-foreground-secondary absolute top-1/2 right-3 -translate-y-1/2 transition-colors"
            aria-label="Clear search"
          >
            <Lucide.x class="size-3.5" aria-hidden />
          </button>
        </form>
      </div>
    </div>

    <%!-- Desktop shelf pill tabs --%>
    <div class="mb-5 hidden items-center gap-2 overflow-hidden lg:flex">
      <div class="flex max-w-[920px] flex-wrap items-center gap-2">
        <button
          :for={shelf_def <- @shelves}
          type="button"
          phx-click="select_shelf"
          phx-value-value={shelf_def.value}
          value={shelf_def.value}
          class={shelf_tab_classes(@active == shelf_def.value)}
          data-shelf={shelf_def.value}
        >
          <%= if @active == shelf_def.value do %>
            {shelf_def.label} · {shelf_def.count}
          <% else %>
            {shelf_def.label} <span class="text-foreground-tertiary">· {shelf_def.count}</span>
          <% end %>
        </button>
      </div>
      <.labels_dropdown :if={@custom_shelves != []} shelves={@custom_shelves} active={@active} />
    </div>
    """
  end

  attr :shelves, :list, required: true
  attr :active, :string, required: true

  defp labels_dropdown(assigns) do
    selected = Enum.find(assigns.shelves, &(&1.slug == assigns.active))
    label = (selected && selected.name) || "Labels"

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:label, label)

    ~H"""
    <.menu
      id="library-labels-dropdown"
      align="end"
      side_offset={8}
      class="text-foreground-secondary ml-auto flex shrink-0 cursor-pointer items-center gap-1.5 py-2 pr-0 pl-[10px] text-sm/5 whitespace-nowrap transition-colors"
    >
      <:trigger>
        {@label}
        <Lucide.chevron_down class="size-4" aria-hidden />
      </:trigger>
      <div class="bg-surface-elevated border-border-divider flex w-[216px] flex-col rounded-[12px] border p-0 py-1 shadow-lg">
        <.menu_item
          :if={@selected}
          event="clear_shelf"
          class="border-border-divider text-foreground-secondary flex h-[41px] items-center justify-between border-b px-[19px] text-sm hover:bg-white/4"
        >
          Clear
        </.menu_item>
        <.menu_item
          :for={shelf <- @shelves}
          event="select_shelf"
          value={%{value: shelf.slug}}
          class={"flex h-[41px] w-full items-center justify-between px-[19px] text-sm hover:bg-white/4" <>
      if(shelf.slug == @active, do: "bg-white/6 font-medium", else: "")}
        >
          <span class="truncate">{shelf.name}</span>
          <span class="text-foreground-secondary text-xs">{shelf.vns_count}</span>
        </.menu_item>
      </div>
    </.menu>
    """
  end

  attr :filters, :map, required: true
  attr :tags, :list, required: true
  attr :custom_shelves, :list, required: true
  attr :profile, :map, required: true
  attr :active, :string, required: true
  attr :fade_read, :boolean, required: true
  attr :show_dates, :boolean, required: true

  defp mobile_more_menu(assigns) do
    show_fade_toggle =
      not assigns.profile.viewer.is_mine and assigns.profile.viewer.is_logged_in

    has_active_label =
      Enum.any?(assigns.custom_shelves, &(&1.slug == assigns.active))

    assigns =
      assigns
      |> assign(:show_fade_toggle, show_fade_toggle)
      |> assign(:show_dates_toggle, assigns.profile.viewer.is_mine)
      |> assign(:has_active_label, has_active_label)
      |> assign(:rating_options, ControlBar.rating_options())

    ~H"""
    <details class="group relative lg:hidden">
      <summary
        class="flex h-fit cursor-pointer list-none items-center gap-2 rounded-full border border-white/7 bg-white/4 px-[14px] py-1.5 text-[13px] leading-[21px] text-[rgb(var(--foreground-primary))] transition-colors duration-150 hover:bg-white/7"
        aria-label="More library filters"
      >
        <Lucide.ellipsis class="size-4" aria-hidden />
      </summary>

      <div
        class="bg-surface-elevated border-border-divider absolute right-0 z-40 mt-2 flex w-[240px] flex-col rounded-[12px] border p-1 shadow-lg"
        role="menu"
        aria-label="More library filters"
      >
        <details class="group/rating">
          <summary class="text-foreground-primary flex h-10 cursor-pointer list-none items-center justify-between rounded-lg px-3 text-sm hover:bg-white/4">
            <span class="flex items-center gap-2.5">
              <Lucide.star
                class={["size-4", @filters.rating && "fill-current"]}
                aria-hidden
              /> Rating
            </span>
            <span :if={@filters.rating} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="px-1 pb-1">
            <button
              type="button"
              phx-click="clear_rating"
              class="text-foreground-secondary flex h-8 w-full items-center rounded-md px-3 text-sm hover:bg-white/4"
            >
              All ratings
            </button>
            <button
              :for={{value, label} <- @rating_options}
              type="button"
              phx-click="set_rating"
              phx-value-value={ControlBar.rating_value(value)}
              value={ControlBar.rating_value(value)}
              class={[
                "flex h-8 w-full items-center rounded-md px-3 text-sm",
                @filters.rating == value && "text-foreground-primary bg-white/6 font-medium",
                @filters.rating != value && "text-foreground-secondary hover:bg-white/4"
              ]}
            >
              <ControlBar.rating_stars value={value} active={@filters.rating == value} label={label} />
            </button>
          </div>
        </details>

        <details class="group/tags">
          <summary class="text-foreground-primary flex h-10 cursor-pointer list-none items-center justify-between rounded-lg px-3 text-sm hover:bg-white/4">
            <span class="flex items-center gap-2.5">
              <Lucide.tag
                class={["size-4", @filters.tag_slug && "fill-current"]}
                aria-hidden
              /> Tags
            </span>
            <span :if={@filters.tag_slug} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="max-h-[220px] overflow-y-auto px-1 pb-1">
            <button
              :if={@filters.tag_slug}
              type="button"
              phx-click="clear_tag"
              class="text-foreground-secondary flex h-8 w-full items-center rounded-md px-3 text-sm hover:bg-white/4"
            >
              Clear filter
            </button>
            <button
              :for={tag <- @tags}
              type="button"
              phx-click="set_tag"
              phx-value-value={tag.tag_slug}
              value={tag.tag_slug}
              class={[
                "flex h-8 w-full items-center justify-between rounded-md px-3 text-sm",
                @filters.tag_slug == tag.tag_slug &&
                  "text-foreground-primary bg-white/6 font-medium",
                @filters.tag_slug != tag.tag_slug && "text-foreground-secondary hover:bg-white/4"
              ]}
            >
              <span class="truncate">{tag.tag_name}</span>
              <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
                {tag.count}
              </span>
            </button>
            <p :if={@tags == []} class="text-foreground-tertiary p-3 text-sm">
              No tags
            </p>
          </div>
        </details>

        <details class="group/labels">
          <summary class="text-foreground-primary flex h-10 cursor-pointer list-none items-center justify-between rounded-lg px-3 text-sm hover:bg-white/4">
            <span class="flex items-center gap-2.5">
              <Lucide.tag
                class={["size-4", @has_active_label && "fill-current"]}
                aria-hidden
              /> Labels
            </span>
            <span :if={@has_active_label} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="max-h-[220px] overflow-y-auto px-1 pb-1">
            <button
              :if={@has_active_label}
              type="button"
              phx-click="clear_shelf"
              class="text-foreground-secondary flex h-8 w-full items-center rounded-md px-3 text-sm hover:bg-white/4"
            >
              Clear
            </button>
            <button
              :for={shelf <- @custom_shelves}
              type="button"
              phx-click="select_shelf"
              phx-value-value={shelf.slug}
              value={shelf.slug}
              class={[
                "flex h-8 w-full items-center justify-between rounded-md px-3 text-sm",
                shelf.slug == @active && "text-foreground-primary bg-white/6 font-medium",
                shelf.slug != @active && "text-foreground-secondary hover:bg-white/4"
              ]}
            >
              <span class="truncate">{shelf.name}</span>
              <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
                {shelf.vns_count}
              </span>
            </button>
            <p :if={@custom_shelves == []} class="text-foreground-tertiary p-3 text-sm">
              No labels
            </p>
          </div>
        </details>

        <div :if={@show_dates_toggle or @show_fade_toggle} class="bg-border-divider my-1 h-px" />

        <button
          :if={@show_dates_toggle}
          type="button"
          data-show-dates-toggle
          aria-pressed={to_string(@show_dates)}
          class="text-foreground-primary flex h-10 items-center justify-between rounded-lg px-3 text-sm hover:bg-white/4"
        >
          <span class="flex items-center gap-2.5">
            <Lucide.calendar class="text-foreground-secondary size-4" aria-hidden /> Show dates
          </span>
          <span class={[
            "h-5 w-9 rounded-full p-0.5 transition-colors",
            @show_dates && "bg-foreground-primary",
            !@show_dates && "bg-white/16"
          ]}>
            <span class={[
              "bg-surface-base block size-4 rounded-full transition-transform",
              @show_dates && "translate-x-4"
            ]}>
            </span>
          </span>
        </button>

        <button
          :if={@show_fade_toggle}
          type="button"
          data-fade-toggle
          aria-pressed={to_string(@fade_read)}
          class="text-foreground-primary flex h-10 items-center justify-between rounded-lg px-3 text-sm hover:bg-white/4"
        >
          <span class="flex items-center gap-2.5">
            <Lucide.eye class="text-foreground-secondary size-4" aria-hidden /> Fade read
          </span>
          <span class={[
            "h-5 w-9 rounded-full p-0.5 transition-colors",
            @fade_read && "bg-foreground-primary",
            !@fade_read && "bg-white/16"
          ]}>
            <span class={[
              "bg-surface-base block size-4 rounded-full transition-transform",
              @fade_read && "translate-x-4"
            ]}>
            </span>
          </span>
        </button>
      </div>
    </details>
    """
  end

  defp count_for(counts, %{value: "ALL"}), do: Map.get(counts, :all, 0)
  defp count_for(counts, %{status: status}), do: Map.get(counts, status, 0)

  defp shelf_menu_item_class(true) do
    "flex h-[48px] items-center gap-3 px-5 text-left text-sm font-medium bg-white/[4%]"
  end

  defp shelf_menu_item_class(false) do
    "flex h-[48px] items-center gap-3 px-5 text-left text-sm font-normal"
  end

  defp shelf_tab_classes(true) do
    "flex shrink-0 items-center justify-center border whitespace-nowrap transition-colors px-[10px] py-2 " <>
      "bg-[rgb(var(--tab-background-active))] border-[rgb(var(--tab-background-active))] text-[rgb(var(--tab-text-active))] text-style-body2Medium font-medium"
  end

  defp shelf_tab_classes(false) do
    "flex shrink-0 items-center justify-center border whitespace-nowrap transition-colors px-[10px] py-2 " <>
      "bg-[rgb(var(--tab-background-default))] border-[rgb(var(--tab-border-default))] text-[rgb(var(--tab-text-default))] hover:border-[rgb(var(--tab-border-hover))] text-style-body2Regular"
  end
end
