defmodule KaguyaWeb.Dev.StyleGuideLive do
  @moduledoc """
  Style guide and visual-regression surface for the ui component library.

  Renders the canonical button matrix (every variant × size, plus disabled,
  loading, and a layout-override demo) and exercises the interactive
  primitives — Dialog, AlertDialog, Menu (disclosure menu + popover) —
  end-to-end at the dev-only route `/dev/ui/style-guide`.
  Eyeball this page after touching component CSS or the menu/dialog hooks.

  Not exposed in any production environment — see router.ex guard.
  """
  use KaguyaWeb, :live_view

  import KaguyaWeb.UI.Button
  import KaguyaWeb.UI.Dialog
  import KaguyaWeb.UI.Menu
  import KaguyaWeb.UI.Input

  alias Phoenix.LiveView.JS
  alias KaguyaWeb.UI.Table
  alias KaguyaWeb.UI.FilterControl
  alias KaguyaWeb.SharedComponents.FilterChip

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       last_event: nil,
       dialog_open?: false,
       alert_open?: false,
       filter_selected?: false
     )}
  end

  def handle_event("toggle_demo_filter", _params, socket) do
    {:noreply, assign(socket, :filter_selected?, !socket.assigns.filter_selected?)}
  end

  def handle_event("primitive_event", %{"label" => label}, socket) do
    {:noreply, assign(socket, last_event: label)}
  end

  def handle_event("open_demo_dialog", _params, socket),
    do: {:noreply, assign(socket, dialog_open?: true)}

  def handle_event("close_demo_dialog", _params, socket),
    do: {:noreply, assign(socket, dialog_open?: false)}

  def handle_event("open_demo_alert", _params, socket),
    do: {:noreply, assign(socket, alert_open?: true)}

  def handle_event("close_demo_alert", _params, socket),
    do: {:noreply, assign(socket, alert_open?: false)}

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-12 p-8">
      <header class="space-y-2">
        <h1 class="text-foreground-primary text-style-heading2Medium">
          Style guide
        </h1>
        <p class="text-foreground-secondary text-style-body2Regular">
          Canonical component matrix and interactive primitives. Last event:
          <code class="bg-surface-elevated text-foreground-link rounded px-2 py-0.5">
            {@last_event || "(none)"}
          </code>
        </p>
      </header>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Input</h2>
        <div class="flex max-w-md flex-col gap-3">
          <label for="demo-name" class="text-sm">Name</label>
          <.input id="demo-name" type="text" placeholder="Your name" />
          <label for="demo-email" class="text-sm">Email — validation error</label>
          <.input
            id="demo-email"
            type="email"
            value="not-an-email"
            aria-invalid="true"
            aria-describedby="demo-email-error"
          />
          <p id="demo-email-error" class="text-semantic-error text-sm">
            Enter a valid email address.
          </p>
          <label for="demo-password" class="text-sm">Password</label>
          <.input id="demo-password" type="password" placeholder="••••••••" />
          <label for="demo-readonly" class="text-sm">Read only</label>
          <.input id="demo-readonly" type="text" value="readonly value" readonly />
          <label for="demo-disabled" class="text-sm">Disabled</label>
          <.input id="demo-disabled" type="text" placeholder="disabled" disabled />
        </div>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Filters</h2>
        <p class="text-foreground-secondary text-sm">
          FilterControl owns filter styling; Menu owns disclosure behavior. FilterChip represents
          an applied filter. Use Tab to inspect focus, Enter to open, and Escape to dismiss.
        </p>
        <div class="flex flex-wrap items-center gap-3">
          <.menu id="demo-filter" class={FilterControl.trigger_class(@filter_selected?)}>
            <:trigger>Tags <Lucide.chevron_down class="size-4" aria-hidden /></:trigger>
            <div class={[FilterControl.panel_class(), "w-56"]}>
              <.menu_item
                event="toggle_demo_filter"
                aria-pressed={to_string(@filter_selected?)}
                class={FilterControl.option_class(@filter_selected?)}
              >
                Romance <Lucide.check :if={@filter_selected?} class="ml-auto size-4" aria-hidden />
              </.menu_item>
            </div>
          </.menu>
          <button type="button" disabled class={FilterControl.trigger_class(false)}>Unavailable filter</button>
          <FilterChip.filter_chip
            :if={@filter_selected?}
            label="Romance"
            icon_x
            phx-click="toggle_demo_filter"
            aria-label="Remove Romance filter"
          />
        </div>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Button</h2>
        <div class="space-y-3">
          <div
            :for={
              variant <- ~w(brand neutral neutral-inverse destructive ghost ghost-destructive link)
            }
            class="flex flex-wrap items-center gap-3"
          >
            <.button :for={size <- ~w(large medium small)} variant={variant} size={size}>
              {variant} / {size}
            </.button>
            <.button variant={variant} size="icon" aria-label={"#{variant} icon"}>
              <Lucide.plus class="size-4" aria-hidden />
            </.button>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <.button disabled>Disabled</.button>
            <.button loading>Loading</.button>
          </div>
          <.button class="w-full">w-full layout override</.button>
        </div>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Dialog</h2>
        <div class="flex flex-wrap items-center gap-3">
          <.button phx-click="open_demo_dialog">
            Open dialog
          </.button>
          <.dialog
            :if={@dialog_open?}
            id="demo-dialog"
            on_close={JS.push("close_demo_dialog")}
            class="bg-surface-elevated text-foreground-primary flex w-full max-w-lg flex-col gap-4 rounded-lg border border-[rgb(var(--border-divider))] p-6"
          >
            <.dialog_header>
              <.dialog_title>Edit profile</.dialog_title>
              <.dialog_description>
                Make changes to your profile here. Click save when you're done.
              </.dialog_description>
            </.dialog_header>
            <div class="space-y-3 py-2">
              <label class="text-style-body2Medium block">
                Name <.input id="demo-dialog-name" type="text" class="mt-1" />
              </label>
            </div>
            <.dialog_footer>
              <.dialog_cancel>Cancel</.dialog_cancel>
              <.dialog_action
                variant="brand"
                phx-click="close_demo_dialog"
              >
                Save changes
              </.dialog_action>
            </.dialog_footer>
          </.dialog>
        </div>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">AlertDialog</h2>
        <.button variant="destructive" phx-click="open_demo_alert">
          Delete account
        </.button>
        <.dialog
          :if={@alert_open?}
          id="demo-alert-dialog"
          on_close={JS.push("close_demo_alert")}
          class="bg-surface-base border-border-divider flex w-full max-w-lg flex-col gap-4 rounded-[16px] border p-6 shadow-lg"
        >
          <.dialog_header>
            <.dialog_title>Are you absolutely sure?</.dialog_title>
            <.dialog_description>
              This action cannot be undone. This will permanently delete your account
              and remove your data from our servers.
            </.dialog_description>
          </.dialog_header>
          <.dialog_footer>
            <.dialog_cancel>Cancel</.dialog_cancel>
            <.dialog_action phx-click={
              JS.push("primitive_event", value: %{label: "alert:confirm-delete"})
              |> JS.push("close_demo_alert")
            }>
              Yes, delete
            </.dialog_action>
          </.dialog_footer>
        </.dialog>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Table</h2>
        <p class="text-foreground-secondary text-sm">
          Titles use row headers. Numeric columns align right and retain tabular digits.
          Pages own their columns and sorting; the shared component owns presentation.
        </p>
        <div class="border-border-divider overflow-hidden rounded-xl border">
          <Table.table id="demo-table" caption="Example catalogue ratings">
            <:header>
              <Table.column_header class="px-4">Title</Table.column_header>
              <Table.column_header class="w-28 px-4 text-right" sort="descending">
                Rating / 5 <span aria-hidden="true">↓</span>
              </Table.column_header>
              <Table.column_header class="w-24 px-4 text-right">Votes</Table.column_header>
            </:header>
            <tr :for={
              {title, rating, votes} <- [
                {"Example visual novel", "4.50", "128"},
                {"A longer title that can wrap naturally", "4.25", "96"},
                {"Unrated visual novel", "—", "2"}
              ]
            }>
              <th scope="row" class="p-4 text-base font-medium">{title}</th>
              <td class="p-4 text-right tabular-nums">{rating}</td>
              <td class="text-foreground-secondary p-4 text-right tabular-nums">{votes}</td>
            </tr>
          </Table.table>
        </div>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Menu (disclosure)</h2>
        <.menu
          id="demo-dropdown"
          class="border-border-divider text-foreground-primary rounded-md border px-4 py-2"
        >
          <:trigger>Open menu</:trigger>
          <div class="bg-surface-menu-item-default border-border-divider w-[200px] overflow-hidden rounded-[12px] border p-0 shadow-[0_5px_15px_rgba(0,5,15,0.35)]">
            <div class="text-foreground-secondary px-3 py-2 text-xs font-semibold">Actions</div>
            <.menu_item
              event="primitive_event"
              value={%{label: "dropdown:profile"}}
              class="hover:bg-surface-menu-item-hover text-foreground-primary flex w-full items-center px-3 py-2 text-sm"
            >
              Profile
            </.menu_item>
            <.menu_item
              event="primitive_event"
              value={%{label: "dropdown:settings"}}
              class="hover:bg-surface-menu-item-hover text-foreground-primary flex w-full items-center px-3 py-2 text-sm"
            >
              Settings
            </.menu_item>
            <div class="bg-border-divider my-1 h-px" />
            <.menu_item
              event="primitive_event"
              value={%{label: "dropdown:logout"}}
              class="flex w-full items-center px-3 py-2 text-sm text-[#f94441] hover:bg-white/4"
            >
              Sign out
            </.menu_item>
          </div>
        </.menu>
      </section>

      <section class="space-y-4">
        <h2 class="text-foreground-primary text-style-heading3Medium">Popover (non-menu)</h2>
        <div class="flex flex-wrap gap-3">
          <.menu
            id="demo-popover-bottom"
            class="border-border-divider text-foreground-primary rounded-md border px-4 py-2"
          >
            <:trigger>Open popover (bottom)</:trigger>
            <div class="bg-surface-base border-border-divider text-foreground-primary w-72 rounded-[12px] border p-4 shadow-xl">
              <div class="space-y-2">
                <h3 class="text-foreground-primary text-style-body2Semibold">Quick action</h3>
                <p class="text-foreground-secondary text-style-body2Regular">
                  Popovers anchor relative to their trigger and dismiss on outside click or Esc.
                </p>
                <button
                  type="button"
                  data-menu-dismiss
                  class="text-foreground-link text-style-body2Medium"
                  phx-click={JS.push("primitive_event", value: %{label: "popover:confirm"})}
                >
                  Send event
                </button>
              </div>
            </div>
          </.menu>

          <.menu
            id="demo-popover-right"
            placement="right"
            class="border-border-divider text-foreground-primary rounded-md border px-4 py-2"
          >
            <:trigger>Open popover (right)</:trigger>
            <div class="bg-surface-base border-border-divider text-foreground-primary w-64 rounded-[12px] border p-4 shadow-xl">
              <p class="text-foreground-secondary text-style-body2Regular">
                Right-anchored popover content.
              </p>
            </div>
          </.menu>
        </div>
      </section>
    </div>
    """
  end
end
