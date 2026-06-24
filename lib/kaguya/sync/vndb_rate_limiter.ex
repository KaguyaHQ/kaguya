defmodule Kaguya.Sync.VndbRateLimiter do
  @moduledoc """
  Global rate limiter for VNDB API requests.

  VNDB allows 200 requests per 5 minutes (~1 req/1.5s sustained).
  Process.sleep in the API client is per-process, so concurrent imports
  bypass it. This GenServer serializes the throttle globally — every
  process calls `throttle/0` before making a VNDB request, and the
  GenServer ensures at least @min_interval_ms between any two requests
  system-wide.
  """

  use GenServer

  @min_interval_ms 1_600

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Block the caller until enough time has passed since the last VNDB request.
  Call this before every VNDB API request.
  """
  def throttle do
    GenServer.call(__MODULE__, :throttle, 60_000)
  end

  # ── Callbacks ──────────────────────────────────────────────────────────────

  @impl true
  def init(_) do
    # Initialize to "already waited" so the first request goes through immediately
    {:ok, System.monotonic_time(:millisecond) - @min_interval_ms}
  end

  @impl true
  def handle_call(:throttle, _from, last_request_at) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - last_request_at
    wait = max(@min_interval_ms - elapsed, 0)

    if wait > 0, do: Process.sleep(wait)

    {:reply, :ok, System.monotonic_time(:millisecond)}
  end
end
