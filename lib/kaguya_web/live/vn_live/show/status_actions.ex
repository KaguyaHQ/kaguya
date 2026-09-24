defmodule KaguyaWeb.VNLive.Show.StatusActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def set_status(socket, %{"status" => status}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        previous = socket.assigns.viewer_bundle

        optimistic =
          previous
          |> put_in([:viewer_vn, :my_reading_status], %{status: status})
          |> Data.maybe_clear_rating_for_status(status)

        socket =
          assign(socket,
            viewer_bundle: optimistic,
            viewer_vn: optimistic.viewer_vn,
            display_vn: Data.build_display_vn(socket.assigns.public_vn, optimistic.viewer_vn),
            pending_status: previous
          )

        case PageData.set_reading_status(socket.assigns.slug, user, status) do
          {:ok, fresh} -> {:noreply, Data.assign_viewer_bundle(socket, fresh)}
          {:error, reason} -> {:noreply, Data.rollback_bundle(socket, previous, reason)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to track this visual novel")}
    end
  end

  def open_dates(socket, _params) do
    case {socket.assigns.current_user, socket.assigns.viewer_vn} do
      {%{id: _}, %{my_reading_status: %{status: _} = status}} ->
        params =
          Map.new([:date_started, :date_finished], fn key ->
            {Atom.to_string(key), date_string(Map.get(status, key))}
          end)

        {:noreply,
         assign(socket,
           reading_dates_form: to_form(params, as: :dates),
           reading_dates_error: nil,
           action_drawer_open: false
         )}

      _ ->
        {:noreply, socket}
    end
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

  def save_dates(socket, %{"dates" => params}) do
    with %{id: _} = user <- socket.assigns.current_user,
         %Phoenix.HTML.Form{} <- socket.assigns.reading_dates_form,
         %{my_reading_status: %{status: status}} <- socket.assigns.viewer_vn do
      socket =
        assign(socket,
          reading_dates_form:
            to_form(Map.take(params, ["date_started", "date_finished"]), as: :dates)
        )

      with {:ok, started} <- parse_date(params["date_started"]),
           {:ok, finished} <- parse_date(params["date_finished"]),
           :ok <- validate_dates(started, finished),
           {:ok, fresh} <-
             PageData.set_reading_status(socket.assigns.slug, user, status, %{
               date_started: started,
               date_finished: finished
             }) do
        {:noreply,
         socket
         |> Data.assign_viewer_bundle(fresh)
         |> assign(reading_dates_form: nil, reading_dates_error: nil)}
      else
        {:error, message} when is_binary(message) ->
          {:noreply, assign(socket, reading_dates_error: message)}

        _ ->
          {:noreply,
           assign(socket, reading_dates_error: "Could not save reading dates. Please try again.")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp date_string(nil), do: ""
  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
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

  def clear_status(socket, _params) do
    {:noreply, open_clear_status_dialog(socket)}
  end

  def close_clear_status_dialog(socket, _params) do
    {:noreply, assign(socket, clear_status_dialog_open?: false)}
  end

  def confirm_clear_status(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        previous = socket.assigns.viewer_bundle

        optimistic =
          previous
          |> put_in([:viewer_vn, :my_reading_status], nil)
          |> put_in([:viewer_vn, :my_rating], nil)

        socket =
          assign(socket,
            viewer_bundle: optimistic,
            viewer_vn: optimistic.viewer_vn,
            display_vn: Data.build_display_vn(socket.assigns.public_vn, optimistic.viewer_vn),
            clear_status_dialog_open?: false,
            pending_status: previous
          )

        case PageData.clear_reading_status(socket.assigns.slug, user) do
          {:ok, fresh} -> {:noreply, Data.assign_viewer_bundle(socket, fresh)}
          {:error, reason} -> {:noreply, Data.rollback_bundle(socket, previous, reason)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to track this visual novel")}
    end
  end

  def set_rating(socket, %{"rating" => rating}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case Float.parse(to_string(rating)) do
          {value, ""} ->
            previous = socket.assigns.viewer_bundle

            optimistic =
              previous |> put_in([:viewer_vn, :my_rating], value) |> Data.ensure_read_status()

            socket =
              assign(socket,
                viewer_bundle: optimistic,
                viewer_vn: optimistic.viewer_vn,
                display_vn: Data.build_display_vn(socket.assigns.public_vn, optimistic.viewer_vn),
                pending_rating: previous
              )

            case PageData.set_rating(socket.assigns.slug, user, value) do
              {:ok, fresh} -> {:noreply, Data.assign_viewer_bundle(socket, fresh)}
              {:error, reason} -> {:noreply, Data.rollback_bundle(socket, previous, reason)}
            end

          _ ->
            {:noreply, put_flash(socket, :error, "Invalid rating")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to rate this visual novel")}
    end
  end

  def clear_rating(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        previous = socket.assigns.viewer_bundle
        optimistic = put_in(previous, [:viewer_vn, :my_rating], nil)

        socket =
          assign(socket,
            viewer_bundle: optimistic,
            viewer_vn: optimistic.viewer_vn,
            display_vn: Data.build_display_vn(socket.assigns.public_vn, optimistic.viewer_vn),
            pending_rating: previous
          )

        case PageData.clear_rating(socket.assigns.slug, user) do
          {:ok, fresh} -> {:noreply, Data.assign_viewer_bundle(socket, fresh)}
          {:error, reason} -> {:noreply, Data.rollback_bundle(socket, previous, reason)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to rate this visual novel")}
    end
  end

  defp open_clear_status_dialog(socket) do
    case socket.assigns.current_user do
      %{id: _} ->
        assign(socket,
          clear_status_dialog_open?: true,
          action_drawer_open: false
        )

      _ ->
        put_flash(socket, :error, "Sign in to track this visual novel")
    end
  end
end
