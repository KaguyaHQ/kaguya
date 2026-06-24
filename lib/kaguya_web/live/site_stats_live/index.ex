defmodule KaguyaWeb.SiteStatsLive.Index do
  use KaguyaWeb, :live_view

  alias Kaguya.SiteStats

  @description "How Kaguya is growing — daily counts of ratings, logged entries, reviews, users, and catalog coverage."
  @mau_goal 4_000
  @chart_width_per_point 56
  @chart_min_width 760
  @chart_height 180
  @plot_top 26
  @plot_bottom 140
  @plot_left 24
  @plot_right 24

  @public_charts [
    %{key: :users_count, label: "Users", color: "#f5a524", decimals: 1},
    %{key: :reviews_count, label: "Reviews", color: "#06d6a0", decimals: 0},
    %{key: :ratings_count, label: "Ratings", color: "#7c5cff", decimals: 0},
    %{key: :reading_statuses_count, label: "Logged", color: "#00bbf9", decimals: 0}
  ]

  @admin_charts [
    %{
      key: :mau_30d_count,
      label: "Monthly Active Users",
      color: "#5bb98b",
      goal: @mau_goal,
      decimals: 0
    },
    %{key: :dau_count, label: "Daily Active Users", color: "#fb7185", decimals: 0}
  ]

  @impl true
  def mount(_params, _session, socket) do
    history = SiteStats.history()
    charts = charts_for(history, admin?(socket.assigns.current_user))

    {:ok,
     socket
     |> assign(:page_title, "Stats - Kaguya")
     |> assign(:meta_description, @description)
     |> assign(:og_description, @description)
     |> assign(:charts, charts)
     |> assign(:history, history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-foreground-primary pb-24">
      <div class="mx-auto max-w-[800px] px-4 pt-10 sm:px-6 lg:pt-16">
        <%= if @history == [] do %>
          <section class="bg-surface-elevated/35 border-border-divider/60 rounded-[8px] border px-5 py-6">
            <h1 class="text-foreground-primary text-style-heading3Medium">Stats</h1>
            <p class="text-foreground-secondary text-style-body2Regular mt-2">
              Site stats are not available yet. The daily snapshot worker populates this page after it runs.
            </p>
          </section>
        <% else %>
          <div class="space-y-10 sm:space-y-12">
            <.stat_chart :for={chart <- @charts} chart={chart} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :chart, :map, required: true

  defp stat_chart(assigns) do
    assigns =
      assigns
      |> assign(:latest, List.last(assigns.chart.points))
      |> assign(:previous, previous_point(assigns.chart.points))
      |> assign(:width, chart_width(assigns.chart.points))
      |> assign(:path, chart_path(assigns.chart.points))
      |> assign(:area_path, chart_area_path(assigns.chart.points))
      |> assign(:gradient_id, "site-stats-grad-#{assigns.chart.key}")

    ~H"""
    <section class="space-y-3">
      <div class="flex items-baseline justify-between gap-4 pr-3">
        <h3
          class="text-foreground-primary text-base leading-none font-medium tracking-tight tabular-nums"
          title={format_full(@latest.value)}
        >
          {format_compact(@latest.value, @chart.decimals)} {@chart.label}
          <span
            :if={Map.get(@chart, :goal)}
            class="text-progress-reading-progress ml-2 text-sm font-semibold tracking-tight"
          >
            of {format_full(@chart.goal)} goal
          </span>
        </h3>

        <div class={[
          "shrink-0 text-xs font-semibold tabular-nums",
          delta_class(@latest.value - @previous.value)
        ]}>
          {format_delta(@latest.value - @previous.value)}
        </div>
      </div>

      <div class="chart-scrollbar overflow-x-auto select-none">
        <svg
          viewBox={"0 0 #{@width} #{@chart.height}"}
          width={@width}
          height={@chart.height}
          role="img"
          aria-label={"#{@chart.label} trend over the last #{length(@chart.points)} days"}
          class="min-w-full"
          style={"width: #{@width}px; height: #{@chart.height}px;"}
        >
          <defs>
            <linearGradient id={@gradient_id} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color={@chart.color} stop-opacity="0.32" />
              <stop offset="100%" stop-color={@chart.color} stop-opacity="0" />
            </linearGradient>
          </defs>

          <path d={@area_path} fill={"url(##{@gradient_id})"} />
          <path
            d={@path}
            fill="none"
            stroke={@chart.color}
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />

          <g :for={point <- @chart.points}>
            <line
              x1={point.x}
              x2={point.x}
              y1={@chart.plot_bottom + 8}
              y2={@chart.plot_bottom + 12}
              stroke="currentColor"
              class="text-foreground-tertiary/50"
              stroke-width="1"
            />
            <text
              x={point.x}
              y={@chart.plot_bottom + 28}
              text-anchor="middle"
              class="fill-foreground-tertiary"
              font-size="10"
              font-weight="500"
            >
              {format_ordinal_day(point.date)}
            </text>
            <text
              x={point.x}
              y={point.y - 10}
              text-anchor="middle"
              class="fill-foreground-secondary"
              font-size="10"
              font-weight="500"
            >
              {point.value}
            </text>
            <circle cx={point.x} cy={point.y} r="3" fill={@chart.color}>
              <title>{format_long_date(point.date)}: {format_full(point.value)} {@chart.label}</title>
            </circle>
          </g>
        </svg>
      </div>
    </section>
    """
  end

  defp charts_for(history, include_admin?) do
    specs = if include_admin?, do: @admin_charts ++ @public_charts, else: @public_charts

    specs
    |> Enum.map(fn spec ->
      spec
      |> Map.put(:height, @chart_height)
      |> Map.put(:plot_bottom, @plot_bottom)
      |> Map.put(:points, chart_points(history, spec.key))
    end)
    |> Enum.reject(&(&1.points == []))
  end

  defp chart_points(history, key) do
    values = Enum.map(history, &Map.get(&1, key, 0))
    min = Enum.min(values, fn -> 0 end)
    max = Enum.max(values, fn -> 1 end)
    span = max - min
    y_min = max(min - max(round(span * 0.05), 1), 0)
    y_max = max + max(round(span * 0.15), max(round(max * 0.02), 1))
    width = chart_width(history)
    x_span = max(width - @plot_left - @plot_right, 1)
    y_span = max(@plot_bottom - @plot_top, 1)
    count = max(length(history) - 1, 1)

    history
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      value = Map.get(row, key, 0)
      x = @plot_left + x_span * index / count
      ratio = if y_max == y_min, do: 0.5, else: (value - y_min) / (y_max - y_min)
      y = @plot_bottom - ratio * y_span

      %{
        date: row.date,
        value: value,
        x: Float.round(x, 2),
        y: Float.round(y, 2)
      }
    end)
  end

  defp chart_path([]), do: ""

  defp chart_path([first | rest]) do
    ["M #{first.x} #{first.y}" | Enum.map(rest, &"L #{&1.x} #{&1.y}")]
    |> Enum.join(" ")
  end

  defp chart_area_path([]), do: ""

  defp chart_area_path(points) do
    first = List.first(points)
    last = List.last(points)
    "#{chart_path(points)} L #{last.x} #{@plot_bottom} L #{first.x} #{@plot_bottom} Z"
  end

  defp previous_point([point]), do: point
  defp previous_point(points), do: Enum.at(points, -2)

  defp chart_width(points_or_history) do
    max(@chart_min_width, length(points_or_history) * @chart_width_per_point)
  end

  defp admin?(%{role: role}) when role in [:admin, "admin"], do: true
  defp admin?(_), do: false

  defp format_compact(number, 1) when number >= 1_000_000, do: "#{floor(number / 100_000) / 10}M"
  defp format_compact(number, 1) when number >= 1_000, do: "#{floor(number / 100) / 10}K"

  defp format_compact(number, _decimals) when number >= 1_000_000,
    do: "#{div(number, 1_000_000)}M"

  defp format_compact(number, _decimals) when number >= 1_000, do: "#{div(number, 1_000)}K"
  defp format_compact(number, _decimals), do: Integer.to_string(number)

  defp format_full(number),
    do: number |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp format_delta(0), do: "+0"
  defp format_delta(number) when number > 0, do: "+#{format_full(number)}"
  defp format_delta(number), do: "-#{format_full(abs(number))}"

  defp delta_class(number) when number > 0, do: "text-emerald-400"
  defp delta_class(number) when number < 0, do: "text-rose-400"
  defp delta_class(_), do: "text-foreground-tertiary"

  defp format_long_date(%Date{} = date) do
    Calendar.strftime(date, "%B %-d, %Y")
  end

  defp format_ordinal_day(%Date{} = date) do
    day = date.day
    "#{day}#{ordinal_suffix(day)}"
  end

  defp ordinal_suffix(day) when rem(day, 100) in 11..13, do: "th"

  defp ordinal_suffix(day) do
    case rem(day, 10) do
      1 -> "st"
      2 -> "nd"
      3 -> "rd"
      _ -> "th"
    end
  end
end
