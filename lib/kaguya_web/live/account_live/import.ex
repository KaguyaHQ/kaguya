defmodule KaguyaWeb.AccountLive.Import do
  use KaguyaWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import KaguyaWeb.Import.VndbImportComponents
  import KaguyaWeb.UI.Switch

  alias Kaguya.{Repo, Shelves}
  alias Kaguya.Users.VndbImport
  alias KaguyaWeb.Import.VndbImportFlow
  alias KaguyaWeb.SharedComponents.DateRangePicker
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @summary_initial_count 20
  @missed_initial_count 5

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      {:ok,
       socket
       |> assign(:page_title, "Import your library - Kaguya")
       |> assign(:meta_description, "Import your VNDB library into Kaguya.")
       |> assign(KaguyaWeb.SEO.noindex())
       |> assign(:show_instructions, true)
       |> assign(:show_all_items, false)
       |> assign(:show_all_missing, false)
       |> assign(:show_all_banned, false)
       |> assign(:vote_fallback_stats, %{eligible_count: 0, applied_count: 0})
       |> assign(:open_picker_vn_id, nil)
       |> VndbImportFlow.init()}
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :summary -> load_summary(socket, params)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:poll_import, socket) do
    VndbImportFlow.poll_import(socket)
  end

  def handle_info({:finish_import, _import_id}, socket) do
    # `load_summary` falls back to `latest_completed_import` when no id is
    # present, so we don't need to advertise the UUID in the URL bar.
    {:noreply,
     socket
     |> VndbImportFlow.unsubscribe()
     |> push_patch(to: ~p"/account/import/summary")}
  end

  def handle_info({:vndb_import_updated, %VndbImport{} = import}, socket) do
    VndbImportFlow.import_updated(socket, import)
  end

  def handle_info({:vndb_import_enqueued, result}, socket) do
    VndbImportFlow.import_enqueued(socket, result)
  end

  def handle_info(:import_progress_tick, socket) do
    VndbImportFlow.progress_tick(socket)
  end

  def handle_info({:complete_import_progress_tick, import_id, from, step, steps}, socket) do
    VndbImportFlow.completion_tick(socket, import_id, from, step, steps)
  end

  def handle_info({:import_date_picked, picker_id, change}, socket) do
    case vn_id_from_picker_id(picker_id) do
      nil ->
        {:noreply, socket}

      vn_id ->
        {:noreply, apply_import_date_change(socket, vn_id, change)}
    end
  end

  @impl true
  def handle_event("show-upload", _params, socket) do
    {:noreply, assign(socket, :show_instructions, false)}
  end

  def handle_event("reset-import", _params, socket) do
    {:noreply,
     socket
     |> VndbImportFlow.reset()
     |> assign(:show_instructions, false)}
  end

  def handle_event("select-import-file", params, socket) do
    {:noreply, VndbImportFlow.select_file(socket, params)}
  end

  def handle_event("request-import-upload", params, socket) do
    VndbImportFlow.request_upload(socket, params)
  end

  def handle_event("import-file-error", %{"message" => message}, socket) do
    {:noreply, VndbImportFlow.file_error(socket, message)}
  end

  def handle_event("start-import", params, socket) do
    {:noreply, VndbImportFlow.start_import(socket, socket.assigns.current_user.id, params)}
  end

  def handle_event("show-all-items", _params, socket) do
    {:noreply, assign(socket, :show_all_items, true)}
  end

  def handle_event("toggle-missing", _params, socket) do
    {:noreply, Phoenix.Component.update(socket, :show_all_missing, &(!&1))}
  end

  def handle_event("toggle-banned", _params, socket) do
    {:noreply, Phoenix.Component.update(socket, :show_all_banned, &(!&1))}
  end

  def handle_event("toggle-vote-fallback", %{"enabled" => "true"}, socket) do
    import = socket.assigns.import

    with %VndbImport{} <- import,
         {:ok, _count} <-
           Shelves.apply_vote_date_fallback(socket.assigns.current_user.id, import.id) do
      {:noreply, refresh_vote_fallback(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update read dates.")}
    end
  end

  def handle_event("toggle-vote-fallback", _params, socket) do
    import = socket.assigns.import

    with %VndbImport{} <- import,
         {:ok, _count} <-
           Shelves.revert_vote_date_fallback(socket.assigns.current_user.id, import.id) do
      {:noreply, refresh_vote_fallback(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update read dates.")}
    end
  end

  def handle_event("toggle_import_date_picker", %{"vn-id" => vn_id}, socket) do
    next = if socket.assigns.open_picker_vn_id == vn_id, do: nil, else: vn_id
    {:noreply, assign(socket, :open_picker_vn_id, next)}
  end

  def handle_event("close_import_date_picker", _params, socket) do
    {:noreply, assign(socket, :open_picker_vn_id, nil)}
  end

  @impl true
  def render(%{live_action: :summary} = assigns) do
    ~H"""
    <div class="mx-auto flex max-w-[988px] flex-col gap-11 px-4 py-10 sm:gap-14 sm:py-16">
      <%= if @import && @import.status == "completed" && summary(@import) do %>
        <.summary_view
          import={@import}
          result={summary(@import)}
          user={@current_user}
          vote_fallback_stats={@vote_fallback_stats}
          show_all_items={@show_all_items}
          show_all_missing={@show_all_missing}
          show_all_banned={@show_all_banned}
          open_picker_vn_id={@open_picker_vn_id}
        />
      <% else %>
        <div class="mx-auto flex max-w-[438px] flex-col items-center py-20 text-center">
          <h1 class="text-foreground-primary mb-3 text-[24px] leading-[1.3] font-normal sm:text-[32px]">
            No completed import yet
          </h1>
          <p class="text-foreground-secondary text-style-body2Regular">
            Start a VNDB import and the summary will appear here when processing finishes.
          </p>
          <.link
            navigate={~p"/account/import"}
            class="bg-button-background-brand-default text-button-text-on-brand text-style-body2Medium mt-8 inline-flex h-10 items-center rounded-[8px] px-4"
          >
            Import your library
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center px-5 sm:px-0">
      <%= if @show_instructions do %>
        <section class="flex flex-col items-center py-[89px]">
          <div class="mx-auto flex w-full max-w-[438px] flex-col items-center">
            <h1 class="text-foreground-primary mb-2 text-xl/6 font-semibold max-sm:mb-1.5 sm:text-[28px]/9 lg:mb-4 lg:text-[32px] lg:leading-[32px]">
              Import your library
            </h1>
            <p class="text-foreground-secondary mb-7 text-sm font-normal max-sm:leading-[150%] sm:mb-9 sm:text-base lg:mb-[52px] lg:text-[14px] lg:leading-[20px]">
              Bring in your data from VNDB
            </p>

            <div class="space-y-6 lg:space-y-8">
              <div class="space-y-3 text-center lg:space-y-4">
                <p class="text-foreground-primary text-center text-sm font-normal sm:text-base lg:text-[16px] lg:leading-[24px]">
                  1. Log in to
                  <a
                    href="https://vndb.org"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-foreground-link underline"
                  >
                    VNDB
                  </a>
                  → My Visual Novel List.
                </p>
                <img
                  src="https://images.kaguya.io/ui/import/vndb-menu.webp"
                  alt="VNDB menu showing My Visual Novel List option"
                  width="150"
                  height="123"
                  class="mx-auto object-contain"
                />
              </div>

              <div class="space-y-3 text-center lg:space-y-4">
                <p class="text-foreground-primary text-center text-sm font-normal sm:text-base lg:text-[16px] lg:leading-[24px]">
                  2. Click Export to download your list.
                </p>
                <img
                  src="https://images.kaguya.io/ui/import/vndb-export-bar.webp"
                  alt="VNDB export bar with Export button"
                  width="370"
                  class="h-auto"
                />
              </div>
            </div>

            <button
              type="button"
              phx-click="show-upload"
              class="bg-button-background-brand-default text-button-text-on-brand text-style-body2Medium mt-[64px] inline-flex h-10 w-fit items-center rounded-[8px] px-4"
            >
              I have my export file
            </button>
          </div>
        </section>
      <% else %>
        <section class="flex w-full flex-col items-center pt-[89px] pb-[120px] sm:px-0">
          <h1 class="text-foreground-primary text-style-heading1Regular mb-[80px]">
            Import your library
          </h1>

          <.upload_form
            status={@import_ui_status}
            file_name={@selected_file_name}
            progress={@import_progress}
            import_error={@import_error}
          />
        </section>
      <% end %>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :file_name, :string, default: nil
  attr :progress, :integer, required: true
  attr :import_error, :string, default: nil

  defp upload_form(assigns) do
    ~H"""
    <form
      id="vndb-import-form"
      class="contents"
    >
      <.dropzone
        status={@status}
        file_name={@file_name}
        error={@import_error}
        progress={@progress}
      />
    </form>
    """
  end

  attr :import, :map, required: true
  attr :result, :map, required: true
  attr :user, :map, required: true
  attr :vote_fallback_stats, :map, required: true
  attr :show_all_items, :boolean, required: true
  attr :show_all_missing, :boolean, required: true
  attr :show_all_banned, :boolean, required: true
  attr :open_picker_vn_id, :any, default: nil

  defp summary_view(assigns) do
    assigns =
      assigns
      |> assign(:items, visible_items(assigns.result.imported_items, assigns.show_all_items))
      |> assign(
        :missing_vns,
        visible_missed(assigns.result.missing_vns, assigns.show_all_missing)
      )
      |> assign(:banned_vns, visible_missed(assigns.result.banned_vns, assigns.show_all_banned))
      |> assign(:library_path, library_path(assigns.user))
      |> assign(:summary_initial_count, @summary_initial_count)
      |> assign(:missed_initial_count, @missed_initial_count)

    ~H"""
    <div class="flex flex-col gap-8">
      <div class="flex flex-col gap-5">
        <h1 class="text-foreground-primary text-[24px] leading-[1.3] font-normal sm:text-[32px]">
          Your library is ready, <span class="font-medium">{display_name(@user)}</span>.
        </h1>

        <div class="flex flex-wrap gap-x-8 gap-y-3">
          <.stat_item label="Visual Novels" value={@result.vns_imported} />
          <.stat_item label="Ratings" value={@result.ratings} />
          <.stat_item label="Reviews" value={@result.reviews} />
          <.stat_item label="Labels" value={@result.shelves} />
        </div>
      </div>

      <.link
        navigate={@library_path}
        class="bg-button-background-brand-default text-button-text-on-brand text-style-body2Medium inline-flex h-10 w-full items-center justify-center rounded-[8px] px-4 sm:w-fit"
      >
        See your library
      </.link>
    </div>

    <div :if={@result.imported_items != []} class="flex flex-col gap-5 sm:gap-10">
      <div
        :if={@vote_fallback_stats.eligible_count > 0}
        class="flex w-fit items-center gap-3 text-left"
      >
        <.switch
          checked={@vote_fallback_stats.applied_count > 0}
          label="Fill in missing read dates from votes"
          phx-click="toggle-vote-fallback"
          phx-value-enabled={to_string(@vote_fallback_stats.applied_count == 0)}
        />
        <span class="text-foreground-secondary text-[14px] font-normal">
          Fill in {@vote_fallback_stats.eligible_count} missing read dates from votes
        </span>
      </div>

      <div class="flex flex-col gap-3">
        <div class="text-foreground-tertiary hidden items-center px-1 text-[11px] tracking-wider uppercase sm:grid sm:grid-cols-[44px_1fr_100px_120px_200px] sm:gap-3">
          <div />
          <div>Title</div>
          <div>Rating</div>
          <div>Status</div>
          <div>Read Dates</div>
        </div>

        <div class="flex flex-col">
          <.imported_item_row
            :for={item <- @items}
            item={item}
            vote_fallback_applied?={@vote_fallback_stats.applied_count > 0}
            open_picker?={@open_picker_vn_id == item.id}
          />
        </div>

        <button
          :if={!@show_all_items && length(@result.imported_items) > @summary_initial_count}
          type="button"
          phx-click="show-all-items"
          class="hover:text-foreground-primary text-foreground-secondary text-style-body2Regular self-center transition-colors"
        >
          Show all {length(@result.imported_items)} titles
        </button>
      </div>
    </div>

    <div :if={@result.missing_vns != [] || @result.banned_vns != []} class="mt-4 flex flex-col gap-6">
      <.missed_list
        :if={@result.missing_vns != []}
        title={"No longer on VNDB (#{length(@result.missing_vns)})"}
        description="These titles have been removed from VNDB."
        items={@missing_vns}
        has_more={length(@result.missing_vns) > @missed_initial_count}
        expanded={@show_all_missing}
        event="toggle-missing"
      />
      <.missed_list
        :if={@result.banned_vns != []}
        title={"Not on Kaguya (#{length(@result.banned_vns)})"}
        description="Kaguya doesn't catalog these titles."
        items={@banned_vns}
        has_more={length(@result.banned_vns) > @missed_initial_count}
        expanded={@show_all_banned}
        event="toggle-banned"
      />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :vote_fallback_applied?, :boolean, required: true
  attr :open_picker?, :boolean, default: false

  defp imported_item_row(assigns) do
    assigns =
      assigns
      |> assign(:date_display, date_display(assigns.item, assigns.vote_fallback_applied?))
      |> assign(:no_date_applicable?, assigns.item.status in ["want_to_read", "not_interested"])

    ~H"""
    <div class="group hover:bg-surface-secondary/50 flex items-center gap-2 rounded-md px-1 py-2 transition-colors sm:grid sm:grid-cols-[44px_1fr_100px_120px_200px] sm:gap-3">
      <a href={vn_path(@item)} class="shrink-0">
        <div class="bg-surface-elevated h-[60px] w-10 overflow-hidden rounded-[2px] sm:h-[66px] sm:w-11">
          <img
            :if={cover_url(@item)}
            src={cover_url(@item)}
            alt=""
            class="size-full object-cover object-center"
            loading="lazy"
          />
        </div>
      </a>

      <div class="flex min-w-0 flex-1 flex-col gap-0.5">
        <a
          href={vn_path(@item)}
          title={@item.title}
          class="hover:text-foreground-secondary text-foreground-primary truncate text-[14px] font-normal transition-colors"
        >
          {@item.title}
        </a>
        <div class="text-foreground-tertiary flex items-center gap-2 text-[12px] sm:hidden">
          <span :if={@item.rating} class="text-foreground-secondary flex items-center gap-0.5">
            <span>{format_rating(@item.rating)}</span>
            <Lucide.star class="text-icons-star-muted size-[9px] fill-current" aria-hidden />
          </span>
          <span :if={@item.rating}>·</span>
          <span :if={@item.status}>{status_label(@item.status)}</span>
          <span :if={@item.status}>·</span>
          <.date_cell
            item={@item}
            display={@date_display}
            no_date_applicable?={@no_date_applicable?}
            id_suffix="mobile"
            open?={@open_picker?}
          />
        </div>
      </div>

      <div class="hidden items-center gap-1 text-[13px] sm:flex">
        <%= if @item.rating do %>
          <span class="text-foreground-secondary">{format_rating(@item.rating)}</span>
          <Lucide.star class="text-icons-star-muted size-[10px] fill-current" aria-hidden />
        <% else %>
          <span class="text-foreground-tertiary">—</span>
        <% end %>
      </div>

      <div class="text-foreground-tertiary hidden text-[13px] sm:block">
        {status_label(@item.status)}
      </div>

      <div class="hidden text-[13px] sm:block">
        <.date_cell
          item={@item}
          display={@date_display}
          no_date_applicable?={@no_date_applicable?}
          id_suffix="desktop"
          open?={@open_picker?}
        />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :display, :any, required: true
  attr :no_date_applicable?, :boolean, required: true
  attr :id_suffix, :string, required: true
  attr :open?, :boolean, default: false

  defp date_cell(%{display: :none, no_date_applicable?: true} = assigns) do
    ~H"""
    <span class="text-foreground-tertiary">—</span>
    """
  end

  defp date_cell(assigns) do
    ~H"""
    <div class="relative flex justify-end">
      <button
        type="button"
        phx-click="toggle_import_date_picker"
        phx-value-vn-id={@item.id}
        class="hover:text-foreground-primary text-foreground-secondary inline-flex cursor-pointer items-center gap-1.5 text-[13px] whitespace-nowrap transition-colors"
      >
        <%= case @display do %>
          <% :none -> %>
            <Lucide.calendar_days class="size-3" aria-hidden />
            <span class="text-foreground-tertiary">Date</span>
          <% %{from_vote?: true, label: label} -> %>
            <span>{label}</span>
            <span
              title="From voted date"
              aria-label="From voted date"
              class="text-[8px] text-teal-400"
            >
              ●
            </span>
          <% %{label: label} -> %>
            <span>{label}</span>
        <% end %>
      </button>
      <%!--
        Anchor the popover to the wrapper, not the trigger button. The trigger
        text swaps between "Date" and a full date string, and the previous
        `inline-block` wrapper grew/shrank with the button, dragging the
        right-anchored popover sideways every time. A block wrapper takes
        the cell's full width, so its right edge is stable.
      --%>
      <div
        :if={@open?}
        phx-click-away="close_import_date_picker"
        class="border-border-divider dark:bg-surface-elevated absolute top-full right-0 z-200 mt-2 w-fit rounded-[12px] border bg-white p-0 shadow-[0_8px_30px_rgba(0,0,0,0.4)]"
      >
        <.live_component
          module={DateRangePicker}
          id={"import-date-#{@id_suffix}-#{@item.id}"}
          status={String.upcase(@item.status || "READ")}
          date_started={@item.date_started}
          date_finished={@item.date_finished}
          notify={:import_date_picked}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat_item(assigns) do
    ~H"""
    <div :if={@value && @value > 0} class="flex flex-col">
      <span class="text-foreground-primary text-[28px] leading-tight font-medium tabular-nums">
        {@value}
      </span>
      <span class="text-foreground-tertiary text-xs">{@label}</span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :items, :list, required: true
  attr :has_more, :boolean, required: true
  attr :expanded, :boolean, required: true
  attr :event, :string, required: true

  defp missed_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <h2 class="text-foreground-tertiary text-xs font-medium tracking-[0.08em] uppercase">
        {@title}
      </h2>
      <p class="text-foreground-tertiary/70 text-style-captionRegular">{@description}</p>
      <div class="flex flex-col gap-1.5">
        <a
          :for={vn <- @items}
          href={vn.vndb_url}
          target="_blank"
          rel="noopener noreferrer"
          title={vn.title}
          class="hover:text-foreground-primary text-foreground-secondary text-style-captionRegular block max-w-[500px] truncate transition-colors"
        >
          {vn.title}
        </a>
        <button
          :if={@has_more}
          type="button"
          phx-click={@event}
          class="hover:text-foreground-primary text-foreground-secondary text-style-captionRegular w-fit text-left transition-colors"
        >
          {if @expanded, do: "Show less", else: "Show all"}
        </button>
      </div>
    </div>
    """
  end

  defp load_summary(socket, params) do
    import =
      params
      |> Map.get("import_id")
      |> case do
        nil -> latest_completed_import(socket.assigns.current_user.id)
        id -> import_for_user(id, socket.assigns.current_user.id)
      end

    socket
    |> assign(:import, import)
    |> refresh_vote_fallback()
  end

  defp refresh_vote_fallback(
         %{assigns: %{import: %VndbImport{id: import_id}, current_user: user}} = socket
       ) do
    stats =
      case Shelves.vote_date_fallback_stats(user.id, import_id) do
        {:ok, stats} -> stats
        _ -> %{eligible_count: 0, applied_count: 0}
      end

    assign(socket, :vote_fallback_stats, stats)
  end

  defp refresh_vote_fallback(socket),
    do: assign(socket, :vote_fallback_stats, %{eligible_count: 0, applied_count: 0})

  defp latest_completed_import(user_id) do
    Repo.one(
      from i in VndbImport,
        where: i.user_id == ^user_id and i.status == "completed",
        order_by: [desc: i.updated_at],
        limit: 1
    )
  end

  defp import_for_user(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get_by(VndbImport, id: uuid, user_id: user_id)
      :error -> nil
    end
  end

  defp summary(%VndbImport{result: nil}), do: nil
  defp summary(%VndbImport{result: result}), do: deserialize_result(result)

  defp deserialize_result(result) do
    %{
      vns_imported: int_value(result, "vns_imported"),
      ratings: int_value(result, "ratings"),
      reviews: int_value(result, "reviews"),
      shelves: int_value(result, "shelves"),
      imported_items: Enum.map(result["imported_items"] || [], &deserialize_imported_item/1),
      missing_vns: Enum.map(result["missing_vns"] || [], &deserialize_missed_vn/1),
      banned_vns: Enum.map(result["banned_vns"] || [], &deserialize_missed_vn/1)
    }
  end

  defp deserialize_imported_item(item) do
    %{
      id: item["id"],
      title: item["title"],
      slug: item["slug"],
      images: item["images"] || %{},
      has_ero: item["has_ero"],
      rating: item["rating"],
      status: item["status"],
      release_date: item["release_date"],
      date_added: item["date_added"],
      date_started: item["date_started"],
      date_finished: item["date_finished"],
      vote_date: item["vote_date"]
    }
  end

  defp deserialize_missed_vn(item) do
    %{title: item["title"], vndb_url: item["vndb_url"] || item["vndbUrl"]}
  end

  defp int_value(map, key), do: map[key] || 0

  defp visible_items(items, true), do: items
  defp visible_items(items, false), do: Enum.take(items, @summary_initial_count)

  defp visible_missed(items, true), do: items
  defp visible_missed(items, false), do: Enum.take(items, @missed_initial_count)

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name

  defp display_name(%{username: username}) when is_binary(username) and username != "",
    do: username

  defp display_name(_), do: "reader"

  defp library_path(%{username: username}) when is_binary(username) and username != "",
    do: "/@#{username}/library"

  defp library_path(_), do: "/"

  defp vn_path(%{slug: slug}) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  defp vn_path(_), do: "#"

  defp cover_url(%{images: images}) when is_map(images) do
    images["medium"] || images["large"] || images["small"] || images["xl"]
  end

  defp cover_url(_), do: nil

  defp format_rating(rating) when is_float(rating) do
    whole = floor(rating)

    if rating == whole do
      Integer.to_string(whole)
    else
      "#{whole}½"
    end
  end

  defp format_rating(rating) when is_integer(rating), do: Integer.to_string(rating)
  defp format_rating(_), do: "—"

  defp status_label("read"), do: "Read"
  defp status_label("currently_reading"), do: "Reading"
  defp status_label("want_to_read"), do: "Wishlist"
  defp status_label("on_hold"), do: "Paused"
  defp status_label("did_not_finish"), do: "Did not finish"
  defp status_label("not_interested"), do: "Not interested"
  defp status_label(status) when is_binary(status), do: status
  defp status_label(_), do: "—"

  # Returns either `:none` or `%{label: "15 Mar 2024" | "1 Jan 2024 – 15 Mar 2024",
  # from_vote?: boolean}`. vote_date
  # is only used as a finish-date fallback when the toggle is on AND status is Read.
  defp date_display(item, vote_fallback_applied?) do
    started = format_iso(item.date_started)
    finished = format_iso(item.date_finished)

    vote_fallback =
      if vote_fallback_applied? && item.status == "read",
        do: format_iso(item.vote_date),
        else: nil

    cond do
      started && finished -> %{label: "#{started} – #{finished}", from_vote?: false}
      finished -> %{label: finished, from_vote?: false}
      vote_fallback -> %{label: vote_fallback, from_vote?: true}
      started -> %{label: started, from_vote?: false}
      true -> :none
    end
  end

  defp format_iso(nil), do: nil
  defp format_iso(""), do: nil
  defp format_iso(value), do: SharedTime.format_short_date(value)

  # Picker ids are of the form "import-date-mobile-<vn_id>" or
  # "import-date-desktop-<vn_id>". Pull the vn_id off the tail.
  defp vn_id_from_picker_id("import-date-mobile-" <> vn_id), do: vn_id
  defp vn_id_from_picker_id("import-date-desktop-" <> vn_id), do: vn_id
  defp vn_id_from_picker_id(_), do: nil

  defp apply_import_date_change(socket, vn_id, %{date_started: started, date_finished: finished}) do
    user_id = socket.assigns.current_user.id
    item = find_imported_item(socket.assigns.import, vn_id)
    status_atom = status_atom_for(item)
    next_started = parse_iso_date(started)
    next_finished = parse_iso_date(finished)
    prev_started = parse_iso_date(item && item["date_started"])
    prev_finished = parse_iso_date(item && item["date_finished"])

    attrs = %{
      status: status_atom,
      date_started: next_started,
      date_finished: next_finished
    }

    case Shelves.set_reading_status(user_id, vn_id, attrs) do
      {:ok, _} ->
        # `upsert_statuses/3` ignores nil fields. If the user collapsed a range
        # to a single date here, the orphan column still holds the old value —
        # null it out explicitly. Same pattern as the library cover picker.
        clear_orphan_import_dates(
          user_id,
          vn_id,
          prev_started,
          prev_finished,
          next_started,
          next_finished
        )

        socket
        |> update_import_item(vn_id, started, finished)
        |> refresh_vote_fallback()

      _ ->
        put_flash(socket, :error, "Could not save reading date.")
    end
  end

  defp parse_iso_date(nil), do: nil
  defp parse_iso_date(""), do: nil
  defp parse_iso_date(%Date{} = d), do: d

  defp parse_iso_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_iso_date(_), do: nil

  defp clear_orphan_import_dates(
         user_id,
         vn_id,
         prev_started,
         prev_finished,
         next_started,
         next_finished
       ) do
    fields =
      []
      |> orphan_field(:date_started, prev_started, next_started)
      |> orphan_field(:date_finished, prev_finished, next_finished)

    case fields do
      [] -> :ok
      list -> Shelves.clear_reading_status_fields(user_id, vn_id, list)
    end
  end

  defp orphan_field(list, key, previous, nil) when not is_nil(previous), do: [key | list]
  defp orphan_field(list, _key, _previous, _next), do: list

  defp find_imported_item(%VndbImport{result: %{"imported_items" => items}}, vn_id) do
    Enum.find(items, &(&1["id"] == vn_id))
  end

  defp find_imported_item(_, _), do: nil

  defp status_atom_for(%{"status" => status}) when is_binary(status) do
    String.to_existing_atom(status)
  rescue
    ArgumentError -> :read
  end

  defp status_atom_for(_), do: :read

  defp update_import_item(socket, vn_id, started, finished) do
    case socket.assigns.import do
      %VndbImport{result: %{"imported_items" => items} = result} = import ->
        updated_items =
          Enum.map(items, fn item ->
            if item["id"] == vn_id do
              item
              |> Map.put("date_started", started)
              |> Map.put("date_finished", finished)
            else
              item
            end
          end)

        assign(socket, :import, %{
          import
          | result: Map.put(result, "imported_items", updated_items)
        })

      _ ->
        socket
    end
  end
end
