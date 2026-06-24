defmodule KaguyaWeb.ProfileLive.Follows do
  @moduledoc """
  `/@:username/followers` and `/@:username/following` — cursor-paginated
  user lists.

  The two routes share a single module; `@live_action` differentiates
  `:followers` vs `:following`.
  """

  use KaguyaWeb.ProfileLive, tab: :followers, title_suffix: "Followers"

  import KaguyaWeb.SharedComponents.LoadMore

  alias KaguyaWeb.SharedComponents.Cover
  alias KaguyaWeb.Components.Profile.Placeholder

  import KaguyaWeb.Components.Profile.Shared, only: [avatar: 1, format_short_number: 1]

  @page_size 10
  @auto_load_until 50

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    {:ok, socket} = super(params, session, socket)

    {:ok,
     socket
     |> assign(:users, [])
     |> assign(:next_cursor, nil)
     |> assign(:has_next, false)
     |> assign(:loading_more, false)
     |> assign(:query_string, "")
     |> assign(:auto_load_until, @auto_load_until)
     |> assign(KaguyaWeb.SEO.noindex())}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]
    action = follow_action(socket)
    label = label_for(action)

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        {:ok, page} = load_page(action, username, nil, viewer)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, "#{label} • Kaguya")
         |> assign(:current_tab, action)
         |> assign(:users, page.items)
         |> assign(:next_cursor, page.next_cursor)
         |> assign(:has_next, page.has_next)
         |> assign(:loading_more, false)
         |> assign(:query_string, URI.parse(uri).query || "")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_follows", _params, %{assigns: %{has_next: false}} = socket),
    do: {:noreply, assign(socket, :loading_more, false)}

  def handle_event("load_more_follows", _params, %{assigns: %{next_cursor: nil}} = socket),
    do: {:noreply, assign(socket, :loading_more, false)}

  def handle_event("load_more_follows", _params, socket) do
    socket = assign(socket, :loading_more, true)
    action = follow_action(socket)

    case load_page(
           action,
           socket.assigns.profile.username,
           socket.assigns.next_cursor,
           socket.assigns.current_user
         ) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:users, socket.assigns.users ++ page.items)
         |> assign(:next_cursor, page.next_cursor)
         |> assign(:has_next, page.has_next)
         |> assign(:loading_more, false)}

      _ ->
        {:noreply, assign(socket, :loading_more, false)}
    end
  end

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    action = follow_action(assigns)
    label = label_for(action)

    assigns =
      assigns
      |> assign(:activity_type, action)
      |> assign(:label, label)

    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <div class="mt-8 max-lg:px-0 lg:mt-10">
        <div class="min-h-[calc(100vh-172px)] w-full">
          <div class="mx-auto max-w-[852px] bg-transparent pb-8 md:bg-[rgb(var(--surface-elevated))] md:pt-4">
            <.follow_tabs
              username={@profile.username}
              activity_type={@activity_type}
              query_string={@query_string}
              total_followers={@profile.counts.followers || 0}
              total_following={@profile.counts.following || 0}
            />

            <div class="mt-4 space-y-6 px-4 md:mt-8 md:space-y-8 md:px-8">
              <%= cond do %>
                <% @users == [] -> %>
                  <div class="my-8 text-center text-[rgb(var(--foreground-primary))]">
                    {empty_message(@activity_type)}
                  </div>
                <% true -> %>
                  <.follow_user_card :for={user <- @users} user={user} />

                  <%= cond do %>
                    <% @has_next and length(@users) < @auto_load_until -> %>
                      <div
                        id="follow-auto-loader"
                        phx-hook="FollowAutoLoad"
                        data-loading-more={to_string(@loading_more)}
                        aria-live="polite"
                        class="flex w-full items-center justify-center py-4 text-sm text-[rgb(var(--foreground-secondary))]"
                      >
                        Loading more
                      </div>
                    <% @has_next -> %>
                      <div class="my-6 flex w-full items-center justify-center">
                        <.load_more
                          phx-click="load_more_follows"
                          disabled={@loading_more}
                          loading_label="Loading…"
                        />
                      </div>
                    <% true -> %>
                      <div class="h-2" />
                  <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </main>
    """
  end

  attr :username, :string, required: true
  attr :activity_type, :atom, required: true
  attr :query_string, :string, default: ""
  attr :total_followers, :integer, required: true
  attr :total_following, :integer, required: true

  defp follow_tabs(assigns) do
    ~H"""
    <div class="mb-0 flex items-center justify-between gap-4 px-4 text-[rgb(var(--foreground-primary))] md:border-b md:border-[rgb(var(--border-divider))] md:px-8">
      <div class="flex items-center space-x-6 bg-transparent p-0">
        <.follow_tab
          username={@username}
          query_string={@query_string}
          value={:followers}
          active?={@activity_type == :followers}
          label="Followers"
          count={@total_followers}
        />
        <.follow_tab
          username={@username}
          query_string={@query_string}
          value={:following}
          active?={@activity_type == :following}
          label="Following"
          count={@total_following}
        />
      </div>
    </div>
    """
  end

  attr :username, :string, required: true
  attr :query_string, :string, default: ""
  attr :value, :atom, required: true
  attr :active?, :boolean, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp follow_tab(assigns) do
    ~H"""
    <.link
      navigate={tab_path(@username, @value, @query_string)}
      class={[
        "flex items-center space-x-2 border-b-2 border-b-transparent bg-transparent p-0 px-[17px] py-2 pb-3 text-base font-semibold text-[rgb(var(--foreground-primary))]",
        @active? && "border-b-white"
      ]}
    >
      <span>{@label}</span>
      <div class={[
        "flex h-5 items-center justify-center rounded-[3px] bg-white/6 p-[5px] text-sm leading-[17px] font-semibold",
        @active? && "bg-white/14"
      ]}>
        {format_short_number(@count)}
      </div>
    </.link>
    """
  end

  attr :user, :map, required: true

  defp follow_user_card(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_auto] justify-between gap-3 md:gap-6 md:pr-5">
      <div class="flex items-start gap-2.5 md:items-center md:gap-6">
        <.link navigate={profile_path(@user)} class="shrink-0">
          <.avatar
            user={@user}
            class="size-8 rounded-full object-cover md:size-20"
            size={:medium}
            sizes="(max-width: 768px) 2rem, 5rem"
          />
        </.link>

        <div class="flex-1">
          <div class="flex flex-col items-start">
            <div class="flex flex-col">
              <.link
                navigate={profile_path(@user)}
                class="line-clamp-1 text-sm leading-[12px] font-semibold text-[rgb(var(--foreground-primary))] max-sm:max-w-[150px] md:text-lg md:leading-[22px] md:font-semibold"
              >
                {@user.display_name}
              </.link>
              <div class="mt-2.5 flex items-center gap-1 text-sm text-[rgb(var(--foreground-primary))] max-md:leading-0 md:gap-1.5">
                <.link
                  navigate={"#{profile_path(@user)}/library"}
                  class="flex items-center gap-0.5 md:gap-1"
                >
                  <Lucide.book_open class="size-2.5 md:size-[15px]" aria-hidden />
                  <span class="text-[11px] font-normal max-md:leading-0 md:text-sm md:font-semibold">
                    {@user.vns_count}
                  </span>
                  <span class="text-[11px] font-normal max-md:leading-0 md:text-sm md:font-normal">
                    VNs
                  </span>
                </.link>

                <span class="text-[10px] text-[rgb(var(--foreground-primary))]/40 md:text-xs">•</span>

                <.link
                  navigate={"#{profile_path(@user)}/reviews"}
                  class="flex items-center gap-0.5 md:gap-1"
                >
                  <Lucide.file_text class="size-2.5 md:size-[15px]" aria-hidden />
                  <span class="text-[11px] font-normal max-md:leading-[12px] md:text-sm md:font-semibold">
                    {@user.reviews_count}
                  </span>
                  <span class="text-[11px] font-normal max-md:leading-[12px] md:text-sm md:font-normal">
                    Reviews
                  </span>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-4 items-center gap-[3px] sm:gap-1 md:mt-4">
        <%= for vn <- @user.library_visual_novels do %>
          <div>
            <Cover.cover
              vn={vn}
              sizes="(max-width: 768px) 32px, 59px"
              fallback_class="rounded-[4px]"
              link={true}
              class="aspect-1/1.5 h-12 w-8 rounded-[1px] md:h-[88px] md:w-[59px] md:rounded-[2px]"
            />
          </div>
        <% end %>
        <div
          :for={_ <- empty_cover_slots(@user.library_visual_novels)}
          class="aspect-1/1.5 h-12 w-8 rounded-[1px] bg-[rgb(var(--surface-elevated))] md:h-[88px] md:w-[59px] md:rounded-[2px]"
        />
      </div>
    </div>
    """
  end

  defp load_page(:following, username, cursor, viewer),
    do: Data.load_following(username, cursor, @page_size, viewer)

  defp load_page(_action, username, cursor, viewer),
    do: Data.load_followers(username, cursor, @page_size, viewer)

  defp follow_action(%{assigns: %{live_action: :following}}), do: :following
  defp follow_action(%{live_action: :following}), do: :following
  defp follow_action(_), do: :followers

  defp label_for(:following), do: "Following"
  defp label_for(_), do: "Followers"

  defp empty_message(:following), do: "Not following anyone"
  defp empty_message(_), do: "No followers found"

  defp tab_path(username, tab, ""), do: "/@#{username}/#{tab}"
  defp tab_path(username, tab, query_string), do: "/@#{username}/#{tab}?#{query_string}"

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_), do: "#"

  defp empty_cover_slots(items), do: List.duplicate(nil, max(0, 4 - length(items || [])))
end
