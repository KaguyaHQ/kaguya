defmodule KaguyaWeb.SharedComponents.Search do
  @moduledoc """
  Shared VN search UI primitives.

  Provides the search input, VN search input, VN result list, and recent
  searches, with `:default` and `:compact` variants sharing the same
  result-row implementation.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Cover

  attr :id, :string, required: true
  attr :variant, :any, default: :default
  attr :mobile, :boolean, default: false
  attr :mobile_fullheight, :boolean, default: false
  attr :page_size, :integer, default: 24
  attr :show_all_results, :boolean, default: true
  attr :placeholder, :string, default: "Search visual novels"
  attr :class, :any, default: nil
  attr :popover_class, :any, default: nil

  def navbar_vn_search(assigns) do
    assigns =
      assigns
      |> assign(:variant, normalize_variant(assigns.variant))
      |> assign(:show_all_results, to_string(assigns.show_all_results))

    ~H"""
    <div
      id={@id}
      phx-hook="VNSearch"
      phx-update="ignore"
      data-page-size={@page_size}
      data-show-all-results={@show_all_results}
      data-variant={@variant}
      data-mobile-fullheight={to_string(@mobile_fullheight)}
      class={[
        "relative",
        if(@mobile, do: "w-full", else: "w-[284px] lg:w-[345px]"),
        @class
      ]}
    >
      <form
        action="/search"
        method="get"
        role="search"
        class="relative flex items-center"
        data-vn-search-form
      >
        <input type="hidden" name="type" value="visualNovels" />
        <.search_icon
          class={[
            "text-foreground-primary pointer-events-none absolute",
            if(@mobile, do: "left-4 size-5", else: "left-3 size-4")
          ]}
          aria-hidden
        />
        <input
          type="search"
          name="q"
          autocomplete="off"
          placeholder={@placeholder}
          data-vn-search-input
          class={[
            "placeholder:text-foreground-primary/40 text-foreground-primary focus-visible:outline-none",
            if(@mobile,
              do:
                "bg-surface-elevated h-11 w-full rounded-[100px] border-none pr-10 pl-12 text-base font-normal dark:bg-white/4",
              else:
                "border-text-field-border focus-visible:border-button-background-brand-default! h-11 w-full rounded-[100px] border bg-transparent pr-4 pl-9 text-sm font-normal focus-visible:border"
            )
          ]}
        />
        <button
          :if={@mobile}
          type="button"
          data-vn-search-clear
          hidden
          class="text-foreground-primary/50 absolute top-1/2 right-1 z-10 flex size-10 -translate-y-1/2 items-center justify-center"
          aria-label="Clear search"
        >
          <Lucide.x class="size-5" aria-hidden />
        </button>
      </form>

      <div
        data-vn-search-popover
        hidden
        class={navbar_popover_class(@mobile, @mobile_fullheight, @popover_class)}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :select_event, :string, required: true
  attr :select_target, :string, default: nil
  attr :page_size, :integer, default: 5
  attr :placeholder, :string, default: "Search visual novels"
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil
  attr :popover_class, :any, default: nil

  @doc """
  Compact VN search powered by the JS-driven `VNSearch` hook, pushing the
  selected item id to LiveView via `select_event` instead of navigating. Mirrors
  the navbar search UX (instant loader, fetches `/search/visual-novels`).
  """
  def vn_select_search(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="VNSearch"
      phx-update="ignore"
      data-page-size={@page_size}
      data-variant="compact"
      data-show-all-results="false"
      data-hide-recent="true"
      data-select-event={@select_event}
      data-select-target={@select_target}
      class={["relative", @class]}
    >
      <form
        action="/search"
        method="get"
        role="search"
        class="relative flex items-center"
        data-vn-search-form
      >
        <input type="hidden" name="type" value="visualNovels" />
        <.search_icon
          class="text-foreground-primary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
          aria-hidden
        />
        <input
          type="search"
          name="q"
          autocomplete="off"
          autocapitalize="off"
          spellcheck="false"
          placeholder={@placeholder}
          data-vn-search-input
          class={[
            "bg-surface-elevated border-border-divider focus:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-11 w-full rounded-[8px] border pr-3 pl-9 text-sm placeholder:text-sm focus:ring-0 focus:outline-none",
            @input_class
          ]}
        />
      </form>

      <div
        data-vn-search-popover
        hidden
        class={[
          "bg-surface-menu-item-default ring-border-divider text-foreground-primary absolute top-[calc(100%+4px)] left-0 z-110 max-h-[262px] w-full min-w-[236px] overflow-x-hidden overflow-y-auto rounded-[8px] p-0 text-sm ring-1",
          "shadow-[0_5px_15px_rgba(0,5,15,0.35)]",
          @popover_class
        ]}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :error, :string, default: nil
  attr :loading, :boolean, default: false
  attr :placeholder, :string, default: "Search visual novels…"
  attr :change_event, :string, default: "search"
  attr :submit_event, :string, default: "search"
  attr :select_event, :string, default: "add_item"
  attr :target, :any, default: nil
  attr :debounce, :integer, default: 350
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil
  attr :results_class, :any, default: nil
  attr :show_add_icon, :boolean, default: false

  def vn_compact_search(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <.form
        for={%{}}
        as={:search}
        id={@id}
        phx-change={@change_event}
        phx-submit={@submit_event}
        phx-target={@target}
        class="relative"
      >
        <.search_icon
          class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-[rgb(var(--foreground-primary))]"
          aria-hidden
        />
        <input
          type="text"
          name="search[query]"
          value={@query}
          placeholder={@placeholder}
          autocomplete="off"
          autocapitalize="off"
          spellcheck="false"
          phx-debounce={@debounce}
          class={[
            "h-11 w-full rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] pr-3 pl-9 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-sm placeholder:text-[rgb(var(--foreground-primary))]/40 focus:border-[rgb(var(--text-field-border-focus))] focus:ring-0 focus:outline-none",
            @input_class
          ]}
        />
      </.form>

      <.vn_results_popover
        :if={@loading or @results != [] or @error}
        results={@results}
        error={@error}
        loading={@loading}
        variant={:compact}
        mode={:select}
        select_event={@select_event}
        target={@target}
        show_add_icon={@show_add_icon}
        class={@results_class}
      />
    </div>
    """
  end

  attr :results, :list, default: []
  attr :error, :string, default: nil
  attr :loading, :boolean, default: false
  attr :variant, :any, default: :default
  attr :mode, :any, default: :navigate
  attr :select_event, :string, default: nil
  attr :target, :any, default: nil
  attr :show_add_icon, :boolean, default: false
  attr :show_remove, :boolean, default: false
  attr :recent, :boolean, default: false
  attr :item_class, :any, default: nil
  attr :empty_message, :string, default: "No results found"
  attr :class, :any, default: nil

  def vn_results_popover(assigns) do
    assigns = normalize_result_assigns(assigns)

    ~H"""
    <div class={[result_popover_class(@variant), @class]}>
      <.vn_result_list
        results={@results}
        error={@error}
        loading={@loading}
        variant={@variant}
        mode={@mode}
        select_event={@select_event}
        target={@target}
        show_add_icon={@show_add_icon}
        show_remove={@show_remove}
        recent={@recent}
        item_class={@item_class}
        empty_message={@empty_message}
      />
    </div>
    """
  end

  attr :results, :list, default: []
  attr :error, :string, default: nil
  attr :loading, :boolean, default: false
  attr :variant, :any, default: :default
  attr :mode, :any, default: :navigate
  attr :select_event, :string, default: nil
  attr :target, :any, default: nil
  attr :show_add_icon, :boolean, default: false
  attr :show_remove, :boolean, default: false
  attr :recent, :boolean, default: false
  attr :item_class, :any, default: nil
  attr :empty_message, :string, default: "No results found"
  attr :class, :any, default: nil

  def vn_result_list(assigns) do
    assigns = normalize_result_assigns(assigns)

    ~H"""
    <div class={[
      if(@recent, do: "[&>div]:divide-border-divider p-0 [&>div]:divide-y", else: "p-0"),
      @class
    ]}>
      <div
        :if={@loading and @results == [] and !@error}
        class="flex items-center justify-center px-6 py-3"
        role="status"
        aria-label="Searching"
      >
        <div class="kaguya-button-loader">
          <span class="kaguya-button-loader-bar"></span>
          <span class="kaguya-button-loader-bar" style="animation-delay: -0.2s"></span>
          <span class="kaguya-button-loader-bar" style="animation-delay: -0.4s"></span>
        </div>
      </div>
      <p
        :if={@error and !@loading}
        class="text-foreground-error flex items-center justify-center px-6 py-[18px] text-center text-sm font-medium"
      >
        {@error}
      </p>
      <p
        :if={!@error and !@loading and @results == []}
        class="text-foreground-primary flex items-center justify-center px-6 py-[18px] text-center text-sm font-medium"
      >
        {@empty_message}
      </p>
      <.vn_result_row
        :for={{result, index} <- Enum.with_index(@results)}
        result={result}
        variant={@variant}
        mode={@mode}
        select_event={@select_event}
        target={@target}
        show_add_icon={@show_add_icon}
        show_remove={@show_remove}
        item_class={@item_class}
        last?={index == length(@results) - 1}
      />
    </div>
    """
  end

  attr :result, :map, required: true
  attr :variant, :any, default: :default
  attr :mode, :any, default: :navigate
  attr :select_event, :string, default: nil
  attr :target, :any, default: nil
  attr :show_add_icon, :boolean, default: false
  attr :show_remove, :boolean, default: false
  attr :item_class, :any, default: nil
  attr :last?, :boolean, default: false

  def vn_result_row(assigns) do
    assigns =
      assigns
      |> assign(:variant, normalize_variant(assigns.variant))
      |> assign(:mode, normalize_mode(assigns.mode))
      |> assign(:compact?, normalize_variant(assigns.variant) == :compact)
      |> assign(:href, href_for(assigns.result))
      |> assign(:image_url, image_url(assigns.result))
      |> assign(:producer_text, producer_text(result_value(assigns.result, :producers)))

    ~H"""
    <div class="flex w-full flex-col">
      <button
        :if={@mode == :select}
        type="button"
        phx-click={@select_event}
        phx-value-id={result_value(@result, :id)}
        phx-target={@target}
        class={result_item_class(@variant, @last?, @item_class)}
      >
        <span class={result_link_class(@variant)}>
          <.result_row_content
            result={@result}
            variant={@variant}
            compact?={@compact?}
            producer_text={@producer_text}
          />
        </span>
        <Lucide.plus
          :if={@show_add_icon}
          class="text-foreground-secondary mt-2 mr-2 size-4 shrink-0"
          aria-hidden
        />
      </button>

      <div :if={@mode == :navigate} class={result_item_class(@variant, @last?, @item_class)}>
        <.link
          navigate={@href || "#"}
          class={result_link_class(@variant)}
          data-vn-search-select
          data-vn-search-id={result_value(@result, :id)}
          data-vn-search-title={result_value(@result, :title)}
          data-vn-search-slug={result_value(@result, :slug)}
          data-vn-search-image-url={@image_url}
          data-vn-search-producers={@producer_text}
        >
          <.result_row_content
            result={@result}
            variant={@variant}
            compact?={@compact?}
            producer_text={@producer_text}
          />
          <Lucide.arrow_right :if={!@compact?} class="-ml-4 size-6 sm:hidden" aria-hidden />
        </.link>

        <button
          :if={@show_remove}
          type="button"
          data-vn-search-remove={result_value(@result, :id)}
          class={[
            "text-foreground-secondary flex shrink-0 items-center justify-center",
            if(@compact?, do: "mr-1 size-8", else: "mr-2 size-10")
          ]}
          aria-label={"Remove #{result_value(@result, :title) || "result"} from recent searches"}
        >
          <Lucide.x class="size-4" aria-hidden />
        </button>
      </div>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :variant, :any, required: true
  attr :compact?, :boolean, required: true
  attr :producer_text, :string, default: nil

  defp result_row_content(assigns) do
    ~H"""
    <div class={[
      "flex min-w-0 flex-1",
      if(@compact?, do: "items-center gap-2.5", else: "items-start gap-4")
    ]}>
      <div class={cover_frame_class(@variant)}>
        <div style={cover_shadow()}>
          <Cover.cover
            vn={@result}
            sizes={if(@compact?, do: "27px", else: "48px")}
            class={cover_image_class(@variant)}
            fallback_class={cover_fallback_class(@variant)}
          />
        </div>
      </div>
      <div class={["flex min-w-0 flex-1 flex-col", if(@compact?, do: "gap-0.5", else: "mt-2 gap-2")]}>
        <span class={[
          "font-source-serif text-foreground-primary",
          if(@compact?,
            do: "text-style-body2Medium truncate",
            else: "text-style-body1Medium line-clamp-1"
          )
        ]}>
          {result_value(@result, :title)}
        </span>
        <span
          :if={@producer_text not in [nil, ""]}
          class={[
            "text-foreground-tertiary",
            if(@compact?,
              do: "text-style-captionRegular truncate",
              else: "text-style-body2Regular line-clamp-1"
            )
          ]}
        >
          {@producer_text}
        </span>
      </div>
    </div>
    """
  end

  defp normalize_result_assigns(assigns) do
    assigns
    |> assign_new(:results, fn -> [] end)
    |> assign_new(:error, fn -> nil end)
    |> assign_new(:loading, fn -> false end)
    |> assign_new(:variant, fn -> :default end)
    |> assign_new(:mode, fn -> :navigate end)
    |> assign_new(:select_event, fn -> nil end)
    |> assign_new(:target, fn -> nil end)
    |> assign_new(:show_add_icon, fn -> false end)
    |> assign_new(:show_remove, fn -> false end)
    |> assign_new(:recent, fn -> false end)
    |> assign_new(:item_class, fn -> nil end)
    |> assign_new(:empty_message, fn -> "No results found" end)
    |> assign_new(:class, fn -> nil end)
    |> assign(:variant, normalize_variant(assigns[:variant] || :default))
    |> assign(:mode, normalize_mode(assigns[:mode] || :navigate))
  end

  defp navbar_popover_class(mobile?, mobile_fullheight?, extra) do
    [
      "absolute z-[110] min-w-[236px] overflow-hidden bg-surface-menu-item-default p-0 text-sm text-foreground-primary ring-1 ring-border-divider",
      "shadow-[0_5px_15px_rgba(0,5,15,0.35)]",
      popover_position_class(mobile?, mobile_fullheight?),
      extra
    ]
  end

  # Inline-replace mobile (navbar): popover escapes the flex-1 input container
  # to span near-full viewport — back-arrow (44px) + gap-2 (8px) = 52px offset,
  # navbar px-5 = 40px total horizontal padding.
  defp popover_position_class(true, true) do
    "top-[52px] -left-[52px] w-[calc(100vw-40px)] max-h-[424px] rounded-[12px] bg-surface-elevated"
  end

  defp popover_position_class(true, false) do
    "top-[52px] right-0 left-0 w-full max-h-[424px] rounded-[12px] bg-surface-elevated"
  end

  defp popover_position_class(false, _),
    do: "top-[60px] w-full max-w-[513px] rounded-[8px] sm:max-h-[484px]"

  defp result_popover_class(:compact) do
    [
      "absolute top-[calc(100%+4px)] left-0 z-[110] max-h-[262px] w-full min-w-[236px] overflow-y-auto overflow-x-hidden rounded-[8px] bg-surface-menu-item-default p-0 text-sm text-foreground-primary ring-1 ring-border-divider",
      "shadow-[0_5px_15px_rgba(0,5,15,0.35)]"
    ]
  end

  defp result_popover_class(:default) do
    [
      "absolute top-[60px] left-0 z-[110] w-full max-w-[513px] min-w-[236px] overflow-hidden rounded-[8px] bg-surface-menu-item-default p-0 text-sm text-foreground-primary ring-1 ring-border-divider sm:max-h-[484px]",
      "shadow-[0_5px_15px_rgba(0,5,15,0.35)]"
    ]
  end

  defp result_item_class(variant, last?, extra) do
    [
      "flex w-full flex-1 cursor-pointer items-start p-0 text-foreground-primary hover:bg-transparent aria-selected:bg-transparent aria-selected:text-foreground-primary lg:hover:bg-surface-menu-item-hover lg:aria-selected:bg-surface-menu-item-hover",
      if(last?, do: "border-b border-transparent", else: "border-b border-border-divider"),
      if(variant == :compact, do: "h-[56px]", else: "h-[96px]"),
      extra
    ]
  end

  defp result_link_class(:compact),
    do: "flex h-full min-w-0 flex-1 items-start justify-between gap-3 px-2 py-1.5 text-left"

  defp result_link_class(:default),
    do: "flex h-full min-w-0 flex-1 items-center justify-between gap-5 px-4 py-2 sm:py-3"

  defp cover_frame_class(:compact),
    do:
      "aspect-[1/1.5] h-[40px] w-[27px] shrink-0 overflow-hidden rounded-[2px] bg-surface-elevated"

  defp cover_frame_class(:default),
    do: "aspect-[1/1.5] h-[72px] w-[48px] overflow-hidden rounded-[4px] bg-surface-elevated"

  defp cover_image_class(:compact),
    do:
      "aspect-[1/1.5] h-[40px] w-[27px] rounded-[2px] object-cover object-center text-transparent"

  defp cover_image_class(:default),
    do:
      "aspect-[1/1.5] h-[72px] w-[48px] rounded-[4px] object-cover object-center text-transparent"

  defp cover_fallback_class(:compact),
    do: "h-[40px] w-[27px] rounded-[2px] border border-border-divider text-[9px]"

  defp cover_fallback_class(:default),
    do: "h-[72px] w-[48px] rounded-[4px] border border-border-divider text-xs"

  defp normalize_variant(value) when value in [:compact, "compact"], do: :compact
  defp normalize_variant(_value), do: :default

  defp normalize_mode(value) when value in [:select, "select"], do: :select
  defp normalize_mode(_value), do: :navigate

  defp href_for(result) do
    case result_value(result, :slug) do
      slug when is_binary(slug) and slug != "" -> "/vn/#{slug}"
      _ -> nil
    end
  end

  defp image_url(item) do
    images = result_value(item, :images) || %{}

    result_value(item, :image_url) ||
      image_value(images, :small) ||
      image_value(images, :medium) ||
      image_value(images, :large) ||
      image_value(images, :xl) ||
      ""
  end

  defp image_value(images, key), do: Map.get(images, key) || Map.get(images, Atom.to_string(key))

  defp result_value(item, key), do: Map.get(item, key) || Map.get(item, Atom.to_string(key))

  defp cover_shadow, do: "box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.35);"

  defp producer_text(producers) when is_list(producers) do
    producers
    |> Enum.map(fn
      %{name: name} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp producer_text(value) when is_binary(value), do: value
  defp producer_text(_), do: nil
end
