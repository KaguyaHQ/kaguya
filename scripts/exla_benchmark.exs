# Run with the production release's Erlang/Elixir runtime; see exla_benchmark.md.
# No application startup, database access, or writes to the model are required.
defmodule Kaguya.ExlaBenchmark do
  alias Kaguya.Recommendations.Nx.{Engine, Npy}

  def run do
    if System.fetch_env!("BENCH_MODE") == "verify", do: verify_saved(), else: run_timing()
  end

  defp run_timing do
    mode = System.fetch_env!("BENCH_MODE")
    unless mode in ["eager", "jit", "verify"], do: raise("invalid BENCH_MODE")

    {:ok, _} = Application.ensure_all_started(:exla)
    Nx.default_backend({EXLA.Backend, client: :host})
    Nx.Defn.default_options(compiler: Nx.Defn.Evaluator)
    emit(%{event: "before_load", mode: mode, memory: memory()})

    path = System.fetch_env!("BENCH_MODEL")
    sizes = System.get_env("BENCH_SIZES", "10,50,100,250,500,1000,2000")
    sizes = sizes |> String.split(",") |> Enum.map(&String.to_integer/1)
    repeats = System.get_env("BENCH_REPEATS", "10") |> String.to_integer()
    unless repeats > 0 and Enum.all?(sizes, &(&1 > 0)), do: raise("invalid workload")

    loader = System.get_env("BENCH_LOADER", "current")

    {load_us, b} =
      :timer.tc(fn ->
        case loader do
          "current" ->
            Npy.load!(path)

          "binary_first" ->
            # Keep the large source binary out of the scoring process's heap.
            Task.async(fn ->
              tensor =
                Nx.with_default_backend(Nx.BinaryBackend, fn -> Npy.load!(path) end)
                |> Nx.backend_transfer({EXLA.Backend, client: :host})

              # Wait for transfer before the loader exits and releases its binary.
              tensor |> Nx.slice([0, 0], [1, 1]) |> Nx.to_binary()
              tensor
            end)
            |> Task.await(:infinity)

          _ ->
            raise "invalid BENCH_LOADER"
        end
      end)

    :erlang.garbage_collect()
    {n_items, n_items} = Nx.shape(b)
    unless Enum.all?(sizes, &(&1 <= n_items)), do: raise("preference count exceeds model size")

    emit(%{
      event: "setup",
      mode: mode,
      loader: loader,
      model_bytes: File.stat!(path).size,
      n_items: n_items,
      model_load_ms: load_us / 1000,
      schedulers: System.schedulers_online(),
      nx: version(:nx),
      exla: version(:exla),
      memory: memory()
    })

    # The matrix is a runtime argument, never a constant captured by the JIT.
    eager = &Engine.ease_scores/3
    compiled = EXLA.jit(&Engine.ease_scores/3, client: :host)

    rows =
      Enum.map(sizes, fn count ->
        # Deterministic, evenly distributed VNs and mean-centered signed ratings.
        # These are synthetic user histories against the actual trained model.
        indices = for i <- 0..(count - 1), do: div(i * n_items, count)
        ratings = for i <- 0..(count - 1), do: rem(i, 11) / 2.0 - 2.5
        mean = Enum.sum(ratings) / count
        idx = Nx.tensor(indices, type: :s64)
        values = Nx.tensor(Enum.map(ratings, &(&1 - mean)), type: :f32)

        fun = if mode == "jit", do: compiled, else: eager
        {first_us, output} = timed(fun, b, idx, values)
        File.write!(output_path(mode, count), output)

        timings =
          for _ <- 1..repeats do
            {us, _} = timed(fun, b, idx, values)
            us / 1000
          end

        row = %{
          preferences: count,
          first_ms: first_us / 1000,
          warm_median_ms: timings |> Enum.sort() |> Enum.at(div(repeats, 2)),
          warm_min_ms: Enum.min(timings),
          warm_max_ms: Enum.max(timings),
          warm_total_ms: Enum.sum(timings),
          repeats: repeats
        }

        row = Map.merge(row, %{event: "shape", mode: mode, memory: memory()})
        emit(row)
        row
      end)

    emit(%{
      event: "summary",
      mode: mode,
      # Kernel timings only: excludes DB, masking, ranking, and explanations.
      first_pass_ms: Enum.sum(Enum.map(rows, &Map.get(&1, :first_ms, 0))),
      repeated_batch_ms: Enum.sum(Enum.map(rows, &Map.get(&1, :warm_total_ms, 0))),
      memory: memory()
    })
  end

  defp verify_saved do
    sizes =
      System.fetch_env!("BENCH_SIZES") |> String.split(",") |> Enum.map(&String.to_integer/1)

    Enum.each(sizes, fn count ->
      eager = File.read!(output_path("eager", count))
      jit = File.read!(output_path("jit", count))
      unless byte_size(eager) == byte_size(jit), do: raise("output size mismatch")
      expected = for <<value::float-native-32 <- eager>>, do: value
      actual = for <<value::float-native-32 <- jit>>, do: value
      pairs = Enum.zip(expected, actual)
      max_error = pairs |> Enum.map(fn {a, b} -> abs(a - b) end) |> Enum.max()
      valid? = Enum.all?(pairs, fn {a, b} -> abs(a - b) <= 1.0e-4 + 1.0e-4 * abs(a) end)
      unless valid?, do: raise("JIT numerical mismatch at #{count} preferences")
      n_items = length(expected)
      indices = for i <- 0..(count - 1), do: div(i * n_items, count)
      expected_top = top_indices(expected, indices)
      actual_top = top_indices(actual, indices)

      emit(%{
        event: "verification",
        preferences: count,
        max_absolute_error: max_error,
        top_50_overlap: MapSet.size(MapSet.intersection(expected_top, actual_top)),
        compared_candidates: MapSet.size(expected_top)
      })
    end)
  end

  defp output_path(mode, count) do
    Path.join(System.fetch_env!("BENCH_OUTPUT_DIR"), "#{mode}-#{count}.bin")
  end

  defp timed(fun, b, idx, values) do
    # EXLA is asynchronous. Reading the full result waits for execution.
    :timer.tc(fn -> fun.(b, idx, values) |> Nx.to_binary() end)
  end

  defp top_indices(scores, excluded) do
    excluded = MapSet.new(excluded)

    scores
    |> Enum.with_index()
    |> Enum.reject(fn {score, index} -> score <= 0 or MapSet.member?(excluded, index) end)
    |> Enum.sort_by(fn {score, index} -> {-score, index} end)
    |> Enum.take(50)
    |> MapSet.new(fn {_, index} -> index end)
  end

  defp memory do
    status = File.read!("/proc/self/status")

    Map.new([{"VmRSS", :rss_mib}, {"VmHWM", :peak_rss_mib}], fn {key, name} ->
      [_, kb] = Regex.run(Regex.compile!("^#{key}:\\s+(\\d+)", "m"), status)
      {name, String.to_integer(kb) / 1024}
    end)
  end

  defp version(app), do: app |> Application.spec(:vsn) |> to_string()
  defp emit(row), do: IO.puts(Jason.encode!(row))
end

Kaguya.ExlaBenchmark.run()
