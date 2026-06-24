defmodule KaguyaWeb.VNLive.Show.QuoteActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def open_quote_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} ->
        {:noreply,
         assign(socket, quote_dialog_open: true, quote_text: "", action_drawer_open: false)}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add quotes")}
    end
  end

  def close_quote_dialog(socket, _params),
    do: {:noreply, assign(socket, quote_dialog_open: false)}

  def save_quote(socket, %{"quote" => %{"text" => text} = attrs}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        case PageData.create_quote(socket.assigns.slug, user, text, attrs["character_id"]) do
          {:ok, quote} ->
            {:noreply,
             socket
             |> Data.update_tab_items(:quotes, &[quote | &1])
             |> assign(quote_dialog_open: false)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add quotes")}
    end
  end

  def toggle_quote_like(socket, %{"quote-id" => quote_id}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        {liked?, socket} =
          Data.update_tab_item(socket, :quotes, quote_id, fn quote ->
            liked? = quote.liked_by_me

            {liked?,
             %{
               quote
               | liked_by_me: !liked?,
                 likes_count: max(0, quote.likes_count + if(liked?, do: -1, else: 1))
             }}
          end)

        case PageData.toggle_quote_like(quote_id, liked?, user) do
          {:ok, _} -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to like quotes")}
    end
  end
end
