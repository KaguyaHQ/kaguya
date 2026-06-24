defmodule KaguyaWeb.Components.Profile.Stats.Primitives do
  @moduledoc """
  Shared primitive components for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  attr :title, :string, required: true
  attr :empty, :boolean, default: false
  slot :inner_block, required: true

  def chart_card(assigns) do
    ~H"""
    <div class="px-0 py-4 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:p-0">
      <.section_heading title={@title} />
      <div class={if @empty, do: nil, else: "mt-2 lg:mt-0"}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true

  def section_heading(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2">
      <h2 class="shrink-0 text-xl/6 font-normal text-[rgb(var(--foreground-primary))] lg:font-medium">
        {@title}
      </h2>
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
