defmodule Kaguya.Observability.AxiomLogHandler do
  @moduledoc """
  Erlang :logger handler that ships log events to Axiom via `Kaguya.Observability.AxiomLogFlusher`.

  Captures warnings and above (SLOW_QUERY, POOL_WAIT, SLOW_REQ, etc.) and writes
  them to a shared ETS buffer. The flusher GenServer periodically drains the buffer
  and POSTs batched events to Axiom's ingest API using the existing Kaguya.Finch pool.

  ## Setup

  1. Add the flusher to your supervision tree (application.ex):

      Kaguya.Observability.AxiomLogFlusher

  2. Add the handler to prod.exs (alongside the existing Sentry handler):

      {:handler, :axiom_handler, Kaguya.Observability.AxiomLogHandler,
       %{config: %{level: :warning}}}

  3. Set environment variables:

      AXIOM_TOKEN   - Axiom API token
      AXIOM_DATASET - Axiom dataset name (e.g. "kaguya-logs")
  """

  @max_batch_size 100
  # Erlang logger severity: emergency=0, alert=1, critical=2, error=3, warning=4, notice=5, info=6, debug=7
  # Lower number = more severe. We want warning (4) and below (more severe).
  @max_severity 4

  # Logger metadata keys promoted to first-class Axiom columns. Keep in sync
  # with `config :logger, :console, metadata: [...]` in config/config.exs.
  # Anything not in this list stays out of Axiom — prevents accidental token
  # / PII leakage from upstream libraries that put arbitrary data in metadata.
  @safe_metadata_keys ~w(
    request_id
    user_id live_view live_action operation request_path
    resource_id resource_type critical
    event_type duration_ms queue_ms query_ms total_ms idle_ms query source name
    status method host parent_type field_name
    worker queue
    event_id attempt count reason error result
    current_status target_status processed dead_letter last_reason errors
    ip path params
    memory_mb processes_mb ets_mb binary_mb process_count port_count
    atom_count run_queue schedulers memory_limit_mb percent_used
    otp_release elixir_version pid
  )a

  # ── Handler callbacks ──────────────────────────────────────────────────

  def adding_handler(config) do
    # ETS table is created by AxiomLogFlusher, but create if not exists
    # (handler may be added before flusher starts)
    if :ets.whereis(:axiom_log_buffer) == :undefined do
      :ets.new(:axiom_log_buffer, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    {:ok, config}
  end

  def removing_handler(_config) do
    :ok
  end

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    # Only ship warnings and above (severity: emergency=0 .. debug=7)
    if level_severity(level) > @max_severity do
      :ok
    else
      message_str = format_message(msg)

      # Skip our own logs to prevent feedback loop
      if String.contains?(message_str, "[AxiomLogFlusher]") do
        :ok
      else
        do_log(level, message_str, meta)
      end
    end
  rescue
    _ -> :ok
  end

  defp do_log(level, message, meta) do
    base = %{
      _time: format_timestamp(meta),
      level: to_string(level),
      message: message,
      mfa: Map.get(meta, :mfa) |> format_mfa(),
      file: Map.get(meta, :file) |> to_string_or_nil(),
      line: Map.get(meta, :line),
      pid: meta |> Map.get(:pid) |> inspect(),
      host: Kaguya.Observability.Telemetry.hostname()
    }

    event = Map.merge(base, extract_safe_metadata(meta))

    key = System.unique_integer([:positive, :monotonic])
    :ets.insert(:axiom_log_buffer, {key, event})

    # Force flush if buffer is large
    if :ets.info(:axiom_log_buffer, :size) >= @max_batch_size do
      send(Kaguya.Observability.AxiomLogFlusher, :flush)
    end

    :ok
  rescue
    # Never crash the logging pipeline
    _ -> :ok
  end

  # Projects whitelisted Logger metadata keys onto an axiom-safe map.
  # Anything that isn't a primitive scalar (string / number / boolean /
  # nil) gets `inspect/1`-ed so Axiom's schema doesn't flip-flop between
  # types per column.
  defp extract_safe_metadata(meta) do
    Enum.reduce(@safe_metadata_keys, %{}, fn key, acc ->
      case Map.fetch(meta, key) do
        {:ok, value} -> Map.put(acc, key, sanitize(value))
        :error -> acc
      end
    end)
  end

  defp sanitize(nil), do: nil
  defp sanitize(v) when is_binary(v), do: v
  defp sanitize(v) when is_number(v), do: v
  defp sanitize(v) when is_boolean(v), do: v
  defp sanitize(v) when is_atom(v), do: Atom.to_string(v)
  defp sanitize(v), do: inspect(v, limit: 50, printable_limit: 200)

  def changing_config(_action, _old_config, new_config) do
    {:ok, new_config}
  end

  # ── Formatting helpers ─────────────────────────────────────────────────

  defp format_timestamp(meta) do
    case Map.get(meta, :time) do
      nil ->
        DateTime.utc_now() |> DateTime.to_iso8601()

      microseconds when is_integer(microseconds) ->
        microseconds
        |> DateTime.from_unix!(:microsecond)
        |> DateTime.to_iso8601()
    end
  rescue
    _ -> DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp format_message({:string, msg}), do: IO.chardata_to_string(msg)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, args}) when is_list(args) do
    :io_lib.format(format, args) |> IO.chardata_to_string()
  rescue
    _ -> inspect({format, args})
  end

  defp format_message(other), do: inspect(other)

  defp format_mfa(nil), do: nil
  defp format_mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  defp format_mfa(other), do: inspect(other)

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(val), do: to_string(val)

  defp level_severity(:emergency), do: 0
  defp level_severity(:alert), do: 1
  defp level_severity(:critical), do: 2
  defp level_severity(:error), do: 3
  defp level_severity(:warning), do: 4
  defp level_severity(:notice), do: 5
  defp level_severity(:info), do: 6
  defp level_severity(:debug), do: 7
  defp level_severity(_), do: 7
end
