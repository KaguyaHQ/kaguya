defmodule KaguyaWeb.VN.Shared do
  @moduledoc """
  Cross-section layout primitives.

  Right now this is just `section_header/1` — the standard title + optional
  count + optional right-side link + thin desktop-only divider used by every
  collection/list section on the VN page.
  """

  use KaguyaWeb, :html

  attr :title, :string, required: true
  attr :count, :integer, default: nil
  attr :right_label, :string, default: nil
  attr :right_href, :string, default: nil

  def section_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
        {@title}
        <span
          :if={@count != nil}
          class="ml-0.5 text-sm font-normal text-[rgb(var(--foreground-primary))]/40"
        >
          ({@count})
        </span>
      </h2>
      <.link
        :if={@right_href}
        navigate={@right_href}
        class="text-xs font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase transition hover:text-[rgb(var(--text-link-hover))]"
      >
        {@right_label}
      </.link>
    </div>
    <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] md:block"></div>
    """
  end
end
