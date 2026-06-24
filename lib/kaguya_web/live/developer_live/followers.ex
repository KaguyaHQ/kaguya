defmodule KaguyaWeb.DeveloperLive.Followers do
  use KaguyaWeb, :live_view

  import KaguyaWeb.SharedComponents.UserListRow, only: [user_list_row: 1]

  alias Kaguya.Social
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.DeveloperLive.Data
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Followers • Kaguya",
       producer: nil,
       followers: [],
       next_cursor: nil,
       has_next: false,
       loading_more: false,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Data.load_followers_page(slug, nil, socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Followers of #{page.producer.name} • Kaguya",
           producer: page.producer,
           followers: page.followers,
           next_cursor: page.next_cursor,
           has_next: page.has_next,
           loading_more: false
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Developer not found · Kaguya",
           not_found?: true
         )}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    with true <- socket.assigns.has_next,
         {:ok, page} <-
           Data.load_followers_page(
             socket.assigns.slug,
             socket.assigns.next_cursor,
             socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(:followers, socket.assigns.followers ++ page.followers)
       |> assign(:next_cursor, page.next_cursor)
       |> assign(:has_next, page.has_next)
       |> assign(:loading_more, false)}
    else
      _ -> {:noreply, assign(socket, :loading_more, false)}
    end
  end

  def handle_event("follow_user", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.follow_user(viewer_id, id)
        {:noreply, refresh_user_follow(socket, id)}

      _ ->
        {:noreply, push_navigate(socket, to: "/login")}
    end
  end

  def handle_event("unfollow_user", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.unfollow_user(viewer_id, id)
        {:noreply, refresh_user_follow(socket, id)}

      _ ->
        {:noreply, push_navigate(socket, to: "/login")}
    end
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-6 min-h-[calc(100vh-172px)] max-w-[669px] pb-[110px] sm:pb-32 md:mt-8 lg:mt-[48px] lg:pb-[88px]">
      <div class="size-full px-4 pb-0 md:px-0 md:pt-0">
        <div class="flex items-end justify-between border-b border-[rgb(var(--border-divider))] pb-4">
          <div class="flex flex-col gap-1">
            <span class="text-sm leading-[17px] text-[rgb(var(--foreground-secondary))] lg:text-base lg:leading-[19px]">
              Followers of
            </span>
            <.link
              navigate={"/developer/#{@producer.slug}"}
              class="w-fit text-lg leading-[22px] font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))] lg:text-2xl lg:leading-[29px]"
            >
              {@producer.name}
            </.link>
          </div>
        </div>

        <p :if={@followers == []} class="mt-6 text-center text-[rgb(var(--foreground-secondary))]">
          No one is following this developer yet.
        </p>

        <div :if={@followers != []} class="flex w-full flex-col divide-y divide-[#98C6F4]/10">
          <.follower_row :for={follower <- @followers} follower={follower} />
        </div>

        <div :if={@has_next} class="my-6 flex w-full items-center justify-center">
          <button
            type="button"
            phx-click="load_more"
            class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--button-background-neutral-default))] px-4 py-2 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-elevated))]"
          >
            Load More
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :follower, :map, required: true

  defp follower_row(assigns) do
    ~H"""
    <.user_list_row user={@follower.user} follow_value_name="id">
      <:meta>
        <time class="mr-10 line-clamp-1 hidden h-fit self-center text-[11px] leading-[13px] text-[rgb(var(--foreground-secondary))] sm:block lg:mr-20 lg:text-[13px] lg:leading-[16px]">
          {SharedTime.calendar_custom(@follower.followed_at)}
        </time>
      </:meta>
    </.user_list_row>
    """
  end

  defp refresh_user_follow(socket, id) do
    assign(
      socket,
      :followers,
      Data.update_user_follow_state(socket.assigns.followers, id, socket.assigns.current_user)
    )
  end
end
