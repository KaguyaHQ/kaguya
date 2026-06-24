defmodule Kaguya.Observability.Telemetry do
  @moduledoc """
  Telemetry handlers for detailed slow request logging.

  Enable/disable via config:
    config :kaguya, :observability, enabled?: true

  When you see a spike in Grafana, search Axiom logs at that timestamp
  for SLOW_REQ, SLOW_QUERY, POOL_WAIT, or SLOW_API to see exactly what happened.

  Logs include the container hostname for correlation.

  Thresholds (configurable):
  - Requests > 1s logged as SLOW_REQ
  - Requests > 10s logged as VERY_SLOW_REQ
  - DB queries > 500ms logged as SLOW_QUERY
  - Pool checkout wait > 200ms logged as POOL_WAIT
  - External API calls > 3s logged as SLOW_API
  - Oban jobs > 10s logged as SLOW_JOB
  - LiveView mount/handle_params > 200ms logged as SLOW_LV_*
  """

  require Logger

  # Thresholds - can be overridden via config :kaguya, :observability, thresholds: [...]
  @default_thresholds %{
    slow_request_ms: 1_000,
    very_slow_request_ms: 10_000,
    slow_query_ms: 500,
    slow_checkout_ms: 200,
    slow_api_ms: 3_000,
    slow_job_ms: 10_000,
    slow_lv_mount_ms: 200
  }

  def attach_handlers do
    if enabled?() do
      handlers = [
        # Ecto query timing
        {"kaguya-ecto-query", [:kaguya, :repo, :query], &__MODULE__.handle_query/4},

        # Phoenix request timing
        {"kaguya-phoenix-stop", [:phoenix, :endpoint, :stop], &__MODULE__.handle_request_stop/4},

        # Finch HTTP client for external API calls
        {"kaguya-finch-stop", [:finch, :request, :stop], &__MODULE__.handle_finch_stop/4},
        {"kaguya-finch-exception", [:finch, :request, :exception],
         &__MODULE__.handle_finch_exception/4},

        # Oban job timing
        {"kaguya-oban-stop", [:oban, :job, :stop], &__MODULE__.handle_oban_stop/4},
        {"kaguya-oban-exception", [:oban, :job, :exception], &__MODULE__.handle_oban_exception/4},

        # LiveView mount/handle_params timing — Phoenix endpoint :stop doesn't
        # fire for socket-mounted LiveViews, so the standard SLOW_REQ telemetry
        # misses navigation inside a LiveView. Capture mount + handle_params
        # durations here.
        {"kaguya-live-view-mount-stop", [:phoenix, :live_view, :mount, :stop],
         &__MODULE__.handle_live_view_stop/4},
        {"kaguya-live-view-handle-params-stop", [:phoenix, :live_view, :handle_params, :stop],
         &__MODULE__.handle_live_view_stop/4},

        # LiveView lifecycle exceptions — Sentry.PlugCapture doesn't see
        # LV crashes because they happen inside a GenServer, not a Plug.
        {"kaguya-live-view-mount-exception", [:phoenix, :live_view, :mount, :exception],
         &__MODULE__.handle_live_view_exception/4},
        {"kaguya-live-view-handle-params-exception",
         [:phoenix, :live_view, :handle_params, :exception],
         &__MODULE__.handle_live_view_exception/4},
        {"kaguya-live-view-handle-event-exception",
         [:phoenix, :live_view, :handle_event, :exception],
         &__MODULE__.handle_live_view_exception/4},
        {"kaguya-live-component-handle-event-exception",
         [:phoenix, :live_component, :handle_event, :exception],
         &__MODULE__.handle_live_view_exception/4}
      ]

      Enum.each(handlers, fn {id, event, handler} ->
        :telemetry.detach(id)
        :telemetry.attach(id, event, handler, nil)
      end)

      Logger.info("[Telemetry] Observability enabled | host=#{hostname()}")
    else
      Logger.info("[Telemetry] Observability disabled via config")
      :ok
    end
  end

  def enabled? do
    Application.get_env(:kaguya, :observability, [])
    |> Keyword.get(:enabled?, true)
  end

  def threshold(key) do
    custom = Application.get_env(:kaguya, :observability, []) |> Keyword.get(:thresholds, %{})
    Map.get(custom, key) || Map.fetch!(@default_thresholds, key)
  end

  # ============================================================================
  # Ecto Query Handler
  # ============================================================================

  def handle_query(_event, measurements, metadata, _config) do
    query_ms = to_ms(Map.get(measurements, :query_time, 0))
    queue_ms = to_ms(Map.get(measurements, :queue_time, 0))
    total_ms = to_ms(Map.get(measurements, :total_time, 0))
    idle_ms = to_ms(Map.get(measurements, :idle_time, 0))

    if queue_ms > threshold(:slow_checkout_ms) do
      Logger.warning("pool wait",
        event_type: "POOL_WAIT",
        duration_ms: queue_ms,
        queue_ms: queue_ms,
        query_ms: query_ms,
        idle_ms: idle_ms,
        source: to_string(metadata.source),
        request_id: request_id()
      )
    end

    if query_ms > threshold(:slow_query_ms) do
      Logger.warning("slow query",
        event_type: "SLOW_QUERY",
        duration_ms: query_ms,
        queue_ms: queue_ms,
        source: to_string(metadata.source),
        query: truncate(metadata.query, 500),
        # Include total for parity with the old free-text format
        total_ms: total_ms,
        request_id: request_id()
      )
    end
  rescue
    e -> log_handler_crash("kaguya-ecto-query", e)
  end

  # ============================================================================
  # Phoenix Request Handler
  # ============================================================================

  def handle_request_stop(_event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    conn = metadata.conn

    # Skip metrics endpoint
    if conn.request_path == "/metrics" do
      :ok
    else
      cond do
        ms > threshold(:very_slow_request_ms) ->
          Logger.error("very slow request",
            event_type: "VERY_SLOW_REQ",
            duration_ms: ms,
            method: conn.method,
            request_path: conn.request_path,
            status: conn.status,
            request_id: conn.assigns[:request_id]
          )

        ms > threshold(:slow_request_ms) ->
          Logger.warning("slow request",
            event_type: "SLOW_REQ",
            duration_ms: ms,
            method: conn.method,
            request_path: conn.request_path,
            status: conn.status,
            request_id: conn.assigns[:request_id]
          )

        true ->
          :ok
      end
    end
  rescue
    e -> log_handler_crash("kaguya-phoenix-stop", e)
  end

  # ============================================================================
  # LiveView Mount / handle_params Timing Handler
  # ============================================================================
  #
  # Telemetry payload (Phoenix 1.7+):
  #   measurements: %{duration: native}
  #   metadata: %{socket: %Phoenix.LiveView.Socket{}, params: map(), uri: String.t() | nil}
  #
  # The endpoint :stop telemetry only fires for HTTP requests through the
  # Plug pipeline. LiveView events (live_redirect / live_patch / push events)
  # never hit the pipeline once the socket is established, so a slow
  # `mount/3` or `handle_params/3` is invisible to SLOW_REQ. This handler
  # closes that gap.

  def handle_live_view_stop(event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if ms > threshold(:slow_lv_mount_ms) do
      stage = lv_stage_stop(event)
      {view_module, live_action} = lv_view_info(metadata)
      uri = Map.get(metadata, :uri)

      Logger.warning("slow live_view #{stage}",
        event_type: "SLOW_LV_#{String.upcase(to_string(stage))}",
        duration_ms: ms,
        live_view: view_module,
        live_action: to_string(live_action || ""),
        request_path: uri && URI.parse(uri).path,
        request_id: request_id()
      )
    end
  rescue
    e -> log_handler_crash("kaguya-live-view-stop", e)
  end

  defp lv_stage_stop([:phoenix, :live_view, stage, :stop]), do: stage

  defp lv_view_info(metadata) do
    case Map.get(metadata, :socket) do
      %{view: v, assigns: a} -> {inspect(v), Map.get(a, :live_action)}
      %{view: v} -> {inspect(v), nil}
      _ -> {"unknown", nil}
    end
  end

  # ============================================================================
  # LiveView Exception Handler
  # ============================================================================
  #
  # Telemetry payload (Phoenix 1.7+):
  #   measurements: %{duration: native}
  #   metadata: %{kind: :error | :exit | :throw, reason: term(),
  #               stacktrace: list(), socket: %Phoenix.LiveView.Socket{},
  #               params: map(), event: String.t() | nil}
  #
  # Phoenix already logs the crash via the default LV logger, which the
  # Sentry.LoggerHandler picks up at :error level. We attach here in
  # addition so the event gets first-class operation/live_view tags
  # rather than the LoggerHandler's free-text format.

  def handle_live_view_exception(event, _measurements, metadata, _config) do
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason)
    stacktrace = Map.get(metadata, :stacktrace, [])

    {view_module, live_action} =
      case Map.get(metadata, :socket) do
        %{view: v, assigns: a} -> {inspect(v), Map.get(a, :live_action)}
        %{view: v} -> {inspect(v), nil}
        _ -> {"unknown", nil}
      end

    stage = lv_stage(event)
    exception = normalize(kind, reason, stacktrace)

    Kaguya.Observability.ErrorReporter.report(exception,
      operation: "live_view.#{stage}.#{view_module}",
      resource_type: "live_view",
      stacktrace: stacktrace,
      metadata: %{
        live_action: live_action,
        event: Map.get(metadata, :event),
        params_keys: metadata |> Map.get(:params, %{}) |> safe_keys()
      }
    )
  rescue
    # Belt-and-braces: never crash the telemetry pipeline.
    e -> log_handler_crash("kaguya-live-view-exception", e)
  end

  defp lv_stage([:phoenix, :live_view, stage, :exception]), do: stage
  defp lv_stage([:phoenix, :live_component, stage, :exception]), do: "component_#{stage}"
  defp lv_stage(_), do: "unknown"

  defp normalize(:error, %_{__exception__: true} = exception, _st), do: exception
  defp normalize(kind, reason, stacktrace), do: Exception.normalize(kind, reason, stacktrace)

  defp safe_keys(%{} = params) do
    params |> Map.keys() |> Enum.take(20) |> Enum.map(&to_string/1)
  rescue
    _ -> []
  end

  defp safe_keys(_), do: []

  # ============================================================================
  # Finch HTTP Client Handler (External API calls)
  # ============================================================================

  def handle_finch_stop(_event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if ms > threshold(:slow_api_ms) do
      request = metadata.request

      Logger.warning("slow external API",
        event_type: "SLOW_API",
        duration_ms: ms,
        host: request.host,
        path: request.path,
        request_id: request_id()
      )
    end
  rescue
    e -> log_handler_crash("kaguya-finch-stop", e)
  end

  def handle_finch_exception(_event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    request = metadata.request

    Logger.error("external API error",
      event_type: "API_ERROR",
      duration_ms: ms,
      host: request.host,
      path: request.path,
      reason: inspect(metadata.reason),
      request_id: request_id()
    )
  rescue
    e -> log_handler_crash("kaguya-finch-exception", e)
  end

  # ============================================================================
  # Oban Job Handler
  # ============================================================================

  # Oban merges the executing job's :id, :args, :queue, :worker, :attempt,
  # :max_attempts, :tags into the top-level metadata map alongside :conf and
  # :job. We read from the top-level keys with Map.get/3 so the handler stays
  # robust if Oban changes shape; raising here would cause :telemetry to detach
  # the handler for the rest of the node's lifetime.

  def handle_oban_stop(_event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if ms > threshold(:slow_job_ms) do
      Logger.warning("slow oban job",
        event_type: "SLOW_JOB",
        duration_ms: ms,
        worker: Map.get(metadata, :worker),
        queue: Map.get(metadata, :queue),
        attempt: Map.get(metadata, :attempt)
      )
    end
  rescue
    e -> log_handler_crash("kaguya-oban-stop", e)
  end

  def handle_oban_exception(_event, measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error("oban job error",
      event_type: "JOB_ERROR",
      duration_ms: ms,
      worker: Map.get(metadata, :worker),
      queue: Map.get(metadata, :queue),
      attempt: Map.get(metadata, :attempt),
      reason: inspect(Map.get(metadata, :reason))
    )
  rescue
    e -> log_handler_crash("kaguya-oban-exception", e)
  end

  # ============================================================================
  # Host Context
  # ============================================================================

  def hostname, do: System.get_env("HOSTNAME") || "local"

  # ============================================================================
  # DB Latency Check (for Supabase/external DB)
  # ============================================================================

  @doc """
  Measure DB round-trip latency. Useful to check Supabase network latency.

  Returns {:ok, latency_ms} or {:error, reason}

  Usage:
    Kaguya.Observability.Telemetry.db_latency()
    # => {:ok, 45}  # 45ms round trip to DB
  """
  def db_latency do
    start = System.monotonic_time(:millisecond)

    case Kaguya.Repo.query("SELECT 1") do
      {:ok, _} ->
        latency = System.monotonic_time(:millisecond) - start
        {:ok, latency}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Log current DB latency and pool status. Call this during a slow period to diagnose.
  """
  def diagnose do
    {latency_result, pool_info} =
      {db_latency(), pool_status()}

    latency_str =
      case latency_result do
        {:ok, ms} -> "#{ms}ms"
        {:error, reason} -> "error: #{inspect(reason)}"
      end

    Logger.info("""
    [DIAGNOSE] host=#{hostname()}
      DB latency: #{latency_str}
      Pool: #{inspect(pool_info)}
    """)

    %{
      db_latency: latency_result,
      pool: pool_info,
      host: hostname()
    }
  end

  defp pool_status do
    # Get pool size from config
    pool_size = Application.get_env(:kaguya, Kaguya.Repo)[:pool_size] || 10
    %{configured_pool_size: pool_size}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp to_ms(native) when is_integer(native),
    do: System.convert_time_unit(native, :native, :millisecond)

  defp to_ms(_), do: 0

  # Phoenix's Plug.RequestId sets this on the request process's Logger metadata.
  # Telemetry handlers for Phoenix/Ecto/Finch run in the caller (request)
  # process, so this returns the matching id. For Oban or other off-process work
  # this is `nil`, which is fine — they're correlated by job_id/worker instead.
  defp request_id, do: Logger.metadata() |> Keyword.get(:request_id)

  # Surface handler bugs without letting :telemetry detach the handler.
  # Avoid inspecting metadata here — Oban payloads can be large.
  defp log_handler_crash(handler, %_{} = exception) do
    Logger.error("telemetry handler crashed",
      event_type: "TELEMETRY_HANDLER_ERROR",
      handler: handler,
      kind: inspect(exception.__struct__),
      error: Exception.message(exception)
    )
  rescue
    _ -> :ok
  end

  defp truncate(string, max) when is_binary(string) do
    if String.length(string) > max do
      String.slice(string, 0, max) <> "..."
    else
      string
    end
  end

  defp truncate(other, _max), do: inspect(other)
end
