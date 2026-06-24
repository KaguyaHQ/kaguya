defmodule KaguyaWeb.AppFooter do
  @moduledoc """
  Site-wide footer rendered beneath every LiveView via the `:app`
  layout:

    * Four-column nav: Project / Contribute / Policies / Tools.
    * Bottom row: copyright + VNDB attribution on the left, contact +
      GitHub + Discord on the right.

  The footer is stateless and renders migrated LiveView routes. Some
  production destinations don't yet have LiveView routes and are omitted
  until the corresponding pages are ported.

  Create forms live under `/contribute/:type` (e.g. `/contribute/vn`,
  `/contribute/character`, `/contribute/developer`) so they can never
  collide with an entity slug — production's `/vn/new` resolves to a real
  VN slugged "new", not a create page. VN, character, and producer create
  are ported; add an "Add series" link pointing at `/contribute/series`
  once that form lands.

  TODO: Production's create links call `useRequireAuth` to open the
  auth-prompt modal for signed-out viewers. That modal isn't ported yet
  (see `docs/migrations/nextjs-liveview/shared-systems.md` §8); wire these links
  through it once it exists.
  """

  use KaguyaWeb, :html

  @project_links [
    %{label: "About", href: "/about"},
    %{label: "FAQ", href: "/faq"},
    %{label: "Feedback", href: "/discussions/feedback"},
    %{label: "Dumps", href: "/dumps"}
  ]

  @contribute_links [
    %{label: "Add visual novel", href: "/contribute/vn"},
    %{label: "Add character", href: "/contribute/character"},
    %{label: "Add producer", href: "/contribute/developer"},
    %{label: "Recent changes", href: "/history"}
  ]

  @policies_links [
    %{label: "Community guidelines", href: "/community-guidelines"},
    %{label: "Review guidelines", href: "/review-guidelines"},
    %{label: "Terms", href: "/terms"},
    %{label: "Privacy", href: "/privacy-policy"}
  ]

  @tools_links [
    %{label: "VN recommender", href: "/vn-recommender"},
    %{label: "Site stats", href: "/site-stats"}
  ]

  def app_footer(assigns) do
    assigns =
      assigns
      |> assign(:current_year, Date.utc_today().year)
      |> assign(:project_links, @project_links)
      |> assign(:contribute_links, @contribute_links)
      |> assign(:policies_links, @policies_links)
      |> assign(:tools_links, @tools_links)

    ~H"""
    <footer data-nosnippet class="border-border-divider w-full border-t">
      <div class="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
        <div class="grid grid-cols-2 gap-6 sm:gap-10 lg:grid-cols-4">
          <.column heading="Project" links={@project_links} />
          <.column heading="Contribute" links={@contribute_links} />
          <.column heading="Policies" links={@policies_links} />
          <.column heading="Tools" links={@tools_links} />
        </div>

        <div class="border-border-divider/60 text-foreground-tertiary flex flex-wrap items-center justify-between gap-2 border-t pt-4 text-[11px] sm:text-xs">
          <div class="flex items-center gap-1.5 sm:gap-2">
            <span>© {@current_year} Kaguya</span>
            <span class="text-foreground-tertiary/50">·</span>
            <span>
              Data from
              <a
                href="https://vndb.org/"
                target="_blank"
                rel="noopener noreferrer"
                class="hover:text-foreground-secondary transition-colors"
              >
                VNDB
              </a>
            </span>
          </div>

          <div class="flex items-center gap-2 sm:gap-3">
            <a
              href="mailto:support@kaguya.io"
              rel="nofollow"
              class="hover:text-foreground-secondary transition-colors"
            >
              Contact
            </a>
            <span class="text-foreground-tertiary/50">·</span>
            <a
              href="https://github.com/KaguyaHQ/kaguya"
              target="_blank"
              rel="nofollow noreferrer"
              class="hover:text-foreground-secondary text-foreground-tertiary transition-colors"
              aria-label="GitHub"
            >
              <.icon_github class="h-[16px] w-[16px]" />
            </a>
            <span class="text-foreground-tertiary/50">·</span>
            <a
              href="https://discord.gg/stcK4A23jt"
              target="_blank"
              rel="nofollow noreferrer"
              class="hover:text-foreground-secondary text-foreground-tertiary transition-colors"
              aria-label="Discord"
            >
              <.icon_discord class="h-[14px] w-[18px]" />
            </a>
          </div>
        </div>
      </div>
    </footer>
    """
  end

  attr :heading, :string, required: true
  attr :links, :list, required: true

  defp column(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <span class="text-foreground-tertiary text-[10px] font-semibold tracking-[0.14em] uppercase">
        {@heading}
      </span>
      <ul class="space-y-2 text-xs sm:text-sm">
        <li :for={link <- @links}>
          <.link
            navigate={link.href}
            rel="nofollow"
            class="hover:text-foreground-primary text-foreground-secondary transition-colors"
          >
            {link.label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  attr :class, :string, default: nil

  defp icon_github(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      class={@class}
      fill="currentColor"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
    """
  end

  defp icon_discord(assigns) do
    ~H"""
    <svg
      viewBox="0 0 25 19"
      class={@class}
      fill="currentColor"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path d="M20.6222 2.46843C19.117 1.76419 17.5076 1.25237 15.825 0.960938C15.6183 1.33454 15.3769 1.83705 15.2104 2.2368C13.4218 1.9678 11.6496 1.9678 9.89379 2.2368C9.72737 1.83705 9.48047 1.33454 9.27197 0.960938C7.58754 1.25237 5.97626 1.76607 4.47106 2.47216C1.43505 7.05996 0.612043 11.5338 1.02355 15.9441C3.03719 17.4479 4.98864 18.3613 6.90717 18.9591C7.38086 18.3071 7.80333 17.6141 8.16728 16.8837C7.47413 16.6204 6.81024 16.2953 6.18294 15.918C6.34935 15.7947 6.51214 15.6658 6.66941 15.5332C10.4955 17.3227 14.6526 17.3227 18.433 15.5332C18.5921 15.6658 18.7549 15.7947 18.9195 15.918C18.2903 16.2972 17.6246 16.6222 16.9315 16.8856C17.2954 17.6141 17.7161 18.309 18.1916 18.9609C20.112 18.3632 22.0652 17.4497 24.0789 15.9441C24.5617 10.8314 23.254 6.39868 20.6222 2.46843ZM8.68853 13.2318C7.53998 13.2318 6.59808 12.1596 6.59808 10.8539C6.59808 9.54812 7.51987 8.47403 8.68853 8.47403C9.85723 8.47403 10.7991 9.54624 10.779 10.8539C10.7808 12.1596 9.85723 13.2318 8.68853 13.2318ZM16.4139 13.2318C15.2653 13.2318 14.3234 12.1596 14.3234 10.8539C14.3234 9.54812 15.2452 8.47403 16.4139 8.47403C17.5825 8.47403 18.5245 9.54624 18.5043 10.8539C18.5043 12.1596 17.5825 13.2318 16.4139 13.2318Z" />
    </svg>
    """
  end
end
