defmodule KaguyaWeb.CommentsComponent do
  @moduledoc """
  Reusable LiveComponent for resource comments.

  The parent LiveView only needs to pass an adapter, resource id, and current
  user. Parent pages can integrate this without owning any
  comment event handlers.
  """

  use KaguyaWeb, :live_component

  alias KaguyaWeb.Comments.ListAdapter
  alias KaguyaWeb.Comments.Tree
  alias KaguyaWeb.Components.Comments, as: CommentUI
  alias KaguyaWeb.SharedComponents.Pagination, as: SharedPagination
  alias Kaguya.Reports

  @default_page_size 10

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign_new(:adapter, fn -> ListAdapter end)
      |> assign_new(:resource_id, fn -> nil end)
      |> assign_new(:current_user, fn -> nil end)
      |> assign_new(:page, fn -> 1 end)
      |> assign_new(:page_size, fn -> @default_page_size end)
      |> assign_new(:base_path, fn -> nil end)
      |> assign_new(:page_param, fn -> "page" end)
      |> assign_new(:focus_comment_id, fn -> nil end)
      |> assign_new(:focused_comment_id, fn -> nil end)
      |> assign_new(:focused_replies_truncated, fn -> false end)
      |> assign_new(:full_discussion_path, fn -> nil end)
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:locked, fn -> false end)
      |> assign_new(:active_reply_id, fn -> nil end)
      |> assign_new(:editing_id, fn -> nil end)
      |> assign_new(:collapsed_ids, fn -> MapSet.new() end)
      |> assign_new(:show_all_ids, fn -> MapSet.new() end)
      |> assign_new(:top_composer_expanded, fn -> false end)
      |> assign_new(:pending_delete_id, fn -> nil end)
      |> assign_new(:pending_report_id, fn -> nil end)
      |> assign_new(:report_error, fn -> nil end)
      |> assign_new(:report_success, fn -> false end)
      |> assign_new(:error_message, fn -> nil end)
      |> assign_new(:hide_header, fn -> false end)
      |> assign(assigns)

    {:ok, load_comments(socket)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :focused_mode, focused_mode?(assigns.focus_comment_id))

    ~H"""
    <div id={@id} class={["review-comments px-4 md:px-8 lg:px-0", @class]}>
      <%!--
        `hide_header={true}` lets the parent (e.g. ReviewLive.Show) render
        its own count heading + separator outside this component, since
        each context wants slightly different placement/typography.
      --%>
      <CommentUI.header_and_composer
        :if={!@hide_header}
        comments_count={@comments_count}
        can_comment={!@focused_mode && !@locked && (@can_comment || is_nil(@current_user))}
        current_user={@current_user}
        target={@myself}
        expanded={@top_composer_expanded}
        show_disabled_composer={!@focused_mode && !@locked}
      />
      <CommentUI.reply_input
        :if={
          @hide_header and !@focused_mode and not @locked and (@can_comment or is_nil(@current_user))
        }
        id={"#{@id}-top-form"}
        target={@myself}
        submit_event="create_comment"
        cancel_event="cancel_composer"
        expand_event="expand_composer"
        current_user={@current_user}
        button_text="Comment"
        placeholder="Add a comment..."
        expanded={@top_composer_expanded}
      />

      <CommentUI.delete_confirm_dialog comment_id={@pending_delete_id} target={@myself} />
      <CommentUI.report_dialog
        comment_id={@pending_report_id}
        target={@myself}
        error={@report_error}
        success={@report_success}
      />

      <p :if={@error_message} class="mt-3 text-sm text-[rgb(255_99_99)]">
        {@error_message}
      </p>

      <div
        :if={@focused_comment_id && @full_discussion_path}
        id="focused-comment-notice"
        class="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-[rgb(var(--border-divider))] bg-white/3 px-4 py-3 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        <span>
          Showing a shared comment and its replies{if @focused_replies_truncated,
            do: " (limited)",
            else: ""}.
        </span>
        <.link
          patch={@full_discussion_path <> "#comments"}
          class="font-medium text-[rgb(var(--foreground-primary))] transition hover:text-[rgb(var(--foreground-secondary))]"
        >
          View full discussion
        </.link>
      </div>

      <div
        :if={@focused_mode && is_nil(@focused_comment_id) && @full_discussion_path && @error_message}
        id="focused-comment-recovery"
        class="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-[rgb(var(--border-divider))] bg-white/3 px-4 py-3 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        <span>This shared comment could not be loaded.</span>
        <.link
          patch={@full_discussion_path <> "#comments"}
          class="font-medium text-[rgb(var(--foreground-primary))] transition hover:text-[rgb(var(--foreground-secondary))]"
        >
          View full discussion
        </.link>
      </div>

      <div class={["comments-list space-y-5", if(@locked, do: "mt-0", else: "mt-5 sm:mt-[26px]")]}>
        <CommentUI.thread
          :for={node <- @tree}
          node={node}
          target={@myself}
          current_user={@current_user}
          active_reply_id={@active_reply_id}
          editing_id={@editing_id}
          collapsed_ids={@collapsed_ids}
          show_all_ids={@show_all_ids}
          can_moderate={@can_moderate}
          locked={@locked}
        />

        <SharedPagination.pagination
          :if={@pagination.total_pages > 1 && @base_path}
          total_pages={@pagination.total_pages}
          current_page={@pagination.page}
          base_path={@base_path}
          page_param={@page_param}
          aria_label="Comments pagination"
          class="pt-2"
        />

        <nav
          :if={@pagination.total_pages > 1 && is_nil(@base_path)}
          class="flex items-center justify-center gap-2 pt-2"
          aria-label="Comments pagination"
        >
          <button
            type="button"
            phx-click="load_page"
            phx-value-page={max(@pagination.page - 1, 1)}
            phx-target={@myself}
            disabled={@pagination.page <= 1}
            class="rounded-[6px] px-3 py-1.5 text-xs font-medium text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))] disabled:cursor-not-allowed disabled:opacity-40"
          >
            Previous
          </button>
          <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
            Page {@pagination.page} of {@pagination.total_pages}
          </span>
          <button
            type="button"
            phx-click="load_page"
            phx-value-page={min(@pagination.page + 1, @pagination.total_pages)}
            phx-target={@myself}
            disabled={@pagination.page >= @pagination.total_pages}
            class="rounded-[6px] px-3 py-1.5 text-xs font-medium text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))] disabled:cursor-not-allowed disabled:opacity-40"
          >
            Next
          </button>
        </nav>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("expand_composer", _params, socket) do
    {:noreply, assign(socket, top_composer_expanded: true)}
  end

  def handle_event("cancel_composer", _params, socket) do
    {:noreply, assign(socket, top_composer_expanded: false, error_message: nil)}
  end

  def handle_event("start_reply", %{"id" => id}, socket) do
    cond do
      is_nil(socket.assigns.current_user) ->
        {:noreply, assign(socket, error_message: "Sign in to reply.")}

      hidden_comment?(socket.assigns.comments, id) ->
        {:noreply,
         assign(socket, active_reply_id: nil, error_message: "Cannot reply to a hidden comment.")}

      true ->
        {:noreply, assign(socket, active_reply_id: id, editing_id: nil, error_message: nil)}
    end
  end

  def handle_event("cancel_reply", _params, socket) do
    {:noreply, assign(socket, active_reply_id: nil, error_message: nil)}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id, active_reply_id: nil, error_message: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, error_message: nil)}
  end

  def handle_event("toggle_thread", %{"id" => id}, socket) do
    collapsed_ids =
      if MapSet.member?(socket.assigns.collapsed_ids, id) do
        MapSet.delete(socket.assigns.collapsed_ids, id)
      else
        MapSet.put(socket.assigns.collapsed_ids, id)
      end

    {:noreply, assign(socket, collapsed_ids: collapsed_ids)}
  end

  def handle_event("show_all_replies", %{"id" => id}, socket) do
    {:noreply, assign(socket, show_all_ids: MapSet.put(socket.assigns.show_all_ids, id))}
  end

  def handle_event("load_page", %{"page" => page}, socket) do
    socket =
      socket
      |> assign(page: int(page, socket.assigns.page), active_reply_id: nil, editing_id: nil)
      |> load_comments()

    {:noreply, socket}
  end

  def handle_event("create_comment", params, socket) do
    content = trimmed(params["content"])
    editor_id = params["_editor_id"]
    attrs = %{content: content, parent_comment_id: params["parent_comment_id"]}

    case socket.assigns.adapter.create(
           socket.assigns.resource_id,
           socket.assigns.current_user,
           attrs
         ) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> assign(active_reply_id: nil, top_composer_expanded: false, error_message: nil)
         |> load_comments()
         |> clear_editor(editor_id)}

      {:error, reason} ->
        # Leave the textarea content alone so the user can edit + retry without
        # losing what they typed; the error message renders above the composer.
        {:noreply, assign(socket, error_message: error_message(reason))}
    end
  end

  def handle_event("update_comment", params, socket) do
    editor_id = params["_editor_id"]

    with id when is_binary(id) <- socket.assigns.editing_id,
         {:ok, _comment} <-
           socket.assigns.adapter.update(id, socket.assigns.current_user, %{
             content: trimmed(params["content"])
           }) do
      {:noreply,
       socket
       |> assign(editing_id: nil, error_message: nil)
       |> load_comments()
       |> clear_editor(editor_id)}
    else
      _ -> {:noreply, assign(socket, error_message: "Couldn't save changes. Try again.")}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    case socket.assigns.adapter.delete(id, socket.assigns.current_user) do
      {:ok, true} ->
        {:noreply,
         socket |> assign(error_message: nil, pending_delete_id: nil) |> load_comments()}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: error_message(reason))}
    end
  end

  def handle_event("confirm_delete_comment", %{"id" => id}, socket) do
    {:noreply, assign(socket, pending_delete_id: id, error_message: nil)}
  end

  def handle_event("cancel_delete_comment", _params, socket) do
    {:noreply, assign(socket, pending_delete_id: nil)}
  end

  def handle_event("delete_pending_comment", _params, socket) do
    case socket.assigns.pending_delete_id do
      id when is_binary(id) -> handle_event("delete_comment", %{"id" => id}, socket)
      _id -> {:noreply, socket}
    end
  end

  def handle_event("open_report_comment", %{"id" => id}, socket) do
    if socket.assigns.current_user do
      {:noreply,
       assign(socket,
         pending_report_id: id,
         report_error: nil,
         report_success: false,
         error_message: nil
       )}
    else
      {:noreply, assign(socket, error_message: "Sign in to report.")}
    end
  end

  def handle_event("cancel_report_comment", _params, socket) do
    {:noreply, assign(socket, pending_report_id: nil, report_error: nil, report_success: false)}
  end

  def handle_event("submit_report_comment", params, socket) do
    id = socket.assigns.pending_report_id

    with %{id: reporter_id} = user <- socket.assigns.current_user,
         true <- can_submit_report?(user),
         comment when is_map(comment) <- find_comment(socket.assigns.comments, id),
         {:ok, _report} <-
           Reports.create_report(%{
             reporter_id: reporter_id,
             entity_type: report_entity_type(socket.assigns.adapter),
             entity_id: id,
             entity_name: display_name(comment.user),
             category: params["category"],
             reason: trimmed(params["reason"]),
             message: trimmed(params["message"])
           }) do
      {:noreply, assign(socket, report_error: nil, report_success: true)}
    else
      nil ->
        {:noreply, assign(socket, report_error: "Sign in to report.")}

      false ->
        {:noreply, assign(socket, report_error: "Your reporting privileges have been revoked.")}

      _ ->
        {:noreply, assign(socket, report_error: "Could not submit this report.")}
    end
  end

  def handle_event("toggle_like", %{"id" => id, "liked" => liked}, socket) do
    was_liked? = liked == "true"
    next_liked? = not was_liked?
    optimistic = apply_local_like(socket, id, next_liked?)

    result =
      if was_liked? do
        socket.assigns.adapter.unlike(id, socket.assigns.current_user)
      else
        socket.assigns.adapter.like(id, socket.assigns.current_user)
      end

    case result do
      {:ok, true} ->
        {:noreply, optimistic}

      {:error, reason} ->
        {:noreply,
         socket
         |> apply_local_like(id, was_liked?)
         |> assign(error_message: error_message(reason))}
    end
  end

  def handle_event("hide_comment", %{"id" => id}, socket) do
    case socket.assigns.adapter.hide(id, socket.assigns.current_user, %{}) do
      {:ok, _count} -> {:noreply, socket |> assign(error_message: nil) |> load_comments()}
      {:error, reason} -> {:noreply, assign(socket, error_message: error_message(reason))}
    end
  end

  def handle_event("unhide_comment", %{"id" => id}, socket) do
    case socket.assigns.adapter.unhide(id, socket.assigns.current_user) do
      {:ok, _count} -> {:noreply, socket |> assign(error_message: nil) |> load_comments()}
      {:error, reason} -> {:noreply, assign(socket, error_message: error_message(reason))}
    end
  end

  def handle_event("pin_comment", %{"id" => id}, socket) do
    pin_or_unpin(socket, id, :pin, "Comment pinned")
  end

  def handle_event("unpin_comment", %{"id" => id}, socket) do
    pin_or_unpin(socket, id, :unpin, "Comment unpinned")
  end

  defp pin_or_unpin(socket, id, action, success_toast) do
    adapter = socket.assigns.adapter

    if function_exported?(adapter, action, 2) do
      case apply(adapter, action, [id, socket.assigns.current_user]) do
        {:ok, _} ->
          socket =
            socket
            |> assign(error_message: nil)
            |> load_comments()
            |> push_event("toast", %{variant: "success", message: success_toast})

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, error_message: error_message(reason))}
      end
    else
      {:noreply, assign(socket, error_message: "This comment type doesn't support pinning.")}
    end
  end

  defp load_comments(%{assigns: %{resource_id: nil}} = socket) do
    assign(socket,
      comments: [],
      tree: [],
      comments_count: 0,
      error_message: nil,
      pagination: empty_pagination(socket.assigns.page, socket.assigns.page_size)
    )
  end

  defp load_comments(socket) do
    adapter = socket.assigns.adapter

    case adapter.load(socket.assigns.resource_id, socket.assigns.current_user, %{
           page: socket.assigns.page,
           page_size: socket.assigns.page_size,
           focus_comment_id: socket.assigns.focus_comment_id
         }) do
      {:ok, %{items: comments, pagination: pagination, comments_count: comments_count} = result} ->
        assign(socket,
          comments: comments,
          tree: Tree.build(comments),
          pagination: pagination,
          comments_count: comments_count,
          error_message: nil,
          focused_comment_id: Map.get(result, :focused_comment_id),
          focused_replies_truncated: Map.get(pagination, :truncated?, false),
          can_comment:
            adapter.can_comment?(socket.assigns.resource_id, socket.assigns.current_user),
          can_moderate: adapter.can_moderate?(socket.assigns.current_user)
        )

      {:error, reason} ->
        assign(socket,
          comments: [],
          tree: [],
          pagination: empty_pagination(socket.assigns.page, socket.assigns.page_size),
          comments_count: 0,
          focused_comment_id: nil,
          focused_replies_truncated: false,
          can_comment: false,
          can_moderate: false,
          error_message: error_message(reason)
        )
    end
  end

  defp empty_pagination(page, page_size),
    do: %{page: page, page_size: page_size, total_pages: 1, total_count: 0}

  defp apply_local_like(socket, id, liked?) do
    comments =
      Enum.map(socket.assigns.comments, fn comment ->
        if comment.id == id do
          delta = if liked?, do: 1, else: -1
          new_count = max((comment.likes_count || 0) + delta, 0)
          %{comment | liked_by_me: liked?, likes_count: new_count}
        else
          comment
        end
      end)

    assign(socket, comments: comments, tree: Tree.build(comments), error_message: nil)
  end

  # Targeted reset for the markdown composer that just submitted. The form id
  # rides along on submit (`_editor_id` hidden input added by
  # `<.markdown_editor>`) so we can address the right hook instance — top
  # composer, edit form, or reply form — without coordinating ids elsewhere.
  defp clear_editor(socket, editor_id) when is_binary(editor_id) and editor_id != "" do
    push_event(socket, "kaguya:markdown-editor-set", %{id: editor_id, content: ""})
  end

  defp clear_editor(socket, _editor_id), do: socket

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_value), do: ""

  defp find_comment(comments, id), do: Enum.find(comments, &(Map.get(&1, :id) == id))

  defp hidden_comment?(comments, id) do
    case find_comment(comments, id) do
      %{hidden_at: hidden_at} -> not is_nil(hidden_at)
      _ -> false
    end
  end

  defp focused_mode?(value) when is_binary(value), do: String.trim(value) != ""
  defp focused_mode?(_value), do: false

  defp report_entity_type(adapter) do
    case adapter.resource_type() do
      :vn_list_comment -> "list_comment"
      :list_comment -> "list_comment"
      :vn_review_comment -> "review_comment"
      :review_comment -> "review_comment"
      other -> to_string(other)
    end
  end

  defp can_submit_report?(%{can_discuss: false, can_review: false, can_list: false}), do: false
  defp can_submit_report?(_user), do: true

  defp display_name(%{display_name: name, username: username}) do
    if is_binary(name) and String.trim(name) != "", do: name, else: username
  end

  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_user), do: "Comment"

  defp int(value, _default) when is_integer(value) and value > 0, do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> case do
      "" -> "Comment action failed."
      message -> message
    end
  end

  defp error_message(:unauthenticated), do: "Sign in to continue."
  defp error_message(:forbidden), do: "You don't have permission to do that."
  defp error_message(:not_found), do: "Comment not found."
  defp error_message(message) when is_binary(message), do: message
  defp error_message(_reason), do: "Comment action failed."
end
