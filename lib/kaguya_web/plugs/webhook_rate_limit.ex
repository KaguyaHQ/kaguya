defmodule KaguyaWeb.Plugs.WebhookRateLimit do
  @moduledoc "IP-based rate limiting for webhook endpoints."

  import Plug.Conn
  require Logger

  alias KaguyaWeb.Plugs.ClientIP

  @minute_ms 60_000
  @limit 120

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = ClientIP.get(conn)

    case Kaguya.RateLimit.hit("webhook:#{ip}", @minute_ms, @limit) do
      {:allow, _} ->
        conn

      {:deny, _retry_ms} ->
        Logger.warning("Webhook rate limit exceeded", ip: ip, path: conn.request_path)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Too many requests"}))
        |> halt()
    end
  end
end
