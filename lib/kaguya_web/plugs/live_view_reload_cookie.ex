defmodule KaguyaWeb.Plugs.LiveViewReloadCookie do
  @moduledoc """
  Clears stale LiveView reload cookies before static rendering.

  LiveView raises a generic 500 when it cannot verify this cookie, even though
  the cookie itself is the only problem. A valid cookie must still reach
  LiveView so it can return the intended HTTP status from a connected mount.
  """

  @behaviour Plug

  @cookie "__phoenix_reload_status__"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = Plug.Conn.fetch_cookies(conn)

    case Map.fetch(conn.req_cookies, @cookie) do
      {:ok, token} -> maybe_clear_invalid(conn, token)
      :error -> conn
    end
  end

  defp maybe_clear_invalid(conn, token) do
    case Phoenix.LiveView.Static.verify_token(KaguyaWeb.Endpoint, token) do
      {:ok, %{status: status}} when is_integer(status) -> conn
      _ -> clear_cookie(conn)
    end
  end

  defp clear_cookie(conn) do
    conn
    |> Plug.Conn.delete_resp_cookie(@cookie)
    |> Map.update!(:req_cookies, &Map.delete(&1, @cookie))
    |> Map.update!(:cookies, &Map.delete(&1, @cookie))
  end
end
