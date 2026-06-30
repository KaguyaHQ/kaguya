defmodule KaguyaWeb.BrowseLive.IndexComponents do
  @moduledoc false

  use KaguyaWeb, :html

  alias Phoenix.LiveView.JS
  alias Kaguya.VisualNovels
  alias KaguyaWeb.BrowseLive.FilterOptions
  alias KaguyaWeb.BrowseLive.MobileControls
  alias KaguyaWeb.BrowseLive.TagSnapshot
  import KaguyaWeb.UI.Menu, only: [menu: 1]

  attr :payload, :map, required: true
  attr :params, :map, required: true

  def browse_page(assigns) do
    ~H"""
    <main class="lg:bg-surface-base text-foreground-primary min-h-screen pt-6 pb-20 sm:pt-8 lg:pt-16 dark:lg:bg-transparent">
      <div class="mx-auto flex w-full flex-col gap-4 sm:gap-6 md:max-lg:max-w-[768px] md:max-lg:px-6 lg:max-w-[1150px] lg:gap-12 lg:px-0">
        <%= if @payload.mode == :characters do %>
          <.characters payload={@payload} params={@params} />
        <% else %>
          <.vns payload={@payload} params={@params} />
        <% end %>
      </div>
    </main>
    """
  end

  attr :payload, :map, required: true
  attr :params, :map, required: true

  defp vns(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 sm:gap-6 lg:gap-8">
      <div class="hidden sm:block">
        <.desktop_vn_filter_controls payload={@payload} params={@params} />
      </div>

      <.mobile_vn_controls payload={@payload} params={@params} />

      <%= if @payload.filters_active? do %>
        <div class="empty:hidden sm:hidden">
          <.active_filter_pills filters={@payload.filters} params={@params} />
        </div>
        <.vn_results result={@payload.result} params={@params} />
      <% else %>
        <.explore_sections sections={@payload.sections} />
      <% end %>
    </div>
    """
  end

  attr :payload, :map, required: true
  attr :params, :map, required: true

  defp characters(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 sm:gap-6 lg:gap-8">
      <div class="flex flex-wrap items-center gap-2 px-4 sm:px-0">
        <.mode_chip id="browse-type-popover" mode={:characters} params={@params} />
        <.character_sort_controls payload={@payload} params={@params} />
      </div>

      <div class="text-foreground-primary scroll-mt-32 max-sm:-mt-[3px] sm:rounded-[12px]">
        <%= if @payload.result.items == [] do %>
          <div class="text-foreground-secondary flex min-h-[400px] flex-col items-center justify-center px-5">
            <p>No characters yet</p>
          </div>
        <% else %>
          <div class="grid grid-cols-3 gap-x-[11px] gap-y-5 px-4 pb-5 sm:grid-cols-4 sm:pb-10 lg:grid-cols-6 lg:gap-x-3 lg:gap-y-5 lg:px-0">
            <.character_card :for={character <- @payload.result.items} character={character} />
          </div>
        <% end %>

        <.pagination
          page={@payload.page}
          total_pages={@payload.result.pagination.total_pages}
          params={@params}
          base_path="/browse/characters"
        />
      </div>
    </div>
    """
  end

  attr :payload, :map, required: true
  attr :params, :map, required: true

  defp desktop_vn_filter_controls(assigns) do
    assigns =
      assigns
      |> assign(:sort_label, desktop_sort_label(assigns.payload))
      |> assign(:tags_count, tags_count(assigns.payload.filters))
      |> assign(:more_count, secondary_filter_count(assigns.payload.filters))
      |> assign(
        :platform_count,
        length(Map.get(assigns.payload.filters, :available_platforms, []))
      )
      |> assign(:more_open?, secondary_filter_count(assigns.payload.filters) > 0)

    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <.mode_chip id="browse-type-popover" mode={:vn} params={@params} />

      <.link_popover_chip label={@sort_label} icon={:sort} active={not is_nil(@payload.sort_param)}>
        <.menu_link
          :for={{label, value} <- [{"Default", ""} | @payload.sort_options]}
          href={query_path("/browse", @params, %{"sort" => value, "page" => nil})}
          selected?={(@payload.sort_param || "") == value}
        >
          {label}
        </.menu_link>
      </.link_popover_chip>

      <.form_popover_chip
        id="browse-tags-popover"
        variant={:tags}
        label="Tags"
        active={@tags_count > 0}
        count={@tags_count}
        clear_href={
          query_path("/browse", @params, %{"tags" => nil, "excludeTags" => nil, "page" => nil})
        }
      >
        <.hidden_params params={@params} except={["tags", "excludeTags", "page"]} />
        <.tag_picker
          include_name="tags"
          exclude_name="excludeTags"
          include_values={@payload.filters[:include_tags]}
          exclude_values={@payload.filters[:exclude_tags]}
          compact
        />
      </.form_popover_chip>

      <.range_popover_chip
        label="Year"
        params={@params}
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
        display={
          range_label(
            "Year",
            @payload.filters[:released_after_year],
            @payload.filters[:released_before_year],
            :year
          )
        }
      />

      <.range_popover_chip
        label="Rating"
        params={@params}
        min_name="minRating"
        max_name="maxRating"
        min_value={@payload.filters[:average_rating_gte]}
        max_value={@payload.filters[:average_rating_lte]}
        min_range={1.0}
        max_range={5.0}
        step={0.1}
        min_placeholder="1.0"
        max_placeholder="5.0"
        display={
          range_label(
            "Rating",
            @payload.filters[:average_rating_gte],
            @payload.filters[:average_rating_lte],
            :rating
          )
        }
      />

      <.link_popover_chip
        label="Length"
        value={single_chip_value(@payload.filters[:length_category], &length_label/1)}
        active={not is_nil(@payload.filters[:length_category])}
        clear_href={query_path("/browse", @params, %{"length" => nil, "page" => nil})}
      >
        <.menu_link
          :for={{label, value} <- length_options()}
          href={query_path("/browse", @params, %{"length" => value, "page" => nil})}
          selected?={(@payload.filters[:length_category] || "") == value}
          description={length_description(value)}
        >
          {label}
        </.menu_link>
      </.link_popover_chip>

      <.multi_popover_chip
        label="Platform"
        params={@params}
        param="platforms"
        values={Map.get(@payload.filters, :available_platforms, [])}
        options={platform_options()}
        count={@platform_count}
        initial_count={10}
      />

      <.range_popover_chip
        label="Popularity"
        params={@params}
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
        display={
          range_label(
            "Popularity",
            @payload.filters[:ratings_count_gte],
            @payload.filters[:ratings_count_lte],
            :votes
          )
        }
      />

      <.link_popover_chip
        label="AVN"
        value={
          single_chip_value(@payload.filters[:is_avn], fn
            true -> "Only AVNs"
            false -> "Hide AVNs"
            value -> to_string(value)
          end)
        }
        active={not is_nil(@payload.filters[:is_avn])}
        clear_href={query_path("/browse", @params, %{"isAvn" => nil, "page" => nil})}
      >
        <.menu_link
          :for={{label, value} <- [{"Any", ""}, {"Only AVNs", "true"}, {"Hide AVNs", "false"}]}
          href={query_path("/browse", @params, %{"isAvn" => value, "page" => nil})}
          selected?={bool_value(@payload.filters[:is_avn]) == value}
        >
          {label}
        </.menu_link>
      </.link_popover_chip>

      <button
        type="button"
        phx-click={JS.toggle(to: "#browse-more-filters", display: "contents")}
        class={filter_chip_class(@more_count > 0)}
        aria-expanded={to_string(@more_open?)}
        aria-controls="browse-more-filters"
      >
        <span>More</span>
        <span
          :if={@more_count > 0}
          class="flex size-5 items-center justify-center rounded-full bg-white/12 text-xs"
        >
          {@more_count}
        </span>
        <Lucide.chevron_down class="text-foreground-tertiary size-3.5" />
      </button>

      <span
        id="browse-more-filters"
        class="contents"
        style={if @more_open?, do: nil, else: "display: none"}
      >
        <.multi_popover_chip
          label="Language"
          params={@params}
          param="languages"
          values={@payload.filters[:available_languages]}
          options={language_options()}
          count={length(@payload.filters[:available_languages] || [])}
          initial_count={8}
        />
        <.multi_popover_chip
          label="Original"
          params={@params}
          param="origLang"
          values={@payload.filters[:original_languages]}
          options={original_language_options()}
          count={length(@payload.filters[:original_languages] || [])}
          initial_count={6}
        />
        <.multi_popover_chip
          label="Engine"
          params={@params}
          param="engines"
          values={@payload.filters[:engines]}
          options={engine_options()}
          count={length(@payload.filters[:engines] || [])}
          initial_count={10}
        />
        <.multi_popover_chip
          label="Store"
          params={@params}
          param="stores"
          values={@payload.filters[:available_on_stores]}
          options={store_options()}
          count={length(@payload.filters[:available_on_stores] || [])}
          initial_count={12}
        />
        <.multi_popover_chip
          label="Free on"
          params={@params}
          param="freeStores"
          values={@payload.filters[:free_on_stores]}
          options={free_store_options()}
          count={length(@payload.filters[:free_on_stores] || [])}
          initial_count={length(free_store_options())}
        />
      </span>

      <.link
        :if={@payload.filters_active?}
        patch={clear_filter_path(@params)}
        rel="nofollow"
        class="text-foreground-primary inline-flex h-[34px] items-center rounded-full border border-white/7 bg-white/4 px-3.5 text-[13px] transition hover:border-white/12 hover:bg-white/7"
      >
        Clear all
      </.link>
    </div>
    """
  end

  attr :payload, :map, required: true
  attr :params, :map, required: true

  defp mobile_vn_controls(assigns) do
    assigns =
      assigns
      |> assign(:sort_label, sort_label(assigns.payload.sort_options, assigns.payload.sort_param))
      |> assign(:filter_count, filter_count(assigns.payload.filters, assigns.params))
      |> assign(:mode_options, mobile_mode_options(assigns.params))
      |> assign(:sort_options, mobile_sort_options(assigns.payload, assigns.params))

    ~H"""
    <MobileControls.vn_controls
      payload={@payload}
      mode_options={@mode_options}
      sort_options={@sort_options}
      sort_label={@sort_label}
      filter_count={@filter_count}
    />
    """
  end

  attr :id, :string, required: true
  attr :mode, :atom, required: true
  attr :params, :map, required: true

  defp mode_chip(assigns) do
    ~H"""
    <.menu id={@id} align="start" class={filter_chip_class(false) <> "cursor-pointer"}>
      <:trigger aria-label="Change browse type">
        <Lucide.gamepad_2 :if={@mode == :vn} class="text-foreground-secondary size-4" />
        <Lucide.user_round :if={@mode == :characters} class="text-foreground-secondary size-4" />
        <span>{if @mode == :characters, do: "Characters", else: "VNs"}</span>
        <Lucide.chevron_down class="text-foreground-tertiary size-3.5 transition-transform duration-150 data-[state=open]:rotate-180" />
      </:trigger>
      <div class={popover_content_class("w-[180px] p-1")}>
        <.link
          patch={mode_href(:vn, @params)}
          rel="nofollow"
          data-menu-dismiss
          class={menu_item_class(@mode == :vn)}
        >
          <Lucide.gamepad_2 class="size-4" /> VNs
        </.link>
        <.link
          patch={mode_href(:characters, @params)}
          rel="nofollow"
          data-menu-dismiss
          class={menu_item_class(@mode == :characters)}
        >
          <Lucide.user_round class="size-4" /> Characters
        </.link>
      </div>
    </.menu>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :active, :boolean, default: false
  attr :icon, :atom, default: nil
  attr :count, :integer, default: 0
  attr :clear_href, :string, default: nil
  slot :inner_block, required: true

  defp link_popover_chip(assigns) do
    assigns =
      assign(assigns, :popover_id, assigns.id || "browse-popover-#{slug_id(assigns.label)}")

    ~H"""
    <.menu
      id={@popover_id}
      align="start"
      class={filter_chip_class(@active) <>
      "cursor-pointer" <> if(@active and @clear_href, do: "pr-8", else: "")}
    >
      <:trigger>
        <.chip_icon :if={@icon} icon={@icon} active={@active} />
        <.chip_label label={@label} value={@value} count={@count} active={@active} />
        <span
          :if={@count > 0}
          class="flex size-5 items-center justify-center rounded-full bg-white/12 text-xs"
        >
          {@count}
        </span>
        <Lucide.chevron_down
          :if={not @active or is_nil(@clear_href)}
          class="text-foreground-tertiary size-3.5"
        />
      </:trigger>
      <:trailing :if={@active and @clear_href}>
        <.link
          patch={@clear_href}
          rel="nofollow"
          class="hover:text-foreground-primary text-foreground-primary/60 absolute top-1/2 right-2 -translate-y-1/2 rounded p-0.5"
          aria-label={"Clear #{@label} filter"}
        >
          <Lucide.x class="size-3.5" />
        </.link>
      </:trailing>
      <div class={popover_content_class("w-[220px] p-1")}>
        {render_slot(@inner_block)}
      </div>
    </.menu>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :active, :boolean, default: false
  attr :count, :integer, default: 0
  attr :clear_href, :string, default: nil
  attr :variant, :atom, default: :default
  slot :inner_block, required: true

  defp form_popover_chip(assigns) do
    ~H"""
    <.menu
      id={@id}
      align="start"
      class={filter_chip_class(@active) <>
      "cursor-pointer" <> if(@active and @clear_href, do: "pr-8", else: "")}
    >
      <:trigger>
        <.chip_label label={@label} value={@value} active={@active} />
        <span
          :if={@count > 0}
          class="flex size-5 items-center justify-center rounded-full bg-white/12 text-xs"
        >
          {@count}
        </span>
        <Lucide.chevron_down :if={not @active} class="text-foreground-tertiary size-3.5" />
      </:trigger>
      <:trailing :if={@active and @clear_href}>
        <.link
          patch={@clear_href}
          rel="nofollow"
          class="hover:text-foreground-primary text-foreground-primary/60 absolute top-1/2 right-2 -translate-y-1/2 rounded p-0.5"
          aria-label={"Clear #{@label} filter"}
        >
          <Lucide.x class="size-3.5" />
        </.link>
      </:trailing>
      <div class={popover_content_class(popover_panel_size(@variant))}>
        <form
          id={"#{@id}-form"}
          phx-hook="BrowseAutoApplyFilter"
          action="/browse"
          method="get"
          onsubmit={compact_get_form_submit()}
        >
          <div class="flex flex-col gap-3">
            {render_slot(@inner_block)}
          </div>
        </form>
      </div>
    </.menu>
    """
  end

  attr :label, :string, required: true
  attr :params, :map, required: true
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
  attr :display, :string, required: true

  defp range_popover_chip(assigns) do
    assigns =
      assigns
      |> assign(:active, not is_nil(assigns.min_value) or not is_nil(assigns.max_value))
      |> assign(:popover_id, "browse-desktop-range-#{assigns.min_name}")

    ~H"""
    <.form_popover_chip
      id={@popover_id}
      variant={:range}
      label={@label}
      value={if @active, do: @display}
      active={@active}
      clear_href={
        query_path("/browse", @params, %{@min_name => nil, @max_name => nil, "page" => nil})
      }
    >
      <.hidden_params params={@params} except={[@min_name, @max_name, "page"]} />
      <.range_inputs
        id={"#{@popover_id}-control"}
        label={@label}
        min_name={@min_name}
        max_name={@max_name}
        min_value={@min_value}
        max_value={@max_value}
        min_range={@min_range}
        max_range={@max_range}
        step={@step}
        stops={@stops}
        min_placeholder={@min_placeholder}
        max_placeholder={@max_placeholder}
        density={:desktop}
      />
    </.form_popover_chip>
    """
  end

  attr :label, :string, required: true
  attr :params, :map, required: true
  attr :param, :string, required: true
  attr :values, :list, default: []
  attr :options, :list, required: true
  attr :count, :integer, default: 0
  attr :initial_count, :integer, default: 8

  defp multi_popover_chip(assigns) do
    values = List.wrap(assigns.values)

    selected =
      Enum.filter(assigns.options, fn {_label, value} -> value in values end)

    unselected =
      Enum.reject(assigns.options, fn {_label, value} -> value in values end)

    assigns =
      assigns
      |> assign(:values, values)
      |> assign(:popover_id, "browse-multi-#{assigns.param}")
      |> assign(:selected_options, selected)
      |> assign(:visible_options, Enum.take(unselected, assigns.initial_count))
      |> assign(:hidden_options, Enum.drop(unselected, assigns.initial_count))

    ~H"""
    <.link_popover_chip
      id={@popover_id}
      label={@label}
      active={@count > 0}
      count={@count}
      clear_href={query_path("/browse", @params, %{@param => nil, "page" => nil})}
    >
      <.menu_link
        :for={{label, value} <- @selected_options ++ @visible_options}
        href={toggle_list_param_path(@params, @param, value)}
        selected?={value in @values}
      >
        {label}
      </.menu_link>

      <details
        :if={@hidden_options != []}
        class="border-border-divider/70 group/more-options border-t pt-1"
      >
        <summary class="hover:text-foreground-primary text-foreground-secondary cursor-pointer list-none rounded-lg px-3 py-2 text-[13px] transition hover:bg-white/4 [&::-webkit-details-marker]:hidden">
          Show all {length(@options)}
        </summary>
        <div class="mt-1 max-h-[280px] overflow-y-auto pr-1">
          <.menu_link
            :for={{label, value} <- @hidden_options}
            href={toggle_list_param_path(@params, @param, value)}
            selected?={value in @values}
          >
            {label}
          </.menu_link>
        </div>
      </details>
    </.link_popover_chip>
    """
  end

  attr :include_name, :string, required: true
  attr :exclude_name, :string, required: true
  attr :include_values, :list, default: []
  attr :exclude_values, :list, default: []
  attr :compact, :boolean, default: false

  defp tag_picker(assigns) do
    include_values = assigns.include_values |> List.wrap() |> Enum.map(&to_string/1)
    exclude_values = assigns.exclude_values |> List.wrap() |> Enum.map(&to_string/1)
    selected_slugs = MapSet.new(include_values ++ exclude_values)

    initial_limit = if assigns.compact, do: 150, else: 18
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
      id={"browse-tag-picker-#{@include_name}"}
      phx-hook="BrowseTagPicker"
      data-initial-limit={@initial_limit}
      data-search-limit="120"
      data-tag-picker-data-url={@tag_data_url}
      class="flex min-h-0 flex-col pt-5 pb-4"
    >
      <input type="hidden" name={@include_name} value={@include_value} data-tag-picker-include />
      <input type="hidden" name={@exclude_name} value={@exclude_value} data-tag-picker-exclude />

      <label class="relative mx-3.5 block">
        <.search_icon class="text-foreground-tertiary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2" />
        <input
          type="search"
          placeholder="Search tags..."
          autocomplete="off"
          class="placeholder:text-foreground-primary/40 text-foreground-primary h-9 w-full rounded-[8px] border border-white/8 bg-white/4 pr-3 pl-9 text-xs/6 outline-none focus:border-white/16 focus:bg-white/6 focus:outline-none"
          data-tag-picker-search
        />
      </label>

      <div
        class={[
          "mt-2 overflow-y-auto pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
          @compact && "max-h-[384px]",
          !@compact && "max-h-none"
        ]}
        data-tag-picker-list
      >
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
      class="flex cursor-pointer items-center justify-between rounded px-3.5 py-3 transition hover:bg-white/2 data-[excluded=true]:bg-red-900/20 data-[selected=true]:bg-white/2"
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
        >
          <Lucide.check :if={@included?} class="size-3" />
        </span>
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

  attr :id, :string, required: true
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
  attr :density, :atom, default: :desktop

  defp range_inputs(assigns) do
    assigns =
      assigns
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
    <div
      id={@id}
      phx-hook="BrowseRangeControl"
      data-browse-range-control
      data-min-range={@min_range}
      data-max-range={@max_range}
      data-step={@step}
      data-stops={@stops_value}
      class="min-w-0 px-3 pt-5 pb-4"
    >
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
          class={range_number_class(@density)}
          data-range-min-input
        />
        <span class="text-foreground-secondary shrink-0 text-xs">-</span>
        <input
          type="number"
          name={@max_name}
          value={@max_input_value}
          placeholder={@max_placeholder}
          inputmode="decimal"
          class={range_number_class(@density)}
          data-range-max-input
        />
      </div>
    </div>
    """
  end

  attr :params, :map, required: true
  attr :except, :list, default: []

  defp hidden_params(assigns) do
    ~H"""
    <input
      :for={{key, value} <- hidden_param_pairs(@params, @except)}
      type="hidden"
      name={key}
      value={value}
    />
    """
  end

  attr :href, :string, required: true
  attr :selected?, :boolean, default: false
  attr :description, :string, default: nil
  slot :inner_block, required: true

  defp menu_link(assigns) do
    ~H"""
    <.link patch={@href} rel="nofollow" class={menu_item_class(@selected?)}>
      <span class="min-w-0 flex-1 truncate">
        {render_slot(@inner_block)}
        <span :if={@description} class="text-foreground-secondary block truncate text-xs font-normal">
          {@description}
        </span>
      </span>
      <Lucide.check :if={@selected?} class="size-4 shrink-0" />
    </.link>
    """
  end

  attr :icon, :atom, required: true
  attr :active, :boolean, default: false

  defp chip_icon(%{icon: :sort} = assigns) do
    ~H"""
    <Lucide.arrow_down_wide_narrow
      class={[
        "size-4",
        @active && "text-foreground-primary",
        !@active && "text-foreground-secondary"
      ]}
      aria-hidden
    />
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :count, :integer, default: 0
  attr :active, :boolean, default: false

  # Active + value (single-select, range): "Label:" (lighter) + Value (base weight)
  defp chip_label(%{active: true, value: value} = assigns) when is_binary(value) do
    ~H"""
    <span class="font-normal">{@label}:</span>
    <span>{@value}</span>
    """
  end

  # Active + count (multi-select): "Label:" prefix only; count badge follows separately
  defp chip_label(%{active: true, count: count} = assigns) when count > 0 do
    ~H"""
    <span class="font-normal">{@label}:</span>
    """
  end

  # Inactive, or sort-style chip where @label is the value itself
  defp chip_label(assigns) do
    ~H"""
    <span>{@label}</span>
    """
  end

  attr :payload, :map, required: true
  attr :params, :map, required: true

  defp character_sort_controls(assigns) do
    ~H"""
    <.link_popover_chip
      label={character_sort_label(@payload)}
      icon={:sort}
      active={@payload.sort_param != "most-popular"}
    >
      <.menu_link
        :for={{label, value} <- @payload.sort_options}
        href={query_path("/browse/characters", @params, %{"sort" => value, "page" => nil})}
        selected?={@payload.sort_param == value}
      >
        {label}
      </.menu_link>
    </.link_popover_chip>
    """
  end

  attr :filters, :map, required: true
  attr :params, :map, required: true

  defp active_filter_pills(assigns) do
    assigns = assign(assigns, :pills, filter_pills(assigns.filters, assigns.params))

    ~H"""
    <div
      :if={@pills != []}
      class="flex flex-wrap gap-1.5 px-4 sm:gap-2 sm:px-0"
      data-testid="filter-pills-container"
    >
      <KaguyaWeb.SharedComponents.FilterChip.filter_chip
        :for={pill <- @pills}
        label={pill.label}
        patch={pill.href}
        rel="nofollow"
        tone={if pill.variant == :exclude, do: "exclude", else: "neutral"}
        class={pill_class(pill.variant)}
        icon_x
        title="Remove filter"
      />

      <.link
        :if={length(@pills) > 1}
        patch={clear_filter_path(@params)}
        rel="nofollow"
        class="hover:text-foreground-primary text-foreground-secondary p-1 text-xs transition-colors duration-150"
        aria-label="Clear all filters"
      >
        Clear all
      </.link>
    </div>
    """
  end

  attr :sections, :list, required: true

  defp explore_sections(assigns) do
    ~H"""
    <div class="flex flex-col gap-5 sm:gap-7">
      <section
        :for={section <- @sections}
        class="flex flex-col gap-3 px-4 sm:gap-4 sm:px-0"
        data-section-id={section.id}
      >
        <header>
          <.link
            patch={section.href}
            rel="nofollow"
            class="group/heading text-foreground-primary inline-flex items-center gap-1.5 text-xl font-semibold tracking-tight transition-colors sm:text-2xl"
          >
            <h2>{section.title}</h2>
            <Lucide.chevron_right class="text-foreground-tertiary size-[18px] translate-x-0 opacity-0 transition-all duration-200 ease-out group-hover/heading:translate-x-0.5 group-hover/heading:opacity-100" />
          </.link>
        </header>
        <%= if section.items == [] do %>
          <p class="text-foreground-secondary py-6 text-sm">No matches yet — check back soon.</p>
        <% else %>
          <div
            id={"browse-section-row-#{section.id}"}
            phx-hook="BrowseSectionRow"
            class="group/section relative"
          >
            <div
              data-browse-section-scroller
              class="-ml-3 flex snap-x snap-mandatory overflow-x-auto py-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
            >
              <div
                :for={vn <- section.items}
                class="w-[124px] shrink-0 grow-0 snap-start pl-3 sm:w-[152px] lg:w-[172px]"
              >
                <.link navigate={"/vn/#{vn.slug}"} class="block">
                  <div class="relative aspect-1/1.5 overflow-hidden rounded-[4px] transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] lg:hover:z-30 lg:hover:scale-[1.08] lg:hover:shadow-2xl">
                    <.cover_img
                      src={vn_cover(vn, :large)}
                      alt={vn.title}
                      class="size-full object-cover"
                      blur_nsfw={adult_cover?(vn)}
                      nsfw_blur_size="172"
                    />
                  </div>
                </.link>
              </div>
            </div>

            <button
              type="button"
              data-browse-section-arrow="prev"
              disabled
              aria-label="Scroll previous"
              class={browse_section_arrow_class(:prev)}
            >
              <Lucide.chevron_left class="size-[22px]" />
            </button>

            <button
              type="button"
              data-browse-section-arrow="next"
              aria-label="Scroll next"
              class={browse_section_arrow_class(:next)}
            >
              <Lucide.chevron_right class="size-[22px]" />
            </button>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :params, :map, required: true

  defp vn_results(assigns) do
    ~H"""
    <div class="text-foreground-primary scroll-mt-32 max-sm:-mt-[3px] sm:rounded-[12px]">
      <%= if @result.items == [] do %>
        <div class="text-foreground-secondary flex min-h-[536px] flex-col items-center justify-center px-5 font-normal">
          <p>No VNs match your filters</p>
          <p>Try adjusting them</p>
        </div>
      <% else %>
        <div class="grid grid-cols-3 gap-1.5 px-4 pb-5 sm:grid-cols-4 sm:gap-4 sm:pb-10 sm:max-lg:px-0 md:grid-cols-5 md:gap-x-3 md:gap-y-4 lg:gap-x-3 lg:gap-y-6 lg:px-0 xl:grid-cols-6">
          <.vn_card :for={vn <- @result.items} vn={vn} />
        </div>
      <% end %>

      <.pagination
        page={@result.pagination.page}
        total_pages={@result.pagination.total_pages}
        params={@params}
        base_path="/browse"
      />
    </div>
    """
  end

  attr :vn, :map, required: true

  defp vn_card(assigns) do
    ~H"""
    <.link navigate={"/vn/#{@vn.slug}"} class="flex flex-col gap-1 rounded-[2px] sm:rounded-[4px]">
      <div class="aspect-1/1.5 overflow-hidden rounded-[2px] sm:rounded-[4px]">
        <.cover_img
          src={vn_cover(@vn, :large)}
          alt={@vn.title}
          class="size-full object-cover object-center"
          blur_nsfw={adult_cover?(@vn)}
          nsfw_blur_size="172"
        />
      </div>
      <div class="flex min-h-4 items-center gap-1.5 px-0.5">
        <div :if={show_rating?(@vn)} class="flex items-baseline gap-1 font-medium">
          <span class="text-foreground-secondary text-[11px] sm:text-[12px]">
            {format_rating(@vn.average_rating)}
          </span>
          <span class="text-foreground-tertiary text-[10px] sm:text-[11px]">
            {short_count(@vn.ratings_count || 0)}
          </span>
        </div>
      </div>
    </.link>
    """
  end

  attr :character, :map, required: true

  defp character_card(assigns) do
    ~H"""
    <.link navigate={"/character/#{@character.slug}"} class="group flex flex-col gap-2.5">
      <div class="relative aspect-1/1.5 w-full overflow-hidden rounded-[12px] bg-[radial-gradient(115%_85%_at_50%_22%,#ffffff_0%,#f1f2f4_50%,#d7d8dc_100%)] shadow-[0_2px_6px_-1px_rgba(0,0,0,0.5)] transition duration-300 ease-out group-hover:-translate-y-1 group-hover:shadow-[0_16px_34px_-12px_rgba(0,0,0,0.75)]">
        <KaguyaWeb.SharedComponents.CharacterImage.character_image
          character={@character}
          sizes="(max-width: 640px) 106px, (max-width: 768px) 140px, 160px"
          class="size-full object-cover object-top transition-transform duration-500 ease-out group-hover:scale-[1.04]"
          fallback_class="size-full bg-[rgb(var(--surface-elevated))]"
          rounded=""
        />
        <div class="pointer-events-none absolute inset-0 rounded-[12px] ring-1 ring-inset ring-black/[0.08] transition group-hover:ring-black/[0.14]" />
      </div>
      <div class="flex flex-col gap-0.5 px-0.5">
        <span class="text-foreground-primary line-clamp-1 text-sm font-semibold transition-colors group-hover:text-white">
          {@character.name}
        </span>
        <span
          :if={(@character.favorites_count || 0) > 0}
          class="text-foreground-tertiary flex items-center gap-1 text-xs"
        >
          <Lucide.heart class="size-3" /> {short_count(@character.favorites_count)}
        </span>
      </div>
    </.link>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :params, :map, required: true
  attr :base_path, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <nav
      :if={@total_pages > 1}
      id="pagination-browse"
      phx-hook="PaginationScroll"
      class="border-border-divider relative mx-5 flex items-center justify-center gap-3 border-t py-6 text-sm"
    >
      <.link
        :if={@page > 1}
        patch={query_path(@base_path, @params, %{"page" => page_param(@page - 1)})}
        rel="nofollow"
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Previous
      </.link>
      <span class="text-foreground-secondary">Page {@page} of {@total_pages}</span>
      <.link
        :if={@page < @total_pages}
        patch={query_path(@base_path, @params, %{"page" => page_param(@page + 1)})}
        rel="nofollow"
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Next
      </.link>
    </nav>
    """
  end

  attr :src, :string, default: nil
  attr :alt, :string, default: ""
  attr :class, :string, required: true
  attr :blur_nsfw, :boolean, default: false
  attr :nsfw_blur_size, :string, default: "100"

  defp cover_img(assigns) do
    ~H"""
    <%= if @src do %>
      <img
        src={@src}
        alt={@alt}
        class={@class}
        loading="lazy"
        data-nsfw-blur={if @blur_nsfw, do: "1"}
        style={if @blur_nsfw, do: "--nsfw-blur-size: #{@nsfw_blur_size};"}
      />
    <% else %>
      <div class={[
        @class,
        "bg-surface-elevated text-foreground-secondary flex items-center justify-center text-center text-[10px]"
      ]}>
        No Image
      </div>
    <% end %>
    """
  end

  defp mode_href(:vn, params) do
    params
    |> Map.drop(["type", "page"])
    |> query_path_from_params("/browse", %{})
  end

  defp mode_href(:characters, params) do
    params
    |> Map.take(["sort"])
    |> Map.drop(["page"])
    |> query_path_from_params("/browse/characters", %{})
  end

  defp query_path_from_params(params, base_path, overrides),
    do: query_path(base_path, params, overrides)

  defp query_path(base_path, params, overrides) do
    query =
      params
      |> Map.merge(overrides)
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> URI.encode_query()

    if query == "", do: base_path, else: base_path <> "?" <> query
  end

  defp page_param(1), do: nil
  defp page_param(page), do: to_string(page)

  defp browse_section_arrow_class(:prev), do: browse_section_arrow_class("-left-14")
  defp browse_section_arrow_class(:next), do: browse_section_arrow_class("-right-14")

  defp browse_section_arrow_class(position_class) do
    [
      "absolute top-1/2 z-30 flex h-20 w-8 -translate-y-1/2 items-center justify-center rounded-full border border-white/[8%] bg-black/55 text-white backdrop-blur-md transition-colors duration-150 hover:border-white/[18%] hover:bg-black/80 disabled:pointer-events-none disabled:opacity-0 max-lg:hidden",
      position_class
    ]
  end

  defp filter_chip_class(active?) do
    base =
      "inline-flex h-[34px] items-center gap-1.5 rounded-full border border-white/[7%] bg-white/[4%] px-3.5 text-[13px] font-medium text-foreground-primary outline-none transition-colors duration-150 hover:border-white/[12%] hover:bg-white/[7%] focus:outline-none focus-visible:outline-none focus-within:border-white/[14%] focus-within:bg-white/[7%]"

    if active? do
      # Brand here is crimson (rgb 155 1 61), and red borders read as
      # destructive/error next to the page's actual semantic-error chips.
      # A filled neutral pill is the cleaner "this chip is selected" signal:
      # bg does the work, not color.
      # `!` overrides the base `bg-white/[4%]` (Tailwind v4 emits utilities
      # alphabetically; without !important the base wins on same-specificity
      # ties — prod sidesteps this via tailwind-merge, we string-concat).
      base <>
        " !bg-white/[10%] hover:!bg-white/[14%]"
    else
      base
    end
  end

  defp pill_class(:exclude),
    do: "!border-semantic-error/60 bg-semantic-error/[0.08] hover:!border-semantic-error/75"

  defp pill_class(_variant),
    do:
      "!border-button-background-brand-default/55 bg-button-background-brand-default/[0.08] hover:!border-button-background-brand-default/70"

  defp popover_content_class(extra) do
    "rounded-[12px] border border-border-divider bg-surface-base text-foreground-primary shadow-xl outline-none " <>
      extra
  end

  defp popover_panel_size(:tags), do: "w-[260px] p-0"
  defp popover_panel_size(:range), do: "w-[280px] p-0"
  defp popover_panel_size(_), do: "w-[320px] p-3"

  defp slug_id(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp range_number_class(:desktop) do
    "h-10 min-w-0 flex-1 rounded-[8px] border border-white/[10%] bg-white/[5%] px-3 text-sm tabular-nums text-foreground-primary outline-none placeholder:text-foreground-tertiary focus:border-white/[16%] focus:bg-white/[7%] [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
  end

  defp range_number_class(_density) do
    "h-12 min-w-0 flex-1 rounded-[10px] border border-white/[10%] bg-white/[5%] px-3 text-base tabular-nums text-foreground-primary outline-none placeholder:text-foreground-tertiary focus:border-white/[16%] focus:bg-white/[7%] [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
  end

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

  defp menu_item_class(true) do
    "flex w-full items-center gap-2 rounded-lg bg-white/[4%] px-3 py-2 text-left text-[13px] font-medium text-foreground-primary outline-none transition focus:outline-none focus-visible:bg-white/[6%] focus-visible:outline-none"
  end

  defp menu_item_class(false) do
    "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-[13px] text-foreground-primary outline-none transition hover:bg-white/[4%] focus:outline-none focus-visible:bg-white/[4%] focus-visible:outline-none"
  end

  defp sort_label(_options, nil), do: "Default"
  defp sort_label(_options, ""), do: "Default"

  defp sort_label(options, value) do
    options
    |> Enum.find_value(fn
      {label, ^value} -> label
      _option -> nil
    end)
    |> case do
      nil -> "Default"
      label -> label
    end
  end

  defp desktop_sort_label(%{sort_param: nil}), do: "Sort"

  defp desktop_sort_label(%{sort_options: options, sort_param: value}),
    do: sort_label(options, value)

  defp character_sort_label(%{sort_options: options, sort_param: value}),
    do: sort_label(options, value)

  defp single_chip_value(nil, _label_fun), do: nil
  defp single_chip_value(value, label_fun), do: label_fun.(value)

  defp tags_count(filters) do
    length(Map.get(filters, :include_tags, [])) + length(Map.get(filters, :exclude_tags, []))
  end

  defp secondary_filter_count(filters) do
    [
      :available_languages,
      :original_languages,
      :engines,
      :available_on_stores,
      :free_on_stores
    ]
    |> Enum.count(&(Map.get(filters, &1, []) != []))
  end

  defp hidden_param_pairs(params, except) do
    except = MapSet.new(except)

    params
    |> Enum.reject(fn {key, value} ->
      MapSet.member?(except, key) or is_nil(value) or value == ""
    end)
    |> Enum.flat_map(fn
      {key, values} when is_list(values) -> Enum.map(values, &{key, &1})
      {key, value} -> [{key, value}]
    end)
  end

  defp toggle_list_param_path(params, param_key, value) do
    values =
      params
      |> Map.get(param_key, "")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    value = to_string(value)

    next_values =
      if value in values do
        Enum.reject(values, &(&1 == value))
      else
        values ++ [value]
      end

    query_path("/browse", params, %{param_key => joined_or_nil(next_values), "page" => nil})
  end

  defp length_options do
    Enum.map(FilterOptions.lengths(), fn {label, value, _description} -> {label, value} end)
  end

  defp length_description("short"), do: "< 10 hours"
  defp length_description("medium"), do: "10-30 hours"
  defp length_description("long"), do: "30-50 hours"
  defp length_description("very_long"), do: "50+ hours"
  defp length_description(_), do: nil

  defp platform_options do
    FilterOptions.platforms()
  end

  defp language_options, do: FilterOptions.languages()
  defp original_language_options, do: FilterOptions.original_languages()
  defp engine_options, do: FilterOptions.engines()
  defp store_options, do: FilterOptions.stores()
  defp free_store_options, do: FilterOptions.free_stores()

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

  defp filter_count(filters, params), do: filters |> filter_pills(params) |> length()

  defp mobile_mode_options(params) do
    [
      %{label: "VNs", href: mode_href(:vn, params), selected?: true, icon: :gamepad},
      %{label: "Characters", href: mode_href(:characters, params), selected?: false, icon: :user}
    ]
  end

  defp mobile_sort_options(payload, params) do
    [{"Default", ""} | payload.sort_options]
    |> Enum.map(fn {label, value} ->
      %{
        label: label,
        href: query_path("/browse", params, %{"sort" => value, "page" => nil}),
        selected?: (payload.sort_param || "") == value
      }
    end)
  end

  defp compact_get_form_submit do
    "this.querySelectorAll('input, select').forEach((field) => { field.disabled = field.value === '' })"
  end

  defp bool_value(true), do: "true"
  defp bool_value(false), do: "false"
  defp bool_value(_), do: ""

  defp filter_pills(filters, params) do
    []
    |> maybe_add_range_pill(
      filters,
      params,
      :released_after_year,
      :released_before_year,
      "fromYear",
      "toYear",
      "Year",
      :year
    )
    |> maybe_add_range_pill(
      filters,
      params,
      :average_rating_gte,
      :average_rating_lte,
      "minRating",
      "maxRating",
      "Rating",
      :rating
    )
    |> maybe_add_range_pill(
      filters,
      params,
      :ratings_count_gte,
      :ratings_count_lte,
      "minRatings",
      "maxRatings",
      "Popularity",
      :votes
    )
    |> add_list_pills(filters, params, :include_tags, "tags", &tag_title/1, :default)
    |> add_list_pills(filters, params, :exclude_tags, "excludeTags", &tag_title/1, :exclude)
    |> add_list_pills(
      filters,
      params,
      :available_platforms,
      "platforms",
      &platform_name/1,
      :default
    )
    |> add_list_pills(
      filters,
      params,
      :available_languages,
      "languages",
      &language_name/1,
      :default
    )
    |> add_list_pills(
      filters,
      params,
      :original_languages,
      "origLang",
      &language_name/1,
      :default
    )
    |> add_list_pills(filters, params, :engines, "engines", & &1, :default)
    |> maybe_add_single_pill(filters, params, :length_category, "length", &length_label/1)
    |> maybe_add_single_pill(filters, params, :is_avn, "isAvn", fn
      true -> "Only AVNs"
      false -> "Hide AVNs"
      value -> to_string(value)
    end)
    |> add_list_pills(filters, params, :available_on_stores, "stores", &store_name/1, :default)
    |> add_list_pills(
      filters,
      params,
      :free_on_stores,
      "freeStores",
      &("Free on " <> store_name(&1)),
      :default
    )
    |> Enum.reverse()
  end

  defp maybe_add_range_pill(
         pills,
         filters,
         params,
         min_key,
         max_key,
         min_param,
         max_param,
         label,
         variant
       ) do
    min = Map.get(filters, min_key)
    max = Map.get(filters, max_key)

    if is_nil(min) and is_nil(max) do
      pills
    else
      [
        %{
          label: range_label(label, min, max, variant),
          href:
            query_path("/browse", params, %{min_param => nil, max_param => nil, "page" => nil}),
          variant: :default
        }
        | pills
      ]
    end
  end

  defp add_list_pills(pills, filters, params, filter_key, param_key, label_fun, variant) do
    filters
    |> Map.get(filter_key, [])
    |> List.wrap()
    |> Enum.reduce(pills, fn value, acc ->
      [
        %{
          label: label_fun.(value),
          href: remove_list_param_path(params, param_key, value),
          variant: variant
        }
        | acc
      ]
    end)
  end

  defp maybe_add_single_pill(pills, filters, params, filter_key, param_key, label_fun) do
    case Map.get(filters, filter_key) do
      nil ->
        pills

      value ->
        [
          %{
            label: label_fun.(value),
            href: query_path("/browse", params, %{param_key => nil, "page" => nil}),
            variant: :default
          }
          | pills
        ]
    end
  end

  defp range_label(label, nil, nil, _variant), do: label
  defp range_label("Year", min, nil, _variant), do: "After #{min}"
  defp range_label("Year", nil, max, _variant), do: "Before #{max}"
  defp range_label("Year", min, max, _variant), do: "#{min} - #{max}"

  defp range_label("Popularity", min, nil, _variant), do: "Over #{min} Ratings"
  defp range_label("Popularity", nil, max, _variant), do: "Under #{max} Ratings"
  defp range_label("Popularity", min, max, _variant), do: "#{min} - #{max}"

  defp range_label("Rating", min, nil, _variant), do: "#{min}★ - 5.0★"
  defp range_label("Rating", nil, max, _variant), do: "1.0★ - #{max}★"
  defp range_label("Rating", min, max, _variant), do: "#{min}★ - #{max}★"

  defp remove_list_param_path(params, param_key, value) do
    next_values =
      params
      |> Map.get(param_key, "")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == to_string(value)))

    query_path("/browse", params, %{param_key => joined_or_nil(next_values), "page" => nil})
  end

  defp joined_or_nil([]), do: nil
  defp joined_or_nil(values), do: Enum.join(values, ",")

  defp clear_filter_path(params),
    do: query_path("/browse", params, Map.put(clear_filter_params(), "page", nil))

  defp clear_filter_params do
    [
      "fromYear",
      "toYear",
      "minRating",
      "maxRating",
      "tags",
      "excludeTags",
      "minRatings",
      "maxRatings",
      "platforms",
      "languages",
      "engines",
      "length",
      "origLang",
      "stores",
      "freeStores",
      "isAvn"
    ]
    |> Map.new(&{&1, nil})
  end

  defp tag_title(slug), do: TagSnapshot.title(slug)
  defp platform_name(code), do: FilterOptions.label(platform_options(), code)
  defp language_name(code), do: FilterOptions.label(language_options(), code)
  defp length_label(value), do: FilterOptions.label(FilterOptions.lengths(), value)
  defp store_name(store), do: FilterOptions.label(store_options(), store)

  defp show_rating?(vn), do: (vn.ratings_count || 0) >= 5 and not is_nil(vn.average_rating)

  defp format_rating(rating) when is_number(rating),
    do: :erlang.float_to_binary(rating / 1, decimals: 1)

  defp format_rating(_), do: nil

  defp short_count(count) when count >= 1_000_000, do: "#{Float.round(count / 1_000_000, 1)}m"
  defp short_count(count) when count >= 1_000, do: "#{Float.round(count / 1_000, 1)}k"
  defp short_count(count), do: to_string(count)

  defp vn_cover(vn, preferred) do
    urls = VisualNovels.build_image_urls(vn)

    Map.get(urls, preferred) || Map.get(urls, :medium) || Map.get(urls, :small) ||
      vn.temp_image_url
  end

  defp adult_cover?(vn) do
    [
      :is_image_nsfw,
      :is_image_suggestive,
      "is_image_nsfw",
      "is_image_suggestive"
    ]
    |> Enum.any?(&(Map.get(vn, &1) == true))
  end
end
