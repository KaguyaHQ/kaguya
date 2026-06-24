defmodule KaguyaWeb.SharedComponents.TimeTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.SharedComponents.Time

  @now ~U[2026-05-12 12:00:00Z]

  test "calendar_custom matches production same-day labels" do
    assert Time.calendar_custom(~U[2026-05-12 11:59:55Z], now: @now) == "Now"
    assert Time.calendar_custom(~U[2026-05-12 11:45:00Z], now: @now) == "15m"
    assert Time.calendar_custom(~U[2026-05-12 09:00:00Z], now: @now) == "3h"
    assert Time.calendar_custom(~U[2026-05-12 09:00:00Z], now: @now, with_ago: true) == "3h ago"
  end

  test "calendar_custom matches production calendar labels" do
    assert Time.calendar_custom(~U[2026-05-11 21:00:00Z], now: @now) == "Yesterday"
    assert Time.calendar_custom(~U[2026-05-10 21:00:00Z], now: @now) == "Sun"
    assert Time.calendar_custom(~U[2026-04-20 21:00:00Z], now: @now) == "Apr 20"
    assert Time.calendar_custom(~U[2025-04-20 21:00:00Z], now: @now) == "Apr 20, 2025"
  end

  test "calendar_short matches production compact labels" do
    assert Time.calendar_short(~U[2026-05-12 11:59:55Z], now: @now) == "5s"
    assert Time.calendar_short(~U[2026-05-12 11:45:00Z], now: @now) == "15min"
    assert Time.calendar_short(~U[2026-05-12 00:00:00Z], now: @now) == "12hr"
    assert Time.calendar_short(~U[2026-05-09 12:00:00Z], now: @now) == "3d"
    assert Time.calendar_short(~U[2026-04-18 12:00:00Z], now: @now) == "3wk"
    assert Time.calendar_short(~U[2026-04-14 12:00:00Z], now: @now) == "1mo"
    assert Time.calendar_short(~U[2025-05-12 12:00:00Z], now: @now) == "1yr"
    assert Time.calendar_short(~U[2026-05-12 11:45:00Z], now: @now, with_ago: true) == "15min ago"
  end
end
