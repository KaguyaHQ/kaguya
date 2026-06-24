defmodule KaguyaWeb.SharedComponents.RemovalReasonDialog do
  @moduledoc """
  Moderator removal dialog: reason category + user-facing message + private
  mod note + optional lock-thread checkbox. The message becomes a
  moderator-comment on the post and the reason/mod_note feeds the audit
  trail in `Kaguya.Discussions.hide_post/2`.

  Submission is purely a form `phx-submit`: the parent LiveView owns the
  event (default `submit_hide_post`) and the busy/open state. Driven by
  data attrs (`data-modal-panel`, `data-modal-cancel`, etc.) so the existing
  `ModalDialog` hook in `app.js` handles focus trap + Esc-to-close.
  """

  use KaguyaWeb, :html

  @reasons [
    %{value: "spam", label: "Spam", message: "Kaguya does not allow spam."},
    %{value: "harassment", label: "Harassment", message: "Kaguya does not allow harassment."},
    %{value: "hate", label: "Hate", message: "Kaguya does not allow hate."},
    %{
      value: "threatening_violence",
      label: "Threatening violence",
      message: "Kaguya does not allow threats of violence."
    },
    %{
      value: "other",
      label: "Other",
      message: "This content was removed because it breaks Kaguya's rules."
    }
  ]

  def reasons, do: @reasons

  @doc """
  Render the dialog. When `open` is false nothing is emitted, keeping the
  page DOM clean so screen readers don't announce an empty dialog node.
  """
  attr :open, :boolean, default: false
  attr :item_label, :string, default: "post"
  attr :busy, :boolean, default: false
  attr :allow_lock_thread, :boolean, default: false
  attr :submit_event, :string, default: "submit_hide_post"
  attr :cancel_event, :string, default: "cancel_hide_post"
  attr :id, :string, default: "removal-reason-dialog"

  def removal_reason_dialog(assigns) do
    assigns = assign(assigns, :reasons, @reasons)

    ~H"""
    <div
      :if={@open}
      id={@id}
      phx-hook="ModalDialog"
      data-cancel-event={@cancel_event}
      class="fixed inset-0 z-170 flex items-center justify-center bg-black/80 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        class="w-full max-w-[540px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] shadow-[0_8px_40px_rgba(0,0,0,0.55)]"
      >
        <div class="flex items-start justify-between gap-3 border-b border-[rgb(var(--border-divider))] px-5 py-4">
          <div class="min-w-0">
            <p
              id={"#{@id}-title"}
              class="text-left text-lg font-semibold text-[rgb(var(--foreground-primary))]"
            >
              Give a reason.
            </p>
            <p
              id={"#{@id}-description"}
              class="mt-2 max-w-[44ch] text-sm/5 text-[rgb(var(--foreground-tertiary))]"
            >
              The {@item_label} will be removed, and this message will be posted as a moderator comment.
            </p>
          </div>
          <button
            type="button"
            phx-click={@cancel_event}
            data-modal-cancel
            aria-label="Close"
            class="flex size-9 shrink-0 items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] transition hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
          >
            <Lucide.x class="size-4" aria-hidden />
          </button>
        </div>

        <form
          id={"#{@id}-form"}
          phx-submit={@submit_event}
          phx-hook="RemovalReasonForm"
          class="grid gap-4 p-5"
        >
          <label class="grid gap-2">
            <span class="flex items-center gap-2 text-sm font-medium text-[rgb(var(--foreground-secondary))]">
              <Lucide.shield_alert class="size-4" aria-hidden /> Removal reason
            </span>
            <select
              name="reason"
              required
              data-modal-initial-focus
              data-removal-reason
              class="h-12 cursor-pointer rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-4 text-sm text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option value="">Select a reason</option>
              <option
                :for={reason <- @reasons}
                value={reason.value}
                data-default-message={reason.message}
              >
                {reason.label}
              </option>
            </select>
          </label>

          <label class="grid gap-2">
            <span class="flex items-center gap-2 text-sm font-medium text-[rgb(var(--foreground-secondary))]">
              <Lucide.message_square class="size-4" aria-hidden /> Message to user
            </span>
            <textarea
              name="message"
              maxlength="1000"
              required
              data-removal-message
              placeholder="Select a reason to prefill the message"
              class="min-h-[130px] resize-none rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-3 text-sm text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))]"
            ></textarea>
            <span class="text-xs/5 text-[rgb(var(--foreground-tertiary))]">
              This will be posted as a moderator comment.
            </span>
          </label>

          <label class="grid gap-2">
            <span class="text-sm font-medium text-[rgb(var(--foreground-secondary))]">
              Internal mod note
            </span>
            <textarea
              name="mod_note"
              maxlength="1000"
              placeholder="Optional private note for moderator context"
              class="min-h-[74px] resize-none rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-3 text-sm text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))]"
            ></textarea>
          </label>

          <div class="-mx-5 -mb-5 flex items-center justify-between gap-3 border-t border-[rgb(var(--border-divider))] px-5 py-4">
            <label
              :if={@allow_lock_thread}
              class="flex items-center gap-2 text-sm font-medium text-[rgb(var(--foreground-secondary))]"
            >
              <input
                type="checkbox"
                name="lock_thread"
                value="true"
                checked
                class="size-4 cursor-pointer rounded border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]"
              />
              <Lucide.lock class="size-3.5" aria-hidden /> Lock thread
            </label>
            <span :if={!@allow_lock_thread}></span>

            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click={@cancel_event}
                data-modal-cancel
                class="h-10 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
              >
                Cancel
              </button>
              <button
                type="submit"
                data-removal-submit
                disabled
                class="h-10 rounded-[8px] bg-[rgb(var(--button-background-destructive-default))] px-4 text-sm font-medium text-white transition hover:bg-[rgb(var(--button-background-destructive-hover))] disabled:cursor-not-allowed disabled:opacity-50"
              >
                {if @busy, do: "Removing...", else: "Submit"}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
