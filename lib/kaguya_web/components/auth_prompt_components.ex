defmodule KaguyaWeb.AuthPromptComponents do
  @moduledoc """
  Shared signed-out auth prompt components.

  Callers keep their normal destination for signed-in viewers, while anonymous
  viewers get an inline prompt that preserves the current page as the login
  return target.
  """

  use KaguyaWeb, :html

  alias Phoenix.LiveView.JS

  attr :href, :string, required: true
  attr :is_logged_in, :boolean, required: true
  attr :modal_id, :string, required: true
  attr :auth_message, :string, default: "Sign in to Kaguya"
  attr :class, :any, default: nil
  attr :rel, :string, default: nil
  attr :rest, :global, include: ~w(aria-label)
  slot :inner_block, required: true

  def auth_link(assigns) do
    ~H"""
    <.link :if={@is_logged_in} navigate={@href} rel={@rel} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </.link>

    <button
      :if={!@is_logged_in}
      type="button"
      phx-click={show_auth_prompt(@modal_id, @auth_message)}
      class={@class}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :event, :string, required: true
  attr :is_logged_in, :boolean, required: true
  attr :modal_id, :string, required: true
  attr :auth_message, :string, default: "Sign in to Kaguya"
  attr :class, :any, default: nil
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(aria-label aria-pressed disabled data-confirm phx-disable-with)
  slot :inner_block, required: true

  def auth_button(assigns) do
    ~H"""
    <button
      :if={@is_logged_in}
      type={@type}
      phx-click={@event}
      class={@class}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>

    <button
      :if={!@is_logged_in}
      type="button"
      phx-click={show_auth_prompt(@modal_id, @auth_message)}
      class={@class}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :message, :string, default: "Sign in to Kaguya"
  attr :return_to, :string, default: "/"

  def auth_prompt_modal(assigns) do
    ~H"""
    <div
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={hide_auth_prompt(@id)}
      phx-key="escape"
      style="display: none"
      class="fixed inset-0 z-140 items-center justify-center bg-black/60 p-4 backdrop-blur-[2px]"
    >
      <button
        type="button"
        aria-label="Close sign-in prompt"
        phx-click={hide_auth_prompt(@id)}
        class="absolute inset-0 cursor-default"
      />

      <div class="bg-surface-base relative w-full max-w-[400px] overflow-hidden rounded-2xl border border-white/[0.07] shadow-[0_24px_64px_rgba(0,0,0,0.6)]">
        <div class="h-px bg-linear-to-r from-transparent via-[rgb(155_1_61)] to-transparent" />
        <div
          class="pointer-events-none absolute top-0 left-1/2 h-[120px] w-[320px] -translate-x-1/2"
          style="background: radial-gradient(ellipse at 50% 0%, rgba(155,1,61,0.1) 0%, transparent 70%)"
        />

        <div class="relative flex flex-col items-center px-8 pt-10 pb-8 text-center">
          <button
            type="button"
            phx-click={hide_auth_prompt(@id)}
            class="hover:text-foreground-primary text-foreground-tertiary absolute top-2 right-2 flex size-11 items-center justify-center rounded-full transition-colors hover:bg-white/6"
            aria-label="Close"
          >
            <Lucide.x class="size-3.5" aria-hidden />
          </button>

          <h2
            id={"#{@id}-title"}
            class="text-foreground-primary mb-10 text-[20px] leading-snug font-semibold"
          >
            {@message}
          </h2>

          <div class="flex w-full flex-col gap-2.5">
            <.link
              href={~p"/auth/google?return_to=#{@return_to}"}
              class="text-foreground-primary flex h-11 items-center justify-center rounded-lg border border-white/10 text-[14px] font-medium transition-colors hover:bg-white/4"
            >
              Continue with Google
            </.link>
            <.link
              href={~p"/signup?redirectTo=#{@return_to}"}
              class="bg-button-background-brand-default hover:bg-button-background-brand-hover flex h-11 items-center justify-center rounded-lg text-[14px] font-semibold text-white transition-colors"
            >
              Create an account
            </.link>
            <.link
              navigate={~p"/login?redirectTo=#{@return_to}"}
              class="text-foreground-primary flex h-11 items-center justify-center rounded-lg border border-white/10 text-[14px] font-medium transition-colors hover:bg-white/4"
            >
              Log in
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_auth_prompt(id, message \\ "Sign in to Kaguya") do
    JS.push("show_auth_prompt", value: %{message: message})
    |> JS.show(
      to: "##{id}",
      display: "flex",
      transition: {"transition ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
  end

  def hide_auth_prompt(id) do
    JS.hide(
      to: "##{id}",
      transition: {"transition ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.remove_class("overflow-hidden", to: "body")
  end
end
