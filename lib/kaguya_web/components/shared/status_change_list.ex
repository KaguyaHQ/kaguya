defmodule KaguyaWeb.SharedComponents.StatusChangeList do
  @moduledoc """
  Render the rows for a "Change status" menu — five status options plus a
  destructive "Remove VN" footer.

  The wrapper (popover, drawer, submenu) is the caller's responsibility — this
  component is just the row list, so the same markup serves the library cover
  menu, the VN show page, and any future status surface.

  ## Events the parent must handle

    * `set_event` — fired when a row is clicked. The button carries:
        `phx-value-vn-id={vn_id}` and `phx-value-status={value}`,
      where `value` is the status string (e.g. `"CURRENTLY_READING"`) to
      match the existing library/VN-page handlers.
    * `remove_event` — fired when the user clicks "Remove VN". Carries
      `phx-value-vn-id={vn_id}`.

  Pass `phx-target` via the `target` attr if the parent is a LiveComponent.

  ## Options

    * `current` — the user's current `ReadingStatusEnum` atom (or nil). The
      matching row is hidden so the user only sees *transitions* away from
      their current state, matching production behavior.
    * `vn_id` — VN id stamped onto every button.
    * `include` — list of status atoms to keep. Defaults to all six.
    * `show_remove?` — whether to render the "Remove VN" footer. Defaults to
      `true` when `current` is set.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.StatusIcons

  attr :vn_id, :string, required: true
  attr :current, :atom, default: nil

  attr :set_event, :string,
    default: "set_item_status",
    doc: "Event name the row buttons push. Defaults to library handler."

  attr :remove_event, :string,
    default: "clear_item_status",
    doc: "Event name the footer button pushes when the user removes the VN."

  attr :target, :any, default: nil, doc: "Optional phx-target (component @myself / DOM selector)."
  attr :show_remove?, :boolean, default: nil

  attr :include, :list,
    default: nil,
    doc: "Override the visible statuses. Defaults to every status except the current one."

  attr :row_class, :string,
    default: "h-[40px] px-3.5",
    doc: "Per-row sizing. Library uses h-[40px] px-3.5; other surfaces may want larger rows."

  attr :rest, :global

  def status_change_list(assigns) do
    statuses = visible_statuses(assigns)

    show_remove? =
      assigns.show_remove? || (is_nil(assigns.show_remove?) && not is_nil(assigns.current))

    assigns =
      assigns
      |> assign(:statuses, statuses)
      |> assign(:show_remove?, show_remove?)

    ~H"""
    <div role="menu" {@rest}>
      <button
        :for={status <- @statuses}
        type="button"
        role="menuitemradio"
        aria-checked={to_string(@current == status.status)}
        phx-click={@set_event}
        phx-target={@target}
        phx-value-vn-id={@vn_id}
        phx-value-status={status_value(status.status)}
        class={[
          "flex w-full items-center gap-2.5 text-left text-sm font-normal",
          "active:bg-surface-menu-item-pressed hover:bg-surface-menu-item-hover text-foreground-primary",
          "transition-colors duration-100",
          @row_class
        ]}
      >
        <span class="flex shrink-0 items-center justify-center">
          <StatusIcons.status_icon status={status.status} class="size-[18px]" />
        </span>
        <span class="flex-1 truncate">{status.label}</span>
        <span
          :if={@current == status.status}
          class="text-foreground-secondary text-xs"
          aria-hidden="true"
        >
          ✓
        </span>
      </button>

      <div :if={@show_remove?} class="border-border-divider/60 mx-3.5 h-px border-t" />

      <button
        :if={@show_remove?}
        type="button"
        role="menuitem"
        phx-click={@remove_event}
        phx-target={@target}
        phx-value-vn-id={@vn_id}
        class={[
          "text-foreground-primary flex w-full items-center gap-2.5 text-left text-sm font-normal",
          "active:bg-surface-menu-item-pressed hover:bg-surface-menu-item-hover",
          "transition-colors duration-100",
          @row_class
        ]}
      >
        <span class="text-foreground-secondary flex shrink-0 items-center justify-center">
          <Lucide.trash_2 class="size-[18px]" aria-hidden />
        </span>
        <span class="flex-1">Remove VN</span>
      </button>
    </div>
    """
  end

  defp visible_statuses(%{include: list}) when is_list(list) do
    Enum.filter(StatusIcons.statuses(), &(&1.status in list))
  end

  defp visible_statuses(%{current: nil}) do
    # No current status: drop Wishlist by default, matching the production
    # `StatusTab` fallthrough (`alwaysShowWantToReadWhenNoStatus` defaults to
    # false everywhere except the VN show page's primary CTA).
    Enum.reject(StatusIcons.statuses(), &(&1.status == :want_to_read))
  end

  defp visible_statuses(%{current: current}) do
    # Hide the row that matches the current status — the user only ever sees
    # transitions away from it.
    Enum.reject(StatusIcons.statuses(), &(&1.status == current))
  end

  # Map atom → status string used by every existing status handler.
  defp status_value(:read), do: "READ"
  defp status_value(:currently_reading), do: "CURRENTLY_READING"
  defp status_value(:want_to_read), do: "WANT_TO_READ"
  defp status_value(:on_hold), do: "ON_HOLD"
  defp status_value(:did_not_finish), do: "DID_NOT_FINISH"
  defp status_value(:not_interested), do: "NOT_INTERESTED"
  defp status_value(_), do: nil
end
