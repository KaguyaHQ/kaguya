defmodule KaguyaWeb.Components.Profile.Library.Grid do
  @moduledoc """
  Library page grid — VN covers, the per-item action dropdown (labels /
  status / dates submenus), the per-item meta row, and the mobile
  load-more + desktop pagination affordances at the bottom.

  Items are rendered from a LiveView stream (`@streams.library_items`)
  passed in via the `items` attr. The `items_empty?` flag drives the empty
  state since streams aren't enumerable on the server.

  Events emitted: `toggle_library_dropdown`, `close_library_dropdown`,
  `toggle_library_action`, `close_library_action`, `toggle_item_shelf`,
  `start_add_label`, `cancel_add_label`, `update_new_label_name`,
  `create_label_for_vn`, `load_more`, plus `set_item_status` /
  `clear_item_status` via `StatusChangeList`. The date submenu sends a
  `:library_date_picked` info message via the live component.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.ProfileLive.LibraryData
  alias KaguyaWeb.SharedComponents.Cover
  alias KaguyaWeb.SharedComponents.StatusChangeList

  attr :items, :any, required: true, doc: "@streams.library_items"
  attr :items_empty?, :boolean, required: true
  attr :custom_shelves, :list, required: true
  attr :profile, :map, required: true
  attr :shelf, :any, required: true
  attr :fade_read, :boolean, required: true
  attr :show_dates, :boolean, required: true
  attr :open_actions, :map, default: %{}
  attr :new_label_name, :string, default: ""
  attr :open_dropdown, :any, default: nil

  def grid(assigns) do
    show_fade_for_viewer =
      not assigns.profile.viewer.is_mine and assigns.profile.viewer.is_logged_in and
        assigns.fade_read

    is_read_shelf = match?({:status, :read}, assigns.shelf)
    today = Date.utc_today()

    assigns =
      assigns
      |> assign(:show_fade_for_viewer, show_fade_for_viewer)
      |> assign(:is_read_shelf, is_read_shelf)
      |> assign(:today_year, today.year)

    ~H"""
    <div
      :if={@items_empty?}
      class="flex min-h-[180px] items-center justify-center"
    >
      <p class="text-foreground-tertiary text-sm">No visual novels here yet</p>
    </div>

    <Cover.cover_tooltip_provider :if={!@items_empty?} id="library-cover-tooltip">
      <div
        id="library-items"
        phx-update="stream"
        class="grid grid-cols-4 gap-2.5 px-4 pt-3 pb-5 sm:gap-4 sm:pt-5 sm:pb-10 md:grid-cols-5 md:gap-x-3 md:px-0 lg:grid-cols-6 lg:gap-x-4"
      >
        <div
          :for={{dom_id, item} <- @items}
          id={dom_id}
          data-vn-id={item.vn.id}
          class={[
            "group relative flex flex-col",
            @open_dropdown == item.vn.id && "z-150"
          ]}
        >
          <% faded = @show_fade_for_viewer and Map.get(item, :viewer_status) == :read %>
          <div class="relative aspect-1/1.5 overflow-hidden rounded-[4px]">
            <Cover.cover
              vn={item.vn}
              sizes="(max-width: 420px) 110px, 137px"
              link
              show_title_tooltip
              class={"size-full rounded-[4px] object-cover object-center" <> if(faded, do: "opacity-20", else: "")}
            />
            <div
              :if={@profile.viewer.is_mine}
              class="pointer-events-none absolute inset-0 hidden bg-black opacity-0 transition-opacity duration-300 group-hover:opacity-40 lg:block"
            >
            </div>
          </div>

          <.grid_item_actions
            :if={@profile.viewer.is_mine}
            item={item}
            custom_shelves={@custom_shelves}
            profile={@profile}
            open_action={Map.get(@open_actions, item.vn.id)}
            new_label_name={@new_label_name}
            open?={@open_dropdown == item.vn.id}
          />

          <.grid_meta
            item={item}
            profile={@profile}
            show_dates={@show_dates}
            is_read_shelf={@is_read_shelf}
            today_year={@today_year}
          />
        </div>
      </div>
    </Cover.cover_tooltip_provider>
    """
  end

  attr :item, :map, required: true
  attr :custom_shelves, :list, default: []
  attr :profile, :map, required: true
  attr :open_action, :atom, default: nil
  attr :new_label_name, :string, default: ""
  attr :open?, :boolean, default: false

  defp grid_item_actions(assigns) do
    shelf_ids = MapSet.new(Enum.map(assigns.item.shelves || [], & &1.id))

    assigns =
      assigns
      |> assign(:shelf_ids, shelf_ids)
      |> assign(:vn_id, assigns.item.vn.id)

    ~H"""
    <div
      :if={@open?}
      phx-click="close_library_dropdown"
      phx-window-keydown="close_library_dropdown"
      phx-key="Escape"
      class="fixed inset-0 z-100 cursor-default"
      aria-hidden="true"
    />
    <div class={[
      "absolute top-2 right-2",
      @open? && "z-110",
      !@open? && "z-20"
    ]}>
      <button
        type="button"
        phx-click="toggle_library_dropdown"
        phx-value-vn-id={@vn_id}
        aria-label="Library actions"
        aria-expanded={to_string(@open?)}
        class={[
          "flex size-6 cursor-pointer items-center justify-center rounded-full bg-black/40 transition-opacity duration-300 hover:bg-white/12",
          @open? && "opacity-100",
          !@open? && "lg:bg-transparent lg:opacity-0 lg:group-hover:opacity-100"
        ]}
      >
        <Lucide.ellipsis_vertical class="size-5 fill-current text-white" aria-hidden />
      </button>

      <div
        :if={@open?}
        class="bg-surface-menu-item-default border-border-divider absolute top-0 left-full z-120 ml-1 w-[160px] rounded-[12px] border p-0 shadow-[0_25px_20px_rgba(0,0,0,0.15)]"
      >
        <div class="relative">
          <.action_row
            vn_id={@vn_id}
            action="labels"
            icon={:tag}
            label="Edit labels"
            active?={@open_action in [:labels, :add_label]}
          />

          <.labels_submenu
            :if={@open_action in [:labels, :add_label]}
            vn_id={@vn_id}
            custom_shelves={@custom_shelves}
            shelf_ids={@shelf_ids}
            new_label_name={@new_label_name}
            adding?={@open_action == :add_label}
          />

          <.action_row
            vn_id={@vn_id}
            action="status"
            icon={:arrow_right_left}
            label="Change status"
            active?={@open_action == :status}
          />

          <.status_submenu :if={@open_action == :status} item={@item} vn_id={@vn_id} />

          <.action_row
            vn_id={@vn_id}
            action="dates"
            icon={:calendar_days}
            label="Edit dates"
            active?={@open_action == :dates}
          />

          <.dates_submenu :if={@open_action == :dates} item={@item} vn_id={@vn_id} />
        </div>
      </div>
    </div>
    """
  end

  attr :vn_id, :string, required: true
  attr :action, :string, required: true
  attr :icon, :atom, required: true
  attr :label, :string, required: true
  attr :active?, :boolean, default: false

  defp action_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_library_action"
      phx-value-vn-id={@vn_id}
      phx-value-action={@action}
      class={[
        "hover:bg-surface-menu-item-hover flex h-[40px] w-full cursor-pointer items-center gap-2.5 px-3.5 text-sm font-normal",
        @active? && "bg-surface-menu-item-hover text-foreground-primary",
        !@active? && "text-foreground-primary"
      ]}
    >
      <span class="text-foreground-secondary flex size-4 items-center justify-center">
        <.row_icon name={@icon} />
      </span>
      <span>{@label}</span>
    </button>
    """
  end

  attr :name, :atom, required: true

  defp row_icon(%{name: :tag} = assigns), do: ~H[<Lucide.tag class="size-4" aria-hidden />]

  defp row_icon(%{name: :arrow_right_left} = assigns),
    do: ~H[<Lucide.arrow_right_left class="size-4" aria-hidden />]

  defp row_icon(%{name: :calendar_days} = assigns),
    do: ~H[<Lucide.calendar_days class="size-4" aria-hidden />]

  attr :vn_id, :string, required: true
  attr :custom_shelves, :list, required: true
  attr :shelf_ids, :any, required: true
  attr :new_label_name, :string, default: ""
  attr :adding?, :boolean, default: false

  defp labels_submenu(assigns) do
    ~H"""
    <div class="bg-surface-menu-item-default border-border-divider absolute top-0 left-full z-60 ml-1 w-[260px] rounded-[12px] border p-0 shadow-[0_25px_20px_rgba(0,0,0,0.15)]">
      <div class="relative p-3">
        <.search_icon
          class="text-foreground-tertiary pointer-events-none absolute top-1/2 left-5 size-3.5 -translate-y-1/2"
          aria-hidden
        />
        <input
          type="text"
          placeholder="Search label"
          aria-label="Search labels"
          class="focus:ring-border-divider placeholder:text-foreground-tertiary text-foreground-primary w-full rounded-[8px] bg-white/2 py-2 pr-3 pl-7 text-xs focus:ring-1 focus:outline-hidden"
        />
      </div>

      <div class="max-h-[220px] overflow-y-auto">
        <button
          :for={shelf <- @custom_shelves}
          type="button"
          phx-click="toggle_item_shelf"
          phx-value-vn-id={@vn_id}
          phx-value-shelf-id={shelf.id}
          class="text-foreground-primary flex w-full items-center gap-2.5 px-3.5 py-2.5 text-left text-sm hover:bg-white/5"
        >
          <span class={[
            "flex size-4 items-center justify-center rounded-[3px] border",
            MapSet.member?(@shelf_ids, shelf.id) && "border-foreground-secondary",
            !MapSet.member?(@shelf_ids, shelf.id) && "border-foreground-tertiary/40"
          ]}>
            <Lucide.check
              :if={MapSet.member?(@shelf_ids, shelf.id)}
              class="text-foreground-secondary size-3"
              aria-hidden
            />
          </span>
          <span class="truncate">{shelf.name}</span>
        </button>
        <p :if={@custom_shelves == []} class="text-foreground-tertiary p-4 text-center text-sm">
          No labels found.
        </p>
      </div>

      <div class="border-border-divider border-t p-3 py-2.5">
        <form
          :if={@adding?}
          phx-submit="create_label_for_vn"
          phx-value-vn-id={@vn_id}
          class="flex items-center gap-2"
        >
          <input
            type="text"
            name="name"
            value={@new_label_name}
            placeholder="New label name"
            autofocus
            phx-change="update_new_label_name"
            class="focus:ring-border-divider placeholder:text-foreground-tertiary text-foreground-primary flex-1 rounded-[6px] bg-white/4 px-3 py-2 text-sm focus:ring-1 focus:outline-hidden"
          />
          <button
            type="submit"
            class="bg-button-background-brand-default text-button-text-on-brand h-9 rounded-[6px] px-3 text-xs font-normal"
          >
            Save
          </button>
          <button
            type="button"
            phx-click="cancel_add_label"
            class="hover:text-foreground-primary text-foreground-tertiary h-9 rounded-[6px] px-2 text-xs"
            aria-label="Cancel adding label"
          >
            <Lucide.x class="size-4" aria-hidden />
          </button>
        </form>
        <div :if={!@adding?} class="flex items-center justify-between">
          <button
            type="button"
            phx-click="start_add_label"
            phx-value-vn-id={@vn_id}
            class="hover:text-foreground-primary text-foreground-secondary inline-flex items-center gap-1.5 text-sm"
          >
            <Lucide.circle_plus class="size-4" aria-hidden /> Add label
          </button>
          <button
            type="button"
            phx-click="close_library_action"
            class="bg-button-background-brand-default text-button-text-on-brand h-9 rounded-[6px] px-4 text-sm font-normal"
          >
            Save
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :vn_id, :string, required: true

  defp status_submenu(assigns) do
    ~H"""
    <div class="bg-surface-menu-item-default border-border-divider absolute top-0 left-full z-60 ml-1 w-[200px] rounded-[12px] border p-0 shadow-[0_25px_20px_rgba(0,0,0,0.15)]">
      <StatusChangeList.status_change_list vn_id={@vn_id} current={@item.status} />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :vn_id, :string, required: true

  defp dates_submenu(assigns) do
    ~H"""
    <div class="border-border-divider dark:bg-surface-elevated absolute top-0 left-full z-60 ml-1 w-fit rounded-[12px] border bg-white p-0 shadow-[0_8px_30px_rgba(0,0,0,0.4)]">
      <.live_component
        module={KaguyaWeb.SharedComponents.DateRangePicker}
        id={"library-date-#{@vn_id}"}
        status={picker_status(@item)}
        date_started={@item.date_started}
        date_finished={@item.date_finished}
        notify={:library_date_picked}
      />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :profile, :map, required: true
  attr :show_dates, :boolean, required: true
  attr :is_read_shelf, :boolean, required: true
  attr :today_year, :integer, required: true

  defp grid_meta(assigns) do
    is_mine = assigns.profile.viewer.is_mine
    rating = assigns.item.rating
    review_id = assigns.item.review_id
    show_dates_active = assigns.show_dates and is_mine
    has_rating = not is_nil(rating)
    has_review = not is_nil(review_id)
    has_read_date = assigns.is_read_shelf and not is_nil(assigns.item.date_finished)

    has_rating_row =
      (is_mine or has_rating or has_review) and
        (has_rating or has_review or has_read_date or show_dates_active)

    assigns =
      assigns
      |> assign(:is_mine, is_mine)
      |> assign(:rating, rating)
      |> assign(:review_id, review_id)
      |> assign(:show_dates_active, show_dates_active)
      |> assign(:has_rating_row, has_rating_row)

    ~H"""
    <div :if={@has_rating_row} class="flex w-full items-center gap-1.5 pt-1 sm:gap-2">
      <%= if @show_dates_active do %>
        <span
          :if={@item.date_finished}
          class="text-foreground-secondary text-[11px] leading-none lg:hidden"
        >
          {format_date_short(@item.date_finished, @today_year)}
        </span>
        <span
          :if={!@item.date_finished}
          class="text-foreground-tertiary inline-flex items-center gap-1 text-[11px] leading-none lg:hidden"
        >
          <Lucide.calendar class="size-2.5" aria-hidden />
          <span>Date</span>
        </span>
      <% end %>

      <div class={"flex items-center gap-1" <> if(@show_dates_active, do: "max-lg:hidden", else: "")}>
        <KaguyaWeb.VN.Icons.display_ratings
          :if={@rating}
          rating={@rating}
          class="gap-px lg:translate-y-0"
          star_class="size-[11px] !text-[rgb(var(--icons-star-muted))] lg:size-[12px]"
          half_rating_class="!text-[9px] !text-[rgb(var(--icons-star-muted))] lg:!text-[10px]"
        />
        <.link
          :if={@review_id}
          navigate={"/@" <> @profile.username <> "/reviews/" <> @item.vn.slug}
          class="-m-1.5 p-1.5"
          title={if @is_mine, do: "Your Review", else: "Review"}
        >
          <Lucide.file_text class="text-icons-star-muted size-3" aria-hidden />
        </.link>
      </div>

      <span
        :if={@is_read_shelf and @item.date_finished}
        class="text-foreground-tertiary text-style-captionRegular ml-auto hidden whitespace-nowrap lg:block"
      >
        {format_date_short(@item.date_finished, @today_year)}
      </span>
    </div>
    """
  end

  defp picker_status(%{status: status}) when is_atom(status),
    do: status |> Atom.to_string() |> String.upcase()

  defp picker_status(%{status: status}) when is_binary(status), do: String.upcase(status)
  defp picker_status(_), do: "READ"

  defp format_date_short(nil, _today_year), do: ""

  defp format_date_short(%Date{} = date, today_year) do
    if date.year == today_year,
      do: Calendar.strftime(date, "%b"),
      else: Integer.to_string(date.year)
  end

  defp format_date_short(%DateTime{} = dt, today_year),
    do: format_date_short(DateTime.to_date(dt), today_year)

  defp format_date_short(_, _), do: ""

  attr :loaded, :integer, required: true
  attr :total, :integer, required: true

  def mobile_load_more(assigns) do
    ~H"""
    <div :if={@loaded < @total} class="flex justify-center py-8 lg:hidden">
      <button
        type="button"
        phx-click="load_more"
        class="bg-surface-elevated hover:text-foreground-primary text-foreground-secondary h-10 rounded-[8px] px-6 text-sm font-normal hover:bg-white/6"
        data-mobile-load-more
        data-mobile-page-size={LibraryData.mobile_page_size()}
      >
        Load more
      </button>
    </div>
    """
  end

  attr :shelf, :any, required: true
  attr :filters, :map, required: true
  attr :pagination, :map, required: true
  attr :username, :string, required: true

  def pagination(assigns) do
    total_pages = assigns.pagination.total_pages || 0
    current = assigns.pagination.page

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(:current, current)

    ~H"""
    <nav
      :if={@total_pages > 1}
      class="relative flex items-center justify-center gap-2 pb-6 max-lg:hidden"
      aria-label="Pagination"
    >
      <%= for page <- pagination_window(@current, @total_pages) do %>
        <%= cond do %>
          <% page == :ellipsis -> %>
            <span class="text-foreground-tertiary px-2 text-sm">…</span>
          <% page == @current -> %>
            <span class="bg-button-background-neutral-inverse-default text-button-text-on-neutral-inverse inline-flex h-8 min-w-8 items-center justify-center rounded-md px-3 text-sm font-medium">
              {page}
            </span>
          <% true -> %>
            <.link
              patch={LibraryData.build_path(@username, @shelf, Map.put(@filters, :page, page))}
              class="hover:text-foreground-primary text-foreground-secondary inline-flex h-8 min-w-8 items-center justify-center rounded-md px-3 text-sm hover:bg-white/4"
            >
              {page}
            </.link>
        <% end %>
      <% end %>
    </nav>
    """
  end

  defp pagination_window(current, total) do
    cond do
      total <= 7 -> Enum.to_list(1..total)
      current <= 4 -> Enum.to_list(1..5) ++ [:ellipsis, total]
      current >= total - 3 -> [1, :ellipsis] ++ Enum.to_list((total - 4)..total)
      true -> [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end
end
