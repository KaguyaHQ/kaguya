defmodule Kaguya.SiteStats.Worker do
  @moduledoc """
  Daily snapshot worker. Writes yesterday's row in `site_stat_snapshots`
  — yesterday is a complete UTC day at 04:05, while today is only ~4
  hours old and would freeze a partial DAU. Then purges the `/site-stats`
  page from Cloudflare so viewers see the fresh data immediately. Monthly
  MAU is computed on the fly at request time from `user_activities`;
  nothing to write here for it.

  Idempotent — re-running for the same day overwrites the row.
  Scheduled in `config/config.exs` Oban crontab at 04:05 UTC, immediately
  after `Kaguya.Stats.RefreshScheduler` (04:00).
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias Kaguya.Repo
  alias Kaguya.SiteStats
  alias Kaguya.SiteStats.{Compute, Snapshot}

  @impl Oban.Worker
  def perform(_job) do
    date = Date.add(Date.utc_today(), -1)
    attrs = Compute.snapshot_for(date)

    %Snapshot{}
    |> Snapshot.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:inserted_at]},
      conflict_target: :date
    )
    |> case do
      {:ok, _snapshot} ->
        Logger.info("Site stats daily snapshot written",
          date: date,
          ratings: attrs.ratings_count,
          reading_statuses: attrs.reading_statuses_count,
          reviews: attrs.reviews_count,
          users: attrs.users_count,
          dau: attrs.dau_count,
          mau_30d: attrs.mau_30d_count,
          vns: attrs.vns_count
        )

        SiteStats.purge_cache()
        :ok

      {:error, changeset} = err ->
        Logger.error("Site stats daily insert failed",
          date: date,
          errors: inspect(changeset.errors)
        )

        err
    end
  rescue
    e ->
      Kaguya.Observability.ErrorReporter.report(e,
        operation: "site_stats.snapshot",
        stacktrace: __STACKTRACE__
      )

      Logger.error("SiteStats.Worker raised",
        worker: "SiteStats.Worker",
        error: inspect(e)
      )

      {:error, e}
  end
end
