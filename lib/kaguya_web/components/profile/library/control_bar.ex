defmodule KaguyaWeb.Components.Profile.Library.ControlBar do
  @moduledoc """
  Desktop control bar for `/@:username/library` — sort/rating/tag popovers,
  search input, active-filter chips, and the fade-read toggle.

  Exported helpers (`sort_popover/1`, `rating_stars/1`, `rating_options/0`,
  `rating_value/1`, `rating_bucket/2`) are also consumed by the mobile
  toolbar in `Profile.Library.Toolbar`.

  Events emitted: `set_sort`, `clear_sort`, `set_rating`, `clear_rating`,
  `set_tag`, `clear_tag`, `search`, `clear_search`, `remove_filter` —
  all handled by `KaguyaWeb.ProfileLive.Library`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu, only: [menu: 1, menu_item: 1]

  alias KaguyaWeb.UI.FilterControl
  alias KaguyaWeb.UI.Input

  @rating_options [
    {5.0, "5"},
    {4.5, "4½"},
    {4.0, "4"},
    {3.5, "3½"},
    {3.0, "3"},
    {2.5, "2½"},
    {2.0, "2"},
    {1.5, "1½"},
    {1.0, "1"},
    {0.5, "½"}
  ]

  def rating_options, do: @rating_options

  attr :shelf, :any, required: true
  attr :filters, :map, required: true
  attr :tags, :list, required: true
  attr :ratings_dist, :list, required: true
  attr :profile, :map, required: true
  attr :fade_read, :boolean, required: true

  def control_bar(assigns) do
    show_fade_toggle =
      not assigns.profile.viewer.is_mine and assigns.profile.viewer.is_logged_in

    assigns = assign(assigns, :show_fade_toggle, show_fade_toggle)

    ~H"""
    <div class="border-border-divider flex h-11 items-center justify-between border-b py-1 max-lg:hidden lg:px-0">
      <div class="flex items-center gap-2">
        <.sort_popover id="library-sort-popover-desktop" shelf={@shelf} filters={@filters} />
        <.rating_popover filters={@filters} ratings_dist={@ratings_dist} />
        <.tag_popover filters={@filters} tags={@tags} />
        <.search_input value={@filters.search || ""} />
      </div>
      <div class="flex items-center gap-2">
        <button
          :if={@show_fade_toggle}
          type="button"
          data-fade-toggle
          aria-pressed={to_string(@fade_read)}
          aria-label={if @fade_read, do: "Show read VNs", else: "Fade read VNs"}
          title={if @fade_read, do: "Show read VNs", else: "Fade read VNs"}
          class="hover:text-foreground-primary text-foreground-secondary inline-flex size-8 items-center justify-center rounded-full"
        >
          <Lucide.eye_off :if={@fade_read} class="size-4" aria-hidden />
          <Lucide.eye :if={!@fade_read} class="size-4" aria-hidden />
        </button>
      </div>
    </div>
    """
  end

  attr :shelf, :any, required: true
  attr :filters, :map, required: true
  attr :id, :string, default: "library-sort-popover"

  def sort_popover(assigns) do
    is_read_shelf = match?({:status, :read}, assigns.shelf)

    options =
      if is_read_shelf do
        [
          {:my_rating_desc, "Highest rated", "my-highest-rated"},
          {:my_rating_asc, "Lowest rated", "my-lowest-rated"},
          {:date_finished_desc, "Recently read", "recently-read"}
        ]
      else
        [
          {:my_rating_desc, "Highest rated", "my-highest-rated"},
          {:my_rating_asc, "Lowest rated", "my-lowest-rated"},
          {:date_added_desc, "Recently added", "newest-added"}
        ]
      end

    active = Enum.find(options, fn {atom, _, _} -> atom == assigns.filters.sort end)
    label = active && elem(active, 1)
    ascending? = match?("my_rating_asc", to_string(assigns.filters.sort))

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:active, assigns.filters.sort)
      |> assign(:label, label)
      |> assign(:ascending?, ascending?)

    ~H"""
    <.menu
      id={@id}
      align="start"
      side_offset={4}
      class={FilterControl.trigger_class(not is_nil(@active), :quiet)}
    >
      <:trigger aria-label="Sort library">
        <Lucide.arrow_down_narrow_wide :if={@ascending?} class="size-4" aria-hidden />
        <Lucide.arrow_down_wide_narrow :if={!@ascending?} class="size-4" aria-hidden />
        <span class="max-lg:max-w-[100px] max-lg:truncate">{@label || "Sort"}</span>
      </:trigger>
      <div class={[FilterControl.panel_class(), "min-w-[180px]"]}>
        <.menu_item
          :for={{atom, label, kebab} <- @options}
          event="set_sort"
          value={%{value: kebab}}
          class={FilterControl.option_class(atom == @active)}
          aria-pressed={to_string(atom == @active)}
        >
          {label}
        </.menu_item>
      </div>
    </.menu>
    """
  end

  attr :filters, :map, required: true
  attr :ratings_dist, :list, required: true

  def rating_popover(assigns) do
    active = assigns.filters.rating

    total =
      case assigns.ratings_dist do
        list when is_list(list) -> Enum.sum(list)
        _ -> 0
      end

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(:total, total)
      |> assign(:options, @rating_options)

    ~H"""
    <.menu
      id="library-rating-popover"
      align="start"
      side_offset={4}
      class={FilterControl.trigger_class(not is_nil(@active), :quiet)}
    >
      <:trigger aria-label="Filter by rating">
        <.rating_stars :if={@active} value={@active} active />
        <Lucide.star
          :if={is_nil(@active)}
          class="text-foreground-secondary size-4"
          aria-hidden
        />
        <span>Rating</span>
      </:trigger>
      <div class={[FilterControl.panel_class(), "min-w-[160px]"]}>
        <.menu_item
          event="clear_rating"
          class={FilterControl.option_class(is_nil(@active))}
          aria-pressed={to_string(is_nil(@active))}
        >
          <span>All ratings</span>
          <span :if={@total > 0} class="text-foreground-tertiary text-xs tabular-nums">{@total}</span>
        </.menu_item>
        <.menu_item
          :for={{value, label} <- @options}
          event="set_rating"
          value={%{value: rating_value(value)}}
          class={FilterControl.option_class(@active == value)}
          aria-pressed={to_string(@active == value)}
        >
          <.rating_stars value={value} active={@active == value} label={label} />
          <% bucket = rating_bucket(value, @ratings_dist) %>
          <span
            :if={bucket > 0}
            class={[
              "text-xs tabular-nums",
              @active == value && "text-foreground-secondary",
              @active != value && "text-foreground-tertiary"
            ]}
          >
            {bucket}
          </span>
        </.menu_item>
      </div>
    </.menu>
    """
  end

  attr :filters, :map, required: true
  attr :tags, :list, required: true

  def tag_popover(assigns) do
    assigns = assign(assigns, :active, assigns.filters.tag_slug)

    ~H"""
    <.menu
      id="library-tag-popover"
      align="start"
      side_offset={4}
      class={FilterControl.trigger_class(not is_nil(@active), :quiet)}
    >
      <:trigger aria-label="Filter by tag">
        <Lucide.tag class={["size-4", @active && "fill-current"]} aria-hidden />
        <span>Tags</span>
      </:trigger>
      <div class={[FilterControl.panel_class(), "w-[220px]"]}>
        <div class="max-h-[280px] overflow-y-auto py-1">
          <.menu_item
            :if={@active}
            event="clear_tag"
            class={FilterControl.option_class()}
          >
            Clear filter
          </.menu_item>
          <.menu_item
            :for={tag <- @tags}
            event="set_tag"
            value={%{value: tag.tag_slug}}
            class={FilterControl.option_class(@active == tag.tag_slug)}
            aria-pressed={to_string(@active == tag.tag_slug)}
          >
            <span class="truncate">{tag.tag_name}</span>
            <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
              {tag.count}
            </span>
          </.menu_item>
          <p :if={@tags == []} class="text-foreground-tertiary px-3 py-4 text-center text-sm">
            No tags
          </p>
        </div>
      </div>
    </.menu>
    """
  end

  attr :value, :string, required: true
  attr :id, :string, default: "library-search-desktop"
  attr :class, :any, default: nil
  attr :autofocus, :boolean, default: false

  def search_input(assigns) do
    assigns = assign(assigns, :form, to_form(%{"value" => assigns.value}))

    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-change="search"
      phx-submit="search"
      class={["relative flex h-9 min-w-0 flex-1 items-center", @class]}
    >
      <.search_icon
        class="text-foreground-primary/50 pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
        aria-hidden
      />
      <Input.input
        type="search"
        field={@form[:value]}
        id={@id <> "-input"}
        aria-label="Search library"
        autofocus={@autofocus}
        placeholder="Search library..."
        phx-debounce="250"
        class="px-8 [&::-webkit-search-cancel-button]:appearance-none"
      />
      <button
        :if={@value != ""}
        type="button"
        phx-click="clear_search"
        class="hover:text-foreground-primary text-foreground-secondary absolute top-1/2 right-0.5 flex size-8 -translate-y-1/2 items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2"
        aria-label="Clear search"
      >
        <Lucide.x class="size-3.5" aria-hidden />
      </button>
    </.form>
    """
  end

  attr :filters, :map, required: true
  attr :applied_producer, :any, required: true

  def active_filters(assigns) do
    items = active_filter_chips(assigns.filters, assigns.applied_producer)
    assigns = assign(assigns, :items, items)

    ~H"""
    <div :if={@items != []} class="flex flex-wrap items-center gap-1.5 px-4 pt-3 lg:px-0 lg:pt-2">
      <KaguyaWeb.SharedComponents.FilterChip.filter_chip
        :for={{key, label} <- @items}
        label={label}
        aria-label={"Remove #{label} filter"}
        phx-click="remove_filter"
        phx-value-key={key}
        icon_x
        title="Remove filter"
      />
    </div>
    """
  end

  attr :value, :float, required: true
  attr :active, :boolean, default: false
  attr :label, :string, default: nil

  def rating_stars(assigns) do
    full_count = trunc(assigns.value)
    half? = assigns.value != full_count

    assigns =
      assigns
      |> assign(:full_stars, List.duplicate(:star, full_count))
      |> assign(:half?, half?)
      |> assign(:aria_label, assigns.label || rating_value(assigns.value))

    ~H"""
    <span class="flex items-center gap-px" aria-label={@aria_label}>
      <Lucide.star
        :for={_ <- @full_stars}
        class={[
          "size-[11px] fill-current",
          if(@active, do: "text-foreground-primary", else: "text-icons-star-muted")
        ]}
        aria-hidden
      />
      <span
        :if={@half?}
        class={[
          "ml-px text-[10px] leading-none font-medium",
          if(@active, do: "text-foreground-primary", else: "text-icons-star-muted")
        ]}
      >
        ½
      </span>
    </span>
    """
  end

  def rating_value(value) do
    if value == trunc(value),
      do: Integer.to_string(trunc(value)),
      else: :erlang.float_to_binary(value, decimals: 1)
  end

  # Map 0.5..5.0 step value to bucket index (0..9) used by library_ratings_dist.
  def rating_bucket(value, dist) when is_list(dist) do
    idx = round(value * 2) - 1
    if idx in 0..9, do: Enum.at(dist, idx, 0), else: 0
  end

  def rating_bucket(_, _), do: 0

  defp active_filter_chips(filters, applied_producer) do
    []
    |> maybe_chip(filters.tag_slug, "tag", &humanize_slug/1)
    |> maybe_chip(filters.producer_slug, "producer", fn _ ->
      applied_producer && applied_producer.name
    end)
    |> maybe_chip(filters.original_language, "language", &humanize_slug/1)
    |> maybe_chip(filters.read_year, "readYear", &"Read in #{&1}")
    |> maybe_chip(filters.release_year, "releaseYear", &"Released in #{&1}")
    |> maybe_chip(filters.length_category, "length", &humanize_slug/1)
    |> maybe_chip(filters.age_rating, "ageRating", &age_label/1)
    |> Enum.reverse()
  end

  defp maybe_chip(acc, nil, _, _), do: acc
  defp maybe_chip(acc, "", _, _), do: acc

  defp maybe_chip(acc, value, key, formatter) do
    case formatter.(value) do
      nil -> acc
      label -> [{key, label} | acc]
    end
  end

  defp humanize_slug(value) when is_binary(value) do
    value |> String.split(["-", "_"]) |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_slug(value), do: to_string(value)

  defp age_label("unknown"), do: "Unknown Age Rating"
  defp age_label("all_ages"), do: "All Ages"
  defp age_label(value), do: value
end
