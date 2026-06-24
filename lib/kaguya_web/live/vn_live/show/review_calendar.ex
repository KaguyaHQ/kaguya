defmodule KaguyaWeb.VNLive.Show.ReviewCalendar do
  @moduledoc false

  def put_review_date(form, "") do
    form
    |> Map.put("date_started", "")
    |> Map.put("date_finished", "")
  end

  def put_review_date(form, date) do
    case Date.from_iso8601(to_string(date)) do
      {:ok, parsed} ->
        started = parse_review_date(form["date_started"])
        finished = parse_review_date(form["date_finished"])

        cond do
          started && finished ->
            put_single_review_date(form, parsed)

          started ->
            if Date.compare(parsed, started) == :eq do
              clear_review_dates(form)
            else
              put_review_date_range(form, started, parsed)
            end

          finished ->
            if Date.compare(parsed, finished) == :eq do
              clear_review_dates(form)
            else
              put_review_date_range(form, finished, parsed)
            end

          true ->
            put_single_review_date(form, parsed)
        end

      _ ->
        form
    end
  end

  defp put_single_review_date(form, %Date{} = date) do
    field = date_field_for_status(form["status"])
    iso_date = Date.to_iso8601(date)

    form
    |> Map.put("date_started", if(field == "date_started", do: iso_date, else: ""))
    |> Map.put("date_finished", if(field == "date_finished", do: iso_date, else: ""))
  end

  def clear_review_dates(form) do
    form
    |> Map.put("date_started", "")
    |> Map.put("date_finished", "")
  end

  def put_review_date_range(form, %Date{} = first, %Date{} = second) do
    {started, finished} =
      case Date.compare(first, second) do
        :gt -> {second, first}
        _ -> {first, second}
      end

    form
    |> Map.put("date_started", Date.to_iso8601(started))
    |> Map.put("date_finished", Date.to_iso8601(finished))
  end

  def date_field_for_status(status)
      when status in ["CURRENTLY_READING", "ON_HOLD", "DID_NOT_FINISH"],
      do: "date_started"

  def date_field_for_status(_status), do: "date_finished"

  @doc """
  Computes the next (date_started, date_finished) pair when the user picks
  `picked_iso` given the existing dates and status. Same behavior as
  `put_review_date/2` but returns a tuple of nullable ISO strings instead of
  mutating a form map. Suitable for consumers outside the review flow.
  """
  def compute_dates(status, started, finished, picked_iso) do
    form = %{
      "status" => status || "READ",
      "date_started" => started || "",
      "date_finished" => finished || ""
    }

    form = put_review_date(form, picked_iso)
    {empty_to_nil(form["date_started"]), empty_to_nil(form["date_finished"])}
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  def review_date_month(form) do
    form
    |> selected_review_date()
    |> case do
      nil ->
        month_start(Date.utc_today())

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> month_start(date)
          _ -> month_start(Date.utc_today())
        end
    end
  end

  def selected_review_date(form) do
    [form["date_started"], form["date_finished"]]
    |> Enum.find(fn value -> is_binary(value) and value != "" end)
  end

  def parse_review_date(value) do
    case Date.from_iso8601(to_string(value || "")) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  def review_date_label(form) do
    status = form["status"] || "READ"
    started = form["date_started"]
    finished = form["date_finished"]

    cond do
      present_date?(started) and present_date?(finished) ->
        "Read #{format_review_date(started)} – #{format_review_date(finished)}"

      present_date?(finished) ->
        "Read #{format_review_date(finished)}"

      present_date?(started) ->
        "#{review_date_prefix(status)} #{format_review_date(started)}"

      true ->
        "#{review_date_prefix(status)} Add dates"
    end
  end

  def review_date_prefix(status)
      when status in ["CURRENTLY_READING", "ON_HOLD", "DID_NOT_FINISH"],
      do: "Started"

  def review_date_prefix(_status), do: "Read"

  def present_date?(value), do: is_binary(value) and value != ""
  def present_text?(value), do: is_binary(value) and String.trim(value) != ""

  def format_review_date(%Date{} = date),
    do: "#{date.day} #{month_name(date.month)} #{date.year}"

  def format_review_date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> "#{date.day} #{month_name(date.month)} #{date.year}"
      _ -> "Add dates"
    end
  end

  def calendar_selected?(day, started, finished),
    do:
      calendar_selected_edge?(day, started, finished) ||
        calendar_range_middle?(day, started, finished)

  def calendar_selected_edge?(day, started, finished) do
    (!!started && Date.compare(day, started) == :eq) ||
      (!!finished && Date.compare(day, finished) == :eq)
  end

  def calendar_range_middle?(day, %Date{} = started, %Date{} = finished) do
    Date.compare(day, started) == :gt && Date.compare(day, finished) == :lt
  end

  def calendar_range_middle?(_day, _started, _finished), do: false

  def calendar_today?(day, today, started, finished),
    do: Date.compare(day, today) == :eq && !calendar_selected?(day, started, finished)

  def review_calendar_days(month) do
    first = month_start(month)
    sunday_offset = rem(Date.day_of_week(first), 7)
    start_date = Date.add(first, -sunday_offset)

    Enum.map(0..41, &Date.add(start_date, &1))
  end

  def shift_month(date, delta) do
    date = month_start(date)
    month_index = date.year * 12 + (date.month - 1) + delta
    year = floor_div(month_index, 12)
    month = Integer.mod(month_index, 12) + 1

    Date.new!(year, month, 1)
  end

  def month_start(%Date{} = date), do: Date.new!(date.year, date.month, 1)
  def month_start(_), do: month_start(Date.utc_today())

  def floor_div(value, divisor) when value >= 0, do: div(value, divisor)
  def floor_div(value, divisor), do: div(value - divisor + 1, divisor)

  def month_name(1), do: "Jan"
  def month_name(2), do: "Feb"
  def month_name(3), do: "Mar"
  def month_name(4), do: "Apr"
  def month_name(5), do: "May"
  def month_name(6), do: "Jun"
  def month_name(7), do: "Jul"
  def month_name(8), do: "Aug"
  def month_name(9), do: "Sep"
  def month_name(10), do: "Oct"
  def month_name(11), do: "Nov"
  def month_name(12), do: "Dec"
end
