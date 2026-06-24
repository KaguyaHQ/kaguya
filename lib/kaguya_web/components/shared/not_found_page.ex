defmodule KaguyaWeb.Components.Shared.NotFoundPage do
  @moduledoc """
  Full-bleed 404 page.

  A background painting of the moon scene fills the viewport; the "Return
  home" anchor is positioned over the moon at runtime by the
  `NotFoundButton` hook, which replays the natural-coordinate math so the
  button stays on the moon at every viewport size.

  Two variants:
    * `:fullscreen` — for the static 404 controller route; takes up
      `min-h-screen` inside the document flow.
    * `:overlay` — for in-LiveView use; `fixed inset-0 z-[100]` so it
      paints over the surrounding navbar/footer.
  """

  use KaguyaWeb, :html

  attr :variant, :atom, default: :fullscreen, values: [:fullscreen, :overlay]
  attr :id, :string, default: "not-found-root"

  def not_found_page(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="NotFoundButton"
      data-button-x="0.535"
      data-button-y="0.245"
      data-object-position-x="0.545"
      class={[
        @variant == :fullscreen && "relative flex min-h-screen flex-col",
        @variant == :overlay && "fixed inset-0 z-100 flex flex-col"
      ]}
    >
      <div class="absolute inset-0 overflow-hidden">
        <img
          data-not-found-img
          src="https://images.kaguya.io/ui/404.webp"
          alt="404 background"
          fetchpriority="high"
          class="size-full object-cover object-[54.5%_top]"
        />
      </div>

      <div class="absolute top-6 left-4 z-10 sm:top-10 sm:left-[8.5%]">
        <.link
          navigate="/"
          class="flex w-fit items-center gap-[5.44px] text-[#D0DAE7] sm:gap-[9px]"
        >
          <span
            class="leading-[34px] font-bold tracking-[-0.04em] max-sm:text-[14px] sm:text-[28px]"
            style="font-family: var(--font-fraunces); font-size: 28px;"
          >
            Kaguya
          </span>
        </.link>
      </div>

      <div
        data-not-found-button
        class="absolute z-10 -translate-x-1/2 opacity-0 transition-opacity duration-300"
      >
        <.link
          navigate="/"
          class={[
            "border-border-strong-divider flex h-[34px] w-fit items-center justify-center rounded-xl border",
            "bg-white/4 px-4 py-2 text-sm text-white/60 backdrop-blur-[2px]",
            "transition-all duration-300 hover:border-white/25 hover:bg-white/8",
            "hover:text-white/90 hover:shadow-[0_0_24px_rgba(255,255,255,0.06)]",
            "min-[1840px]:h-[clamp(34px,1.85vw,47px)] min-[1840px]:rounded-[clamp(12px,0.65vw,17px)]",
            "min-[1840px]:px-[clamp(16px,0.87vw,22px)] min-[1840px]:py-[clamp(8px,0.43vw,11px)]",
            "min-[1840px]:text-[clamp(14px,0.76vw,19px)]"
          ]}
        >
          Return home
        </.link>
      </div>

      <div class="relative z-10 mt-auto pb-[22px] text-center">
        <a
          href="https://kaguya.io/vn/sengoku-rance"
          class="hover:text-foreground-secondary text-foreground-quaternary text-[12px] leading-[18px]"
        >
          Art from Sengoku Rance
        </a>
      </div>
    </div>
    """
  end
end
