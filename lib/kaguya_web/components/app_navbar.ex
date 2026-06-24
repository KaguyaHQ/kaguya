defmodule KaguyaWeb.AppNavbar do
  @moduledoc """
  Site-wide top navigation rendered above every LiveView via the `:app`
  layout. Mirrors the Next.js production navbar
  (`../personal/legacy-next-app/src/components/navbar/Navbar.tsx`):

    * Desktop (>= lg)  — logo, primary nav (Browse / Lists / Members /
      Discussions), search input, notifications bell, avatar, library
      shortcut, and overflow menu (Settings / Reviews / Lists /
      Activity / Chat / Log out).
    * Mobile (< lg)    — logo, inline search toggle, notifications,
      hamburger drawer with primary nav + per-viewer shortcuts.
    * Anonymous        — Log in / Sign up CTAs replace the avatar.

  The component is stateless: it receives the current viewer and the
  current request path, and renders the appropriate state. Dropdown +
  drawer open/close is driven entirely by `Phoenix.LiveView.JS` so no
  LiveView round-trip is needed for menu toggling.

  Many of the linked destinations are not yet implemented as routes in
  this Phoenix app — they're intentional dead links so the navbar
  reaches UX parity with production while the LiveView surfaces are
  ported one-by-one.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Search, as: SharedSearch
  alias Phoenix.LiveView.JS

  @primary_nav [
    %{
      label: "Browse",
      match: :prefix,
      children: [
        %{label: "VNs", href: "/browse", match: :prefix},
        %{label: "Lists", href: "/lists", match: :exact},
        %{label: "Members", href: "/members", match: :exact}
      ]
    },
    %{label: "Discussions", href: "/discussions", match: :prefix}
  ]

  attr :viewer, :map,
    default: nil,
    doc: "Normalized current user map or `nil` for anonymous viewers."

  attr :current_path, :string, default: "/"

  attr :transparent, :boolean,
    default: false,
    doc: "Render with a transparent background (VN pages)."

  def app_navbar(assigns) do
    assigns =
      assigns
      |> assign(:primary_nav, @primary_nav)
      |> assign_new(:viewer, fn -> nil end)

    ~H"""
    <div
      data-nosnippet
      class={[
        "relative z-90 w-full",
        !@transparent && "md:sticky md:top-0"
      ]}
      style="transform: translateZ(0)"
    >
      <.desktop_nav
        viewer={@viewer}
        current_path={@current_path}
        transparent={@transparent}
        primary_nav={@primary_nav}
      />
      <.mobile_nav viewer={@viewer} current_path={@current_path} primary_nav={@primary_nav} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Desktop
  # ---------------------------------------------------------------------------

  attr :viewer, :map, default: nil
  attr :current_path, :string, required: true
  attr :transparent, :boolean, default: false
  attr :primary_nav, :list, required: true

  defp desktop_nav(assigns) do
    ~H"""
    <nav
      class={[
        "h-[72px] w-full max-lg:hidden",
        if(@transparent,
          do: "border-b border-b-transparent bg-transparent",
          else: "bg-surface-base border-b-border-strong-divider border-b"
        )
      ]}
      style={
        if @transparent, do: "box-shadow: none", else: "box-shadow: 0 2px 8px -1px rgba(0,0,0,0.08)"
      }
    >
      <div class="mx-auto flex size-full max-w-[1168px] items-center justify-between px-4 md:px-8">
        <div class="flex items-center">
          <.logo />

          <ul class="text-foreground-primary flex items-center gap-6 pl-7 text-sm">
            <li :for={item <- @primary_nav}>
              <.desktop_nav_link item={item} current_path={@current_path} />
            </li>
          </ul>
        </div>

        <div class="flex items-center gap-4">
          <.search_input />

          <%= if @viewer do %>
            <.notifications_button viewer={@viewer} variant={:desktop} />
            <.avatar_link viewer={@viewer} />
            <.library_link viewer={@viewer} />
            <.user_menu viewer={@viewer} current_path={@current_path} />
          <% else %>
            <.signed_out_actions current_path={@current_path} />
          <% end %>
        </div>
      </div>
    </nav>
    """
  end

  attr :item, :map, required: true
  attr :current_path, :string, required: true

  defp desktop_nav_link(%{item: %{children: _}} = assigns) do
    active? = nav_active?(assigns.item, assigns.current_path)
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <%!-- Dropdown opens on hover (mouse) and focus-within (keyboard). No JS:
    `group-hover` + `group-focus-within` drive visibility. `top-full` puts the
    menu flush against the button bottom so cursor traversal stays inside the
    group's hover zone; visual gap comes from `pt-2` inside the menu wrapper. --%>
    <div class="group relative -mb-1.5">
      <button
        type="button"
        aria-haspopup="menu"
        class={[
          "flex h-[65px] w-fit items-center gap-1 bg-transparent transition-colors",
          if(@active?,
            do: "border-button-background-brand-default border-b-[3px] font-semibold",
            else: "hover:text-foreground-secondary border-b-[3px] border-b-transparent font-medium"
          )
        ]}
      >
        {@item.label}
        <Lucide.chevron_down
          class="size-4 transition-transform duration-150 group-focus-within:rotate-180 group-hover:rotate-180"
          aria-hidden
        />
      </button>

      <div
        role="menu"
        class={[
          "invisible absolute top-full left-0 z-50 min-w-[180px] opacity-0 transition-opacity duration-150",
          "group-hover:visible group-hover:opacity-100",
          "group-focus-within:visible group-focus-within:opacity-100"
        ]}
      >
        <div class="pt-2">
          <div class="bg-surface-elevated border-border-divider rounded-lg border p-1 shadow-lg">
            <.link
              :for={child <- @item.children}
              navigate={child.href}
              role="menuitem"
              class={[
                "block rounded px-3 py-2 text-sm transition-colors",
                if(nav_active?(child, @current_path),
                  do: "text-foreground-primary bg-white/5 font-semibold",
                  else: "text-foreground-primary hover:bg-white/5"
                )
              ]}
            >
              {child.label}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp desktop_nav_link(assigns) do
    active? = nav_active?(assigns.item, assigns.current_path)
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <.link
      navigate={@item.href}
      class={[
        "-mb-1.5 flex h-[65px] w-fit items-center bg-transparent transition-colors",
        if(@active?,
          do: "border-button-background-brand-default border-b-[3px] font-semibold",
          else: "hover:text-foreground-secondary border-b-[3px] border-b-transparent font-medium"
        )
      ]}
    >
      {@item.label}
    </.link>
    """
  end

  # ---------------------------------------------------------------------------
  # Mobile (hamburger drawer)
  # ---------------------------------------------------------------------------

  attr :viewer, :map, default: nil
  attr :current_path, :string, required: true
  attr :primary_nav, :list, required: true

  defp mobile_nav(assigns) do
    ~H"""
    <div
      id="mobile-nav"
      data-state="closed"
      data-search="closed"
      phx-click-away={close_drawer() |> close_search()}
      phx-window-keydown={close_drawer() |> close_search()}
      phx-key="Escape"
      class="bg-surface-base group relative top-0 z-50 flex h-fit w-full flex-col items-center gap-10 px-5 py-0.5 shadow-[0_4px_10px_rgba(0,0,0,0.3)] group-data-[search=open]:shadow-none lg:hidden"
    >
      <div class="flex w-full items-center justify-between gap-0 group-data-[search=open]:gap-2">
        <div class="flex items-center group-data-[search=open]:hidden">
          <.logo />
        </div>

        <button
          type="button"
          phx-click={close_search()}
          class="text-foreground-primary hidden size-11 shrink-0 items-center justify-center rounded-[50%] bg-white/2 p-0 group-data-[search=open]:flex"
          aria-label="Back"
        >
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden>
            <path
              d="M13 4L7 10L13 16"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </button>

        <div class="hidden flex-1 group-data-[search=open]:block">
          <.search_input mobile />
        </div>

        <div class="z-30 flex items-center gap-1 group-data-[search=open]:hidden">
          <button
            type="button"
            phx-click={open_search()}
            class="text-foreground-primary flex size-11 items-center justify-center rounded-full bg-transparent"
            aria-label="Search"
          >
            <.icon_search class="size-6" />
          </button>

          <%= if @viewer do %>
            <.notifications_button viewer={@viewer} variant={:mobile} />
          <% end %>

          <button
            type="button"
            phx-click={toggle_drawer()}
            class="text-foreground-primary flex size-11 items-center justify-center border-none bg-transparent"
            aria-label="Menu"
            aria-haspopup="menu"
            aria-controls="mobile-drawer"
          >
            <.icon_menu class="text-foreground-primary size-6 group-data-[state=open]:hidden" />
            <Lucide.x class="size-6 group-data-[state=closed]:hidden" aria-hidden />
          </button>
        </div>
      </div>

      <div
        phx-click={close_drawer()}
        aria-hidden="true"
        class="pointer-events-none absolute inset-x-0 top-full z-100 h-screen bg-black/40 opacity-0 backdrop-blur-[2px] transition-opacity duration-200 group-data-[state=open]:pointer-events-auto group-data-[state=open]:opacity-100"
      />

      <div
        id="mobile-drawer"
        class="absolute inset-x-0 top-full z-110 grid grid-rows-[0fr] transition-[grid-template-rows] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] group-data-[state=open]:grid-rows-[1fr]"
      >
        <div class="overflow-hidden">
          <div class="bg-surface-base px-6 py-4 opacity-0 shadow-[0_8px_24px_rgba(0,0,0,0.3)] transition-opacity duration-100 group-data-[state=open]:opacity-100 group-data-[state=open]:delay-75 group-data-[state=open]:duration-200">
            <%= if @viewer do %>
              <.link
                navigate={"/@#{@viewer.username}"}
                class="text-foreground-primary flex items-center gap-2.5 rounded-[8px] p-3 text-[15px] font-medium hover:bg-white/5"
              >
                <.avatar viewer={@viewer} size="size-9" sizes="36px" />
                {display_name(@viewer)}
              </.link>

              <div class="mt-2 grid grid-cols-2 gap-1.5">
                <.link
                  :for={shortcut <- viewer_shortcuts(@viewer)}
                  navigate={shortcut.href}
                  class="text-foreground-secondary flex items-center gap-2 rounded-[8px] px-3 py-2.5 text-[13px] font-medium hover:bg-white/5"
                >
                  <.viewer_shortcut_icon kind={shortcut.kind} class="size-[18px]" />
                  {shortcut.label}
                </.link>
              </div>

              <div class="border-border-divider my-3 border-t" />
            <% end %>

            <nav>
              <.link
                :for={item <- flatten_nav(@primary_nav)}
                navigate={item.href}
                class={[
                  "flex items-center gap-2.5 rounded-[8px] p-3 text-[15px] font-medium",
                  if(nav_active?(item, @current_path),
                    do: "text-foreground-primary bg-white/5",
                    else: "text-foreground-primary hover:bg-white/5"
                  )
                ]}
              >
                <.primary_nav_icon kind={item.label} class="size-[22px]" />
                {item.label}
              </.link>

              <.link
                :if={@viewer}
                navigate="/account/settings"
                class="text-foreground-primary flex items-center gap-2.5 rounded-[8px] p-3 text-[15px] font-medium hover:bg-white/5"
              >
                <Lucide.settings class="size-[22px]" aria-hidden /> Settings
              </.link>
            </nav>

            <div class="border-border-divider my-3 border-t" />

            <%= if @viewer do %>
              <.sign_out_button current_path={@current_path} />
            <% else %>
              <div class="flex gap-3">
                <a
                  href={~p"/signup"}
                  rel="nofollow"
                  class="bg-button-background-neutral-inverse-default text-button-text-on-neutral-inverse flex h-11 flex-1 items-center justify-center rounded-[8px] text-[15px] font-semibold"
                >
                  Sign up
                </a>
                <.link
                  navigate={~p"/login"}
                  rel="nofollow"
                  class="bg-button-background-neutral-default text-foreground-primary flex h-11 flex-1 items-center justify-center rounded-[8px] text-[15px] font-semibold"
                >
                  Log in
                </.link>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_drawer(js \\ %JS{}) do
    js
    |> JS.toggle_attribute({"data-state", "open", "closed"}, to: "#mobile-nav")
    |> JS.set_attribute({"data-search", "closed"}, to: "#mobile-nav")
  end

  defp close_drawer(js \\ %JS{}) do
    JS.set_attribute(js, {"data-state", "closed"}, to: "#mobile-nav")
  end

  defp open_search(js \\ %JS{}) do
    js
    |> JS.set_attribute({"data-search", "open"}, to: "#mobile-nav")
    |> JS.set_attribute({"data-state", "closed"}, to: "#mobile-nav")
    |> JS.focus(to: "#mobile-vn-search [data-vn-search-input]")
  end

  defp close_search(js \\ %JS{}) do
    JS.set_attribute(js, {"data-search", "closed"}, to: "#mobile-nav")
  end

  # ---------------------------------------------------------------------------
  # Building blocks
  # ---------------------------------------------------------------------------

  defp logo(assigns) do
    ~H"""
    <.link
      navigate="/"
      class="text-foreground-primary flex w-fit items-center gap-[5.44px] sm:gap-[9px]"
    >
      <span
        class="text-[20px] leading-[24px] font-semibold tracking-[-0.04em] sm:text-[28px] sm:leading-[34px]"
        style="font-family: var(--font-fraunces)"
      >
        Kaguya
      </span>
    </.link>
    """
  end

  attr :mobile, :boolean, default: false

  defp search_input(assigns) do
    assigns =
      assign(
        assigns,
        :search_id,
        if(assigns.mobile, do: "mobile-vn-search", else: "desktop-vn-search")
      )

    ~H"""
    <SharedSearch.navbar_vn_search
      id={@search_id}
      mobile={@mobile}
      mobile_fullheight={@mobile}
      variant={if(@mobile, do: :compact, else: :default)}
      page_size={24}
      show_all_results
    />
    """
  end

  attr :viewer, :map, required: true
  attr :variant, :atom, values: [:desktop, :mobile], required: true

  defp notifications_button(assigns) do
    ~H"""
    <.link
      navigate="/notifications"
      class={[
        "text-foreground-secondary relative flex size-11 shrink-0 items-center justify-center rounded-full transition-colors",
        if(@variant == :desktop, do: "hover:bg-surface-menu-item-hover", else: "")
      ]}
      aria-label="Notifications"
    >
      <.icon_bell_outline :if={unread_count(@viewer) == 0} class="size-6" />
      <.icon_bell_filled :if={unread_count(@viewer) > 0} class="size-6" />
      <span
        :if={unread_count(@viewer) > 0}
        class="bg-button-background-brand-default text-button-text-on-brand absolute top-1 right-1 grid min-h-[18px] min-w-[18px] place-items-center rounded-full px-1 text-[10px] leading-none font-semibold"
      >
        {unread_count_label(@viewer)}
      </span>
    </.link>
    """
  end

  attr :viewer, :map, required: true

  defp avatar_link(assigns) do
    ~H"""
    <.link navigate={"/@#{@viewer.username}"} class="shrink-0">
      <.avatar viewer={@viewer} size="size-8" sizes="32px" />
    </.link>
    """
  end

  attr :viewer, :map, required: true

  defp library_link(assigns) do
    ~H"""
    <.link
      navigate={"/@#{@viewer.username}/library"}
      class="hover:bg-surface-menu-item-hover text-foreground-secondary relative flex size-11 shrink-0 items-center justify-center rounded-full bg-transparent"
      aria-label="Library"
    >
      <.icon_library class="size-6" />
    </.link>
    """
  end

  attr :viewer, :map, required: true
  attr :current_path, :string, required: true

  defp user_menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click={JS.toggle(to: "#user-menu-dropdown")}
        class="hover:bg-surface-elevated text-foreground-secondary flex size-11 items-center justify-center rounded-full bg-transparent p-2.5"
        aria-label="More menu"
        aria-haspopup="menu"
      >
        <.icon_ellipsis class="size-6" />
      </button>

      <div
        id="user-menu-dropdown"
        style="display: none"
        phx-click-away={JS.hide(to: "#user-menu-dropdown")}
        role="menu"
        class="bg-surface-menu-item-default absolute right-0 z-120 mt-3 w-[240px] rounded-[12px] p-0 shadow-[1px_10px_10px_rgba(10,25,30,0.30)]"
      >
        <.user_menu_item navigate="/account/settings" label="Settings">
          <Lucide.settings class="text-foreground-secondary size-4" aria-hidden />
        </.user_menu_item>
        <.user_menu_item navigate={"/@#{@viewer.username}/reviews"} label="Reviews">
          <Lucide.message_square_text class="text-foreground-secondary size-4" aria-hidden />
        </.user_menu_item>
        <.user_menu_item navigate={"/@#{@viewer.username}/lists"} label="Lists">
          <Lucide.list_ordered class="text-foreground-secondary size-4" aria-hidden />
        </.user_menu_item>
        <.user_menu_item navigate={"/@#{@viewer.username}/activity"} label="Activity">
          <Lucide.activity class="text-foreground-secondary size-4" aria-hidden />
        </.user_menu_item>
        <.user_menu_item href="https://discord.gg/stcK4A23jt" label="Chat" target="_blank">
          <.icon_discord class="text-foreground-secondary size-4" />
        </.user_menu_item>
        <div class="border-border-divider/40 border-t" />
        <.form for={%{}} action={~p"/auth/sign-out"} method="post">
          <input type="hidden" name="return_to" value="/" />
          <button
            type="submit"
            role="menuitem"
            phx-click={JS.hide(to: "#user-menu-dropdown")}
            class="active:bg-surface-menu-item-pressed bg-surface-menu-item-default hover:bg-surface-menu-item-hover text-foreground-primary flex size-full items-center gap-[9px] px-5 py-3 text-sm font-medium"
          >
            <Lucide.log_out class="text-foreground-secondary size-4" aria-hidden /> Log Out
          </button>
        </.form>
      </div>
    </div>
    """
  end

  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :label, :string, required: true
  attr :target, :string, default: nil
  slot :inner_block, required: true

  defp user_menu_item(%{navigate: nav} = assigns) when is_binary(nav) do
    ~H"""
    <.link
      navigate={@navigate}
      role="menuitem"
      class="active:bg-surface-menu-item-pressed bg-surface-menu-item-default hover:bg-surface-menu-item-hover text-foreground-primary flex size-full items-center gap-[9px] px-5 py-3 text-sm font-medium"
    >
      {render_slot(@inner_block)}
      {@label}
    </.link>
    """
  end

  defp user_menu_item(assigns) do
    ~H"""
    <a
      href={@href}
      target={@target}
      role="menuitem"
      class="active:bg-surface-menu-item-pressed bg-surface-menu-item-default hover:bg-surface-menu-item-hover text-foreground-primary flex size-full items-center gap-[9px] px-5 py-3 text-sm font-medium"
    >
      {render_slot(@inner_block)}
      {@label}
    </a>
    """
  end

  attr :current_path, :string, required: true

  defp signed_out_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <.link
        navigate={~p"/login"}
        rel="nofollow"
        class="text-foreground-primary text-style-body2Medium px-3 py-2.5 whitespace-nowrap underline-offset-2 hover:underline"
      >
        Log in
      </.link>
      <a
        href={~p"/signup"}
        rel="nofollow"
        class="text-foreground-primary text-style-body2Medium px-3 py-2.5 whitespace-nowrap underline-offset-2 hover:underline"
      >
        Sign up
      </a>
    </div>
    """
  end

  attr :current_path, :string, required: true

  defp sign_out_button(assigns) do
    ~H"""
    <.form for={%{}} action={~p"/auth/sign-out"} method="post">
      <input type="hidden" name="return_to" value="/" />
      <button
        type="submit"
        phx-click={close_drawer()}
        class="text-foreground-primary flex w-full items-center gap-2.5 rounded-[8px] p-3 text-[15px] font-medium hover:bg-white/5"
      >
        <Lucide.log_out class="size-[22px]" aria-hidden /> Log Out
      </button>
    </.form>
    """
  end

  attr :viewer, :map, required: true
  attr :size, :string, required: true
  attr :sizes, :string, required: true

  defp avatar(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@viewer}
      size={@size}
      sizes={@sizes}
      fallback={:initials}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Icon map
  # ---------------------------------------------------------------------------

  attr :class, :string, default: nil

  defp icon_search(assigns) do
    ~H"""
    <.search_icon class={@class} />
    """
  end

  defp icon_menu(assigns) do
    ~H"""
    <svg
      viewBox="0 0 512 512"
      fill="none"
      class={@class}
      aria-hidden
    >
      <path
        d="M80 160h352M80 256h352M80 352h352"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-miterlimit="10"
        stroke-width="32"
      />
    </svg>
    """
  end

  defp icon_library(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 512 512"
      fill="none"
      class={["text-foreground-secondary", @class]}
      aria-hidden
    >
      <rect
        x="32"
        y="96"
        width="64"
        height="368"
        rx="16"
        ry="16"
        fill="none"
        stroke="currentColor"
        stroke-linejoin="round"
        stroke-width="32"
      />
      <path
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="32"
        d="M112 224h128M112 400h128"
      />
      <rect
        x="112"
        y="160"
        width="128"
        height="304"
        rx="16"
        ry="16"
        fill="none"
        stroke="currentColor"
        stroke-linejoin="round"
        stroke-width="32"
      />
      <rect
        x="256"
        y="48"
        width="96"
        height="416"
        rx="16"
        ry="16"
        fill="none"
        stroke="currentColor"
        stroke-linejoin="round"
        stroke-width="32"
      />
      <path
        fill="none"
        stroke="currentColor"
        stroke-linejoin="round"
        stroke-width="32"
        d="M422.46 96.11l-40.4 4.25c-11.12 1.17-19.18 11.57-17.93 23.1l34.92 321.59c1.26 11.53 11.37 20 22.49 18.84l40.4-4.25c11.12-1.17 19.18-11.57 17.93-23.1L445 115c-1.31-11.58-11.42-20.06-22.54-18.89z"
      />
    </svg>
    """
  end

  defp icon_bell_outline(assigns) do
    ~H"""
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      class={@class}
      aria-hidden
    >
      <path
        d="M15 18V18.75C15 19.5456 14.6839 20.3087 14.1213 20.8713C13.5587 21.4339 12.7957 21.75 12 21.75C11.2044 21.75 10.4413 21.4339 9.87868 20.8713C9.31607 20.3087 9 19.5456 9 18.75V18M20.0475 16.4733C18.8438 15 17.9939 14.25 17.9939 10.1883C17.9939 6.46875 16.0945 5.14359 14.5313 4.5C14.3236 4.41469 14.1281 4.21875 14.0648 4.00547C13.7906 3.07219 13.0219 2.25 12 2.25C10.9781 2.25 10.2089 3.07266 9.9375 4.00641C9.87422 4.22203 9.67875 4.41469 9.4711 4.5C7.90594 5.14453 6.00844 6.465 6.00844 10.1883C6.0061 14.25 5.15625 15 3.9525 16.4733C3.45375 17.0836 3.89063 18 4.76297 18H19.2417C20.1094 18 20.5434 17.0808 20.0475 16.4733Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  defp icon_bell_filled(assigns) do
    ~H"""
    <svg
      width="24"
      height="24"
      viewBox="0 0 28 28"
      fill="none"
      class={@class}
      aria-hidden
    >
      <path
        d="M24.0669 18.6654C23.9761 18.556 23.8869 18.4466 23.7994 18.3411C22.5963 16.8859 21.8684 16.0076 21.8684 11.888C21.8684 9.75516 21.3582 8.00516 20.3525 6.69266C19.6109 5.72305 18.6085 4.9875 17.2873 4.44391C17.2703 4.43445 17.2551 4.42204 17.2424 4.40727C16.7672 2.81586 15.4667 1.75 14 1.75C12.5333 1.75 11.2334 2.81586 10.7581 4.40562C10.7455 4.41988 10.7305 4.4319 10.7138 4.44117C7.63054 5.71047 6.13211 8.1457 6.13211 11.8863C6.13211 16.0076 5.40531 16.8859 4.20109 18.3395C4.11359 18.445 4.02445 18.5522 3.93367 18.6637C3.69917 18.9466 3.5506 19.2906 3.50553 19.6552C3.46046 20.0198 3.52079 20.3897 3.67937 20.7211C4.01679 21.432 4.73594 21.8734 5.55679 21.8734H22.4492C23.2662 21.8734 23.9805 21.4326 24.319 20.7249C24.4782 20.3935 24.5391 20.0233 24.4945 19.6582C24.4498 19.2932 24.3014 18.9487 24.0669 18.6654ZM14 26.25C14.7903 26.2494 15.5656 26.0348 16.2438 25.6292C16.922 25.2236 17.4778 24.642 17.8522 23.946C17.8698 23.9127 17.8785 23.8753 17.8775 23.8376C17.8764 23.7999 17.8656 23.7631 17.8461 23.7308C17.8266 23.6985 17.7991 23.6718 17.7663 23.6532C17.7334 23.6347 17.6963 23.625 17.6586 23.625H10.3425C10.3047 23.6249 10.2676 23.6345 10.2346 23.653C10.2017 23.6715 10.1741 23.6982 10.1545 23.7305C10.135 23.7629 10.1242 23.7997 10.1231 23.8375C10.122 23.8752 10.1307 23.9126 10.1484 23.946C10.5227 24.6419 11.0784 25.2234 11.7565 25.6291C12.4346 26.0347 13.2098 26.2493 14 26.25Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  defp icon_ellipsis(assigns) do
    ~H"""
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" class={@class} aria-hidden>
      <path
        d="M19.5 13.5C20.3284 13.5 21 12.8284 21 12C21 11.1716 20.3284 10.5 19.5 10.5C18.6716 10.5 18 11.1716 18 12C18 12.8284 18.6716 13.5 19.5 13.5Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-miterlimit="10"
      />
      <path
        d="M12 13.5C12.8284 13.5 13.5 12.8284 13.5 12C13.5 11.1716 12.8284 10.5 12 10.5C11.1716 10.5 10.5 11.1716 10.5 12C10.5 12.8284 11.1716 13.5 12 13.5Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-miterlimit="10"
      />
      <path
        d="M4.5 13.5C5.32843 13.5 6 12.8284 6 12C6 11.1716 5.32843 10.5 4.5 10.5C3.67157 10.5 3 11.1716 3 12C3 12.8284 3.67157 13.5 4.5 13.5Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-miterlimit="10"
      />
    </svg>
    """
  end

  # Brand icons (Lucide has no Discord glyph — KEEP_INLINE)
  # ---------------------------------------------------------------------------

  attr :class, :string, default: nil

  defp icon_discord(assigns) do
    ~H"""
    <svg viewBox="0 0 16 13" class={@class} fill="currentColor" aria-hidden="true">
      <path d="M13.55 1.09A14.4 14.4 0 0 0 10.25 0c-.14.27-.31.63-.42.92a12.7 12.7 0 0 0-3.66 0C6.06.63 5.89.27 5.74 0 4.58.21 3.48.58 2.44 1.09.35 4.4-.22 7.64.07 10.82a14.78 14.78 0 0 0 4.05 2.18c.33-.47.62-.97.87-1.5-.48-.19-.94-.42-1.37-.7l.34-.27A11.27 11.27 0 0 0 12.05 10.52l.34.28c-.43.27-.89.51-1.37.7.25.53.55 1.03.87 1.5a14.62 14.62 0 0 0 4.05-2.18C16.26 7.13 15.36 3.93 13.55 1.09ZM5.34 8.86c-.79 0-1.44-.78-1.44-1.72s.64-1.72 1.44-1.72c.8 0 1.45.78 1.44 1.72 0 .94-.63 1.72-1.44 1.72Zm5.32 0c-.79 0-1.44-.78-1.44-1.72s.63-1.72 1.44-1.72c.8 0 1.45.78 1.44 1.72 0 .94-.64 1.72-1.44 1.72Z" />
    </svg>
    """
  end

  attr :kind, :string, required: true
  attr :class, :string, default: nil

  defp primary_nav_icon(%{kind: "Browse"} = assigns) do
    ~H"""
    <Lucide.compass class={@class} aria-hidden />
    """
  end

  defp primary_nav_icon(%{kind: "VNs"} = assigns) do
    ~H"""
    <Lucide.compass class={@class} aria-hidden />
    """
  end

  defp primary_nav_icon(%{kind: "Lists"} = assigns) do
    ~H"""
    <Lucide.list class={@class} aria-hidden />
    """
  end

  defp primary_nav_icon(%{kind: "Discussions"} = assigns) do
    ~H"""
    <Lucide.message_square_text class={@class} aria-hidden />
    """
  end

  defp primary_nav_icon(%{kind: "Members"} = assigns) do
    ~H"""
    <Lucide.users class={@class} aria-hidden />
    """
  end

  defp primary_nav_icon(assigns) do
    _ = assigns
    ~H""
  end

  attr :kind, :atom, required: true
  attr :class, :string, default: nil

  defp viewer_shortcut_icon(%{kind: :library} = assigns) do
    ~H"""
    <Lucide.book_open class={@class} aria-hidden />
    """
  end

  defp viewer_shortcut_icon(%{kind: :reviews} = assigns) do
    ~H"""
    <Lucide.message_square_text class={@class} aria-hidden />
    """
  end

  defp viewer_shortcut_icon(%{kind: :lists} = assigns) do
    ~H"""
    <Lucide.list_ordered class={@class} aria-hidden />
    """
  end

  defp viewer_shortcut_icon(%{kind: :activity} = assigns) do
    ~H"""
    <Lucide.activity class={@class} aria-hidden />
    """
  end

  defp viewer_shortcut_icon(assigns) do
    ~H""
  end

  # ---------------------------------------------------------------------------
  # Public viewer normalizer — call from LiveView mount to avoid repeating the
  # plain-map shape this component depends on.
  # ---------------------------------------------------------------------------

  @doc """
  Normalize a `Kaguya.Users.User` struct (or the plain map assigned to
  `:current_user` by `KaguyaWeb.UserAuth`) into the shape this navbar
  expects.

  Returns `nil` for anonymous viewers.
  """
  def normalize_viewer(user, unread_count \\ 0)

  def normalize_viewer(nil, _unread_count), do: nil

  def normalize_viewer(%{username: username} = user, unread_count) when is_binary(username) do
    %{
      id: Map.get(user, :id),
      username: username,
      display_name: Map.get(user, :display_name) || username,
      avatar_url: avatar_url_from(user),
      unread_notifications_count: unread_count
    }
  end

  def normalize_viewer(_, _unread_count), do: nil

  defp avatar_url_from(%{avatar_urls: %{small: small}}) when is_binary(small), do: small

  defp avatar_url_from(%{avatar_id: avatar_id}) when is_binary(avatar_id) do
    case Kaguya.Users.build_avatar_urls(avatar_id) do
      %{small: small} when is_binary(small) -> small
      _ -> nil
    end
  end

  defp avatar_url_from(_), do: nil

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp viewer_shortcuts(viewer) do
    [
      %{label: "Library", href: "/@#{viewer.username}/library", kind: :library},
      %{label: "Reviews", href: "/@#{viewer.username}/reviews", kind: :reviews},
      %{label: "Lists", href: "/@#{viewer.username}/lists", kind: :lists},
      %{label: "Activity", href: "/@#{viewer.username}/activity", kind: :activity}
    ]
  end

  defp nav_active?(%{children: children}, current_path) when is_list(children) do
    Enum.any?(children, &nav_active?(&1, current_path))
  end

  defp nav_active?(%{href: href, match: :exact}, current_path), do: current_path == href

  defp nav_active?(%{href: href, match: :prefix}, current_path) do
    String.starts_with?(current_path || "", href)
  end

  # Flatten nested nav (parents with children) into a single-level list of
  # leaves. Used by the mobile drawer so the touch surface stays a flat list
  # instead of recreating the desktop dropdown.
  defp flatten_nav(items) do
    Enum.flat_map(items, fn
      %{children: children} -> children
      item -> [item]
    end)
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp unread_count(%{unread_notifications_count: count}) when is_integer(count) and count > 0,
    do: count

  defp unread_count(_), do: 0

  defp unread_count_label(viewer) do
    case unread_count(viewer) do
      n when n > 99 -> "99+"
      n -> Integer.to_string(n)
    end
  end
end
