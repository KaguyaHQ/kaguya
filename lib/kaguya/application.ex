defmodule Kaguya.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  require Cachex.Spec

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers for detailed performance logging
    Kaguya.Observability.Telemetry.attach_handlers()

    # this is global config for Req. if later added new services that also use Req,
    # revisit whether a global default is still okay.
    Req.default_options(finch: Kaguya.Finch)

    s3_host = (Application.get_env(:ex_aws, :s3) || [])[:host]

    base_pools = %{
      # catch-all for any general host (same as default Finch)
      :default => [size: 50]
    }

    pools =
      if is_binary(s3_host) do
        Map.put(base_pools, "https://#{s3_host}", size: 100, count: 2)
      else
        base_pools
      end

    children =
      [
        # PromEx must start first to capture initialization metrics
        Kaguya.Observability.PromEx,
        Kaguya.Repo,
        {Oban, Application.fetch_env!(:kaguya, Oban)},
        {DNSCluster, query: Application.get_env(:kaguya, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Kaguya.PubSub},
        {Kaguya.RateLimit, [clean_period: :timer.minutes(10), key_older_than: :timer.hours(4)]},
        # Start the Finch HTTP client for Req
        {Finch, name: Kaguya.Finch, pools: pools},
        # Pre-generated top-25 recs + VNDB username index. Populates ETS
        # from a priv/data bundle at boot. Missing files log a warning and
        # leave the tables empty so a deploy without the snapshot still
        # boots.
        Kaguya.Recommendations.PregeneratedRecs.Loader,
        cachex_child(:kaguya_cache, []),
        cachex_child(:vn_browse_cache,
          hooks: [
            Cachex.Spec.hook(
              module: Cachex.Limit.Scheduled,
              # 256 = ~20 stable explore-mode keys + headroom for tag-filter
              # traffic. Stable section keys never evict because they're
              # touched on every page view.
              args: {256, [reclaim: 0.1], [frequency: :timer.minutes(1)]}
            )
          ],
          expiration:
            Cachex.Spec.expiration(
              default: :timer.hours(24 * 7),
              interval: :timer.hours(6),
              lazy: true
            )
        ),
        cachex_child(:character_browse_cache,
          hooks: [
            Cachex.Spec.hook(
              module: Cachex.Limit.Scheduled,
              args: {100, [reclaim: 0.1], [frequency: :timer.minutes(1)]}
            )
          ],
          expiration:
            Cachex.Spec.expiration(
              default: :timer.hours(24 * 7),
              interval: :timer.hours(6),
              lazy: true
            )
        ),
        # Viewer-independent core of each VN detail page (`/vn/:slug`).
        # Keyed per VN × content-pref combo × mod visibility;
        # invalidated on writes by `KaguyaWeb.VNLive.VNPageCache`. 2_000 entries
        # ≈ a few hundred hot VNs × their bounded pref/page variants.
        cachex_child(:vn_page_cache,
          hooks: [
            Cachex.Spec.hook(
              module: Cachex.Limit.Scheduled,
              args: {2_000, [reclaim: 0.1], [frequency: :timer.minutes(1)]}
            )
          ],
          expiration:
            Cachex.Spec.expiration(
              default: :timer.hours(24 * 3),
              interval: :timer.hours(6),
              lazy: true
            )
        ),
        # Global VNDB API rate limiter (ensures ≤1 req per 1.6s across all processes)
        Kaguya.Sync.VndbRateLimiter,
        # Axiom log drain — flushes ETS buffer to Axiom ingest API
        Kaguya.Observability.AxiomLogFlusher,
        # BEAM health beacons (PROCESS_START / HEARTBEAT / MEMORY_CRITICAL)
        # shipped through the Logger pipeline → AxiomLogFlusher above.
        Kaguya.Observability.Heartbeat,
        # Start to serve requests, typically the last entry
        KaguyaWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # Register Sentry Logger Handler
    Logger.add_handlers(:kaguya)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kaguya.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, sup} ->
        maybe_warm_browse_sections()
        {:ok, sup}

      other ->
        other
    end
  end

  # Pre-populates the :vn_browse_cache entries that back the /browse explore
  # page (Most Popular, AVN, Otome, Available on itch) so the first user
  # request hits a warm cache. Fires after the supervisor is up so Repo and
  # Cachex are guaranteed ready. Disabled in test env to avoid hitting the
  # sandboxed DB from a non-test process.
  defp maybe_warm_browse_sections do
    if Application.get_env(:kaguya, :browse_cache_warm_on_boot, true) do
      Task.start(fn ->
        # Tiny grace window so the endpoint and migrations have settled.
        Process.sleep(2_000)

        try do
          {:ok, count} = Kaguya.VisualNovels.BrowseSections.warm_sync()
          Logger.info("[BrowseSections] warmed #{count} explore-mode sections")
        rescue
          e ->
            Logger.warning(
              "[BrowseSections] boot warm failed: #{Exception.message(e)} (cache will warm lazily)"
            )
        end
      end)
    end

    :ok
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KaguyaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp cachex_child(name, opts) do
    Supervisor.child_spec({Cachex, Keyword.put(opts, :name, name)}, id: name)
  end
end
