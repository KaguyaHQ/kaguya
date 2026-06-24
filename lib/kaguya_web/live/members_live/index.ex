defmodule KaguyaWeb.MembersLive.Index do
  use KaguyaWeb, :live_view

  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.UI.Menu

  alias Kaguya.Social
  alias KaguyaWeb.MembersLive.Data

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Members • Kaguya")
     |> assign(:meta_description, "Browse and follow visual novel readers on Kaguya.")
     |> assign(KaguyaWeb.SEO.index())
     |> assign(:members, [])
     |> assign(:search_results, [])
     |> assign(:query, "")
     |> assign(:sort, :most_active)
     |> assign(:next_cursor, nil)
     |> assign(:has_next, false)
     |> assign(:loading_more, false)}
  end

  def handle_params(params, _uri, socket) do
    sort = Data.sort_from_slug(Map.get(params, "sort"))
    query = Map.get(params, "q", "") |> Data.normalize_search()

    {:ok, page} = Data.list_members(sort, nil, socket.assigns.current_user)
    {:ok, search_results} = Data.search_members(query, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:sort, sort)
     |> assign(:query, query)
     |> assign(:members, page.items)
     |> assign(:search_results, search_results)
     |> assign(:next_cursor, page.next_cursor)
     |> assign(:has_next, page.has_next)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    query = Data.normalize_search(query)

    {:noreply,
     push_patch(socket,
       to: members_path(socket.assigns.sort, query),
       replace: true
     )}
  end

  def handle_event("load_more", _params, socket) do
    with true <- socket.assigns.has_next,
         {:ok, page} <-
           Data.list_members(
             socket.assigns.sort,
             socket.assigns.next_cursor,
             socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(:members, socket.assigns.members ++ page.items)
       |> assign(:next_cursor, page.next_cursor)
       |> assign(:has_next, page.has_next)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("follow", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.follow_user(viewer_id, id)
        {:noreply, refresh_member_follow(socket, id)}

      _ ->
        {:noreply, push_navigate(socket, to: "/login")}
    end
  end

  def handle_event("unfollow", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.unfollow_user(viewer_id, id)
        {:noreply, refresh_member_follow(socket, id)}

      _ ->
        {:noreply, push_navigate(socket, to: "/login")}
    end
  end

  def render(assigns) do
    ~H"""
    <main class="mx-auto mt-6 min-h-[calc(100vh-172px)] max-w-[992px] px-4 pb-[110px] sm:px-8 sm:pb-32 md:mt-10 lg:px-4 lg:pb-28 xl:px-0">
      <div class="mb-6">
        <div class="border-border-divider flex items-center justify-between gap-4 border-b pb-4">
          <h1 class="text-foreground-primary text-xl leading-[22px] font-medium tracking-[-0.5px] sm:text-2xl/7 sm:font-normal">
            Members
          </h1>

          <div class="flex min-w-0 items-center gap-3">
            <.form for={%{}} as={:search} phx-change="search" class="hidden sm:block">
              <div class="relative h-10 w-[284px] max-w-[42vw]">
                <.search_icon
                  class="text-foreground-primary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
                  aria-hidden
                />
                <input
                  type="search"
                  name="q"
                  value={@query}
                  placeholder="Search username"
                  phx-debounce="350"
                  class="border-border-divider placeholder:text-foreground-primary/40 text-foreground-primary size-full rounded-full border bg-transparent pr-4 pl-9 text-sm focus:outline-none"
                />
              </div>
            </.form>

            <.menu
              :if={!searching?(@query)}
              id="members-sort-menu"
              align="end"
              class="text-foreground-primary flex cursor-pointer items-center gap-1.5 text-sm font-medium sm:text-base"
            >
              <:trigger aria-label="Sort members">
                <Lucide.arrow_up_down class="size-[18px]" aria-hidden />
                <span>{Data.sort_label(@sort)}</span>
                <Lucide.chevron_down class="size-[18px]" aria-hidden />
              </:trigger>
              <div class="border-border-divider dark:bg-surface-base w-40 overflow-hidden rounded-md border bg-white p-0 shadow-lg">
                <.sort_link sort={:newest} current_sort={@sort} query={@query} label="Newest" />
                <.sort_link
                  sort={:most_active}
                  current_sort={@sort}
                  query={@query}
                  label="Most Active"
                />
                <.sort_link sort={:most_followed} current_sort={@sort} query={@query} label="Popular" />
              </div>
            </.menu>
          </div>
        </div>

        <.form for={%{}} as={:search} phx-change="search" class="pt-4 sm:hidden">
          <div class="relative h-10">
            <.search_icon
              class="text-foreground-primary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
              aria-hidden
            />
            <input
              type="search"
              name="q"
              value={@query}
              placeholder="Search username"
              phx-debounce="350"
              class="border-border-divider placeholder:text-foreground-primary/40 text-foreground-primary size-full rounded-lg border bg-transparent pr-4 pl-9 text-sm focus:outline-none"
            />
          </div>
        </.form>
      </div>

      <%= if searching?(@query) do %>
        <section>
          <p :if={@search_results != []} class="text-foreground-secondary mb-4 text-sm">
            {length(@search_results)} {pluralize(length(@search_results), "result", "results")} for "{@query}"
          </p>
          <p :if={@search_results == []} class="text-foreground-secondary mb-6">
            No members found for "{@query}"
          </p>
          <.members_grid users={@search_results} current_user={@current_user} />
        </section>
      <% else %>
        <section>
          <p :if={@members == []} class="text-foreground-secondary mt-6 text-center">
            No members found.
          </p>
          <.members_grid users={@members} current_user={@current_user} />

          <div :if={@has_next} class="my-6 flex w-full items-center justify-center lg:mt-10">
            <.load_more phx-click="load_more" />
          </div>
        </section>
      <% end %>
    </main>
    """
  end

  attr :users, :list, required: true
  attr :current_user, :any, default: nil

  def members_grid(assigns) do
    ~H"""
    <div :if={@users != []} class="flex flex-col items-center gap-5 md:gap-6">
      <div class="grid w-full grid-cols-2 gap-x-6 gap-y-8 sm:grid-cols-3 sm:gap-x-[29px] md:grid-cols-4 lg:gap-x-8 lg:gap-y-12">
        <.member_card :for={user <- @users} user={user} current_user={@current_user} />
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :current_user, :any, default: nil

  def member_card(assigns) do
    ~H"""
    <article class="flex w-full flex-col items-center justify-center text-center lg:w-[224px]">
      <div class="flex flex-col items-center justify-center gap-3 text-center">
        <div class="relative">
          <.link navigate={profile_path(@user)} class="block">
            <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
              user={@user}
              size="size-[108px] lg:size-[146px]"
              sizes="(max-width: 1023px) 108px, 146px"
              class="border border-white/12 dark:shadow-[0px_2px_6px_0px_rgba(0,0,0,0.25)]"
              fallback={:silhouette}
            />
          </.link>

          <div
            :if={@user.follow_state != :self}
            class="absolute right-[3px] bottom-[3px] lg:right-[4px] lg:bottom-[4px]"
          >
            <.follow_button user={@user} current_user={@current_user} />
          </div>
        </div>

        <.link
          navigate={profile_path(@user)}
          class="text-foreground-primary line-clamp-1 text-[13px]/4 font-semibold lg:text-[15px] lg:leading-[18px]"
        >
          {@user.display_name}
        </.link>
      </div>

      <div class="text-foreground-secondary mt-0.5 line-clamp-1 flex items-center gap-1 text-[11px] leading-[13px] lg:text-xs/4">
        <.link navigate={"#{profile_path(@user)}/library"}>
          {pluralize_count(@user.vns_count, "VN", "VNs")}
        </.link>
        <span class="text-[9px]">•</span>
        <.link navigate={"#{profile_path(@user)}/reviews"}>
          {pluralize_count(@user.reviews_count, "review", "reviews")}
        </.link>
      </div>

      <div class="mt-2 grid w-full grid-cols-4 gap-x-[3px] md:mt-3 md:gap-x-1">
        <.cover_thumb :for={vn <- @user.favorite_visual_novels} vn={vn} />
        <div
          :for={_index <- empty_cover_slots(@user.favorite_visual_novels)}
          class="pointer-events-none flex aspect-1/1.5 size-full items-center justify-center rounded-[2px] bg-white/2"
        />
      </div>
    </article>
    """
  end

  attr :user, :map, required: true
  attr :current_user, :any, default: nil

  def follow_button(assigns) do
    ~H"""
    <%= if @user.follow_state == :following do %>
      <button
        type="button"
        phx-click="unfollow"
        phx-value-id={@user.id}
        aria-label={"Unfollow #{@user.display_name}"}
        title={"Unfollow #{@user.display_name}"}
        class="bg-button-background-brand-default text-button-text-on-brand flex size-[30px] items-center justify-center rounded-full"
      >
        <Lucide.check class="size-4" aria-hidden />
      </button>
    <% else %>
      <button
        type="button"
        phx-click="follow"
        phx-value-id={@user.id}
        aria-label={"Follow #{@user.display_name}"}
        title={"Follow #{@user.display_name}"}
        class="bg-button-background-neutral-inverse-default text-surface-base flex size-[30px] items-center justify-center rounded-full"
      >
        <Lucide.plus class="size-4" aria-hidden />
      </button>
    <% end %>
    """
  end

  attr :vn, :map, required: true

  def cover_thumb(assigns) do
    ~H"""
    <.link
      navigate={"/vn/#{@vn.slug}"}
      class="aspect-1/1.5 overflow-hidden rounded-[2px] border border-white/12 dark:shadow-[0px_2px_6px_0px_rgba(0,0,0,0.40)]"
    >
      <KaguyaWeb.SharedComponents.Cover.cover
        vn={@vn}
        sizes="108px"
        class="rounded-[2px]"
        fallback_class="text-[10px]"
      />
    </.link>
    """
  end

  attr :sort, :atom, required: true
  attr :current_sort, :atom, required: true
  attr :query, :string, default: ""
  attr :label, :string, required: true

  def sort_link(assigns) do
    ~H"""
    <.link
      data-menu-dismiss
      patch={members_path(@sort, @query)}
      class="hover:bg-surface-elevated text-foreground-primary flex w-full items-center justify-between gap-4 px-5 py-2 text-left text-sm dark:hover:bg-white/5"
      aria-current={if @sort == @current_sort, do: "true"}
    >
      <span>{@label}</span>
      <Lucide.check :if={@sort == @current_sort} class="size-4" aria-hidden />
    </.link>
    """
  end

  defp refresh_member_follow(socket, id) do
    socket
    |> assign(
      :members,
      Data.update_follow_state(socket.assigns.members, id, socket.assigns.current_user)
    )
    |> assign(
      :search_results,
      Data.update_follow_state(socket.assigns.search_results, id, socket.assigns.current_user)
    )
  end

  defp members_path(sort, query) do
    params =
      [{"sort", Data.sort_to_slug(sort)}]
      |> maybe_put_query(query)
      |> URI.encode_query()

    "/members?#{params}"
  end

  defp maybe_put_query(params, query) do
    if Data.searching?(query), do: params ++ [{"q", query}], else: params
  end

  defp searching?(query), do: Data.searching?(query)

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_user), do: "#"

  defp pluralize_count(count, singular, plural),
    do: "#{count || 0} #{pluralize(count || 0, singular, plural)}"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp empty_cover_slots(favorites) do
    case max(0, 4 - length(favorites || [])) do
      0 -> []
      count -> 1..count
    end
  end
end
