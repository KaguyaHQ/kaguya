defmodule KaguyaWeb.Components.Discussions.EditPostDialog do
  @moduledoc """
  In-place edit dialog for an existing discussion post. Title is locked once
  others have engaged (matched server-side by `Kaguya.Discussions.update_post/3`
  via `check_title_unlocked/2`) so we render it read-only when the post has
  comments; otherwise it's editable. Category and entity target are never
  editable in this dialog — they're properties of the post, not of the
  current revision.

  We don't reuse the full new-post UI here because the category picker is
  pointless in edit mode and the simpler dialog keeps the show page cleaner.
  """

  use KaguyaWeb, :html

  attr :open, :boolean, default: false
  attr :post, :map, default: nil
  attr :form, :map, default: %{}
  attr :busy, :boolean, default: false
  attr :error_message, :string, default: nil
  attr :title_locked, :boolean, default: false
  attr :submit_event, :string, default: "submit_edit_post"
  attr :cancel_event, :string, default: "cancel_edit_post"
  attr :id, :string, default: "edit-post-dialog"

  def edit_post_dialog(assigns) do
    ~H"""
    <div
      :if={@open && @post}
      id={@id}
      phx-hook="ModalDialog"
      data-cancel-event={@cancel_event}
      class="fixed inset-0 z-170 flex items-end justify-center bg-black/80 px-0 backdrop-blur-md sm:items-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="max-h-full w-full overflow-y-auto bg-[rgb(var(--surface-base))] text-[rgb(var(--foreground-primary))] outline-hidden sm:max-h-[80vh] sm:max-w-[640px] sm:rounded-[12px]"
      >
        <div class="flex items-center justify-between border-b border-[rgb(var(--border-divider))] px-5 py-3 sm:px-6 sm:pt-6 sm:pb-3">
          <h2
            id={"#{@id}-title"}
            class="text-lg font-semibold text-[rgb(var(--foreground-primary))]"
          >
            Edit Post
          </h2>
          <button
            type="button"
            phx-click={@cancel_event}
            data-modal-cancel
            class="flex size-9 items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] transition-colors hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
            aria-label="Close"
          >
            <Lucide.x class="size-4" aria-hidden />
          </button>
        </div>

        <form
          phx-submit={@submit_event}
          class="flex flex-col p-5 sm:px-6 sm:pt-4 sm:pb-6"
        >
          <div :if={@post.entity_tag} class="mb-4">
            <span class="inline-flex max-w-full items-center gap-1.5 rounded-md bg-white/8 px-2.5 py-1.5 text-sm font-medium text-[rgb(var(--foreground-primary))]">
              {@post.entity_tag.label}
              <span class="text-[10px] tracking-wide text-[rgb(var(--foreground-tertiary))] uppercase">
                locked
              </span>
            </span>
          </div>

          <p
            :if={@error_message}
            class="mb-3 text-sm text-[rgb(var(--semantic-error))]"
          >
            {@error_message}
          </p>

          <div class="overflow-hidden rounded-lg border border-[rgb(var(--text-field-border))] bg-[rgb(var(--text-field-bg))]">
            <div class="px-3 pt-3 pb-2">
              <input
                name="title"
                value={Map.get(@form, "title", @post.title)}
                placeholder="Title"
                maxlength="200"
                data-modal-initial-focus={!@title_locked}
                disabled={@title_locked}
                class={[
                  "w-full bg-transparent text-base font-semibold text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:outline-hidden",
                  @title_locked && "cursor-not-allowed opacity-60"
                ]}
              />
              <p
                :if={@title_locked}
                class="mt-1 text-xs text-[rgb(var(--foreground-tertiary))]"
              >
                Title is locked once a post has replies.
              </p>
            </div>

            <div class="mx-3 border-t border-[rgb(var(--border-divider))]/40"></div>

            <textarea
              name="content"
              rows="6"
              maxlength="20000"
              placeholder="Write something..."
              data-modal-initial-focus={@title_locked}
              class="max-h-[400px] min-h-[150px] w-full resize-y rounded-none border-0 bg-transparent p-3 text-base text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:outline-hidden"
            ><%= Map.get(@form, "content", @post.content) || "" %></textarea>
          </div>

          <div class="flex justify-end gap-3 pt-4">
            <button
              type="button"
              phx-click={@cancel_event}
              data-modal-cancel
              class="h-9 rounded-[6px] bg-white/6 px-4 text-sm font-medium text-[rgb(var(--foreground-primary))] transition-colors hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@busy}
              class="h-9 rounded-[6px] bg-[rgb(var(--button-background-brand-default))] px-5 text-sm font-medium text-white transition-colors hover:bg-[rgb(var(--button-background-brand-hover))] disabled:cursor-not-allowed disabled:opacity-50"
            >
              {if @busy, do: "Saving...", else: "Save"}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
