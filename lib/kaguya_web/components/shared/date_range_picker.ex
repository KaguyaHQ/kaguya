defmodule KaguyaWeb.SharedComponents.DateRangePicker do
  @moduledoc """
  Reusable read-dates calendar. Renders just the grid — the consumer wraps it
  in a disclosure popover (`KaguyaWeb.UI.Menu` or a server-driven `:if`
  panel) for trigger + positioning + open/close, which keeps interaction
  parity with every other popover on the page (Change status, Edit labels, etc.).

  Parent passes the current `date_started`, `date_finished`, `status`, and a
  `notify` atom. When the user clicks a day, the component computes the new
  date pair via `ReviewCalendar.compute_dates/4` and sends
  `{tag, id, %{date_started: ..., date_finished: ..., picked: iso}}` to the
  parent LiveView's `handle_info/2`. The parent persists and re-renders the
  component with the new dates.

  Includes dropdown month/year navigation.
  """

  use KaguyaWeb, :live_component

  alias KaguyaWeb.VNLive.Show.ReviewCalendar

  # How many years back the year dropdown can reach. People log books read
  # decades ago, so we go further than the typical "5 years back".
  @year_lookback 50
  @year_lookahead 1

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:month, nil)
     |> assign(:pending_started, :unset)
     |> assign(:pending_finished, :unset)}
  end

  @impl true
  def update(assigns, socket) do
    previous_started = socket.assigns[:date_started]
    previous_finished = socket.assigns[:date_finished]

    socket =
      socket
      |> assign_new(:status, fn -> "READ" end)
      |> assign_new(:date_started, fn -> nil end)
      |> assign_new(:date_finished, fn -> nil end)
      |> assign_new(:notify, fn -> :date_range_picker_changed end)
      |> assign(assigns)

    # When the parent finally re-renders with the dates we optimistically applied
    # locally, drop the pending overlay so the canonical assigns own the view
    # again. Pre-set we hold `:unset` and never clear from the parent's render
    # cycle.
    pending_started =
      if dates_changed?(previous_started, socket.assigns.date_started),
        do: :unset,
        else: socket.assigns.pending_started

    pending_finished =
      if dates_changed?(previous_finished, socket.assigns.date_finished),
        do: :unset,
        else: socket.assigns.pending_finished

    month = socket.assigns.month || default_month(socket.assigns)

    {:ok,
     socket
     |> assign(:month, month)
     |> assign(:pending_started, pending_started)
     |> assign(:pending_finished, pending_finished)}
  end

  defp dates_changed?(nil, nil), do: false
  defp dates_changed?(a, b) when a == b, do: false
  defp dates_changed?(_, _), do: true

  @impl true
  def handle_event("shift_month", %{"delta" => delta}, socket) do
    delta = parse_int(delta)

    {:noreply,
     update(socket, :month, fn current ->
       ReviewCalendar.shift_month(current || Date.utc_today(), delta)
     end)}
  end

  def handle_event("set_month", %{"month" => raw_month}, socket) do
    case Integer.parse(to_string(raw_month)) do
      {month, _} when month in 1..12 ->
        current = socket.assigns.month || Date.utc_today()
        {:noreply, assign(socket, :month, Date.new!(current.year, month, 1))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_year", %{"year" => raw_year}, socket) do
    case Integer.parse(to_string(raw_year)) do
      {year, _} ->
        current = socket.assigns.month || Date.utc_today()
        {:noreply, assign(socket, :month, Date.new!(year, current.month, 1))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_date", %{"date" => date_iso}, socket) do
    current_started =
      pending_or_assign(socket.assigns.pending_started, socket.assigns.date_started)

    current_finished =
      pending_or_assign(socket.assigns.pending_finished, socket.assigns.date_finished)

    {started, finished} =
      ReviewCalendar.compute_dates(
        socket.assigns.status,
        current_started,
        current_finished,
        date_iso
      )

    send(self(), {
      socket.assigns.notify,
      socket.assigns.id,
      %{date_started: started, date_finished: finished, picked: date_iso}
    })

    # Paint the new dates locally *before* the server roundtrip lands. The
    # `:unset` sentinel switches back once `update/2` sees the parent's
    # canonical assigns line up with what we optimistically applied.
    {:noreply,
     socket
     |> assign(:pending_started, started)
     |> assign(:pending_finished, finished)}
  end

  defp pending_or_assign(:unset, assign), do: assign
  defp pending_or_assign(value, _assign), do: value

  @impl true
  def render(assigns) do
    started_source = pending_or_assign(assigns.pending_started, assigns.date_started)
    finished_source = pending_or_assign(assigns.pending_finished, assigns.date_finished)
    started = ReviewCalendar.parse_review_date(started_source)
    finished = ReviewCalendar.parse_review_date(finished_source)
    month = ReviewCalendar.month_start(assigns.month || Date.utc_today())

    assigns =
      assigns
      |> assign(:started_date, started)
      |> assign(:finished_date, finished)
      |> assign(:month_date, month)
      |> assign(:today, Date.utc_today())
      |> assign(:days, ReviewCalendar.review_calendar_days(month))
      |> assign(:year_options, year_options(month.year))
      |> assign(:month_options, month_options())

    ~H"""
    <div
      id={@id}
      data-date-range-picker
      class="w-[264px] p-3"
    >
      <div class="mb-2 flex items-center justify-between gap-1">
        <button
          type="button"
          phx-click="shift_month"
          phx-value-delta="-1"
          phx-target={@myself}
          class="hover:bg-surface-menu-item-hover hover:text-foreground-primary text-foreground-secondary flex size-7 shrink-0 items-center justify-center rounded-md transition"
          aria-label="Previous month"
        >
          <Lucide.chevron_left class="size-4" aria-hidden="true" />
        </button>

        <div class="flex items-center gap-1">
          <.month_select month={@month_date.month} options={@month_options} target={@myself} />
          <.year_select year={@month_date.year} options={@year_options} target={@myself} />
        </div>

        <button
          type="button"
          phx-click="shift_month"
          phx-value-delta="1"
          phx-target={@myself}
          class="hover:bg-surface-menu-item-hover hover:text-foreground-primary text-foreground-secondary flex size-7 shrink-0 items-center justify-center rounded-md transition"
          aria-label="Next month"
        >
          <Lucide.chevron_right class="size-4" aria-hidden="true" />
        </button>
      </div>

      <div class="grid grid-cols-[repeat(7,32px)] justify-center text-center text-xs">
        <span
          :for={day <- ~w(Su Mo Tu We Th Fr Sa)}
          class="text-foreground-tertiary flex size-8 items-center justify-center text-[11px] font-normal"
        >
          {day}
        </span>
        <button
          :for={day <- @days}
          type="button"
          phx-click="set_date"
          phx-value-date={Date.to_iso8601(day)}
          phx-target={@myself}
          disabled={Date.compare(day, @today) == :gt}
          class={day_classes(day, @started_date, @finished_date, @today, @month_date)}
        >
          {day.day}
        </button>
      </div>
    </div>
    """
  end

  # Pre-compute the class list for a calendar cell. Keeping this as plain Elixir
  # (rather than a long inline class={[...]}) makes the priorities readable:
  # range edge wins, then range middle, then today, then in/out-of-month.
  defp day_classes(day, started, finished, today, month) do
    selected_edge? = ReviewCalendar.calendar_selected_edge?(day, started, finished)
    range_middle? = ReviewCalendar.calendar_range_middle?(day, started, finished)
    today? = Date.compare(day, today) == :eq
    future? = Date.compare(day, today) == :gt
    other_month? = day.month != month.month

    base = "flex size-8 items-center justify-center text-sm leading-none font-normal transition"

    cond do
      selected_edge? ->
        "#{base} bg-foreground-primary text-surface-base rounded-md font-medium"

      range_middle? ->
        # Range fill — the rounded edges paint via the selected-edge clauses
        # above; middle cells stay square so the run reads as one continuous
        # band.
        "#{base} bg-surface-menu-item-hover text-foreground-primary"

      today? ->
        # Today carries a thin outline + subtle fill so it reads as "current
        # day" without competing with a real selection.
        "#{base} bg-surface-menu-item-hover text-foreground-primary rounded-md ring-1 ring-inset ring-border-divider"

      future? ->
        "#{base} text-foreground-tertiary cursor-not-allowed opacity-30 rounded-md"

      other_month? ->
        "#{base} text-foreground-tertiary hover:bg-surface-menu-item-hover rounded-md"

      true ->
        "#{base} text-foreground-primary hover:bg-surface-menu-item-hover rounded-md"
    end
  end

  # ---------------------------------------------------------------------------
  # Month / year dropdowns. Native <select> + minimal styling so we get OS-
  # level keyboard nav and accessibility without a custom popover.
  # ---------------------------------------------------------------------------

  attr :month, :integer, required: true
  attr :options, :list, required: true
  attr :target, :any, required: true

  defp month_select(assigns) do
    ~H"""
    <span class="relative inline-flex items-center">
      <select
        name="month"
        aria-label="Month"
        phx-change="set_month"
        phx-target={@target}
        class={[
          "cursor-pointer appearance-none rounded-md bg-transparent",
          "text-foreground-primary h-7 py-0 pr-6 pl-2 text-sm font-medium",
          "focus:ring-border-divider hover:bg-surface-menu-item-hover focus:ring-1 focus:outline-none",
          "transition-colors"
        ]}
      >
        <option :for={{value, label} <- @options} value={value} selected={value == @month}>
          {label}
        </option>
      </select>
      <Lucide.chevron_down
        class="text-foreground-tertiary pointer-events-none absolute top-1/2 right-1.5 size-3 -translate-y-1/2"
        aria-hidden="true"
      />
    </span>
    """
  end

  attr :year, :integer, required: true
  attr :options, :list, required: true
  attr :target, :any, required: true

  defp year_select(assigns) do
    ~H"""
    <span class="relative inline-flex items-center">
      <select
        name="year"
        aria-label="Year"
        phx-change="set_year"
        phx-target={@target}
        class={[
          "cursor-pointer appearance-none rounded-md bg-transparent",
          "text-foreground-primary h-7 py-0 pr-6 pl-2 text-sm font-medium",
          "focus:ring-border-divider hover:bg-surface-menu-item-hover focus:ring-1 focus:outline-none",
          "transition-colors"
        ]}
      >
        <option :for={value <- @options} value={value} selected={value == @year}>
          {value}
        </option>
      </select>
      <Lucide.chevron_down
        class="text-foreground-tertiary pointer-events-none absolute top-1/2 right-1.5 size-3 -translate-y-1/2"
        aria-hidden="true"
      />
    </span>
    """
  end

  defp month_options do
    Enum.map(1..12, &{&1, ReviewCalendar.month_name(&1)})
  end

  defp year_options(current_year) do
    today_year = Date.utc_today().year
    upper = max(current_year, today_year) + @year_lookahead
    lower = min(current_year, today_year) - @year_lookback
    Enum.to_list(upper..lower//-1)
  end

  defp default_month(assigns) do
    seed =
      assigns[:date_finished] || assigns[:date_started] || Date.utc_today()

    case seed do
      %Date{} = d ->
        ReviewCalendar.month_start(d)

      value when is_binary(value) ->
        ReviewCalendar.month_start(ReviewCalendar.parse_review_date(value) || Date.utc_today())

      _ ->
        ReviewCalendar.month_start(Date.utc_today())
    end
  end

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> 0
    end
  end
end
