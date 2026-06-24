defmodule Kaguya.Observability.AxiomLogFlusher do
  @moduledoc """
  GenServer that periodically flushes the Axiom log buffer to the Axiom ingest API.

  Drains the ETS buffer populated by `Kaguya.Observability.AxiomLogHandler` and ships events
  as a JSON batch via the existing `Kaguya.Finch` HTTP pool.
  """

  use GenServer
  require Logger

  @flush_interval_ms 2_000
  @max_retries 2

  # ── Public API ─────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns flush statistics for diagnostics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ── GenServer callbacks ────────────────────────────────────────────────

  @impl true
  def init(_) do
    # Trap exits so terminate/2 fires on supervisor shutdown (SIGTERM
    # during deploys, app stop) — the last batch of warnings gets
    # shipped before the BEAM exits.
    Process.flag(:trap_exit, true)

    if :ets.whereis(:axiom_log_buffer) == :undefined do
      :ets.new(:axiom_log_buffer, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    axiom_config = Application.get_env(:kaguya, :axiom, [])
    token = axiom_config[:token]
    dataset = axiom_config[:dataset]

    enabled = is_binary(token) and token != "" and is_binary(dataset) and dataset != ""

    state = %{
      token: token,
      dataset: dataset,
      enabled: enabled,
      events_shipped: 0,
      events_dropped: 0,
      flushes_ok: 0,
      flushes_failed: 0
    }

    if enabled do
      Logger.info("[AxiomLogFlusher] Enabled | dataset=#{dataset}")
      schedule_flush()
    else
      Logger.info("[AxiomLogFlusher] Disabled (AXIOM_TOKEN/AXIOM_DATASET not set)")
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    state = if state.enabled, do: flush_buffer(state), else: state
    schedule_flush()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:stats, _from, state) do
    stats =
      Map.take(state, [
        :enabled,
        :dataset,
        :events_shipped,
        :events_dropped,
        :flushes_ok,
        :flushes_failed
      ])

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    # One last drain on the way out. Synchronous Finch POST inside a
    # shutting-down supervisor is fine — `Kaguya.Finch` is started
    # before this GenServer (one_for_one), so it's still alive here.
    if state.enabled, do: flush_buffer(state)
    :ok
  end

  # ── Flush logic ────────────────────────────────────────────────────────

  defp flush_buffer(state) do
    events = :ets.tab2list(:axiom_log_buffer)

    if events != [] do
      :ets.delete_all_objects(:axiom_log_buffer)

      event_list = Enum.map(events, fn {_key, event} -> event end)
      count = length(event_list)
      payload = Jason.encode!(event_list)

      case send_to_axiom(state, payload, 0) do
        :ok ->
          %{
            state
            | events_shipped: state.events_shipped + count,
              flushes_ok: state.flushes_ok + 1
          }

        :error ->
          %{
            state
            | events_dropped: state.events_dropped + count,
              flushes_failed: state.flushes_failed + 1
          }
      end
    else
      state
    end
  end

  defp send_to_axiom(_state, _payload, retries) when retries > @max_retries, do: :error

  defp send_to_axiom(state, payload, retries) do
    url = "https://api.axiom.co/v1/datasets/#{state.dataset}/ingest"

    request =
      Finch.build(
        :post,
        url,
        [
          {"authorization", "Bearer #{state.token}"},
          {"content-type", "application/json"}
        ],
        payload
      )

    case Finch.request(request, Kaguya.Finch, receive_timeout: 10_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 429}} ->
        Process.sleep(1_000 * (retries + 1))
        send_to_axiom(state, payload, retries + 1)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[AxiomLogFlusher] Ingest failed status=#{status} body=#{body}")
        :error

      {:error, reason} ->
        Logger.warning("[AxiomLogFlusher] Ingest error: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.warning("[AxiomLogFlusher] Unexpected error: #{inspect(e)}")
      :error
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
