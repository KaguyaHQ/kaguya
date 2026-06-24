defmodule KaguyaWeb.SharedComponents.MarkdownEditor do
  @moduledoc """
  Shared markdown composer — textarea + keyboard shortcuts + action row.

  Single source of truth for everywhere users author markdown: comment
  composers, comment-edit forms, the review editor, and (eventually) any
  other markdown surface. Mirrors `MarkdownEditor.tsx` + `ReplyInput.tsx`
  on the Next.js side: Cmd/Ctrl+B/I/K for inline formatting, Cmd+Enter to
  submit, auto-height textarea, click-anywhere-to-focus, expand-on-focus.

  Client behavior lives in the `MarkdownEditor` JS hook
  (`assets/js/hooks/markdown_editor.js`).

  ## Slots

  Use slots to extend the editor for richer surfaces (review editor) without
  reopening the component:

  - `:leading_inputs` — hidden inputs that ride along on submit
    (e.g. `parent_comment_id`).
  - `:above_textarea` — block-level controls rendered above the textarea
    (e.g. date range picker, rating stars).
  - `:before_actions` — controls on the action row, left of Cancel
    (e.g. spoiler toggle, char counter).
  - `:extra_actions` — buttons left of Cancel/Submit
    (e.g. Delete on review-edit).
  - `:actions` — completely overrides the default Cancel/Submit row.

  ## Example (comment composer)

      <.markdown_editor
        id="comments-top-form"
        target={@myself}
        submit_event="create_comment"
        cancel_event="cancel_composer"
        expand_event="expand_composer"
        submit_label="Comment"
        placeholder="Add a comment..."
        expanded={@expanded}
      />
  """

  use KaguyaWeb, :html

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true, doc: "Stable DOM id — also used for action-row id."
  attr :target, :any, required: true, doc: "`phx-target` for the form's events."

  attr :submit_event, :string, required: true
  attr :cancel_event, :string, default: nil
  attr :expand_event, :string, default: nil, doc: "Pushed on textarea focus, when set."

  attr :name, :string, default: "content", doc: "Textarea name (POST'd on submit)."
  attr :value, :string, default: "", doc: "Pre-populated content (e.g. for edit forms)."
  attr :rows, :integer, default: 1
  attr :maxlength, :integer, default: 5000
  attr :placeholder, :string, default: ""

  attr :submit_label, :string, default: "Submit"
  attr :cancel_label, :string, default: "Cancel"

  attr :show_actions, :boolean,
    default: true,
    doc: "Hide the bottom action row entirely (e.g. inline-only compose)."

  attr :submit_disabled_when_empty, :boolean,
    default: true,
    doc: "Disable submit while the textarea is whitespace-only."

  attr :class, :any, default: nil, doc: "Classes on the outer wrapper."
  attr :form_class, :any, default: nil, doc: "Override classes on the form element."

  attr :textarea_class, :any,
    default: nil,
    doc: "Override the default textarea classes."

  slot :leading_inputs
  slot :above_textarea
  slot :before_actions
  slot :extra_actions

  slot :actions,
    doc: "Override the entire action row. When set, default Cancel/Submit are hidden."

  def markdown_editor(assigns) do
    assigns =
      assigns
      |> assign_new(:default_form_class, fn ->
        "flex cursor-text flex-col overflow-hidden rounded-xl border border-[rgb(var(--border-divider))] text-[rgb(var(--foreground-primary))] dark:border-white/10"
      end)
      |> assign_new(:default_textarea_class, fn ->
        "min-h-[44px] w-full resize-none rounded-none border-0 bg-transparent px-3 pt-2.5 pb-1.5 text-sm text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))] focus:border-0 lg:min-h-[72px] lg:px-4 lg:pt-3 lg:pb-2 lg:text-base"
      end)

    ~H"""
    <div class={["w-full", @class]}>
      <form
        id={@id}
        phx-submit={@submit_event}
        phx-target={@target}
        phx-hook="MarkdownEditor"
        data-expand-event={@expand_event}
        class={@form_class || @default_form_class}
      >
        <%!--
          `_editor_id` rides along on submit so the LiveView can echo the
          form id back via `push_event("kaguya:markdown-editor-set", ...)` —
          that's how the server tells the hook which composer to clear or
          restore after a server-side submit completes.
        --%>
        <input type="hidden" name="_editor_id" value={@id} />
        {render_slot(@leading_inputs)}
        {render_slot(@above_textarea)}

        <textarea
          name={@name}
          rows={@rows}
          maxlength={@maxlength}
          placeholder={@placeholder}
          phx-focus={@expand_event}
          phx-target={@target}
          class={@textarea_class || @default_textarea_class}
        ><%= @value %></textarea>

        <%= cond do %>
          <% @actions != [] -> %>
            {render_slot(@actions)}
          <% @show_actions -> %>
            <div
              id={"#{@id}-actions"}
              class="flex items-center justify-end gap-2 px-2.5 pb-2.5 lg:px-3 lg:pb-3"
            >
              {render_slot(@before_actions)} {render_slot(@extra_actions)}
              <button
                :if={@cancel_event}
                type="button"
                phx-click={cancel_js(@id, @cancel_event, @target)}
                class="h-7 rounded-full bg-black/4 px-3 py-1 text-xs font-semibold text-[rgb(var(--foreground-primary))] transition hover:bg-black/8 lg:h-8 lg:px-4 lg:py-1.5 lg:text-sm dark:bg-white/6"
              >
                {@cancel_label}
              </button>
              <button
                type="submit"
                data-markdown-editor-submit="true"
                data-reply-submit="true"
                disabled={@submit_disabled_when_empty && String.trim(@value || "") == ""}
                class="h-7 min-w-[60px] rounded-full bg-[rgb(var(--button-background-brand-default))] px-3 py-1 text-xs font-semibold text-white transition hover:bg-[rgb(var(--button-background-brand-hover))] disabled:cursor-not-allowed disabled:opacity-50 lg:h-8 lg:min-w-[68px] lg:px-4 lg:py-1.5 lg:text-sm"
                style="text-shadow: 0px 3.04px 3.04px rgba(0, 0, 0, 0.25)"
              >
                {@submit_label}
              </button>
            </div>
          <% true -> %>
        <% end %>
      </form>
    </div>
    """
  end

  defp cancel_js(id, cancel_event, target) do
    JS.dispatch("kaguya:reply-input-cancel", to: "##{id}")
    |> JS.hide(to: "##{id}-actions")
    |> JS.push(cancel_event, target: target)
  end
end
