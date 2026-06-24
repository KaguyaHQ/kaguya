defmodule KaguyaWeb.BrowseLive.MobileControls do
  @moduledoc false

  use KaguyaWeb, :html

  alias Phoenix.LiveView.JS
  alias KaguyaWeb.BrowseLive.TagSnapshot
  alias KaguyaWeb.UI.Checkbox

  attr :payload, :map, required: true
  attr :mode_options, :list, required: true
  attr :sort_options, :list, required: true
  attr :sort_label, :string, required: true
  attr :filter_count, :integer, required: true

  def vn_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-4 sm:hidden">
      <button
        type="button"
        phx-click={JS.show(to: "#browse-mode-drawer")}
        class="bg-button-background-neutral-inverse-default text-button-text-on-neutral-inverse inline-flex h-9 items-center gap-2 rounded-[8px] px-3 text-sm font-semibold"
        aria-haspopup="dialog"
        aria-controls="browse-mode-drawer"
      >
        <Lucide.gamepad_2 class="size-4" /> VNs
      </button>

      <button
        type="button"
        phx-click={JS.show(to: "#browse-sort-drawer")}
        class="bg-button-background-neutral-default text-foreground-primary inline-flex h-9 min-w-0 items-center gap-1.5 rounded-[8px] px-3 text-sm font-medium"
        aria-haspopup="dialog"
        aria-controls="browse-sort-drawer"
      >
        <span class="truncate">{@sort_label}</span>
        <Lucide.chevron_down class="text-foreground-tertiary size-3.5" />
      </button>

      <button
        type="button"
        phx-click={JS.show(to: "#browse-filter-panel")}
        class="bg-button-background-neutral-default text-foreground-primary ml-auto inline-flex h-9 items-center gap-2 rounded-[8px] px-3 text-sm font-medium"
        aria-haspopup="dialog"
        aria-controls="browse-filter-panel"
      >
        <Lucide.sliders_vertical class="size-4" />
        <span>Filters</span>
        <span
          :if={@filter_count > 0}
          class="bg-button-background-neutral-inverse-default text-button-text-on-neutral-inverse -mr-1 flex min-w-5 justify-center rounded-full px-1.5 text-xs font-semibold"
        >
          {@filter_count}
        </span>
      </button>

      <.mode_drawer options={@mode_options} />
      <.sort_drawer options={@sort_options} />
      <.filter_panel payload={@payload} />
    </div>
    """
  end

  attr :options, :list, required: true

  defp mode_drawer(assigns) do
    ~H"""
    <div
      id="browse-mode-drawer"
      style="display: none"
      class="fixed inset-0 z-125 sm:hidden"
      role="dialog"
      aria-modal="true"
      aria-labelledby="browse-mode-title"
    >
      <button
        type="button"
        phx-click={JS.hide(to: "#browse-mode-drawer")}
        class="absolute inset-0 cursor-default bg-black/60 backdrop-blur-[2px]"
        aria-label="Close browse type"
      />
      <div class="bg-surface-elevated text-foreground-primary absolute inset-x-0 bottom-0 rounded-t-[10px] px-4 pt-3 pb-6 shadow-[0_-8px_10px_rgba(0,0,0,0.4)]">
        <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-white/20" />
        <h2 id="browse-mode-title" class="sr-only">Browse type</h2>
        <div class="flex flex-col gap-1">
          <.link
            :for={option <- @options}
            patch={option.href}
            rel="nofollow"
            class={drawer_option_class(option.selected?)}
          >
            <.mode_icon icon={option.icon} class="size-4" /> {option.label}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :options, :list, required: true

  defp sort_drawer(assigns) do
    ~H"""
    <div
      id="browse-sort-drawer"
      style="display: none"
      class="fixed inset-0 z-125 sm:hidden"
      role="dialog"
      aria-modal="true"
      aria-labelledby="browse-sort-title"
    >
      <button
        type="button"
        phx-click={JS.hide(to: "#browse-sort-drawer")}
        class="absolute inset-0 cursor-default bg-black/60 backdrop-blur-[2px]"
        aria-label="Close sort"
      />
      <div class="bg-surface-elevated text-foreground-primary absolute inset-x-0 bottom-0 rounded-t-[10px] px-4 pt-3 pb-6 shadow-[0_-8px_10px_rgba(0,0,0,0.4)]">
        <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-white/20" />
        <h2 id="browse-sort-title" class="sr-only">Sort</h2>
        <div class="flex flex-col gap-1">
          <.link
            :for={option <- @options}
            patch={option.href}
            rel="nofollow"
            class={drawer_option_class(option.selected?)}
          >
            <span>{option.label}</span>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :payload, :map, required: true

  defp filter_panel(assigns) do
    ~H"""
    <div
      id="browse-filter-panel"
      style="display: none"
      class="bg-surface-base text-foreground-primary fixed inset-0 z-130 sm:hidden"
      role="dialog"
      aria-modal="true"
      aria-labelledby="browse-filter-title"
    >
      <form
        id="browse-mobile-filter-form"
        action="/browse"
        method="get"
        phx-hook="LvNavGetForm"
        onsubmit={compact_get_form_submit()}
        class="flex h-dvh flex-col"
      >
        <input
          :if={@payload.sort_param not in [nil, ""]}
          type="hidden"
          name="sort"
          value={@payload.sort_param}
        />

        <header class="border-border-divider flex h-[60px] shrink-0 items-center justify-between border-b px-5">
          <h2 id="browse-filter-title" class="text-lg font-semibold">Filters</h2>
          <div class="flex items-center gap-4">
            <.link
              :if={@payload.filters_active?}
              patch="/browse"
              rel="nofollow"
              class="hover:text-foreground-primary text-foreground-secondary text-sm transition-colors"
            >
              Clear all
            </.link>
            <button type="submit" class="text-foreground-primary text-sm font-semibold">
              Done
            </button>
          </div>
        </header>

        <div class="flex-1 overflow-y-auto overscroll-contain pb-8">
          <div class="flex flex-col">
            <.filter_section title="Tags">
              <.tag_picker
                include_name="tags"
                exclude_name="excludeTags"
                include_values={@payload.filters[:include_tags]}
                exclude_values={@payload.filters[:exclude_tags]}
              />
            </.filter_section>

            <.filter_section title="Available Languages">
              <.checkbox_list_control
                name="languages"
                label="Available Languages"
                values={@payload.filters[:available_languages]}
                options={language_options()}
                initial_count={6}
              />
            </.filter_section>

            <.range_control
              label="Avg Rating"
              min_name="minRating"
              max_name="maxRating"
              min_value={@payload.filters[:average_rating_gte]}
              max_value={@payload.filters[:average_rating_lte]}
              min_range={1.0}
              max_range={5.0}
              step={0.1}
              min_placeholder="1.0"
              max_placeholder="5.0"
            />

            <.filter_section title="Length">
              <.radio_list_control
                name="length"
                value={@payload.filters[:length_category] || ""}
                options={length_options()}
              />
            </.filter_section>

            <.range_control
              label="Release Year"
              min_name="fromYear"
              max_name="toYear"
              min_value={@payload.filters[:released_after_year]}
              max_value={@payload.filters[:released_before_year]}
              min_range={1980}
              max_range={2026}
              step={1}
              stops={vn_year_stops()}
              min_placeholder="1980"
              max_placeholder="2026"
            />

            <.filter_section title="Platforms">
              <.checkbox_list_control
                name="platforms"
                label="Platforms"
                values={@payload.filters[:available_platforms]}
                options={platform_options()}
                initial_count={5}
              />
            </.filter_section>

            <.range_control
              label="Votes"
              min_name="minRatings"
              max_name="maxRatings"
              min_value={@payload.filters[:ratings_count_gte]}
              max_value={@payload.filters[:ratings_count_lte]}
              min_range={0}
              max_range={5000}
              step={1}
              stops={total_ratings_stops()}
              min_placeholder="0"
              max_placeholder="1000"
            />

            <.filter_section title="Original Language">
              <.checkbox_list_control
                name="origLang"
                label="Original Language"
                values={@payload.filters[:original_languages]}
                options={original_language_options()}
                initial_count={6}
              />
            </.filter_section>

            <.filter_section title="Engine">
              <.checkbox_list_control
                name="engines"
                label="Engine"
                values={@payload.filters[:engines]}
                options={engine_options()}
                initial_count={8}
              />
            </.filter_section>

            <.filter_section title="Store">
              <.checkbox_list_control
                name="stores"
                label="Store"
                values={@payload.filters[:available_on_stores]}
                options={store_options()}
                initial_count={8}
              />
            </.filter_section>

            <.filter_section title="Free on">
              <.checkbox_list_control
                name="freeStores"
                label="Free on"
                values={@payload.filters[:free_on_stores]}
                options={free_store_options()}
                initial_count={2}
              />
            </.filter_section>

            <.filter_section title="AVN">
              <.radio_list_control
                name="isAvn"
                value={bool_value(@payload.filters[:is_avn])}
                options={[{"Any", "", nil}, {"Only AVNs", "true", nil}, {"Hide AVNs", "false", nil}]}
              />
            </.filter_section>
          </div>
        </div>
      </form>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp filter_section(assigns) do
    ~H"""
    <section class="border-b border-white/6 p-5">
      <h3 class="text-foreground-primary text-sm font-semibold">{@title}</h3>
      <div class="mt-3 flex flex-col gap-2">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :include_name, :string, required: true
  attr :exclude_name, :string, required: true
  attr :include_values, :list, default: []
  attr :exclude_values, :list, default: []

  defp tag_picker(assigns) do
    include_values = assigns.include_values |> List.wrap() |> Enum.map(&to_string/1)
    exclude_values = assigns.exclude_values |> List.wrap() |> Enum.map(&to_string/1)
    selected_slugs = MapSet.new(include_values ++ exclude_values)

    initial_limit = 18
    tags = TagSnapshot.list()
    all_tags = TagSnapshot.list(include_sexual: true)
    included_tags = Enum.filter(all_tags, &(Map.get(&1, "slug") in include_values))
    excluded_tags = Enum.filter(all_tags, &(Map.get(&1, "slug") in exclude_values))

    suggestion_tags = Enum.reject(tags, &(Map.get(&1, "slug") in selected_slugs))

    assigns =
      assigns
      |> assign(:initial_limit, initial_limit)
      |> assign(:tag_data_url, TagSnapshot.asset_path())
      |> assign(:include_value, Enum.join(include_values, ","))
      |> assign(:exclude_value, Enum.join(exclude_values, ","))
      |> assign(:include_values, include_values)
      |> assign(:exclude_values, exclude_values)
      |> assign(:included_tags, included_tags)
      |> assign(:excluded_tags, excluded_tags)
      |> assign(:suggestion_tags, Enum.take(suggestion_tags, initial_limit))

    ~H"""
    <div
      id="browse-mobile-tag-picker"
      phx-hook="BrowseTagPicker"
      data-initial-limit={@initial_limit}
      data-search-limit="80"
      data-tag-picker-data-url={@tag_data_url}
      class="flex min-h-0 flex-col"
    >
      <input type="hidden" name={@include_name} value={@include_value} data-tag-picker-include />
      <input type="hidden" name={@exclude_name} value={@exclude_value} data-tag-picker-exclude />

      <label class="relative block">
        <.search_icon class="text-foreground-tertiary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2" />
        <input
          type="search"
          placeholder="Search tags..."
          autocomplete="off"
          class="placeholder:text-foreground-primary/40 text-foreground-primary h-10 w-full rounded-[8px] border border-white/8 bg-white/4 pr-3 pl-9 text-sm outline-none focus:border-white/16 focus:bg-white/6"
          data-tag-picker-search
        />
      </label>

      <div
        class="mt-2 max-h-[360px] overflow-y-auto pr-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        data-tag-picker-list
      >
        <div
          class="text-foreground-primary/50 pt-2 pb-1 text-[11px] font-semibold tracking-wider uppercase"
          data-tag-picker-label
        >
          Popular
        </div>
        <.tag_row
          :for={tag <- @included_tags ++ @excluded_tags ++ @suggestion_tags}
          tag={tag}
          included?={Map.get(tag, "slug") in @include_values}
          excluded?={Map.get(tag, "slug") in @exclude_values}
        />
        <p
          hidden
          data-tag-picker-empty
          class="text-foreground-secondary px-3 py-5 text-center text-sm"
        >
          No tags found
        </p>
      </div>
    </div>
    """
  end

  attr :tag, :map, required: true
  attr :included?, :boolean, required: true
  attr :excluded?, :boolean, required: true

  defp tag_row(assigns) do
    ~H"""
    <div
      class="flex cursor-pointer items-center justify-between rounded px-0 py-2.5 transition hover:bg-white/2 data-[excluded=true]:bg-red-900/20 data-[selected=true]:bg-white/2"
      data-tag-picker-row
      data-tag-slug={@tag["slug"]}
      data-tag-name={String.downcase(@tag["name"] || "")}
      data-selected={to_string(@included? or @excluded?)}
      data-included={to_string(@included?)}
      data-excluded={to_string(@excluded?)}
    >
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-2 text-left"
        data-tag-picker-include-button
      >
        <span
          class="border-foreground-secondary data-[checked=true]:bg-foreground-secondary data-[checked=true]:border-foreground-secondary text-surface-elevated flex size-3.5 shrink-0 items-center justify-center rounded-[3px] border-2"
          data-tag-picker-checkbox
          data-checked={to_string(@included?)}
        />
        <span class="min-w-0 truncate text-sm leading-[17px]">{@tag["name"]}</span>
        <span class="text-foreground-primary/40 shrink-0 text-xs leading-[15px]">
          {short_count(@tag["vnsCount"] || 0)}
        </span>
      </button>

      <button
        type="button"
        class="data-[excluded=true]:text-semantic-error hover:text-semantic-error text-foreground-quaternary -my-2 -mr-2 flex size-8 shrink-0 items-center justify-center transition"
        data-tag-picker-exclude-button
        data-excluded={to_string(@excluded?)}
        aria-label={"Exclude #{@tag["name"]}"}
      >
        <Lucide.circle_minus class="size-4" />
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :min_name, :string, required: true
  attr :max_name, :string, required: true
  attr :min_value, :any, default: nil
  attr :max_value, :any, default: nil
  attr :min_range, :any, required: true
  attr :max_range, :any, required: true
  attr :step, :any, default: 1
  attr :stops, :list, default: []
  attr :min_placeholder, :string, default: nil
  attr :max_placeholder, :string, default: nil

  defp range_control(assigns) do
    assigns =
      assigns
      |> assign(:active?, not is_nil(assigns.min_value) or not is_nil(assigns.max_value))
      |> assign(:min_input_value, range_input_value(assigns.min_value))
      |> assign(:max_input_value, range_input_value(assigns.max_value))
      |> assign(:slider_min, slider_min(assigns.stops, assigns.min_range))
      |> assign(:slider_max, slider_max(assigns.stops, assigns.max_range))
      |> assign(:slider_step, slider_step(assigns.stops, assigns.step))
      |> assign(
        :min_slider_value,
        slider_value(assigns.min_value, assigns.min_range, assigns.stops)
      )
      |> assign(
        :max_slider_value,
        slider_value(assigns.max_value, assigns.max_range, assigns.stops)
      )
      |> assign(:stops_value, Enum.join(assigns.stops, ","))

    ~H"""
    <section
      id={"browse-range-#{@min_name}"}
      phx-hook="BrowseRangeControl"
      data-browse-range-control
      data-min-range={@min_range}
      data-max-range={@max_range}
      data-step={@step}
      data-stops={@stops_value}
      class="border-b border-white/6"
    >
      <div class="flex items-center gap-2 px-6 pt-5 pb-2">
        <span class="text-foreground-primary text-sm font-medium">{@label}</span>
        <div :if={@active?} class="bg-button-background-brand-default size-1.5 rounded-full" />
      </div>

      <div class="px-6 pt-1 pb-4">
        <div data-range-slider class="relative h-11 cursor-pointer select-none">
          <div class="absolute top-1/2 h-[6px] w-full -translate-y-1/2 cursor-pointer rounded-full bg-white/8" />
          <div
            data-range-fill
            class="bg-button-background-brand-default absolute top-1/2 h-[6px] -translate-y-1/2 rounded-full"
          />
          <input
            type="range"
            min={@slider_min}
            max={@slider_max}
            step={@slider_step}
            value={@min_slider_value}
            aria-label={"Minimum #{@label}"}
            class="browse-range-input"
            data-range-min-slider
          />
          <input
            type="range"
            min={@slider_min}
            max={@slider_max}
            step={@slider_step}
            value={@max_slider_value}
            aria-label={"Maximum #{@label}"}
            class="browse-range-input"
            data-range-max-slider
          />
        </div>

        <div class="mt-3 flex items-center gap-3">
          <input
            type="number"
            name={@min_name}
            value={@min_input_value}
            placeholder={@min_placeholder}
            inputmode="decimal"
            class="placeholder:text-foreground-tertiary text-foreground-primary h-12 min-w-0 flex-1 [appearance:textfield] rounded-[10px] border border-white/10 bg-white/5 px-3 text-base tabular-nums outline-none focus:border-white/16 focus:bg-white/7 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
            data-range-min-input
          />
          <span class="text-foreground-secondary shrink-0 text-xs">-</span>
          <input
            type="number"
            name={@max_name}
            value={@max_input_value}
            placeholder={@max_placeholder}
            inputmode="decimal"
            class="placeholder:text-foreground-tertiary text-foreground-primary h-12 min-w-0 flex-1 [appearance:textfield] rounded-[10px] border border-white/10 bg-white/5 px-3 text-base tabular-nums outline-none focus:border-white/16 focus:bg-white/7 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
            data-range-max-input
          />
        </div>
      </div>
    </section>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :values, :list, default: []
  attr :options, :list, required: true
  attr :initial_count, :integer, default: 6

  defp checkbox_list_control(assigns) do
    assigns =
      assign(
        assigns,
        :selected_values,
        assigns.values |> List.wrap() |> Enum.map(&to_string/1)
      )

    selected =
      Enum.filter(assigns.options, fn {_label, value} -> value in assigns.selected_values end)

    unselected =
      Enum.reject(assigns.options, fn {_label, value} -> value in assigns.selected_values end)

    visible = Enum.take(unselected, assigns.initial_count)
    hidden = Enum.drop(unselected, assigns.initial_count)

    assigns =
      assigns
      |> assign(:selected_options, selected)
      |> assign(:visible_options, visible)
      |> assign(:hidden_options, hidden)

    ~H"""
    <div class="space-y-2" data-multi-select-control>
      <input
        type="hidden"
        name={@name}
        value={Enum.join(@selected_values, ",")}
        data-multi-select-input
      />
      <div class="flex flex-col gap-0.5">
        <.checkbox_option
          :for={{option_label, option_value} <- @selected_options ++ @visible_options}
          name={@name}
          label={option_label}
          value={option_value}
          checked={option_value in @selected_values}
        />

        <details :if={@hidden_options != []} class="group">
          <summary class="hover:text-foreground-primary text-foreground-secondary cursor-pointer list-none pt-2 text-sm transition-colors">
            Show all {length(@options)}
          </summary>
          <div class="mt-1 flex flex-col gap-0.5">
            <.checkbox_option
              :for={{option_label, option_value} <- @hidden_options}
              name={@name}
              label={option_label}
              value={option_value}
              checked={option_value in @selected_values}
            />
          </div>
        </details>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true

  defp checkbox_option(assigns) do
    ~H"""
    <label class={checkbox_row_class(@checked)}>
      <Checkbox.checkbox
        value={@value}
        checked={@checked}
        include_hidden={false}
        class="border-foreground-secondary text-button-background-brand-default size-3.5 rounded-[3px] border-2 bg-transparent"
        data-multi-select-option
        data-name={@name}
      />
      <span class="truncate text-sm leading-[17px]">{@label}</span>
    </label>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp radio_list_control(assigns) do
    ~H"""
    <div class="flex flex-col gap-0.5">
      <label
        :for={{option_label, option_value, option_description} <- @options}
        class={radio_row_class(option_value == @value)}
      >
        <input
          type="radio"
          name={@name}
          value={option_value}
          checked={option_value == @value}
          class="sr-only"
        />
        <span class="flex min-w-0 flex-col">
          <span class="truncate text-sm leading-[17px]">{option_label}</span>
          <span :if={option_description} class="text-foreground-secondary text-xs">
            {option_description}
          </span>
        </span>
        <Lucide.check
          :if={option_value == @value}
          class="text-button-background-brand-default ml-auto size-4 shrink-0"
          aria-hidden
        />
      </label>
    </div>
    """
  end

  defp drawer_option_class(true),
    do:
      "flex h-11 items-center gap-2 rounded-[8px] bg-button-background-neutral-inverse-default px-3 text-sm font-semibold text-button-text-on-neutral-inverse"

  defp drawer_option_class(false),
    do:
      "flex h-11 items-center gap-2 rounded-[8px] px-3 text-sm font-medium text-foreground-primary transition hover:bg-white/[6%]"

  defp range_input_value(nil), do: ""
  defp range_input_value(value), do: to_string(value)

  defp slider_min(stops, _min_range) when stops != [], do: 0
  defp slider_min(_stops, min_range), do: min_range

  defp slider_max(stops, _max_range) when stops != [], do: length(stops) - 1
  defp slider_max(_stops, max_range), do: max_range

  defp slider_step(stops, _step) when stops != [], do: 1
  defp slider_step(_stops, step), do: step

  defp slider_value(nil, default, stops), do: slider_value(default, default, stops)

  defp slider_value(value, _default, stops) when stops != [] do
    number = number_value(value)

    stops
    |> Enum.with_index()
    |> Enum.min_by(fn {stop, _index} -> abs(number_value(stop) - number) end)
    |> elem(1)
  end

  defp slider_value(value, _default, _stops), do: value

  defp number_value(value) when is_integer(value), do: value
  defp number_value(value) when is_float(value), do: value

  defp number_value(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp number_value(_), do: 0

  defp total_ratings_stops do
    [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      20,
      30,
      40,
      50,
      60,
      70,
      80,
      90,
      100,
      200,
      300,
      400,
      500,
      600,
      700,
      800,
      900,
      1000,
      2000,
      3000,
      4000,
      5000
    ]
  end

  defp vn_year_stops do
    [
      1980,
      1985,
      1990,
      1992,
      1994,
      1996,
      1998,
      2000,
      2002,
      2004,
      2006,
      2008,
      2010,
      2011,
      2012,
      2013,
      2014,
      2015,
      2016,
      2017,
      2018,
      2019,
      2020,
      2021,
      2022,
      2023,
      2024,
      2025,
      2026
    ]
  end

  defp checkbox_row_class(true),
    do: "flex cursor-pointer items-center gap-2 overflow-hidden rounded bg-white/[2%] px-0 py-2.5"

  defp checkbox_row_class(false),
    do:
      "flex cursor-pointer items-center gap-2 overflow-hidden rounded px-0 py-2.5 hover:bg-white/[2%]"

  defp radio_row_class(true),
    do:
      "flex w-full cursor-pointer items-center justify-between gap-3 rounded bg-white/[4%] px-0 py-2.5 text-left"

  defp radio_row_class(false),
    do:
      "flex w-full cursor-pointer items-center justify-between gap-3 rounded px-0 py-2.5 text-left hover:bg-white/[2%]"

  defp length_options do
    [
      {"Any", "", nil},
      {"Short", "short", "< 10 hours"},
      {"Medium", "medium", "10-30 hours"},
      {"Long", "long", "30-50 hours"},
      {"Very Long", "very_long", "50+ hours"}
    ]
  end

  defp platform_options do
    [
      {"Windows", "win"},
      {"Android", "and"},
      {"Nintendo Switch", "swi"},
      {"macOS", "mac"},
      {"Linux", "lin"},
      {"PlayStation Vita", "psv"},
      {"iOS", "ios"},
      {"PlayStation Portable", "psp"},
      {"PlayStation 4", "ps4"},
      {"Web/Browser", "web"},
      {"PlayStation 3", "ps3"},
      {"PlayStation 2", "ps2"},
      {"PlayStation 5", "ps5"},
      {"Nintendo DS", "nds"},
      {"Xbox Series X/S", "xxs"},
      {"Xbox One", "xbo"},
      {"Xbox 360", "x36"},
      {"PlayStation 1", "ps1"},
      {"Switch 2", "sw2"},
      {"PC-98", "p98"},
      {"PC-88", "p88"},
      {"Sega Saturn", "sat"},
      {"Dreamcast", "drc"},
      {"DOS", "dos"},
      {"MSX", "msx"},
      {"Nintendo 3DS", "n3d"},
      {"Game Boy Advance", "gba"},
      {"Wii", "wii"},
      {"PC Engine", "pce"},
      {"FM Towns", "fmd"},
      {"Super Famicom", "sfc"},
      {"NES", "nes"},
      {"Game Boy Color", "gbc"},
      {"PC-FX", "pcf"},
      {"X68000", "x68"},
      {"FM-7", "fm7"},
      {"X1 Super", "x1s"},
      {"Sega CD", "scd"},
      {"Sega Genesis", "smd"},
      {"Wii U", "wiu"},
      {"FM-8", "fm8"},
      {"3DO", "tdo"},
      {"Amiga", "amg"},
      {"Mobile (legacy)", "mob"},
      {"Blu-ray Player", "bdp"},
      {"VN.com", "vnd"},
      {"DVD Player", "dvd"},
      {"Other", "oth"}
    ]
  end

  defp language_options do
    [
      {"日本語", "ja"},
      {"English", "en"},
      {"简体中文", "zh-Hans"},
      {"Русский", "ru"},
      {"Español", "es"},
      {"한국어", "ko"},
      {"繁體中文", "zh-Hant"},
      {"Português (BR)", "pt-br"},
      {"Tiếng Việt", "vi"},
      {"Italiano", "it"},
      {"Français", "fr"},
      {"Bahasa Indonesia", "id"},
      {"Deutsch", "de"},
      {"Polski", "pl"},
      {"Türkçe", "tr"},
      {"Українська", "uk"},
      {"العربية", "ar"},
      {"Magyar", "hu"},
      {"ไทย", "th"},
      {"Català", "ca"},
      {"Čeština", "cs"},
      {"Português (PT)", "pt-pt"},
      {"Suomi", "fi"},
      {"Nederlands", "nl"},
      {"Latviešu", "lv"},
      {"Svenska", "sv"},
      {"Bahasa Melayu", "ms"},
      {"Norsk", "no"},
      {"Български", "bg"},
      {"Euskara", "eu"},
      {"Ελληνικά", "el"},
      {"עברית", "he"},
      {"Dansk", "da"},
      {"فارسی", "fa"},
      {"Gaeilge", "ga"},
      {"Slovenčina", "sk"},
      {"Română", "ro"},
      {"हिन्दी", "hi"},
      {"தமிழ்", "ta"},
      {"Eesti", "et"},
      {"Esperanto", "eo"},
      {"Беларуская", "be"},
      {"Slovenščina", "sl"},
      {"Gàidhlig", "gd"},
      {"Galego", "gl"},
      {"Lietuvių", "lt"},
      {"Македонски", "mk"},
      {"Bosanski", "bs"},
      {"Latina", "la"},
      {"Hrvatski", "hr"},
      {"ᏣᎳᎩ", "ck"},
      {"Қазақша", "kk"},
      {"ᐃᓄᒃᑎᑐᑦ", "iu"},
      {"Српски", "sr"},
      {"اردو", "ur"}
    ]
  end

  defp original_language_options do
    [
      {"日本語", "ja"},
      {"English", "en"},
      {"Русский", "ru"},
      {"简体中文", "zh-Hans"},
      {"한국어", "ko"},
      {"繁體中文", "zh-Hant"},
      {"Español", "es"},
      {"Français", "fr"},
      {"Deutsch", "de"},
      {"Português (BR)", "pt-br"},
      {"Bahasa Indonesia", "id"},
      {"Italiano", "it"},
      {"Українська", "uk"},
      {"Polski", "pl"},
      {"ไทย", "th"},
      {"Tiếng Việt", "vi"},
      {"Türkçe", "tr"},
      {"Čeština", "cs"},
      {"العربية", "ar"},
      {"Magyar", "hu"},
      {"Català", "ca"},
      {"Suomi", "fi"},
      {"Nederlands", "nl"},
      {"தமிழ்", "ta"},
      {"Norsk", "no"},
      {"Slovenčina", "sk"},
      {"Română", "ro"},
      {"Svenska", "sv"},
      {"Ελληνικά", "el"},
      {"Bahasa Melayu", "ms"},
      {"Қазақша", "kk"},
      {"Српски", "sr"}
    ]
  end

  defp engine_options do
    [
      {"Ren'Py", "Ren'Py"},
      {"KiriKiri", "KiriKiri"},
      {"TyranoScript", "TyranoScript"},
      {"Unity", "Unity"},
      {"LiveMaker", "LiveMaker"},
      {"NScripter", "NScripter"},
      {"RPG Maker", "RPG Maker"},
      {"YU-RIS", "YU-RIS"},
      {"Flash Player", "Flash Player"},
      {"Godot", "Godot"},
      {"Artemis Engine", "Artemis Engine"},
      {"Dorian Engine", "Dorian Engine"},
      {"Macromedia Director", "Macromedia Director"},
      {"Wolf RPG Editor", "Wolf RPG Editor"},
      {"Shiina Rio", "Shiina Rio"},
      {"Cocos2d", "Cocos2d"},
      {"Visual Novel Maker", "Visual Novel Maker"},
      {"Majiro", "Majiro"},
      {"RealLive", "RealLive"},
      {"System-NNN", "System-NNN"},
      {"BGI/Ethornell", "BGI/Ethornell"},
      {"GameMaker", "GameMaker"},
      {"Light.vn", "Light.vn"},
      {"Comic Maker", "Comic Maker"},
      {"Yuuki! Novel", "Yuuki! Novel"},
      {"Twine", "Twine"},
      {"SiglusEngine", "SiglusEngine"},
      {"CatSystem2", "CatSystem2"},
      {"AVG32", "AVG32"},
      {"Bruns", "Bruns"},
      {"Comic Maker 2", "Comic Maker 2"},
      {"QLIE", "QLIE"},
      {"NeXAS", "NeXAS"},
      {"EntisGLS", "EntisGLS"},
      {"codeX RScript", "codeX RScript"},
      {"ADV98V", "ADV98V"},
      {"KaGuYa", "KaGuYa"},
      {"SaiSys", "SaiSys"},
      {"Marble", "Marble"},
      {"ADV Player HD", "ADV Player HD"},
      {"Malie", "Malie"},
      {"AST", "AST"},
      {"AliceSoft System4.X", "AliceSoft System4.X"},
      {"Ikura GDL", "Ikura GDL"},
      {"AliceSoft System3.X", "AliceSoft System3.X"},
      {"Hot Soup Processor", "Hot Soup Processor"},
      {"Luca System", "Luca System"},
      {"MAGES. Engine", "MAGES. Engine"},
      {"ExHibit", "ExHibit"},
      {"Adobe AIR", "Adobe AIR"}
    ]
  end

  defp store_options do
    [
      {"Steam", "steam"},
      {"itch.io", "itch"},
      {"DLsite", "dlsite"},
      {"DLsite (EN)", "dlsiteen"},
      {"DMM", "dmm"},
      {"Getchu", "getchu"},
      {"DiGiket", "digiket"},
      {"Gyutto", "gyutto"},
      {"Play-Asia", "playasia"},
      {"Google Play", "googplay"},
      {"App Store", "appstore"},
      {"Patreon", "patreon"},
      {"Freem!", "freem"},
      {"Melonbooks", "melonjp"},
      {"BOOTH", "booth"},
      {"GOG", "gog"},
      {"MangaGamer", "mg"},
      {"JAST USA", "jastusa"},
      {"Denpasoft", "denpa"},
      {"Nutaku", "nutaku"},
      {"FAKKU", "fakku"},
      {"Kagura Games", "kagura"}
    ]
  end

  defp free_store_options do
    [
      {"itch.io", "itch"},
      {"Steam", "steam"}
    ]
  end

  defp compact_get_form_submit do
    """
    this.querySelectorAll('[data-multi-select-control]').forEach((group) => {
      const input = group.querySelector('[data-multi-select-input]');
      const values = Array.from(group.querySelectorAll('[data-multi-select-option]:checked')).map((field) => field.value);
      if (input) input.value = values.join(',');
    });
    this.querySelectorAll('input, select').forEach((field) => { field.disabled = field.value === '' });
    """
  end

  defp bool_value(true), do: "true"
  defp bool_value(false), do: "false"
  defp bool_value(_), do: ""

  defp short_count(count) when count >= 1_000_000, do: "#{Float.round(count / 1_000_000, 1)}m"
  defp short_count(count) when count >= 1_000, do: "#{Float.round(count / 1_000, 1)}k"
  defp short_count(count), do: to_string(count)

  attr :icon, :atom, required: true
  attr :class, :string, required: true

  defp mode_icon(%{icon: :gamepad} = assigns) do
    ~H"""
    <Lucide.gamepad_2 class={@class} aria-hidden />
    """
  end

  defp mode_icon(%{icon: :user} = assigns) do
    ~H"""
    <Lucide.user_round class={@class} aria-hidden />
    """
  end
end
