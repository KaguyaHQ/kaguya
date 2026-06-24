defmodule KaguyaWeb.Plugs.ClientIP do
  @moduledoc """
  Shared client-IP resolution for request handlers behind Cloudflare/Caddy.
  """

  import Plug.Conn

  @doc """
  Resolve the client IP from a `%Plug.Conn{}`, trying the proxy-set headers
  most likely to be trustworthy in our stack first.

  Priority: Cloudflare > X-Forwarded-For (first hop) > remote_ip.
  """
  def get(conn) do
    cf_ip = get_req_header(conn, "cf-connecting-ip") |> List.first()

    x_forwarded =
      get_req_header(conn, "x-forwarded-for")
      |> List.first()
      |> case do
        nil -> nil
        val -> val |> String.split(",") |> List.first() |> String.trim()
      end

    remote = conn.remote_ip |> :inet.ntoa() |> to_string()

    cf_ip || x_forwarded || remote
  end
end
