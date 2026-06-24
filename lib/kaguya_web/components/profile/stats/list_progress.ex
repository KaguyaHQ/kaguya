defmodule KaguyaWeb.Components.Profile.Stats.ListProgress do
  @moduledoc """
  List progress ring components for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  attr :items, :list, required: true

  def list_progress_section(assigns) do
    ~H"""
    <div
      :if={@items != []}
      class="px-0 py-4 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:p-0"
    >
      <div class="flex items-center gap-5">
        <h2 class="text-xl/6 font-normal text-[rgb(var(--foreground-primary))] lg:font-medium">
          List Progress
        </h2>
      </div>
      <div class="mt-3 h-px bg-[rgb(var(--border-divider))] max-lg:hidden" />

      <div class="mt-5 grid grid-cols-2 gap-4 lg:mt-6 lg:grid-cols-4 lg:gap-0">
        <.progress_ring :for={item <- @items} item={item} />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp progress_ring(assigns) do
    pct =
      if assigns.item.total == 0,
        do: 0,
        else: round(assigns.item.read_count / assigns.item.total * 100)

    circumference = 2 * :math.pi() * 85
    offset = circumference - pct / 100 * circumference

    assigns =
      assigns
      |> assign(:pct, pct)
      |> assign(:circumference, Float.round(circumference, 2))
      |> assign(:offset, Float.round(offset, 2))

    ~H"""
    <.link
      navigate={"/@#{@item.username}/list/#{@item.slug}"}
      class="group flex aspect-square items-center justify-center"
    >
      <div class="relative size-full max-h-[190px] max-w-[190px]">
        <svg viewBox="0 0 190 190" class="size-full -rotate-90">
          <circle cx="95" cy="95" r="80" fill="rgb(var(--surface-base))" />
          <circle
            cx="95"
            cy="95"
            r="85"
            fill="none"
            stroke="currentColor"
            stroke-width="10"
            class="text-white/8"
          />
          <circle
            cx="95"
            cy="95"
            r="85"
            fill="none"
            stroke="#00BBF9"
            stroke-width="10"
            stroke-linecap="round"
            stroke-dasharray={@circumference}
            stroke-dashoffset={@offset}
          />
        </svg>
        <div class="absolute inset-0 flex flex-col items-center justify-center px-6">
          <span class="line-clamp-2 text-center text-base/tight transition-colors group-hover:text-[rgb(var(--text-link-hover))]">
            {@item.name}
          </span>
          <span class="mt-0.5 text-[40px] leading-none font-normal text-[rgb(var(--foreground-secondary))] tabular-nums">
            {@pct}%
          </span>
          <span class="mt-1 text-sm text-[rgb(var(--foreground-quaternary))] tabular-nums">
            {@item.read_count} of {@item.total}
          </span>
        </div>
      </div>
    </.link>
    """
  end
end
