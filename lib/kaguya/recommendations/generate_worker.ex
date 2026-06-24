defmodule Kaguya.Recommendations.GenerateWorker do
  @moduledoc """
  Oban worker that generates personalized VN recommendations (EASE).

  Inference runs in-process via `Kaguya.Recommendations.Nx.Engine` on the
  EXLA backend. The B-matrix artifacts in `priv/data/` are trained offline
  (see the scripts under `priv/recommendations/`) — this worker only runs
  scoring.

  Flow:

    1. Export the target users' prefs / masks to tmp CSVs.
    2. Score each user via the Nx engine; write results to an output CSV.
    3. Import the output CSV into `user_recommendations`.
    4. Emit telemetry. Cleanup tmp files.

  Args (all optional):

    * `"user_ids"` — list of UUIDs; default: every eligible user
    * `"n_final"`  — recs per user (default 50; UI shows all)
  """

  use Oban.Worker, queue: :recommendations, max_attempts: 3

  alias Kaguya.Recommendations
  alias Kaguya.Recommendations.Nx.Engine, as: NxEngine

  @csv_suffixes ["_prefs.csv", "_masks.csv", "_out.csv"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    user_ids = Map.get(args, "user_ids") || Recommendations.list_eligible_user_ids()
    n_final = Map.get(args, "n_final", 50)

    if user_ids == [] do
      {:ok, :no_eligible_users}
    else
      {:ok, run(user_ids, n_final)}
    end
  end

  defp run(user_ids, n_final) do
    method = Recommendations.method()
    prefix = tmp_prefix()

    try do
      paths = Recommendations.export_user_data(prefix, user_ids)
      out_path = "#{prefix}_out.csv"

      case score_users(paths, out_path, n_final) do
        :ok ->
          model_version = "#{method}-nx-#{Date.utc_today() |> Date.to_iso8601()}"
          {:ok, result} = Recommendations.import_recommendations_csv(out_path, model_version)

          :telemetry.execute(
            [:kaguya, :recommendations, :generated],
            %{n_users: length(user_ids), n_inserted: count_inserted(result)},
            %{method: method, model_version: model_version}
          )

          {:ok, result}

        {:error, _} = err ->
          err
      end
    after
      Enum.each(@csv_suffixes, &File.rm(prefix <> &1))
      # Release the ~500MB B matrix cached in :persistent_term. The cron fires
      # every ~3 days and synchronous refresh clicks are rare — holding this
      # in RAM between runs costs a lot to save ~5s of reload on the next call.
      # `score_user` reloads on demand.
      :persistent_term.erase({Kaguya.Recommendations.Nx.Engine, :context, method})
    end
  end

  defp score_users(paths, out_path, n_final) do
    # The Nx engine scores one user at a time; the CSV has all users batched.
    # Group once, score each, write one combined CSV the importer can read.
    prefs_by_user = load_grouped(paths.prefs, &parse_pref_row/1)
    masks_by_user = load_grouped(paths.masks, & &1["vndb_id"])

    total = map_size(prefs_by_user)

    IO.puts(
      "[Nx] scoring #{total} users — first call loads B matrix (~5s) + JIT compiles per pref shape."
    )

    t_start = System.monotonic_time(:millisecond)
    # ~50 progress lines total
    log_every = max(div(total, 50), 1)

    File.open!(out_path, [:write, :utf8], fn io ->
      IO.write(
        io,
        "user_id,vndb_id,score,ease_score,rank,reasons,total_positive_contribution\n"
      )

      prefs_by_user
      |> Enum.with_index(1)
      |> Enum.each(fn {{user_id, prefs}, i} ->
        masks = Map.get(masks_by_user, user_id, [])

        t_user = System.monotonic_time(:millisecond)
        result = NxEngine.score_user(prefs, masks, n_final: n_final)
        user_ms = System.monotonic_time(:millisecond) - t_user

        case result do
          nil ->
            :ok

          rows ->
            Enum.each(rows, fn row ->
              IO.write(io, format_csv_row(user_id, row))
            end)
        end

        # Progress: log the first 3 (to show activity + first-shape JIT cost),
        # then every ~2% of the batch, plus the last one.
        if i <= 3 or rem(i, log_every) == 0 or i == total do
          elapsed_s = (System.monotonic_time(:millisecond) - t_start) / 1000
          eta_s = if i > 0, do: elapsed_s / i * (total - i), else: 0.0

          IO.puts(
            "  [#{i}/#{total}] #{String.pad_leading("#{user_ms}", 5)}ms user  " <>
              "elapsed=#{Float.round(elapsed_s, 1)}s  eta=#{Float.round(eta_s, 1)}s"
          )
        end
      end)
    end)

    total_s = (System.monotonic_time(:millisecond) - t_start) / 1000

    IO.puts(
      "[Nx] done — #{total} users in #{Float.round(total_s, 1)}s (#{Float.round(total_s * 1000 / total, 1)}ms/user avg)"
    )

    :ok
  rescue
    e ->
      {:error,
       "Nx engine failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"}
  end

  defp load_grouped(path, mapper) do
    case File.read(path) do
      {:ok, body} ->
        [_header | lines] = String.split(body, "\n", trim: true)

        lines
        |> Enum.map(&parse_csv_line(&1, mapper))
        |> Enum.reject(&is_nil/1)
        |> Enum.group_by(fn {uid, _} -> uid end, fn {_, row} -> row end)

      _ ->
        %{}
    end
  end

  defp parse_csv_line(line, mapper) do
    case String.split(line, ",") do
      [uid | rest] ->
        row =
          case rest do
            [vndb_id] ->
              mapper.(%{"vndb_id" => vndb_id})

            [vndb_id, value] ->
              mapper.(%{"vndb_id" => vndb_id, "value" => value})

            _ ->
              nil
          end

        if row, do: {uid, row}, else: nil

      _ ->
        nil
    end
  end

  defp parse_pref_row(%{"vndb_id" => vid, "value" => v}) do
    {f, _} = Float.parse(v)
    %{vndb_id: vid, value: f}
  end

  defp format_csv_row(user_id, row) do
    # `reasons` is `"vndb_id:contribution|vndb_id:contribution|..."` — the
    # importer splits on `|` then on `:`. Contribution serialized with 6
    # decimals matches score/ease_score precision; plenty of headroom for
    # rounding when the frontend reduces it to a whole-number percent.
    reason_col =
      row.reasons
      |> Enum.map_join("|", fn r ->
        "#{r.vndb_id}:#{:erlang.float_to_binary(r.contribution, [{:decimals, 6}])}"
      end)

    :io_lib.format("~s,~s,~.6f,~.6f,~w,~s,~.6f~n", [
      user_id,
      row.vndb_id,
      row.final_score,
      row.ease_score,
      row.rank,
      reason_col,
      row.total_positive_contribution
    ])
    |> IO.iodata_to_binary()
  end

  # Multi.insert_all is chunked, so result has keys like {:insert, 0},
  # {:insert, 1}, ... — sum them for the telemetry count.
  defp count_inserted(multi_result) do
    Enum.reduce(multi_result, 0, fn
      {{:insert, _}, {n, _}}, acc -> acc + n
      _, acc -> acc
    end)
  end

  defp tmp_prefix do
    Path.join(
      System.tmp_dir!(),
      "kaguya_recs_#{Recommendations.method()}_#{System.os_time(:second)}"
    )
  end
end
