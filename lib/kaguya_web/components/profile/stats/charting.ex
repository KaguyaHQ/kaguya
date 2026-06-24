defmodule KaguyaWeb.Components.Profile.Stats.Charting do
  @moduledoc """
  Stateless chart and display helpers for the profile stats page.
  """

  alias KaguyaWeb.Format

  @donut_colors ["#06D6A0", "#00BBF9", "#E879A0", "#FFD166", "#A78BFA", "#F97316"]

  def build_year_chart(titles_hist, hours_hist, score_hist, param_key) do
    titles = count_histogram(titles_hist)
    hours = hours_hist |> count_histogram() |> Enum.map(&%{&1 | value: round(&1.value / 60)})
    scores = float_histogram(score_hist)

    %{
      has_data?: titles != [] or hours != [] or scores != [],
      titles: titles,
      hours: hours,
      scores: scores,
      title_total: Enum.reduce(titles, 0, &(&1.value + &2)),
      hours_total: Enum.reduce(hours, 0, &(&1.value + &2)),
      mean_score: mean_score(scores),
      param_key: param_key
    }
  end

  def count_histogram(hist) when is_map(hist) do
    hist
    |> Enum.map(fn {period, value} -> %{period: to_string(period), value: numeric_int(value)} end)
    |> Enum.reject(&(&1.value <= 0))
    |> Enum.sort_by(&sort_period/1)
  end

  def count_histogram(_), do: []

  def float_histogram(hist) when is_map(hist) do
    hist
    |> Enum.map(fn {period, value} ->
      %{period: to_string(period), value: numeric_float(value)}
    end)
    |> Enum.reject(&(&1.value <= 0))
    |> Enum.sort_by(&sort_period/1)
  end

  def float_histogram(_), do: []

  defp sort_period(%{period: period}) do
    case Integer.parse(period) do
      {year, ""} -> {year, ""}
      {year, rest} -> {year, rest}
      _ -> {0, period}
    end
  end

  def chart_points([]), do: []

  def chart_points(rows) do
    width = 902
    height = 320
    pad_x = 28
    pad_top = 24
    pad_bottom = 58
    max_value = rows |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end) |> max(1)
    count = length(rows)

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      x =
        if count == 1 do
          div(width, 2)
        else
          pad_x + index * ((width - pad_x * 2) / (count - 1))
        end

      plot_height = height - pad_top - pad_bottom
      y = pad_top + (max_value - row.value) / max_value * plot_height

      %{x: Float.round(x / 1, 1), y: Float.round(y / 1, 1), label: row.period, value: row.value}
    end)
  end

  def area_path([]), do: ""

  def area_path(points) do
    first = List.first(points)
    last = List.last(points)
    baseline = 262

    smooth_path(points) <>
      " L #{last.x},#{baseline} L #{first.x},#{baseline} Z"
  end

  def smooth_path([]), do: ""

  def smooth_path([point]), do: "M #{point.x},#{point.y}"

  # Catmull-Rom-to-Bezier with tension=6 (default). For each segment P1→P2,
  # control points are derived from neighbours P0 and P3. Mirror endpoints
  # for the first/last segments to keep the curve smooth without overshoot.
  def smooth_path([first | _] = points) do
    tension = 6
    last_index = length(points) - 1

    indexed = Enum.with_index(points)

    segments =
      indexed
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map_join(" ", fn [{p1, i1}, {p2, _i2}] ->
        p0 = if i1 == 0, do: p1, else: Enum.at(points, i1 - 1)
        p3 = if i1 + 1 >= last_index, do: p2, else: Enum.at(points, i1 + 2)

        cp1x = p1.x + (p2.x - p0.x) / tension
        cp1y = p1.y + (p2.y - p0.y) / tension
        cp2x = p2.x - (p3.x - p1.x) / tension
        cp2y = p2.y - (p3.y - p1.y) / tension

        "C #{Float.round(cp1x / 1, 1)},#{Float.round(cp1y / 1, 1)} " <>
          "#{Float.round(cp2x / 1, 1)},#{Float.round(cp2y / 1, 1)} " <>
          "#{Float.round(p2.x / 1, 1)},#{Float.round(p2.y / 1, 1)}"
      end)

    "M #{first.x},#{first.y} " <> segments
  end

  def chart_metric_rows(chart, :titles), do: Map.get(chart, :titles, [])
  def chart_metric_rows(chart, :hours), do: Map.get(chart, :hours, [])
  def chart_metric_rows(chart, :scores), do: Map.get(chart, :scores, [])
  def chart_metric_rows(chart, _), do: Map.get(chart, :titles, [])

  def metric_tabs(chart) do
    [
      %{metric: :titles, label: "Titles Read", value: Format.integer(chart.title_total)},
      %{metric: :hours, label: "Hours Read", value: Format.integer(chart.hours_total)},
      %{metric: :scores, label: "Mean Rating", value: format_decimal(chart.mean_score, 2)}
    ]
  end

  def metric_label(:titles), do: "titles read"
  def metric_label(:hours), do: "hours read"
  def metric_label(:scores), do: "mean rating"
  def metric_label(_), do: "titles read"

  def format_chart_point_value(value, :scores), do: format_decimal(value, 1)
  def format_chart_point_value(value, _), do: Format.integer(value)

  defp mean_score([]), do: nil

  defp mean_score(scores) do
    scores
    |> Enum.map(& &1.value)
    |> Enum.sum()
    |> Kernel./(length(scores))
  end

  def bar_max([], _key, true), do: 5.0
  def bar_max([], _key, _rating), do: 0
  def bar_max(_items, _key, true), do: 5.0

  def bar_max(items, key, _rating),
    do: items |> Enum.map(&Map.get(&1, key, 0)) |> Enum.max(fn -> 0 end)

  def bar_height(0, _max), do: 1
  def bar_height(value, max) when max in [0, 0.0], do: if(value > 0, do: 100, else: 1)
  def bar_height(value, max), do: max(1, round(value / max * 100))

  def bar_min_height(0), do: "1px"
  def bar_min_height(_), do: "14px"

  def bar_width(0, _max), do: 0
  def bar_width(value, max) when max in [0, 0.0], do: if(value > 0, do: 100, else: 0)
  def bar_width(value, max), do: min(100, max(3, value / max * 83.25))

  def format_bar_value(value, true), do: format_decimal(value, 1)
  def format_bar_value(value, _), do: Format.integer(value)

  def format_decimal(nil, _decimals), do: "0"

  def format_decimal(value, decimals) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: decimals)
  end

  def format_decimal(value, _decimals), do: to_string(value)

  def pluralize(1, singular, _plural), do: singular
  def pluralize(_count, _singular, plural), do: plural

  defp numeric_int(value) when is_integer(value), do: value
  defp numeric_int(value) when is_float(value), do: round(value)
  defp numeric_int(%Decimal{} = value), do: value |> Decimal.to_integer()
  defp numeric_int(_), do: 0

  defp numeric_float(value) when is_integer(value), do: value * 1.0
  defp numeric_float(value) when is_float(value), do: value
  defp numeric_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric_float(_), do: 0.0

  def donut_segments(items, total) do
    circumference = 2 * :math.pi() * 91

    {_offset, segments} =
      items
      |> Enum.with_index()
      |> Enum.reduce({0.0, []}, fn {item, index}, {offset, acc} ->
        percent = if total == 0, do: 0.0, else: item.value / total * 100
        dash = circumference * percent / 100
        gap = circumference - dash

        segment =
          item
          |> Map.put(:color, Enum.at(@donut_colors, rem(index, length(@donut_colors))))
          |> Map.put(:percent, format_decimal(percent, 1))
          |> Map.put(:dash, Float.round(dash, 2))
          |> Map.put(:gap, Float.round(gap, 2))
          |> Map.put(:offset, Float.round(-offset, 2))

        {offset + dash, [segment | acc]}
      end)

    Enum.reverse(segments)
  end
end
