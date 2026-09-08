defmodule Kaguya.AxiomLogHandlerTest do
  # async: false — we share a single named ETS table with the live handler.
  use ExUnit.Case, async: false

  alias Kaguya.Observability.AxiomLogHandler

  @table :axiom_log_buffer

  setup do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  defp last_event do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {k, _} -> k end)
    |> List.last()
    |> elem(1)
  end

  defp log(level, meta) do
    AxiomLogHandler.log(%{level: level, msg: {:string, "msg"}, meta: meta}, nil)
  end

  test "projects whitelisted metadata to first-class fields" do
    log(:warning, %{
      request_id: "req-1",
      user_id: "user-9",
      live_view: "Some.LV",
      operation: "demo"
    })

    e = last_event()
    assert e.request_id == "req-1"
    assert e.user_id == "user-9"
    assert e.live_view == "Some.LV"
    assert e.operation == "demo"
  end

  test "drops metadata keys not on the whitelist" do
    log(:warning, %{user_id: "u1", custom_unsafe: %{secret: "should-not-leak"}})

    e = last_event()
    assert e.user_id == "u1"
    refute Map.has_key?(e, :custom_unsafe)
    refute Map.has_key?(e, :secret)
  end

  test "retains operational diagnostics while excluding unrelated metadata" do
    diagnostics = %{
      handler: :oban_exception,
      kind: "RuntimeError",
      error_kind: :invalid_image,
      image_type: "avatar",
      image_id: "image-123",
      date: "2026-09-08",
      size_bytes: 4096,
      latest_url: "https://example.test/latest.tar.gz",
      dated_url: "https://example.test/2026-09-08.tar.gz",
      key: "dumps/2026-09-08.tar.gz",
      mode: :full,
      dry_run: false,
      chunks: 3,
      url: "https://example.test/sitemap.xml",
      ratings: 10,
      reading_statuses: 20,
      reviews: 5,
      users: 30,
      dau: 8,
      mau_30d: 25,
      vns: 50
    }

    log(:warning, Map.put(diagnostics, :authorization, "must-not-be-exported"))
    event = last_event()

    for {key, value} <- diagnostics do
      expected =
        if is_atom(value) and not is_boolean(value), do: Atom.to_string(value), else: value

      assert Map.fetch!(event, key) == expected
    end

    refute Map.has_key?(event, :authorization)
  end

  test "sanitizes non-primitive metadata via inspect/1" do
    log(:warning, %{user_id: %{nested: :map}, request_id: {1, 2, 3}})

    e = last_event()
    assert is_binary(e.user_id)
    assert is_binary(e.request_id)
  end

  test "skips below-severity levels" do
    log(:info, %{user_id: "u1"})
    log(:debug, %{user_id: "u2"})

    assert :ets.info(@table, :size) == 0
  end

  test "ignores feedback-loop events from the flusher itself" do
    AxiomLogHandler.log(
      %{
        level: :warning,
        msg: {:string, "[AxiomLogFlusher] ingest failed"},
        meta: %{user_id: "u1"}
      },
      nil
    )

    assert :ets.info(@table, :size) == 0
  end
end
