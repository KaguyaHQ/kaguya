defmodule KaguyaWeb.UI.ConfirmDialog do
  @moduledoc """
  A modal confirmation dialog for guard prompts and destructive confirms.

  Uses the shared native dialog for focus, dismissal and scroll locking.

  Open/close is owned by the parent LiveView: render the dialog only when it
  should be open (`:if={@open?}`), and wire `cancel_event` to the assign that
  closes it. The hook fires `cancel_event` on Escape, overlay click, or the
  cancel button, so all three dismissal paths converge on one handler.

  ## Tone drives button hierarchy

  * `:guard` — an interruption the user didn't ask for (e.g. unsaved changes).
    The **safe** action (cancel) is the only filled button and takes initial
    focus; the confirm action is a quiet ghost in error-red. This stops users
    from hitting the destructive action on autopilot.
  * `:destructive` — the user explicitly asked to delete. The confirm action is
    a solid destructive button; cancel stays quiet. Cancel still takes initial
    focus so a stray Enter never deletes.

  ## Example

      <.confirm_dialog
        :if={@discard_open}
        id="new-post-discard"
        title="Discard changes?"
        tone={:guard}
        confirm_label="Discard"
        confirm_event="discard_new_post"
        cancel_label="Keep editing"
        cancel_event="keep_editing_new_post"
      >
        Your changes haven't been saved.
      </.confirm_dialog>
  """
  use KaguyaWeb, :html

  import KaguyaWeb.UI.Button, only: [button: 1]

  attr :id, :string, required: true, doc: "unique id; titles/descriptions derive from it"
  attr :title, :string, required: true

  attr :tone, :atom,
    values: [:guard, :destructive],
    default: :guard,
    doc: "see moduledoc — controls button hierarchy"

  attr :confirm_label, :string, required: true
  attr :confirm_event, :string, required: true, doc: "phx-click for the confirm action"
  attr :cancel_label, :string, default: "Cancel"

  attr :cancel_event, :string,
    required: true,
    doc: "phx-click for cancel; also fired on Escape and overlay click"

  attr :class, :string, default: nil, doc: "merged onto the root overlay (e.g. z-index)"
  attr :rest, :global, doc: "spread onto the confirm button (e.g. phx-hook, data-*)"

  slot :inner_block, required: true, doc: "the description body"

  def confirm_dialog(assigns) do
    assigns = assign(assigns, :destructive?, assigns.tone == :destructive)

    ~H"""
    <KaguyaWeb.UI.Dialog.dialog
      id={@id}
      class={[
        "flex items-center justify-center bg-black/80 p-6",
        @class
      ]}
      viewport
      on_close={Phoenix.LiveView.JS.push(@cancel_event)}
      aria-labelledby={"#{@id}-title"}
      aria-describedby={"#{@id}-desc"}
      role="alertdialog"
    >
      <div class="bg-surface-base w-full max-w-[360px] rounded-[16px] p-6 shadow-[0_16px_80px_rgba(0,0,0,0.6)]">
        <p id={"#{@id}-title"} class="text-foreground-primary text-lg font-medium">
          {@title}
        </p>
        <p id={"#{@id}-desc"} class="text-foreground-secondary mt-2 text-sm font-normal">
          {render_slot(@inner_block)}
        </p>

        <div class="mt-5 flex justify-end gap-2">
          <.button
            variant={if @destructive?, do: "destructive", else: "ghost-destructive"}
            size="small"
            phx-click={@confirm_event}
            class={@destructive? && "order-2"}
            {@rest}
          >
            {@confirm_label}
          </.button>
          <.button
            variant={if @destructive?, do: "neutral", else: "neutral-inverse"}
            size="small"
            data-dialog-close
            data-dialog-initial-focus
            class={@destructive? && "order-1"}
          >
            {@cancel_label}
          </.button>
        </div>
      </div>
    </KaguyaWeb.UI.Dialog.dialog>
    """
  end
end
