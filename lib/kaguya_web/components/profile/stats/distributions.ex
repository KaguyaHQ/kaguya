defmodule KaguyaWeb.Components.Profile.Stats.Distributions do
  @moduledoc """
  Distribution chart components (ratings, length, bar lists, donuts) for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Stats.Charting
  import KaguyaWeb.Components.Profile.Stats.Primitives

  alias KaguyaWeb.Components.Shared.RatingsChart
  alias KaguyaWeb.Format

  attr :profile, :map, required: true

  def ratings_section(assigns) do
    ~H"""
    <.chart_card :if={@profile.ratings_count > 0} title="Ratings">
      <RatingsChart.ratings_chart
        dist={@profile.ratings_dist}
        count={@profile.ratings_count}
        average={@profile.average_rating || 0.0}
        username={@profile.username}
        hide_title
        class="h-[179px] lg:h-[267px]"
        content_class="mt-2 px-[12px] pt-5 lg:mt-9 lg:px-0 lg:pt-6"
      />
    </.chart_card>
    """
  end

  attr :username, :string, required: true
  attr :items, :list, required: true

  def length_section(assigns) do
    max = assigns.items |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    items = Enum.map(assigns.items, &Map.put(&1, :height, bar_height(&1.value, max)))
    assigns = assign(assigns, :items, items)

    ~H"""
    <.chart_card :if={@items != []} title="Length">
      <ul class="mt-2 flex h-[179px] gap-2 px-[12px] pt-5 lg:mt-9 lg:h-[267px] lg:px-0 lg:pt-6">
        <%= for item <- @items do %>
          <li class="flex min-w-0 flex-1 flex-col items-center gap-2">
            <.link
              navigate={"/@#{@username}/library/read?length=#{item.key}"}
              class="group flex w-full flex-1 items-end"
            >
              <span class="relative flex size-full items-end justify-center">
                <span
                  class="absolute left-1/2 z-10 -translate-x-1/2 text-[10px] font-medium text-[rgb(var(--foreground-primary))] tabular-nums"
                  style={"bottom: calc(#{item.height}% + 6px)"}
                >
                  {item.value}
                </span>
                <span
                  class="block w-full origin-bottom animate-[barRise_800ms_cubic-bezier(0.16,1,0.3,1)_both] rounded-t-[4px] transition-opacity group-hover:opacity-80 motion-reduce:animate-none"
                  style={"height: #{item.height}%; min-height: #{bar_min_height(item.value)}; background-color: #9B7EDE"}
                >
                  <span class="sr-only">{item.value} visual novels, {item.label}</span>
                </span>
              </span>
            </.link>
            <span class="text-center text-[9px] font-medium text-[rgb(var(--foreground-secondary))] sm:text-[10px]">
              <span class="lg:hidden">{item.short_label}</span>
              <span class="max-lg:hidden">{item.label}</span>
            </span>
          </li>
        <% end %>
      </ul>
    </.chart_card>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :value_key, :atom, required: true
  attr :color, :string, required: true
  attr :username, :string, required: true
  attr :filter_key, :string, required: true
  attr :limit, :integer, default: 10
  attr :rating, :boolean, default: false

  def bar_list_section(assigns) do
    items = assigns.items |> Enum.take(assigns.limit)
    max_value = bar_max(items, assigns.value_key, assigns.rating)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:max_value, max_value)

    ~H"""
    <.chart_card title={@title} empty={@items == []}>
      <%= if @items == [] do %>
        <.empty_chart height="h-[344px] lg:h-[504px]" />
      <% else %>
        <ul class="mt-8 flex flex-col gap-1.5 px-[12px] lg:mt-9 lg:px-0">
          <%= for item <- @items do %>
            <% value = Map.fetch!(item, @value_key) %>
            <li>
              <.link
                navigate={"/@#{@username}/library/read?#{@filter_key}=#{URI.encode(item.slug || "")}"}
                class="group flex items-center"
              >
                <span class="w-[142px] truncate pr-3 text-sm font-medium transition-colors group-hover:text-[rgb(var(--text-link-hover))] md:w-[172px] md:pr-4 md:text-base">
                  {item.name}
                </span>
                <span class="relative flex min-w-0 flex-1 items-center">
                  <span
                    class="h-6 origin-left animate-[barGrow_900ms_cubic-bezier(0.16,1,0.3,1)_both] rounded-[4px] motion-reduce:animate-none lg:h-7"
                    style={"width: #{bar_width(value, @max_value)}%; background-color: #{@color}"}
                  />
                  <span class="flex items-center pl-2.5 text-sm font-medium tabular-nums max-md:text-xs">
                    {format_bar_value(value, @rating)}
                    <span :if={@rating} class="ml-1 text-[rgb(var(--icons-star-muted))]">★</span>
                  </span>
                </span>
              </.link>
            </li>
          <% end %>
        </ul>
      <% end %>
    </.chart_card>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :username, :string, required: true
  attr :filter_key, :string, required: true
  attr :center_label, :string, required: true

  def donut_section(assigns) do
    total = Enum.reduce(assigns.items, 0, &(&1.value + &2))

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:segments, donut_segments(assigns.items, total))

    ~H"""
    <.chart_card :if={@items != []} title={@title}>
      <div class="mt-8 flex items-center gap-8 px-[12px] max-lg:flex-col lg:mt-9 lg:px-0">
        <div class="relative h-[200px] w-[200px] shrink-0 rounded-full lg:h-[220px] lg:w-[220px]">
          <svg
            viewBox="0 0 220 220"
            class="absolute inset-0 size-full -rotate-90"
            role="img"
            aria-label={@title}
          >
            <circle
              cx="110"
              cy="110"
              r="91"
              fill="none"
              stroke="rgba(255,255,255,.10)"
              stroke-width="31"
            />
            <g class="kaguya-donut-sweep">
              <%= for segment <- @segments do %>
                <.link navigate={"/@#{@username}/library/read?#{@filter_key}=#{URI.encode(segment.key || "")}"}>
                  <circle
                    cx="110"
                    cy="110"
                    r="91"
                    fill="none"
                    stroke={segment.color}
                    stroke-width="31"
                    stroke-dasharray={"#{segment.dash} #{segment.gap}"}
                    stroke-dashoffset={segment.offset}
                    class="opacity-95 transition-opacity hover:opacity-80"
                  >
                    <title>
                      {segment.label}: {Format.integer(segment.value)} ({segment.percent}%)
                    </title>
                  </circle>
                </.link>
              <% end %>
            </g>
          </svg>
          <div class="pointer-events-none absolute inset-[14%] rounded-full bg-[rgb(var(--surface-base))]" />
          <div class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
            <span class="text-[32px] leading-none font-normal tabular-nums lg:text-[36px]">
              {Format.integer(@total)}
            </span>
            <span class="mt-1 text-sm text-[rgb(var(--foreground-quaternary))]">{@center_label}</span>
          </div>
        </div>

        <ul class="flex min-w-0 flex-col max-lg:w-full">
          <%= for segment <- @segments do %>
            <li>
              <.link
                navigate={"/@#{@username}/library/read?#{@filter_key}=#{URI.encode(segment.key || "")}"}
                class="group flex items-center gap-2 py-[5px]"
              >
                <span
                  class="size-2.5 shrink-0 rounded-[2px]"
                  style={"background-color: #{segment.color}"}
                />
                <span class="truncate text-sm transition-colors group-hover:text-[rgb(var(--text-link-hover))]">
                  {segment.label}
                </span>
                <span class="ml-auto shrink-0 text-sm text-[rgb(var(--foreground-secondary))] tabular-nums">
                  {Format.integer(segment.value)}
                </span>
                <span class="w-[38px] shrink-0 text-right text-xs text-[rgb(var(--foreground-quaternary))] tabular-nums">
                  {segment.percent}%
                </span>
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
    </.chart_card>
    """
  end
end
