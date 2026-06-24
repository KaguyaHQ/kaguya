defmodule Kaguya.Observability.Heartbeat do
  @moduledoc """
  Periodic BEAM health beacon shipped to Axiom.

  Three event_types are emitted, all as Logger calls so the existing
  `Kaguya.Observability.AxiomLogHandler` routes them to Axiom without
  any new plumbing:

    * `PROCESS_START` — emitted once on startup. Every occurrence in
      Axiom = a process (re)start. Wire an Axiom monitor on
      `event_type == "PROCESS_START"` for crash-loop alerting.

    * `HEARTBEAT` — emitted every `@interval_ms` (60 s). Memory, process
      count, scheduler queue depth.

    * `MEMORY_CRITICAL` — fires once when total memory crosses
      `@critical_ratio` of the configured limit. Resets if memory drops
      back below 90% of the threshold (so a GC-driven dip will allow a
      future re-fire).

  The memory limit is read from the `KAGUYA_MEMORY_LIMIT_MB` env var if
  set (e.g. matching the Hetzner box's RAM); otherwise it falls back to
  a conservative 4096 MB default.
  """

  use GenServer
  require Logger

  @interval_ms 60_000
  @critical_ratio 0.85
  @reset_ratio 0.75
  @default_limit_mb 4096

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    limit_mb = memory_limit_mb()
    snap = snapshot()

    # :warning so it ships through AxiomLogHandler (which is :warning+).
    Logger.warning("process started",
      event_type: "PROCESS_START",
      memory_mb: snap.memory_mb,
      processes_mb: snap.processes_mb,
      atom_count: snap.atom_count,
      process_count: snap.process_count,
      schedulers: System.schedulers_online(),
      otp_release: System.otp_release(),
      elixir_version: System.version(),
      memory_limit_mb: limit_mb,
      pid: System.pid()
    )

    Process.send_after(self(), :tick, @interval_ms)
    {:ok, %{memory_critical_logged: false, limit_mb: limit_mb}}
  end

  @impl true
  def handle_info(:tick, state) do
    snap = snapshot()

    # :warning so the event clears the AxiomLogHandler's severity gate
    # (:warning+) and reaches Axiom on every tick — needed for the
    # memory-trend / process-restart dashboards driven off the `HEARTBEAT`
    # event. The level is
    # operationally "interesting", not "something is wrong"; filter
    # dashboards / pagers by `event_type == "HEARTBEAT"` rather than by
    # level if heartbeats clutter warning queries.
    Logger.warning("heartbeat",
      event_type: "HEARTBEAT",
      memory_mb: snap.memory_mb,
      processes_mb: snap.processes_mb,
      ets_mb: snap.ets_mb,
      binary_mb: snap.binary_mb,
      process_count: snap.process_count,
      port_count: snap.port_count,
      atom_count: snap.atom_count,
      run_queue: snap.run_queue
    )

    state = maybe_alert_memory(state, snap.memory_mb)
    Process.send_after(self(), :tick, @interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Memory critical (one-shot per crossing) ──────────────────────────

  defp maybe_alert_memory(%{memory_critical_logged: false, limit_mb: limit} = s, mb)
       when mb > limit * @critical_ratio do
    Logger.error("memory critical — OOM likely",
      event_type: "MEMORY_CRITICAL",
      memory_mb: mb,
      memory_limit_mb: limit,
      percent_used: round(mb / limit * 100),
      process_count: :erlang.system_info(:process_count)
    )

    %{s | memory_critical_logged: true}
  end

  defp maybe_alert_memory(%{memory_critical_logged: true, limit_mb: limit} = s, mb)
       when mb < limit * @reset_ratio do
    # Dropped back below 75% — re-arm the alert.
    %{s | memory_critical_logged: false}
  end

  defp maybe_alert_memory(state, _mb), do: state

  # ── Snapshot helpers ─────────────────────────────────────────────────

  defp snapshot do
    mem = :erlang.memory()

    %{
      memory_mb: mb(mem[:total]),
      processes_mb: mb(mem[:processes]),
      ets_mb: mb(mem[:ets]),
      binary_mb: mb(mem[:binary]),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      atom_count: :erlang.system_info(:atom_count),
      run_queue: :erlang.statistics(:run_queue_lengths_all) |> Enum.sum()
    }
  end

  defp mb(bytes) when is_integer(bytes), do: div(bytes, 1024 * 1024)
  defp mb(_), do: 0

  defp memory_limit_mb do
    case System.get_env("KAGUYA_MEMORY_LIMIT_MB") do
      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} when n > 0 -> n
          _ -> @default_limit_mb
        end

      _ ->
        @default_limit_mb
    end
  end
end
