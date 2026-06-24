defmodule KaguyaWeb.VN.StatusIcons do
  @moduledoc """
  Single source of truth for the six reading-status glyphs used on the VN
  page (status segments, sidebar, mobile drawer, dropdowns).

  These use Phosphor icon paths — *not* Lucide. The Phosphor paths and the
  Lucide paths look visibly different at the same size (different stroke
  curves, different inner shapes for the rounded variants).

  ## Why a separate module from `lucide_icons`

  - **Family mismatch.** These come from Phosphor, which ships
    hand-tuned `regular` and `fill` variants per icon. CSS
    `fill-current` on a Lucide outline does *not* reproduce a Phosphor
    `fill` glyph (different inner geometry, different proportions).
  - **Custom sparkle.** Phosphor's own `Sparkle` is rejected in favor of
    a BoxIcons-derived custom SVG with matching fill/regular variants.

  ## API

      <.status_icon kind={:read} weight={:fill} class="size-[20px]" />

  - `kind`: one of `:wishlist | :reading | :read | :paused
    | :did_not_finish | :not_interested`
  - `weight`: `:regular` (outline) or `:fill` (solid).
  - `class`: forwarded onto the `<svg>` element. Color is inherited
    via `currentColor`.

  Paths copied from `@phosphor-icons/react@2.1.10` (Phosphor Icons v2)
  for `BookOpen`, `CheckCircle`, `PauseCircle`, `StopCircle`, `XCircle`.
  Sparkle is a BoxIcons-derived variant.
  """

  use KaguyaWeb, :html

  attr :kind, :atom,
    required: true,
    values: [:wishlist, :reading, :read, :paused, :did_not_finish, :not_interested]

  attr :weight, :atom, default: :regular, values: [:regular, :fill]
  attr :class, :any, default: nil

  def status_icon(%{kind: :wishlist} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="m21.45 11.11l-3-1.5l-2.68-1.34l-.03-.03l-1.34-2.68l-1.5-3c-.34-.68-1.45-.68-1.79 0l-1.5 3l-1.34 2.68l-.03.03l-2.68 1.34l-3 1.5c-.34.17-.55.52-.55.89s.21.72.55.89l3 1.5l2.68 1.34l.03.03l1.34 2.68l1.5 3c.17.34.52.55.89.55s.72-.21.89-.55l1.5-3l1.34-2.68l.03-.03l2.68-1.34l3-1.5c.34-.17.55-.52.55-.89s-.21-.72-.55-.89Z" />
      <% else %>
        <path d="m21.45 11.11l-3-1.5l-2.7-1.35l-1.35-2.7l-1.5-3c-.34-.68-1.45-.68-1.79 0l-1.5 3l-1.35 2.7l-2.7 1.35l-3 1.5c-.34.17-.55.52-.55.89s.21.72.55.89l3 1.5l2.7 1.35l1.35 2.7l1.5 3c.17.34.52.55.89.55s.73-.21.89-.55l1.5-3l1.35-2.7l2.7-1.35l3-1.5c.34-.17.55-.52.55-.89s-.21-.72-.55-.89Zm-3.89 1.5l-.84.42l-2.16 1.08l-.3.15l-.15.3L12 18.77l-2.11-4.21l-.15-.3l-.3-.15l-2.16-1.08l-.84-.42L5.23 12l1.21-.61l.84-.42l2.16-1.08l.3-.15l.15-.3L12 5.23l2.11 4.21l.15.3l.3.15l2.16 1.08l.84.42l1.21.61z" />
      <% end %>
    </svg>
    """
  end

  def status_icon(%{kind: :reading} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 256 256"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="M240,56V200a8,8,0,0,1-8,8H160a24,24,0,0,0-24,23.94,7.9,7.9,0,0,1-5.12,7.55A8,8,0,0,1,120,232a24,24,0,0,0-24-24H24a8,8,0,0,1-8-8V56a8,8,0,0,1,8-8H88a32,32,0,0,1,32,32v87.73a8.17,8.17,0,0,0,7.47,8.25,8,8,0,0,0,8.53-8V80a32,32,0,0,1,32-32h64A8,8,0,0,1,240,56Z" />
      <% else %>
        <path d="M232,48H160a40,40,0,0,0-32,16A40,40,0,0,0,96,48H24a8,8,0,0,0-8,8V200a8,8,0,0,0,8,8H96a24,24,0,0,1,24,24,8,8,0,0,0,16,0,24,24,0,0,1,24-24h72a8,8,0,0,0,8-8V56A8,8,0,0,0,232,48ZM96,192H32V64H96a24,24,0,0,1,24,24V200A39.81,39.81,0,0,0,96,192Zm128,0H160a39.81,39.81,0,0,0-24,8V88a24,24,0,0,1,24-24h64Z" />
      <% end %>
    </svg>
    """
  end

  def status_icon(%{kind: :read} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 256 256"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm45.66,85.66-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z" />
      <% else %>
        <path d="M173.66,98.34a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35A8,8,0,0,1,173.66,98.34ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z" />
      <% end %>
    </svg>
    """
  end

  def status_icon(%{kind: :paused} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 256 256"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="M128,24A104,104,0,1,0,232,128,104.13,104.13,0,0,0,128,24ZM112,160a8,8,0,0,1-16,0V96a8,8,0,0,1,16,0Zm48,0a8,8,0,0,1-16,0V96a8,8,0,0,1,16,0Z" />
      <% else %>
        <path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216ZM112,96v64a8,8,0,0,1-16,0V96a8,8,0,0,1,16,0Zm48,0v64a8,8,0,0,1-16,0V96a8,8,0,0,1,16,0Z" />
      <% end %>
    </svg>
    """
  end

  def status_icon(%{kind: :did_not_finish} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 256 256"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm32,132a4,4,0,0,1-4,4H100a4,4,0,0,1-4-4V100a4,4,0,0,1,4-4h56a4,4,0,0,1,4,4Z" />
      <% else %>
        <path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216ZM160,88H96a8,8,0,0,0-8,8v64a8,8,0,0,0,8,8h64a8,8,0,0,0,8-8V96A8,8,0,0,0,160,88Zm-8,64H104V104h48Z" />
      <% end %>
    </svg>
    """
  end

  def status_icon(%{kind: :not_interested} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 256 256"
      fill="currentColor"
      class={@class}
      aria-hidden="true"
    >
      <%= if @weight == :fill do %>
        <path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm37.66,130.34a8,8,0,0,1-11.32,11.32L128,139.31l-26.34,26.35a8,8,0,0,1-11.32-11.32L116.69,128,90.34,101.66a8,8,0,0,1,11.32-11.32L128,116.69l26.34-26.35a8,8,0,0,1,11.32,11.32L139.31,128Z" />
      <% else %>
        <path d="M165.66,101.66,139.31,128l26.35,26.34a8,8,0,0,1-11.32,11.32L128,139.31l-26.34,26.35a8,8,0,0,1-11.32-11.32L116.69,128,90.34,101.66a8,8,0,0,1,11.32-11.32L128,116.69l26.34-26.35a8,8,0,0,1,11.32,11.32ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z" />
      <% end %>
    </svg>
    """
  end
end
