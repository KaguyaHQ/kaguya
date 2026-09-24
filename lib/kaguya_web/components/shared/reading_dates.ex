defmodule KaguyaWeb.SharedComponents.ReadingDates do
  @moduledoc "Reading date dialog and draft validation shared by VN and library pages."
  use KaguyaWeb, :html
  alias Phoenix.LiveView.JS
  import KaguyaWeb.UI.Input
  import KaguyaWeb.UI.Dialog

  attr :form, :any, required: true
  attr :error, :string, default: nil

  def reading_dates_dialog(assigns) do
    ~H"""
    <.dialog
      id="reading-dates-dialog"
      on_close={JS.push("close_reading_dates")}
      aria-labelledby="reading-dates-title"
      class="bg-surface-elevated border-border-divider text-foreground-primary w-[min(420px,calc(100vw-32px))] rounded-xl border p-6 shadow-xl"
    >
      <h2 id="reading-dates-title" class="text-style-body1Medium">Reading dates</h2>
      <p class="text-foreground-secondary text-style-body2Regular mt-2">
        Leave a date blank if you don’t remember it.
      </p>
      <.form
        for={@form}
        id="reading-dates-form"
        phx-hook="ReadingDates"
        phx-change="change_reading_dates"
        phx-submit="save_reading_dates"
        class="mt-3 space-y-4"
      >
        <div :for={{field, label} <- [date_started: "Started", date_finished: "Finished"]}>
          <div class="mb-2 flex h-8 items-center justify-between gap-3">
            <label for={@form[field].id} class="text-style-body2Medium">{label}</label>
            <div class="flex items-center gap-1">
              <button
                type="button"
                phx-click="set_reading_date_today"
                phx-value-field={field}
                aria-label={"Set " <> String.downcase(label) <> " to today"}
                class="focus-visible:outline-foreground-primary/70 hover:bg-surface-elevated hover:text-foreground-primary text-foreground-secondary text-style-captionRegular h-8 rounded-md px-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >Today</button>
              <button
                :if={@form[field].value not in [nil, ""]}
                type="button"
                phx-click={
                  JS.dispatch("reading-date:clear",
                    to: "#reading-dates-form",
                    detail: %{id: @form[field].id}
                  )
                  |> JS.push("clear_reading_date", value: %{field: field})
                }
                phx-value-field={field}
                aria-label={"Clear " <> String.downcase(label)}
                class="focus-visible:outline-foreground-primary/70 hover:bg-surface-elevated hover:text-foreground-primary text-foreground-secondary text-style-captionRegular h-8 rounded-md px-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >Clear</button>
            </div>
          </div>
          <.input
            field={@form[field]}
            type="date"
            control_size="roomy"
            class="text-style-body2Regular scheme-dark"
            max={Date.to_iso8601(Date.utc_today())}
          />
        </div>
        <p
          :if={@error}
          id="reading-dates-error"
          role="alert"
          class="text-semantic-error text-style-body2Regular"
        >
          {@error}
        </p>
        <div class="flex justify-end gap-2 pt-2">
          <.dialog_cancel>Cancel</.dialog_cancel>
          <button type="submit" class="btn btn-brand btn-small" phx-disable-with="Saving…">Save</button>
        </div>
      </.form>
    </.dialog>
    """
  end

  def change_dates(socket, %{"dates" => params}) do
    if socket.assigns.reading_dates_form do
      {:noreply,
       assign(socket,
         reading_dates_form:
           to_form(Map.take(params, ["date_started", "date_finished"]), as: :dates),
         reading_dates_error: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def set_date_today(socket, %{"field" => field})
      when field in ["date_started", "date_finished"] do
    if form = socket.assigns.reading_dates_form do
      change_dates(socket, %{
        "dates" => Map.put(form.params, field, Date.to_iso8601(Date.utc_today()))
      })
    else
      {:noreply, socket}
    end
  end

  def clear_date(socket, %{"field" => field}) when field in ["date_started", "date_finished"] do
    if form = socket.assigns.reading_dates_form do
      change_dates(socket, %{"dates" => Map.put(form.params, field, "")})
    else
      {:noreply, socket}
    end
  end

  def parse_dates(params) do
    with {:ok, started} <- parse_date(params["date_started"]),
         {:ok, finished} <- parse_date(params["date_finished"]),
         :ok <- validate_dates(started, finished) do
      {:ok, %{date_started: started, date_finished: finished}}
    end
  end

  defp parse_date(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "Enter a valid date."}
    end
  end

  defp parse_date(_), do: {:error, "Enter a valid date."}

  defp validate_dates(started, finished) do
    cond do
      Enum.any?([started, finished], &(&1 && Date.compare(&1, Date.utc_today()) == :gt)) ->
        {:error, "Reading dates cannot be in the future."}

      started && finished && Date.compare(started, finished) == :gt ->
        {:error, "Finished must be on or after Started."}

      true ->
        :ok
    end
  end
end
