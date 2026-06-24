defmodule KaguyaWeb.Components.Comments do
  @moduledoc """
  Shared HEEx components for reusable comment threads.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu

  alias KaguyaWeb.SharedComponents.LikeButton
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @initial_visible_replies 3

  attr :comments_count, :integer, default: 0
  attr :can_comment, :boolean, default: false
  attr :current_user, :map, default: nil
  attr :target, :any, required: true
  attr :expanded, :boolean, default: false
  attr :show_disabled_composer, :boolean, default: true

  def header_and_composer(assigns) do
    ~H"""
    <h3 class="mb-5 text-sm font-medium text-[rgb(var(--foreground-secondary))]">
      <%= if @comments_count > 0 do %>
        {format_count(@comments_count)}
      <% end %>
      {pluralize(@comments_count, "Comment", "Comments")}
    </h3>

    <.reply_input
      :if={@can_comment}
      id="comments-top-form"
      target={@target}
      submit_event="create_comment"
      cancel_event="cancel_composer"
      expand_event="expand_composer"
      current_user={@current_user}
      button_text="Comment"
      placeholder="Add a comment..."
      expanded={@expanded}
    />

    <div :if={!@can_comment && @show_disabled_composer} class="flex items-start gap-[11px]">
      <div class="size-[26px] shrink-0 rounded-full bg-[rgb(var(--surface-banner))]/40 lg:size-[36px]" />
      <div class="h-[44px] flex-1 rounded-[4px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] lg:h-[72px]" />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :submit_event, :string, required: true
  attr :cancel_event, :string, required: true
  attr :expand_event, :string, default: nil
  attr :current_user, :map, default: nil
  attr :parent_comment_id, :string, default: nil
  attr :content, :string, default: ""
  attr :button_text, :string, default: "Reply"
  attr :placeholder, :string, default: "Add a reply..."
  attr :expanded, :boolean, default: true
  attr :rows, :integer, default: 1
  attr :class, :any, default: nil

  def reply_input(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.MarkdownEditor.markdown_editor
      id={@id}
      target={@target}
      submit_event={@submit_event}
      cancel_event={@cancel_event}
      expand_event={@expand_event}
      value={@content}
      rows={@rows}
      placeholder={@placeholder}
      submit_label={@button_text}
      show_actions={@expanded}
      class={["w-full", @parent_comment_id && "mt-3", @class]}
    >
      <:leading_inputs>
        <input
          :if={@parent_comment_id}
          type="hidden"
          name="parent_comment_id"
          value={@parent_comment_id}
        />
      </:leading_inputs>
    </KaguyaWeb.SharedComponents.MarkdownEditor.markdown_editor>
    """
  end

  attr :node, :map, required: true
  attr :target, :any, required: true
  attr :current_user, :map, default: nil
  attr :active_reply_id, :string, default: nil
  attr :editing_id, :string, default: nil
  attr :collapsed_ids, :any, required: true
  attr :show_all_ids, :any, required: true
  attr :can_moderate, :boolean, default: false
  attr :locked, :boolean, default: false

  def thread(assigns) do
    assigns =
      assigns
      |> assign(:comment, assigns.node.comment)
      |> assign(:has_children, assigns.node.children != [])
      |> assign(:expanded, expanded?(assigns.node, assigns.collapsed_ids))
      |> assign(:visible_children, visible_children(assigns.node, assigns.show_all_ids))
      |> assign(:hidden_children_count, hidden_children_count(assigns.node, assigns.show_all_ids))
      |> assign(:descendant_count, descendant_count(assigns.node))
      |> assign(
        :visible_children_with_meta,
        visible_children_with_meta(assigns.node, assigns.show_all_ids)
      )

    ~H"""
    <div
      id={"comment-thread-#{@comment.id}"}
      phx-hook="CommentThread"
      data-comment-thread-id={@comment.id}
      class="relative"
    >
      <.comment_item
        comment={@comment}
        target={@target}
        current_user={@current_user}
        active_reply_id={@active_reply_id}
        editing_id={@editing_id}
        can_moderate={@can_moderate}
        locked={@locked}
      />

      <button
        :if={@has_children}
        type="button"
        phx-click="toggle_thread"
        phx-value-id={@comment.id}
        phx-target={@target}
        data-comment-trunk
        class="absolute top-[26px] bottom-0 left-0 z-20 w-[26px] cursor-pointer border-0 bg-transparent p-0 lg:top-[36px] lg:w-[36px]"
        aria-label={if @expanded, do: "Collapse replies", else: "Expand replies"}
      >
        <span class="absolute top-0 left-1/2 block h-full w-px bg-[rgb(var(--border-divider))]" />
        <span class="absolute top-1/2 left-1/2 flex size-[15px] -translate-1/2 items-center justify-center rounded-full bg-[rgb(var(--surface-base))] text-[rgb(var(--foreground-secondary))] lg:size-[17px]">
          <%= if @expanded do %>
            <Lucide.circle_minus class="size-full" aria-hidden />
          <% else %>
            <Lucide.circle_plus class="size-full" aria-hidden />
          <% end %>
        </span>
      </button>

      <div
        :if={@has_children && !@expanded}
        id={"comment-thread-#{@comment.id}-children"}
        data-comment-children
        class="relative mt-4 ml-[13px] pl-[16px] lg:ml-[18px] lg:pl-[29px]"
      >
        <div
          id={"comment-thread-#{@comment.id}-last-branch"}
          data-comment-last-branch-for={@comment.id}
          class="relative"
        >
          <.thread_branch />
          <button
            type="button"
            phx-click="toggle_thread"
            phx-value-id={@comment.id}
            phx-target={@target}
            class="mt-[4px] ml-1 cursor-pointer border-0 bg-transparent p-0 text-xs text-[rgb(var(--foreground-secondary))] duration-75 hover:text-[rgb(var(--foreground-primary))] lg:mt-[9px]"
          >
            {@descendant_count} {pluralize(@descendant_count, "reply", "replies")}
          </button>
        </div>
      </div>

      <div
        :if={@has_children && @expanded}
        id={"comment-thread-#{@comment.id}-children"}
        data-comment-children
        class="relative mt-4 ml-[13px] pl-[16px] lg:ml-[18px] lg:pl-[29px]"
      >
        <div
          :for={entry <- @visible_children_with_meta}
          id={if entry.last_branch?, do: "comment-thread-#{@comment.id}-last-branch"}
          data-comment-last-branch-for={if entry.last_branch?, do: @comment.id}
          class="relative mt-3 first:mt-0"
        >
          <.thread_branch />
          <.thread
            node={entry.node}
            target={@target}
            current_user={@current_user}
            active_reply_id={@active_reply_id}
            editing_id={@editing_id}
            collapsed_ids={@collapsed_ids}
            show_all_ids={@show_all_ids}
            can_moderate={@can_moderate}
            locked={@locked}
          />
        </div>

        <div
          :if={@hidden_children_count > 0}
          id={"comment-thread-#{@comment.id}-last-branch"}
          data-comment-last-branch-for={@comment.id}
          class="relative mt-3"
        >
          <.thread_branch />
          <button
            type="button"
            phx-click="show_all_replies"
            phx-value-id={@comment.id}
            phx-target={@target}
            class="cursor-pointer border-0 bg-transparent p-0 text-xs text-[rgb(var(--foreground-secondary))] duration-75 hover:text-[rgb(var(--foreground-primary))]"
          >
            Show {@hidden_children_count} more {pluralize(@hidden_children_count, "reply", "replies")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :comment, :map, required: true
  attr :target, :any, required: true
  attr :current_user, :map, default: nil
  attr :active_reply_id, :string, default: nil
  attr :editing_id, :string, default: nil
  attr :can_moderate, :boolean, default: false
  attr :locked, :boolean, default: false

  def comment_item(assigns) do
    assigns =
      assigns
      |> assign(:is_mine, same_user?(assigns.current_user, assigns.comment.user))
      |> assign(:is_hidden, not is_nil(assigns.comment.hidden_at))
      |> assign(
        :can_report,
        can_report?(
          assigns.current_user,
          same_user?(assigns.current_user, assigns.comment.user),
          assigns.can_moderate
        )
      )

    ~H"""
    <div
      id={"comment-#{@comment.id}"}
      class="flex w-full gap-[11px] rounded-lg transition-colors"
    >
      <.avatar user={@comment.user} size="size-[26px] lg:size-[36px]" linked />

      <div class="min-w-0 flex-1">
        <div class="flex min-w-0 items-center gap-1">
          <.link
            :if={@comment.user}
            navigate={profile_path(@comment.user)}
            class="max-w-[120px] truncate text-xs leading-[22px] font-semibold text-[rgb(var(--foreground-secondary))] lg:max-w-none lg:text-sm"
          >
            {display_name(@comment.user)}
          </.link>
          <span
            :if={@comment.user && Map.get(@comment.user, :is_discussion_moderator, false)}
            class="inline-flex h-3.5 shrink-0 items-center rounded-[3px] bg-[rgb(var(--primitives-palette-green-base)/0.15)] px-1 text-[9px] leading-none font-semibold text-[rgb(var(--primitives-palette-green-base))]"
          >
            MOD
          </span>
          <Lucide.pin
            :if={Map.get(@comment, :is_pinned, false)}
            class="size-3 shrink-0 text-[rgb(var(--foreground-tertiary))]"
            aria-label="Pinned"
          />
          <span class="text-[7px] text-[rgb(var(--foreground-primary))]/40">•</span>
          <time
            class="text-xs font-light text-[rgb(var(--foreground-primary))]"
            title={SharedTime.datetime_title(@comment.inserted_at)}
          >
            {SharedTime.calendar_custom(@comment.inserted_at)}
          </time>
          <span
            :if={@comment.is_edited}
            class="text-xs font-light text-[rgb(var(--foreground-primary))]"
          >
            (edited)
          </span>
          <span
            :if={@is_hidden}
            class="rounded-full bg-[rgb(var(--surface-elevated))] px-1.5 py-0.5 text-[10px] font-medium text-[rgb(var(--foreground-tertiary))]"
          >
            hidden
          </span>
        </div>

        <.reply_input
          :if={@editing_id == @comment.id && !@locked}
          id={"comment-#{@comment.id}-edit-form"}
          target={@target}
          submit_event="update_comment"
          cancel_event="cancel_edit"
          current_user={@current_user}
          content={@comment.content}
          button_text="Save"
          placeholder="Edit comment..."
          rows={2}
          class="mt-1"
        />

        <.comment_content
          :if={@editing_id != @comment.id}
          id={"comment-#{@comment.id}-content"}
          content={@comment.content}
          class="mt-1 text-sm font-normal text-[rgb(var(--foreground-primary))] lg:text-base"
        />

        <div :if={@editing_id != @comment.id} class="mt-3 flex h-9 items-center gap-4 lg:h-8">
          <LikeButton.like_button
            id={"comment-#{@comment.id}-like"}
            click="toggle_like"
            value_id={@comment.id}
            value_liked={@comment.liked_by_me}
            target={@target}
            liked={@comment.liked_by_me}
            likes_count={@comment.likes_count || 0}
          />

          <button
            :if={!@locked}
            id={"comment-#{@comment.id}-reply"}
            type="button"
            phx-click="start_reply"
            phx-value-id={@comment.id}
            phx-target={@target}
            class="flex gap-1 p-0 text-xs font-semibold text-[rgb(var(--foreground-secondary))] no-underline hover:text-[rgb(var(--foreground-primary))] lg:text-sm lg:font-normal"
          >
            Reply
          </button>

          <button
            :if={Map.get(@comment, :share_url)}
            id={"comment-#{@comment.id}-share"}
            type="button"
            data-share-button
            data-share-url={@comment.share_url}
            data-share-title="Kaguya discussion comment"
            class="flex gap-1 p-0 text-xs font-semibold text-[rgb(var(--foreground-secondary))] no-underline hover:text-[rgb(var(--foreground-primary))] lg:text-sm lg:font-normal"
          >
            Share
          </button>

          <.menu
            :if={@is_mine || @can_moderate || @can_report}
            id={"comment-#{@comment.id}-actions"}
            align="end"
            class="group -ml-2 flex size-9 cursor-pointer items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] hover:bg-white/4 hover:text-[#9BC5FF] lg:size-8"
          >
            <:trigger aria-label="Comment actions">
              <Lucide.ellipsis class="size-4" aria-hidden />
              <span class="sr-only">Comment actions</span>
            </:trigger>
            <div class="w-[120px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 shadow-[0_5px_15px_rgba(0,5,15,0.35)]">
              <.menu_item
                :if={@is_mine && !@locked}
                event="start_edit"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.pencil class="size-4" aria-hidden /> Edit
              </.menu_item>
              <.menu_item
                :if={@is_mine && !@locked}
                event="confirm_delete_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[#f94441] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.trash_2 class="-mt-0.5 size-4 shrink-0" aria-hidden /> Delete
              </.menu_item>
              <.menu_item
                :if={@can_report}
                event="open_report_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.flag class="-mt-0.5 size-4 shrink-0" aria-hidden /> Report
              </.menu_item>
              <.menu_item
                :if={@can_moderate && !@is_hidden}
                event="hide_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.eye_off class="-mt-0.5 size-4 shrink-0" aria-hidden /> Hide
              </.menu_item>
              <.menu_item
                :if={@can_moderate && @is_hidden}
                event="unhide_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.eye class="-mt-0.5 size-4 shrink-0" aria-hidden /> Unhide
              </.menu_item>
              <.menu_item
                :if={@can_moderate && Map.get(@comment, :pin_eligible, false) && @comment.is_pinned}
                event="unpin_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.pin_off class="-mt-0.5 size-4 shrink-0" aria-hidden /> Unpin
              </.menu_item>
              <.menu_item
                :if={@can_moderate && Map.get(@comment, :pin_eligible, false) && !@comment.is_pinned}
                event="pin_comment"
                target={@target}
                value={%{id: @comment.id}}
                class="flex size-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-4 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
              >
                <Lucide.pin class="-mt-0.5 size-4 shrink-0" aria-hidden /> Pin
              </.menu_item>
            </div>
          </.menu>
        </div>

        <.reply_input
          :if={@active_reply_id == @comment.id && @editing_id != @comment.id && !@locked}
          id={"comment-#{@comment.id}-reply-form"}
          target={@target}
          submit_event="create_comment"
          cancel_event="cancel_reply"
          current_user={@current_user}
          parent_comment_id={@comment.id}
          button_text="Reply"
          placeholder="Add a reply..."
          class="mt-3 max-lg:ml-0"
        />
      </div>
    </div>
    """
  end

  attr :comment_id, :string, default: nil
  attr :target, :any, required: true
  attr :error, :string, default: nil
  attr :success, :boolean, default: false

  def report_dialog(assigns) do
    assigns = assign(assigns, :categories, report_categories())

    ~H"""
    <div
      :if={@comment_id}
      id={"report-comment-dialog-#{@comment_id}"}
      phx-hook="ModalDialog"
      data-cancel-event="cancel_report_comment"
      class="fixed inset-0 z-150 flex items-center justify-center bg-black/80 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby={"report-comment-dialog-#{@comment_id}-title"}
        aria-describedby={"report-comment-dialog-#{@comment_id}-description"}
        class="w-full max-w-[480px] rounded-[16px] bg-[rgb(var(--surface-base))] px-5 pt-8 pb-6 shadow-[0_8px_40px_rgba(0,0,0,0.55)] sm:px-10"
      >
        <p
          id={"report-comment-dialog-#{@comment_id}-title"}
          class="text-xl font-semibold text-[rgb(var(--foreground-primary))] sm:text-2xl"
        >
          Report Comment
        </p>
        <p
          id={"report-comment-dialog-#{@comment_id}-description"}
          class="mt-4 text-base leading-[26px] text-[rgb(var(--foreground-secondary))]"
        >
          Does this comment break our guidelines? Let us know so we can take a closer look.
        </p>

        <%= if @success do %>
          <p class="mt-4 text-sm text-green-400">Report submitted successfully.</p>
          <div class="mt-5 flex justify-end">
            <button
              type="button"
              phx-click="cancel_report_comment"
              phx-target={@target}
              data-modal-cancel
              data-modal-initial-focus
              class="rounded-[8px] bg-[rgb(var(--surface-elevated))] px-[26px] py-3.5 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
            >
              Close
            </button>
          </div>
        <% else %>
          <form
            id="report-comment-form"
            phx-submit="submit_report_comment"
            phx-target={@target}
            phx-hook="ReportForm"
            class="mt-4 flex flex-col gap-4"
          >
            <div class="flex flex-col gap-1.5">
              <label
                for="report-comment-category"
                class="text-xs text-[rgb(var(--foreground-primary))]"
              >
                Category
              </label>
              <select
                id="report-comment-category"
                name="category"
                required
                data-modal-initial-focus
                class="w-full cursor-pointer rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-2.5 text-sm text-[rgb(var(--foreground-primary))] outline-none"
              >
                <option value="">Select a category</option>
                <option :for={{value, label} <- @categories} value={value}>{label}</option>
              </select>
            </div>

            <div class="flex flex-col gap-1.5">
              <label for="report-comment-reason" class="text-xs text-[rgb(var(--foreground-primary))]">
                Why are you reporting this comment?
              </label>
              <input
                id="report-comment-reason"
                name="reason"
                type="text"
                required
                maxlength="200"
                placeholder="Brief summary (required)"
                class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-2.5 text-sm text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))]"
              />
              <span
                data-reason-counter
                class="text-right text-[11px] text-[rgb(var(--foreground-tertiary))]"
              >
                0/200
              </span>
            </div>

            <div class="flex flex-col gap-1.5">
              <label
                for="report-comment-message"
                class="text-xs text-[rgb(var(--foreground-primary))]"
              >
                Additional details (optional)
              </label>
              <textarea
                id="report-comment-message"
                name="message"
                maxlength="5000"
                placeholder="Provide more context if needed"
                class="min-h-[100px] resize-none rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-3.5 text-xs text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))]"
              />
            </div>

            <p :if={@error} class="text-sm text-red-400">{@error}</p>

            <div class="flex justify-end gap-2">
              <button
                type="button"
                phx-click="cancel_report_comment"
                phx-target={@target}
                data-modal-cancel
                class="rounded-[8px] bg-[rgb(var(--surface-elevated))] px-[26px] py-3.5 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
              >
                Cancel
              </button>
              <button
                type="submit"
                data-report-submit
                disabled
                class="rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-[26px] py-3.5 text-sm text-white transition hover:bg-[rgb(var(--button-background-brand-hover))] disabled:cursor-not-allowed disabled:opacity-50"
              >
                Report
              </button>
            </div>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  attr :comment_id, :string, default: nil
  attr :target, :any, required: true

  def delete_confirm_dialog(assigns) do
    ~H"""
    <div
      :if={@comment_id}
      id={"delete-comment-dialog-#{@comment_id}"}
      phx-hook="ModalDialog"
      data-cancel-event="cancel_delete_comment"
      class="fixed inset-0 z-150 flex items-center justify-center bg-black/80 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby={"delete-comment-dialog-#{@comment_id}-title"}
        aria-describedby={"delete-comment-dialog-#{@comment_id}-description"}
        class="w-full max-w-[380px] rounded-[14px] bg-[#0A0A0A] p-6 shadow-[0_8px_40px_rgba(0,0,0,0.55)]"
      >
        <p
          id={"delete-comment-dialog-#{@comment_id}-title"}
          class="text-lg font-medium text-[rgb(var(--foreground-primary))]"
        >
          Delete Comment?
        </p>
        <p
          id={"delete-comment-dialog-#{@comment_id}-description"}
          class="mt-2 text-sm/5 text-[rgb(var(--foreground-tertiary))]"
        >
          This will permanently delete your comment. This action cannot be undone.
        </p>

        <div class="mt-5 flex justify-end gap-2.5">
          <button
            type="button"
            phx-click="cancel_delete_comment"
            phx-target={@target}
            data-modal-cancel
            data-modal-initial-focus
            class="h-9 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 text-[13px] font-normal text-[rgb(var(--foreground-secondary))] transition hover:bg-white/8"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="delete_pending_comment"
            phx-target={@target}
            class="h-9 min-w-16 rounded-[8px] bg-[rgb(var(--button-background-destructive-default))] px-4 text-[13px] font-medium text-white transition hover:bg-[rgb(var(--button-background-destructive-hover))]"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :content, :string, default: ""
  attr :id, :string, required: true
  attr :class, :any, default: nil

  def comment_content(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CommentContent"
      class={["comment-content kaguya-markdown wrap-break-word", @class]}
    >
      <KaguyaWeb.SharedComponents.Markdown.markdown_inline content={@content} variant="comment" />
    </div>
    """
  end

  attr :user, :map, default: nil
  attr :size, :string, default: "size-[26px] lg:size-[36px]"
  attr :sizes, :string, default: "(max-width: 1023px) 26px, 36px"
  attr :linked, :boolean, default: false

  def avatar(%{linked: true, user: %{username: username}} = assigns) when is_binary(username) do
    ~H"""
    <.link navigate={profile_path(@user)} class="h-fit shrink-0">
      <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
        user={@user}
        size={@size}
        sizes={@sizes}
        fallback={:initials}
      />
    </.link>
    """
  end

  def avatar(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@user || %{}}
      size={@size}
      sizes={@sizes}
      fallback={:initials}
    />
    """
  end

  defp thread_branch(assigns) do
    ~H"""
    <div class="pointer-events-none absolute top-0 left-[-16px] lg:left-[-29px]">
      <svg
        class="text-[rgb(var(--border-divider))] duration-75 lg:hidden"
        width="16"
        height="13"
        viewBox="0 0 16 13"
        fill="none"
      >
        <path d="M 0.5 4 A 8 8 0 0 0 8.5 12 H 16" stroke="currentColor" stroke-width="1" />
      </svg>
      <svg
        class="hidden text-[rgb(var(--border-divider))] duration-75 lg:block"
        width="29"
        height="18"
        viewBox="0 0 29 18"
        fill="none"
      >
        <path d="M 0.5 9 A 8 8 0 0 0 8.5 17 H 29" stroke="currentColor" stroke-width="1" />
      </svg>
    </div>
    """
  end

  defp expanded?(%{comment: %{id: id}, depth: depth}, collapsed_ids) do
    depth < 3 and not MapSet.member?(collapsed_ids, id)
  end

  defp expanded?(%{comment: %{id: id}}, collapsed_ids), do: not MapSet.member?(collapsed_ids, id)

  defp visible_children(node, show_all_ids) do
    if MapSet.member?(show_all_ids, node.comment.id) do
      node.children
    else
      Enum.take(node.children, @initial_visible_replies)
    end
  end

  defp hidden_children_count(node, show_all_ids) do
    if MapSet.member?(show_all_ids, node.comment.id) do
      0
    else
      max(length(node.children) - @initial_visible_replies, 0)
    end
  end

  defp visible_children_with_meta(node, show_all_ids) do
    children = visible_children(node, show_all_ids)
    hidden_count = hidden_children_count(node, show_all_ids)
    last_index = length(children) - 1

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      %{node: child, last_branch?: hidden_count == 0 and index == last_index}
    end)
  end

  defp descendant_count(node) do
    Enum.reduce(node.children, length(node.children), fn child, count ->
      count + descendant_count(child)
    end)
  end

  defp same_user?(%{id: id}, %{id: id}) when is_binary(id), do: true
  defp same_user?(_current_user, _comment_user), do: false

  defp can_report?(nil, _is_mine, _can_moderate), do: false
  defp can_report?(_current_user, true, _can_moderate), do: false
  defp can_report?(_current_user, _is_mine, true), do: false
  defp can_report?(_current_user, _is_mine, _can_moderate), do: true

  defp display_name(%{display_name: name, username: username}) do
    if is_binary(name) and String.trim(name) != "", do: name, else: username
  end

  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_user), do: "Kaguya user"

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_user), do: "/"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp format_count(value) when is_integer(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 1)}M"
  end

  defp format_count(value) when is_integer(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 1)}K"
  end

  defp format_count(value), do: to_string(value || 0)

  defp report_categories do
    [
      {"spam", "Spam"},
      {"harassment", "Harassment"},
      {"spoilers", "Spoilers"},
      {"off_topic", "Off-topic"},
      {"incorrect_info", "Incorrect info"},
      {"inappropriate", "Inappropriate content"},
      {"other", "Other"}
    ]
  end
end
