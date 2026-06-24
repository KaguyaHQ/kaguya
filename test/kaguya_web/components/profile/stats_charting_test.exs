defmodule KaguyaWeb.Components.Profile.Stats.ChartingTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Components.Profile.Stats.Charting

  describe "histograms" do
    test "normalizes, filters, and sorts count histograms" do
      assert [
               %{period: "2023", value: 2},
               %{period: "2024", value: 4}
             ] =
               Charting.count_histogram(%{
                 "2024" => 4,
                 "2022" => 0,
                 2023 => 2,
                 "bad" => -1
               })
    end

    test "normalizes float histograms including decimals" do
      assert [
               %{period: "2024", value: 4.5}
             ] = Charting.float_histogram(%{"2024" => Decimal.new("4.5"), "2025" => 0})
    end
  end

  describe "year charts" do
    test "converts read minutes to rounded hours" do
      chart =
        Charting.build_year_chart(%{"2024" => 2}, %{"2024" => 125}, %{"2024" => 4.25}, "readYear")

      assert chart.title_total == 2
      assert chart.hours_total == 2
      assert chart.mean_score == 4.25
      assert [%{period: "2024", value: 2}] = chart.hours
    end

    test "builds paths for single and multi-point charts" do
      one = Charting.chart_points([%{period: "2024", value: 2}])
      many = Charting.chart_points([%{period: "2023", value: 1}, %{period: "2024", value: 2}])

      assert [%{x: 451.0, label: "2024"}] = one
      assert Charting.smooth_path(one) =~ "M "
      assert Charting.area_path(many) =~ " Z"
    end
  end

  describe "donuts" do
    test "assigns deterministic percentages and colors" do
      [first, second] =
        Charting.donut_segments(
          [
            %{key: "en", label: "English", value: 1},
            %{key: "ja", label: "Japanese", value: 3}
          ],
          4
        )

      assert first.percent == "25.0"
      assert first.color == "#06D6A0"
      assert second.percent == "75.0"
      assert second.color == "#00BBF9"
    end
  end
end
