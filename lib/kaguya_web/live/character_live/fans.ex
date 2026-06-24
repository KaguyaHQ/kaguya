defmodule KaguyaWeb.CharacterLive.Fans do
  use KaguyaWeb, :live_view

  import KaguyaWeb.SharedComponents.UserListRow, only: [user_list_row: 1]

  alias Kaguya.Characters
  alias Kaguya.Social
  alias Kaguya.Users
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Character Fans • Kaguya",
       character: nil,
       fans: [],
       next_cursor: nil,
       has_next: false,
       loading_more: false,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case load_page(slug, nil, socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Fans of #{page.character.name} • Kaguya",
           character: page.character,
           fans: page.fans,
           next_cursor: page.next_cursor,
           has_next: page.has_next,
           loading_more: false
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Character not found · Kaguya",
           not_found?: true
         )}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    with true <- socket.assigns.has_next,
         {:ok, page} <-
           load_page(socket.assigns.slug, socket.assigns.next_cursor, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:fans, socket.assigns.fans ++ page.fans)
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
              Fans of
            </span>
            <.link
              navigate={"/character/#{@character.slug}"}
              class="w-fit text-lg leading-[22px] font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))] lg:text-2xl lg:leading-[29px]"
            >
              {@character.name}
            </.link>
          </div>
        </div>

        <p :if={@fans == []} class="mt-6 text-center text-[rgb(var(--foreground-secondary))]">
          No fans found.
        </p>

        <div :if={@fans != []} class="flex w-full flex-col divide-y divide-[#98C6F4]/10">
          <.fan_row :for={fan <- @fans} fan={fan} />
        </div>

        <div :if={@has_next} class="my-6 flex w-full items-center justify-center">
          <button
            type="button"
            phx-click="load_more"
            disabled={@loading_more}
            class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--button-background-neutral-default))] px-4 py-2 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-elevated))] disabled:opacity-60"
          >
            {if @loading_more, do: "Loading…", else: "Load More"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :fan, :map, required: true

  defp fan_row(assigns) do
    ~H"""
    <.user_list_row user={@fan.user} follow_value_name="id">
      <:meta>
        <time class="mr-10 line-clamp-1 hidden h-fit self-center text-[11px] leading-[13px] text-[rgb(var(--foreground-secondary))] sm:block lg:mr-20 lg:text-[13px] lg:leading-[16px]">
          {SharedTime.calendar_custom(@fan.favorited_at)}
        </time>
      </:meta>
    </.user_list_row>
    """
  end

  defp load_page(slug, cursor, current_user) do
    with {:ok, character} <- Characters.get_character_by_slug(slug, current_user),
         {:ok, fans} <-
           Characters.list_favoriters_of(character.id, cursor: cursor, limit: @page_size) do
      {:ok,
       %{
         character: character,
         fans: normalize_fans(fans.items, current_user),
         next_cursor: fans.next_cursor,
         has_next: fans.has_next
       }}
    end
  end

  defp normalize_fans(items, current_user) do
    viewer_id = viewer_id(current_user)
    user_ids = items |> Enum.map(& &1.user.id) |> Enum.reject(&is_nil/1)

    followed_ids =
      if viewer_id, do: Social.batch_followed_ids(viewer_id, user_ids), else: MapSet.new()

    Enum.map(items, fn item ->
      user = item.user

      %{
        id: item.id,
        favorited_at: item.favorited_at,
        user:
          user
          |> normalize_user()
          |> Map.put(:follow_state, follow_state(user, viewer_id, followed_ids))
          |> Map.put(:is_followed_by_me, MapSet.member?(followed_ids, user.id))
      }
    end)
  end

  defp normalize_user(user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username || "Unknown",
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp refresh_user_follow(socket, id) do
    assign(
      socket,
      :fans,
      Enum.map(socket.assigns.fans, fn
        %{user: %{id: ^id} = user} = fan ->
          put_in(fan, [:user], put_user_follow_state(user, socket.assigns.current_user))

        fan ->
          fan
      end)
    )
  end

  defp put_user_follow_state(%{id: id} = user, current_user) do
    viewer_id = viewer_id(current_user)
    state = Social.follow_state(viewer_id, id)

    user
    |> Map.put(:follow_state, state)
    |> Map.put(:is_followed_by_me, state == :following)
  end

  defp follow_state(%{id: id}, viewer_id, _followed_ids) when id == viewer_id, do: :self

  defp follow_state(%{id: id}, _viewer_id, followed_ids) do
    if MapSet.member?(followed_ids, id), do: :following, else: :not_following
  end

  defp viewer_id(%{id: id}) when is_binary(id), do: id
  defp viewer_id(_), do: nil
end
