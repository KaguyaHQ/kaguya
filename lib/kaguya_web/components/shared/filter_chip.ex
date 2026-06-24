defmodule KaguyaWeb.SharedComponents.FilterChip do
  @moduledoc """
  Shared generic chip / pill primitive — single place for the small
  rounded chips used across the app for applied filters (remove-me
  chips), navigation tags, and content-warning labels.

  Not to be confused with the **VN-page tag chip** specifically (name
  link + percent zone + tag-vote popover + voted-pip + warning border).
  That chip lives in `lib/kaguya_web/components/vn/header.ex`
  as `defp tag_chip/1` + `defp tag_vote_trigger/1` + `defp tag_vote_menu/1`,
  kept local because of the embedded popover. Promoting it to a shared
  module is tracked under § 10 phase 2.

  This `FilterChip` consolidates four hand-rolled "generic chip"
  implementations that were drifting on radius / padding / tones:

    * `browse_live/index_components.ex active_filter_pill_class/1`
      (rectangular chip with `:exclude` semantic-error variant)
    * `profile_live/library.ex active_filters/1` (same rectangular
      chip — visually identical, hand-rolled separately)
    * `profile_live/tag_votes.ex` per-row tag pill (smaller padding,
      content-warning border variant)
    * `recommendations/list.ex filter_chip/1` (pill-shape variant for
      the recommender's "Wishlisted hidden" / "Selected tag" chips)

  ## API

      <.filter_chip label="Slice of Life" />
      <.filter_chip label="Wishlist" tone="exclude" href="/browse" />
      <.filter_chip label="Spoiler" tone="warning" size="sm" />
      <.filter_chip label="Wishlisted hidden" shape="pill" phx-click="clear" />

  ## Shape × tone

  Two visual shapes, each with multiple tones:

  * `shape="default"` (rectangular `rounded-[4px]`) — browse / library /
    tag-votes pages. Tones map to `:neutral` (chip-border), `:exclude`
    (semantic-error tinted), `:warning` (chip-border-warning).
  * `shape="pill"` (`rounded-full`) — recommendations filters. Single
    tone (neutral).

  The chip is rendered as `<.link href={...}>` when an `:href` /
  `:patch` / `:navigate` attr is set, otherwise as `<button phx-click>`.
  Pass either a textual `:label` or use the inner block for richer
  content.
  """

  use KaguyaWeb, :html

  attr :label, :string,
    default: nil,
    doc: "Chip text. Either `:label` or `:inner_block` is required."

  attr :shape, :string,
    default: "default",
    values: ~w(default pill)

  attr :tone, :string,
    default: "neutral",
    values: ~w(neutral exclude warning)

  attr :size, :string,
    default: "default",
    values: ~w(default sm),
    doc: "`default` for browse-style (px-2 py-1); `sm` for tag-votes-style (px-1.5 py-[1px])."

  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil

  attr :icon_x, :boolean,
    default: false,
    doc: "Append the `×` clear icon (active-filter pattern)."

  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-value-key phx-value-slug phx-value-id title aria-label rel)

  slot :inner_block

  def filter_chip(assigns) do
    assigns =
      assigns
      |> assign(:shape_class, shape_class(assigns.shape, assigns.size))
      |> assign(:tone_class, tone_class(assigns.shape, assigns.tone))

    cond do
      assigns.navigate || assigns.patch ->
        ~H"""
        <.link
          navigate={@navigate}
          patch={@patch}
          class={[@shape_class, @tone_class, @class]}
          {@rest}
        >
          <.chip_body label={@label} icon_x={@icon_x}>{render_slot(@inner_block)}</.chip_body>
        </.link>
        """

      assigns.href ->
        ~H"""
        <a href={@href} class={[@shape_class, @tone_class, @class]} {@rest}>
          <.chip_body label={@label} icon_x={@icon_x}>{render_slot(@inner_block)}</.chip_body>
        </a>
        """

      true ->
        ~H"""
        <button type="button" class={[@shape_class, @tone_class, @class]} {@rest}>
          <.chip_body label={@label} icon_x={@icon_x}>{render_slot(@inner_block)}</.chip_body>
        </button>
        """
    end
  end

  attr :label, :string, default: nil
  attr :icon_x, :boolean, required: true
  slot :inner_block

  defp chip_body(assigns) do
    ~H"""
    <span class="pointer-events-none truncate">{@label || render_slot(@inner_block)}</span>
    <Lucide.x
      :if={@icon_x}
      class="group-hover:text-foreground-primary text-foreground-tertiary size-3 shrink-0 transition-colors duration-150"
      aria-hidden
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Shape × size
  # ---------------------------------------------------------------------------

  defp shape_class("pill", "sm"),
    do:
      "group inline-flex h-6 cursor-pointer items-center gap-1 whitespace-nowrap rounded-full pr-1.5 pl-2.5 text-[10px] font-normal transition-colors duration-150"

  defp shape_class("pill", _),
    do:
      "group inline-flex h-6 cursor-pointer items-center gap-1 whitespace-nowrap rounded-full pr-1.5 pl-2.5 text-[11px] font-normal transition-colors duration-150"

  defp shape_class(_default, "sm"),
    do:
      "group inline-flex cursor-pointer items-center gap-1 whitespace-nowrap rounded-[3px] border px-1.5 py-[1px] text-xs font-normal transition-colors duration-150"

  defp shape_class(_default, _),
    do:
      "group inline-flex cursor-pointer items-center gap-1 whitespace-nowrap rounded-[4px] border px-2 py-1 text-xs font-normal transition-colors duration-150"

  # ---------------------------------------------------------------------------
  # Tone — picks border + text + (optional) bg
  # ---------------------------------------------------------------------------

  defp tone_class("pill", _tone),
    do:
      "border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-secondary))] hover:border-[rgb(var(--foreground-tertiary)/0.6)] hover:text-[rgb(var(--foreground-primary))]"

  defp tone_class(_default, "exclude"),
    do:
      "border-semantic-error/40 bg-semantic-error/[.06] text-foreground-primary hover:border-semantic-error/60"

  defp tone_class(_default, "warning"),
    do:
      "border-chip-border-warning-default text-foreground-secondary hover:border-chip-border-warning-hover hover:text-foreground-primary"

  defp tone_class(_default, _neutral),
    do:
      "border-[rgb(var(--chip-border-default))] text-foreground-primary hover:border-[rgb(var(--chip-border-hover))]"
end
