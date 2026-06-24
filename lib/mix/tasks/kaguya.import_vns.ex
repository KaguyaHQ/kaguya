defmodule Mix.Tasks.Kaguya.ImportVns do
  @moduledoc """
  Selectively import specific VNs from the VNDB PostgreSQL dump.

  Runs the same dump sync steps as `mix kaguya.dump_sync` but scoped to
  the specified VNs. Skips producers (global) and removals (not applicable).

  ## Usage

      mix kaguya.import_vns --vndb-ids v12345
      mix kaguya.import_vns --vndb-ids v12345,v67890
      mix kaguya.import_vns --vndb-ids v12345 --unban
      mix kaguya.import_vns --vndb-ids v12345 --vndb-db vndb_20260330
      mix kaguya.import_vns --vndb-ids v12345 --step vns,releases

  ## Options

    * `--vndb-ids` - Comma-separated VNDB IDs (required)
    * `--unban` - Remove from banned_vndb_ids before importing
    * `--vndb-db` - VNDB dump database name (default: vndb_latest)
    * `--step` - Run only specific steps (same as dump_sync)
  """
  use Mix.Task
  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.BannedVndbId

  @shortdoc "Selectively import VNs from VNDB dump"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [vndb_ids: :string, unban: :boolean, vndb_db: :string, step: :string],
        aliases: []
      )

    vndb_ids =
      case Keyword.get(opts, :vndb_ids) do
        nil ->
          Mix.shell().error("--vndb-ids is required")
          System.halt(1)

        str ->
          String.split(str, ",", trim: true) |> Enum.map(&String.trim/1)
      end

    # Handle unbanning
    if Keyword.get(opts, :unban, false) do
      banned =
        from(b in BannedVndbId, where: b.vndb_id in ^vndb_ids, select: b.vndb_id) |> Repo.all()

      if banned != [] do
        {count, _} = from(b in BannedVndbId, where: b.vndb_id in ^banned) |> Repo.delete_all()
        Logger.info("Removed #{count} VN(s) from banned_vndb_ids: #{Enum.join(banned, ", ")}")
      end
    end

    # Delegate to DumpSync with target_vndb_ids
    sync_opts = [target_vndb_ids: vndb_ids]

    sync_opts =
      if v = Keyword.get(opts, :vndb_db), do: [{:vndb_db, v} | sync_opts], else: sync_opts

    sync_opts = if v = Keyword.get(opts, :step), do: [{:step, v} | sync_opts], else: sync_opts

    Kaguya.Sync.DumpSync.run(sync_opts)
  end
end
