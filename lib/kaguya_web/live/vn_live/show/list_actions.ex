defmodule KaguyaWeb.VNLive.Show.ListActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def open_list_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        lists =
          case PageData.list_lists_for_vn(socket.assigns.slug, user) do
            {:ok, lists} -> lists
            _ -> []
          end

        selected_list_ids = selected_list_ids(lists)

        {:noreply,
         assign(socket,
           list_dialog_open: true,
           action_drawer_open: false,
           lists: lists,
           selected_list_ids: selected_list_ids,
           initial_list_ids: selected_list_ids,
           new_list_name: "",
           create_list_error: nil
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
         new_list_name: "",
         create_list_error: nil
       )}

  def change_list_name(socket, %{"list" => %{"name" => name}}) do
    {:noreply, assign(socket, new_list_name: name, create_list_error: nil)}
  end

  def update_list_membership(socket, params) do
    list_ids = get_in(params, ["lists", "ids"]) || []
    {:noreply, assign(socket, selected_list_ids: list_ids)}
  end

  def save_list_membership(socket, params) do
    list_ids = get_in(params, ["lists", "ids"]) || []

    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.save_lists_for_vn(socket.assigns.slug, user, list_ids) do
          :ok ->
            {:noreply,
             assign(socket,
               list_dialog_open: false,
               new_list_name: "",
               create_list_error: nil
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to update lists")}
    end
  end

  def create_list(socket, %{"list" => %{"name" => name}}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        trimmed_name = String.trim(name || "")

        if trimmed_name == "" do
          {:noreply,
           assign(socket,
             new_list_name: name || "",
             create_list_error: "List name can't be blank"
           )}
        else
          case PageData.create_list_for_vn(socket.assigns.slug, user, trimmed_name) do
            {:ok, _list} ->
              lists =
                case PageData.list_lists_for_vn(socket.assigns.slug, user) do
                  {:ok, lists} -> lists
                  _ -> socket.assigns.lists
                end

              selected_list_ids = selected_list_ids(lists)

              {:noreply,
               assign(socket,
                 lists: lists,
                 selected_list_ids: selected_list_ids,
                 initial_list_ids: selected_list_ids,
                 new_list_name: "",
                 create_list_error: nil
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 new_list_name: name || "",
                 create_list_error: Data.format_error(reason)
               )}
          end
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to create lists")}
    end
  end

  defp selected_list_ids(lists) do
    lists
    |> Enum.filter(& &1.contains_vn)
    |> Enum.map(& &1.id)
  end
end
