defmodule KaguyaWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :kaguya

  @session_max_age 60 * 60 * 24 * 90

  @session_options [
    store: :cookie,
    key: "_kaguya_key",
    signing_salt: "N50dGEEM",
    same_site: "Lax",
    max_age: @session_max_age
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :kaguya,
    gzip: not code_reloading?,
    only: KaguyaWeb.static_paths(),
    # `only:` matches the first path segment exactly, so digested top-level
    # files like `/favicon-{md5}.png?vsn=d` (emitted by `~p"/favicon.png"` in
    # prod via cache_static_manifest) get rejected. `only_matching:` does
    # prefix-match the first segment, so listing the stem `favicon` covers
    # both the bare and digested forms. See Plug.Static docs.
    only_matching: ~w(favicon),
    cache_control_for_vsn_requests: "public, max-age=31536000, immutable",
    cache_control_for_etags: "public, max-age=300, must-revalidate"

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if Application.compile_env(:kaguya, :dev_routes) do
    if Mix.env() == :dev do
      plug Tidewave
    end

    if code_reloading? do
      socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
      plug Phoenix.LiveReloader
      plug Phoenix.CodeReloader
      plug Phoenix.Ecto.CheckRepoStatus, otp_app: :kaguya
    end

    plug Phoenix.LiveDashboard.RequestLogger,
      param_key: "request_logger",
      cookie_key: "request_logger"
  end

  # Trust X-Forwarded-* headers from Caddy so conn.scheme/host/port
  # reflect the public-facing values rather than the in-container HTTP
  # on :8080. Required for OAuth redirect URLs to come out as
  # https://<host>/auth/callback instead of http://<host>:8080/...
  plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]

  # Expose /metrics for Prometheus scraping (Alloy)
  plug PromEx.Plug, prom_ex_module: Kaguya.Observability.PromEx

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.RequestId
  plug :server_timing

  # Block all requests that don't have our secret origin header which cloudflare adds through transform rules
  # plug KaguyaWeb.Plugs.VerifyOriginHeader

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 8_000_000

  plug CORSPlug,
    origin: Application.compile_env!(:kaguya, :cors_origins),
    headers: CORSPlug.defaults()[:headers] ++ ["X-Kaguya-Surface"]

  plug Sentry.PlugContext
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug KaguyaWeb.Router
  # --- define the server_timing plug below —
  defp server_timing(conn, _opts) do
    start = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      dur =
        System.convert_time_unit(System.monotonic_time() - start, :native, :millisecond)

      Plug.Conn.put_resp_header(conn, "x-app-time-ms", Integer.to_string(dur))
    end)
  end
end
