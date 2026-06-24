import Config
import Dotenvy

if config_env() != :test do
  # Load the .env file if it exists (do not crash if missing/unreadable).
  _ = source([".env", System.get_env()])

  # Axiom log drain (ships warnings+ to Axiom for persistent, searchable logs)
  config :kaguya, :axiom,
    token: env!("AXIOM_TOKEN", :string, nil),
    dataset: env!("AXIOM_DATASET", :string, nil)

  # Sentry. nil DSN disables shipping but keeps the LoggerHandler attached
  # (dev surfaces handler errors without burning quota). SENTRY_BROWSER_DSN
  # optionally splits browser events to a separate project; falls back to SENTRY_DSN.
  sentry_dsn = env!("SENTRY_DSN", :string, nil)
  sentry_env = env!("SENTRY_ENVIRONMENT", :string, to_string(config_env()))
  sentry_release = env!("SENTRY_RELEASE", :string, nil)

  config :sentry,
    dsn: sentry_dsn,
    environment_name: sentry_env,
    release: sentry_release

  config :kaguya, :sentry_browser,
    dsn: env!("SENTRY_BROWSER_DSN", :string, sentry_dsn),
    environment: sentry_env,
    release: sentry_release
end

config :kaguya, :default_surface, "vn"

case config_env() do
  :test ->
    config :kaguya, :google_oauth,
      client_id: "google_client_test",
      client_secret: "google_secret_test",
      redirect_uri: "http://localhost:4002/auth/callback"

    config :ex_aws,
      http_client: ExAws.Request.Req,
      access_key_id: "test",
      secret_access_key: "test",
      s3: [
        scheme: "https://",
        host: "example.invalid"
      ]

    config :kaguya, :meilisearch, %{
      base_url: nil,
      master_key: nil
    }

    config :kaguya, uploads_bucket: "test"

    config :kaguya, :frontend_url, "http://localhost:3000"

  :dev ->
    # Dev boots without real secrets so a fresh clone runs `mix phx.server`
    # out of the box. Features backed by these services (R2 uploads,
    # Meilisearch, encrypted columns) stay inert until you fill in `.env`.
    # Real values are required in :prod (strict env! below).
    r2_host =
      env!("R2_ENDPOINT", :string, nil) ||
        "#{env!("R2_ACCOUNT_ID", :string, "dev-account")}.r2.cloudflarestorage.com"

    config :ex_aws,
      http_client: ExAws.Request.Req,
      access_key_id: env!("R2_APPLICATION_KEY_ID", :string, "dev"),
      secret_access_key: env!("R2_APPLICATION_KEY", :string, "dev"),
      s3: [
        scheme: "https://",
        host: r2_host
      ]

    config :kaguya, :meilisearch, %{
      base_url: env!("MEILI_BASE_URL", :string, nil),
      master_key: env!("MEILI_MASTER_KEY", :string, nil)
    }

    config :kaguya, uploads_bucket: env!("R2_BUCKET_NAME", :string, "kaguya-dev")

    config :kaguya, ssr_secret: env!("SSR_SECRET", :string, nil)

    config :kaguya, :frontend_url, env!("FRONTEND_URL", :string, "https://kaguya.io")

    config :kaguya, :google_oauth,
      client_id: env!("GOOGLE_OAUTH_CLIENT_ID", :string, nil),
      client_secret: env!("GOOGLE_OAUTH_CLIENT_SECRET", :string, nil),
      redirect_uri: env!("GOOGLE_OAUTH_REDIRECT_URI", :string, nil)

  :prod ->
    # ExAws configuration for R2 bucket. The S3 endpoint is account-scoped:
    # `<account_id>.r2.cloudflarestorage.com`. Provide the full host via
    # R2_ENDPOINT, or just the account id via R2_ACCOUNT_ID.
    r2_host =
      env!("R2_ENDPOINT", :string, nil) ||
        "#{env!("R2_ACCOUNT_ID", :string!)}.r2.cloudflarestorage.com"

    config :ex_aws,
      http_client: ExAws.Request.Req,
      access_key_id: env!("R2_APPLICATION_KEY_ID", :string!),
      secret_access_key: env!("R2_APPLICATION_KEY", :string!),
      s3: [
        scheme: "https://",
        host: r2_host
      ]

    config :kaguya, :meilisearch, %{
      base_url: env!("MEILI_BASE_URL", :string!),
      master_key: env!("MEILI_MASTER_KEY", :string!)
    }

    # Application-specific configuration
    config :kaguya,
      uploads_bucket: env!("R2_BUCKET_NAME", :string!)

    # SSR secret for rate limiting (Next.js sends this to bypass strict limits)
    config :kaguya,
      ssr_secret: env!("SSR_SECRET", :string, nil)

    config :kaguya, :frontend_url, env!("FRONTEND_URL", :string, "https://kaguya.io")

    # Google browser sign-in. Supabase remains only the Postgres host; Google
    # callbacks issue Phoenix-owned browser sessions.
    config :kaguya, :google_oauth,
      client_id: env!("GOOGLE_OAUTH_CLIENT_ID", :string, nil),
      client_secret: env!("GOOGLE_OAUTH_CLIENT_SECRET", :string, nil),
      redirect_uri: env!("GOOGLE_OAUTH_REDIRECT_URI", :string, nil)
