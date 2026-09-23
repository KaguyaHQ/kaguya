# Local production snapshots must not replay jobs or write to shared services.
oban = Application.fetch_env!(:kaguya, Oban)

Application.put_env(
  :kaguya,
  Oban,
  Keyword.merge(oban, queues: [], plugins: [], peer: false, testing: :manual)
)

Application.put_env(:kaguya, :enable_meili_indexing, false)
Application.put_env(:kaguya, :browse_cache_warm_on_boot, false)
Application.put_env(:kaguya, :browse_cache_warm_async, false)
Application.put_env(:kaguya, Kaguya.Mailer, adapter: Swoosh.Adapters.Local)
Application.put_env(:ex_aws, :access_key_id, "dev")
Application.put_env(:ex_aws, :secret_access_key, "dev")
Application.put_env(:ex_aws, :s3, scheme: "https://", host: "example.invalid")
# Pin the app to the same local target as refresh-db.py, even if the caller
# has production connection settings in its environment.
repo = Application.fetch_env!(:kaguya, Kaguya.Repo)

Application.put_env(
  :kaguya,
  Kaguya.Repo,
  repo
  |> Keyword.drop([:url, :socket_dir, :socket, :ssl])
  |> Keyword.merge(
    hostname: "127.0.0.1",
    port: 5432,
    database: "kaguya_dev2",
    username: "postgres",
    password: System.fetch_env!("KAGUYA_LOCAL_DB_PASSWORD")
  )
)

endpoint = Application.fetch_env!(:kaguya, KaguyaWeb.Endpoint)

Application.put_env(
  :kaguya,
  KaguyaWeb.Endpoint,
  Keyword.merge(endpoint, server: true, http: [ip: {127, 0, 0, 1}, port: 4001])
)

{:ok, _} = Application.ensure_all_started(:kaguya)

IO.puts(
  "Kaguya development server ready; jobs, outbound mail, search indexing and object-storage writes disabled"
)
