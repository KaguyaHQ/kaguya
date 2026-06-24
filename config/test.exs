import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kaguya, Kaguya.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kaguya_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kaguya, KaguyaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FFOA71EyzfZkoBkKYFx3Hmbg2ubjLJA4uTWfIzsfR5QR8Xa1+vRFCwFb+EJxCRI+",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Route emails to the test process inbox so tests can use
# Swoosh.TestAssertions.assert_email_sent/1. Overrides the Local
# adapter set in config.exs.
config :kaguya, Kaguya.Mailer, adapter: Swoosh.Adapters.Test

# Catch LiveView misuse at runtime (e.g. missing required assigns/slots)
# that the compiler can't reach. Cheap overhead in tests.
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Stable query-param order in `~p"/foo?b=1&a=2"` (becomes `?a=2&b=1`),
# so URL string comparisons in tests don't flake on map iteration order.
config :phoenix,
  sort_verified_routes_query_params: true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :kaguya, :cors_origins, [
  "http://localhost:3000",
  "https://kaguya.io"
]

config :kaguya, Oban, testing: :manual

config :kaguya, :enable_meili_indexing, false

# Don't fire the :vn_browse_cache boot warmer in tests — it would hit the
# sandboxed Repo from a non-test process.
config :kaguya, :browse_cache_warm_on_boot, false

# Don't fire the async browse-cache re-warm (BrowseSections.refresh/warm_async)
# in tests — it spawns an unlinked Task that queries the Repo outside the test's
# sandbox ownership, leaking committed rows and poisoning other tests.
config :kaguya, :browse_cache_warm_async, false

config :kaguya, :google_req_options, plug: {Req.Test, :google_oauth}
