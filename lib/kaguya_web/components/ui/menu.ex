defmodule KaguyaWeb.UI.Menu do
  @moduledoc """
  Disclosure menu / popover primitive built on the native Popover API.

  Replaces the SaladUI DropdownMenu/Popover floating components. The panel is a
  real `popover` element rendered **inline** in the LiveView template — the
  browser promotes it to the top layer (escaping `overflow-hidden`/z-index)
  **without moving the node out of the DOM**, so morphdom keeps full ownership
  and any server patch to the panel (e.g. `aria-checked`) stays reactive.

  Positioning, `aria-expanded`/`data-state` syncing, and item-dismiss are
  handled by the `AnchoredPopover` hook (`assets/js/hooks/anchored_popover.js`).
  Native light-dismiss (click-outside + Esc) and focus return come for free.

  ## Example

      <.menu id="status-overflow-menu" placement="right" align="start" class="mt-3 mr-1">
        <:trigger class="size-8 ..." aria-label="More reading statuses">
          <.icon name="hero-ellipsis-horizontal" />
        </:trigger>
        <div class="w-[216px] ...">
          <.menu_item event="set_status" value={%{status: "ON_HOLD"}} role="menuitemradio" aria-checked={...}>
            Paused
          </.menu_item>
        </div>
      </.menu>

  The caller owns the panel cosmetics — wrap the items in your own styled
  container inside the default slot.
  """
  use KaguyaWeb, :ui_component

  @doc """
  Disclosure menu. Requires a unique `id`; the trigger and panel derive their
  ids from it (`<id>-trigger`, `<id>-panel`).
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil, doc: "Layout/style classes for the trigger button"
  attr :placement, :string, values: ~w(top right bottom left), default: "bottom"
  attr :align, :string, values: ~w(start center end), default: "start"
  attr :side_offset, :integer, default: 8
  attr :align_offset, :integer, default: 0
  attr :match_width, :boolean, default: false, doc: "Size the panel to the trigger width"

  attr :wrapper_class, :string,
    default: nil,
    doc:
      "Classes for the trigger/panel wrapper. Use with a `:trailing` slot for a sibling action."

  attr :rest, :global

  slot :trigger, required: true do
    attr :class, :string
    attr :"aria-label", :string
  end

  slot :trailing,
    doc: "Optional sibling of the trigger (e.g. a clear-filter link), inside the wrapper."

  slot :inner_block, required: true

  def menu(assigns) do
    trigger = List.first(assigns.trigger)
    assigns = assign(assigns, :trigger_slot, trigger)

    ~H"""
    <div class={[
      @trailing == [] && "contents",
      @trailing != [] && "relative inline-flex",
      @wrapper_class
    ]}>
      <button
        type="button"
        id={@id <> "-trigger"}
        popovertarget={@id <> "-panel"}
        aria-haspopup="true"
        aria-expanded="false"
        aria-label={@trigger_slot[:"aria-label"]}
        class={[@trigger_slot[:class], @class]}
      >
        {render_slot(@trigger)}
      </button>
      {render_slot(@trailing)}
      <div
        id={@id <> "-panel"}
        popover="auto"
        phx-hook="AnchoredPopover"
        data-anchor={@id <> "-trigger"}
        data-placement={@placement}
        data-align={@align}
        data-side-offset={@side_offset}
        data-align-offset={@align_offset}
        data-match-width={@match_width && "true"}
        style="margin:0;position:fixed;inset:auto;"
        {@rest}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A clickable menu item that pushes a LiveView event and dismisses the menu.

  Renders a plain `<button phx-click>` — no SaladUI state machine. The
  `AnchoredPopover` hook closes the panel on click (via `data-menu-dismiss`).
  Pass `role`/`aria-checked` through the global attrs.
  """
  attr :event, :string, required: true
  attr :value, :any, default: nil
  attr :target, :any, default: nil
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def menu_item(assigns) do
    assigns = assign(assigns, :on_click, menu_action_push(assigns))

    ~H"""
    <button type="button" data-menu-dismiss phx-click={@on_click} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  A navigation menu item (`<.link>`) that dismisses the menu on click. Pass
  `navigate`/`patch`/`href` and any other link attrs through the global attrs.
  """
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(navigate patch href method replace download target rel)
  slot :inner_block, required: true

  def menu_link(assigns) do
    ~H"""
    <.link data-menu-dismiss class={@class} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp menu_action_push(%{event: event, value: nil, target: nil}), do: JS.push(event)

  defp menu_action_push(%{event: event, value: value, target: nil}),
    do: JS.push(event, value: value)

  defp menu_action_push(%{event: event, value: nil, target: target}),
    do: JS.push(event, target: target)

  defp menu_action_push(%{event: event, value: value, target: target}),
    do: JS.push(event, value: value, target: target)
end
