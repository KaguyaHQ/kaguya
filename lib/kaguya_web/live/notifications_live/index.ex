defmodule KaguyaWeb.NotificationsLive.Index do
  use KaguyaWeb, :live_view

  alias KaguyaWeb.NotificationsLive.Data
  alias KaguyaWeb.NotificationsLive.IndexComponents

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      {:ok,
       socket
       |> assign(KaguyaWeb.SEO.noindex())
       |> assign(:page_title, "Notifications • Kaguya")
       |> assign(:meta_description, "Your recent notifications.")
       |> assign(:notifications, [])
       |> assign(:next_cursor, nil)
       |> assign(:has_next, false)
       |> assign(:limit, Data.page_size())
       |> assign(:load_error?, false)
       |> assign(:load_more_disabled?, false)
       |> assign(:unread_count, 0)}
    else
      {:ok, redirect(socket, to: "/login")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.current_user do
      case Data.load_page(socket.assigns.current_user, params) do
        {:ok, payload} ->
          socket =
            socket
            |> assign(:notifications, payload.notifications)
            |> assign(:has_next, payload.has_next)
            |> assign(:next_cursor, payload.next_cursor)
            |> assign(:limit, payload.limit)
            |> assign(:unread_count, payload.unread_count)
            |> assign(:load_error?, false)
            |> assign(:load_more_disabled?, false)
            |> mark_visible_notifications_seen()

          {:noreply, socket}

        {:error, :not_found} ->
          {:noreply, socket |> assign(:load_error?, true)}

        _ ->
          {:noreply, socket |> assign(:load_error?, true)}
      end
    else
      {:noreply, redirect(socket, to: "/login")}
    end
  end

  @impl true
  def handle_event("open-notification", %{"url" => raw_url}, socket) do
    case safe_target_path(raw_url) do
      nil -> {:noreply, socket}
      target -> {:noreply, push_navigate(socket, to: target)}
    end
  end

  # Notifications without a link (e.g. system messages) still emit the click;
  # there's nothing to navigate to, so it's a no-op.
  def handle_event("open-notification", _params, socket), do: {:noreply, socket}

  def handle_event("load-more-notifications", _params, socket) do
    limit = socket.assigns.limit
    cursor = socket.assigns.next_cursor

    socket = assign(socket, :load_more_disabled?, true)

    case Data.load_more(socket.assigns.current_user, cursor, limit) do
      {:ok, payload} ->
        {:noreply,
         socket
         |> assign(:notifications, socket.assigns.notifications ++ payload.notifications)
         |> assign(:has_next, payload.has_next)
         |> assign(:next_cursor, payload.next_cursor)
         |> assign(:load_more_disabled?, false)}

      _ ->
        {:noreply,
         socket
         |> assign(:load_more_disabled?, false)
         |> put_flash(:error, "Could not load more notifications.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @load_error? do %>
      <div class="text-foreground-secondary mx-auto mt-8 max-w-[988px] px-4 text-sm lg:px-0">
        Could not load notifications right now. Please try again.
      </div>
    <% else %>
      <IndexComponents.notifications_page
        notifications={@notifications}
        load_more?={@has_next}
        load_more_disabled?={@load_more_disabled?}
        unread_count={@unread_count}
      />
    <% end %>
    """
  end

  # Visiting the notifications page acknowledges everything: mark all unread read
  # in the DB (which clears the navbar bell via the {:unread_count, _} broadcast)
  # and reset the local count. The in-memory list keeps its read flags untouched
  # so rows stay subtly highlighted as "new" for the rest of the session.
  defp mark_visible_notifications_seen(
         %{assigns: %{unread_count: count, current_user: %{} = current_user}} = socket
       )
       when is_integer(count) and count > 0 do
    case Data.mark_all_notifications_read(current_user) do
      {:ok, _} -> assign(socket, :unread_count, 0)
      _ -> socket
    end
  end

  defp mark_visible_notifications_seen(socket), do: socket

  defp safe_target_path(url) when is_binary(url) do
    if String.starts_with?(url, "/") and String.length(url) > 0 and url != "#" do
      url
    else
      nil
    end
  end

  defp safe_target_path(_), do: nil
end
