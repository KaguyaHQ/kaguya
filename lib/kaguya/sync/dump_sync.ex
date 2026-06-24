defmodule Kaguya.Sync.DumpSync do
  @moduledoc """
  Orchestrator for syncing from a local VNDB PostgreSQL dump to Kaguya.

  Two-phase execution:

    Phase 1 — Entity upserts (fail-fast):
      1. VNs          — foundation, everything references these
      2. Producers    — needed by releases
      3. Characters   — entity + VN-character junctions
      4. Quotes       — VN quotes (needs VN + character mappings)
      5. Tags         — entity + VN-tag junctions

    ── mappings reloaded (new entities visible to phase 2) ──

    Phase 2 — Dependent steps (best-effort):
      6. Relations    — VN-VN junctions
      7. Releases     — releases + extlinks + VN-producers
      8. Removals     — delete stale rows
      9. Images       — process covers + character images
     10. Post-sync    — reindex search, recompute relevance, recompute
                        languages/platforms/series, clear caches
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.BannedVndbId
  alias Kaguya.Characters.Character
  alias Kaguya.Producers.Producer
  alias Kaguya.VisualNovels.VisualNovel

  @default_vndb_db "vndb_latest"
  @chunk_size 500

  @entity_steps [
    {:vns, Kaguya.Sync.DumpSync.VNs},
    {:producers, Kaguya.Sync.DumpSync.Producers},
    {:characters, Kaguya.Sync.DumpSync.Characters},
    {:quotes, Kaguya.Sync.DumpSync.Quotes},
    {:tags, Kaguya.Sync.DumpSync.Tags}
  ]

  @dependent_steps [
    {:relations, Kaguya.Sync.DumpSync.Relations},
    {:releases, Kaguya.Sync.DumpSync.Releases},
    {:removals, Kaguya.Sync.DumpSync.Removals},
    {:images, Kaguya.Sync.DumpSync.Images},
    {:post_sync, Kaguya.Sync.DumpSync.PostSync}
  ]

  @all_steps @entity_steps ++ @dependent_steps

  # Which mappings each entity step affects
  @step_mapping_keys %{
    vns: [:vn_mapping],
    producers: [:producer_mapping],
    characters: [:char_mapping],
    tags: [:tag_mapping]
  }

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Run all steps in order, or a single step by name.

  Options:
    * `:target_vndb_ids` — list of VNDB IDs (e.g. ["v12345"]) for selective import.
      When set, only those VNs are processed and steps that don't apply (producers,
      removals) are skipped automatically unless overridden with `:step`.
  """
  def run(opts \\ []) do
    step_filter = Keyword.get(opts, :step)
    dry_run = Keyword.get(opts, :dry_run, false)
    overview_only = Keyword.get(opts, :overview, false)
    vndb_db = Keyword.get(opts, :vndb_db, @default_vndb_db)
    target_vndb_ids = Keyword.get(opts, :target_vndb_ids)

    targeted? = is_list(target_vndb_ids) and target_vndb_ids != []
    label = if targeted?, do: " (targeted: #{Enum.join(target_vndb_ids, ", ")})", else: ""

    Logger.info(
      "Starting VNDB dump sync#{if dry_run, do: " (DRY RUN)", else: ""}#{label} (source: #{vndb_db})..."
    )

    {:ok, vndb} = connect_vndb(vndb_db)
    Logger.info("Connected to VNDB dump database '#{vndb_db}'")

    if not targeted?, do: display_overview(vndb)

    if overview_only do
      if Process.alive?(vndb), do: GenServer.stop(vndb)
      Logger.info("Overview only — no steps executed.")
      %{}
    else
      Report.start()

      ctx = build_context(vndb, dry_run, target_vndb_ids)

      steps_to_run =
        if step_filter do
          filter_steps(step_filter)
        else
          if targeted? do
            # Skip producers (global) and removals (adding, not removing)
            @all_steps |> Enum.reject(fn {name, _} -> name in [:producers, :removals] end)
          else
            @all_steps
          end
        end

      results = run_steps(steps_to_run, ctx)

      if Process.alive?(vndb), do: GenServer.stop(vndb)

      case Report.write_report(step_filter) do
        nil -> Logger.info("No report data to write.")
        path -> Logger.info("Sync report saved to: #{path}")
      end

      Report.stop()

      Logger.info("Dump sync finished. Results: #{inspect(results)}")
      if not dry_run, do: Kaguya.Sitemaps.PublisherWorker.enqueue_full()
      results
    end
  end

  # ── Connection ──────────────────────────────────────────────────────────────

  def connect_vndb(database \\ @default_vndb_db) do
    config = Application.get_env(:kaguya, :vndb_dump, [])

    Postgrex.start_link(
      hostname: System.get_env("VNDB_DUMP_HOST") || Keyword.get(config, :hostname, "localhost"),
      database: database,
      username:
        System.get_env("VNDB_DUMP_USERNAME") || Keyword.get(config, :username, "postgres"),
      password: System.get_env("VNDB_DUMP_PASSWORD") || Keyword.get(config, :password, ""),
      port: vndb_dump_port(config),
      timeout: Keyword.get(config, :timeout, :infinity)
    )
  end

  defp vndb_dump_port(config) do
    case System.get_env("VNDB_DUMP_PORT") do
      nil -> Keyword.get(config, :port, 5432)
      value -> String.to_integer(value)
    end
  end

  # ── Shared Lookups ──────────────────────────────────────────────────────────

  def load_vn_mapping, do: load_mapping(VisualNovel, :vndb_id)
  def load_tag_mapping, do: load_mapping(Tag, :vndb_tag_id)
  def load_char_mapping, do: load_mapping(Character, :vndb_id)
  def load_producer_mapping, do: load_mapping(Producer, :vndb_id)

  def load_banned_ids do
    banned =
      from(b in BannedVndbId, select: b.vndb_id)
      |> Repo.all()

    # Merged VNDB ids are also skipped at sync time. The source row was
    # deleted as part of the merge; if VNDB still serves the id we don't
    # want to recreate the source. Behaves identically to a banned id
    # for `step_01` (skip insert) and `step_07` (no-op — there's no
    # Kaguya row left to remove). See `Kaguya.VisualNovels.Merge` and
    # the `vn_merges` table.
    MapSet.new(banned ++ Kaguya.VisualNovels.Merge.merged_vndb_ids())
  end

  @ero_prop_threshold 0.75
  @min_tag_weight 20

  @bestiality_tag "g183"

  @doc """
  Classifies VNs as nukige using three methods:

  1. Ero proportion (ero_prop >= 0.75) — tag-based narrative vs ero ratio
  2. No-votes NSFW — 0 VNDB votes + sexual covers (c_sexual_avg >= 150)
  3. Bestiality — tag rank method from moderation README

  Returns a MapSet of VNDB IDs.
  """
  def classify_nukige_from_dump(vndb) do
    ero_prop_ids = classify_by_ero_prop(vndb)
    no_votes_ids = classify_no_votes_nsfw(vndb)
    bestiality_ids = classify_bestiality(vndb)

    combined = MapSet.union(ero_prop_ids, MapSet.union(no_votes_ids, bestiality_ids))

    Logger.info(
      "[DumpSync] Nukige classifier: #{MapSet.size(ero_prop_ids)} ero_prop + #{MapSet.size(no_votes_ids)} no-votes-nsfw + #{MapSet.size(bestiality_ids)} bestiality = #{MapSet.size(combined)} total"
    )

    combined
  end

  defp classify_by_ero_prop(vndb) do
    tsv_path =
      Path.join(:code.priv_dir(:kaguya), "repo/scripts/moderation/tag_classification.tsv")

    if File.exists?(tsv_path) do
      load_tag_classification_into_vndb(vndb, tsv_path)

      rows =
        query_vndb!(
          vndb,
          """
          WITH per_tag AS (
            SELECT tv.vid, tc.classification,
                   COUNT(*) as voters,
                   AVG(tv.vote)::numeric as avg_vote
            FROM tags_vn tv
            JOIN _tag_class tc ON tc.tag_id = tv.tag
            WHERE NOT tv.ignore AND tc.classification IN ('ero', 'narrative')
            GROUP BY tv.vid, tv.tag, tc.classification
          ),
          signals AS (
            SELECT vid, classification,
                   GREATEST(voters * avg_vote, 0) as signal
            FROM per_tag
          ),
          per_vn AS (
            SELECT vid,
                   COALESCE(SUM(signal) FILTER (WHERE classification = 'ero'), 0) as ero_w,
                   COALESCE(SUM(signal) FILTER (WHERE classification = 'narrative'), 0) as narr_w
            FROM signals
            GROUP BY vid
            HAVING COALESCE(SUM(signal) FILTER (WHERE classification = 'ero'), 0) +
                   COALESCE(SUM(signal) FILTER (WHERE classification = 'narrative'), 0) >= $1
          )
          SELECT vid FROM per_vn
          WHERE (ero_w + narr_w) > 0
            AND ero_w / (ero_w + narr_w) >= $2
          """,
          [@min_tag_weight, @ero_prop_threshold]
        )

      MapSet.new(rows, & &1.vid)
    else
      Logger.warning(
        "[DumpSync] tag_classification.tsv not found, skipping ero_prop classification"
      )

      MapSet.new()
    end
  end

  # No-votes NSFW: 0 VNDB votes + sexual/explicit covers (c_sexual_avg >= 150)
  # ID cutoff prevents misclassifying new VNs that simply haven't been voted on yet
  @no_votes_id_cutoff 56000

  defp classify_no_votes_nsfw(vndb) do
    rows =
      query_vndb!(
        vndb,
        """
        SELECT v.id AS vid
        FROM vn v
        WHERE v.c_votecount = 0
          AND CAST(SUBSTRING(v.id FROM 2) AS integer) < $1
          AND v.c_image IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM images i
            WHERE i.id = v.c_image
              AND i.c_sexual_avg >= 150
              AND i.c_votecount >= 3
          )
        """,
        [@no_votes_id_cutoff]
      )

    MapSet.new(rows, & &1.vid)
  end

  # Bestiality: tag rank method — if bestiality is among the top-ranked tags, it's core content
  # Also catches VNs with no description + any bestiality tag
  defp classify_bestiality(vndb) do
    rows =
      query_vndb!(
        vndb,
        """
        WITH tag_ranks AS (
          SELECT tv.vid, tv.tag,
                 COUNT(*) as voters,
                 AVG(tv.vote)::numeric as avg_vote,
                 ROW_NUMBER() OVER (PARTITION BY tv.vid ORDER BY COUNT(*) DESC) as rank
          FROM tags_vn tv
          WHERE NOT tv.ignore AND tv.vote > 0
          GROUP BY tv.vid, tv.tag
        )
        SELECT vid FROM tag_ranks
        WHERE tag = $1
          AND (
            rank = 1
            OR (rank <= 3 AND avg_vote >= 2.0)
            OR (rank <= 5 AND avg_vote >= 2.5)
          )

        UNION

        SELECT tv.vid FROM tags_vn tv
        JOIN vn v ON v.id = tv.vid
        WHERE tv.tag = $1
          AND NOT tv.ignore
          AND tv.vote > 0
          AND (v.description IS NULL OR v.description = '')
        """,
        [@bestiality_tag]
      )

    MapSet.new(rows, & &1.vid)
  end

  defp load_tag_classification_into_vndb(vndb, tsv_path) do
    query_vndb_raw!(vndb, """
    CREATE TEMP TABLE IF NOT EXISTS _tag_class (
      tag_id text PRIMARY KEY, classification text NOT NULL
    )
    """)

    query_vndb_raw!(vndb, "TRUNCATE _tag_class")

    # Parse TSV and batch-insert (COPY requires server-side file access)
    rows =
      tsv_path
      |> File.stream!()
      |> Stream.drop(1)
      |> Stream.map(fn line ->
        case String.split(String.trim(line), "\t") do
          [tag_id, _name, _cat, classification | _] -> {tag_id, classification}
          _ -> nil
        end
      end)
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(fn {_id, c} -> c in ["ero", "narrative"] end)
      |> Enum.to_list()

    # Batch insert in chunks of 500
    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      values = Enum.map_join(chunk, ", ", fn {id, c} -> "('#{id}', '#{c}')" end)

      query_vndb_raw!(vndb, """
      INSERT INTO _tag_class (tag_id, classification) VALUES #{values}
      ON CONFLICT (tag_id) DO NOTHING
      """)
    end)

    Logger.info("[DumpSync] Loaded #{length(rows)} tag classifications (ero + narrative)")
  end

  defp load_mapping(schema, key_field) do
    from(s in schema,
      where: not is_nil(field(s, ^key_field)),
      select: {field(s, ^key_field), s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Batch Utilities ─────────────────────────────────────────────────────────

  @doc "Build $1, $2, ... placeholder string for parameterized queries."
  def placeholders(list) do
    Enum.map_join(1..length(list), ", ", &"$#{&1}")
  end

  @doc """
  Insert rows via `Repo.insert_all` in chunks.
  Accepts the same opts as `Repo.insert_all` plus `:chunk_size`.
  Returns total rows inserted/upserted.
  """
  def chunked_insert(_schema, [], _opts), do: 0

  def chunked_insert(schema, rows, opts) do
    {chunk_size, opts} = Keyword.pop(opts, :chunk_size, @chunk_size)

    rows
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} = Repo.insert_all(schema, chunk, opts)
      acc + count
    end)
  end

  # ── VNDB Dump Queries ────────────────────────────────────────────────────────

  @doc "Execute a query against the VNDB dump. Raises on error."
  def query_vndb!(vndb, sql, params \\ []) do
    case Postgrex.query(vndb, sql, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        rows_to_maps(rows, columns)

      {:error, err} ->
        raise "VNDB query failed: #{inspect(err)}"
    end
  end

  @doc "Execute a query against the VNDB dump. Returns [] on error (use for non-critical reads)."
  def query_vndb(vndb, sql, params \\ []) do
    case Postgrex.query(vndb, sql, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        rows_to_maps(rows, columns)

      {:error, err} ->
        Logger.error("VNDB query failed: #{inspect(err)}")
        []
    end
  end

  @doc "Execute a query and return raw rows. Raises on error."
  def query_vndb_raw!(vndb, sql, params \\ []) do
    case Postgrex.query(vndb, sql, params) do
      {:ok, %{rows: rows}} -> rows
      {:error, err} -> raise "VNDB query failed: #{inspect(err)}"
    end
  end

  @doc "Execute a query and return raw rows. Returns [] on error."
  def query_vndb_raw(vndb, sql, params \\ []) do
    case Postgrex.query(vndb, sql, params) do
      {:ok, %{rows: rows}} ->
        rows

      {:error, err} ->
        Logger.error("VNDB query failed: #{inspect(err)}")
        []
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  @doc "Parse VNDB dump integer date (YYYYMMDD) to Elixir Date."
  def parse_vndb_date(val) when val in [0, nil], do: nil
  def parse_vndb_date(val) when is_integer(val) and val >= 99_990_000, do: nil

  def parse_vndb_date(yyyymmdd) when is_integer(yyyymmdd) do
    year = div(yyyymmdd, 10000)
    month = yyyymmdd |> rem(10000) |> div(100) |> clamp(1, 12)
    day = rem(yyyymmdd, 100)

    # Try actual day first; fall back to day=1 for unknown (99) or invalid days
    case Date.new(year, month, day) do
      {:ok, date} ->
        date

      {:error, _} ->
        case Date.new(year, month, 1) do
          {:ok, date} -> date
          {:error, _} -> nil
        end
    end
  end

  def parse_vndb_date(_), do: nil

  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp clamp(val, min, max), do: val |> Kernel.max(min) |> Kernel.min(max)

  # ── Pre-Sync Overview ───────────────────────────────────────────────────────

  @overview_comparisons [
    {"VNs", "SELECT count(*) FROM vn", {VisualNovel, nil}},
    {"Characters", "SELECT count(*) FROM chars", {Character, nil}},
    {"Producers", "SELECT count(*) FROM producers", {Producer, nil}},
    {"Tags", "SELECT count(*) FROM tags", {Tag, :vndb_tag_id}},
    {"Releases", "SELECT count(*) FROM releases", {"vn_releases", nil}},
    {"VN-Characters", "SELECT count(*) FROM chars_vns", {"vn_characters", nil}},
    {"VN-Relations", "SELECT count(*) FROM vn_relations", {"vn_relations", nil}},
    {"VN-Producers",
     "SELECT count(DISTINCT (pid, vid)) FROM releases_producers rp JOIN releases_vn rv ON rv.id = rp.id",
     {"vn_producers", nil}}
  ]

  defp display_overview(vndb) do
    rows =
      Enum.map(@overview_comparisons, fn {label, vndb_sql, {kaguya_source, vndb_id_field}} ->
        [[vndb_count]] = query_vndb_raw!(vndb, vndb_sql)

        kaguya_count =
          case kaguya_source do
            table when is_binary(table) ->
              %{rows: [[n]]} = Repo.query!("SELECT count(*) FROM #{table}")
              n

            schema when is_atom(schema) ->
              q =
                if vndb_id_field,
                  do: from(s in schema, where: not is_nil(field(s, ^vndb_id_field))),
                  else: schema

              Repo.aggregate(q, :count)
          end

        diff = vndb_count - kaguya_count
        {label, kaguya_count, vndb_count, diff}
      end)

    IO.puts("\n  ┌─────────────────┬────────────┬────────────┬────────────┐")
    IO.puts("  │ Entity          │     Kaguya │       VNDB │       Diff │")
    IO.puts("  ├─────────────────┼────────────┼────────────┼────────────┤")

    Enum.each(rows, fn {label, kaguya, vndb, diff} ->
      sign =
        cond do
          diff > 0 -> "+"
          diff < 0 -> ""
          true -> " "
        end

      IO.puts(
        "  │ #{String.pad_trailing(label, 15)} │ #{String.pad_leading(format_number(kaguya), 10)} │ " <>
          "#{String.pad_leading(format_number(vndb), 10)} │ #{String.pad_leading("#{sign}#{format_number(diff)}", 10)} │"
      )
    end)

    IO.puts("  └─────────────────┴────────────┴────────────┴────────────┘\n")
  end

  defp format_number(n) when is_integer(n) and n >= 0 and n < 1000, do: Integer.to_string(n)
  defp format_number(n) when is_integer(n) and n < 0, do: "-#{format_number(abs(n))}"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp build_context(vndb, dry_run, target_vndb_ids) do
    banned_ids = load_banned_ids()

    # Classify nukige from VNDB dump tag data (ero_prop >= 0.75)
    # Exclude banned VNs — they must never be categorized or imported
    nukige_ids = classify_nukige_from_dump(vndb)

    category_map =
      nukige_ids
      |> Enum.reject(fn id -> MapSet.member?(banned_ids, id) end)
      |> Map.new(fn id -> {id, :nukige} end)

    ctx = %{
      vndb: vndb,
      dry_run: dry_run,
      vn_mapping: load_vn_mapping(),
      banned_ids: banned_ids,
      category_map: category_map,
      tag_mapping: load_tag_mapping(),
      char_mapping: load_char_mapping(),
      producer_mapping: load_producer_mapping(),
      target_vndb_ids: target_vndb_ids
    }

    log_mappings("Initial", ctx)
    ctx
  end

  defp reload_mappings(ctx, keys) do
    loaders = %{
      vn_mapping: &load_vn_mapping/0,
      tag_mapping: &load_tag_mapping/0,
      char_mapping: &load_char_mapping/0,
      producer_mapping: &load_producer_mapping/0
    }

    Enum.reduce(keys, ctx, fn key, ctx ->
      old = Map.get(ctx, key)
      new = loaders[key].()
      delta = map_size(new) - map_size(old)

      if delta != 0 do
        Logger.info(
          "  #{key}: #{map_size(old)} → #{map_size(new)} (#{if delta > 0, do: "+"}#{delta})"
        )
      end

      Map.put(ctx, key, new)
    end)
  end

  defp log_mappings(label, ctx) do
    Logger.info(
      "#{label} mappings: #{map_size(ctx.vn_mapping)} VNs, " <>
        "#{map_size(ctx.tag_mapping)} tags, " <>
        "#{map_size(ctx.char_mapping)} characters, " <>
        "#{map_size(ctx.producer_mapping)} producers, " <>
        "#{MapSet.size(ctx.banned_ids)} banned, " <>
        "#{map_size(ctx.category_map)} nukige (classifier)"
    )
  end

  defp run_steps(steps, ctx) do
    entity_names = MapSet.new(@entity_steps, &elem(&1, 0))

    {entity, dependent} =
      Enum.split_with(steps, fn {name, _} -> MapSet.member?(entity_names, name) end)

    # Phase 1: Entity steps (fail-fast)
    {results, ctx} = run_phase(entity, ctx, _fail_fast = true)

    if has_failure?(results) do
      Logger.error("Entity step failed — skipping dependent steps")
      results
    else
      # Reload only the mappings that entity steps changed
      changed_keys =
        entity
        |> Enum.flat_map(fn {name, _} -> Map.get(@step_mapping_keys, name, []) end)
        |> Enum.uniq()

      ctx =
        if changed_keys != [] do
          Logger.info("Reloading mappings: #{Enum.join(changed_keys, ", ")}")
          reload_mappings(ctx, changed_keys)
        else
          ctx
        end

      # Phase 2: Dependent steps (best-effort)
      {dep_results, _ctx} = run_phase(dependent, ctx, _fail_fast = false)
      Map.merge(results, dep_results)
    end
  end

  defp run_phase(steps, ctx, fail_fast) do
    Enum.reduce_while(steps, {%{}, ctx}, fn {name, module}, {acc, ctx} ->
      Logger.info("━━━ Step: #{name} ━━━")
      start = System.monotonic_time(:millisecond)

      result =
        try do
          module.run(ctx)
        rescue
          e ->
            Logger.error("Step #{name} failed: #{Exception.message(e)}")
            Logger.error(Exception.format(:error, e, __STACKTRACE__))
            {:error, Exception.message(e)}
        end

      elapsed = System.monotonic_time(:millisecond) - start
      Logger.info("Step #{name} completed in #{format_duration(elapsed)}")

      acc = Map.put(acc, name, result)

      if fail_fast and match?({:error, _}, result) do
        {:halt, {acc, ctx}}
      else
        {:cont, {acc, ctx}}
      end
    end)
  end

  defp has_failure?(results) do
    Enum.any?(results, fn {_name, result} -> match?({:error, _}, result) end)
  end

  defp filter_steps(nil), do: @all_steps

  defp filter_steps(step_name) when is_binary(step_name) do
    if String.contains?(step_name, ",") do
      # Comma-separated: --step vns,tags,releases
      names =
        step_name
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_existing_atom(String.trim(&1)))
        |> MapSet.new()

      Enum.filter(@all_steps, fn {n, _} -> MapSet.member?(names, n) end)
    else
      name = String.to_existing_atom(step_name)
      Enum.filter(@all_steps, fn {n, _} -> n == name end)
    end
  rescue
    ArgumentError -> []
  end

  defp rows_to_maps(rows, columns) do
    col_atoms = Enum.map(columns, &String.to_atom/1)
    Enum.map(rows, fn row -> col_atoms |> Enum.zip(row) |> Map.new() end)
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}min"
end
