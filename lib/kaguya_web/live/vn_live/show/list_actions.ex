defmodule KaguyaWeb.VNLive.Show.ListActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def open_list_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        shelves =
          case PageData.list_shelves_for_user(user) do
            {:ok, shelves} -> shelves
            _ -> []
          end

        {:noreply,
         assign(socket,
           list_dialog_open: true,
           action_drawer_open: false,
           shelves: shelves,
           new_shelf_name: "",
           create_shelf_error: nil,
           selected_shelf_ids:
             Enum.map(get_in(socket.assigns, [:viewer_vn, :my_shelves]) || [], & &1.id)
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add this visual novel to lists")}
    end
  end

  def close_list_dialog(socket, _params),
    do:
      {:noreply,
       assign(socket,
         list_dialog_open: false,
         new_shelf_name: "",
         create_shelf_error: nil
       )}

  def change_shelf_name(socket, %{"shelf" => %{"name" => name}}) do
    {:noreply, assign(socket, new_shelf_name: name, create_shelf_error: nil)}
  end

  def update_list_membership(socket, params) do
    shelf_ids = get_in(params, ["shelves", "ids"]) || []
    {:noreply, assign(socket, selected_shelf_ids: shelf_ids)}
  end

  def save_list_membership(socket, params) do
    shelf_ids = get_in(params, ["shelves", "ids"]) || []

    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.save_shelves_for_vn(socket.assigns.slug, user, shelf_ids) do
          {:ok, bundle} ->
            {:noreply,
             socket
             |> Data.assign_viewer_bundle(bundle)
             |> assign(
               list_dialog_open: false,
               new_shelf_name: "",
               create_shelf_error: nil
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to update lists")}
    end
  end

  def create_shelf(socket, %{"shelf" => %{"name" => name}}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        trimmed_name = String.trim(name || "")

        if trimmed_name == "" do
          {:noreply,
           assign(socket,
             new_shelf_name: name || "",
             create_shelf_error: "List name can't be blank"
           )}
        else
          case PageData.create_shelf_for_vn(socket.assigns.slug, user, trimmed_name) do
            {:ok, bundle} ->
              shelves =
                case PageData.list_shelves_for_user(user) do
                  {:ok, shelves} -> shelves
                  _ -> socket.assigns.shelves
                end

              {:noreply,
               socket
               |> Data.assign_viewer_bundle(bundle)
               |> assign(
                 shelves: shelves,
                 selected_shelf_ids: Enum.map(bundle.viewer_vn.my_shelves, & &1.id),
                 new_shelf_name: "",
                 create_shelf_error: nil
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 new_shelf_name: name || "",
                 create_shelf_error: Data.format_error(reason)
               )}
          end
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to create lists")}
    end
  end
end
