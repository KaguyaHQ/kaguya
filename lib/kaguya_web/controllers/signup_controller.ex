defmodule KaguyaWeb.SignupController do
  @moduledoc """
  Dispatches `/signup` to either the signup form (`KaguyaWeb.AuthLive.Signup`)
  or the post-signup wizard (`KaguyaWeb.AuthLive.AccountSetup`) based on the
  `action` query param, while preserving the URL.

  This mirrors the Next.js production app at `../personal/legacy-next-app/src/app/(auth)/signup/page.tsx`,
  where `/signup?action=account_setup` is the canonical onboarding URL that
  Phoenix magic-link confirmations redirect to.

  Each target LiveView declares its own `on_mount {KaguyaWeb.UserAuth, :default}`
  hook since we're rendering them from a controller instead of inside the
  `live_session :default` router block.
  """
  use KaguyaWeb, :controller

  alias Phoenix.LiveView.Controller, as: LiveView

  # Mount params arrive as `:not_mounted_at_router` when a LiveView is rendered
  # from a controller. Forward the query params via the session so the LV can
  # pull `return_to`, `redirectTo`, and `action` without having to special-case
  # the sentinel everywhere. Merged into (rather than replacing) the existing
  # HTTP session so callers that pre-seed `signup_email`/`signup_return_to`
  # still take effect.
  def index(conn, %{"action" => "account_setup"} = params) do
    LiveView.live_render(conn, KaguyaWeb.AuthLive.AccountSetup,
      session: build_session(conn, params)
    )
  end

  def index(conn, params) do
    LiveView.live_render(conn, KaguyaWeb.AuthLive.Signup, session: build_session(conn, params))
  end

  defp build_session(conn, params) do
    conn
    |> Plug.Conn.get_session()
    |> Map.merge(
      prune_nils(%{
        "signup_return_to" =>
          params["return_to"] || params["redirectTo"] ||
            Plug.Conn.get_session(conn, "signup_return_to"),
        "signup_action" => params["action"]
      })
    )
  end

  defp prune_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)
end