end

# Never force server on in test.
if config_env() != :test do
  config :kaguya, KaguyaWeb.Endpoint, server: true
end

# Swoosh with Amazon SES via SMTP (for dev and prod)
if config_env() in [:dev, :prod] do
  ses_username = System.get_env("SES_SMTP_USERNAME")
  ses_password = System.get_env("SES_SMTP_PASSWORD")

  if ses_username && ses_password do
    ses_relay = System.get_env("SES_SMTP_HOST") || "email-smtp.us-east-1.amazonaws.com"

    config :kaguya, Kaguya.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: ses_relay,
      port: 587,
      username: ses_username,
      password: ses_password,
      tls: :always,
      tls_options: [
        server_name_indication: String.to_charlist(ses_relay),
        verify: :verify_peer,
        depth: 3,
        cacertfile: CAStore.file_path()
      ],
      auth: :always,
      ssl: false,
      retries: 1,
      no_mx_lookups: true
  end
end

if config_env() == :prod do
  database_url =
    env!("DATABASE_URL", :string!) ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  # inet for IPv4 (local connections to db), inet6 for IPv6
  use_ipv4 = env!("USE_IPV4", :boolean, false)
  socket_options = if use_ipv4, do: [:inet], else: [:inet6]

  database_timeout =
    case System.get_env("DATABASE_TIMEOUT") do
      nil -> :infinity
      value -> String.to_integer(value)
    end

  # database_pool_timeout =
  #   case System.get_env("DATABASE_POOL_TIMEOUT") do
  #     nil -> :infinity
  #     value -> String.to_integer(value)
  #   end

  config :kaguya, Kaguya.Repo,
    url: database_url,
    socket_options: socket_options,
    # Default to 10, consider increasing if you see POOL_WAIT logs
    pool_size: env!("DATABASE_POOL_SIZE", :integer, 10),
    # Default to 60s (60,000ms)
    timeout: database_timeout,
    # `random_page_cost = 1.5` lives in `pg_db_role_setting` on the
    # database side (`ALTER ROLE postgres SET random_page_cost = 1.5`) —
    # Supabase doesn't honor it through Postgrex's startup-message
    # `parameters:` path, so it's set at the role level instead.
    parameters: [
      application_name: env!("DATABASE_APPLICATION_NAME", :string, "kaguya_phoenix"),
      statement_timeout: "0"
    ]

  # You still need this for Phoenix internals even for API-only mode
  secret_key_base =
    env!("SECRET_KEY_BASE", :string!) ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :kaguya, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kaguya, KaguyaWeb.Endpoint,
    # Public-facing config
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # IPv6 (dual-stack, supports IPv4 too)
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      # Internal container port (8080), fronted by Caddy
      port: port
    ],
    check_origin: ["https://kaguya.io"],
    secret_key_base: secret_key_base

  # Default to info for prod
  level =
    env!("LOG_LEVEL", :string, "info")
    |> String.downcase()
    |> String.to_existing_atom()

  config :logger, level: level
end
