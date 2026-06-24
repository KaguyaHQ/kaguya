defmodule KaguyaWeb.ProfileLive.Library do
  @moduledoc """
  `/@:username/library` and `/@:username/library/:shelf` — user library
  with shelf tabs, sort, filter, search, and pagination.

  URL contract:
    * Shelf in path: `/@:username/library/:shelf` (`reading`, `read`,
      `wishlist`, `paused`, `did-not-finish`, `not-interested`, or a
      custom shelf slug).
    * Filters in the query string: `q`, `sort`, `rating`, `tag`, `producer`,
      `language`, `readYear`, `releaseYear`, `length`, `ageRating`, `page`.
    * Sort values match production kebab strings (`highest-rated`,
      `recently-added`, etc.). See `LibraryData.parse_sort/1`.

  Items are rendered through a LiveView stream (`@streams.library_items`).
  An `@items_state` map (vn_id → item) is kept alongside the stream to
  support optimistic mutations that need previous-item state (status flip,
  shelf toggle, date change) — see `update_item/4`. Parity with prod for
  parity-sensitive UI behavior lives in `docs/migrations/nextjs-liveview/parity/library-parity.md`.

  Client-side prefs (localStorage):
    * `fadeReadLibrary` → fade-read toggle (visible to non-owner viewers).
    * `showDatesLibrary` → show-dates toggle (visible to the owner).

  Bridged via the `LibraryPrefs` JS hook — see `assets/js/app.js`.
  """

  use KaguyaWeb.ProfileLive, tab: :library, title_suffix: "Library"

  alias Kaguya.Shelves
  alias KaguyaWeb.Components.Profile.Library.{ControlBar, Grid, Toolbar}
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.ProfileLive.LibraryData

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:library_items, dom_id: &"library-item-#{&1.vn.id}")
     |> assign(:state, :loading)
     |> assign(:profile, nil)
     |> assign(:permissions, %{any?: false})
     |> assign(:page_title, "Profile · Kaguya")
     |> assign(:current_tab, :library)
     |> assign(:root?, false)
     |> assign(:fade_read, false)
     |> assign(:show_dates, false)
     |> assign(:mobile_search_open, false)
     |> assign(:open_actions, %{})
     |> assign(:new_label_name, "")
     |> assign(:open_dropdown, nil)
     |> assign(:items_state, %{})
     |> assign(:loaded_count, 0)
     |> assign(:items_empty?, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        shelf = LibraryData.resolve_shelf(params["shelf"])
        filters = LibraryData.parse_filters(params)
        library = LibraryData.load_library(profile, viewer, shelf, filters)
        {items, library} = pop_items(library)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Library"))
         # The library is a personal tracking surface, not a publication: its
         # content is derivative of canonical VN pages, and its filter/sort/page
         # query-string variants generate thin near-duplicates (the GSC
         # "Duplicate without user-selected canonical" report). Goodreads blocks
         # the equivalent shelf pages outright; we noindex but keep `follow` so
         # crawlers still walk through to the VN pages linked in the grid.
         |> assign(KaguyaWeb.SEO.noindex())
         |> assign(:shelf, shelf)
         |> assign(:filters, filters)
         |> assign(:library, library)
         |> put_items(items, reset: true)
         |> assign(:mobile_search_open, not is_nil(filters.search) and filters.search != "")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  # ---------------------------------------------------------------------------
  # Event handlers — URL updates + localStorage bridge
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def handle_event("select_shelf", %{"value" => value}, socket) do
    shelf = shelf_from_value(value)
    filters = clear_shelf_specific_sort(socket.assigns.filters, shelf) |> reset_page()
    {:noreply, push_patch_to(socket, shelf, filters)}
  end

  def handle_event("clear_shelf", _params, socket) do
    filters = reset_page(socket.assigns.filters)
    {:noreply, push_patch_to(socket, {:all}, filters)}
  end

  def handle_event("set_sort", %{"value" => v}, socket),
    do: {:noreply, update_filter(socket, :sort, v)}

  def handle_event("clear_sort", _, socket), do: {:noreply, update_filter(socket, :sort, nil)}

  def handle_event("set_rating", %{"value" => v}, socket),
    do: {:noreply, update_filter(socket, :rating, v)}

  def handle_event("clear_rating", _, socket), do: {:noreply, update_filter(socket, :rating, nil)}

  def handle_event("set_tag", %{"value" => v}, socket),
    do: {:noreply, update_filter(socket, :tag_slug, v)}

  def handle_event("clear_tag", _, socket), do: {:noreply, update_filter(socket, :tag_slug, nil)}

  def handle_event("search", %{"value" => v}, socket),
    do: {:noreply, update_filter(socket, :search, v)}

  def handle_event("remove_filter", %{"key" => k}, socket),
    do: {:noreply, update_filter(socket, field_for(k), nil)}

  def handle_event("clear_search", _, socket) do
    {:noreply, socket |> assign(:mobile_search_open, false) |> update_filter(:search, nil)}
  end

  def handle_event("toggle_mobile_search", _params, socket) do
    if socket.assigns.mobile_search_open do
      filters = socket.assigns.filters |> Map.put(:search, nil) |> reset_page()

      {:noreply,
       socket
       |> assign(:mobile_search_open, false)
       |> push_patch_to(socket.assigns.shelf, filters)}
    else
      {:noreply, assign(socket, :mobile_search_open, true)}
    end
  end

  def handle_event("set_page", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {n, _} when n > 0 ->
        filters = Map.put(socket.assigns.filters, :page, n)
        {:noreply, push_patch_to(socket, socket.assigns.shelf, filters)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    page_size = LibraryData.mobile_page_size()
    next_page = max(2, div(socket.assigns.loaded_count, page_size) + 1)
    filters = Map.put(socket.assigns.filters, :page, next_page)

    more =
      LibraryData.load_library(
        socket.assigns.profile,
        socket.assigns[:current_user],
        socket.assigns.shelf,
        filters,
        page_size: page_size
      )

    {new_items, _} = pop_items(more)
    {:noreply, put_items(socket, new_items, reset: false)}
  end

  # localStorage bridge — pushed by the LibraryPrefs hook on mount/toggle.
  def handle_event("set_fade_read", %{"value" => value}, socket) do
    {:noreply, assign(socket, :fade_read, truthy(value))}
  end

  def handle_event("set_show_dates", %{"value" => value}, socket) do
    {:noreply, assign(socket, :show_dates, truthy(value))}
  end

  def handle_event("set_item_status", %{"vn-id" => vn_id, "status" => status}, socket) do
    with true <- owner?(socket),
         {:ok, new_status} <- status_from_value(status),
         %{} = item <- socket.assigns.items_state[vn_id] do
      previous_status = item.status
      updated = %{item | status: new_status}

      # Optimistic: stream-insert the patched item (or drop it if the row no
      # longer belongs to the active shelf), then shift count badges to match.
      optimistic =
        socket
        |> apply_item_update(updated)
        |> shift_status_counts(previous_status, new_status)
        |> maybe_drop_from_visible_shelf(updated)

      case Shelves.set_reading_status(socket.assigns.profile.id, vn_id, %{status: new_status}) do
        {:ok, _} ->
          {:noreply, close_library_dropdown_state(optimistic)}

        _ ->
          {:noreply,
           optimistic
           |> revert_item_update(item)
           |> shift_status_counts(new_status, previous_status)
           |> close_library_dropdown_state()
           |> put_flash(:error, "Could not update status")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_item_status", %{"vn-id" => vn_id}, socket) do
    with true <- owner?(socket),
         %{} = item <- socket.assigns.items_state[vn_id] do
      previous_status = item.status

      # Optimistic: pull the row out of the grid and decrement both the old
      # status tab and the (status-aware) "All" count. Revert on server error.
      optimistic =
        socket
        |> drop_item(item)
        |> decrement_status_counts(previous_status)

      case Shelves.delete_reading_status(socket.assigns.profile.id, vn_id) do
        {:ok, _} ->
          {:noreply, close_library_dropdown_state(optimistic)}

        _ ->
          {:noreply,
           optimistic
           |> apply_item_update(item)
           |> shift_status_counts(nil, previous_status)
           |> close_library_dropdown_state()
           |> put_flash(:error, "Could not remove VN")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_library_dropdown", %{"vn-id" => vn_id}, socket) do
    previous = socket.assigns.open_dropdown
    next = if previous == vn_id, do: nil, else: vn_id

    {:noreply,
     socket
     |> assign(:open_dropdown, next)
     |> assign(:open_actions, %{})
     |> restream_item(previous)
     |> restream_item(next)}
  end

  def handle_event("close_library_dropdown", _params, socket) do
    previous = socket.assigns.open_dropdown

    {:noreply,
     socket
     |> assign(:open_dropdown, nil)
     |> assign(:open_actions, %{})
     |> restream_item(previous)}
  end

  def handle_event("toggle_library_action", %{"vn-id" => vn_id, "action" => action}, socket) do
    current = Map.get(socket.assigns.open_actions, vn_id)
    new_action = parse_library_action(action)

    next_open =
      cond do
        new_action == nil -> socket.assigns.open_actions
        current == new_action -> Map.delete(socket.assigns.open_actions, vn_id)
        true -> Map.put(socket.assigns.open_actions, vn_id, new_action)
      end

    {:noreply,
     socket
     |> assign(:open_actions, next_open)
     |> restream_item(vn_id)}
  end

  def handle_event("close_library_action", _params, socket) do
    previous = socket.assigns.open_dropdown

    {:noreply,
     socket
     |> assign(:open_actions, %{})
     |> restream_item(previous)}
  end

  def handle_event("start_add_label", %{"vn-id" => vn_id}, socket) do
    {:noreply,
     socket
     |> assign(:open_actions, Map.put(socket.assigns.open_actions, vn_id, :add_label))
     |> assign(:new_label_name, "")
     |> restream_item(vn_id)}
  end

  def handle_event("cancel_add_label", _params, socket) do
    previous = socket.assigns.open_dropdown

    {:noreply,
     socket
     |> assign(:open_actions, %{})
     |> assign(:new_label_name, "")
     |> restream_item(previous)}
  end

  def handle_event("update_new_label_name", %{"name" => name}, socket) do
    # The input is `phx-change` so we only need to track the value; the form
    # re-renders from the per-item stream when the user submits/cancels.
    {:noreply, assign(socket, :new_label_name, name)}
  end

  def handle_event("create_label_for_vn", %{"vn-id" => vn_id, "name" => name}, socket) do
    name = String.trim(name)

    with true <- owner?(socket),
         true <- name != "",
         {:ok, shelf} <-
           Shelves.create_shelf(%{user_id: socket.assigns.profile.id, name: name}),
         {:ok, _} <-
           Shelves.add_vns_to_shelves(socket.assigns.profile.id, [shelf.id], [vn_id]) do
      {:noreply,
       socket
       |> reload_library()
       |> assign(:open_actions, Map.put(socket.assigns.open_actions, vn_id, :labels))
       |> assign(:new_label_name, "")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not create label")}
    end
  end

  def handle_event("toggle_item_shelf", %{"vn-id" => vn_id, "shelf-id" => shelf_id}, socket) do
    with true <- owner?(socket),
         %{} = item <- socket.assigns.items_state[vn_id] do
      selected? = Enum.any?(item.shelves || [], &(&1.id == shelf_id))
      shelf = Enum.find(socket.assigns.library.custom_shelves, &(&1.id == shelf_id))

      new_shelves =
        if selected?,
          do: Enum.reject(item.shelves || [], &(&1.id == shelf_id)),
          else: [shelf | item.shelves || []]

      optimistic = apply_item_update(socket, %{item | shelves: new_shelves})

      result =
        if selected?,
          do: Shelves.remove_vns_from_shelves(socket.assigns.profile.id, [shelf_id], [vn_id]),
          else: Shelves.add_vns_to_shelves(socket.assigns.profile.id, [shelf_id], [vn_id])

      case result do
        {:ok, _} -> {:noreply, optimistic}
        # Revert by reloading authoritative state.
        _ -> {:noreply, reload_library(optimistic)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # Shared events (toggle_follow, open_mod_panel) fall through to the parent
  # via the macro-injected handlers.

  @impl Phoenix.LiveView
  def handle_info({:library_date_picked, picker_id, change}, socket) do
    with true <- owner?(socket),
         "library-date-" <> vn_id <- picker_id,
         %{} = item <- socket.assigns.items_state[vn_id] do
      status = item.status || :read
      next_started = parse_date(change.date_started)
      next_finished = parse_date(change.date_finished)

      # Pass `%Date{}` structs through to the context — `Repo.insert_all` skips
      # the cast pipeline and would balk at raw ISO strings for `:date` fields.
      attrs = %{status: status, date_started: next_started, date_finished: next_finished}

      case Shelves.set_reading_status(socket.assigns.profile.id, vn_id, attrs) do
        {:ok, _} ->
          # `Shelves.upsert_statuses/3` treats `nil` as "leave the field alone".
          # When the user goes range → single, the orphaned column would persist
          # — run a targeted UPDATE to null it out.
          maybe_clear_orphan_dates(
            socket.assigns.profile.id,
            vn_id,
            item.date_started,
            item.date_finished,
            next_started,
            next_finished
          )

          updated = %{item | date_started: next_started, date_finished: next_finished}
          {:noreply, apply_item_update(socket, updated)}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not save reading dates.")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream + shadow-index helpers
  # ---------------------------------------------------------------------------

  defp pop_items(%{grid: %{items: items} = grid} = library) do
    {items, %{library | grid: %{grid | items: []}}}
  end

  defp pop_items(library), do: {[], library}

  defp put_items(socket, items, opts) do
    reset? = Keyword.get(opts, :reset, false)

    socket =
      if reset? do
        socket
        |> stream(:library_items, items, reset: true)
        |> assign(:items_state, Map.new(items, &{&1.vn.id, &1}))
        |> assign(:loaded_count, length(items))
      else
        # Skip duplicates already in the index — load_more can race with the
        # underlying query when items are added/removed between pages.
        new_items = Enum.reject(items, &Map.has_key?(socket.assigns.items_state, &1.vn.id))

        socket
        |> stream_each(new_items)
        |> assign(
          :items_state,
          Map.merge(socket.assigns.items_state, Map.new(new_items, &{&1.vn.id, &1}))
        )
        |> assign(:loaded_count, socket.assigns.loaded_count + length(new_items))
      end

    assign(socket, :items_empty?, socket.assigns.loaded_count == 0)
  end

  defp stream_each(socket, items) do
    Enum.reduce(items, socket, &stream_insert(&2, :library_items, &1))
  end

  defp apply_item_update(socket, item) do
    socket
    |> stream_insert(:library_items, item)
    |> assign(:items_state, Map.put(socket.assigns.items_state, item.vn.id, item))
  end

  # Re-emit an existing item through the stream so per-item template state
  # (open dropdown, open action) reflects the latest parent assigns. Streams
  # don't re-iterate consumed items on parent re-renders — anything visible
  # in the item template that depends on socket-level state must be paired
  # with a `stream_insert` to flush the update to the client.
  defp restream_item(socket, nil), do: socket

  defp restream_item(socket, vn_id) do
    case socket.assigns.items_state[vn_id] do
      nil -> socket
      item -> stream_insert(socket, :library_items, item)
    end
  end

  defp drop_item(socket, item) do
    socket
    |> stream_delete(:library_items, item)
    |> assign(:items_state, Map.delete(socket.assigns.items_state, item.vn.id))
    |> assign(:loaded_count, max(socket.assigns.loaded_count - 1, 0))
    |> then(&assign(&1, :items_empty?, &1.assigns.loaded_count == 0))
  end

  defp revert_item_update(socket, item) do
    socket
    |> stream_insert(:library_items, item)
    |> assign(:items_state, Map.put(socket.assigns.items_state, item.vn.id, item))
  end

  # If we're on a status-filtered shelf and the new status doesn't match,
  # hide the row so the user sees "it left the shelf I'm looking at".
  defp maybe_drop_from_visible_shelf(socket, item) do
    case socket.assigns[:shelf] do
      {:status, status} when status != item.status -> drop_item(socket, item)
      _ -> socket
    end
  end

  # ---------------------------------------------------------------------------
  # Count rebalancing — mirrors `Library.library_status_counts/2`. `:all`
  # excludes `:not_interested`.
  # ---------------------------------------------------------------------------

  defp shift_status_counts(socket, same, same), do: socket

  defp shift_status_counts(socket, previous, next) do
    update(socket, :library, fn library ->
      new_counts =
        library.counts
        |> apply_status_delta(previous, -1)
        |> apply_status_delta(next, +1)

      %{library | counts: new_counts}
    end)
  end

  defp decrement_status_counts(socket, previous) do
    update(socket, :library, fn library ->
      %{library | counts: apply_status_delta(library.counts, previous, -1)}
    end)
  end

  defp apply_status_delta(counts, nil, _delta), do: counts

  defp apply_status_delta(counts, status, delta) do
    counts = Map.update(counts, status, max(delta, 0), &max(&1 + delta, 0))

    if status == :not_interested do
      counts
    else
      Map.update(counts, :all, max(delta, 0), &max(&1 + delta, 0))
    end
  end

  # ---------------------------------------------------------------------------
  # Date/orphan helpers
  # ---------------------------------------------------------------------------

  defp maybe_clear_orphan_dates(
         user_id,
         vn_id,
         prev_started,
         prev_finished,
         next_started,
         next_finished
       ) do
    fields =
      []
      |> add_clear(:date_started, prev_started, next_started)
      |> add_clear(:date_finished, prev_finished, next_finished)

    case fields do
      [] -> :ok
      list -> Shelves.clear_reading_status_fields(user_id, vn_id, list)
    end
  end

  defp add_clear(list, key, previous, nil) when not is_nil(previous), do: [key | list]
  defp add_clear(list, _key, _previous, _next), do: list

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(_), do: nil

  # ---------------------------------------------------------------------------
  # Misc helpers
  # ---------------------------------------------------------------------------

  defp parse_library_action("labels"), do: :labels
  defp parse_library_action("status"), do: :status
  defp parse_library_action("dates"), do: :dates
  defp parse_library_action("add_label"), do: :add_label
  defp parse_library_action(_), do: nil

  defp shelf_from_value("ALL"), do: {:all}

  defp shelf_from_value(value) do
    case Enum.find(LibraryData.permanent_shelves(), &(&1.value == value)) do
      %{status: status} when is_atom(status) -> {:status, status}
      _ -> {:custom, value}
    end
  end

  defp status_from_value(value) do
    case Enum.find(LibraryData.permanent_shelves(), &(&1.value == value)) do
      %{status: status} when is_atom(status) -> {:ok, status}
      _ -> {:error, :invalid_status}
    end
  end

  defp owner?(socket) do
    profile = socket.assigns[:profile]
    viewer = socket.assigns[:current_user]

    profile && viewer && profile.id == viewer.id
  end

  defp close_library_dropdown_state(socket) do
    socket
    |> assign(:open_dropdown, nil)
    |> assign(:open_actions, %{})
  end

  defp reload_library(socket) do
    library =
      LibraryData.load_library(
        socket.assigns.profile,
        socket.assigns[:current_user],
        socket.assigns.shelf,
        socket.assigns.filters
      )

    {items, library} = pop_items(library)

    socket
    |> assign(:library, library)
    |> put_items(items, reset: true)
  end

  # When leaving the READ shelf, drop the read-specific sort options that
  # don't make sense elsewhere.
  defp clear_shelf_specific_sort(filters, shelf) do
    case {filters.sort, shelf} do
      {sort, {:status, :read}} when sort in [:date_finished_desc, :date_finished_asc] -> filters
      {sort, _} when sort in [:date_finished_desc, :date_finished_asc] -> %{filters | sort: nil}
      _ -> filters
    end
  end

  defp reset_page(filters), do: Map.put(filters, :page, 1)

  defp push_patch_to(socket, shelf, filters) do
    push_patch(socket,
      to: LibraryData.build_path(socket.assigns.profile.username, shelf, filters)
    )
  end

  # Single update path for all filter-field events: parse the raw value,
  # set it on the filter map, reset pagination, push the new URL. Each
  # field's parsing rule lives in `parse_filter_value/3`.
  defp update_filter(socket, field, raw) do
    current = Map.get(socket.assigns.filters, field)
    value = parse_filter_value(field, raw, current)
    filters = socket.assigns.filters |> Map.put(field, value) |> reset_page()
    push_patch_to(socket, socket.assigns.shelf, filters)
  end

  defp parse_filter_value(:sort, raw, current) do
    parsed = LibraryData.parse_sort(raw)
    # Clicking the active sort clears it (matches the prod toggle behavior).
    if parsed == current, do: nil, else: parsed
  end

  defp parse_filter_value(:rating, raw, _), do: parse_rating(raw)

  defp parse_filter_value(field, raw, _) when field in [:tag_slug, :search],
    do: blank_to_nil(raw)

  defp parse_filter_value(_, raw, _), do: raw

  defp parse_rating(""), do: nil
  defp parse_rating(nil), do: nil

  defp parse_rating(value) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_rating(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_), do: nil

  defp field_for("tag"), do: :tag_slug
  defp field_for("producer"), do: :producer_slug
  defp field_for("language"), do: :original_language
  defp field_for("readYear"), do: :read_year
  defp field_for("releaseYear"), do: :release_year
  defp field_for("length"), do: :length_category
  defp field_for("ageRating"), do: :age_rating
  defp field_for("rating"), do: :rating
  defp field_for("sort"), do: :sort
  defp field_for("search"), do: :search
  defp field_for("q"), do: :search
  defp field_for(_), do: :_unknown

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(1), do: true
  defp truthy("1"), do: true
  defp truthy(_), do: false

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <div
        id="library-prefs"
        phx-hook="LibraryPrefs"
        data-fade-read={to_string(@fade_read)}
        data-show-dates={to_string(@show_dates)}
        data-is-owner={to_string(@profile.viewer.is_mine)}
        data-is-logged-in={to_string(@profile.viewer.is_logged_in)}
        class="mt-8 lg:mt-10"
      >
        <div class="mx-auto mt-3 lg:mt-8 lg:max-w-[988px]">
          <Toolbar.toolbar
            shelf={@shelf}
            filters={@filters}
            counts={@library.counts}
            custom_shelves={@library.custom_shelves}
            tags={@library.tags}
            profile={@profile}
            fade_read={@fade_read}
            show_dates={@show_dates}
            mobile_search_open={@mobile_search_open}
          />

          <section class="h-full scroll-mt-24" id="vns">
            <div class="text-foreground-primary scroll-mt-32 rounded-[12px]">
              <ControlBar.control_bar
                shelf={@shelf}
                filters={@filters}
                tags={@library.tags}
                ratings_dist={@library.ratings_dist}
                profile={@profile}
                fade_read={@fade_read}
              />

              <ControlBar.active_filters
                filters={@filters}
                applied_producer={@library.applied_producer}
              />

              <Grid.grid
                items={@streams.library_items}
                items_empty?={@items_empty?}
                custom_shelves={@library.custom_shelves}
                profile={@profile}
                shelf={@shelf}
                fade_read={@fade_read}
                show_dates={@show_dates}
                open_actions={@open_actions}
                new_label_name={@new_label_name}
                open_dropdown={@open_dropdown}
              />

              <Grid.mobile_load_more
                loaded={@loaded_count}
                total={@library.grid.pagination.total_count || 0}
              />

              <Grid.pagination
                shelf={@shelf}
                filters={@filters}
                pagination={@library.grid.pagination}
                username={@profile.username}
              />
            </div>
          </section>
        </div>
      </div>
    </main>
    """
  end
end
