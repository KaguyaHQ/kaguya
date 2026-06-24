defmodule KaguyaWeb.AuthComponents do
  @moduledoc false

  use KaguyaWeb, :html

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :mobile_title, :string, default: nil
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <div class="bg-surface-base text-foreground-primary min-h-screen">
      <div class="flex min-h-screen max-lg:hidden">
        <section class="relative flex flex-1 justify-center px-[136px]">
          <div class="absolute top-0 mt-6 w-full px-8">
            <nav class="relative flex items-center">
              <.logo small />
            </nav>
          </div>
          <div class="w-full max-w-[386px] pt-[172px]">
            {render_slot(@inner_block)}
          </div>
        </section>

        <aside class="relative w-[54.3%] overflow-hidden">
          <img
            src="https://images.kaguya.io/ui/auth/auth.webp"
            alt="featured cover"
            class="absolute inset-0 size-full object-cover object-[8.5%]"
          />
          <a
            href="https://kaguya.io/vn/witch-on-the-holy-night"
            target="_blank"
            class="hover:text-foreground-secondary text-foreground-tertiary absolute bottom-[23px] left-1/2 z-10 -translate-x-1/2 text-sm font-medium"
          >
            Art from Mahoyo
          </a>
          <div class="absolute inset-0 bg-black/25" />
        </aside>
      </div>

      <div class="mt-8 flex h-full items-center lg:hidden">
        <div class="flex w-full px-5 pb-14 sm:flex-col sm:items-center md:px-24">
          <div class="max-h-full w-full sm:max-w-sm">
            <.logo class="mb-14" />
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true

  def auth_header(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 max-lg:gap-0">
      <h1 class="text-foreground-primary text-style-heading1Regular max-lg:text-[22px] max-lg:leading-[27px] max-lg:font-normal">
        {@title}
      </h1>
      <p class="text-foreground-tertiary text-style-body2Medium max-lg:mt-3 max-lg:mb-9">
        {@subtitle}
      </p>
    </div>
    """
  end

  attr :return_to, :string, default: "/"

  def google_button(assigns) do
    ~H"""
    <.link
      href={~p"/auth/google?return_to=#{@return_to}"}
      class="bg-text-field-bg border-text-field-border hover:border-text-field-border-focus text-foreground-primary text-style-body2Medium flex h-12 w-full items-center justify-center gap-4 rounded-[6px] border shadow-none"
    >
      <.google_icon class="size-5" /> Continue with Google
    </.link>
    """
  end

  attr :class, :string, default: nil

  defp google_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 18 18" class={@class} aria-hidden="true">
      <path
        fill="#4285F4"
        d="M17.64 9.205c0-.639-.057-1.252-.164-1.841H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.258h2.908c1.702-1.566 2.684-3.874 2.684-6.614Z"
      />
      <path
        fill="#34A853"
        d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.345 0-4.33-1.584-5.038-3.71H.957v2.332A9 9 0 0 0 9 18Z"
      />
      <path
        fill="#FBBC05"
        d="M3.962 10.71A5.41 5.41 0 0 1 3.68 9c0-.593.102-1.17.282-1.71V4.958H.957A8.998 8.998 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.005-2.332Z"
      />
      <path
        fill="#EA4335"
        d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A9 9 0 0 0 .957 4.958L3.962 7.29C4.67 5.163 6.655 3.58 9 3.58Z"
      />
    </svg>
    """
  end

  def divider(assigns) do
    ~H"""
    <div class="flex items-center">
      <div class="bg-border-divider h-px flex-1" />
      <span class="text-foreground-secondary text-style-body2Regular px-2.5">or</span>
      <div class="bg-border-divider h-px flex-1" />
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :value, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :autofocus, :boolean, default: false
  attr :maxlength, :integer, default: nil
  attr :input_class, :any, default: nil

  def auth_input(assigns) do
    ~H"""
    <label class="block">
      <span class="text-foreground-tertiary text-style-body2Regular mb-3 block">{@label}</span>
      <input
        name={@name}
        type={@type}
        value={@value}
        placeholder={@placeholder}
        autocomplete={@autocomplete}
        autofocus={@autofocus}
        maxlength={@maxlength}
        class={[
          "bg-text-field-bg border-text-field-border focus-visible:border-text-field-border-focus placeholder:text-text-field-placeholder-text text-foreground-primary text-style-body2Regular h-12 w-full rounded-[6px] border px-3 focus-visible:outline-none",
          @input_class
        ]}
      />
    </label>
    """
  end

  attr :label, :string, required: true
  attr :disabled, :boolean, default: false
  attr :variant, :string, default: "inverse"

  def auth_button(assigns) do
    class =
      if assigns.variant == "brand" do
        "bg-button-background-brand-default text-button-text-on-brand hover:bg-button-background-brand-hover"
      else
        "bg-button-background-neutral-inverse-default text-button-text-on-neutral-inverse hover:bg-button-background-neutral-inverse-hover"
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <button
      type="submit"
      disabled={@disabled}
      class={[
        "text-style-body2Medium mt-[30px] h-12 w-full rounded-[8px] disabled:opacity-60",
        @class
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :message, :string, default: nil

  def error(assigns) do
    ~H"""
    <p :if={@message} class="mt-1.5 text-[13px] leading-[16px] font-light text-[#FF5E5E]">
      {@message}
    </p>
    """
  end

  attr :class, :string, default: nil
  attr :small, :boolean, default: false

  def logo(assigns) do
    ~H"""
    <.link
      navigate="/"
      class={["text-foreground-primary flex w-fit items-center gap-[5.44px] sm:gap-[9px]", @class]}
    >
      <span
        class={[
          "font-semibold tracking-[-0.04em]",
          if(@small,
            do: "text-[22px] leading-[26px]",
            else: "text-[20px] leading-[24px] sm:text-[28px] sm:leading-[34px]"
          )
        ]}
        style="font-family: var(--font-fraunces)"
      >
        Kaguya
      </span>
    </.link>
    """
  end
end
