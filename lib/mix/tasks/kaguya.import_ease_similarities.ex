defmodule Mix.Tasks.Kaguya.ImportEaseSimilarities do
  @moduledoc """
  Seeds EASE-computed VN similarities into vn_similarities.
  Only inserts NEW pairs — never overwrites existing community-voted ones.

  Usage:
    mix kaguya.import_ease_similarities
    mix kaguya.import_ease_similarities --file priv/data/ease_similarities.json
    mix kaguya.import_ease_similarities --dry-run

  --dry-run prints a coverage report (added vs. skipped, VNs gaining sims,
  popular-VN impact) without writing to the DB.
  """
  use Mix.Task
  require Logger

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Similarities.Similarity
  alias Kaguya.VisualNovels.VisualNovel

  @default_file "priv/data/ease_similarities.json"
  @batch_size 1000

  def run(args) do
    Application.put_env(:kaguya, KaguyaWeb.Endpoint, server: false)
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [file: :string, dry_run: :boolean])
    file = Keyword.get(opts, :file, @default_file)
    dry_run? = Keyword.get(opts, :dry_run, false)

    Logger.info("Importing EASE similarities from #{file}")
    if dry_run?, do: Logger.info("[DRY RUN] No DB changes will be made.")

    data = file |> File.read!() |> Jason.decode!()
    Logger.info("Loaded #{map_size(data)} VNs from JSON")

    vndb_map = build_vndb_map()
    Logger.info("Mapped #{map_size(vndb_map)} vndb_ids to internal IDs")

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = build_rows(data, vndb_map, now)
    Logger.info("Built #{length(rows)} similarity pairs")

    if dry_run?, do: report_dry_run(rows), else: perform_insert(rows)
  end

  defp perform_insert(rows) do
    inserted =
      rows
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(0, fn batch, acc ->
        {count, _} =
          Repo.insert_all(
            Similarity,
            batch,
            on_conflict: :nothing,
            conflict_target: [:visual_novel_id, :similar_vn_id]
          )

        acc + count
      end)

    Logger.info("Inserted #{inserted} new pairs (#{length(rows) - inserted} already existed)")
  end

  defp report_dry_run(rows) do
    Logger.info("Comparing against current vn_similarities state…")

    existing_pairs =
      from(s in Similarity, select: {s.visual_novel_id, s.similar_vn_id})
      |> Repo.all()
      |> MapSet.new()

    new_pairs_set =
      rows
      |> Enum.map(fn r -> {r.visual_novel_id, r.similar_vn_id} end)
      |> MapSet.new()

    {to_insert, to_skip} =
      Enum.split_with(rows, fn r ->
        not MapSet.member?(existing_pairs, {r.visual_novel_id, r.similar_vn_id})
      end)

    orphan_count =
      Enum.count(existing_pairs, fn pair -> not MapSet.member?(new_pairs_set, pair) end)

    current_counts = pairs_to_counts(MapSet.to_list(existing_pairs))

    new_counts =
      to_insert
      |> Enum.flat_map(fn r -> [r.visual_novel_id, r.similar_vn_id] end)
      |> Enum.frequencies()

    total_vns = Repo.aggregate(VisualNovel, :count)
    vns_with_sims_before = map_size(current_counts)
    vns_without_sims_before = total_vns - vns_with_sims_before

    cold_warmed =
      Enum.filter(new_counts, fn {vn_id, _} ->
        Map.get(current_counts, vn_id, 0) == 0
      end)

    warmed_buckets = bucket_counts(Enum.map(cold_warmed, fn {_, c} -> c end))

    cold? = fn id -> Map.get(current_counts, id, 0) == 0 end

    {pairs_both_cold, pairs_one_cold, pairs_neither_cold} =
      Enum.reduce(to_insert, {0, 0, 0}, fn r, {bb, ob, nn} ->
        a_cold = cold?.(r.visual_novel_id)
        b_cold = cold?.(r.similar_vn_id)

        cond do
          a_cold and b_cold -> {bb + 1, ob, nn}
          a_cold or b_cold -> {bb, ob + 1, nn}
          true -> {bb, ob, nn + 1}
        end
      end)

    popular_threshold = 30

    popular_vn_ids =
      current_counts
      |> Enum.filter(fn {_, c} -> c >= popular_threshold end)
      |> Enum.map(fn {id, _} -> id end)
      |> MapSet.new()

    popular_new_pairs =
      Enum.filter(new_counts, fn {vn_id, _} ->
        MapSet.member?(popular_vn_ids, vn_id)
      end)

    popular_buckets = bucket_counts(Enum.map(popular_new_pairs, fn {_, c} -> c end))

    IO.puts("\n=== DRY RUN REPORT ===\n")
    IO.puts("JSON pairs (after dedup):   #{length(rows)}")
    IO.puts("Existing pairs in DB:       #{MapSet.size(existing_pairs)}")
    IO.puts("")
    IO.puts("Would INSERT (new):         #{length(to_insert)}")
    IO.puts("Would SKIP (already in DB): #{length(to_skip)}")
    IO.puts("Persisting untouched:       #{orphan_count} (in DB, absent from new JSON)")
    IO.puts("")
    IO.puts("--- VN coverage ---")
    IO.puts("Total VNs in DB:            #{total_vns}")
    IO.puts("VNs with ≥1 similar before: #{vns_with_sims_before}")
    IO.puts("VNs with 0  similar before: #{vns_without_sims_before}")
    IO.puts("")
    IO.puts("Among the 0-similar VNs:")
    IO.puts("  Gain ≥1 similar after run: #{length(cold_warmed)}")
    IO.puts("  Still 0 after run:         #{vns_without_sims_before - length(cold_warmed)}")
    IO.puts("")
    IO.puts("New similar count per previously-empty VN:")
    print_buckets(warmed_buckets)
    IO.puts("")
    IO.puts("New pairs broken down by participants:")
    IO.puts("  Both sides previously cold (cold↔cold): #{pairs_both_cold}")
    IO.puts("  One side cold, one warm (cold↔warm):    #{pairs_one_cold}")
    IO.puts("  Both sides already warm (warm↔warm):    #{pairs_neither_cold}")
    IO.puts("  → Pairs touching a cold VN (cold↔*):    #{pairs_both_cold + pairs_one_cold}")
    IO.puts("")
    IO.puts("Popular VNs (≥#{popular_threshold} existing sims): #{MapSet.size(popular_vn_ids)}")
    IO.puts("  Of those, gaining ≥1 new pair: #{length(popular_new_pairs)}")
    IO.puts("  New pairs added per popular VN:")
    print_buckets(popular_buckets)
    IO.puts("")
    IO.puts("(No changes made — drop --dry-run to apply.)")
    :ok
  end

  defp pairs_to_counts(pairs) do
    pairs
    |> Enum.flat_map(fn {a, b} -> [a, b] end)
    |> Enum.frequencies()
  end

  defp bucket_counts(counts) do
    Enum.reduce(counts, %{}, fn n, acc ->
      key =
        cond do
          n == 0 -> "0"
          n in 1..2 -> "1-2"
          n in 3..5 -> "3-5"
          n in 6..10 -> "6-10"
          n in 11..15 -> "11-15"
          true -> "16+"
        end

      Map.update(acc, key, 1, &(&1 + 1))
    end)
  end

  defp print_buckets(buckets) do
    Enum.each(["0", "1-2", "3-5", "6-10", "11-15", "16+"], fn key ->
      count = Map.get(buckets, key, 0)
      if count > 0, do: IO.puts("    #{String.pad_trailing(key, 7)} #{count}")
    end)
  end

  defp build_vndb_map do
    from(v in VisualNovel,
      where: not is_nil(v.vndb_id),
      select: {v.vndb_id, v.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp build_rows(data, vndb_map, now) do
    # First pass: collect all directional (source → similar) pairs with scores
    directional_pairs =
      data
      |> Enum.flat_map(fn {source_vndb_id, similar_list} ->
        source_id = Map.get(vndb_map, source_vndb_id)

        if source_id do
          similar_list
          |> Enum.flat_map(fn %{"vndb_id" => similar_vndb_id, "score" => score} ->
            similar_id = Map.get(vndb_map, similar_vndb_id)

            if similar_id && similar_id != source_id do
              [{source_id, similar_id, score}]
            else
              []
            end
          end)
        else
          []
        end
      end)

    # Second pass: normalize IDs and average scores from both directions
    # Average prevents the reverse direction from inflating cross-cluster scores
    # while preserving genuine mutual similarities (unlike min which is too aggressive)
    directional_pairs
    |> Enum.group_by(fn {src, sim, _score} ->
      if src < sim, do: {src, sim}, else: {sim, src}
    end)
    |> Enum.map(fn {{low_id, high_id}, pairs} ->
      scores = pairs |> Enum.map(fn {_, _, s} -> s end)
      avg_score = Enum.sum(scores) / length(scores)

      %{
        visual_novel_id: low_id,
        similar_vn_id: high_id,
        score: avg_score,
        upvotes_count: 0,
        downvotes_count: 0,
        inserted_at: now,
        updated_at: now
      }
    end)
  end
end
