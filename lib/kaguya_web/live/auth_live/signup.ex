defmodule KaguyaWeb.AuthLive.Signup do
  use KaguyaWeb, :live_view
  on_mount {KaguyaWeb.UserAuth, :default}

  import KaguyaWeb.AuthComponents

  @impl true
  def mount(params, session, socket) do
    params = normalize_params(params)

    return_to =
      safe_return_to(params["redirectTo"] || params["return_to"] || session["signup_return_to"])

    email = to_string(params["email"] || Map.get(session, "signup_email", ""))
    action = params["action"] || session["signup_action"]

    socket =
      socket
      |> assign(:hide_navbar, true)
      |> assign(:hide_footer, true)
      |> assign(:email, email)
      |> assign(:email_error, nil)
      |> assign(:signup_error, Phoenix.Flash.get(socket.assigns.flash, :auth_error))
      |> assign(:action, action)
      |> assign(:return_to, return_to)

    {:ok, socket}
  end

  defp normalize_params(:not_mounted_at_router), do: %{}
  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_), do: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_shell title="Get started" subtitle="Create a new account">
      <%= if @action == "confirm_email" do %>
        <.confirm_email email={@email} return_to={@return_to} signup_error={@signup_error} />
      <% else %>
        <.auth_header title="Get started" subtitle="Create a new account" />

        <div class="mt-7 space-y-5 max-lg:mt-0">
          <.google_button return_to={@return_to} />
          <.divider />
        </div>

        <.form for={%{}} action={~p"/auth/sign-up"} method="post" class="mt-5 w-full">
          <input type="hidden" name="return_to" value={@return_to} />
          <.auth_input
            name="email"
            label="Email"
            type="email"
            value={@email}
            placeholder="towa@nitrochiral.com"
            autocomplete="email"
            autofocus
          />
          <p
            :if={@signup_error}
            class="mt-1.5 text-[13px] leading-[16px] font-light text-[#FF5E5E]"
          >
            {@signup_error}
          </p>
          <.auth_button label="Email me a sign-in link" />
        </.form>

        <div class="mt-7 flex items-center justify-center gap-1 max-lg:mt-6">
          <span class="text-foreground-tertiary text-style-body2Regular">
            Already have an account?
          </span>
          <.link
            navigate={~p"/login"}
            rel="nofollow"
            class="text-foreground-secondary text-style-body2Regular underline"
          >
            Log in
          </.link>
        </div>
      <% end %>
    </.auth_shell>
    """
  end

  attr :email, :string, default: ""
  attr :return_to, :string, default: "/"
  attr :signup_error, :string, default: nil

  defp confirm_email(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <h1 class="text-foreground-primary text-style-heading1Regular max-lg:text-[22px] max-lg:leading-[27px] max-lg:font-semibold">
        Check your email
      </h1>
      <p class="text-foreground-tertiary text-style-body2Medium">
        We sent a sign-in link to <span class="text-foreground-secondary">{@email}</span>
      </p>
    </div>
    <div class="mt-11 space-y-4">
      <.form for={%{}} action={~p"/auth/resend-confirmation"} method="post">
        <input type="hidden" name="email" value={@email} />
        <input type="hidden" name="return_to" value={@return_to} />
        <p
          :if={@signup_error}
          class="mt-1.5 text-[13px] leading-[16px] font-light text-[#FF5E5E]"
        >
          {@signup_error}
        </p>
        <div class="mt-3 flex items-center justify-center gap-1">
          <span class="text-foreground-tertiary text-style-body2Regular">Didn't receive it?</span>
          <button
            id="signup-resend"
            type="submit"
            phx-hook="ResendCountdown"
            phx-update="ignore"
            class="disabled:text-foreground-quaternary text-foreground-secondary text-style-body2Regular underline disabled:cursor-not-allowed disabled:no-underline"
          >
            Resend
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"), do: path, else: "/"
  end

  defp safe_return_to(_), do: "/"
end
