defmodule Kaguya.Stats.RefreshScheduler do
  @moduledoc """
  Daily Oban worker that enqueues VN stats snapshot refreshes for users who
  have had any stats-relevant activity in the last 26 hours.

  "Activity" means: a `reading_statuses`, `ratings`, or `reviews` row
  inserted or updated. Idle users are skipped — their snapshot remains valid
  until they touch something.

  Year-specific snapshots are currently disabled — the cron enqueues only the
  all-time (`period: nil`) snapshot per active user. The year-handling code is
  preserved in comments below so it can be re-enabled when/if year pages come
  back (see `Kaguya.Stats.year_snapshot_threshold/0` and the commented block
  in `Kaguya.Stats.Worker.perform/1`).

  Scheduled in `config/config.exs` Oban crontab:

      {"0 4 * * *", Kaguya.Stats.RefreshScheduler}  # 04:00 UTC daily
  """

  use Oban.Worker, queue: :stats, max_attempts: 1

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Stats.Worker

  # 26 hours: a 24h cadence with 2 hours of overlap so cron skew or a slow
  # previous run can never leave a window of activity uncovered.
  @lookback_hours 26

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@lookback_hours, :hour)
    user_ids = active_user_ids(cutoff)

    case user_ids do
      [] ->
        :ok

      ids ->
        jobs =
          Enum.map(ids, fn uid ->
            Worker.new(%{
              "type" => "vn_full_snapshot",
              "user_id" => uid,
              "period" => nil
            })
          end)

        # YEAR-STATS DISABLED — previous implementation below also enqueued
        # per-year snapshot jobs. Uncomment to re-enable year pages.
        #
        # alias Kaguya.Stats
        # alias Kaguya.Stats.UserPeriodStat
        #
        # qualifying = qualifying_years_by_user(ids)
        # existing = snapshot_years_by_user(ids)
        #
        # jobs =
        #   Enum.flat_map(ids, fn uid ->
        #     years =
        #       Enum.uniq(Map.get(qualifying, uid, []) ++ Map.get(existing, uid, []))
        #
        #     periods = [nil | years]
        #
        #     Enum.map(periods, fn period ->
        #       Worker.new(%{
        #         "type" => "vn_full_snapshot",
        #         "user_id" => uid,
        #         "period" => period
        #       })
        #     end)
        #   end)

        Oban.insert_all(jobs)
        :ok
    end
  end

  # Returns a deduped list of user_ids whose reading_status, rating, or review
  # rows were touched at or after `cutoff`.
  defp active_user_ids(cutoff) do
    rs_q =
      from rs in ReadingStatus,
        where: rs.updated_at >= ^cutoff,
        select: rs.user_id

    rating_q =
      from r in Rating,
        where: r.updated_at >= ^cutoff,
        select: r.user_id

    review_q =
      from r in Review,
        where: r.updated_at >= ^cutoff,
        select: r.user_id

    rs_q
    |> union(^rating_q)
    |> union(^review_q)
    |> Repo.all()
  end

  # YEAR-STATS DISABLED — helpers kept in comments for easy revival.
  #
  # For each user_id in the input, returns a map of user_id => list of years
  # that currently meet the qualification threshold for getting a year-specific
  # snapshot. One query, grouped by user + year, filtered by HAVING.
  #
  # defp qualifying_years_by_user(user_ids) do
  #   threshold = Kaguya.Stats.year_snapshot_threshold()
  #
  #   from(rs in ReadingStatus,
  #     where:
  #       rs.user_id in ^user_ids and rs.status == :read and not is_nil(rs.date_finished),
  #     group_by: [rs.user_id, fragment("EXTRACT(year FROM ?)::int", rs.date_finished)],
  #     having: count(rs.id) >= ^threshold,
  #     select: {rs.user_id, fragment("EXTRACT(year FROM ?)::int", rs.date_finished)}
  #   )
  #   |> Repo.all()
  #   |> Enum.group_by(fn {uid, _year} -> uid end, fn {_uid, year} -> year end)
  # end
  #
  # For each user_id in the input, returns a map of user_id => list of years
  # that already have a UserPeriodStat row. We re-enqueue these so the worker
  # can clean up snapshots for years that no longer qualify.
  #
  # defp snapshot_years_by_user(user_ids) do
  #   from(s in Kaguya.Stats.UserPeriodStat,
  #     where: s.user_id in ^user_ids and not is_nil(s.period),
  #     select: {s.user_id, s.period}
  #   )
  #   |> Repo.all()
  #   |> Enum.group_by(fn {uid, _year} -> uid end, fn {_uid, year} -> year end)
  # end
end
