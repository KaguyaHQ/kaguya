defmodule KaguyaWeb.Components.Profile.Stats.YearChart do
  @moduledoc """
  Year-over-year line chart component for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Stats.Charting
  import KaguyaWeb.Components.Profile.Stats.Primitives

  attr :title, :string, required: true
  attr :color, :string, required: true
  attr :username, :string, required: true
  attr :year_param, :string, required: true
  attr :chart_key, :string, required: true
  attr :active_metric, :atom, required: true
  attr :chart, :map, required: true

  def year_chart(assigns) do
    rows = chart_metric_rows(assigns.chart, assigns.active_metric)

    points =
      rows
      |> chart_points()
      |> Enum.map(&Map.put(&1, :href, "?#{assigns.year_param}=#{&1.label}"))

    assigns =
      assigns
      |> assign(:points, points)
      |> assign(:area_path, area_path(points))
      |> assign(:smooth_path, smooth_path(points))
      |> assign(:metric_tabs, metric_tabs(assigns.chart))
      |> assign(:active_label, metric_label(assigns.active_metric))

    ~H"""
    <div class="px-0 py-4 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:p-0">
      <div class="flex items-center justify-between gap-2">
        <h2 class="shrink-0 text-xl/6 font-normal text-[rgb(var(--foreground-primary))] lg:font-medium">
          {@title}
        </h2>
        <div class="flex shrink-0 items-center gap-1.5">
          <.metric_pill
            :for={tab <- @metric_tabs}
            chart_key={@chart_key}
            metric={tab.metric}
            color={@color}
            label={tab.label}
            value={tab.value}
            active={@active_metric == tab.metric}
          />
        </div>
      </div>
      <div class="mt-3 h-px bg-[rgb(var(--border-divider))] max-lg:hidden" />

      <%= if @points != [] do %>
        <div class="mt-4 overflow-x-auto">
          <svg
            viewBox="0 0 902 320"
            class="h-[260px] w-full min-w-[680px] lg:h-[330px]"
            role="img"
            aria-label={"#{@title} chart"}
          >
            <defs>
              <linearGradient
                id={"stats-fill-#{String.replace(@title, " ", "-")}"}
                x1="0"
                y1="0"
                x2="0"
                y2="1"
              >
                <stop offset="0%" stop-color={@color} stop-opacity="0.30" />
                <stop offset="100%" stop-color={@color} stop-opacity="0.05" />
              </linearGradient>
            </defs>
            <line x1="28" y1="262" x2="874" y2="262" stroke="rgba(255,255,255,.16)" stroke-width="1" />
            <path d={@area_path} fill={"url(#stats-fill-#{String.replace(@title, " ", "-")})"} />
            <path
              :if={length(@points) > 1}
              d={@smooth_path}
              fill="none"
              stroke={@color}
              stroke-width="3"
              stroke-linejoin="round"
              stroke-linecap="round"
            />
            <%= for point <- @points do %>
              <.link navigate={"/@#{@username}/library/read#{point.href}"} class="group/year-point">
                <circle cx={point.x} cy={point.y} r="7" fill={@color} opacity="0.18" />
                <circle
                  cx={point.x}
                  cy={point.y}
                  r="4.5"
                  fill={@color}
                  stroke={@color}
                  stroke-width="2"
                >
                  <title>
                    {@title} {point.label}: {format_chart_point_value(point.value, @active_metric)} {@active_label}
                  </title>
                </circle>
              </.link>
              <text
                x={point.x}
                y="296"
                text-anchor="middle"
                fill="rgb(var(--foreground-secondary))"
                font-size="12"
                font-weight="600"
              >
                {point.label}
              </text>
              <text
                x={point.x}
                y={point.y - 13}
                text-anchor="middle"
                fill="rgb(var(--foreground-primary))"
                font-size="12"
                font-weight="700"
              >
                {format_chart_point_value(point.value, @active_metric)}
              </text>
            <% end %>
          </svg>
        </div>
      <% else %>
        <.empty_chart height="h-[139px] lg:h-[227px]" />
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :chart_key, :string, required: true
  attr :metric, :atom, required: true
  attr :color, :string, default: nil
  attr :active, :boolean, default: false

  defp metric_pill(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_stats_metric"
      phx-value-chart={@chart_key}
      phx-value-metric={@metric}
      class={[
        "rounded-full px-2.5 py-1 text-[11px] font-medium transition-colors",
        @active && "font-semibold text-white",
        !@active &&
          "text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
      ]}
      style={if @active, do: "background-color: #{@color}"}
    >
      {@label}
    </button>
    """
  end
end
