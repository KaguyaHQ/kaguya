defmodule Mix.Tasks.Kaguya.DumpSync do
  @moduledoc """
  Syncs Kaguya database from a local VNDB PostgreSQL dump.

  ## Usage

      mix kaguya.dump_sync                          # run all steps
      mix kaguya.dump_sync --step vns               # single step
      mix kaguya.dump_sync --step vns,producers,tags  # multiple steps
      mix kaguya.dump_sync --overview              # show Kaguya vs VNDB counts only
      mix kaguya.dump_sync --dry-run                # show counts, don't write
      mix kaguya.dump_sync --vndb-db vndb_latest    # use a different source database

  ## Steps (in execution order)

      1. vns         - VN core data (titles, ratings, descriptions)
      2. producers   - Producer entities + external links
      3. characters  - Characters + VN-character junctions
      4. quotes      - VN quotes (score >= 0)
      5. tags        - Tag definitions + parent hierarchy + VN-tag associations
      6. relations   - VN-VN relations
      7. releases    - Releases + extlinks + VN-producers
      8. removals    - Detect & remove stale entities (13 categories)
      9. images      - Process covers + character images + screenshots
     10. post_sync   - Recompute tag relevance, repopulate languages/platforms,
                       regenerate series, reindex search, clear caches
  """
  use Mix.Task
  require Logger

  @shortdoc "Sync Kaguya from VNDB PostgreSQL dump"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [step: :string, dry_run: :boolean, overview: :boolean, vndb_db: :string],
        aliases: [s: :step, n: :dry_run]
      )

    Kaguya.Sync.DumpSync.run(opts)
  end
end
