defmodule KaguyaWeb.SharedComponents.Badge do
  @moduledoc """
  Shared badge primitive — single place for the small inline pill labels used
  across moderation queues, profile headers, and character role pills.

  Covers the base tones (`default | secondary | destructive | outline`) and
  the profile tone palette (`developer | staff`),
  plus the moderation / status tones inline in this repo.

  Replaces:

    * `KaguyaWeb.Components.Profile.Shared.user_badge/1` (kept as a thin wrapper)
    * `moderation_live/reports.ex defp status_badge_class/1` (hex-color literals)

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 8.

  ## Examples

      <.badge tone="developer">Developer</.badge>
      <.badge tone="staff" size="sm">Staff</.badge>
      <.badge variant="outline" tone="warning">Locked</.badge>
      <.badge tone="success">Resolved</.badge>
  """

  use KaguyaWeb, :html

  attr :variant, :string,
    default: "default",
    values: ~w(default secondary destructive outline),
    doc:
      "Visual style. `default` fills with the tone color; `outline` shows just the border. `destructive` and `secondary` are kept for parity with shadcn callers."

  attr :tone, :string,
    default: "neutral",
    values: ~w(neutral developer staff success warning danger info brand),
    doc: "Semantic tone — picks the background/border/text triplet."

  attr :size, :string,
    default: "default",
    values: ~w(default xs sm lg),
    doc: "default = the `ProfileBadge` 10-px caps tag; xs/sm/lg are spacing variants."

  attr :uppercase, :boolean,
    default: true,
    doc: "Tracked uppercase typography. Match the production caps tag look."

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def badge(assigns) do
    assigns =
      assigns
      |> assign(:tone_class, tone_class(assigns.variant, assigns.tone))
      |> assign(:size_class, size_class(assigns.size))
      |> assign(:case_class, if(assigns.uppercase, do: "uppercase tracking-wide", else: nil))

    ~H"""
    <span
      class={[
        "inline-flex shrink-0 items-center rounded-[2px] font-normal",
        @size_class,
        @tone_class,
        @case_class,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Tone → class. Default variant fills; outline draws border only.
  # ---------------------------------------------------------------------------

  defp tone_class("outline", tone) do
    {_bg, border, text} = tone_palette(tone)
    "border bg-transparent #{border} #{text}"
  end

  defp tone_class(_default, tone) do
    {bg, _border, text} = tone_palette(tone)
    "#{bg} #{text}"
  end

  defp tone_palette("developer"),
    do:
      {"bg-[rgb(var(--primitives-palette-yellow-base))]",
       "border-[rgb(var(--primitives-palette-yellow-base))]",
       "text-[rgb(var(--foreground-primary))]"}

  defp tone_palette("staff"),
    do:
      {"bg-[rgb(var(--primitives-palette-neutral-700))]",
       "border-[rgb(var(--primitives-palette-neutral-700))]",
       "text-[rgb(var(--foreground-primary))]"}

  defp tone_palette("success"),
    do:
      {"bg-[rgb(var(--primitives-palette-green-base)/0.16)]",
       "border-[rgb(var(--primitives-palette-green-base)/0.45)]",
       "text-[rgb(var(--primitives-palette-green-base))]"}

  defp tone_palette("warning"),
    do:
      {"bg-[rgb(var(--primitives-palette-yellow-base)/0.16)]",
       "border-[rgb(var(--primitives-palette-yellow-base)/0.45)]",
       "text-[rgb(var(--primitives-palette-yellow-base))]"}

  defp tone_palette("danger"),
    do:
      {"bg-[rgb(var(--primitives-palette-red-base)/0.16)]",
       "border-[rgb(var(--primitives-palette-red-base)/0.45)]",
       "text-[rgb(var(--primitives-palette-red-base))]"}

  defp tone_palette("info"),
    do:
      {"bg-[rgb(var(--primitives-palette-blue-base)/0.16)]",
       "border-[rgb(var(--primitives-palette-blue-base)/0.45)]",
       "text-[rgb(var(--primitives-palette-blue-base))]"}

  defp tone_palette("brand"),
    do:
      {"bg-[rgb(var(--button-background-brand-default))]",
       "border-[rgb(var(--button-background-brand-default))]",
       "text-[rgb(var(--button-text-on-brand))]"}

  defp tone_palette(_neutral),
    do:
      {"bg-[rgb(var(--surface-elevated))]", "border-[rgb(var(--border-divider))]",
       "text-[rgb(var(--foreground-secondary))]"}

  # ---------------------------------------------------------------------------
  # Sizes
  # ---------------------------------------------------------------------------

  defp size_class("xs"), do: "px-1 py-px text-[9px] leading-[12px]"
  defp size_class("sm"), do: "px-1.5 py-0.5 text-[10px] leading-[13px]"
  defp size_class("lg"), do: "px-3 py-1 text-xs leading-[16px]"
  defp size_class(_default), do: "px-1 py-px text-[10px] leading-[13px]"
end
