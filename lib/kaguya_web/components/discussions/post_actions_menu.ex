defmodule KaguyaWeb.Components.Discussions.PostActionsMenu do
  @moduledoc """
  Post-level "..." actions dropdown for the discussion show page: owner
  Edit + Delete, moderator Pin/Lock/Hide, non-owner Report, and an admin
  Delete for mods on other people's posts.

  All actions are emitted as phx-click events to the parent LiveView
  (`KaguyaWeb.DiscussionLive.Show`); this component just decides which
  buttons to render and what shape the menu takes.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu

  @doc """
  Returns nil when the viewer has no actions available — keeps the action
  bar clean for logged-out viewers and for non-owner, non-mod users.
  """
  attr :post, :map, required: true
  attr :current_user, :map, default: nil
  attr :can_moderate_discussions, :boolean, default: false

  def post_actions_menu(assigns) do
    assigns =
      assigns
      |> assign(:is_mine, owner?(assigns.current_user, assigns.post))
      |> assign(:is_hidden, not is_nil(assigns.post.hidden_at))

    assigns =
      assigns
      |> assign(:owner_can_modify, assigns.post.can_modify && assigns.is_mine)
      |> assign(
        :can_admin_delete,
        assigns.can_moderate_discussions && not assigns.is_mine
      )
      |> assign(
        :can_report,
        not assigns.is_mine && not assigns.can_moderate_discussions && !!assigns.current_user
      )

    assigns =
      assign(
        assigns,
        :has_any_action,
        assigns.owner_can_modify || assigns.can_admin_delete || assigns.can_report ||
          assigns.can_moderate_discussions
      )

    ~H"""
    <.menu
      :if={@has_any_action}
      id={"post-#{@post.id}-actions"}
      align="end"
      class="group flex size-8 cursor-pointer items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] hover:bg-white/4 hover:text-[#9BC5FF]"
    >
      <:trigger aria-label="Post actions">
        <Lucide.ellipsis class="size-4" aria-hidden />
        <span class="sr-only">Post actions</span>
      </:trigger>
      <div class="w-[140px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 shadow-[0_5px_15px_rgba(0,5,15,0.35)]">
        <.menu_item
          :if={@owner_can_modify}
          event="start_edit_post"
          class={menu_item_class()}
        >
          <Lucide.pencil class="size-4 shrink-0" aria-hidden /> Edit
        </.menu_item>

        <.menu_item
          :if={@can_moderate_discussions}
          event="toggle_pin_post"
          class={menu_item_class()}
        >
          <%= if @post.is_pinned do %>
            <Lucide.pin_off class="size-4 shrink-0" aria-hidden /> Unpin
          <% else %>
            <Lucide.pin class="size-4 shrink-0" aria-hidden /> Pin
          <% end %>
        </.menu_item>

        <.menu_item
          :if={@can_moderate_discussions}
          event="toggle_lock_post"
          class={menu_item_class()}
        >
          <%= if @post.is_locked do %>
            <Lucide.lock_open class="size-4 shrink-0" aria-hidden /> Unlock
          <% else %>
            <Lucide.lock class="size-4 shrink-0" aria-hidden /> Lock
          <% end %>
        </.menu_item>

        <.menu_item
          :if={@can_moderate_discussions && @is_hidden}
          event="unhide_post"
          class={menu_item_class()}
        >
          <Lucide.eye class="size-4 shrink-0" aria-hidden /> Unhide
        </.menu_item>

        <.menu_item
          :if={@can_moderate_discussions && !@is_hidden}
          event="start_hide_post"
          class={menu_item_class()}
        >
          <Lucide.eye_off class="size-4 shrink-0" aria-hidden /> Hide
        </.menu_item>

        <.menu_item
          :if={@can_report}
          event="report_post"
          class={menu_item_class()}
        >
          <Lucide.flag class="size-4 shrink-0" aria-hidden /> Report
        </.menu_item>

        <.menu_item
          :if={@owner_can_modify || @can_admin_delete}
          event="confirm_delete_post"
          class={menu_item_class("text-[#f94441]")}
        >
          <Lucide.trash_2 class="size-4 shrink-0" aria-hidden /> Delete
        </.menu_item>
      </div>
    </.menu>
    """
  end

  defp menu_item_class do
    "flex h-full w-full cursor-pointer items-center justify-start gap-[9px] rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-3.5 pr-[37px] pl-3.5 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
  end

  defp menu_item_class(extra_class), do: menu_item_class() <> " " <> extra_class

  defp owner?(%{id: user_id}, %{user: %{id: user_id}}) when is_binary(user_id), do: true
  defp owner?(_user, _post), do: false
end
