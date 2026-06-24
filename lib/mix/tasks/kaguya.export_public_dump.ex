defmodule Mix.Tasks.Kaguya.ExportPublicDump do
  @moduledoc """
  Export the Kaguya public DB dump.

  ## Usage

      mix kaguya.export_public_dump --output /tmp/kaguya-dump
      mix kaguya.export_public_dump --output /tmp/out --dry-run
      mix kaguya.export_public_dump --output /tmp/out --table visual_novels --table tags

  Output file extension (`.tar.zst` or `.tar.gz`) is applied automatically
  depending on whether `zstd` is installed.

  ## Options

    * `--output PATH` (required) — destination archive path.
    * `--dry-run` — log row counts per table; don't write files.
    * `--table NAME` — restrict to a single table. Repeatable.
  """

  use Mix.Task

  @shortdoc "Export the Kaguya public DB dump"

  def run(args) do
    # Start Repo only (not the Phoenix endpoint), so this can run alongside
    # `mix phx.server` without binding 4000 twice. `app.config` is needed
    # so `runtime.exs` evaluates — that's where MIX_ENV=prod reads
    # DATABASE_URL etc.
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    case Kaguya.Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output: :string, dry_run: :boolean, table: [:string, :keep]],
        aliases: [o: :output, n: :dry_run]
      )

    tables =
      case Keyword.get_values(opts, :table) do
        [] -> nil
        names -> Enum.map(names, &String.to_atom/1)
      end

    Kaguya.PublicDump.run(
      output: Keyword.fetch!(opts, :output),
      dry_run: Keyword.get(opts, :dry_run, false),
      tables: tables
    )
  end
end
