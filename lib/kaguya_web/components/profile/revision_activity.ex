defmodule KaguyaWeb.Components.Profile.RevisionActivity do
  @moduledoc """
  Profile contribution activity rows and burst groups.

  Delegates field-level rendering to
  `KaguyaWeb.Components.Profile.RevisionDiff`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.RevisionDiff, only: [inline_diff: 1]

  attr :revision, :map, required: true
  attr :show_entity_type, :boolean, required: true
  attr :compact, :boolean, default: false
  attr :expanded, :boolean, default: false
  attr :current_user, :map, default: nil

  def row(assigns) do
    assigns =
      assigns
      |> assign(:has_diff, has_diff?(assigns.revision))
      |> assign(:action_label, action_label(assigns.revision.action))
      |> assign(:is_edit, assigns.revision.action in [nil, :edit])

    ~H"""
    <article class="border-border-divider/60 group border-b last:border-b-0">
      <div
        phx-click={if @has_diff, do: "toggle_revision_diff"}
        phx-value-id={if @has_diff, do: @revision.id}
        role={if @has_diff, do: "button"}
        tabindex={if @has_diff, do: "0"}
        aria-expanded={if @has_diff, do: to_string(@expanded)}
        class={[
          "flex flex-wrap items-center gap-x-3 gap-y-1 p-2 text-sm transition-colors",
          "focus-visible:bg-surface-menu-item-hover focus-visible:outline-none",
          @has_diff && "hover:bg-surface-menu-item-hover cursor-pointer"
        ]}
      >
        <span
          aria-hidden="true"
          class={[
            "text-foreground-tertiary grid size-5 shrink-0 place-items-center transition",
            !@has_diff && "opacity-30"
          ]}
        >
          <.chevron_icon direction={if @expanded, do: :down, else: :right} />
        </span>

        <.action_icon
          :if={!@compact}
          action={@revision.action}
          class="text-foreground-secondary size-4 shrink-0"
        />

        <div class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <span
            :if={!@compact and !@is_edit}
            class="text-foreground-tertiary text-xs font-medium tracking-wide uppercase"
          >
            {@action_label}
          </span>

          <.link
            :if={!@compact and @revision.entity_href}
            navigate={@revision.entity_href}
            class="text-foreground-primary truncate font-semibold hover:text-[rgb(var(--text-link-hover))] hover:underline"
          >
            {entity_name(@revision)}
          </.link>
          <span
            :if={!@compact and is_nil(@revision.entity_href)}
            class="text-foreground-primary truncate font-semibold"
          >
            {entity_name(@revision)}
          </span>

          <span :if={@revision.summary} class="text-foreground-secondary truncate text-sm">
            <span :if={!@compact} class="text-foreground-quaternary mr-1.5" aria-hidden="true">
              —
            </span>
            {@revision.summary}
          </span>

          <span
            :if={@compact and is_nil(@revision.summary)}
            class="text-foreground-secondary text-sm"
          >
            {@action_label}
          </span>

          <span
            :if={!@compact and @show_entity_type}
            class="text-foreground-tertiary text-xs"
          >
            {entity_label(@revision.entity_type)}
          </span>
        </div>

        <div class="text-foreground-tertiary flex shrink-0 items-center gap-2 text-xs">
          <span
            :if={@revision.source && @revision.source != :user}
            class="bg-surface-elevated inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] tracking-wide uppercase"
            title="System-authored revision"
          >
            <.bot_icon class="size-3" />
            {@revision.source}
          </span>

          <time
            :if={@revision.inserted_at}
            datetime={DateTime.to_iso8601(@revision.inserted_at)}
            title={full_timestamp(@revision.inserted_at)}
            class="tabular-nums"
          >
            {time_label(@revision.inserted_at)}
          </time>

          <.link
            :if={@revision.revision_href}
            navigate={@revision.revision_href}
            class="hover:text-foreground-primary transition-colors"
            title="Open full diff"
          >
            r{@revision.revision_number}
          </.link>
          <span :if={is_nil(@revision.revision_href)}>r{@revision.revision_number}</span>
        </div>
      </div>

      <div :if={@expanded and @has_diff} class="border-border-divider/60 border-t p-3">
        <.inline_diff
          diff={@revision.diff.diff}
          current={@revision.diff.current}
          previous={@revision.diff.previous}
          entity_type={@revision.entity_type}
          current_user={@current_user}
        />
      </div>
    </article>
    """
  end

  attr :revisions, :list, required: true
  attr :show_entity_type, :boolean, required: true
  attr :expanded_revision_ids, :any, default: MapSet.new()
  attr :current_user, :map, default: nil

  def group(assigns) do
    assigns =
      assigns
      |> assign(:latest, hd(assigns.revisions))
      |> assign(:earliest, List.last(assigns.revisions))

    ~H"""
    <details class="border-border-divider/60 group border-b last:border-b-0">
      <summary class="focus-visible:bg-surface-menu-item-hover hover:bg-surface-menu-item-hover flex w-full cursor-pointer list-none flex-wrap items-center gap-x-3 gap-y-1 p-2 text-left text-sm transition focus-visible:outline-none [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden="true"
          class="text-foreground-tertiary grid size-5 shrink-0 place-items-center"
        >
          <.chevron_icon direction={:right} class="transition group-open:rotate-90" />
        </span>

        <.action_icon action={@latest.action} class="text-foreground-secondary size-4 shrink-0" />

        <div class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <.link
            :if={@latest.entity_href}
            navigate={@latest.entity_href}
            class="text-foreground-primary truncate font-semibold hover:text-[rgb(var(--text-link-hover))] hover:underline"
          >
            {entity_name(@latest)}
          </.link>
          <span
            :if={is_nil(@latest.entity_href)}
            class="text-foreground-primary truncate font-semibold"
          >
            {entity_name(@latest)}
          </span>

          <span class="text-foreground-secondary text-sm">
            <span class="text-foreground-quaternary mr-1.5" aria-hidden="true">
              —
            </span>
            {length(@revisions)} {group_action_label(@latest.action)}
            <span class="text-foreground-quaternary mx-1.5" aria-hidden="true">·</span>
            <span class="tabular-nums">{time_range(@earliest.inserted_at, @latest.inserted_at)}</span>
          </span>

          <span :if={@show_entity_type} class="text-foreground-tertiary text-xs">
            {entity_label(@latest.entity_type)}
          </span>
        </div>
      </summary>

      <div class="border-border-divider/40 ml-[14px] border-l pl-[14px]">
        <.row
          :for={revision <- @revisions}
          revision={revision}
          show_entity_type={@show_entity_type}
          compact
          expanded={MapSet.member?(@expanded_revision_ids, revision.id)}
          current_user={@current_user}
        />
      </div>
    </details>
    """
  end

  attr :action, :atom, default: :edit
  attr :class, :string, default: "size-4"

  defp action_icon(%{action: :create} = assigns) do
    ~H"""
    <Lucide.sparkles class={@class} aria-label="Created" />
    """
  end

  defp action_icon(%{action: :revert} = assigns) do
    ~H"""
    <Lucide.rotate_ccw class={@class} aria-label="Reverted" />
    """
  end

  defp action_icon(%{action: :hide} = assigns) do
    ~H"""
    <Lucide.eye_off class={@class} aria-label="Hid" />
    """
  end

  defp action_icon(%{action: :unhide} = assigns) do
    ~H"""
    <Lucide.eye class={@class} aria-label="Unhid" />
    """
  end

  defp action_icon(%{action: :lock} = assigns) do
    ~H"""
    <Lucide.lock class={@class} aria-label="Locked" />
    """
  end

  defp action_icon(%{action: :unlock} = assigns) do
    ~H"""
    <Lucide.lock_open class={@class} aria-label="Unlocked" />
    """
  end

  defp action_icon(assigns) do
    ~H"""
    <Lucide.pencil class={@class} aria-label="Edited" />
    """
  end

  attr :direction, :atom, default: :right
  attr :class, :string, default: "size-3.5"

  defp chevron_icon(%{direction: :down} = assigns) do
    ~H"""
    <Lucide.chevron_down class={@class} aria-hidden />
    """
  end

  defp chevron_icon(assigns) do
    ~H"""
    <Lucide.chevron_right class={@class} aria-hidden />
    """
  end

  attr :class, :string, default: "size-3"

  defp bot_icon(assigns) do
    ~H"""
    <Lucide.bot class={@class} aria-hidden />
    """
  end

  defp has_diff?(%{diff: %{diff: diff}}) when is_list(diff), do: diff != []
  defp has_diff?(_), do: false

  defp entity_name(%{entity: %{title: title}}) when is_binary(title) and title != "", do: title
  defp entity_name(%{entity: %{name: name}}) when is_binary(name) and name != "", do: name
  defp entity_name(_), do: "Unknown entity"

  defp entity_label(:visual_novel), do: "Visual novel"
  defp entity_label(:release), do: "Release"
  defp entity_label(:producer), do: "Producer"
  defp entity_label(:character), do: "Character"
  defp entity_label(:series), do: "Series"
  defp entity_label(_), do: "Entry"

  defp action_label(:create), do: "Created"
  defp action_label(:revert), do: "Reverted"
  defp action_label(:hide), do: "Hid"
  defp action_label(:unhide), do: "Unhid"
  defp action_label(:lock), do: "Locked"
  defp action_label(:unlock), do: "Unlocked"
  defp action_label(_), do: "Edited"

  defp group_action_label(:edit), do: "edits"
  defp group_action_label(action), do: String.downcase(action_label(action))

  defp time_label(nil), do: ""

  defp time_label(%DateTime{} = dt) do
    [pad2(dt.hour), pad2(dt.minute)] |> Enum.join(":")
  end

  defp time_range(nil, nil), do: ""
  defp time_range(nil, latest), do: time_label(latest)
  defp time_range(earliest, nil), do: time_label(earliest)

  defp time_range(earliest, latest) do
    earliest_time = time_label(earliest)
    latest_time = time_label(latest)

    if earliest_time == latest_time, do: earliest_time, else: "#{earliest_time}-#{latest_time}"
  end

  defp full_timestamp(%DateTime{} = dt),
    do: "#{month_day_year(DateTime.to_date(dt))} #{time_label(dt)}"

  defp month_day(%Date{} = date), do: "#{month_name(date.month)} #{date.day}"
  defp month_day_year(%Date{} = date), do: "#{month_day(date)}, #{date.year}"

  defp month_name(1), do: "Jan"
  defp month_name(2), do: "Feb"
  defp month_name(3), do: "Mar"
  defp month_name(4), do: "Apr"
  defp month_name(5), do: "May"
  defp month_name(6), do: "Jun"
  defp month_name(7), do: "Jul"
  defp month_name(8), do: "Aug"
  defp month_name(9), do: "Sep"
  defp month_name(10), do: "Oct"
  defp month_name(11), do: "Nov"
  defp month_name(12), do: "Dec"

  defp pad2(value) when value < 10, do: "0#{value}"
  defp pad2(value), do: to_string(value)
end
