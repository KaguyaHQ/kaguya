defmodule KaguyaWeb.Components.Profile.Nav do
  @moduledoc """
  Profile tab navigation.

  Visibility rules:
    * Reviews — hidden when `counts.reviews == 0`.
    * Lists — hidden when `counts.lists == 0` for non-owners.
    * Edits — hidden when `counts.edits == 0` for non-owners.
    * Favorites — always shown.
    * Discussions — always present (deprecated post-Feb 2026 refactor,
      route still serves an empty state for parity).

  The nav strip is hidden entirely on `/followers`, `/following`,
  `/votes/*` — these are reached from explicit links, not the tab bar.

  On non-root tabs the nav rail picks up a `bg-surface-elevated` background
  on desktop and the page leads with a compact mobile row (avatar + display
  name → back to overview).
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Shared, only: [avatar: 1]

  @links [
    {:overview, "Profile", nil},
    {:activity, "Activity", "activity"},
    {:library, "Library", "library"},
    {:reviews, "Reviews", "reviews"},
    {:discussions, "Discussions", "discussions"},
    {:lists, "Lists", "lists"},
    {:favorites, "Favorites", "favorites"},
    {:stats, "Stats", "stats"},
    {:recs, "Recs", "recs"},
    {:edits, "Edits", "edits"}
  ]

  def links, do: @links

  @doc """
  Whether the nav strip should be rendered for this tab. Followers/following
  and votes pages hide it.
  """
  def show_nav?(:followers), do: false
  def show_nav?(:following), do: false
  def show_nav?(:tag_votes), do: false
  def show_nav?(_), do: true

  attr :profile, :map, required: true, doc: "Header view-model from `Data.load_header/2`."
  attr :current_tab, :atom, required: true
  attr :root?, :boolean, default: false

  def nav(assigns) do
    ~H"""
    <%= if show_nav?(@current_tab) do %>
      <.mobile_compact_row :if={not @root?} profile={@profile} />

      <nav class={[
        "relative flex h-[33px] flex-col items-center justify-center overflow-hidden",
        "max-lg:mt-6 lg:relative lg:mx-auto lg:h-12 lg:w-full lg:max-w-[988px] lg:flex-row",
        not @root? && "lg:bg-[rgb(var(--surface-elevated))]",
        @root? && "lg:mt-5",
        not @root? && "max-lg:hidden"
      ]}>
        <%!-- Root profile bottom divider (desktop only) --%>
        <div
          :if={@root?}
          class="absolute inset-x-0 bottom-0 hidden h-px bg-[rgb(var(--border-divider))] lg:block"
        />
        <%!-- Mobile full-width bottom divider --%>
        <div class="absolute inset-x-0 bottom-0 h-px bg-[rgb(var(--border-divider))] lg:hidden" />

        <%!-- Inner-page desktop: avatar + name on the left --%>
        <.link
          :if={not @root?}
          navigate={"/@" <> @profile.username}
          class="absolute left-0 z-10 hidden h-full shrink-0 items-center gap-2 pr-3 pl-4 lg:flex"
        >
          <.avatar
            user={@profile}
            class="size-[22px] rounded-[6px] object-cover"
            sizes="22px"
          />
          <span class="text-style-body2Medium max-w-[140px] truncate text-[rgb(var(--foreground-primary))]">
            {@profile.display_name}
          </span>
        </.link>

        <div class="relative w-full lg:h-full">
          <div class={[
            "no-scrollbar flex items-center",
            "max-lg:touch-pan-x max-lg:overflow-x-auto max-lg:overscroll-x-contain max-lg:pr-4",
            "lg:h-full lg:justify-center",
            if(not @root?, do: "max-lg:pl-[100px]", else: "max-lg:pl-[12px]")
          ]}>
            <div class="flex h-full bg-transparent py-0 text-base font-normal text-[rgb(var(--foreground-primary))] max-lg:shrink-0 max-lg:gap-1 lg:gap-6">
              <%= for {tab, label, segment} <- visible_links(@profile) do %>
                <.link
                  navigate={href_for(@profile.username, segment)}
                  data-tab={tab}
                  class={[
                    "relative flex h-[33px] items-center justify-center border-b-transparent bg-transparent transition-colors",
                    "max-lg:-mb-px max-lg:shrink-0 max-lg:px-3 max-lg:py-1.5 max-lg:text-sm max-lg:font-medium max-lg:whitespace-nowrap",
                    "lg:text-style-body2Regular text-[rgb(var(--foreground-secondary))] lg:h-full lg:border-b-2 lg:px-1",
                    active_classes(tab == @current_tab, @root?)
                  ]}
                >
                  {label}
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </nav>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Mobile compact row (inner pages only)
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true

  defp mobile_compact_row(assigns) do
    ~H"""
    <div class="relative mt-4 flex h-[44px] items-center lg:hidden">
      <.link navigate={"/@" <> @profile.username} class="flex h-full items-center gap-2.5 px-4">
        <.avatar user={@profile} class="size-6 rounded-full object-cover" sizes="24px" />
        <span class="text-style-body2Medium truncate text-[rgb(var(--foreground-primary))]">
          {@profile.display_name}
        </span>
      </.link>
      <div class="absolute inset-x-0 bottom-0 h-px bg-[rgb(var(--border-divider))]" />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Link visibility + URLs
  # ---------------------------------------------------------------------------

  defp visible_links(profile) do
    counts = profile.counts || %{}
    is_mine = profile.viewer && profile.viewer.is_mine

    Enum.filter(@links, fn {tab, _, _} ->
      case tab do
        :reviews -> (counts[:reviews] || 0) > 0
        :lists -> (counts[:lists] || 0) > 0 or is_mine
        :edits -> (counts[:edits] || 0) > 0 or is_mine
        _ -> true
      end
    end)
  end

  defp href_for(username, nil), do: "/@" <> username
  defp href_for(username, segment), do: "/@" <> username <> "/" <> segment

  defp active_classes(false, _root?), do: "max-lg:text-[rgb(var(--foreground-secondary))]"

  defp active_classes(true, root?) do
    base = [
      "lg:border-[rgb(var(--button-background-brand-default))]",
      "max-lg:text-[rgb(var(--foreground-primary))]",
      "lg:text-style-body2Medium lg:text-[rgb(var(--foreground-primary))]",
      "max-lg:after:absolute max-lg:after:bottom-0 max-lg:after:left-1/4 max-lg:after:h-[4px] max-lg:after:w-1/2",
      "max-lg:after:bg-[rgb(var(--button-background-brand-default))]"
    ]

    if root?, do: base, else: base ++ ["lg:bg-[rgb(var(--surface-elevated))]"]
  end
end
