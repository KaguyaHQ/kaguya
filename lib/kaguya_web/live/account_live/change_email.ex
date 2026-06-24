defmodule KaguyaWeb.AccountLive.ChangeEmail do
  @moduledoc """
  Change-email form for authenticated users. Mirrors
  `../personal/legacy-next-app/src/components/account/NewEmailForm.tsx`.

  Submission posts to `/account/update-email`. The app sends a Phoenix-owned
  verification link to the new address; `/auth/confirm` applies the change.
  """
  use KaguyaWeb, :live_view

  alias Lucideicons, as: Lucide

  @impl true
  def mount(_params, _session, socket) do
    if is_nil(socket.assigns[:current_user]) do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      {:ok,
       socket
       |> assign(:current_email, get_email(socket.assigns.current_user))
       |> assign(:page_title, "Change Email - Kaguya")
       |> assign(KaguyaWeb.SEO.noindex())
       |> assign(:form_error, Phoenix.Flash.get(socket.assigns.flash, :auth_error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-8 max-w-[502px] pb-[160px] lg:mt-16">
      <div class="flex flex-col gap-5 px-4 md:px-8 lg:gap-4">
        <h3 class="text-foreground-primary text-[22px] leading-[27px] font-semibold lg:text-[30px] lg:leading-[38px]">
          Change Email
        </h3>

        <form action={~p"/account/update-email"} method="post" class="flex flex-col">
          <input
            type="hidden"
            name="_csrf_token"
            value={Plug.CSRFProtection.get_csrf_token()}
          />
          <div class="max-lg:hidden">
            <span class="text-foreground-tertiary text-style-body2Regular mb-3 block">
              Current
            </span>
            <input
              type="email"
              disabled
              readonly
              value={@current_email}
              class="bg-text-field-bg border-text-field-border text-foreground-primary text-style-body2Regular h-12 w-full rounded-[6px] border px-3"
            />
          </div>

          <div class="flex items-center gap-2 lg:hidden">
            <div class="border-border-divider flex w-fit items-center justify-center rounded-full border bg-white/2 p-3">
              <Lucide.mail class="text-foreground-primary size-6" aria-hidden />
            </div>
            <div>
              <p class="text-foreground-primary text-base font-medium">Current</p>
              <p class="text-foreground-tertiary text-sm leading-[150%] font-light">
                {@current_email}
              </p>
            </div>
          </div>

          <div class="mt-5">
            <span class="text-foreground-tertiary text-style-body2Regular mb-3 block">
              New Email
            </span>
            <input
              name="email"
              type="email"
              placeholder="New Email"
              autocomplete="email"
              required
              class="bg-text-field-bg border-text-field-border focus-visible:border-text-field-border-focus placeholder:text-text-field-placeholder-text text-foreground-primary text-style-body2Regular h-12 w-full rounded-[6px] border px-3 transition-colors focus-visible:outline-hidden"
            />
          </div>

          <p
            :if={@form_error}
            class="mt-1.5 text-[13px] leading-[16px] font-light text-[#FF5E5E]"
          >
            {@form_error}
          </p>

          <button
            type="submit"
            class="active:bg-button-background-brand-pressed bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand mt-6 flex h-10 w-fit items-center justify-center self-end rounded-[6px] px-6 text-base leading-[22px] max-lg:font-semibold max-sm:w-full sm:font-normal lg:rounded-[8px]"
            style="text-shadow: 0px 3.04px 3.04px rgba(0, 0, 0, 0.25)"
          >
            Save
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp get_email(%{email: email}) when is_binary(email), do: email
  defp get_email(_), do: nil
end
