# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kaguya,
  ecto_repos: [Kaguya.Repo],
  generators: [
    timestamp_type: :utc_datetime,
    binary_id: true
  ]

config :kaguya, Kaguya.Repo, migration_primary_key: [name: :id, type: :binary_id]

config :kaguya, :vndb_dump,
  hostname: "localhost",
  username: "postgres",
  password: "",
  port: 5432,
  timeout: :infinity

# Nx: default backend for tensor ops. EXLA JIT-compiles `defn` functions
# through XLA (SIMD/BLAS-backed native code) — the EASE matmul in
# `Kaguya.Recommendations.Nx.Engine` is `defn` and benefits directly.
# Eager ops outside `defn` still run on the EXLA runtime (faster than
# BinaryBackend, not as fast as fused defn). Flip back to BinaryBackend
# only as a fallback if an EXLA build breaks on a target platform.
config :nx, :default_backend, EXLA.Backend

config :kaguya, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    maintenance: 1,
    stats: 1,
    exports: 1,
    import: 5,
    # `images` runs variant generation. Each job can fan out up to
    # `image_variant_concurrency` (default 3) parallel libvips ops, so
    # concurrency 3 here means up to ~9 simultaneous libvips processes
    # under heavy burst — leaves room for the request path on a 4-core box.
    # Tune up if queue depth grows under steady load.
    images: 3,
    # `recommendations` runs the Nx engine in-process against the ~500 MB
    # EASE B matrix, which lives in persistent_term. Keep concurrency at 1
    # so we never double-load the matrix on Hetzner's 4 GB box.
    recommendations: 1
    # sync: 1
  ],
  repo: Kaguya.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       # Weekly public DB dump publish to R2 (Sunday 00:00 UTC).
       # Skipped at runtime if :public_dump config isn't set (env vars
       # missing in dev). See lib/kaguya/public_dump/publisher_worker.ex.
       {"0 0 * * 0", Kaguya.PublicDump.PublisherWorker},
       # Weekly recompute (Sunday 03:10)
       {"10 3 * * 0", Kaguya.Tags.RecomputeTagRelevanceWorker},
       # Bi-weekly personalized VN recs regeneration (Mon + Thu, 04:20 UTC).
       # Uses the already-trained B matrix in priv/data/ease_B.npy — does
       # NOT retrain the matrix itself (that's an operator-triggered step).
       # Two fixed days instead of `*/3 * *` to avoid cron's month-boundary
       # reset quirk; keeps spacing at 3-4 days year-round.
       {"20 4 * * 1,4", Kaguya.Recommendations.GenerateWorker},
       # Daily VN stats snapshot refresh for active users (04:00 UTC)
       {"0 4 * * *", Kaguya.Stats.RefreshScheduler},
       # Daily site-wide stats snapshot (04:05 UTC)
       {"5 4 * * *", Kaguya.SiteStats.Worker},
       # Expire short-lived user library exports from R2.
       {"40 4 * * *", Kaguya.Exports.Workers.ExportCleanupWorker},
       # Daily sitemap refresh for user-generated surfaces.
       {"0 2 * * *", Kaguya.Sitemaps.PublisherWorker, args: %{mode: "user_content"}},
       # Weekly full sitemap refresh for low-churn catalog metadata.
       {"30 2 * * 0", Kaguya.Sitemaps.PublisherWorker, args: %{mode: "full"}}
       # Weekly VNDB sync — disabled for manual testing
       # {"0 4 * * 0", Kaguya.Sync.VndbSyncWorker}
     ]}
  ]

# Configures the endpoint
config :kaguya, KaguyaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KaguyaWeb.ErrorHTML, json: KaguyaWeb.ErrorJSON],
    layout: {KaguyaWeb.Layouts, :root}
  ],
  pubsub_server: Kaguya.PubSub,
  live_view: [signing_salt: "N50dGEEM"]

config :esbuild,
  version: "0.25.4",
  kaguya: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  list_layout_island: [
    args:
      ~w(js/list_layout_island.jsx --bundle --target=es2022 --format=esm --outfile=../priv/static/assets/js/list_layout_island.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  favorites_dnd_island: [
    args:
      ~w(js/favorites_dnd_island.jsx --bundle --target=es2022 --format=esm --outfile=../priv/static/assets/js/favorites_dnd_island.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.2.2",
  kaguya: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger. The metadata list is surfaced in console output
# and shipped to Axiom as structured columns (via `Kaguya.Observability.AxiomLogHandler`).
# Sentry's LoggerHandler also reads a subset of these keys (see config/prod.exs).
# Add new structured keys here as needed.
#
# `:default_formatter` is the modern key for OTP's built-in Logger handler;
# the legacy `:console` Logger backend was deprecated and silently ignores
# format/metadata in newer Elixir versions.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    # Observability context (request + LiveView)
    :user_id,
    :live_view,
    :live_action,
    :operation,
    :request_path,
    :resource_id,
    :resource_type,
    :critical,
    # Structured telemetry events (SLOW_QUERY, SLOW_REQ, …)
    :event_type,
    :duration_ms,
    :queue_ms,
    :query_ms,
    :total_ms,
    :idle_ms,
    :query,
    :source,
    :worker,
    :queue,
    :status,
    :method,
    :host,
    :parent_type,
    :field_name,
    :name,
    # BEAM health beacon
    :memory_mb,
    :processes_mb,
    :ets_mb,
    :binary_mb,
    :process_count,
    :port_count,
    :atom_count,
    :run_queue,
    :schedulers,
    :memory_limit_mb,
    :percent_used,
    :otp_release,
    :elixir_version,
    :pid,
    :event_id,
    :attempt,
    :count,
    :reason,
    :error,
    :result,
    :current_status,
    :target_status,
    :processed,
    :dead_letter,
    :last_reason,
    :errors,
    :ip,
    :path,
    :params
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

config :sentry,
  client: Kaguya.SentryFinchClient,
  before_send: {Kaguya.Observability.SentryFilter, :before_send}

# Swoosh mailer config (adapter configured in runtime.exs)
config :kaguya, Kaguya.Mailer, adapter: Swoosh.Adapters.Local

# Disable Swoosh API client (we use SMTP adapter)
config :swoosh, :api_client, false

# Observability config - set enabled?: false to disable all telemetry logging
config :kaguya, :observability,
  enabled?: true,
  # Override thresholds (in ms) if defaults are too noisy/quiet
  thresholds:
    %{
      # slow_request_ms: 1_000,
      # very_slow_request_ms: 10_000,
      # slow_query_ms: 500,
      # slow_checkout_ms: 200,
      # slow_api_ms: 3_000,
      # slow_job_ms: 10_000,
      # slow_resolver_ms: 100
    }
