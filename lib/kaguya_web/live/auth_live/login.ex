defmodule KaguyaWeb.AuthLive.Login do
  use KaguyaWeb, :live_view

  import KaguyaWeb.AuthComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(:hide_navbar, true)
     |> assign(:hide_footer, true)
     |> assign(:login_error, Phoenix.Flash.get(socket.assigns.flash, :auth_error))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_url_state(socket, params)}
  end

  defp assign_url_state(socket, params) do
    socket
    |> assign(:email, to_string(params["email"] || ""))
    |> assign(:return_to, safe_return_to(params["redirectTo"] || params["return_to"]))
    |> assign(:reset_password?, truthy?(params["reset_password"]))
    |> assign(:action, params["action"])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_shell title="Welcome back" subtitle="Log in to your Kaguya account">
      <%= cond do %>
        <% @action == "email_sent" -> %>
          <.email_sent />
        <% @reset_password? -> %>
          <.password_reset action={@action} />
        <% true -> %>
          <.auth_header title="Welcome back" subtitle="Log in to your Kaguya account" />

          <div class="mt-7 space-y-5 max-lg:mt-0">
            <.google_button return_to={@return_to} />
            <.divider />
          </div>

          <.form for={%{}} action={~p"/auth/sign-in"} method="post" class="mt-5 w-full">
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
              :if={@login_error}
              class="mt-1.5 text-[13px] leading-[16px] font-light text-[#FF5E5E]"
            >
              {@login_error}
            </p>
            <.auth_button label="Email me a sign-in link" />
          </.form>

          <div class="mt-7 flex items-center justify-center gap-1 max-lg:mt-6">
            <span class="text-foreground-tertiary text-style-body2Regular">
              Don't have an account?
            </span>
            <.link
              navigate={~p"/signup"}
              rel="nofollow"
              class="text-foreground-secondary text-style-body2Regular underline"
            >
              Sign up
            </.link>
          </div>
      <% end %>
    </.auth_shell>
    """
  end

  defp email_sent(assigns) do
    ~H"""
    <h3 class="text-foreground-primary text-[22px] leading-[27px] font-semibold lg:text-[24px] lg:leading-[29px]">
      Check your email
    </h3>
    <p class="text-foreground-tertiary mt-3 text-sm leading-[150%] font-light">
      If an account exists for that email, we've sent a sign-in link.
    </p>
    <.link
      patch={~p"/login"}
      class="bg-button-background-brand-default text-button-text-on-brand text-style-body2Medium mt-8 flex h-12 w-full items-center justify-center rounded-[8px]"
    >
      Back to login
    </.link>
    """
  end

  defp password_reset(assigns) do
    ~H"""
    <h3 class="text-foreground-primary text-[22px] leading-[27px] font-semibold lg:text-[32px] lg:leading-[39px]">
      Sign in by email
    </h3>
    <p class="text-foreground-tertiary mt-2 mb-7 text-sm leading-[150%] font-light lg:mt-3 lg:mb-6">
      Enter your email, and we'll send you a sign-in link.
    </p>
    <.form for={%{}} action={~p"/auth/reset-password"} method="post" class="w-full">
      <.auth_input
        name="email"
        label="Email"
        type="email"
        placeholder="towa@nitrochiral.com"
        autocomplete="email"
        autofocus
      />
      <.auth_button label="Email me a sign-in link" variant="brand" />
    </.form>
    """
  end

  defp truthy?(value), do: value in [true, "true", "1", "yes", ""]

  defp safe_return_to(path) when is_binary(path) and byte_size(path) > 0,
    do:
      if(String.starts_with?(path, "/") and not String.starts_with?(path, "//"),
        do: path,
        else: "/"
      )

  defp safe_return_to(_), do: "/"
end
