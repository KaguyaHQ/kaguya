defmodule Kaguya.Auth.EmailRateLimit do
  @moduledoc "A shared, in-memory one-minute cooldown for login-email recipients."

  use GenServer

  alias Hammer.ETS.SlidingWindow

  @cooldown_ms :timer.minutes(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.take(opts, [:name]))
  end

  def reserve(email, server \\ __MODULE__)

  def reserve(email, server) when is_binary(email) do
    if String.trim(email) == "",
      do: {:error, :invalid_email},
      else: GenServer.call(server, {:reserve, recipient_key(email)})
  end

  def reserve(_, _), do: {:error, :invalid_email}

  def remaining_ms(email, server \\ __MODULE__)

  def remaining_ms(email, server) when is_binary(email) do
    GenServer.call(server, {:remaining, recipient_key(email)})
  end

  def remaining_ms(_, _), do: 0

  @impl true
  def init(:ok) do
    # Keep Hammer's sliding-window operations in one process so checking and
    # reserving are serialized. The existing IP limiter stays unchanged.
    table = :ets.new(__MODULE__, [:set, :private])
    schedule_clean()
    {:ok, table}
  end

  @impl true
  def handle_call({:reserve, key}, _from, table) do
    result =
      case remaining(table, key) do
        0 ->
          {:allow, 1} = SlidingWindow.hit(table, key, @cooldown_ms, 1)
          :ok

        remaining_ms ->
          # Do not record denied attempts: they must not extend the cooldown.
          {:error, {:email_cooldown, remaining_ms}}
      end

    {:reply, result, table}
  end

  def handle_call({:remaining, key}, _from, table) do
    {:reply, remaining(table, key), table}
  end

  @impl true
  def handle_info(:clean, table) do
    SlidingWindow.clean(%{table: table})
    schedule_clean()
    {:noreply, table}
  end

  defp remaining(table, key) do
    now = System.system_time(:microsecond)

    table
    |> :ets.match_object({{key, :_}, :_})
    |> Enum.reduce(0, fn {_key, expires_at}, acc -> max(acc, expires_at - now) end)
    |> then(&div(&1 + 999, 1000))
  end

  defp recipient_key(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp schedule_clean, do: Process.send_after(self(), :clean, @cooldown_ms)
end
