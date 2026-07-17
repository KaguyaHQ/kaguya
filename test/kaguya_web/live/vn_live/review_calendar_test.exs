defmodule KaguyaWeb.VNLive.ReviewCalendarTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.VNLive.Show.ReviewCalendar

  describe "compute_dates/4 — a set read date is never demoted" do
    test "clicking an earlier day adds the start date and keeps the read date" do
      assert {"2023-12-15", "2024-01-01"} =
               ReviewCalendar.compute_dates("READ", nil, "2024-01-01", "2023-12-15")
    end

    test "clicking a later day restates the read date rather than demoting it" do
      # The old behavior built a range here, sliding date_finished forward to the
      # clicked day and burying the real read date in date_started — which is how
      # an entry read years ago resurfaced at the top of Recently Read.
      assert {nil, "2024-03-09"} =
               ReviewCalendar.compute_dates("READ", nil, "2024-01-01", "2024-03-09")
    end

    test "clicking the read date again clears both dates" do
      assert {nil, nil} =
               ReviewCalendar.compute_dates("READ", nil, "2024-01-01", "2024-01-01")
    end
  end

  describe "compute_dates/4 — start-date side" do
    test "clicking a later day closes the range" do
      assert {"2024-01-01", "2024-01-20"} =
               ReviewCalendar.compute_dates("READ", "2024-01-01", nil, "2024-01-20")
    end

    test "clicking an earlier day restates the start date for an in-progress read" do
      assert {"2023-11-05", nil} =
               ReviewCalendar.compute_dates("CURRENTLY_READING", "2024-01-01", nil, "2023-11-05")
    end
  end

  describe "compute_dates/4 — unchanged behaviors" do
    test "a first pick on an empty entry sets the read date" do
      assert {nil, "2024-05-05"} = ReviewCalendar.compute_dates("READ", nil, nil, "2024-05-05")
    end

    test "a first pick on an in-progress entry sets the start date" do
      assert {"2024-05-05", nil} =
               ReviewCalendar.compute_dates("CURRENTLY_READING", nil, nil, "2024-05-05")
    end

    test "picking with a full range already set starts over from that day" do
      assert {nil, "2024-06-01"} =
               ReviewCalendar.compute_dates("READ", "2024-01-01", "2024-01-10", "2024-06-01")
    end
  end
end
