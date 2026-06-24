defmodule KaguyaWeb.DiscussionLive.Show do
  use KaguyaWeb, :live_view

  import KaguyaWeb.SharedComponents.ModerationNotice
  import KaguyaWeb.SharedComponents.RemovalReasonDialog
  import KaguyaWeb.Components.Discussions.EditPostDialog
  import KaguyaWeb.Components.Discussions.PostActionsMenu

  alias Kaguya.Discussions
  alias Kaguya.Reports
  alias KaguyaWeb.Comments.DiscussionAdapter
  alias KaguyaWeb.CommentsComponent
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.DiscussionLive.Data
  alias KaguyaWeb.Markdown.UserContent
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Discussion • Kaguya",
       meta_description: "Discussion on Kaguya",
       post: nil,
       comments_page: 1,
       focus_comment_id: nil,
       can_discuss: false,
       can_moderate_discussions: false,
       load_error?: false,
       not_found?: false,
       # Post action dialogs / inline state. Each pair gates a modal +
       # tracks the in-flight server call so the submit buttons can disable
       # themselves while we wait for the context module to reply.
       edit_dialog_open: false,
       edit_form: %{},
       edit_busy: false,
       edit_error: nil,
       hide_dialog_open: false,
       hide_busy: false,
       hide_error: nil,
       delete_dialog_open: false,
       delete_busy: false,
       report_dialog_open: false,
       report_error: nil,
       report_success: false,
       action_error: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Data.load_post_page(params["short_id"], socket.assigns.current_user) do
      {:ok, payload} ->
        {:noreply,
         assign(socket,
           post: payload.post,
           comments_page: page_param(params["page"]),
           focus_comment_id:
             resolve_focus_comment(
               payload.post,
               params["comment_short_id"],
               socket.assigns.current_user
             ),
           can_discuss: payload.can_discuss,
           can_moderate_discussions: payload.can_moderate_discussions,
           load_error?: false,
           not_found?: false,
           page_title: "#{payload.post.title || "Discussion"} • Kaguya",
           meta_description: meta_description(payload.post)
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           post: nil,
           not_found?: true,
           load_error?: false,
           page_title: "Discussion • Kaguya"
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, load_error?: true, not_found?: false)}
    end
  end

  # Translate the URL `comment_short_id` (8-char path segment) into the
  # internal UUID `focus_comment_id` the comments component already
  # understands. When the short id resolves we pass the UUID through;
  # when it can't (deleted/hidden/typo) we hand back a generated UUID so
  # the adapter's existing not-found path lights up the recovery banner
  # instead of silently dropping focus mode.
  defp resolve_focus_comment(_post, nil, _viewer), do: nil
  defp resolve_focus_comment(_post, "", _viewer), do: nil

  defp resolve_focus_comment(%{id: post_id}, short_id, viewer) when is_binary(short_id) do
    case Discussions.get_comment_by_short_id_for_post(post_id, short_id, viewer) do
      {:ok, comment} -> comment.id
      {:error, :not_found} -> Ecto.UUID.generate()
    end
  end

  defp resolve_focus_comment(_post, _short_id, _viewer), do: nil

  @impl true
  def handle_event("toggle_post_like", _params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         post when is_map(post) <- socket.assigns.post do
      was_liked? = post.liked_by_me
      next_liked? = not was_liked?
      socket = assign(socket, post: apply_local_post_like(post, next_liked?))

      case toggle_post_like(was_liked?, post.id, user_id) do
        {:ok, true} ->
          {:noreply, socket}

        _ ->
          {:noreply,
           socket
           |> assign(post: apply_local_post_like(socket.assigns.post, was_liked?))
           |> put_flash(:error, "Could not update this like.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to like discussions.")}
    end
  end

  # ────────────── Owner edit ──────────────

  def handle_event("start_edit_post", _params, socket) do
    {:noreply,
     assign(socket,
       edit_dialog_open: true,
       edit_form: %{},
       edit_error: nil,
       edit_busy: false
     )}
  end

  def handle_event("cancel_edit_post", _params, socket) do
    {:noreply, assign(socket, edit_dialog_open: false, edit_error: nil, edit_busy: false)}
  end

  def handle_event("submit_edit_post", params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         post when is_map(post) <- socket.assigns.post,
         attrs <- %{
           title: trimmed(params["title"]),
           content: trimmed(params["content"])
         },
         socket <- assign(socket, edit_busy: true),
         {:ok, _updated} <- Discussions.update_post(post.id, user_id, attrs),
         {:ok, payload} <- Data.load_post_page(post.short_id, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(
         post: payload.post,
         edit_dialog_open: false,
         edit_form: %{},
         edit_busy: false,
         edit_error: nil
       )
       |> push_toast(:success, "Post updated")}
    else
      nil ->
        {:noreply, assign(socket, action_error: "Sign in to edit posts.", edit_busy: false)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           edit_form: params,
           edit_error: changeset_error_message(changeset),
           edit_busy: false
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           edit_form: params,
           edit_error: error_message(reason),
           edit_busy: false
         )}
    end
  end

  # ────────────── Mod toggles ──────────────

  def handle_event("toggle_pin_post", _params, socket) do
    toast = if socket.assigns.post.is_pinned, do: "Post unpinned", else: "Post pinned"

    moderate_post(
      socket,
      fn post_id ->
        Discussions.admin_moderate_post(post_id, %{is_pinned: !socket.assigns.post.is_pinned})
      end,
      toast
    )
  end

  def handle_event("toggle_lock_post", _params, socket) do
    toast = if socket.assigns.post.is_locked, do: "Post unlocked", else: "Post locked"

    moderate_post(
      socket,
      fn post_id ->
        if socket.assigns.post.is_locked,
          do: Discussions.admin_unlock_post(post_id),
          else: Discussions.admin_lock_post(post_id)
      end,
      toast
    )
  end

  def handle_event("unhide_post", _params, socket) do
    moderate_post(socket, fn post_id -> Discussions.unhide_post(post_id) end, "Post unhidden")
  end

  # ────────────── Hide with reason ──────────────

  def handle_event("start_hide_post", _params, socket) do
    {:noreply, assign(socket, hide_dialog_open: true, hide_error: nil, hide_busy: false)}
  end

  def handle_event("cancel_hide_post", _params, socket) do
    {:noreply, assign(socket, hide_dialog_open: false, hide_error: nil, hide_busy: false)}
  end

  def handle_event("submit_hide_post", params, socket) do
    if socket.assigns.can_moderate_discussions do
      post = socket.assigns.post

      attrs = %{
        reason: trimmed(params["reason"]),
        mod_note: trimmed(params["mod_note"]),
        add_comment: true,
        comment: trimmed(params["message"]),
        lock_thread: params["lock_thread"] == "true"
      }

      socket = assign(socket, hide_busy: true)

      with {:ok, _post} <- Discussions.hide_post(post.id, attrs),
           {:ok, payload} <- Data.load_post_page(post.short_id, socket.assigns.current_user) do
        {:noreply,
         socket
         |> assign(
           post: payload.post,
           hide_dialog_open: false,
           hide_busy: false,
           hide_error: nil
         )
         |> push_toast(:success, "Post removed")}
      else
        {:error, reason} ->
          {:noreply, assign(socket, hide_busy: false, hide_error: error_message(reason))}
      end
    else
      {:noreply, push_toast(socket, :error, "You don't have permission to do that.")}
    end
  end

  # ────────────── Delete ──────────────

  def handle_event("confirm_delete_post", _params, socket) do
    {:noreply, assign(socket, delete_dialog_open: true, delete_busy: false)}
  end

  def handle_event("cancel_delete_post", _params, socket) do
    {:noreply, assign(socket, delete_dialog_open: false, delete_busy: false)}
  end

  def handle_event("submit_delete_post", _params, socket) do
    post = socket.assigns.post
    user = socket.assigns.current_user
    socket = assign(socket, delete_busy: true)

    cond do
      is_nil(post) ->
        {:noreply, assign(socket, delete_dialog_open: false, delete_busy: false)}

      user && post.user && user.id == post.user.id ->
        finish_delete(socket, Discussions.delete_post(post.id, user.id), post)

      socket.assigns.can_moderate_discussions ->
        finish_delete(socket, Discussions.admin_delete_post(post.id), post)

      true ->
        {:noreply,
         assign(socket,
           delete_busy: false,
           delete_dialog_open: false,
           action_error: "You don't have permission to delete this post."
         )}
    end
  end

  # ────────────── Report ──────────────

  def handle_event("report_post", _params, socket) do
    if socket.assigns.current_user do
      {:noreply,
       assign(socket,
         report_dialog_open: true,
         report_error: nil,
         report_success: false
       )}
    else
      {:noreply, assign(socket, action_error: "Sign in to report.")}
    end
  end

  def handle_event("cancel_report_post", _params, socket) do
    {:noreply,
     assign(socket, report_dialog_open: false, report_error: nil, report_success: false)}
  end

  def handle_event("submit_report_post", params, socket) do
    with %{id: reporter_id} <- socket.assigns.current_user,
         post when is_map(post) <- socket.assigns.post,
         {:ok, _report} <-
           Reports.create_report(%{
             reporter_id: reporter_id,
             entity_type: "post",
             entity_id: post.id,
             entity_name: post.title || "Post",
             category: params["category"],
             reason: trimmed(params["reason"]),
             message: trimmed(params["message"])
           }) do
      {:noreply, assign(socket, report_error: nil, report_success: true)}
    else
      nil -> {:noreply, assign(socket, report_error: "Sign in to report.")}
      {:error, _} -> {:noreply, assign(socket, report_error: "Could not submit this report.")}
    end
  end

  # ────────────── Helpers ──────────────

  defp moderate_post(socket, mutation_fun, success_toast) do
    if socket.assigns.can_moderate_discussions do
      post = socket.assigns.post

      with {:ok, _} <- mutation_fun.(post.id),
           {:ok, payload} <- Data.load_post_page(post.short_id, socket.assigns.current_user) do
        socket = assign(socket, post: payload.post, action_error: nil)
        {:noreply, maybe_push_toast(socket, success_toast)}
      else
        {:error, reason} ->
          {:noreply,
           socket
           |> push_toast(:error, error_message(reason))
           |> assign(action_error: nil)}
      end
    else
      {:noreply, push_toast(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp maybe_push_toast(socket, nil), do: socket
  defp maybe_push_toast(socket, message), do: push_toast(socket, :success, message)

  defp push_toast(socket, variant, message) do
    push_event(socket, "toast", %{variant: Atom.to_string(variant), message: message})
  end

  defp finish_delete(socket, result, post) do
    case result do
      {:ok, _} ->
        # Bounce back to the entity / category list; the post no longer
        # has a viewable detail page.
        {:noreply,
         socket
         |> assign(delete_dialog_open: false, delete_busy: false)
         |> push_toast(:success, "Post deleted")
         |> push_navigate(to: fallback_href(post))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(delete_busy: false, delete_dialog_open: false)
         |> push_toast(:error, error_message(reason))}
    end
  end

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_), do: ""

  defp changeset_error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> case do
      "" -> "Couldn't save the post."
      msg -> msg
    end
  end

  defp error_message(:locked), do: "This post is locked."
  defp error_message(:not_found), do: "Post not found."
  defp error_message(:forbidden), do: "You don't have permission to do that."
  defp error_message(:title_locked), do: "Title can't be changed after a post has replies."

  defp error_message({:error, :pinned_thread_limit_reached}),
    do: "All pin slots used (max 6)."

  defp error_message(:pinned_thread_limit_reached), do: "All pin slots used (max 6)."
  defp error_message(%Ecto.Changeset{} = cs), do: changeset_error_message(cs)
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(_other), do: "Action failed. Try again."

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <div
        :if={@load_error?}
        class="text-foreground-secondary mx-auto mt-8 max-w-3xl px-4 text-sm lg:px-0"
      >
        Discussion could not be loaded. Please try again.
      </div>

      <NotFoundPage.not_found_page :if={@not_found?} variant={:overlay} />

      <div
        :if={!@load_error? && !@not_found? && @post}
        class="mx-auto mt-6 max-w-3xl px-4 pb-20 lg:mt-10 lg:px-0"
      >
        <div class="space-y-10">
          <.link
            navigate={fallback_href(@post)}
            class="hover:text-foreground-primary text-foreground-secondary inline-flex items-center gap-1.5 text-sm transition-colors"
          >
            <Lucide.arrow_left class="size-3.5" aria-hidden /> Back
          </.link>

          <%= cond do %>
            <% @post.deleted_at -> %>
              <div class="border-border-divider rounded-xl border px-6 py-10 text-center">
                <p class="text-foreground-tertiary text-sm italic">
                  {deleted_message(@post)}
                </p>
              </div>
            <% hidden_tombstone?(@post) -> %>
              <article class="border-border-divider border-b pb-5">
                <div class="mb-4 space-y-2">
                  <.locked_notice :if={@post.is_locked} />
                  <.removal_notice />
                </div>

                <h1 class="text-foreground-primary text-xl/tight font-semibold lg:text-2xl">
                  {@post.title || "[ Removed by moderator ]"}
                </h1>
              </article>
              <.comments_section
                post={@post}
                current_user={@current_user}
                comments_page={@comments_page}
                focus_comment_id={@focus_comment_id}
              />
            <% true -> %>
              <.post_header
                post={@post}
                current_user={@current_user}
                can_moderate_discussions={@can_moderate_discussions}
              />
              <.comments_section
                post={@post}
                current_user={@current_user}
                comments_page={@comments_page}
                focus_comment_id={@focus_comment_id}
              />
          <% end %>
        </div>
      </div>

      <.edit_post_dialog
        :if={@post}
        open={@edit_dialog_open}
        post={@post}
        form={@edit_form}
        busy={@edit_busy}
        error_message={@edit_error}
        title_locked={(@post.comments_count || 0) > 0}
      />

      <.removal_reason_dialog
        open={@hide_dialog_open}
        item_label="post"
        busy={@hide_busy}
        allow_lock_thread={@post && !@post.is_locked}
      />

      <.post_delete_dialog
        :if={@post && @delete_dialog_open}
        post={@post}
        busy={@delete_busy}
      />

      <.post_report_dialog
        :if={@post && @report_dialog_open}
        post={@post}
        error={@report_error}
        success={@report_success}
      />

      <div
        :if={@action_error}
        role="alert"
        class="fixed bottom-4 left-1/2 z-180 -translate-x-1/2 rounded-md border border-red-500/30 bg-red-500/15 px-4 py-2 text-sm text-red-200"
      >
        {@action_error}
      </div>
    </main>
    """
  end

  attr :post, :map, required: true
  attr :busy, :boolean, default: false

  defp post_delete_dialog(assigns) do
    ~H"""
    <div
      id="delete-post-dialog"
      phx-hook="ModalDialog"
      data-cancel-event="cancel_delete_post"
      class="fixed inset-0 z-170 flex items-center justify-center bg-black/80 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-post-dialog-title"
        class="w-full max-w-[380px] rounded-[14px] bg-[#0A0A0A] p-6 shadow-[0_8px_40px_rgba(0,0,0,0.55)]"
      >
        <p
          id="delete-post-dialog-title"
          class="text-lg font-medium text-[rgb(var(--foreground-primary))]"
        >
          Delete Post?
        </p>
        <p class="mt-2 text-sm/5 text-[rgb(var(--foreground-tertiary))]">
          This will permanently delete this post and all its replies. This action cannot be undone.
        </p>
        <div class="mt-5 flex justify-end gap-2.5">
          <button
            type="button"
            phx-click="cancel_delete_post"
            data-modal-cancel
            data-modal-initial-focus
            class="h-9 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 text-[13px] font-normal text-[rgb(var(--foreground-secondary))] transition hover:bg-white/8"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="submit_delete_post"
            disabled={@busy}
            class="h-9 min-w-16 rounded-[8px] bg-[rgb(var(--button-background-destructive-default))] px-4 text-[13px] font-medium text-white transition hover:bg-[rgb(var(--button-background-destructive-hover))] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {if @busy, do: "Deleting...", else: "Delete"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :error, :string, default: nil
  attr :success, :boolean, default: false

  defp post_report_dialog(assigns) do
    ~H"""
    <div
      id="report-post-dialog"
      phx-hook="ModalDialog"
      data-cancel-event="cancel_report_post"
      class="fixed inset-0 z-170 flex items-center justify-center bg-black/80 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="report-post-dialog-title"
        class="w-full max-w-[480px] rounded-[16px] bg-[rgb(var(--surface-base))] px-5 pt-8 pb-6 shadow-[0_8px_40px_rgba(0,0,0,0.55)] sm:px-10"
      >
        <p
          id="report-post-dialog-title"
          class="text-xl font-semibold text-[rgb(var(--foreground-primary))] sm:text-2xl"
        >
          Report Post
        </p>
        <p class="mt-4 text-base leading-[26px] text-[rgb(var(--foreground-secondary))]">
          Does this post break our guidelines? Let us know so we can take a closer look.
        </p>

        <%= if @success do %>
          <p class="mt-4 text-sm text-green-400">Report submitted successfully.</p>
          <div class="mt-5 flex justify-end">
            <button
              type="button"
              phx-click="cancel_report_post"
              data-modal-cancel
              data-modal-initial-focus
              class="rounded-[8px] bg-[rgb(var(--surface-elevated))] px-[26px] py-3.5 text-sm text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
            >
              Close
            </button>
          </div>
        <% else %>
          <form
            id="report-post-form"
            phx-submit="submit_report_post"
            phx-hook="ReportForm"
            class="mt-4 flex flex-col gap-4"
          >
            <div class="flex flex-col gap-1.5">
              <label for="report-post-category" class="text-xs text-[rgb(var(--foreground-primary))]">
                Category
              </label>
              <select
                id="report-post-category"
                name="category"
                required
                data-modal-initial-focus
                class="w-full cursor-pointer rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-2.5 text-sm text-[rgb(var(--foreground-primary))] outline-none"
              >
                <option value="">Select a category</option>
                <option :for={{value, label} <- report_categories()} value={value}>{label}</option>
              </select>
            </div>

            <div class="flex flex-col gap-1.5">
              <label for="report-post-reason" class="text-xs text-[rgb(var(--foreground-primary))]">
                Why are you reporting this post?
              </label>
              <input
                id="report-post-reason"
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
              <label for="report-post-message" class="text-xs text-[rgb(var(--foreground-primary))]">
                Additional details (optional)
              </label>
              <textarea
                id="report-post-message"
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
                phx-click="cancel_report_post"
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

  attr :post, :map, required: true
  attr :current_user, :map, default: nil
  attr :can_moderate_discussions, :boolean, default: false

  defp post_header(assigns) do
    ~H"""
    <article class="border-border-divider border-b pb-5">
      <div :if={@post.is_locked || @post.hidden_at} class="mb-4 space-y-2">
        <.locked_notice :if={@post.is_locked} />
        <.removal_notice
          :if={@post.hidden_at}
          message="This post has been removed by the moderators."
        />
      </div>

      <div class="flex items-start justify-between gap-3">
        <div class="flex min-w-0 items-center gap-3">
          <.author_avatar user={@post.user} />
          <div class="flex min-w-0 flex-col">
            <.link
              :if={@post.user}
              navigate={"/@#{@post.user.username}"}
              class="hover:text-foreground-tertiary text-foreground-primary truncate text-sm font-semibold transition-colors"
            >
              {@post.user.display_name}
            </.link>
            <span :if={!@post.user} class="text-foreground-tertiary text-sm font-semibold">
              Unknown
            </span>
            <time
              class="text-foreground-tertiary text-xs"
              datetime={datetime_attr(@post.inserted_at)}
              title={datetime_title(@post.inserted_at)}
            >
              {SharedTime.calendar_custom(@post.inserted_at)}
            </time>
          </div>
        </div>

        <span
          :if={@post.is_pinned}
          class="bg-button-background-brand-default/15 border-button-background-brand-default/30 text-button-background-brand-default inline-flex items-center gap-1 rounded-md border px-2 py-0.5 text-xs font-medium"
        >
          <Lucide.pin class="size-3" aria-hidden /> Pinned
        </span>
      </div>

      <.link
        :if={@post.entity_tag}
        navigate={@post.entity_tag.href}
        class="hover:text-foreground-primary text-foreground-secondary mt-3 inline-flex max-w-full rounded-md bg-white/6 px-2 py-0.5 text-xs font-medium transition-colors hover:bg-white/10"
      >
        {@post.entity_tag.label}
      </.link>

      <h1 class="text-foreground-primary mt-4 text-xl/tight font-semibold lg:text-2xl">
        {@post.title}
      </h1>

      <div
        :if={@post.content}
        class="kaguya-markdown text-foreground-primary mt-4 text-sm/6 md:text-base md:leading-[26px]"
      >
        {UserContent.to_html(@post.content)}
      </div>

      <span :if={@post.is_edited} class="text-foreground-tertiary mt-1 inline-block text-xs">
        (edited)
      </span>

      <div class="mt-4 flex items-center gap-2">
        <button
          type="button"
          phx-click="toggle_post_like"
          aria-pressed={@post.liked_by_me}
          class="hover:text-foreground-primary text-foreground-secondary inline-flex h-9 items-center gap-1.5 rounded-full px-2 text-sm transition hover:bg-white/4"
        >
          <Lucide.heart
            class={[
              "size-4",
              @post.liked_by_me && "fill-current text-[rgb(var(--like-heart))]"
            ]}
            aria-hidden
          />
          <span
            :if={@post.likes_count > 0}
            class={@post.liked_by_me && "text-[rgb(var(--like-heart))]"}
          >
            {format_count(@post.likes_count)}
          </span>
        </button>

        <.post_actions_menu
          post={@post}
          current_user={@current_user}
          can_moderate_discussions={@can_moderate_discussions}
        />
      </div>
    </article>
    """
  end

  attr :post, :map, required: true
  attr :current_user, :map, default: nil
  attr :comments_page, :integer, default: 1
  attr :focus_comment_id, :string, default: nil

  defp comments_section(assigns) do
    ~H"""
    <section id="comments">
      <.live_component
        module={CommentsComponent}
        id="discussion-comments"
        adapter={DiscussionAdapter}
        resource_id={@post.id}
        current_user={@current_user}
        page={@comments_page}
        page_size={20}
        base_path={comments_base_path(@post, @focus_comment_id)}
        focus_comment_id={@focus_comment_id}
        full_discussion_path={@post.url}
        locked={@post.is_locked || !!@post.deleted_at || hidden_tombstone?(@post)}
        class="px-0"
      />
    </section>
    """
  end

  attr :user, :map, default: nil

  defp author_avatar(%{user: %{username: username}} = assigns) when is_binary(username) do
    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@user}
      size="size-8"
      sizes="32px"
      fallback={:initials}
      link
    />
    """
  end

  defp author_avatar(assigns) do
    ~H"""
    <div class="size-8 shrink-0 rounded-full bg-white/6" />
    """
  end

  defp toggle_post_like(true, post_id, user_id), do: Discussions.unlike_post(post_id, user_id)
  defp toggle_post_like(false, post_id, user_id), do: Discussions.like_post(post_id, user_id)

  defp apply_local_post_like(post, liked?) do
    delta = if liked?, do: 1, else: -1
    %{post | liked_by_me: liked?, likes_count: max((post.likes_count || 0) + delta, 0)}
  end

  defp meta_description(%{content: content}) when is_binary(content) and content != "",
    do: content |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)

  defp meta_description(_post), do: "Discussion on Kaguya"

  defp page_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page_param(_value), do: 1

  # Used by the comments pagination only. Focused-mode loads cap pagination
  # at a single page (no Next/Prev), so we always anchor pagination back to
  # the full discussion path.
  defp comments_base_path(post, _focus_comment_id), do: post.url <> "#comments"

  defp fallback_href(%{entity_tag: %{href: href}}), do: href
  defp fallback_href(%{category: %{slug: slug}}), do: "/discussions/#{slug}"
  defp fallback_href(_post), do: "/discussions"

  defp hidden_tombstone?(%{hidden_at: hidden_at, content: content}),
    do: not is_nil(hidden_at) and is_nil(content)

  defp deleted_message(%{deleted_by_type: :admin}),
    do: "This post has been removed by a moderator."

  defp deleted_message(%{deleted_by_type: "admin"}),
    do: "This post has been removed by a moderator."

  defp deleted_message(_post), do: "This post has been deleted by its author."

  defp format_count(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 1)}m"
  defp format_count(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 1)}k"
  defp format_count(value), do: to_string(value || 0)

  defp datetime_attr(nil), do: nil
  defp datetime_attr(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp datetime_attr(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp datetime_title(value), do: SharedTime.format_datetime_tooltip(value)
end
