defmodule KaguyaWeb.UI.Dialog do
  @moduledoc """
  Native `<dialog>` modal primitive. Replaces the SaladUI Dialog/AlertDialog
  floating components.

  Server-driven open: render the dialog conditionally with `:if` and the
  `Dialog` hook (`assets/js/hooks/dialog.js`) calls `.showModal()` on mount.
  The browser supplies the top layer, focus trap, Esc-to-cancel, `::backdrop`,
  and inert background — no JS focus management needed. Native `close`/`cancel`
  events are forwarded to the server via `on_close` so it can flip its assign.

  The `<dialog>` element **is** the panel — pass panel cosmetics (background,
  border, radius, shadow, width) via `class`. Close buttons opt in with
  `<.dialog_cancel>` (or any element carrying `data-dialog-close`).

  ## Example

      <.dialog
        :if={@confirm_open?}
        id="confirm-dialog"
        on_close={JS.push("close_confirm")}
        class="w-[437px] rounded-[16px] border bg-[rgb(var(--surface-base))] p-0"
      >
        <.dialog_header>
          <.dialog_title>Delete review?</.dialog_title>
          <.dialog_description>This cannot be undone.</.dialog_description>
        </.dialog_header>
        <.dialog_footer>
          <.dialog_cancel>Cancel</.dialog_cancel>
          <.dialog_action phx-click="confirm_delete">Delete</.dialog_action>
        </.dialog_footer>
      </.dialog>
  """
  use KaguyaWeb, :ui_component

  @doc """
  The modal `<dialog>` element. Requires a unique `id`.

  * `:on_close` - JS command pushed when the dialog closes (Esc, backdrop,
    cancel button). Wire this to the server event that flips the open assign.
  * `:dismissable` - allow backdrop-click + Esc dismissal. Defaults to `true`.
  * `:class` - panel cosmetics (the caller owns background/border/radius/shadow).
  """
  attr :id, :string, required: true
  attr :on_close, :any, default: nil
  attr :dismissable, :boolean, default: true
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      phx-hook="Dialog"
      data-on-close={@on_close}
      data-dismissable={to_string(@dismissable)}
      class={
        [
          # Structure only (centering + backdrop). The caller owns the panel
          # cosmetics — width, padding, background, border, radius, shadow — so
          # its classes never conflict with a baked-in default (there is no
          # tw_merge here; a baked `p-6` would beat a caller's `p-0`).
          "m-auto backdrop:bg-black/80",
          @class
        ]
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </dialog>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_header(assigns) do
    ~H"""
    <div class={["flex flex-col space-y-2 text-center sm:text-left", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_title(assigns) do
    ~H"""
    <h2 class={["text-lg leading-none font-semibold tracking-tight", @class]} {@rest}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_description(assigns) do
    ~H"""
    <p class={["text-muted-foreground text-sm", @class]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_footer(assigns) do
    ~H"""
    <div class={["flex flex-col-reverse gap-2 sm:flex-row sm:justify-end", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Quiet neutral close button. Dismisses the dialog (native `close`), which fires
  the `on_close` handler. `class` is layout-only.
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_cancel(assigns) do
    ~H"""
    <button type="button" data-dialog-close class={["btn btn-neutral btn-small", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Primary action button. Defaults to the destructive system button — dialogs
  confirm consequential actions. The action's own `phx-click` runs; the server
  is expected to close the dialog as part of handling it. `class` is layout-only.
  """
  attr :class, :string, default: nil
  attr :variant, :string, values: ~w(brand destructive), default: "destructive"
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_action(assigns) do
    ~H"""
    <button type="button" class={["btn", "btn-#{@variant}", "btn-small", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end
end
