defmodule KaguyaWeb.ListLive.Index do
  use KaguyaWeb, :live_view

  alias KaguyaWeb.ListLive.Data
  alias KaguyaWeb.Lists.IndexComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Lists • Kaguya",
       meta_description: "Popular and recent visual novel lists from the Kaguya community.",
       popular_lists: [],
       recently_liked_lists: [],
       recent_lists: [],
       hidden_gem_lists: [],
       is_logged_in: false,
       load_error?: false
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case Data.load_index_page(socket.assigns.current_user) do
      {:ok, payload} ->
        {:noreply, assign(socket, Map.put(payload, :load_error?, false))}

      {:error, _reason} ->
        {:noreply, assign(socket, :load_error?, true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        :if={@load_error?}
        class="text-foreground-secondary mx-auto mt-8 max-w-[988px] px-5 text-sm lg:px-0"
      >
        Lists could not be loaded. Please try again.
      </div>

      <IndexComponents.lists_index
        :if={!@load_error?}
        popular_lists={@popular_lists}
        hidden_gem_lists={@hidden_gem_lists}
        recently_liked_lists={@recently_liked_lists}
        recent_lists={@recent_lists}
        is_logged_in={@is_logged_in}
        current_path={@current_path}
      />
    </div>
    """
  end
end
