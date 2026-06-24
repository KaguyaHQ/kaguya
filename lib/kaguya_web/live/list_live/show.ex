defmodule KaguyaWeb.ListLive.Show do
  use KaguyaWeb, :live_view

  alias Kaguya.Lists
  alias Kaguya.Pagination
  alias Kaguya.Users
  alias KaguyaWeb.Comments.ListAdapter
  alias KaguyaWeb.CommentsComponent
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.ListLive.Data
  alias KaguyaWeb.Lists.ShowComponents
  alias KaguyaWeb.SEO
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @base_url "https://kaguya.io"
  @comments_page_size 10

  @impl true
  def mount(_params, session, socket) do
    current_user = Map.get(socket.assigns, :current_user) || current_user_from_session(session)

    # `nav_viewer` is set by `KaguyaWeb.UserAuth.on_mount(:default, …)` from the
    # raw current_user map. Overriding it here with `Data.normalize_user/1`
    # quietly broke the navbar avatar — that fn pattern-matches on `%User{}`
    # but `current_user` is a plain map (`Map.from_struct/1` output), so it
    # always hit the all-nil fallback. Keep the upstream value.
    {:ok,
     assign(socket,
       current_user: current_user,
       state: :loading,
       page_title: "List - Kaguya",
       current_path: "/",
       route: nil,
       list: nil,
       raw_list: nil,
       owner: nil,
       items: [],
       tiers: [],
       list_pagination: empty_pagination(1, Data.list_page_size()),
       comments: [],
       comments_pagination: empty_pagination(1, @comments_page_size),
       list_page: 1,
       comments_page: 1,
       base_path: "/",
       base_path_with_list_page: "/",
       base_path_with_comments_page: "/",
       share_url: "",
       liked_by_me: false,
       likes_count: 0,
       is_mine: false,
       is_admin: false,
       is_hidden: false,
       is_hidden_for_viewer: false,
       can_comment: false,
       fade_read: false,
       tier_fullscreen: false,
       my_read_count: 0,
       total_count: 0,
       reading_percentage: 0.0,
       updated_from_now: "recently"
     )}
  end

  @impl true
  def handle_params(%{"username" => username, "slug" => slug} = params, uri, socket) do
    list_page = parse_page(params["listPage"])
    comments_page = parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:current_path, current_path(uri))
     |> load_page(username, slug, list_page, comments_page)}
  end

  @impl true
  def handle_event("toggle-like", params, socket), do: handle_event("toggle_like", params, socket)

  def handle_event("toggle_like", _params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         true <- socket.assigns.list.is_public,
         {:ok, true} <-
           toggle_like(socket.assigns.liked_by_me, socket.assigns.raw_list.id, user_id) do
      liked_by_me = !socket.assigns.liked_by_me
      delta = if liked_by_me, do: 1, else: -1

      {:noreply,
       socket
       |> assign(:liked_by_me, liked_by_me)
       |> assign(:likes_count, max((socket.assigns.likes_count || 0) + delta, 0))}
    else
      nil -> {:noreply, put_flash(socket, :error, "Sign in to like lists.")}
      false -> {:noreply, put_flash(socket, :error, "Private lists cannot be liked.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
      _ -> {:noreply, put_flash(socket, :error, "Could not update this like.")}
    end
  end

  def handle_event("toggle-visibility", params, socket),
    do: handle_event("toggle_visibility", params, socket)

  def handle_event("toggle_visibility", _params, socket) do
    with %{id: user_id} = user <- socket.assigns.current_user,
         true <- socket.assigns.is_mine,
         new_public? <- !socket.assigns.list.is_public,
         :ok <- ensure_can_make_public(user, new_public?),
         attrs <- visibility_attrs(socket.assigns.list, user_id, new_public?),
         {:ok, updated_list} <- Lists.update_list(socket.assigns.raw_list.id, attrs) do
      list =
        socket.assigns.list
        |> Map.put(:is_public, updated_list.is_public)
        |> Map.put(:updated_at, updated_list.updated_at)

      {:noreply,
       socket
       |> assign(:raw_list, updated_list)
       |> assign(:list, with_titles(list))
       |> assign(
         :updated_from_now,
         SharedTime.calendar_custom(updated_list.last_activity_at || updated_list.updated_at)
       )
       |> push_toast(
         :success,
         if(updated_list.is_public, do: "List is now public", else: "List is now private")
       )}
    else
      false -> {:noreply, put_flash(socket, :error, "Only the list owner can change visibility.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
      _ -> {:noreply, put_flash(socket, :error, "Only the list owner can change visibility.")}
    end
  end

  def handle_event("toggle-hidden", params, socket),
    do: handle_event("toggle_hidden", params, socket)

  def handle_event("toggle_hidden", _params, socket) do
    with %{id: actor_id} <- socket.assigns.current_user,
         true <- socket.assigns.is_admin,
         false <- socket.assigns.is_mine,
         {:ok, _list} <- toggle_hidden(socket.assigns.raw_list, actor_id) do
      message =
        if is_nil(socket.assigns.raw_list.hidden_at), do: "List hidden", else: "List unhidden"

      {:noreply,
       socket
       |> reload_current_page()
       |> push_toast(:success, message)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Moderator access is required.")}
    end
  end

  def handle_event("toggle-fade-read", params, socket),
    do: handle_event("toggle_fade_read", params, socket)

  def handle_event("toggle_fade_read", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :fade_read, !socket.assigns.fade_read)}
    else
      {:noreply, put_flash(socket, :error, "Sign in to fade read VNs.")}
    end
  end

  def handle_event("set_fade_read", %{"fade_read" => fade_read}, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :fade_read, truthy?(fade_read))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_tier_fullscreen", _params, socket) do
    {:noreply, assign(socket, :tier_fullscreen, true)}
  end

  def handle_event("close_tier_fullscreen", _params, socket) do
    {:noreply, assign(socket, :tier_fullscreen, false)}
  end

  def handle_event("create_comment", %{"content" => content}, socket) do
    content = String.trim(content || "")

    cond do
      is_nil(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Sign in to comment.")}

      !socket.assigns.can_comment ->
        {:noreply, put_flash(socket, :error, "Comments are not available for this list.")}

      content == "" ->
        {:noreply, put_flash(socket, :error, "Comment cannot be empty.")}

      true ->
        case Lists.create_list_comment(%{
               list_id: socket.assigns.raw_list.id,
               user_id: socket.assigns.current_user.id,
               content: content
             }) do
          {:ok, _comment} -> {:noreply, reload_current_page(socket)}
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
        end
    end
  end

  @impl true
  def render(%{state: :not_found} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-20 text-[rgb(var(--foreground-primary))]">
      <%= if @state == :loading or is_nil(@list) do %>
        <section class="mx-auto max-w-[1060px] px-4 py-20 text-sm text-[rgb(var(--foreground-secondary))]">
          Loading list...
        </section>
      <% else %>
        <section class="mx-auto mt-6 max-w-[1060px] gap-[84px] pb-[110px] sm:pb-32 lg:mt-10 lg:grid lg:grid-cols-[1fr_246px] lg:pb-[144px]">
          <div>
            <div class="space-y-6 md:max-lg:space-y-8 lg:space-y-9">
              <ShowComponents.list_header
                list={@list}
                owner={@owner}
                updated_from_now={@updated_from_now}
                reading_percentage={@reading_percentage}
                my_read_count={@my_read_count}
                total_count={@total_count}
              />

              <div>
                <%= if @is_hidden_for_viewer do %>
                  <div class="px-4 py-12 text-sm text-[rgb(var(--foreground-secondary))] md:px-8 lg:px-0">
                    This list has been hidden by moderators.
                  </div>
                <% else %>
                  <%= if @list.display_mode == "tier" do %>
                    <ShowComponents.tier_board
                      items={@items}
                      tiers={@tiers}
                      fade_read={@fade_read}
                      fullscreen={@tier_fullscreen}
                      list_name={@list.name}
                    />
                  <% else %>
                    <ShowComponents.list_grid
                      items={@items}
                      is_ranked={@list.is_ranked}
                      fade_read={@fade_read}
                    />
                  <% end %>

                  <ShowComponents.pagination
                    pagination={@list_pagination}
                    current_page={@list_page}
                    base_path={@base_path_with_comments_page}
                    page_param="listPage"
                  />
                <% end %>

                <div class="mt-8 px-4 md:px-8 lg:hidden">
                  <ShowComponents.actions_panel
                    list={@list}
                    owner={@owner}
                    liked_by_me={@liked_by_me}
                    likes_count={@likes_count}
                    is_mine={@is_mine}
                    is_public={@list.is_public}
                    is_logged_in={!is_nil(@current_user)}
                    is_admin={@is_admin}
                    is_hidden={@is_hidden}
                    total_count={@total_count}
                    current_count={@my_read_count}
                    reading_percentage={@reading_percentage}
                    fade_read={@fade_read}
                    panel_id="mobile"
                    mobile={true}
                    share_url={@share_url}
                  />
                </div>

                <div class="mt-6 mb-8 h-px bg-[rgb(var(--border-divider))] sm:max-lg:mb-6 lg:mt-12" />
              </div>

              <.live_component
                module={CommentsComponent}
                id="comments"
                adapter={ListAdapter}
                resource_id={@raw_list.id}
                current_user={@current_user}
                page={@comments_page}
                page_size={10}
                base_path={@base_path_with_list_page <> "#comments"}
                page_param="page"
              />
            </div>
          </div>

          <aside class="h-fit max-lg:hidden">
            <ShowComponents.actions_panel
              list={@list}
              owner={@owner}
              liked_by_me={@liked_by_me}
              likes_count={@likes_count}
              is_mine={@is_mine}
              is_public={@list.is_public}
              is_logged_in={!is_nil(@current_user)}
              is_admin={@is_admin}
              is_hidden={@is_hidden}
              total_count={@total_count}
              current_count={@my_read_count}
              reading_percentage={@reading_percentage}
              fade_read={@fade_read}
              panel_id="sidebar"
              share_url={@share_url}
            />
          </aside>
        </section>
      <% end %>
    </main>
    """
  end

  defp load_page(socket, username, slug, list_page, comments_page) do
    case Data.load_show_page(username, slug, list_page, socket.assigns.current_user,
           comments_page: comments_page
         ) do
      {:ok, payload} -> assign_payload(socket, username, slug, list_page, comments_page, payload)
      {:error, _reason} -> assign_not_found(socket)
    end
  end

  defp assign_payload(socket, username, slug, list_page, comments_page, payload) do
    list_pagination = normalize_pagination(payload.pagination, list_page, Data.list_page_size())

    comments_pagination =
      normalize_pagination(payload.comments_pagination, comments_page, @comments_page_size)

    list = with_titles(payload.list)
    owner = payload.user
    base_path = "/@#{owner.username}/list/#{list.slug}"
    total_count = list.vns_count || list_pagination.total_count || length(payload.visual_novels)

    socket
    |> assign(:state, :loaded)
    |> assign(:route, %{
      username: username,
      slug: slug,
      list_page: list_page,
      comments_page: comments_page
    })
    |> assign(:list, list)
    |> assign(:raw_list, payload.raw_list)
    |> assign(:owner, owner)
    |> assign(:items, payload.visual_novels)
    |> assign(:tiers, payload.tiers)
    |> assign(:list_pagination, list_pagination)
    |> assign(:comments, payload.comments)
    |> assign(:comments_pagination, comments_pagination)
    |> assign(:list_page, list_pagination.page)
    |> assign(:comments_page, comments_pagination.page)
    |> assign(:base_path, base_path)
    |> assign(
      :base_path_with_list_page,
      add_query_param(base_path, "listPage", list_pagination.page, 1)
    )
    |> assign(
      :base_path_with_comments_page,
      add_query_param(base_path, "page", comments_pagination.page, 1)
    )
    |> assign(:share_url, @base_url <> base_path)
    |> assign(:liked_by_me, payload.liked_by_me)
    |> assign(:likes_count, list.likes_count || 0)
    |> assign(:is_mine, payload.is_mine)
    |> assign(:is_admin, payload.can_moderate_lists)
    |> assign(:is_hidden, not is_nil(list.hidden_at))
    |> assign(:is_hidden_for_viewer, payload.is_hidden_for_viewer)
    |> assign(:can_comment, payload.is_logged_in and not payload.is_hidden_for_viewer)
    |> assign(:my_read_count, payload.my_read_count || 0)
    |> assign(:total_count, total_count)
    |> assign(:reading_percentage, reading_percentage(payload.my_read_count || 0, total_count))
    |> assign(
      :updated_from_now,
      SharedTime.calendar_custom(list.last_activity_at || list.updated_at || list.inserted_at)
    )
    |> assign(
      SEO.list(list, owner, payload.visual_novels,
        page: list_pagination.page,
        page_size: Data.list_page_size(),
        total_count: total_count
      )
    )
  end

  defp reload_current_page(socket) do
    route = socket.assigns.route
    load_page(socket, route.username, route.slug, route.list_page, route.comments_page)
  end

  defp assign_not_found(socket) do
    socket
    |> assign(SEO.list_not_found())
    |> assign(:state, :not_found)
  end

  defp normalize_pagination(pagination, page, page_size) do
    total_count = Pagination.resolve_count(pagination) || 0

    total_pages =
      Pagination.resolve_total_pages(pagination) ||
        max(div(total_count + page_size - 1, page_size), 1)

    %{
      page: Map.get(pagination, :page) || page,
      page_size: Map.get(pagination, :page_size) || page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp empty_pagination(page, page_size) do
    %{page: page, page_size: page_size, total_count: 0, total_pages: 1}
  end

  defp visibility_attrs(list, user_id, is_public) do
    %{
      user_id: user_id,
      name: list.name,
      description: list.description,
      is_ranked: list.is_ranked,
      display_mode: list.display_mode,
      is_public: is_public
    }
  end

  defp ensure_can_make_public(user, true) do
    if Data.can_publish_public_lists?(user),
      do: :ok,
      else: {:error, "Your public list privileges have been revoked"}
  end

  defp ensure_can_make_public(_user, false), do: :ok

  defp toggle_like(true, list_id, user_id), do: Lists.unlike_list(list_id, user_id)
  defp toggle_like(false, list_id, user_id), do: Lists.like_list(list_id, user_id)

  defp toggle_hidden(%{hidden_at: nil, id: list_id}, actor_id) do
    Lists.hide_list(list_id, %{
      actor_id: actor_id,
      reason: "Hidden from LiveView moderation action"
    })
  end

  defp toggle_hidden(%{id: list_id}, _actor_id), do: Lists.unhide_list(list_id)

  defp push_toast(socket, variant, message, description \\ nil) do
    push_event(socket, "toast", %{
      variant: to_string(variant),
      message: message,
      description: description
    })
  end

  defp with_titles(list) do
    Map.put(
      list,
      :updated_at_title,
      SharedTime.datetime_title(list.last_activity_at || list.updated_at || list.inserted_at)
    )
  end

  defp current_user_from_session(%{"current_user_id" => user_id}) when is_binary(user_id) do
    case Users.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp current_user_from_session(_session), do: nil

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp current_path(uri) do
    parsed = URI.parse(uri)
    path = parsed.path || "/"
    if parsed.query, do: path <> "?" <> parsed.query, else: path
  end

  defp add_query_param(path, _key, value, default) when value in [nil, default], do: path

  defp add_query_param(path, key, value, _default) do
    joiner = if String.contains?(path, "?"), do: "&", else: "?"
    path <> joiner <> "#{key}=#{value}"
  end

  defp reading_percentage(_read_count, total_count) when total_count in [nil, 0], do: 0.0

  defp reading_percentage(read_count, total_count),
    do: Float.round(read_count / total_count * 100, 1)

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(reason), do: inspect(reason)
end
