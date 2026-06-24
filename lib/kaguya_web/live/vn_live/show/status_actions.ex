defmodule KaguyaWeb.VNLive.Show.StatusActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
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
