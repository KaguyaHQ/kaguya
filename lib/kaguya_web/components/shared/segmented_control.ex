defmodule KaguyaWeb.SharedComponents.SegmentedControl do
  @moduledoc """
  iOS-style segmented control — N mutually exclusive options sitting in a
  single rounded container, with the active segment subtly elevated above
  the container background. Hierarchy between callsites comes from `size`
  alone — the shape is always the same so the visual language stays
  consistent.

  Reach for this when the user is picking one of a small set of options
  in the same surface (Feed vs. Activity, Friends vs. Global). For
  app-level navigation across many top-level destinations, use the
  underline-tab pattern in `app_navbar` instead.
  """

  use KaguyaWeb, :html

  attr :label, :string, required: true, doc: "Accessible name for the tablist."
  attr :size, :atom, default: :md, values: [:sm, :md]
  attr :class, :any, default: nil

  slot :segment, required: true do
    attr :selected, :boolean, required: true
    attr :on_select, :any, required: true, doc: "phx-click event name or JS struct."

    attr :value, :map, doc: "Map of phx-value-* attributes — keys are atoms, values stringify."
  end

  def segmented_control(assigns) do
    ~H"""
    <div
      role="tablist"
      aria-label={@label}
      class={[
        "inline-flex items-center rounded-lg bg-white/4 p-0.5",
        @size == :md && "h-9",
        @size == :sm && "h-7",
        @class
      ]}
    >
      <button
        :for={seg <- @segment}
        type="button"
        role="tab"
        aria-selected={seg.selected}
        phx-click={seg.on_select}
        {value_attrs(seg[:value])}
        class={[
          "inline-flex h-full items-center justify-center rounded-md font-medium transition-colors",
          @size == :md && "px-4 text-sm",
          @size == :sm && "px-3 text-xs",
          if(seg.selected,
            do: "text-foreground-primary bg-white/10",
            else: "hover:text-foreground-secondary text-foreground-tertiary"
          )
        ]}
      >
        {render_slot(seg)}
      </button>
    </div>
    """
  end

  defp value_attrs(nil), do: []

  defp value_attrs(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {:"phx-value-#{k}", v} end)
  end
end
