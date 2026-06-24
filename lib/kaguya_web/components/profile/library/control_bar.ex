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

  import KaguyaWeb.UI.Menu, only: [menu: 1]

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
      class="text-foreground-primary inline-flex h-[34px] cursor-pointer list-none items-center gap-1.5 rounded-full border border-white/7 bg-white/4 px-3.5 text-[13px] transition-colors duration-150 hover:border-white/12 hover:bg-white/7 max-lg:h-fit max-lg:gap-2 max-lg:px-[14px] max-lg:py-1.5 max-lg:leading-[21px]"
    >
      <:trigger>
        <Lucide.arrow_down_narrow_wide :if={@ascending?} class="size-4" aria-hidden />
        <Lucide.arrow_down_wide_narrow :if={!@ascending?} class="size-4" aria-hidden />
        <span :if={@label}>{@label}</span>
      </:trigger>
      <div class="bg-surface-elevated flex w-auto min-w-[180px] flex-col rounded-[12px] border-none p-1 shadow-lg">
        <button
          :for={{atom, label, kebab} <- @options}
          type="button"
          phx-click="set_sort"
          phx-value-value={kebab}
          value={kebab}
          class={[
            "w-full cursor-pointer rounded-lg px-3 py-2.5 text-left text-[13px]/4 font-normal whitespace-nowrap transition-colors sm:py-2 sm:text-xs",
            atom == @active &&
              "bg-button-background-neutral-inverse-default font-semibold text-[rgb(var(--button-text-on-neutral-inverse))]",
            atom != @active && "text-foreground-primary hover:bg-white/4"
          ]}
        >
          {label}
        </button>
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
      class="text-foreground-primary inline-flex h-[34px] cursor-pointer list-none items-center gap-1.5 rounded-full border border-white/7 bg-white/4 px-3.5 text-[13px] transition-colors duration-150 hover:border-white/12 hover:bg-white/7 max-lg:h-fit max-lg:gap-2 max-lg:px-[14px] max-lg:py-1.5 max-lg:leading-[21px]"
    >
      <:trigger>
        <.rating_stars :if={@active} value={@active} active />
        <Lucide.star
          :if={is_nil(@active)}
          class="text-foreground-secondary size-4"
          aria-hidden
        />
      </:trigger>
      <div class="bg-surface-elevated flex w-auto min-w-[160px] flex-col rounded-[12px] border-none p-1 shadow-lg">
        <button
          type="button"
          phx-click="clear_rating"
          class={[
            "flex h-9 w-full cursor-pointer items-center justify-between rounded-md px-3 text-sm",
            is_nil(@active) && "text-foreground-primary font-medium",
            not is_nil(@active) && "text-foreground-secondary hover:bg-white/4"
          ]}
        >
          <span>All ratings</span>
          <span :if={@total > 0} class="text-foreground-tertiary text-xs tabular-nums">{@total}</span>
        </button>
        <button
          :for={{value, label} <- @options}
          type="button"
          phx-click="set_rating"
          phx-value-value={rating_value(value)}
          value={rating_value(value)}
          class={[
            "flex h-9 w-full cursor-pointer items-center justify-between rounded-md px-3 text-sm",
            @active == value && "bg-white/6",
            @active != value && "hover:bg-white/4"
          ]}
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
        </button>
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
      class="text-foreground-primary inline-flex h-[34px] cursor-pointer list-none items-center gap-1.5 rounded-full border border-white/7 bg-white/4 px-3.5 text-[13px] transition-colors duration-150 hover:border-white/12 hover:bg-white/7 max-lg:h-fit max-lg:gap-2 max-lg:px-[14px] max-lg:py-1.5 max-lg:leading-[21px]"
    >
      <:trigger>
        <Lucide.tag class={["size-4", @active && "fill-current"]} aria-hidden />
      </:trigger>
      <div class="bg-surface-elevated flex w-[220px] flex-col rounded-[12px] border-none p-1 shadow-lg">
        <div class="max-h-[280px] overflow-y-auto py-1">
          <button
            :if={@active}
            type="button"
            phx-click="clear_tag"
            class="text-foreground-secondary flex h-8 w-full cursor-pointer items-center rounded-md px-3 text-sm hover:bg-white/4"
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
              "flex h-8 w-full cursor-pointer items-center justify-between rounded-md px-3 text-sm",
              @active == tag.tag_slug && "text-foreground-primary bg-white/6 font-medium",
              @active != tag.tag_slug && "text-foreground-secondary hover:bg-white/4"
            ]}
          >
            <span class="truncate">{tag.tag_name}</span>
            <span class="text-foreground-tertiary ml-2 shrink-0 text-xs tabular-nums">
              {tag.count}
            </span>
          </button>
          <p :if={@tags == []} class="text-foreground-tertiary px-3 py-4 text-center text-sm">
            No tags
          </p>
        </div>
      </div>
    </.menu>
    """
  end

  attr :value, :string, required: true

  def search_input(assigns) do
    ~H"""
    <form
      phx-change="search"
      phx-submit="search"
      class="relative flex h-[34px] min-w-0 flex-1 items-center"
    >
      <.search_icon
        class="text-foreground-primary/50 pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
        aria-hidden
      />
      <input
        type="search"
        name="value"
        placeholder="Search library..."
        value={@value}
        phx-debounce="250"
        class="border-border-divider no-search-clear placeholder:text-foreground-primary/40 text-foreground-primary size-full rounded-full border bg-transparent px-8 text-[13px] leading-[18px] focus:ring-0 focus:outline-hidden"
      />
      <button
        :if={@value != ""}
        type="button"
        phx-click="clear_search"
        class="hover:text-foreground-primary text-foreground-secondary absolute top-1/2 right-2.5 -translate-y-1/2 transition-colors"
        aria-label="Clear search"
      >
        <Lucide.x class="size-3.5" aria-hidden />
      </button>
    </form>
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
