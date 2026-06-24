defmodule KaguyaWeb.Components.Profile.Placeholder do
  @moduledoc """
  Shared screens used by every profile tab while they're still stubs
  (Stream 0) and for the always-needed `:not_found` / `:loading` states.

  When a per-tab agent ships its real body it should stop calling
  `coming_soon/1`, but the `not_found/1` and `loading/1` screens stay —
  every tab uses them.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Profile.Skeletons
  alias KaguyaWeb.Components.Shared.NotFoundPage

  attr :label, :string, required: true

  def coming_soon(assigns) do
    ~H"""
    <section class="mx-auto mt-10 max-w-[988px] px-4">
      <div class="rounded-md border border-dashed border-[rgb(var(--border-divider))] p-10 text-center text-sm text-[rgb(var(--foreground-secondary))]">
        {@label} coming soon.
      </div>
    </section>
    """
  end

  def not_found(assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def loading(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 lg:px-20 lg:pb-12">
      <Skeletons.header_skeleton />
      <Skeletons.content_skeleton />
    </main>
    """
  end
end
