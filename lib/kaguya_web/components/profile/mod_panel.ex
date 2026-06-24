defmodule KaguyaWeb.Components.Profile.ModPanel do
  @moduledoc """
  Moderation dialogs that overlay the profile overview when a privileged
  viewer opens the mod panel.

  Mirrors `../personal/legacy-next-app/src/components/profile/UserModPanel.tsx`:

  - **Manage permissions** — toggle the user/discuss/review/list/mod flags
    via `Kaguya.Users.update_permissions/2`. Save is gated on a diff.
  - **Suppress / Restore Ratings** — confirm dialog routed through
    `Kaguya.Users.suppress_ratings/1` and `unsuppress_ratings/1`.
  - **Delete user** — admin-only destructive confirm. Calls
    `Kaguya.Users.delete_user/1` then navigates to `/`.

  This component is purely presentational — the LiveView owns the open/close
  state, the draft permissions assigns, and the `phx-click` mutation events.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Switch, only: [switch: 1]

  @user_permission_options [
    %{
      field: :can_edit,
      label: "Can edit database",
      description: "Create and edit VN, character, producer, release, tag, cover, and quote data."
    },
    %{
      field: :can_discuss,
      label: "Can discuss",
      description: "Create posts, comment, and like discussion content."
    },
    %{
      field: :can_review,
      label: "Can review",
      description: "Write reviews and interact with review comments."
    },
    %{
      field: :can_list,
      label: "Can create public lists",
      description: "Publish lists and interact with public list comments."
    }
  ]

  @mod_permission_options [
    %{field: :mod_db, label: "Database mod"},
    %{field: :mod_discussions, label: "Discussion mod"},
    %{field: :mod_reviews, label: "Review mod"},
    %{field: :mod_lists, label: "List mod"},
    %{field: :mod_users, label: "User mod"}
  ]

  def user_permission_options, do: @user_permission_options
  def mod_permission_options, do: @mod_permission_options

  @doc """
  Returns the user/mod permission options that the actor with the given
  `permissions` flag map is allowed to toggle.
  """
  def manageable_fields(permissions) do
    is_admin = Map.get(permissions, :is_admin, false)

    user_fields =
      Enum.filter(@user_permission_options, fn %{field: field} ->
        cond do
          is_admin or Map.get(permissions, :can_manage_users, false) -> true
          field == :can_edit -> Map.get(permissions, :can_moderate_db, false)
          field == :can_discuss -> Map.get(permissions, :can_moderate_discussions, false)
          field == :can_review -> Map.get(permissions, :can_moderate_reviews, false)
          field == :can_list -> Map.get(permissions, :can_moderate_lists, false)
          true -> false
        end
      end)

    mod_fields = if is_admin, do: @mod_permission_options, else: []

    {user_fields, mod_fields}
  end

  # ---------------------------------------------------------------------------
  # Permissions dialog
  # ---------------------------------------------------------------------------

  attr :open, :boolean, required: true
  attr :profile, :map, required: true
  attr :permissions, :map, required: true

  attr :draft, :map,
    required: true,
    doc: "Current draft state as %{field => boolean}."

  attr :saved, :map,
    required: true,
    doc: "Last persisted state — used to compute the dirty diff."

  attr :busy, :boolean, default: false

  def permissions_dialog(%{open: false} = assigns), do: ~H""

  def permissions_dialog(assigns) do
    {user_fields, mod_fields} = manageable_fields(assigns.permissions)

    assigns =
      assigns
      |> assign(:user_fields, user_fields)
      |> assign(:mod_fields, mod_fields)
      |> assign(:dirty, dirty?(assigns.draft, assigns.saved, user_fields ++ mod_fields))

    ~H"""
    <div
      id="mod-perms-dialog"
      phx-hook="ModalDialog"
      data-cancel-event="mod_close"
      class="fixed inset-0 z-80 flex items-center justify-center bg-black/60 px-5"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="mod-perms-title"
        class="w-full max-w-[460px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] shadow-2xl"
      >
        <div class="relative border-b border-[rgb(var(--border-divider))] px-5 pt-5 pb-4">
          <p
            id="mod-perms-title"
            class="text-style-body1Medium text-[rgb(var(--foreground-primary))]"
          >
            User permissions
          </p>
          <p class="text-style-body2Regular mt-1 text-[rgb(var(--foreground-secondary))]">
            Manage what @{@profile.username} can do on Kaguya.
          </p>
          <button
            type="button"
            phx-click="mod_close"
            data-modal-cancel
            disabled={@busy}
            aria-label="Close"
            class="absolute top-3 right-3 inline-flex size-7 cursor-pointer items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] hover:bg-white/8 hover:text-[rgb(var(--foreground-primary))] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[rgb(var(--border-strong-divider,var(--border-divider)))] disabled:opacity-50"
          >
            <Lucide.x class="size-4" aria-hidden />
          </button>
        </div>

        <div class="max-h-[60vh] overflow-y-auto px-5 py-2">
          <section :if={@user_fields != []} class="py-3">
            <h4 class="text-style-captionRegular mb-1 tracking-wider text-[rgb(var(--foreground-tertiary))] uppercase">
              User privileges
            </h4>
            <div class="divide-y divide-[rgb(var(--border-divider))]/40">
              <label
                :for={%{field: field, label: label, description: desc} <- @user_fields}
                class="flex cursor-pointer items-center justify-between gap-5 py-3"
              >
                <span class="min-w-0">
                  <span class="text-style-body2Medium block text-[rgb(var(--foreground-primary))]">
                    {label}
                  </span>
                  <span class="text-style-captionRegular mt-0.5 block text-[rgb(var(--foreground-tertiary))]">
                    {desc}
                  </span>
                </span>
                <.switch
                  checked={Map.get(@draft, field, false)}
                  disabled={@busy}
                  label={label}
                  phx-click="mod_toggle_permission"
                  phx-value-field={field}
                />
              </label>
            </div>
          </section>

          <section
            :if={@mod_fields != []}
            class="border-t border-[rgb(var(--border-divider))]/40 py-3"
          >
            <h4 class="text-style-captionRegular mb-1 tracking-wider text-[rgb(var(--foreground-tertiary))] uppercase">
              Moderator access
            </h4>
            <div class="divide-y divide-[rgb(var(--border-divider))]/40">
              <label
                :for={%{field: field, label: label} <- @mod_fields}
                class="flex cursor-pointer items-center justify-between gap-5 py-3"
              >
                <span class="text-style-body2Medium text-[rgb(var(--foreground-primary))]">
                  {label}
                </span>
                <.switch
                  checked={Map.get(@draft, field, false)}
                  disabled={@busy}
                  label={label}
                  phx-click="mod_toggle_permission"
                  phx-value-field={field}
                />
              </label>
            </div>
          </section>
        </div>

        <div class="flex justify-end gap-2 border-t border-[rgb(var(--border-divider))] px-5 py-4">
          <button
            type="button"
            phx-click="mod_close"
            data-modal-cancel
            disabled={@busy}
            class="h-9 rounded-[6px] bg-[rgb(var(--surface-elevated))] px-4 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-white/8 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="mod_save_permissions"
            disabled={@busy or not @dirty}
            class="h-9 rounded-[6px] bg-[rgb(var(--button-background-brand-default))] px-4 text-sm font-medium text-white hover:bg-[rgb(var(--button-background-brand-hover))] disabled:opacity-50"
          >
            Save changes
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp dirty?(draft, saved, fields) do
    Enum.any?(fields, fn %{field: f} -> Map.get(draft, f) != Map.get(saved, f) end)
  end

  # ---------------------------------------------------------------------------
  # Suppress/restore + delete confirm dialogs
  # ---------------------------------------------------------------------------

  attr :open, :boolean, required: true
  attr :profile, :map, required: true
  attr :ratings_suppressed, :boolean, required: true
  attr :busy, :boolean, default: false

  def suppress_dialog(assigns) do
    title =
      if assigns.ratings_suppressed, do: "Restore User Ratings?", else: "Suppress User Ratings?"

    description =
      if assigns.ratings_suppressed do
        "This will restore #{assigns.profile.username}'s ratings so they count in VN averages again."
      else
        "This will exclude #{assigns.profile.username}'s ratings from all VN averages. Use this for users suspected of rating manipulation."
      end

    confirm_label = if assigns.ratings_suppressed, do: "Restore", else: "Suppress"
    variant = if assigns.ratings_suppressed, do: :default, else: :destructive

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:description, description)
      |> assign(:confirm_label, confirm_label)
      |> assign(:variant, variant)

    ~H"""
    <.confirm_dialog
      :if={@open}
      title={@title}
      description={@description}
      confirm_label={@confirm_label}
      variant={@variant}
      busy={@busy}
      confirm_event="mod_confirm_suppress"
    />
    """
  end

  attr :open, :boolean, required: true
  attr :profile, :map, required: true
  attr :busy, :boolean, default: false

  def delete_dialog(assigns) do
    ~H"""
    <.confirm_dialog
      :if={@open}
      title="Delete User Account?"
      description={"This will permanently delete #{@profile.username}'s account, including all their ratings, reviews, lists, and comments. This cannot be undone."}
      confirm_label="Delete User"
      variant={:destructive}
      busy={@busy}
      confirm_event="mod_confirm_delete"
    />
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :confirm_label, :string, required: true
  attr :variant, :atom, required: true
  attr :busy, :boolean, default: false
  attr :confirm_event, :string, required: true

  defp confirm_dialog(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-80 flex items-center justify-center bg-black/60 px-5"
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        class="w-full max-w-[437px] overflow-hidden rounded-[16px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] shadow-2xl"
      >
        <div class="border-b border-[rgb(var(--border-divider))] px-6 py-4">
          <p class="text-base font-medium text-[rgb(var(--foreground-primary))]">{@title}</p>
        </div>
        <div class="px-6 py-5">
          <p class="text-sm text-[rgb(var(--foreground-secondary))]">{@description}</p>
        </div>
        <div class="flex justify-end gap-2 border-t border-[rgb(var(--border-divider))] px-5 py-4">
          <button
            type="button"
            phx-click="mod_close"
            disabled={@busy}
            class="h-9 rounded-[6px] bg-[rgb(var(--surface-elevated))] px-4 text-sm font-medium text-[rgb(var(--foreground-primary))] hover:bg-white/8 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={@confirm_event}
            disabled={@busy}
            class={[
              "h-9 rounded-[6px] px-4 text-sm font-medium text-white disabled:opacity-50",
              @variant == :destructive &&
                "bg-[rgb(var(--button-background-destructive-default))] hover:bg-[rgb(var(--button-background-destructive-hover))]",
              @variant == :default &&
                "bg-[rgb(var(--button-background-brand-default))] hover:bg-[rgb(var(--button-background-brand-hover))]"
            ]}
          >
            {@confirm_label}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
