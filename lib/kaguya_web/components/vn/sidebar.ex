defmodule KaguyaWeb.VN.Sidebar do
  @moduledoc """
  Desktop sticky sidebar and the shared viewer-controls card.

  The viewer-controls card (cover + status segments + rating + action rows)
  is reused inside the mobile header — so we expose it as its own
  function component (`viewer_controls_card/1`) the mobile module can call.

  All `phx-click` events here (`set_status`, `set_rating`, `clear_status`,
  `clear_rating`, `open_review_dialog`, `open_list_dialog`) are handled in
  `KaguyaWeb.VNLive.Show`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.AuthPromptComponents, only: [auth_button: 1]
  import KaguyaWeb.UI.Menu

  import KaguyaWeb.VN.Icons
  import KaguyaWeb.VN.Formatters
  alias KaguyaWeb.SharedComponents.Cover
  alias Phoenix.LiveView.JS

  @overflow_statuses ["ON_HOLD", "DID_NOT_FINISH", "NOT_INTERESTED"]

  # ---------------------------------------------------------------------------
  # Sticky sidebar (desktop only)
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :display_vn, :map, required: true
  attr :viewer, :map, default: nil
  attr :viewer_vn, :map, default: nil
  attr :auth, :map, default: nil
  attr :current_path, :string, required: true

  def vn_sidebar(assigns) do
    assigns =
      assign(assigns, :adult_cover?, adult_cover?(assigns.display_vn) || adult_cover?(assigns.vn))

    ~H"""
    <aside class="sticky top-28 hidden h-fit lg:block">
      <%= if cover = cover_url(@display_vn) do %>
        <%!-- TODO(show.ex): no new event needed — open_media_lightbox already exists --%>
        <button
          id="vn-sidebar-cover-button"
          type="button"
          phx-click="open_media_lightbox"
          phx-value-url={cover}
          phx-value-title={@vn.title}
          aria-label={"Open #{@vn.title} cover"}
          class="group relative block w-full cursor-pointer overflow-hidden rounded-[8px] bg-transparent p-0 text-left transition outline-none focus-visible:ring-2 focus-visible:ring-[rgb(var(--foreground-primary))]/30"
        >
          <Cover.cover
            vn={@display_vn}
            sizes="220px"
            eager
            object_fit="contain"
            alt={"#{@vn.title} cover"}
            class="cursor-pointer rounded-[8px]"
            fallback_class="rounded-[8px]"
            enable_nsfw_reveal
          />
          <div
            :if={@adult_cover?}
            id="vn-sidebar-cover-reveal"
            data-nsfw-cover-reveal-overlay
            phx-click={reveal_sidebar_cover()}
            class="absolute inset-0 cursor-pointer"
            aria-hidden="true"
          >
          </div>
        </button>
      <% else %>
        <div class="aspect-2/3 w-full rounded-[8px] bg-[rgb(var(--surface-banner))]"></div>
      <% end %>

      <.viewer_controls_card
        viewer={@viewer}
        viewer_vn={@viewer_vn}
        auth={@auth}
        current_path={@current_path}
        id_prefix="sidebar"
        variant={:desktop}
        class="mt-6 rounded-[8px] border border-[rgb(var(--border-divider))]"
      />
    </aside>
    """
  end

  # ---------------------------------------------------------------------------
  # Viewer controls card — shared between sidebar and mobile header.
  # ---------------------------------------------------------------------------

  attr :viewer, :map, default: nil
  attr :viewer_vn, :map, default: nil
  attr :auth, :map, default: nil
  attr :current_path, :string, required: true
  attr :class, :string, default: nil
  attr :id_prefix, :string, default: "viewer-controls"
  attr :variant, :atom, default: :desktop

  def viewer_controls_card(assigns) do
    ~H"""
    <div class={[@class, "flex flex-col overflow-hidden"]}>
      <%!-- Controls render immediately based on `@auth` (i.e. `current_user`),
      never on the async `@viewer`. A signed-in user gets interactive controls
      at once with `@viewer_vn || %{}` as the resting state; the live values
      (rating, status, "Edit Review" vs "Review or log…") hydrate when the
      viewer bundle's `start_async` lands. Avoids a dead "Loading your account…"
      gap and the auth-prompt trap — see docs/architecture/liveview-render-staging.md. --%>
      <% signed_in? = !is_nil(@auth) %>
      <% controls_vn = @viewer_vn || %{} %>
      <.status_segments
        id={@id_prefix <> "-status-segments"}
        viewer_vn={controls_vn}
        variant={@variant}
        signed_in?={signed_in?}
        current_path={@current_path}
      />
      <.rating_row
        viewer_vn={controls_vn}
        id={@id_prefix <> "-rating-stars"}
        variant={@variant}
        signed_in?={signed_in?}
        current_path={@current_path}
      />
      <.review_or_log_button
        viewer_vn={controls_vn}
        variant={@variant}
        signed_in?={signed_in?}
        current_path={@current_path}
      />
      <.add_to_lists_button variant={@variant} signed_in?={signed_in?} current_path={@current_path} />
    </div>
    """
  end

  attr :viewer, :map, default: nil
  attr :viewer_vn, :map, default: nil
  attr :auth, :map, default: nil
  attr :class, :string, default: nil

  def mobile_action_trigger(assigns) do
    assigns =
      assigns
      |> assign(
        :trigger_label,
        mobile_trigger_label(assigns.viewer, assigns.viewer_vn, assigns.auth)
      )
      |> assign(:trigger_rating, assigns.viewer_vn && assigns.viewer_vn.my_rating)
      |> assign(:avatar_url, assigns.viewer && assigns.viewer.avatar_url)

    ~H"""
    <button
      type="button"
      phx-click="open_action_drawer"
      class={[
        "flex w-full cursor-pointer items-center justify-between rounded-[10px] border border-[rgb(var(--border-divider))]/30 bg-[rgb(var(--surface-elevated))] px-3 py-1.5 transition active:scale-[0.98]",
        @class
      ]}
    >
      <span class="flex min-w-0 items-center gap-2">
        <img
          :if={@avatar_url}
          src={@avatar_url}
          alt=""
          class="size-6 shrink-0 rounded-full object-cover"
        />
        <span class="min-w-0 truncate text-[13px] font-normal text-[rgb(var(--foreground-primary))]">
          {@trigger_label}
        </span>
        <.display_ratings
          :if={@trigger_rating && !has_review?(@viewer_vn)}
          rating={@trigger_rating}
          star_class="text-[11px] leading-none"
          class="shrink-0"
        />
      </span>
      <Lucide.ellipsis
        class="size-[18px] shrink-0 text-[rgb(var(--foreground-secondary))]"
        aria-hidden
      />
    </button>
    """
  end

  attr :viewer, :map, default: nil
  attr :viewer_vn, :map, default: nil
  attr :auth, :map, default: nil
  attr :current_path, :string, required: true

  def mobile_action_drawer(assigns) do
    ~H"""
    <%!-- TODO(show.ex): list/recommendation dialogs (if added later) should also receive the body scroll-lock JS pattern used here --%>
    <div
      class="fixed inset-0 z-120 lg:hidden"
      role="dialog"
      aria-modal="true"
      aria-labelledby="mobile-action-drawer-title"
      tabindex="-1"
      phx-mounted={Phoenix.LiveView.JS.add_class("overflow-hidden", to: "body")}
      phx-remove={Phoenix.LiveView.JS.remove_class("overflow-hidden", to: "body")}
    >
      <button
        type="button"
        phx-click="close_action_drawer"
        class="absolute inset-0 cursor-default bg-black/45"
        aria-label="Close actions"
      >
      </button>

      <div class="absolute inset-x-0 bottom-0 px-3 pb-3">
        <div class="bg-[rgb(var(--surface-base))] text-[rgb(var(--foreground-primary))] shadow-[0_-8px_10px_rgba(0,0,0,0.4)]">
          <h2 class="sr-only" id="mobile-action-drawer-title">VN actions</h2>
          <div class="flex flex-col pb-2">
            <.viewer_controls_card
              viewer={@viewer}
              viewer_vn={@viewer_vn}
              auth={@auth}
              current_path={@current_path}
              id_prefix="mobile-drawer"
              variant={:mobile}
              class="bg-transparent"
            />
            <button
              type="button"
              data-share-button
              class="flex h-12 w-full cursor-pointer items-center justify-center gap-2 border-t border-[rgb(var(--border-divider))] bg-transparent text-[13px] font-normal text-[rgb(var(--foreground-secondary))] ring-0 transition [-webkit-tap-highlight-color:transparent] hover:bg-transparent focus:bg-transparent active:bg-transparent [@media(hover:hover)]:hover:bg-[rgb(var(--surface-menu-item-hover))] [@media(hover:hover)]:active:bg-[rgb(var(--surface-menu-item-pressed))]"
            >
              Share
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Internal sub-components (signed-out, segments, rating row, action rows,
  # signed-in footer). Public so HEEx can call them locally; they are not
  # part of the page's external contract.
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :viewer_vn, :map, required: true
  attr :variant, :atom, default: :desktop
  attr :signed_in?, :boolean, default: true
  attr :current_path, :string, required: true

  def status_segments(assigns) do
    active = active_status(assigns.viewer_vn)
    overflow_active? = active in @overflow_statuses
    has_status? = is_binary(active)

    assigns =
      assigns
      |> assign(active: active)
      |> assign(overflow_active?: overflow_active?)
      |> assign(has_status?: has_status?)
      |> assign(:mobile?, assigns.variant == :mobile)
      |> assign(
        :overflow_trigger_class,
        [
          "relative flex size-8 cursor-pointer items-center justify-center rounded-full transition outline-none focus-visible:ring-2 focus-visible:ring-[rgb(var(--foreground-primary))]/30",
          overflow_active? && "text-[rgb(var(--foreground-primary))]",
          !overflow_active? &&
            "text-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-secondary))]",
          "data-[state=open]:bg-[rgb(var(--surface-menu-item-hover))]/60"
        ]
        |> Enum.filter(& &1)
        |> Enum.join(" ")
      )

    ~H"""
    <div
      id={@id}
      phx-hook="StatusSegments"
      data-active={@active || ""}
      class={[
        "flex items-start",
        @mobile? && "gap-0 px-10 pt-6 pb-4",
        !@mobile? && "gap-1 px-1.5 pt-4 pb-3"
      ]}
    >
      <.status_segment
        :for={segment <- primary_status_segments()}
        segment={segment}
        active?={@active == segment.value}
        signed_in?={@signed_in?}
        current_path={@current_path}
      />
      <.menu
        :if={@signed_in?}
        id={@id <> "-overflow-menu"}
        placement={if @mobile?, do: "bottom", else: "right"}
        align={if @mobile?, do: "end", else: "start"}
        side_offset={8}
        class={@overflow_trigger_class <> "mt-3 mr-1"}
      >
        <:trigger aria-label="More reading statuses">
          <.status_glyph kind={:more} active?={@overflow_active?} />
          <span
            :if={@overflow_active?}
            class={[
              "absolute -top-0.5 -right-0.5 size-2 rounded-full",
              overflow_indicator_class(@active)
            ]}
          >
          </span>
        </:trigger>
        <div class="w-[216px] overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-0 text-[rgb(var(--foreground-secondary))] shadow-[0_8px_30px_rgb(0,0,0,0.5)]">
          <.menu_item
            :for={segment <- overflow_status_segments()}
            event="set_status"
            value={%{status: segment.value}}
            role="menuitemradio"
            aria-checked={@active == segment.value}
            class={
              [
                "flex h-[41px] w-full cursor-pointer items-center gap-[9px] bg-[rgb(var(--surface-menu-item-default))] px-[19px] py-3 text-left text-[13px] font-normal text-[rgb(var(--foreground-secondary))] transition outline-none hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]",
                @active == segment.value && "bg-[rgb(var(--surface-menu-item-hover))]",
                status_color_class(segment.value)
              ]
              |> Enum.filter(& &1)
              |> Enum.join(" ")
            }
          >
            <span class="shrink-0 [&>svg]:size-4">
              <Lucide.circle_pause :if={segment.icon == :paused} class="size-4" aria-hidden />
              <Lucide.circle_stop
                :if={segment.icon == :did_not_finish}
                class="size-4"
                aria-hidden
              />
              <Lucide.circle_x :if={segment.icon == :not_interested} class="size-4" aria-hidden />
            </span>
            <span class="truncate text-[rgb(var(--foreground-secondary))]">{segment.label}</span>
          </.menu_item>
          <.menu_item
            :if={@has_status?}
            event="clear_status"
            role="menuitem"
            class="flex h-[41px] w-full cursor-pointer items-center gap-[9px] bg-[rgb(var(--surface-menu-item-default))] px-[19px] py-3 text-left text-[13px] font-normal text-[rgb(var(--foreground-secondary))] transition outline-none hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
          >
            <Lucide.trash_2 class="size-4 shrink-0" aria-hidden /> Remove VN
          </.menu_item>
        </div>
      </.menu>
      <.auth_button
        :if={!@signed_in?}
        event="set_status"
        is_logged_in={false}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to update your library"
        class="relative mt-3 mr-1 flex size-8 cursor-pointer items-center justify-center rounded-full text-[rgb(var(--foreground-tertiary))] transition hover:text-[rgb(var(--foreground-secondary))]"
        aria-label="Sign in to set status"
      >
        <.status_glyph kind={:more} active?={false} />
      </.auth_button>
    </div>
    """
  end

  attr :segment, :map, required: true
  attr :active?, :boolean, required: true
  attr :signed_in?, :boolean, default: true
  attr :current_path, :string, required: true

  defp status_segment(assigns) do
    ~H"""
    <%= if @signed_in? do %>
      <button
        type="button"
        phx-click="set_status"
        phx-value-status={@segment.value}
        data-status-segment={@segment.value}
        aria-pressed={if @active?, do: "true", else: "false"}
        class={[
          "flex flex-1 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-lg py-3 transition outline-none [-webkit-tap-highlight-color:transparent]",
          !@active? &&
            "hover:bg-[rgb(var(--surface-elevated))]/60"
        ]}
      >
        <span
          data-status-icon
          class={[
            @active? && status_color_class(@segment.value),
            !@active? &&
              "text-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-secondary))]"
          ]}
        >
          <.status_glyph kind={@segment.icon} active?={@active?} />
        </span>
        <span class="text-xs font-normal text-[rgb(var(--foreground-tertiary))]">
          {@segment.label}
        </span>
      </button>
    <% else %>
      <.auth_button
        event="set_status"
        is_logged_in={false}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to update your library"
        class="flex flex-1 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-lg py-3 text-[rgb(var(--foreground-tertiary))] transition outline-none [-webkit-tap-highlight-color:transparent] hover:bg-[rgb(var(--surface-elevated))]/60"
        aria-label={"Sign in to mark #{String.downcase(@segment.label)}"}
      >
        <span class="hover:text-[rgb(var(--foreground-secondary))]">
          <.status_glyph kind={@segment.icon} active?={false} />
        </span>
        <span class="text-xs font-normal text-[rgb(var(--foreground-tertiary))]">
          {@segment.label}
        </span>
      </.auth_button>
    <% end %>
    """
  end

  # Filled vs outline glyph swap on active — matches the visual weight
  # difference Phosphor's `weight="fill"` gives prod.
  attr :kind, :atom, required: true
  attr :active?, :boolean, required: true

  defp status_glyph(%{kind: :more} = assigns) do
    ~H"""
    <Lucide.ellipsis class="size-4" aria-hidden />
    """
  end

  defp status_glyph(assigns) do
    ~H"""
    <KaguyaWeb.VN.StatusIcons.status_icon
      kind={@kind}
      weight={if @active?, do: :fill, else: :regular}
      class="size-[20px]"
    />
    """
  end

  attr :viewer_vn, :map, required: true
  attr :id, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :signed_in?, :boolean, default: true
  attr :current_path, :string, required: true

  def rating_row(assigns) do
    rating = Map.get(assigns.viewer_vn, :my_rating)
    show_rating? = active_status(assigns.viewer_vn) not in ["NOT_INTERESTED", "not_interested"]

    assigns =
      assigns
      |> assign(rating: rating)
      |> assign(show_rating?: show_rating?)
      |> assign(:mobile?, assigns.variant == :mobile)

    ~H"""
    <div
      :if={@show_rating?}
      class={[
        "group/rating relative flex w-full flex-col items-center border-t border-[rgb(var(--border-divider))]",
        @mobile? &&
          "gap-0 bg-transparent py-3 [&_.rating-star]:size-[34px] [&_.rating-star_svg]:size-[34px]!",
        !@mobile? && "gap-1.5 bg-[rgb(var(--surface-elevated))]/35 px-4 py-[13px]"
      ]}
    >
      <span class={[
        "text-[13px] font-normal text-[rgb(var(--foreground-secondary))]",
        @mobile? && "mb-0.5 leading-5",
        !@mobile? && "leading-5"
      ]}>
        Rate
      </span>
      <div
        class={[
          "relative flex items-center justify-center",
          @mobile? && "py-1"
        ]}
        style={if @rating, do: nil, else: "--icons-user-star-hover: var(--icons-user-star)"}
      >
        <div
          id={@id}
          phx-hook="RatingStars"
          data-rating={@rating || ""}
          data-has-rating={if @rating, do: "true", else: "false"}
          aria-label="Set your rating"
          class="rating-stars flex items-center justify-center gap-1 max-sm:gap-2"
        >
          <.rating_star :for={i <- 0..4} index={i} rating={@rating} />
          <.auth_button
            :if={!@signed_in?}
            event="set_rating"
            is_logged_in={false}
            modal_id="vn-auth-prompt"
            auth_message="Sign in to rate visual novels"
            class="absolute inset-0 z-20 overflow-hidden text-[0px]"
            aria-label="Sign in to rate"
          >
            <span class="sr-only">Sign in to rate</span>
          </.auth_button>
        </div>
        <button
          :if={@signed_in? && @rating}
          type="button"
          phx-click="clear_rating"
          class={[
            "absolute top-1/2 z-20 flex size-[27px] -translate-y-1/2 cursor-pointer items-center justify-center rounded-full transition duration-200 hover:bg-[rgb(var(--surface-menu-item-hover))]",
            "left-[-27px] translate-x-2 opacity-0 pointer-coarse:translate-x-0 pointer-coarse:opacity-100 [@media(hover:hover)]:group-hover/rating:translate-x-0 [@media(hover:hover)]:group-hover/rating:opacity-100",
            @mobile? && "translate-x-0 opacity-100"
          ]}
          aria-label="Clear rating"
        >
          <Lucide.x
            class="size-4 text-[#667088] dark:text-[rgb(var(--foreground-tertiary))]"
            aria-hidden
          />
        </button>
      </div>
    </div>
    """
  end

  attr :viewer_vn, :map, required: true
  attr :variant, :atom, default: :desktop
  attr :signed_in?, :boolean, default: true
  attr :current_path, :string, required: true

  def review_or_log_button(assigns) do
    has_review? = !!assigns.viewer_vn[:my_review]

    assigns =
      assigns
      |> assign(has_review?: has_review?)
      |> assign(:mobile?, assigns.variant == :mobile)

    ~H"""
    <%= if @signed_in? do %>
      <button
        type="button"
        phx-click="open_review_dialog"
        class={[
          "flex w-full cursor-pointer items-center justify-center gap-2 rounded-none border-0 border-t border-[rgb(var(--border-divider))] bg-transparent text-[13px] font-normal text-[rgb(var(--foreground-secondary))] ring-0 transition [-webkit-tap-highlight-color:transparent] hover:bg-transparent focus:bg-transparent active:bg-transparent [@media(hover:hover)]:hover:bg-[rgb(var(--surface-menu-item-hover))] [@media(hover:hover)]:active:bg-[rgb(var(--surface-menu-item-pressed))]",
          @mobile? && "h-12",
          !@mobile? && "h-11"
        ]}
      >
        <%= if @has_review? do %>
          Edit Review
        <% else %>
          Review or log…
        <% end %>
      </button>
    <% else %>
      <.auth_button
        event="open_review_dialog"
        is_logged_in={false}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to write a review"
        class={[
          "flex w-full cursor-pointer items-center justify-center gap-2 rounded-none border-0 border-t border-[rgb(var(--border-divider))] bg-transparent text-[13px] font-normal text-[rgb(var(--foreground-secondary))] ring-0 transition [-webkit-tap-highlight-color:transparent] hover:bg-transparent focus:bg-transparent active:bg-transparent [@media(hover:hover)]:hover:bg-[rgb(var(--surface-menu-item-hover))] [@media(hover:hover)]:active:bg-[rgb(var(--surface-menu-item-pressed))]",
          @mobile? && "h-12",
          !@mobile? && "h-11"
        ]}
      >
        Review or log…
      </.auth_button>
    <% end %>
    """
  end

  attr :variant, :atom, default: :desktop
  attr :signed_in?, :boolean, default: true
  attr :current_path, :string, required: true

  def add_to_lists_button(assigns) do
    assigns = assign(assigns, :mobile?, assigns.variant == :mobile)

    ~H"""
    <%= if @signed_in? do %>
      <button
        type="button"
        phx-click="open_list_dialog"
        class={[
          "flex w-full cursor-pointer items-center justify-center gap-2 rounded-none border-0 border-t border-[rgb(var(--border-divider))] bg-transparent px-4 py-3 text-[13px] font-normal text-[rgb(var(--foreground-secondary))] ring-0 transition [-webkit-tap-highlight-color:transparent] hover:bg-transparent focus:bg-transparent active:bg-transparent [@media(hover:hover)]:hover:bg-[rgb(var(--surface-menu-item-hover))] [@media(hover:hover)]:active:bg-[rgb(var(--surface-menu-item-pressed))]",
          @mobile? && "h-12",
          !@mobile? && "h-11"
        ]}
      >
        Add to lists
      </button>
    <% else %>
      <.auth_button
        event="open_list_dialog"
        is_logged_in={false}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to add visual novels to lists"
        class={[
          "flex w-full cursor-pointer items-center justify-center gap-2 rounded-none border-0 border-t border-[rgb(var(--border-divider))] bg-transparent px-4 py-3 text-[13px] font-normal text-[rgb(var(--foreground-secondary))] ring-0 transition [-webkit-tap-highlight-color:transparent] hover:bg-transparent focus:bg-transparent active:bg-transparent [@media(hover:hover)]:hover:bg-[rgb(var(--surface-menu-item-hover))] [@media(hover:hover)]:active:bg-[rgb(var(--surface-menu-item-pressed))]",
          @mobile? && "h-12",
          !@mobile? && "h-11"
        ]}
      >
        Add to lists
      </.auth_button>
    <% end %>
    """
  end

  attr :viewer, :map, required: true
  attr :viewer_vn, :map, required: true
  attr :current_path, :string, required: true

  def signed_in_footer(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 border-t border-[rgb(var(--border-divider))] px-3 py-2 text-[11px] text-[rgb(var(--foreground-tertiary))]">
      <span class="truncate">
        Signed in as {@viewer.display_name || @viewer.username}
      </span>
      <.form for={%{}} action={~p"/auth/sign-out"} method="post" class="shrink-0">
        <input type="hidden" name="return_to" value={@current_path} />
        <button
          type="submit"
          class="cursor-pointer text-[11px] text-[rgb(var(--foreground-tertiary))] underline-offset-2 transition hover:text-[rgb(var(--foreground-primary))] hover:underline"
        >
          Sign out
        </button>
      </.form>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp primary_status_segments do
    [
      %{value: "WANT_TO_READ", label: "Wishlist", icon: :wishlist},
      %{value: "CURRENTLY_READING", label: "Reading", icon: :reading},
      %{value: "READ", label: "Read", icon: :read}
    ]
  end

  defp overflow_status_segments do
    [
      %{value: "ON_HOLD", label: "Paused", icon: :paused},
      %{value: "DID_NOT_FINISH", label: "Did not finish", icon: :did_not_finish},
      %{value: "NOT_INTERESTED", label: "Not interested", icon: :not_interested}
    ]
  end

  # Matches the SEGMENT_COLORS map in prod's `statusUtils.tsx` — each
  # reading status owns a distinct hue so the active segment reads at a
  # glance.
  defp status_color_class("WANT_TO_READ"), do: "text-[rgb(var(--status-wishlist))]"
  defp status_color_class("CURRENTLY_READING"), do: "text-[rgb(var(--status-reading))]"
  defp status_color_class("READ"), do: "text-[rgb(var(--status-read))]"
  defp status_color_class("ON_HOLD"), do: "text-[rgb(var(--status-paused))]"
  defp status_color_class("DID_NOT_FINISH"), do: "text-[rgb(var(--status-dnf))]"
  defp status_color_class("NOT_INTERESTED"), do: "text-[rgb(var(--status-not-interested))]"
  defp status_color_class(_), do: "text-[rgb(var(--foreground-primary))]"

  defp overflow_indicator_class("ON_HOLD"), do: "bg-[rgb(var(--status-paused))]"
  defp overflow_indicator_class("DID_NOT_FINISH"), do: "bg-[rgb(var(--status-dnf))]"
  defp overflow_indicator_class("NOT_INTERESTED"), do: "bg-[rgb(var(--status-not-interested))]"
  defp overflow_indicator_class(_), do: "bg-[rgb(var(--foreground-primary))]"

  defp active_status(%{my_reading_status: %{status: status}}) when is_binary(status), do: status
  defp active_status(_), do: nil

  defp adult_cover?(vn) when is_map(vn) do
    Map.get(vn, :is_image_nsfw) == true or Map.get(vn, :is_image_suggestive) == true
  end

  defp adult_cover?(_), do: false

  defp reveal_sidebar_cover do
    JS.set_attribute({"data-nsfw-revealed", "1"}, to: "#vn-sidebar-cover-button img")
    |> JS.remove_attribute("data-nsfw-blur", to: "#vn-sidebar-cover-button img")
    |> JS.remove_attribute("data-nsfw-reveal", to: "#vn-sidebar-cover-button img")
    |> JS.set_attribute({"hidden", "hidden"}, to: "#vn-sidebar-cover-reveal")
  end

  defp has_review?(%{my_review: %{id: id}}) when not is_nil(id), do: true
  defp has_review?(_), do: false

  defp mobile_trigger_label(nil, _viewer_vn, nil), do: "Sign in to track this"
  # Authenticated but the viewer bundle hasn't landed yet: show the resting
  # action label immediately (optimistic), not a loading placeholder. It
  # refines to the rated/reviewed/status label once `viewer_vn` hydrates.
  defp mobile_trigger_label(nil, _viewer_vn, _auth), do: "Rate, review, add to list + more"

  defp mobile_trigger_label(_viewer, %{my_review: %{id: id}}, _auth) when not is_nil(id),
    do: "You've reviewed this"

  defp mobile_trigger_label(_viewer, %{my_rating: rating}, _auth) when is_number(rating),
    do: "You've rated this"

  defp mobile_trigger_label(_viewer, viewer_vn, _auth) do
    case active_status(viewer_vn) do
      "WANT_TO_READ" -> "On your wishlist"
      "CURRENTLY_READING" -> "You're reading this"
      "READ" -> "You've finished this"
      "ON_HOLD" -> "You've put this on hold"
      "DID_NOT_FINISH" -> "You've dropped this"
      "NOT_INTERESTED" -> "Not interested"
      _ -> "Rate, review, add to list + more"
    end
  end
end
