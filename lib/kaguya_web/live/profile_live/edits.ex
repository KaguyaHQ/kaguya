defmodule KaguyaWeb.ProfileLive.Edits do
  @moduledoc """
  `/@:username/edits` — contribution history with activity heatmap.

  Mirrors the Next.js edits tab at
  `../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/users/[username]/(tabs)/edits/page.tsx`
  using `Kaguya.Revisions` directly.
  """

  use KaguyaWeb.ProfileLive, tab: :edits, title_suffix: "Edits"

  alias Kaguya.{Repo, Revisions}
  alias Kaguya.Releases.Release
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.Components.Profile.RevisionActivity
  alias KaguyaWeb.ProfileLive.Data

  @page_size 50
  @range_days 30
  @burst_gap_minutes 10

  @entity_order [:visual_novel, :release, :producer, :character, :series]
  @entity_codes %{
    visual_novel: "v",
    release: "r",
    producer: "p",
    character: "c",
    series: "s"
  }
  @entity_by_code Map.new(@entity_codes, fn {type, code} -> {code, type} end)

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <div class="mx-auto mt-2 w-full max-w-[988px] space-y-6 px-4 pb-20 lg:mt-4 lg:px-0">
        <header class="flex flex-wrap items-baseline gap-x-2">
          <h2 class="text-3xl font-semibold text-[rgb(var(--foreground-primary))] tabular-nums lg:text-4xl">
            {format_count(@total_edits)}
          </h2>
          <p class="text-sm text-[rgb(var(--foreground-secondary))]">
            {if @total_edits == 1, do: "contribution", else: "contributions"} by {@profile.display_name}
          </p>
        </header>

        <.activity_heatmap daily_counts={@daily_counts} entity_types={@entity_types_filter} />

        <section aria-label="Activity log">
          <div class="sticky top-0 z-50 -mx-4 mb-2 border-b border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))]/95 px-4 backdrop-blur supports-backdrop-filter:bg-[rgb(var(--surface-base))]/80 md:top-[65px] lg:mx-0 lg:px-0">
            <.filter_bar
              username={@profile.username}
              selected_types={@selected_entity_types}
              at_default={@filters_at_default}
            />
          </div>

          <%= cond do %>
            <% @revisions == [] -> %>
              <div class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]/40 p-10 text-center">
                <p class="text-sm text-[rgb(var(--foreground-secondary))]">
                  {@profile.display_name} hasn't made any edits matching these filters.
                </p>
              </div>
            <% true -> %>
              <div>
                <%= for {day_key, rows} <- @revision_groups do %>
                  <div class="mb-3">
                    <h3 class="mt-4 mb-1 text-xs font-semibold text-[rgb(var(--foreground-tertiary))]">
                      {day_label(day_key)}
                    </h3>

                    <div>
                      <%= for cluster <- cluster_rows(rows) do %>
                        <%= case cluster do %>
                          <% {:single, revision} -> %>
                            <RevisionActivity.row
                              revision={revision}
                              show_entity_type={@show_entity_type}
                              expanded={MapSet.member?(@expanded_revision_ids, revision.id)}
                              current_user={@current_user}
                            />
                          <% {:group, revisions} -> %>
                            <RevisionActivity.group
                              revisions={revisions}
                              show_entity_type={@show_entity_type}
                              expanded_revision_ids={@expanded_revision_ids}
                              current_user={@current_user}
                            />
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <div :if={@has_more} class="mt-4 flex justify-center">
                  <button
                    type="button"
                    phx-click="load_more_edits"
                    disabled={@loading_more}
                    class="inline-flex h-8 items-center rounded-[8px] px-3 text-xs font-medium text-[rgb(var(--foreground-secondary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] hover:text-[rgb(var(--foreground-primary))] disabled:opacity-60"
                  >
                    {if @loading_more, do: "Loading…", else: "Load more"}
                  </button>
                </div>
              </div>
          <% end %>
        </section>
      </div>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        selected_entity_types = parse_entity_types(params["t"])
        entity_types_filter = derive_entity_types_filter(selected_entity_types)
        {revisions, total_count, has_more} = load_revisions(profile.id, entity_types_filter, 0)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Edits"))
         |> assign(KaguyaWeb.SEO.noindex())
         |> assign(:selected_entity_types, selected_entity_types)
         |> assign(:entity_types_filter, entity_types_filter)
         |> assign(:filters_at_default, filters_at_default?(selected_entity_types))
         |> assign(:revisions, revisions)
         |> assign(:revision_groups, group_by_day(revisions))
         |> assign(:show_entity_type, show_entity_type?(revisions))
         |> assign(:total_count, total_count)
         |> assign(:has_more, has_more)
         |> assign(:loading_more, false)
         |> assign(:expanded_revision_ids, MapSet.new())
         |> assign(:daily_counts, Revisions.edit_timeseries(profile.id))
         |> assign(:total_edits, Revisions.user_revisions_count(profile.id, sources: [:user]))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_edits", _params, %{assigns: %{has_more: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_revision_diff", %{"id" => id}, socket) do
    expanded_revision_ids =
      if MapSet.member?(socket.assigns.expanded_revision_ids, id) do
        MapSet.delete(socket.assigns.expanded_revision_ids, id)
      else
        MapSet.put(socket.assigns.expanded_revision_ids, id)
      end

    {:noreply, assign(socket, :expanded_revision_ids, expanded_revision_ids)}
  end

  def handle_event("load_more_edits", _params, socket) do
    %{profile: profile, entity_types_filter: entity_types_filter, revisions: revisions} =
      socket.assigns

    offset = length(revisions)

    socket = assign(socket, :loading_more, true)

    {new_revisions, total_count, has_more} =
      load_revisions(profile.id, entity_types_filter, offset)

    all_revisions = revisions ++ new_revisions

    {:noreply,
     socket
     |> assign(:revisions, all_revisions)
     |> assign(:revision_groups, group_by_day(all_revisions))
     |> assign(:show_entity_type, show_entity_type?(all_revisions))
     |> assign(:total_count, total_count)
     |> assign(:has_more, has_more)
     |> assign(:loading_more, false)}
  end

  def handle_event(event, params, socket) when event in ["toggle_follow", "open_mod_panel"] do
    super(event, params, socket)
  end

  attr :username, :string, required: true
  attr :selected_types, :list, required: true
  attr :at_default, :boolean, required: true

  defp filter_bar(assigns) do
    assigns = assign(assigns, :entity_order, @entity_order)

    ~H"""
    <div class="flex flex-wrap items-center gap-x-1 gap-y-2 py-2">
      <div class="flex flex-wrap items-center gap-1">
        <.entity_type_pill
          :for={type <- @entity_order}
          username={@username}
          type={type}
          selected_types={@selected_types}
        />
      </div>

      <div class="ml-auto flex items-center gap-1">
        <.link
          :if={!@at_default}
          patch={"/@" <> @username <> "/edits"}
          class="h-8 rounded-[8px] px-2 text-xs text-[rgb(var(--foreground-tertiary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] hover:text-[rgb(var(--foreground-primary))]"
        >
          Reset
        </.link>
      </div>
    </div>
    """
  end

  attr :username, :string, required: true
  attr :type, :atom, required: true
  attr :selected_types, :list, required: true

  defp entity_type_pill(assigns) do
    assigns =
      assigns
      |> assign(:active, assigns.type in assigns.selected_types)
      |> assign(:patch, filter_patch(assigns.username, assigns.selected_types, assigns.type))

    ~H"""
    <.link
      patch={@patch}
      aria-pressed={to_string(@active)}
      class={entity_pill_class(@active)}
    >
      <.entity_icon type={@type} class="size-3" />
      {entity_label_plural(@type)}
    </.link>
    """
  end

  attr :daily_counts, :list, required: true
  attr :entity_types, :any, required: true

  defp activity_heatmap(assigns) do
    assigns =
      assign(assigns, :heatmap, heatmap(assigns.daily_counts, assigns.entity_types))

    ~H"""
    <section
      aria-label="30-day edit activity"
      class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]/40 p-4"
    >
      <header class="mb-3 flex flex-wrap items-baseline gap-x-2">
        <h3 class="text-lg font-semibold text-[rgb(var(--foreground-primary))] tabular-nums">
          {format_count(@heatmap.total)}
        </h3>
        <p class="text-sm text-[rgb(var(--foreground-secondary))]">
          {if @heatmap.total == 1, do: "edit", else: "edits"} · last 30 days
        </p>
        <p class="ml-auto text-xs text-[rgb(var(--foreground-tertiary))]">{@heatmap.range_label}</p>
      </header>

      <div class="flex gap-1.5">
        <div class="flex flex-col gap-[3px] pr-1 text-[10px] text-[rgb(var(--foreground-quaternary))]">
          <div
            :for={label <- ["", "Mon", "", "Wed", "", "Fri", ""]}
            class="flex h-[14px] items-center leading-[14px]"
            aria-hidden="true"
          >
            {label}
          </div>
        </div>

        <div class="flex gap-[3px]" role="grid" aria-label="Daily edit count">
          <div :for={week <- @heatmap.weeks} class="flex flex-col gap-[3px]" role="row">
            <div
              :for={cell <- week}
              role="gridcell"
              title={cell.tooltip}
              aria-label={cell.tooltip}
              class={heatmap_cell_class(cell)}
            />
          </div>
        </div>
      </div>

      <div class="mt-3 flex items-center justify-end gap-1.5 text-[10px] text-[rgb(var(--foreground-quaternary))]">
        <span>Less</span>
        <div class={heatmap_legend_class(0)} aria-hidden="true" />
        <div class={heatmap_legend_class(1)} aria-hidden="true" />
        <div class={heatmap_legend_class(2)} aria-hidden="true" />
        <div class={heatmap_legend_class(3)} aria-hidden="true" />
        <div class={heatmap_legend_class(4)} aria-hidden="true" />
        <span>More</span>
      </div>
    </section>
    """
  end

  attr :type, :atom, required: true
  attr :class, :string, default: "size-4"

  # Icon paths mirror lucide-react v0.577 to match the pills the Next.js
  # `ChangesFilterBar` renders: BookOpenText, Disc3, Building2, Users, Rows3.
  defp entity_icon(%{type: :visual_novel} = assigns) do
    ~H"""
    <Lucide.book_open_text class={@class} aria-hidden />
    """
  end

  defp entity_icon(%{type: :release} = assigns) do
    ~H"""
    <Lucide.disc_3 class={@class} aria-hidden />
    """
  end

  defp entity_icon(%{type: :producer} = assigns) do
    ~H"""
    <Lucide.building class={@class} aria-hidden />
    """
  end

  defp entity_icon(%{type: :character} = assigns) do
    ~H"""
    <Lucide.users class={@class} aria-hidden />
    """
  end

  defp entity_icon(%{type: :series} = assigns) do
    ~H"""
    <Lucide.rows_3 class={@class} aria-hidden />
    """
  end

  defp load_revisions(user_id, entity_types_filter, offset) do
    opts =
      [
        limit: @page_size,
        offset: offset
      ]
      |> maybe_put(:entity_types, entity_types_filter)

    revisions =
      user_id
      |> Revisions.user_revisions(opts)
      |> hydrate_revisions()

    total_count =
      user_id
      |> Revisions.user_revisions_count(Keyword.delete(opts, :limit) |> Keyword.delete(:offset))

    {revisions, total_count, offset + length(revisions) < total_count}
  end

  defp hydrate_revisions([]), do: []

  defp hydrate_revisions(rows) do
    pairs = Enum.map(rows, &{&1.entity_type, &1.entity_id})
    diff_map = Revisions.batch_load_diffs(nil, Enum.map(rows, & &1.id))

    entity_map =
      pairs
      |> Revisions.batch_load_entities()
      |> preload_release_visual_novels()

    Enum.map(rows, fn row ->
      entity = Map.get(entity_map, {row.entity_type, row.entity_id})

      row
      |> Map.put(:entity, entity)
      |> Map.put(:entity_href, entity_href(row.entity_type, entity))
      |> Map.put(:revision_href, revision_href(row.entity_type, entity, row.id))
      |> Map.put(:diff, Map.get(diff_map, row.id))
    end)
  end

  defp preload_release_visual_novels(entity_map) do
    releases =
      entity_map
      |> Map.values()
      |> Enum.filter(&match?(%Release{}, &1))
      |> Repo.preload(:visual_novel)
      |> Map.new(&{&1.id, &1})

    Map.new(entity_map, fn
      {{:release, id}, %Release{}} -> {{:release, id}, Map.fetch!(releases, id)}
      entry -> entry
    end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_entity_types(nil), do: @entity_order
  defp parse_entity_types(""), do: @entity_order

  defp parse_entity_types(raw) when is_binary(raw) do
    raw
    |> String.graphemes()
    |> Enum.map(&Map.get(@entity_by_code, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> @entity_order
      types -> Enum.filter(@entity_order, &(&1 in types))
    end
  end

  defp derive_entity_types_filter(selected) do
    if filters_at_default?(selected), do: nil, else: selected
  end

  defp filters_at_default?(selected) do
    MapSet.new(selected) == MapSet.new(@entity_order)
  end

  defp filter_patch(username, selected_types, type) do
    next =
      if type in selected_types do
        if length(selected_types) == 1,
          do: selected_types,
          else: List.delete(selected_types, type)
      else
        Enum.filter(@entity_order, &(&1 in [type | selected_types]))
      end

    codes =
      next
      |> Enum.map(&Map.fetch!(@entity_codes, &1))
      |> Enum.sort()
      |> Enum.join()

    if filters_at_default?(next) do
      "/@#{username}/edits"
    else
      "/@#{username}/edits?t=#{codes}"
    end
  end

  defp group_by_day(rows) do
    rows
    |> Enum.reduce([], fn row, groups ->
      day_key = day_key(row.inserted_at)

      case groups do
        [{^day_key, day_rows} | rest] -> [{day_key, day_rows ++ [row]} | rest]
        _ -> [{day_key, [row]} | groups]
      end
    end)
    |> Enum.reverse()
  end

  defp cluster_rows(rows) do
    rows
    |> do_cluster([])
    |> Enum.reverse()
  end

  defp do_cluster([], acc), do: acc

  defp do_cluster([head | rest], acc) do
    {same, remaining} = Enum.split_while(rest, &same_burst?(head, &1))
    revisions = [head | same]

    cluster =
      if length(revisions) > 1 do
        {:group, revisions}
      else
        {:single, head}
      end

    do_cluster(remaining, [cluster | acc])
  end

  defp same_burst?(head, next) do
    head.entity_type == next.entity_type and
      head.entity_id == next.entity_id and
      head.action == next.action and
      not is_nil(head.inserted_at) and
      not is_nil(next.inserted_at) and
      DateTime.diff(head.inserted_at, next.inserted_at, :minute) <= @burst_gap_minutes
  end

  defp show_entity_type?(rows) do
    rows
    |> Enum.map(& &1.entity_type)
    |> Enum.uniq()
    |> length()
    |> Kernel.>(1)
  end

  defp heatmap(daily_counts, entity_types) do
    today = Date.utc_today()
    start_date = Date.add(today, -(@range_days - 1))
    grid_start = Date.add(start_date, -rem(Date.day_of_week(start_date), 7))
    allowed = entity_types && MapSet.new(entity_types)

    counts_by_day =
      Enum.reduce(daily_counts || [], %{}, fn count, acc ->
        if allowed && count.entity_type not in allowed do
          acc
        else
          Map.update(acc, count.day, count.count || 0, &(&1 + (count.count || 0)))
        end
      end)

    days =
      grid_start
      |> Date.range(today)
      |> Enum.map(fn day ->
        in_range = Date.compare(day, start_date) != :lt
        value = if in_range, do: Map.get(counts_by_day, day, 0)
        %{day: day, value: value}
      end)
      |> pad_heatmap_days()

    max_value =
      days
      |> Enum.map(&(&1.value || 0))
      |> Enum.max(fn -> 0 end)

    weeks =
      days
      |> Enum.map(&Map.put(&1, :bucket, bucketize(&1.value || 0, max_value)))
      |> Enum.map(&Map.put(&1, :tooltip, heatmap_tooltip(&1)))
      |> Enum.chunk_every(7)

    %{
      weeks: weeks,
      total: Enum.reduce(days, 0, &(&2 + (&1.value || 0))),
      range_label: range_label(start_date, today)
    }
  end

  defp pad_heatmap_days(days) do
    remainder = rem(length(days), 7)

    if remainder == 0 do
      days
    else
      days ++ List.duplicate(%{day: nil, value: nil}, 7 - remainder)
    end
  end

  defp bucketize(value, _max) when value <= 0, do: 0
  defp bucketize(value, max) when max <= 4, do: min(value, 4)

  defp bucketize(value, max) do
    quartile = max / 4

    cond do
      value <= quartile -> 1
      value <= quartile * 2 -> 2
      value <= quartile * 3 -> 3
      true -> 4
    end
  end

  defp heatmap_tooltip(%{day: nil}), do: nil

  defp heatmap_tooltip(%{day: day, value: value}) do
    "#{month_day_year(day)} · #{value} #{if value == 1, do: "edit", else: "edits"}"
  end

  defp heatmap_cell_class(%{value: nil}), do: "h-[14px] w-[14px] rounded-[3px] opacity-0"

  defp heatmap_cell_class(%{bucket: 0}) do
    "h-[14px] w-[14px] rounded-[3px] bg-[rgb(var(--surface-elevated))]/60 ring-1 ring-inset ring-[rgb(var(--border-divider))]/30"
  end

  defp heatmap_cell_class(%{bucket: 1}),
    do: "h-[14px] w-[14px] rounded-[3px] bg-[oklch(70%_0.18_290_/_0.20)]"

  defp heatmap_cell_class(%{bucket: 2}),
    do: "h-[14px] w-[14px] rounded-[3px] bg-[oklch(70%_0.18_290_/_0.40)]"

  defp heatmap_cell_class(%{bucket: 3}),
    do: "h-[14px] w-[14px] rounded-[3px] bg-[oklch(70%_0.18_290_/_0.65)]"

  defp heatmap_cell_class(%{bucket: 4}),
    do: "h-[14px] w-[14px] rounded-[3px] bg-[oklch(70%_0.18_290_/_0.95)]"

  defp heatmap_legend_class(0) do
    "h-[10px] w-[10px] rounded-[2px] bg-[rgb(var(--surface-elevated))]/60 ring-1 ring-inset ring-[rgb(var(--border-divider))]/30"
  end

  defp heatmap_legend_class(1),
    do: "h-[10px] w-[10px] rounded-[2px] bg-[oklch(70%_0.18_290_/_0.20)]"

  defp heatmap_legend_class(2),
    do: "h-[10px] w-[10px] rounded-[2px] bg-[oklch(70%_0.18_290_/_0.40)]"

  defp heatmap_legend_class(3),
    do: "h-[10px] w-[10px] rounded-[2px] bg-[oklch(70%_0.18_290_/_0.65)]"

  defp heatmap_legend_class(4),
    do: "h-[10px] w-[10px] rounded-[2px] bg-[oklch(70%_0.18_290_/_0.95)]"

  defp entity_pill_class(true) do
    "inline-flex items-center gap-1.5 rounded-full bg-[rgb(var(--surface-menu-item-hover))] px-3 py-1 text-xs font-medium text-[rgb(var(--foreground-primary))] transition-colors"
  end

  defp entity_pill_class(false) do
    "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium text-[rgb(var(--foreground-tertiary))] transition-colors hover:text-[rgb(var(--foreground-secondary))]"
  end

  defp entity_href(:visual_novel, %{slug: slug}) when is_binary(slug), do: "/vn/#{slug}"
  defp entity_href(:character, %{slug: slug}) when is_binary(slug), do: "/character/#{slug}"
  defp entity_href(:producer, %{slug: slug}) when is_binary(slug), do: "/developer/#{slug}"
  defp entity_href(:series, %{slug: slug}) when is_binary(slug), do: "/series/#{slug}"

  defp entity_href(:release, %Release{visual_novel: %{slug: slug}}) when is_binary(slug),
    do: "/vn/#{slug}/releases"

  defp entity_href(_, _), do: nil

  defp revision_href(_type, _entity, nil), do: nil

  defp revision_href(:visual_novel, %{slug: slug}, id) when is_binary(slug),
    do: "/vn/#{slug}/history/#{id}"

  defp revision_href(:character, %{slug: slug}, id) when is_binary(slug),
    do: "/character/#{slug}/history/#{id}"

  defp revision_href(:producer, %{slug: slug}, id) when is_binary(slug),
    do: "/developer/#{slug}/history/#{id}"

  defp revision_href(:series, %{slug: slug}, id) when is_binary(slug),
    do: "/series/#{slug}/history/#{id}"

  defp revision_href(:release, %Release{id: release_id, visual_novel: %{slug: slug}}, id)
       when is_binary(slug),
       do: "/vn/#{slug}/release/#{release_id}/history/#{id}"

  defp revision_href(_, _, _), do: nil

  defp entity_label_plural(:visual_novel), do: "Visual novels"
  defp entity_label_plural(:release), do: "Releases"
  defp entity_label_plural(:producer), do: "Producers"
  defp entity_label_plural(:character), do: "Characters"
  defp entity_label_plural(:series), do: "Series"

  defp day_key(nil), do: "unknown"
  defp day_key(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp day_label("unknown"), do: "Undated"

  defp day_label(day_key) do
    {:ok, day} = Date.from_iso8601(day_key)
    today = Date.utc_today()

    cond do
      day == today -> "Today"
      day == Date.add(today, -1) -> "Yesterday"
      day.year == today.year -> month_day(day)
      true -> month_day_year(day)
    end
  end

  defp range_label(start_date, today) do
    if start_date.year == today.year do
      "#{month_day(start_date)} – #{month_day(today)}"
    else
      "#{month_day_year(start_date)} – #{month_day_year(today)}"
    end
  end

  defp month_day(%Date{} = date), do: "#{month_name(date.month, :short)} #{date.day}"
  defp month_day_year(%Date{} = date), do: "#{month_day(date)}, #{date.year}"

  defp month_name(1, :short), do: "Jan"
  defp month_name(2, :short), do: "Feb"
  defp month_name(3, :short), do: "Mar"
  defp month_name(4, :short), do: "Apr"
  defp month_name(5, :short), do: "May"
  defp month_name(6, :short), do: "Jun"
  defp month_name(7, :short), do: "Jul"
  defp month_name(8, :short), do: "Aug"
  defp month_name(9, :short), do: "Sep"
  defp month_name(10, :short), do: "Oct"
  defp month_name(11, :short), do: "Nov"
  defp month_name(12, :short), do: "Dec"

  defp format_count(value) when is_integer(value),
    do: value |> Integer.to_string() |> add_commas()

  defp format_count(_), do: "0"

  defp add_commas(value) when byte_size(value) <= 3, do: value

  defp add_commas(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
