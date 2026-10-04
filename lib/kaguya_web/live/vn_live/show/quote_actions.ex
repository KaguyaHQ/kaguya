defmodule KaguyaWeb.VNLive.Show.QuoteActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  def open_quote_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} ->
        {:noreply,
         assign(socket,
           quote_dialog_open: true,
           quote_form: quote_form(%{}),
           quote_editing_id: nil,
           quote_error: nil,
           action_drawer_open: false
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add quotes")}
    end
  end

  def close_quote_dialog(socket, _params),
    do: {:noreply, assign(socket, quote_dialog_open: false)}

  def edit_quote(socket, %{"quote-id" => id}) do
    items =
      case socket.assigns.tabs[:quotes] do
        {:ok, items} -> items
        _ -> []
      end

    quote = Enum.find(items, &(to_string(&1.id) == id))
    user = socket.assigns.current_user

    if quote && user && quote.created_by == user.id do
      {:noreply,
       assign(socket,
         quote_dialog_open: true,
         quote_editing_id: quote.id,
         quote_error: nil,
         quote_form:
           quote_form(%{
             "text" => quote.quote,
             "character_id" => (quote.character && quote.character.id) || ""
           })
       )}
    else
      {:noreply, put_flash(socket, :error, "You can only edit your own quotes")}
    end
  end

  def validate_quote(socket, %{"quote" => attrs}) do
    {:noreply, assign(socket, quote_form: quote_form(attrs), quote_error: nil)}
  end

  def select_quote_character(socket, %{"character-id" => id}) do
    attrs = Map.put(socket.assigns.quote_form.params, "character_id", id)
    {:noreply, assign(socket, quote_form: quote_form(attrs))}
  end

  def save_quote(socket, %{"quote" => %{"text" => text} = attrs}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        result =
          if socket.assigns.quote_editing_id do
            PageData.update_quote(
              socket.assigns.slug,
              user,
              socket.assigns.quote_editing_id,
              text,
              attrs["character_id"]
            )
          else
            PageData.create_quote(socket.assigns.slug, user, text, attrs["character_id"])
          end

        case result do
          {:ok, quote} ->
            socket = save_quote_to_tab(socket, quote)

            {:noreply,
             assign(socket, quote_dialog_open: false, quote_editing_id: nil, quote_error: nil)}

          {:error, reason} ->
            {:noreply,
             assign(socket, quote_form: quote_form(attrs), quote_error: Data.format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to add quotes")}
    end
  end

  defp save_quote_to_tab(socket, quote) do
    if socket.assigns.quote_editing_id do
      Data.update_tab_items(socket, :quotes, &replace_quote(&1, quote))
    else
      Data.update_tab_items(socket, :quotes, &[quote | &1])
    end
  end

  defp replace_quote(items, updated) do
    Enum.map(items, fn quote -> if quote.id == updated.id, do: updated, else: quote end)
  end

  defp quote_form(attrs) do
    %{"text" => "", "character_id" => "", "character_query" => ""}
    |> Map.merge(Map.take(attrs, ["text", "character_id", "character_query"]))
    |> to_form(as: :quote)
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
