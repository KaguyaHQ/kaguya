defmodule KaguyaWeb.VN.Icons do
  @moduledoc """
  Inline SVG/star primitives shared across the VN page.

  All components are stateless function components. Components that draw an
  icon accept a `:class` attr so callers control size/color via Tailwind.
  Star renderers (`display_ratings/1`, `rating_star/1`) take a numeric
  rating and decide their own fill state from it.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Shared.DisplayRatings

  # ---------------------------------------------------------------------------
  # Reading-status icons (used inside the sidebar status segments)
  #
  # Delegates to `KaguyaWeb.VN.StatusIcons` which holds the Phosphor-Icons
  # paths. Kept as a
  # thin wrapper for backwards compatibility with existing callers; new code
  # should call `StatusIcons.status_icon/1` directly with `:weight`.
  # ---------------------------------------------------------------------------

  attr :kind, :atom, required: true

  def status_icon(assigns) do
    ~H"""
    <KaguyaWeb.VN.StatusIcons.status_icon kind={@kind} weight={:regular} class="size-[18px]" />
    """
  end

  # ---------------------------------------------------------------------------
  # Friend-activity overlay badge — switches glyph by status/review flag.
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true

  def activity_badge_icon(%{item: %{has_review: true}} = assigns) do
    ~H"""
    <svg viewBox="0 0 11 9" fill="none" class="size-[9px]" aria-hidden="true">
      <path
        d="M1 1.5h9M1 4.5h9M1 7.5h6"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "READ"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 11 9" fill="none" class="size-[9px]" aria-hidden="true">
      <path
        d="M1.5 4.5 4 7l5.5-5.5"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "CURRENTLY_READING"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 11 9" fill="none" class="size-[9px]" aria-hidden="true">
      <path
        d="M5.5 1v7M5.5 1S4.5.5 2.75.5.5 1 .5 1v7s.75-.5 2.25-.5 2.75.5 2.75.5M5.5 1s1-.5 2.75-.5S10.5 1 10.5 1v7s-.75-.5-2.25-.5-2.75.5-2.75.5"
        stroke="currentColor"
        stroke-width="1.25"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "ON_HOLD"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 6 7" fill="none" class="size-[7px]" aria-hidden="true">
      <path
        d="M1.5.75v5.5M4.5.75v5.5"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "DID_NOT_FINISH"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 7 7" fill="none" class="size-[8px]" aria-hidden="true">
      <rect
        x="0.75"
        y="0.75"
        width="5.5"
        height="5.5"
        rx="1"
        stroke="currentColor"
        stroke-width="1.5"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "WANT_TO_READ"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 7 9" fill="none" class="size-[8px]" aria-hidden="true">
      <path
        d="M1 .75h5V8L3.5 6.25 1 8z"
        stroke="currentColor"
        stroke-width="1.25"
        stroke-linecap="square"
      />
    </svg>
    """
  end

  def activity_badge_icon(%{item: %{reading_status: "NOT_INTERESTED"}} = assigns) do
    ~H"""
    <svg viewBox="0 0 7 7" fill="none" class="size-[8px]" aria-hidden="true">
      <path d="M1 1l5 5M6 1L1 6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
    </svg>
    """
  end

  def activity_badge_icon(assigns) do
    ~H"""
    <span class="size-[3px] rounded-full bg-current"></span>
    """
  end

  # ---------------------------------------------------------------------------
  # 5-star read-only display (used in review header rows + activity badges)
  # ---------------------------------------------------------------------------

  attr :rating, :any, default: nil
  attr :class, :any, default: nil
  attr :star_class, :any, default: "text-[13px] leading-none"
  attr :icon_class, :any, default: nil
  attr :empty_star_class, :any, default: nil
  attr :half_rating_class, :any, default: nil
  attr :half_rating_variant, :atom, default: :text, values: [:text, :icon]
  attr :fill_by_percentage, :boolean, default: false

  def display_ratings(assigns) do
    DisplayRatings.display_ratings(assigns)
  end

  # ---------------------------------------------------------------------------
  # Interactive 5-star input — used in the sidebar viewer-controls card.
  # ---------------------------------------------------------------------------
  #
  # Each star is a layered base/full/half stack, with two half-and-half
  # transparent buttons stacked on top. Clicking the left half submits
  # `index + 0.5`; the right half submits `index + 1.0`. No JS hook needed
  # for half-star granularity.

  attr :index, :integer, required: true
  attr :rating, :any, default: nil

  def rating_star(assigns) do
    rating = assigns.rating || 0
    full? = rating >= assigns.index + 1
    half? = !full? and rating >= assigns.index + 0.5

    assigns =
      assigns
      |> assign(
        :base_state,
        cond do
          full? -> "full"
          half? -> "half"
          true -> "empty"
        end
      )
      |> assign(:half_value, assigns.index + 0.5)
      |> assign(:full_value, assigns.index + 1.0)

    ~H"""
    <span
      data-star
      data-base-state={@base_state}
      class="group/star rating-star relative inline-block size-[27px] leading-none"
    >
      <%!-- Base: filled surface with divider stroke, matching prod's empty star (Lucide Star path). --%>
      <svg
        viewBox="0 0 24 24"
        class="absolute inset-0 size-[27px]"
        fill="rgb(var(--surface-base))"
        stroke="currentColor"
        stroke-width="1"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path
          class="text-[rgb(var(--border-divider))]"
          d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z"
        />
      </svg>
      <%!-- Full and half overlays — opacity toggled by data attributes. --%>
      <svg
        data-fill="full"
        viewBox="0 0 24 24"
        class="absolute inset-0 size-[27px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <path
          class="text-[rgb(var(--icons-user-star))]"
          d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z"
        />
      </svg>
      <span data-fill="half" class="absolute inset-y-0 left-0 w-1/2 overflow-hidden">
        <svg
          viewBox="0 0 24 24"
          class="absolute inset-y-0 left-0 size-[27px]"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            class="text-[rgb(var(--icons-user-star))]"
            d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z"
          />
        </svg>
      </span>
      <button
        type="button"
        phx-click="set_rating"
        phx-value-rating={@half_value}
        aria-label={"Rate #{rating_label(@half_value)} of 5"}
        class="absolute inset-y-0 left-0 z-10 w-1/2 cursor-pointer"
      >
      </button>
      <button
        type="button"
        phx-click="set_rating"
        phx-value-rating={@full_value}
        aria-label={"Rate #{rating_label(@full_value)} of 5"}
        class="absolute inset-y-0 right-0 z-10 w-1/2 cursor-pointer"
      >
      </button>
    </span>
    """
  end

  defp rating_label(rating), do: :erlang.float_to_binary(rating * 1.0, decimals: 1)
end
