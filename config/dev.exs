import Config

# Configure your database
config :kaguya, Kaguya.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kaguya_dev2",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

port = String.to_integer(System.get_env("PORT") || "4000")

config :kaguya, KaguyaWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: port],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "eUOa6QxfYYUEHlEFBhZcESDWmZJnwlqk/nWCqAcqzSkRPcXYMzWQheJVslJ1UCTe",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:kaguya, ~w(--sourcemap=inline --watch)]},
    list_layout_island:
      {Esbuild, :install_and_run, [:list_layout_island, ~w(--sourcemap=inline --watch)]},
    favorites_dnd_island:
      {Esbuild, :install_and_run, [:favorites_dnd_island, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:kaguya, ~w(--watch)]}
  ]

# Browser auto-reload on file change. Watchers above rebuild the CSS/JS
# bundle on disk; this triggers the browser to actually pick it up.
# Without `patterns:`, `Phoenix.LiveReloader` is plugged but inert.
config :kaguya, KaguyaWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/kaguya_web/router\.ex$",
      ~r"lib/kaguya_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :kaguya, dev_routes: true

# LiveView dev affordances: HEEx file:line comments in rendered HTML,
# data-phx debug attributes, and runtime checks that catch misuse the
# compiler can't (e.g., missing required slots, bad assigns).
config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

# Configure CORS
config :kaguya, :cors_origins, ["http://localhost:3000", "https://kaguya.io"]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable meili indexing since this is prod meili
config :kaguya, :enable_meili_indexing, false

# # Enable origin header protection since this is prod API behind Cloudflare
config :kaguya, :protect_origin_header, false

# Opt-in helper to run Oban inline during debugging sessions.
if System.get_env("OBAN_INLINE") == "true" do
  config :kaguya, Oban, testing: :inline
end
