defmodule KaguyaWeb.VNLive.Show do
  use KaguyaWeb, :live_view

  require Logger

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.AuthPromptComponents
  alias KaguyaWeb.SEO
  alias KaguyaWeb.VN.{Backdrop, Collections, Community, Header, Sidebar}

  alias KaguyaWeb.VNLive.Show.{
    Components,
    Data,
    Filters,
    ListActions,
    MediaActions,
    QuoteActions,
    RecommendationActions,
    ReviewActions,
    StatusActions,
    TagActions
  }

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       release_filters: Filters.connect_param_release_filters(socket),
       slug: nil,
       page_title: "Visual Novel",
       has_backdrop: false,
       nav_transparent: false,
       public_vn: nil,
       display_vn: nil,
       reviews: nil,
       discussions: {:ok, []},
       characters: [],
       series: nil,
       related: [],
       recommendations: [],
       popular_lists: [],
       viewer_bundle: nil,
       viewer: nil,
       viewer_vn: nil,
       friend_activity: [],
       friend_reviews: [],
       pending_status: nil,
       pending_rating: nil,
       clear_status_dialog_open?: false,
       review_dialog_open: false,
       review_delete_dialog_open?: false,
       review_date_picker_open?: false,
       review_form: %{},
       review_save_error: nil,
       review_min_length_error?: false,
       list_dialog_open: false,
       shelves: [],
       selected_shelf_ids: [],
       new_shelf_name: "",
       create_shelf_error: nil,
       recommendation_dialog_open: false,
       recommendation_slug: "",
       quote_dialog_open: false,
       quote_text: "",
       media_lightbox: nil,
       action_drawer_open: false,
       reviews_sort: "MOST_LIKED",
       release_filter_options: %{languages: [], platforms: []},
       recommendation_query: "",
       recommendation_results: [],
       recommendation_search_error: nil,
       tag_dialog_open: false,
       tag_query: "",
       tag_results: [],
       tag_search_error: nil,
       active_tab: :tags,
       expanded_tag_kinds: [],
       tabs: %{},
       loading: true,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    page_num = Filters.parse_page(params["page"])
    sort = Filters.normalize_sort(params["sort"])
    current_user = socket.assigns.current_user
    initial_tab = live_action_tab(socket.assigns[:live_action])

    case timed_section(:core, fn ->
           PageData.get_public_page(slug, current_user,
             page: page_num,
             sort: Filters.sort_atom(sort)
           )
         end) do
      {:ok, vn, page_data} ->
        desktop_hero = backdrop_image_url(page_data.vn, current_user)
        has_backdrop = desktop_hero != nil

        # LCP preload hints: desktop hero is the backdrop screenshot; mobile is
        # the mobile backdrop when present, otherwise the cover. Emitted in the
        # document <head> by root.html.heex so the browser starts the fetch
        # during HTML parse rather than after layout.
        mobile_hero =
          backdrop_mobile_image_url(page_data.vn, current_user) ||
            get_in(page_data.vn, [:images, :small]) ||
            get_in(page_data.vn, [:images, :medium])

        socket =
          socket
          |> assign(SEO.vn(page_data.vn))
          |> noindex_media_tabs(initial_tab)
          |> assign(
            slug: slug,
            preload_hero_image_desktop: desktop_hero,
            preload_hero_image_mobile: mobile_hero,
            has_backdrop: has_backdrop,
            nav_transparent: has_backdrop,
            public_vn: page_data.vn,
            display_vn: Data.build_display_vn(page_data.vn, nil),
            reviews: page_data.reviews,
            discussions: :loading,
            characters: page_data.characters,
            series: page_data.series,
            related: page_data.related,
            recommendations: page_data.recommendations,
            popular_lists: page_data.popular_lists,
            viewer_bundle: nil,
            viewer: nil,
            viewer_vn: nil,
            friend_activity: [],
            friend_reviews: [],
            clear_status_dialog_open?: false,
            review_dialog_open: false,
            review_delete_dialog_open?: false,
            review_date_picker_open?: false,
            review_form: %{},
            review_save_error: nil,
            review_min_length_error?: false,
            list_dialog_open: false,
            new_shelf_name: "",
            create_shelf_error: nil,
            recommendation_dialog_open: false,
            quote_dialog_open: false,
            quote_text: "",
            media_lightbox: nil,
            action_drawer_open: false,
            reviews_sort: sort,
            release_filter_options: %{languages: [], platforms: []},
            recommendation_query: "",
            recommendation_results: [],
            recommendation_search_error: nil,
            tag_dialog_open: false,
            tag_query: "",
            tag_results: [],
            tag_search_error: nil,
            active_tab: initial_tab,
            expanded_tag_kinds: [],
            tabs: Data.build_tabs(page_data.vn, page_data),
            loading: false
          )
          |> maybe_start_tab_async(initial_tab)
          |> maybe_start_discussions_async(vn, current_user)
          |> maybe_start_viewer_async(vn, current_user)
          |> maybe_start_friends_async(vn, current_user)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(SEO.vn_not_found())
         |> assign(
           slug: slug,
           not_found?: true,
           loading: false
         )}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = tab_atom(tab)

    socket =
      socket
      |> assign(active_tab: tab)
      |> maybe_start_tab_async(tab)

    {:noreply, socket}
  end

  def handle_event("toggle_tag_kind", %{"kind" => kind}, socket) do
    expanded = socket.assigns.expanded_tag_kinds

    next =
      if kind in expanded, do: List.delete(expanded, kind), else: [kind | expanded]

    {:noreply, assign(socket, expanded_tag_kinds: next)}
  end

  def handle_event("open_action_drawer", _params, socket) do
    {:noreply, assign(socket, action_drawer_open: true)}
  end

  def handle_event("close_action_drawer", _params, socket) do
    {:noreply, assign(socket, action_drawer_open: false)}
  end

  def handle_event("set_release_filters", %{"release_filters" => filters}, socket) do
    filters = Filters.normalize_release_filters(filters)

    socket =
      socket
      |> assign(release_filters: filters)
      |> update_releases_for_filters()

    {:noreply, socket}
  end

  def handle_event("set_status", params, socket),
    do: socket |> ensure_viewer_bundle() |> StatusActions.set_status(params)

  def handle_event("clear_status", params, socket),
    do: socket |> ensure_viewer_bundle() |> StatusActions.clear_status(params)

  def handle_event("close_clear_status_dialog", params, socket),
    do: StatusActions.close_clear_status_dialog(socket, params)

  def handle_event("confirm_clear_status", params, socket),
    do: socket |> ensure_viewer_bundle() |> StatusActions.confirm_clear_status(params)

  def handle_event("set_rating", params, socket),
    do: socket |> ensure_viewer_bundle() |> StatusActions.set_rating(params)

  def handle_event("clear_rating", params, socket),
    do: socket |> ensure_viewer_bundle() |> StatusActions.clear_rating(params)

  def handle_event("toggle_review_like", params, socket),
    do: socket |> ensure_viewer_bundle() |> ReviewActions.toggle_review_like(params)

  def handle_event("open_review_dialog", params, socket),
    do: socket |> ensure_viewer_bundle() |> ReviewActions.open_review_dialog(params)

  def handle_event("close_review_dialog", params, socket),
    do: ReviewActions.close_review_dialog(socket, params)

  def handle_event("open_review_delete_dialog", _params, socket),
    do: {:noreply, assign(socket, review_delete_dialog_open?: true)}

  def handle_event("close_review_delete_dialog", _params, socket),
    do: {:noreply, assign(socket, review_delete_dialog_open?: false)}

  def handle_event("update_review_form", params, socket),
    do: ReviewActions.update_review_form(socket, params)

  def handle_event("set_review_form_rating", params, socket),
    do: ReviewActions.set_review_form_rating(socket, params)

  def handle_event("save_review", params, socket),
    do: socket |> ensure_viewer_bundle() |> ReviewActions.save_review(params)

  def handle_event("toggle_review_date_picker", _params, socket),
    do:
      {:noreply,
       Phoenix.Component.assign(
         socket,
         :review_date_picker_open?,
         not socket.assigns.review_date_picker_open?
       )}

  def handle_event("close_review_date_picker", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :review_date_picker_open?, false)}

  def handle_event("delete_review", params, socket),
    do: socket |> ensure_viewer_bundle() |> ReviewActions.delete_review(params)

  def handle_event("open_list_dialog", params, socket),
    do: socket |> ensure_viewer_bundle() |> ListActions.open_list_dialog(params)

  def handle_event("close_list_dialog", params, socket),
    do: ListActions.close_list_dialog(socket, params)

  def handle_event("change_shelf_name", params, socket),
    do: ListActions.change_shelf_name(socket, params)

  def handle_event("update_list_membership", params, socket),
    do: ListActions.update_list_membership(socket, params)

  def handle_event("save_list_membership", params, socket),
    do: socket |> ensure_viewer_bundle() |> ListActions.save_list_membership(params)

  def handle_event("create_shelf", params, socket),
    do: socket |> ensure_viewer_bundle() |> ListActions.create_shelf(params)

  def handle_event("open_recommendation_dialog", params, socket),
    do: RecommendationActions.open_recommendation_dialog(socket, params)

  def handle_event("open_recommendation_search", params, socket),
    do: RecommendationActions.open_recommendation_search(socket, params)

  def handle_event("close_recommendation_dialog", params, socket),
    do: RecommendationActions.close_recommendation_dialog(socket, params)

  def handle_event("search_recommendations", params, socket),
    do: RecommendationActions.search_recommendations(socket, params)

  def handle_event("add_recommendation", params, socket),
    do: RecommendationActions.add_recommendation(socket, params)

  def handle_event("vote_recommendation", params, socket),
    do: RecommendationActions.vote_recommendation(socket, params)

  def handle_event("vote_tag", params, socket), do: TagActions.vote_tag(socket, params)

  def handle_event("clear_tag_vote", params, socket),
    do: TagActions.clear_tag_vote(socket, params)

  def handle_event("open_tag_dialog", params, socket),
    do: TagActions.open_tag_dialog(socket, params)

  def handle_event("close_tag_dialog", params, socket),
    do: TagActions.close_tag_dialog(socket, params)

  def handle_event("search_tags", params, socket), do: TagActions.search_tags(socket, params)

  def handle_event("add_tag", params, socket), do: TagActions.add_tag(socket, params)

  def handle_event("open_quote_dialog", params, socket),
    do: QuoteActions.open_quote_dialog(socket, params)

  def handle_event("close_quote_dialog", params, socket),
    do: QuoteActions.close_quote_dialog(socket, params)

  def handle_event("save_quote", params, socket), do: QuoteActions.save_quote(socket, params)

  def handle_event("toggle_quote_like", params, socket),
    do: QuoteActions.toggle_quote_like(socket, params)

  def handle_event("toggle_cover_like", params, socket),
    do: MediaActions.toggle_cover_like(socket, params)

  def handle_event("toggle_screenshot_like", params, socket),
    do: MediaActions.toggle_screenshot_like(socket, params)

  def handle_event("open_media_lightbox", params, socket),
    do: MediaActions.open_media_lightbox(socket, params)

  def handle_event("close_media_lightbox", params, socket),
    do: MediaActions.close_media_lightbox(socket, params)

  def handle_event("previous_media", params, socket),
    do: MediaActions.previous_media(socket, params)

  def handle_event("next_media", params, socket), do: MediaActions.next_media(socket, params)

  @impl true
  def handle_async({:vn_tab, :releases, slug}, {:ok, {:ok, release_data}}, socket) do
    if socket.assigns.slug == slug do
      {:noreply,
       socket
       |> assign(
         release_filters: release_data.filters,
         release_filter_options: release_data.filter_options
       )
       |> put_tab_state(:releases, {:ok, release_data.items})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_tab, tab, slug}, {:ok, {:ok, items}}, socket) do
    if socket.assigns.slug == slug do
      {:noreply, put_tab_state(socket, tab, {:ok, items})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_tab, tab, slug}, {:ok, {:error, reason}}, socket) do
    if socket.assigns.slug == slug do
      {:noreply, put_tab_state(socket, tab, {:error, reason})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_tab, tab, slug}, {:exit, reason}, socket) do
    if socket.assigns.slug == slug do
      {:noreply, put_tab_state(socket, tab, {:error, reason})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_discussions, slug}, {:ok, {:ok, discussions}}, socket) do
    if socket.assigns.slug == slug do
      {:noreply, assign(socket, discussions: {:ok, discussions})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_discussions, slug}, _result, socket) do
    if socket.assigns.slug == slug do
      {:noreply, assign(socket, discussions: {:error, :load_failed})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_viewer, slug}, {:ok, {:ok, bundle}}, socket) do
    if socket.assigns.slug == slug and is_nil(socket.assigns.viewer_bundle) do
      {:noreply, Data.assign_viewer_bundle(socket, bundle)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_viewer, _slug}, _result, socket), do: {:noreply, socket}

  def handle_async({:vn_friends, slug}, {:ok, {:ok, friends}}, socket) do
    if socket.assigns.slug == slug do
      {:noreply, Data.assign_friends(socket, friends)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:vn_friends, _slug}, _result, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:review_date_picked, _id, change}, socket),
    do: ReviewActions.apply_review_date_change(socket, change)

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <KaguyaWeb.Components.Shared.NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[rgb(var(--surface-base))] text-[rgb(var(--foreground-primary))]">
      <%= if @loading or is_nil(@public_vn) do %>
        <div class="mx-auto max-w-6xl px-4 py-20 text-sm text-[rgb(var(--foreground-tertiary))]">
          Loading visual novel...
        </div>
      <% else %>
        <div class={["relative", @has_backdrop && "lg:-mt-[72px]"]}>
          <Backdrop.vn_backdrop
            image_url={backdrop_image_url(@public_vn, @current_user)}
            mobile_image_url={backdrop_mobile_image_url(@public_vn, @current_user)}
          />

          <div class={[
            "relative z-10 mx-auto max-w-[1149px] gap-x-[18px] pb-16 sm:pb-32 lg:grid lg:grid-cols-[232px_1fr] lg:px-6",
            @has_backdrop && "lg:pt-[460px]",
            !@has_backdrop && "pt-6 lg:pt-8"
          ]}>
            <Sidebar.vn_sidebar
              vn={@display_vn}
              display_vn={@display_vn}
              viewer={@viewer}
              viewer_vn={@viewer_vn}
              auth={if @current_user, do: %{ok: true}, else: nil}
              current_path={Filters.current_path(@slug, @reviews_sort, @reviews)}
            />

            <div class="flex min-w-0 flex-col gap-12 lg:gap-[18px] lg:*:last:pb-0">
              <Header.vn_desktop_header
                vn={@display_vn}
                active_tab={@active_tab}
                tabs={@tabs}
                release_filters={@release_filters}
                release_filter_options={@release_filter_options}
                expanded_tag_kinds={@expanded_tag_kinds}
                current_user={@current_user}
                is_logged_in={!is_nil(@current_user)}
                user_can_edit={Data.can_edit_content?(@current_user)}
              />
              <Header.vn_mobile_header
                vn={@display_vn}
                active_tab={@active_tab}
                tabs={@tabs}
                release_filters={@release_filters}
                release_filter_options={@release_filter_options}
                expanded_tag_kinds={@expanded_tag_kinds}
                viewer={@viewer}
                viewer_vn={@viewer_vn}
                auth={if @current_user, do: %{ok: true}, else: nil}
                current_path={Filters.current_path(@slug, @reviews_sort, @reviews)}
                current_user={@current_user}
                is_logged_in={!is_nil(@current_user)}
                user_can_edit={Data.can_edit_content?(@current_user)}
              />
              <Header.reading_stats_row vn={@display_vn} />
              <Community.friend_activity_section activity_items={@friend_activity} vn_slug={@slug} />
              <Community.friend_reviews_section
                vn_slug={@slug}
                viewer_username={@viewer && @viewer.username}
                review_items={@friend_reviews}
                liked_review_ids={Data.liked_review_ids(@viewer_vn)}
              />
              <Community.reviews_section
                vn={@public_vn}
                reviews={@reviews}
                sort={@reviews_sort}
                is_logged_in={!is_nil(@current_user)}
                liked_review_ids={Data.liked_review_ids(@viewer_vn)}
              />
              <Collections.characters_section
                characters={@characters}
                slug={@slug}
                user_can_edit={Data.can_edit_db?(@current_user)}
              />
              <Collections.series_section series={@series} />
              <Collections.related_section :if={is_nil(@series)} relations={@related} />
              <Collections.recommendations_section
                recommendations={@recommendations}
                slug={@slug}
                user_can_edit={Data.can_edit_content?(@current_user)}
                is_logged_in={!is_nil(@current_user)}
              />
              <Collections.popular_lists_section lists={@popular_lists} slug={@slug} />
              <Community.discussions_section discussions={@discussions} vn_slug={@slug} />
            </div>
          </div>
        </div>
      <% end %>

      <AuthPromptComponents.auth_prompt_modal
        id="vn-auth-prompt"
        message={@auth_prompt_message}
        return_to={@current_path}
      />
      <Components.review_dialog
        :if={@review_dialog_open}
        vn={@display_vn}
        form={@review_form}
        has_review?={!!get_in(@viewer_vn || %{}, [:my_review])}
        save_error={@review_save_error}
        min_length_error?={@review_min_length_error?}
        date_picker_open?={@review_date_picker_open?}
        draft_key={review_draft_key(@current_user, @display_vn)}
      />
      <Components.review_delete_dialog
        :if={@review_delete_dialog_open?}
        draft_key={review_draft_key(@current_user, @display_vn)}
      />
      <Components.clear_status_dialog :if={@clear_status_dialog_open?} />
      <Components.list_dialog
        :if={@list_dialog_open}
        shelves={@shelves}
        selected_ids={@selected_shelf_ids}
        initial_ids={Enum.map(get_in(@viewer_vn || %{}, [:my_shelves]) || [], & &1.id)}
        vn_title={@display_vn.title}
        new_shelf_name={@new_shelf_name}
        create_shelf_error={@create_shelf_error}
      />
      <Components.recommendation_dialog :if={@recommendation_dialog_open} />
      <Components.tag_dialog
        :if={@tag_dialog_open}
        query={@tag_query}
        results={@tag_results}
        error={@tag_search_error}
      />
      <Components.quote_dialog :if={@quote_dialog_open} characters={@characters} />
      <Components.media_lightbox :if={@media_lightbox} media={@media_lightbox} />
      <div
        :if={@action_drawer_open}
        id="action-drawer-scroll-lock"
        class="hidden"
        phx-window-keydown="close_action_drawer"
        phx-key="Escape"
        phx-mounted={JS.add_class("overflow-hidden", to: "body")}
        phx-remove={JS.remove_class("overflow-hidden", to: "body")}
      >
      </div>
      <Sidebar.mobile_action_drawer
        :if={@action_drawer_open}
        viewer={@viewer}
        viewer_vn={@viewer_vn}
        auth={if @current_user, do: %{ok: true}, else: nil}
        current_path={Filters.current_path(@slug, @reviews_sort, @reviews)}
      />
    </div>
    """
  end

  defp tab_atom(tab) when tab in ~w(tags covers screenshots releases quotes),
    do: String.to_existing_atom(tab)

  defp tab_atom(_), do: :tags

  defp live_action_tab(action) when action in [:quotes, :covers, :screenshots], do: action
  defp live_action_tab(_), do: :tags

  # Cover/screenshot galleries are thin media grids derivative of the VN page;
  # noindex them. The main page and /quotes stay indexable (SEO.vn already sets
  # those to index).
  defp noindex_media_tabs(socket, tab) when tab in [:covers, :screenshots],
    do: assign(socket, SEO.noindex())

  defp noindex_media_tabs(socket, _tab), do: socket

  # Per-user, per-VN key for the client-side review draft (localStorage). Scoping
  # to the user keeps drafts from leaking across accounts on a shared device;
  # scoping to the VN lets someone draft reviews for several titles at once.
  # Returns nil when either is missing so the hook simply no-ops.
  defp review_draft_key(%{id: user_id}, %{id: vn_id})
       when not is_nil(user_id) and not is_nil(vn_id),
       do: "kaguya:review-draft:#{user_id}:#{vn_id}"

  defp review_draft_key(_user, _vn), do: nil

  defp maybe_start_discussions_async(socket, vn, current_user) do
    if connected?(socket) do
      start_async(socket, {:vn_discussions, socket.assigns.slug}, fn ->
        timed_section(:discussions, fn -> PageData.get_discussions(vn, current_user) end)
      end)
    else
      socket
    end
  end

  defp maybe_start_viewer_async(socket, _vn, nil), do: socket

  defp maybe_start_viewer_async(socket, vn, current_user) do
    if connected?(socket) do
      start_async(socket, {:vn_viewer, socket.assigns.slug}, fn ->
        timed_section(:viewer, fn -> PageData.viewer_bundle_for_vn(vn, current_user) end)
      end)
    else
      socket
    end
  end

  defp maybe_start_friends_async(socket, _vn, nil), do: socket

  defp maybe_start_friends_async(socket, vn, current_user) do
    if connected?(socket) do
      start_async(socket, {:vn_friends, socket.assigns.slug}, fn ->
        timed_section(:friends, fn -> PageData.friends_for_vn(vn, current_user) end)
      end)
    else
      socket
    end
  end

  defp maybe_start_tab_async(socket, :tags), do: socket

  defp maybe_start_tab_async(socket, tab) do
    case Map.get(socket.assigns.tabs, tab) do
      :not_loaded ->
        socket
        |> put_tab_state(tab, :loading)
        |> start_tab_async(tab)

      _ ->
        socket
    end
  end

  defp start_tab_async(socket, tab) do
    if connected?(socket) do
      slug = socket.assigns.slug
      current_user = socket.assigns.current_user
      filters = if tab == :releases, do: socket.assigns.release_filters, else: %{}

      start_async(socket, {:vn_tab, tab, slug}, fn ->
        timed_section(:"tab.#{tab}", fn -> PageData.get_tab(slug, tab, current_user, filters) end)
      end)
    else
      socket
    end
  end

  defp update_releases_for_filters(%{assigns: %{active_tab: :releases}} = socket) do
    socket
    |> put_tab_state(:releases, :loading)
    |> start_tab_async(:releases)
  end

  defp update_releases_for_filters(socket), do: put_tab_state(socket, :releases, :not_loaded)

  defp put_tab_state(socket, tab, state) do
    update(socket, :tabs, &Map.put(&1, tab, state))
  end

  defp ensure_viewer_bundle(%{assigns: %{viewer_bundle: %{}}} = socket), do: socket
  defp ensure_viewer_bundle(%{assigns: %{current_user: nil}} = socket), do: socket

  defp ensure_viewer_bundle(socket) do
    case timed_section(:viewer, fn ->
           PageData.get_viewer_bundle(socket.assigns.slug, socket.assigns.current_user)
         end) do
      {:ok, bundle} -> Data.assign_viewer_bundle(socket, bundle)
      _ -> socket
    end
  end

  defp timed_section(section, fun) when is_function(fun, 0) do
    started_at = System.monotonic_time()

    try do
      fun.()
    after
      duration = System.monotonic_time() - started_at
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      section_name = "vn_page.#{section}"

      :telemetry.execute(
        [:kaguya, :vn_page, section],
        %{duration: duration, duration_ms: duration_ms},
        %{section: section_name}
      )

      if duration_ms >= 50 do
        Logger.info("#{section_name} completed in #{duration_ms}ms")
      end
    end
  end

  # Backdrop = hero screenshot. If the screenshot's own moderation
  # flags would have hidden it in the Screenshots tab for this viewer,
  # also suppress it here so we don't leak it through the page hero.
  defp backdrop_image_url(public_vn, current_user) do
    if backdrop_visible?(public_vn, current_user) do
      get_in(public_vn, [:featured_screenshot, :large])
    end
  end

  defp backdrop_mobile_image_url(public_vn, current_user) do
    if backdrop_visible?(public_vn, current_user) do
      get_in(public_vn, [:featured_screenshot, :medium]) ||
        get_in(public_vn, [:featured_screenshot, :large])
    end
  end

  defp backdrop_visible?(public_vn, current_user) do
    featured = Map.get(public_vn, :featured_screenshot) || %{}

    cond do
      Map.get(featured, :is_nsfw) == true and
          not Map.get(current_user || %{}, :show_nsfw_screenshots, false) ->
        false

      Map.get(featured, :is_brutal) == true and
          not Map.get(current_user || %{}, :show_brutal_screenshots, false) ->
        false

      true ->
        true
    end
  end
end
