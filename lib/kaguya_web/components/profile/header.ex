defmodule KaguyaWeb.Components.Profile.Header do
  @moduledoc """
  Profile page header — banner, avatar, name, badges, action button,
  stats grid, and the tab nav strip below.

  Three shapes:
    * Root profile (`/@:username`) — full banner + avatar block + stats.
    * Inner page (`/@:username/<tab>`) — no banner/avatar; nav only.
    * Hidden-nav pages (followers, following, tag votes) — only the
      mobile compact row (handled by `Nav`).

  Each profile tab calls this component with `current_tab` set so the
  nav highlights the right entry. Optimistic follow state lives on the
  `profile.viewer.follow_state` map.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Shared,
    only: [avatar: 1, format_short_number: 1, user_badge: 1]

  import KaguyaWeb.Components.Profile.Nav, only: [nav: 1]
  import KaguyaWeb.Components.Profile.FollowButton, only: [follow_button: 1]
  import KaguyaWeb.Components.Profile.HeaderActionsMenu, only: [actions_menu: 1]

  attr :profile, :map, required: true, doc: "Header view-model from `Data.load_header/2`."
  attr :current_tab, :atom, required: true
  attr :permissions, :map, default: %{any?: false}
  attr :root?, :boolean, default: false

  attr :mod_state, :map,
    default: %{},
    doc: "Persisted mod state — drives the Suppress/Restore label in the Mod pill menu."

  def header(assigns) do
    ~H"""
    <section class={[
      "col-span-full",
      @root? && "lg:mx-auto lg:max-w-[988px]"
    ]}>
      <.banner_and_identity
        :if={@root?}
        profile={@profile}
        permissions={@permissions}
        mod_state={@mod_state}
      />
      <.nav profile={@profile} current_tab={@current_tab} root?={@root?} />
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Banner + identity block (root profile only)
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true
  attr :permissions, :map, required: true
  attr :mod_state, :map, default: %{}

  defp banner_and_identity(assigns) do
    banner = assigns.profile.banner_urls
    has_banner = (banner[:medium] || banner[:large]) != nil

    assigns =
      assigns
      |> assign(:has_banner, has_banner)
      |> assign(:show_staff, assigns.profile.role in [:admin, "admin"])

    ~H"""
    <div class="max-lg:flex max-lg:flex-col max-lg:items-center">
      <.banner profile={@profile} has_banner={@has_banner} />

      <div class="mx-auto w-full px-4 max-lg:-mt-11 lg:px-6">
        <div class="flex items-center max-lg:flex-col lg:space-x-4">
          <%!-- Avatar --%>
          <div class={[
            "relative z-20 size-[90px] rounded-full max-lg:self-start lg:size-[100px]",
            @has_banner && "shadow-[0_0_0_5px_rgb(var(--surface-base))] lg:-mt-[50px]",
            not @has_banner && "lg:size-20"
          ]}>
            <.avatar
              user={@profile}
              class="size-full rounded-full object-cover"
              size={:medium}
              sizes="(max-width: 1024px) 90px, 100px"
              fetchpriority="high"
            />
          </div>

          <%!-- Mobile action row (under avatar, top-right on banner) --%>
          <div class="-mt-9 flex items-center space-x-2 self-end lg:hidden">
            <.identity_action profile={@profile} variant={:mobile} />
            <.actions_menu
              profile={@profile}
              permissions={@permissions}
              mod_state={@mod_state}
              variant={:mobile}
            />
          </div>

          <%!-- Identity + stats --%>
          <div class="flex flex-col items-center max-lg:mt-0 max-lg:gap-2 lg:min-w-0 lg:flex-1 lg:flex-row lg:items-center lg:justify-between lg:space-x-6">
            <div class="mt-4 flex min-w-0 flex-1 flex-col gap-2 lg:mt-3 lg:gap-[3px]">
              <div class="flex min-w-0 items-center gap-2">
                <h1 class="truncate text-xl leading-[24px] font-medium text-[rgb(var(--foreground-primary))] lg:text-2xl/9 lg:font-medium">
                  {@profile.display_name}
                </h1>
                <div class="flex shrink-0 items-center gap-1">
                  <.user_badge :if={@show_staff} class="translate-y-px" />
                </div>
              </div>

              <%!-- Desktop username + inline action --%>
              <div class="flex flex-col gap-1.5 max-lg:hidden">
                <div class="flex items-center gap-[15px]">
                  <span class="text-style-body2Regular text-[rgb(var(--foreground-secondary))] lg:text-base/5 lg:font-normal">
                    @{@profile.username}
                  </span>
                  <.identity_action profile={@profile} variant={:desktop} />
                  <.actions_menu
                    profile={@profile}
                    permissions={@permissions}
                    mod_state={@mod_state}
                    variant={:desktop}
                  />
                </div>
              </div>
            </div>

            <.stats_grid profile={@profile} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Banner
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true
  attr :has_banner, :boolean, required: true

  defp banner(assigns) do
    src = assigns.profile.banner_urls[:large] || assigns.profile.banner_urls[:medium]
    src_mobile = assigns.profile.banner_urls[:medium] || src

    assigns = assigns |> assign(:src, src) |> assign(:src_mobile, src_mobile)

    ~H"""
    <div class="relative max-lg:w-full lg:overflow-hidden">
      <%= if @has_banner do %>
        <picture>
          <source media="(min-width: 1024px)" srcset={@src} />
          <img
            src={@src_mobile}
            alt="profile cover"
            width="1280"
            height="292"
            sizes="(max-width: 640px) 390px, 1280px"
            class="h-[156px] w-full object-cover lg:h-[196px]"
            fetchpriority="high"
          />
        </picture>
        <div class="pointer-events-none absolute inset-0 bg-linear-to-b from-black/0 to-black/15 max-lg:max-h-[156px]" />
      <% else %>
        <div class="h-[120px] w-full bg-[rgb(30,32,34)] lg:h-[30px] lg:bg-transparent" />
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Edit / Follow action
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true
  attr :variant, :atom, required: true, values: [:mobile, :desktop]

  defp identity_action(assigns) do
    is_mine = assigns.profile.viewer && assigns.profile.viewer.is_mine
    assigns = assign(assigns, :is_mine, is_mine)

    ~H"""
    <%= if @is_mine do %>
      <.link
        navigate="/account/edit/profile"
        class={edit_button_classes(@variant)}
      >
        Edit Profile
      </.link>
    <% else %>
      <.follow_button
        user_id={@profile.id}
        follow_state={@profile.viewer.follow_state}
        is_logged_in={@profile.viewer.is_logged_in}
        variant={:neutral_inverse}
        class={follow_button_size(@variant)}
      />
    <% end %>
    """
  end

  defp edit_button_classes(:mobile) do
    "inline-flex h-[33px] max-w-fit cursor-pointer items-center justify-center rounded-[6px] bg-button-background-neutral-inverse-default px-6 py-1.5 text-sm font-medium text-button-text-on-neutral-inverse hover:bg-button-background-neutral-inverse-hover active:bg-button-background-neutral-inverse-pressed focus:bg-button-background-neutral-inverse-hover focus:outline-hidden focus:ring-0"
  end

  defp edit_button_classes(:desktop) do
    "text-style-captionMedium inline-flex h-[26px] cursor-pointer items-center justify-center rounded-[4px] bg-button-background-neutral-inverse-default px-3 text-button-text-on-neutral-inverse hover:bg-button-background-neutral-inverse-hover active:bg-button-background-neutral-inverse-pressed focus:bg-button-background-neutral-inverse-hover focus:outline-hidden focus:ring-0"
  end

  defp follow_button_size(:mobile),
    do: "h-[33px] !min-w-0 !rounded-[6px] !px-6 !py-1.5 !text-sm !font-semibold"

  defp follow_button_size(:desktop),
    do: "text-style-captionMedium !h-[26px] !min-w-0 !rounded-[4px] !px-3 !py-0"

  # ---------------------------------------------------------------------------
  # Stats grid
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true

  defp stats_grid(assigns) do
    counts = assigns.profile.counts
    username = assigns.profile.username

    items =
      [
        {"/@#{username}/library", counts.vns || 0, "VN", "VNs", true},
        {"/@#{username}/reviews", counts.reviews || 0, "Review", "Reviews",
         (counts.reviews || 0) > 0},
        {"/@#{username}/lists", counts.lists || 0, "List", "Lists", (counts.lists || 0) > 0},
        {"/@#{username}/votes/tag", counts.tag_votes || 0, "Tag vote", "Tag votes",
         (counts.tag_votes || 0) > 0},
        {"/@#{username}/followers", counts.followers || 0, "Follower", "Followers", true},
        {"/@#{username}/following", counts.following || 0, "Following", "Following", true}
      ]
      |> Enum.filter(fn {_, _, _, _, show} -> show end)

    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="flex flex-row items-center gap-2.5 lg:gap-0">
      <%= for {{href, count, singular, plural, _show}, index} <- Enum.with_index(@items) do %>
        <span
          :if={index > 0}
          class="h-[38px] w-px bg-[rgb(var(--border-divider))] lg:mx-3 lg:h-[48px]"
        />
        <.link
          navigate={href}
          class="group flex cursor-pointer flex-col items-center gap-px lg:gap-0"
        >
          <span class="lg:text-style-proseSemibold text-lg font-semibold text-[rgb(var(--foreground-primary))] group-hover:text-[rgb(var(--text-link-hover))]">
            {format_short_number(count)}
          </span>
          <span class="lg:text-style-body2Regular text-[11px]/4 font-normal text-[rgb(var(--foreground-secondary))] group-hover:text-[rgb(var(--text-link-hover))]">
            {pluralize(count, singular, plural)}
          </span>
        </.link>
      <% end %>
    </div>
    """
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural
end
