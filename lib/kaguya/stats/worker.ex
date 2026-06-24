defmodule Kaguya.Stats.Worker do
  @moduledoc """
  Oban worker that recomputes a user's VN stats snapshot.

  Scheduled in two ways:
    * Daily by `Kaguya.Stats.RefreshScheduler` for users active in the last 26h
    * On demand by the `kaguya.backfill_vn_stats` mix task

  This worker only knows one job type: `vn_full_snapshot`.

  Year-specific snapshots are currently disabled — the worker only handles
  the all-time (`period: nil`) case. The integer-year clause plus the
  threshold / delete helpers are preserved in comments below for easy
  revival when year pages come back.
  """
  use Oban.Worker, queue: :stats, max_attempts: 3

  alias Kaguya.Stats
  alias Oban.Job

  @doc """
  Enqueue a snapshot rebuild for `user_id` and `period`.

  `period` is currently always `nil` (all-time). The integer-year path is
  disabled — see the commented clause in `perform/1`.
  """
  def enqueue(:vn_full_snapshot, user_id, period) do
    %{"type" => "vn_full_snapshot", "user_id" => user_id, "period" => period}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Job{args: %{"type" => "vn_full_snapshot", "user_id" => user_id, "period" => nil}}) do
    case Stats.compute_and_upsert_snapshot(user_id, nil) do
      {:ok, _} ->
        :ok

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        # User was deleted between scheduler enqueue and worker run —
        # cascade wiped their activity, so nothing to snapshot. Discard.
        if Keyword.get(errors, :user_id) |> fk_violation?() do
          :ok
        else
          error
        end
    end
  end

  # YEAR-STATS DISABLED — preserved for easy revival.
  #
  # def perform(%Job{args: %{"type" => "vn_full_snapshot", "user_id" => user_id, "period" => year}})
  #     when is_integer(year) do
  #   if year_qualifies?(user_id, year) do
  #     compute_and_upsert(user_id, year)
  #   else
  #     delete_year_snapshot(user_id, year)
  #     :ok
  #   end
  # end

  # Catch-all to discard year jobs that might still exist from before the
  # disable (e.g. in flight when the change deployed). Can be removed once
  # such jobs are guaranteed drained.
  def perform(%Job{args: %{"type" => "vn_full_snapshot", "period" => period}})
      when is_integer(period) do
    :ok
  end

  defp fk_violation?({_msg, opts}) when is_list(opts),
    do: Keyword.get(opts, :constraint) == :foreign

  defp fk_violation?(_), do: false

  # YEAR-STATS DISABLED — helpers preserved for revival.
  #
  # defp year_qualifies?(user_id, year) do
  #   {start_date, end_date} = year_range(year)
  #
  #   count =
  #     ReadingStatus
  #     |> where(
  #       [rs],
  #       rs.user_id == ^user_id and rs.status == :read and
  #         rs.date_finished >= ^start_date and rs.date_finished < ^end_date
  #     )
  #     |> Repo.aggregate(:count, :id)
  #
  #   count >= Stats.year_snapshot_threshold()
  # end
  #
  # defp delete_year_snapshot(user_id, year) do
  #   from(s in UserPeriodStat,
  #     where: s.user_id == ^user_id and s.period == ^year
  #   )
  #   |> Repo.delete_all()
  # end
  #
  # defp year_range(year) do
  #   {Date.new!(year, 1, 1), Date.new!(year + 1, 1, 1)}
  # end
end
