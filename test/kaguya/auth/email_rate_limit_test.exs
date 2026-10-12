defmodule Kaguya.Auth.EmailRateLimitTest do
  use ExUnit.Case, async: true

  alias Kaguya.Auth.EmailRateLimit

  setup do
    %{limiter: start_supervised!(EmailRateLimit)}
  end

  test "normalization shares a cooldown without blocking another recipient", %{limiter: limiter} do
    assert :ok = EmailRateLimit.reserve("Reader@Example.com", limiter)

    assert {:error, {:email_cooldown, remaining}} =
             EmailRateLimit.reserve(" reader@example.COM ", limiter)

    assert remaining > 59_000
    assert remaining <= 60_000
    assert :ok = EmailRateLimit.reserve("other@example.com", limiter)
  end

  test "denied requests do not extend the cooldown", %{limiter: limiter} do
    assert :ok = EmailRateLimit.reserve("reader@example.com", limiter)
    before = EmailRateLimit.remaining_ms("reader@example.com", limiter)

    for _ <- 1..20 do
      assert {:error, {:email_cooldown, _}} =
               EmailRateLimit.reserve("reader@example.com", limiter)
    end

    assert EmailRateLimit.remaining_ms("reader@example.com", limiter) <= before
  end

  test "a recipient can request again after the previous reservation expires", %{limiter: limiter} do
    assert :ok = EmailRateLimit.reserve("reader@example.com", limiter)

    # Advance the stored expiry rather than sleeping for a minute.
    :sys.replace_state(limiter, fn table ->
      for {key, _expires_at} <- :ets.tab2list(table) do
        :ets.insert(table, {key, System.system_time(:microsecond) - 1})
      end

      table
    end)

    assert EmailRateLimit.remaining_ms("reader@example.com", limiter) == 0
    assert :ok = EmailRateLimit.reserve("reader@example.com", limiter)
  end

  test "concurrent reservations admit exactly one request", %{limiter: limiter} do
    results =
      1..20
      |> Task.async_stream(fn _ -> EmailRateLimit.reserve("reader@example.com", limiter) end,
        max_concurrency: 20
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &match?({:error, {:email_cooldown, _}}, &1)) == 19
  end

  test "empty and malformed recipients cannot reserve a send", %{limiter: limiter} do
    for email <- [nil, %{}, "", " "] do
      assert {:error, :invalid_email} = EmailRateLimit.reserve(email, limiter)
    end
  end
end
