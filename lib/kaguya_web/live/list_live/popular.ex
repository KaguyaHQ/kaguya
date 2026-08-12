defmodule KaguyaWeb.ListLive.Popular do
  use KaguyaWeb, :live_view

  import KaguyaWeb.SharedComponents.LoadMore

  alias KaguyaWeb.ListLive.Data
  alias KaguyaWeb.Lists.Cards, as: ListCards

  @page_size 10
  @description "Discover the most popular lists curated by the Kaguya community. See what's trending and find your next favorite collection."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:popular_lists, dom_id: &"popular-list-#{&1.id}")
     |> stream(:popular_lists, [])
     |> assign(
       page_title: "Popular Lists • Kaguya",
       meta_description: @description,
       meta_robots: "index,follow",
       canonical_url: "https://kaguya.io/lists/popular",
       og_title: "Popular Lists • Kaguya",
       og_description: @description,
       og_url: "https://kaguya.io/lists/popular",
       twitter_title: "Popular Lists • Kaguya",
       twitter_description: @description,
       next_cursor: nil,
       has_next: false,
       empty?: true,
       loading_more?: false,
       load_error?: false
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case Data.load_popular_lists(socket.assigns.current_user, nil, @page_size) do
      {:ok, page} ->
        {:noreply,
         socket
         |> stream(:popular_lists, page.items, reset: true)
         |> assign(
           next_cursor: page.next_cursor,
           has_next: page.has_next,
           empty?: page.items == [],
           load_error?: false
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, :load_error?, true)}
    end
  end

  @impl true
  def handle_event("load_more_popular_lists", _params, %{assigns: %{has_next: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event(
        "load_more_popular_lists",
        _params,
        %{assigns: %{next_cursor: nil}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "load_more_popular_lists",
        _params,
        %{assigns: %{loading_more?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("load_more_popular_lists", _params, socket) do
    socket = assign(socket, :loading_more?, true)

    case Data.load_popular_lists(
           socket.assigns.current_user,
           socket.assigns.next_cursor,
           @page_size
         ) do
      {:ok, page} ->
        {:noreply,
         socket
         |> stream(:popular_lists, page.items)
         |> assign(
           next_cursor: page.next_cursor,
           has_next: page.has_next,
           loading_more?: false
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:loading_more?, false)
         |> put_flash(:error, "Popular lists could not be loaded. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto mt-6 min-h-[calc(100vh-172px)] max-w-[535px] pb-[110px] sm:pb-32 md:mt-8 lg:mt-[64px] lg:max-w-[766px] lg:pb-[88px]">
      <div class="size-full px-4 pt-2 pb-3 sm:pb-8 md:px-8 md:pt-0">
        <h1
          id="popular-lists-heading"
          class="text-foreground-primary border border-x-0 border-y-0 text-xl leading-[19px] font-medium sm:border-b sm:border-b-[#98c6f4]/20 sm:pb-1.5 md:text-base lg:pb-3.5 lg:text-2xl/8 lg:font-semibold"
        >
          Popular Lists
        </h1>

        <p
          :if={@load_error?}
          id="popular-lists-load-error"
          class="text-foreground-secondary py-12 text-center text-sm"
        >
          Popular lists could not be loaded. Please try again.
        </p>

        <div
          :if={!@load_error?}
          id="popular-lists"
          phx-update="stream"
          class="mt-4 max-sm:space-y-6 sm:max-lg:-mt-1 md:max-lg:-space-y-2 lg:divide-y lg:divide-white/8"
        >
          <p
            id="popular-lists-empty"
            class="text-foreground-secondary hidden py-12 text-center text-sm only:block"
          >
            No popular lists yet.
          </p>

          <div
            :for={{id, list} <- @streams.popular_lists}
            id={id}
            class="sm:pt-6 sm:pb-4"
          >
            <ListCards.list_card
              list={list}
              sizes="(max-width: 768px) 67px, 93px"
              max_covers={5}
              variant="description"
              cover_fallback_size={42}
              container_class="flex h-fit w-full -space-x-[29px] overflow-hidden rounded-[2px] sm:-space-x-6"
              title_class="mt-1.5 text-base leading-[21px] font-semibold text-foreground-primary dark:text-[#f9f9f9] sm:mt-0 md:max-lg:text-sm lg:font-semibold"
              image_class="rounded-[2px]"
              description_class="md:max-lg:text-xs md:max-lg:leading-[17px] md:max-lg:text-foreground-quaternary"
            />
          </div>
        </div>

        <div :if={@has_next and !@load_error?} class="my-6 flex w-full items-center justify-center">
          <.load_more
            id="popular-lists-load-more"
            phx-click="load_more_popular_lists"
            phx-disable-with="Loading…"
            disabled={@loading_more?}
            loading_label="Loading…"
          />
        </div>
      </div>
    </main>
    """
  end
end
