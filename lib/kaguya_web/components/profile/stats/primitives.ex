defmodule KaguyaWeb.Components.Profile.Stats.Primitives do
  @moduledoc """
  Shared primitive components for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  attr :title, :string, required: true
  attr :help, :string, default: nil
  attr :help_id, :string, default: nil
  attr :empty, :boolean, default: false
  slot :inner_block, required: true

  def chart_card(assigns) do
    ~H"""
    <div class="px-0 py-4 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:p-0">
      <.section_heading title={@title} help={@help} help_id={@help_id} />
      <div class={if @empty, do: nil, else: "mt-2 lg:mt-0"}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true

  attr :help, :string, default: nil
  attr :help_id, :string, default: nil

  def section_heading(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <h2 class="shrink-0 text-xl/6 font-normal text-[rgb(var(--foreground-primary))] lg:font-medium">
        {@title}
      </h2>
      <span :if={@help} id={@help_id} phx-hook="ChartHelp" class="inline-flex">
        <button
          id={@help_id <> "-trigger"}
          type="button"
          aria-label={"About " <> @title}
          aria-describedby={@help_id <> "-content"}
          popovertarget={@help_id <> "-content"}
          class="focus-visible:outline-foreground-primary hover:text-foreground-primary text-foreground-tertiary inline-flex size-7 items-center justify-center rounded-full focus-visible:outline-2"
        >
          <Lucide.info class="size-4" aria-hidden />
        </button>
        <span
          id={@help_id <> "-content"}
          popover="auto"
          phx-hook="AnchoredPopover"
          data-anchor={@help_id <> "-trigger"}
          style="visibility: hidden"
          role="tooltip"
          class="bg-surface-elevated border-border-divider text-foreground-primary fixed m-0 w-64 max-w-[calc(100vw-24px)] rounded-lg border p-3 text-sm/relaxed shadow-lg"
        >
          {@help}
        </span>
      </span>
    </div>
    <div class="mt-3 h-px bg-[rgb(var(--border-divider))] max-lg:hidden" />
    """
  end

  attr :height, :string, required: true

  def empty_chart(assigns) do
    ~H"""
    <div class={["flex items-center justify-center", @height]}>
      <p class="text-gray-400">No data available</p>
    </div>
    """
  end

  def empty_stats(assigns) do
    ~H"""
    <div class="rounded-[8px] border border-[rgb(var(--border-divider))] px-5 py-8 text-center">
      <p class="text-sm text-[rgb(var(--foreground-secondary))]">No stats yet.</p>
    </div>
    """
  end
end
