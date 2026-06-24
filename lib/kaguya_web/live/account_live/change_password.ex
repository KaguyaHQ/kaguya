defmodule KaguyaWeb.AccountLive.ChangePassword do
  @moduledoc """
  Legacy password route. Browser auth is magic-link only.
  """
  use KaguyaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:info, "Password login is no longer used. Sign in with your email link.")
     |> redirect(to: ~p"/account/settings")}
  end

  @impl true
  def render(assigns) do
    ~H""
  end
end
