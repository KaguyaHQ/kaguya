defmodule KaguyaWeb.Components.Profile.HeaderActionsMenu do
  @moduledoc """
  Profile header "Mod" pill + dropdown — mirrors `UserModPanel.tsx`.

  Renders nothing unless the viewer has at least one moderation action
  available against the target profile (not self, not logged-out, has the
  right permission flags). Click events (`mod_open_permissions`,
  `mod_open_suppress`, `mod_open_delete`) are owned by `ProfileLive.Show`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu
  import KaguyaWeb.Components.Profile.ModPanel, only: [manageable_fields: 1]

  attr :profile, :map, required: true
  attr :permissions, :map, default: %{any?: false}
  attr :mod_state, :map, default: %{}

  attr :variant, :atom,
    default: :mobile,
    values: [:mobile, :desktop],
    doc: "Trigger size — mobile uses a 33px pill, desktop a 26px pill."

  def actions_menu(assigns) do
    is_mine = assigns.profile.viewer && assigns.profile.viewer.is_mine

    {user_fields, mod_fields} = manageable_fields(assigns.permissions)
    can_manage_perms = user_fields ++ mod_fields != [] and not is_mine
    can_suppress = suppress_allowed?(assigns.permissions) and not is_mine
    is_admin = Map.get(assigns.permissions, :is_admin, false) and not is_mine

    has_any_action = can_manage_perms or can_suppress or is_admin
    ratings_suppressed = Map.get(assigns.mod_state, :ratings_suppressed, false)

    assigns =
      assigns
      |> assign(:can_manage_perms, can_manage_perms)
      |> assign(:can_suppress, can_suppress)
      |> assign(:is_admin, is_admin)
      |> assign(:has_any_action, has_any_action)
      |> assign(:ratings_suppressed, ratings_suppressed)

    ~H"""
    <.menu
      :if={@has_any_action}
      id={"profile-#{@profile.id}-mod-#{@variant}"}
      align="end"
      class={trigger_class(@variant)}
    >
      <:trigger aria-label="Moderation actions">
        <Lucide.shield class={trigger_icon_class(@variant)} aria-hidden /> Mod
      </:trigger>
      <div class="w-[200px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 shadow-[0_5px_15px_rgba(0,5,15,0.35)]">
        <.menu_item
          :if={@can_manage_perms}
          event="mod_open_permissions"
          class={menu_item_class()}
        >
          <Lucide.sliders_horizontal class="size-[15px] shrink-0" aria-hidden /> Manage Permissions
        </.menu_item>

        <.menu_item
          :if={@can_suppress}
          event="mod_open_suppress"
          class={menu_item_class()}
        >
          <%= if @ratings_suppressed do %>
            <Lucide.shield_off class="size-[15px] shrink-0" aria-hidden /> Restore Ratings
          <% else %>
            <Lucide.shield class="size-[15px] shrink-0" aria-hidden /> Suppress Ratings
          <% end %>
        </.menu_item>

        <.menu_item
          :if={@is_admin}
          event="mod_open_delete"
          class={menu_item_class("text-[#f94441]")}
        >
          <Lucide.trash_2 class="size-[15px] shrink-0" aria-hidden /> Delete User
        </.menu_item>
      </div>
    </.menu>
    """
  end

  # Pill — Shield + "Mod" text, sized to sit next to the Follow button.
  defp trigger_class(:mobile),
    do:
      "text-style-captionMedium inline-flex h-[33px] cursor-pointer items-center gap-1 rounded-[6px] border border-[rgb(var(--chip-border-default,var(--border-divider)))] bg-transparent px-3 text-[rgb(var(--foreground-secondary))] hover:border-[rgb(var(--chip-border-hover,var(--foreground-tertiary)))] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[rgb(var(--border-strong-divider,var(--border-divider)))]"

  defp trigger_class(:desktop),
    do:
      "text-style-captionMedium inline-flex h-[26px] cursor-pointer items-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default,var(--border-divider)))] bg-transparent px-2 text-[rgb(var(--foreground-secondary))] hover:border-[rgb(var(--chip-border-hover,var(--foreground-tertiary)))] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[rgb(var(--border-strong-divider,var(--border-divider)))]"

  defp trigger_icon_class(:mobile), do: "size-[13px]"
  defp trigger_icon_class(:desktop), do: "size-3"

  defp menu_item_class do
    "flex h-full w-full cursor-pointer items-center justify-start gap-2 rounded-none border-0 bg-[rgb(var(--surface-menu-item-default))] py-3.5 pl-3.5 pr-4 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
  end

  defp menu_item_class(extra_class), do: menu_item_class() <> " " <> extra_class

  defp suppress_allowed?(permissions) do
    Map.get(permissions, :is_admin, false) or
      Map.get(permissions, :can_moderate_reviews, false) or
      Map.get(permissions, :can_manage_users, false)
  end
end
