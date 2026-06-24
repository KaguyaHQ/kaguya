defmodule KaguyaWeb.SharedComponents.Time do
  @moduledoc """
  Shared date labels for relative and absolute timestamps.
  """

  @month_names ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @full_month_names ~w(January February March April May June July August September October November December)
  @weekday_names ~w(Mon Tue Wed Thu Fri Sat Sun)

  def calendar_custom(value, opts \\ [])

  def calendar_custom(nil, _opts), do: "recently"

  def calendar_custom(value, opts) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        calendar_custom(datetime, opts)

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, datetime} -> calendar_custom(datetime, opts)
          _ -> "recently"
        end
    end
  end

  def calendar_custom(%NaiveDateTime{} = datetime, opts) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> calendar_custom(opts)
  end

  def calendar_custom(%DateTime{} = datetime, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    with_ago? = Keyword.get(opts, :with_ago, false)
    seconds = DateTime.diff(now, datetime, :second)
    now_date = DateTime.to_date(now)
    then_date = DateTime.to_date(datetime)

    cond do
      now_date == then_date and seconds <= 10 ->
        if with_ago?, do: "now", else: "Now"

      now_date == then_date and seconds < 3_600 ->
        minutes = max(DateTime.diff(now, datetime, :minute), 1)
        "#{minutes}m#{ago_suffix(with_ago?)}"

      now_date == then_date ->
        hours = DateTime.diff(now, datetime, :hour)
        "#{hours}h#{ago_suffix(with_ago?)}"

      Date.diff(now_date, then_date) == 1 ->
        "Yesterday"

      Date.diff(now_date, then_date) in 2..6 ->
        weekday_name(then_date)

      now_date.year == then_date.year ->
        "#{month_name(then_date)} #{then_date.day}"

      true ->
        "#{month_name(then_date)} #{then_date.day}, #{then_date.year}"
    end
  end

  def calendar_custom(_value, _opts), do: "recently"

  def calendar_short(value, opts \\ [])

  def calendar_short(nil, _opts), do: "recently"

  def calendar_short(%NaiveDateTime{} = datetime, opts) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> calendar_short(opts)
  end

  def calendar_short(%DateTime{} = datetime, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    with_ago? = Keyword.get(opts, :with_ago, false)

    cond do
      DateTime.diff(now, datetime, :second) < 60 ->
        "#{max(DateTime.diff(now, datetime, :second), 1)}s#{ago_suffix(with_ago?)}"

      DateTime.diff(now, datetime, :minute) < 60 ->
        "#{DateTime.diff(now, datetime, :minute)}min#{ago_suffix(with_ago?)}"

      DateTime.diff(now, datetime, :hour) < 24 ->
        "#{DateTime.diff(now, datetime, :hour)}hr#{ago_suffix(with_ago?)}"

      DateTime.diff(now, datetime, :day) < 7 ->
        "#{DateTime.diff(now, datetime, :day)}d#{ago_suffix(with_ago?)}"

      div(DateTime.diff(now, datetime, :day), 7) < 4 ->
        "#{div(DateTime.diff(now, datetime, :day), 7)}wk#{ago_suffix(with_ago?)}"

      month_diff(now, datetime) < 12 ->
        "#{month_diff(now, datetime)}mo#{ago_suffix(with_ago?)}"

      true ->
        "#{now.year - datetime.year}yr#{ago_suffix(with_ago?)}"
    end
  end

  def calendar_short(value, opts) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> calendar_short(datetime, opts)
      _ -> "recently"
    end
  end

  def calendar_short(_value, _opts), do: "recently"

  def datetime_title(nil), do: nil
  def datetime_title(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def datetime_title(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  def datetime_title(value) when is_binary(value), do: value
  def datetime_title(_value), do: nil

  @doc """
  Formats a date as `D MMM YYYY` (e.g. `15 Mar 2024`).

  Accepts ISO date or
  datetime strings, `Date`, `NaiveDateTime`, and `DateTime`. Returns `nil`
  for unparseable input so callers can decide how to render the absence.
  """
  def format_short_date(nil), do: nil

  def format_short_date(%Date{} = date) do
    "#{date.day} #{month_name(date)} #{date.year}"
  end

  def format_short_date(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> format_short_date()
  end

  def format_short_date(%NaiveDateTime{} = datetime) do
    datetime |> NaiveDateTime.to_date() |> format_short_date()
  end

  def format_short_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        format_short_date(date)

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> format_short_date(datetime)
          _ -> nil
        end
    end
  end

  def format_short_date(_value), do: nil

  @doc """
  Formats a date as `MMMM D, YYYY` (e.g. `March 15, 2024`).
  """
  def format_long_date(nil), do: nil

  def format_long_date(%Date{} = date) do
    "#{full_month_name(date)} #{date.day}, #{date.year}"
  end

  def format_long_date(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> format_long_date()

  def format_long_date(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.to_date() |> format_long_date()

  def format_long_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        format_long_date(date)

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> format_long_date(datetime)
          _ -> nil
        end
    end
  end

  def format_long_date(_value), do: nil

  @doc """
  Formats a datetime as `MMMM D, YYYY [at] h:mm A` (e.g. `March 15, 2024 at 3:30 PM`).

  Used by `DateTooltip`. Useful for hover tooltips on `<time>` elements.
  """
  def format_datetime_tooltip(nil), do: nil

  def format_datetime_tooltip(%DateTime{} = datetime) do
    "#{format_long_date(datetime)} at #{format_time_12h(datetime)}"
  end

  def format_datetime_tooltip(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> format_datetime_tooltip()

  def format_datetime_tooltip(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_datetime_tooltip(datetime)
      _ -> nil
    end
  end

  def format_datetime_tooltip(_value), do: nil

  @doc """
  Formats a datetime as `MMM D, YYYY HH:mm` (e.g. `Mar 15, 2024 15:30`).

  Used in the changes log and activity log entry tooltips.
  """
  def format_datetime_short(nil), do: nil

  def format_datetime_short(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    "#{month_name(date)} #{date.day}, #{date.year} #{format_time_24h(datetime)}"
  end

  def format_datetime_short(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> format_datetime_short()

  def format_datetime_short(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_datetime_short(datetime)
      _ -> nil
    end
  end

  def format_datetime_short(_value), do: nil

  @doc """
  Formats a datetime's time-of-day as `HH:mm` (24-hour, e.g. `15:30`).

  Used by activity log entries.
  """
  def format_time_24h(nil), do: nil

  def format_time_24h(%DateTime{} = datetime) do
    "#{pad2(datetime.hour)}:#{pad2(datetime.minute)}"
  end

  def format_time_24h(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> format_time_24h()

  def format_time_24h(_value), do: nil

  @doc """
  Formats a datetime's time-of-day as `h:mm A` (12-hour with AM/PM, e.g. `3:30 PM`).
  """
  def format_time_12h(nil), do: nil

  def format_time_12h(%DateTime{} = datetime) do
    {hour_12, period} = to_12h(datetime.hour)
    "#{hour_12}:#{pad2(datetime.minute)} #{period}"
  end

  def format_time_12h(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> format_time_12h()

  def format_time_12h(_value), do: nil

  @doc """
  Returns the year as a string (e.g. `2024`).
  """
  def format_year(%Date{year: year}), do: Integer.to_string(year)
  def format_year(%DateTime{year: year}), do: Integer.to_string(year)
  def format_year(%NaiveDateTime{year: year}), do: Integer.to_string(year)
  def format_year(_), do: nil

  @doc """
  Returns the abbreviated month name (e.g. `Mar`).
  """
  def format_month_short(%Date{} = date), do: month_name(date)
  def format_month_short(%DateTime{} = dt), do: dt |> DateTime.to_date() |> format_month_short()

  def format_month_short(%NaiveDateTime{} = dt),
    do: dt |> NaiveDateTime.to_date() |> format_month_short()

  def format_month_short(_), do: nil

  defp ago_suffix(true), do: " ago"
  defp ago_suffix(false), do: ""

  defp month_name(%Date{month: month}) do
    Enum.at(@month_names, month - 1)
  end

  defp full_month_name(%Date{month: month}) do
    Enum.at(@full_month_names, month - 1)
  end

  defp weekday_name(date) do
    Enum.at(@weekday_names, Date.day_of_week(date) - 1)
  end

  defp month_diff(now, then) do
    years = now.year - then.year
    months = now.month - then.month
    max(years * 12 + months, 0)
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)

  defp to_12h(0), do: {12, "AM"}
  defp to_12h(12), do: {12, "PM"}
  defp to_12h(h) when h < 12, do: {h, "AM"}
  defp to_12h(h), do: {h - 12, "PM"}
end
