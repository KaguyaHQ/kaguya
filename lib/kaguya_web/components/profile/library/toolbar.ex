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
  alias KaguyaWeb.UI.FilterControl

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
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3 px-4 lg:hidden">
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
        <div class={[FilterControl.panel_class(), "w-56"]}>
          <.menu_item
            :for={shelf_def <- @shelves}
            event="select_shelf"
            value={%{value: shelf_def.value}}
            class={FilterControl.option_class(@active == shelf_def.value)}
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
          id="library-mobile-search-toggle"
          phx-click="toggle_mobile_search"
          aria-expanded={to_string(@mobile_search_open)}
          aria-controls="library-mobile-search"
          aria-label="Search library"
          class={FilterControl.trigger_class(@mobile_search_open)}
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
    <div id="library-mobile-search" class={["px-4 pb-3 lg:hidden", !@mobile_search_open && "hidden"]}>
      <ControlBar.search_input
        :if={@mobile_search_open}
        id="library-search-mobile"
        value={@filters.search || ""}
        autofocus
      />
    </div>

    <%!-- Desktop shelf navigation --%>
    <div class="mb-5 hidden items-center gap-2 overflow-hidden lg:flex">
      <div class="flex max-w-[920px] flex-wrap items-center gap-2">
        <button
          :for={shelf_def <- @shelves}
          type="button"
          phx-click="select_shelf"
          phx-value-value={shelf_def.value}
          value={shelf_def.value}
          id={"library-shelf-#{shelf_def.value}"}
          aria-pressed={to_string(@active == shelf_def.value)}
          class={shelf_trigger_class(@active == shelf_def.value)}
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
      class={[shelf_trigger_class(not is_nil(@selected)), "ml-auto"]}
    >
      <:trigger>
        {@label}
        <Lucide.chevron_down class="size-4" aria-hidden />
      </:trigger>
      <div class={[FilterControl.panel_class(), "w-[216px]"]}>
        <.menu_item
          :if={@selected}
          event="clear_shelf"
          class={FilterControl.option_class()}
        >
          Clear
        </.menu_item>
        <.menu_item
          :for={shelf <- @shelves}
          event="select_shelf"
          value={%{value: shelf.slug}}
          class={FilterControl.option_class(shelf.slug == @active)}
          aria-pressed={to_string(shelf.slug == @active)}
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
    <.menu id="library-mobile-more-menu" align="end" class={FilterControl.trigger_class()}>
      <:trigger aria-label="More library filters">
        <Lucide.ellipsis class="size-4" aria-hidden />
      </:trigger>
      <div class={[FilterControl.panel_class(), "max-h-[70dvh] w-[260px] overflow-y-auto"]}>
        <details class="group/rating">
          <summary class={[FilterControl.option_class(), "list-none"]}>
            <span class="flex items-center gap-2.5">
              <Lucide.star
                class={["size-4", @filters.rating && "fill-current"]}
                aria-hidden
              /> Rating
            </span>
            <span :if={@filters.rating} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="px-1 pb-1">
            <.menu_item
              event="clear_rating"
              class={FilterControl.option_class(is_nil(@filters.rating))}
              aria-pressed={to_string(is_nil(@filters.rating))}
            >
              All ratings
            </.menu_item>
            <.menu_item
              :for={{value, label} <- @rating_options}
              event="set_rating"
              value={%{value: ControlBar.rating_value(value)}}
              class={FilterControl.option_class(@filters.rating == value)}
              aria-pressed={to_string(@filters.rating == value)}
            >
              <ControlBar.rating_stars value={value} active={@filters.rating == value} label={label} />
            </.menu_item>
          </div>
        </details>

        <details class="group/tags">
          <summary class={[FilterControl.option_class(), "list-none"]}>
            <span class="flex items-center gap-2.5">
              <Lucide.tag
                class={["size-4", @filters.tag_slug && "fill-current"]}
                aria-hidden
              /> Tags
            </span>
            <span :if={@filters.tag_slug} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="max-h-[220px] overflow-y-auto px-1 pb-1">
            <.menu_item
              :if={@filters.tag_slug}
              event="clear_tag"
              class={FilterControl.option_class()}
            >
              Clear filter
            </.menu_item>
            <.menu_item
              :for={tag <- @tags}
              event="set_tag"
              value={%{value: tag.tag_slug}}
              class={FilterControl.option_class(@filters.tag_slug == tag.tag_slug)}
              aria-pressed={to_string(@filters.tag_slug == tag.tag_slug)}
            >
              <span class="truncate">{tag.tag_name}</span>
              <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
                {tag.count}
              </span>
            </.menu_item>
            <p :if={@tags == []} class="text-foreground-tertiary p-3 text-sm">
              No tags
            </p>
          </div>
        </details>

        <details class="group/labels">
          <summary class={[FilterControl.option_class(), "list-none"]}>
            <span class="flex items-center gap-2.5">
              <Lucide.tag
                class={["size-4", @has_active_label && "fill-current"]}
                aria-hidden
              /> Labels
            </span>
            <span :if={@has_active_label} class="bg-foreground-secondary size-1.5 rounded-full" />
          </summary>
          <div class="max-h-[220px] overflow-y-auto px-1 pb-1">
            <.menu_item
              :if={@has_active_label}
              event="clear_shelf"
              class={FilterControl.option_class()}
            >
              Clear
            </.menu_item>
            <.menu_item
              :for={shelf <- @custom_shelves}
              event="select_shelf"
              value={%{value: shelf.slug}}
              class={FilterControl.option_class(shelf.slug == @active)}
              aria-pressed={to_string(shelf.slug == @active)}
            >
              <span class="truncate">{shelf.name}</span>
              <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
                {shelf.vns_count}
              </span>
            </.menu_item>
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
          class={FilterControl.option_class()}
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
            ]}></span>
          </span>
        </button>

        <button
          :if={@show_fade_toggle}
          type="button"
          data-fade-toggle
          aria-pressed={to_string(@fade_read)}
          class={FilterControl.option_class()}
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
            ]}></span>
          </span>
        </button>
      </div>
    </.menu>
    """
  end

  defp shelf_trigger_class(selected?) do
    [
      "inline-flex shrink-0 cursor-pointer items-center justify-center gap-1.5 rounded-md border px-[10px] py-2 whitespace-nowrap transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground-secondary",
      if(selected?,
        do:
          "border-[rgb(var(--tab-background-active))] bg-[rgb(var(--tab-background-active))] text-[rgb(var(--tab-text-active))] text-style-body2Medium",
        else:
          "border-[rgb(var(--tab-border-default))] bg-[rgb(var(--tab-background-default))] text-[rgb(var(--tab-text-default))] hover:border-[rgb(var(--tab-border-hover))] text-style-body2Regular"
      )
    ]
  end

  defp count_for(counts, %{value: "ALL"}), do: Map.get(counts, :all, 0)
  defp count_for(counts, %{status: status}), do: Map.get(counts, status, 0)
end
