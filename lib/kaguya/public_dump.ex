defmodule Kaguya.PublicDump do
  @moduledoc """
  Public DB dump pipeline.

  Mirrors VNDB's `util/dbdump.pl export-db`. Reads from `Kaguya.Repo` inside
  a SERIALIZABLE READ ONLY DEFERRABLE transaction (consistent snapshot),
  writes one TSV per table + `schema.sql` + `import.sql` + README/TIMESTAMP/
  (LICENSE files when present), then bundles into a tar archive.

  Run via the `mix kaguya.export_public_dump` task.
  """

  require Logger

  alias Kaguya.PublicDump.{Archive, SchemaWriter, Spec, SqlBuilder, Tables}
  alias Kaguya.Repo

  @doc """
  Run the dump.

  Options:
    * `:output` — output archive path (required). Extension is applied
      automatically based on whether `zstd` is installed.
    * `:dry_run` — log row counts per table; don't write files.
    * `:tables` — restrict to these table names (atoms). Defaults to all.
  """
  def run(opts) do
    output = Keyword.fetch!(opts, :output)
    dry_run = Keyword.get(opts, :dry_run, false)
    table_filter = Keyword.get(opts, :tables)

    specs = filter_tables(Tables.all(), table_filter)

    Logger.info("Public dump: #{length(specs)} tables → #{output}#{if dry_run, do: " (DRY RUN)"}")

    if dry_run, do: log_counts(specs), else: export(specs, output)
    :ok
  end

  defp filter_tables(all, nil), do: all
  defp filter_tables(all, names), do: Enum.filter(all, &(&1.name in names))

  defp log_counts(specs) do
    in_snapshot(fn ->
      for spec <- specs do
        %{rows: [[count]]} = Repo.query!(count_sql(spec))
        Logger.info("  #{spec.name}: #{count}")
      end
    end)
  end

  defp export(specs, output) do
    staging = output <> ".staging"
    File.rm_rf!(staging)
    File.mkdir_p!(Path.join(staging, "db"))

    in_snapshot(fn ->
      write_timestamp(staging)
      Enum.each(specs, &copy_table_to_file(&1, staging))
      SchemaWriter.write_schema(specs, Path.join(staging, "schema.sql"))
      SchemaWriter.write_import(specs, Path.join(staging, "import.sql"))
      copy_static_files(staging)
    end)

    Archive.create(staging, output)
    File.rm_rf!(staging)
    :ok
  end

  # ── snapshot + per-table writers ───────────────────────────────────────────

  # SERIALIZABLE READ ONLY DEFERRABLE = consistent snapshot, no write conflicts.
  # Wraps the entire dump in one transaction so every table sees the same view.
  defp in_snapshot(func) do
    Repo.transaction(
      fn ->
        Repo.query!("SET TIME ZONE 'UTC'")
        Repo.query!("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE")
        func.()
      end,
      timeout: :infinity
    )
  end

  defp copy_table_to_file(%Spec{} = spec, staging) do
    path = Path.join([staging, "db", Atom.to_string(spec.name)])
    sql = SqlBuilder.build(spec)
    started = System.monotonic_time(:millisecond)

    File.open!(path, [:write, :binary], fn file ->
      Repo
      |> Ecto.Adapters.SQL.stream(sql, [], log: false)
      |> Stream.flat_map(& &1.rows)
      |> Stream.each(&IO.binwrite(file, &1))
      |> Stream.run()
    end)

    elapsed = System.monotonic_time(:millisecond) - started
    %{size: bytes} = File.stat!(path)
    Logger.info("  #{spec.name}: #{elapsed}ms, #{div(bytes, 1024)} KiB")
  end

  # ── auxiliary files ───────────────────────────────────────────────────────

  defp write_timestamp(staging) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    File.write!(Path.join(staging, "TIMESTAMP"), ts <> "\n")
  end

  defp copy_static_files(staging) do
    src = Application.app_dir(:kaguya, "priv/dump")

    if File.dir?(src) do
      for file <- File.ls!(src) do
        File.cp!(Path.join(src, file), Path.join(staging, file))
      end
    end
  end

  # ── count queries (dry-run) ───────────────────────────────────────────────

  defp count_sql(%Spec{sql: sql}) when is_binary(sql) do
    "SELECT count(*) FROM (#{String.trim_trailing(sql)}) sub"
  end

  defp count_sql(%Spec{name: name, where: where}) do
    where_clause = if where && where != "", do: " WHERE #{String.trim_trailing(where)}", else: ""
    "SELECT count(*) FROM #{name} x#{where_clause}"
  end
end
