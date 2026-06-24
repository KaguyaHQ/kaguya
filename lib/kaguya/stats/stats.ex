defmodule Kaguya.Stats do
  @moduledoc """
  Public API for reading user VN stats.

  Stats snapshots are written in the background by `Kaguya.Stats.Worker`,
  scheduled daily by `Kaguya.Stats.RefreshScheduler` for users with recent
  activity. Reads happen here.

  ## Year-specific stats currently disabled

  Only the all-time snapshot (`period == nil`) is computed right now. The
  year-specific code paths (`year_snapshot_threshold/0`, `list_years/1`,
  per-year cron refresh, year dropdown fields) are preserved in
  comments throughout the codebase and can be re-enabled when year pages
  come back. See `Kaguya.Stats.RefreshScheduler` and
  `Kaguya.Stats.Worker` for the companion disabled paths.

  All-time counts every `:read` VN regardless of whether the user set a
  `date_finished`.
  """

  alias Kaguya.Stats.{Compute, UserPeriodStat, Hero}
  alias Kaguya.Reviews.Review
  alias Kaguya.Lists.List
  alias Kaguya.Repo
  import Ecto.Query

  @doc """
  Compute a full stats snapshot for a user and upsert it to the database.
  Used by both the background worker and manual refresh callers.
  """
  def compute_and_upsert_snapshot(user_id, period \\ nil) do
    attrs = Compute.full_snapshot(user_id, period)

    %UserPeriodStat{}
    |> UserPeriodStat.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:user_id, :period]
    )
  end

  # YEAR-STATS DISABLED — preserved for revival.
  #
  # @year_snapshot_threshold 10
  #
  # @doc """
  # Minimum number of finished VNs (status == :read with a date_finished)
  # required for a year to get its own snapshot row and appear in the year
  # dropdown on the stats page.
  # """
  # def year_snapshot_threshold, do: @year_snapshot_threshold
  #
  # def list_years(user_id) do
  #   from(s in UserPeriodStat,
  #     where: s.user_id == ^user_id and not is_nil(s.period),
  #     order_by: [asc: s.period],
  #     select: s.period
  #   )
  #   |> Repo.all()
  # end

  def format_histogram(%{} = hist_map) do
    hist_map
    |> Enum.map(fn {bucket_str, cnt} ->
      period =
        case Integer.parse(bucket_str) do
          {year, ""} -> Integer.to_string(year)
          _ -> bucket_str
        end

      %{period: period, count: cnt}
    end)
  end

  def histogram_resolver(field) do
    fn %{^field => hist}, _args, _res ->
      {:ok, format_histogram(hist || %{})}
    end
  end

  def format_float_histogram(%{} = hist_map) do
    hist_map
    |> Enum.map(fn {bucket_str, value} ->
      period =
        case Integer.parse(bucket_str) do
          {year, ""} -> Integer.to_string(year)
          _ -> bucket_str
        end

      %{period: period, value: value}
    end)
  end

  def float_histogram_resolver(field) do
    fn %{^field => hist}, _args, _res ->
      {:ok, format_float_histogram(hist || %{})}
    end
  end

  def build_user_vn_stats(%{id: uid} = user, period \\ nil, opts \\ []) do
    snapshot = get_snapshot(uid, period)

    %{
      user_id: uid,
      period: period,
      hero_stats: Hero.fetch(user, period, snapshot),
      read_time_minutes: snap(snapshot, :read_time_minutes, 0),
      producers_count: snap(snapshot, :producers_count, 0),
      vns_hist: snap(snapshot, :vns_hist, %{}),
      read_time_hist: snap(snapshot, :read_time_hist, %{}),
      mean_score_hist: snap(snapshot, :mean_score_hist, %{}),
      vns_by_release_year_hist: snap(snapshot, :vns_by_release_year_hist, %{}),
      read_time_by_release_year_hist: snap(snapshot, :read_time_by_release_year_hist, %{}),
      mean_score_by_release_year_hist: snap(snapshot, :mean_score_by_release_year_hist, %{}),
      most_read_vn_tags: snap(snapshot, :most_read_vn_tags, []),
      highest_rated_vn_tags: snap(snapshot, :highest_rated_vn_tags, []),
      most_read_producers: snap(snapshot, :most_read_producers, []),
      highest_rated_producers: snap(snapshot, :highest_rated_producers, []),
      most_read_languages: Compute.most_read_languages(uid, period),
      most_liked_vn_review: get_most_liked_vn_review(uid),
      most_liked_vn_list: get_most_liked_vn_list(uid, opts),
      updated_at: snapshot && snapshot.updated_at
    }
  end

  defp snap(nil, _key, default), do: default
  defp snap(snapshot, key, default), do: Map.get(snapshot, key) || default

  @doc """
  Fetch the latest VN stats snapshot.
  """
  def get_snapshot(user_id, nil) do
    Repo.one(
      from s in UserPeriodStat,
        where: s.user_id == ^user_id and is_nil(s.period)
    )
  end

  def get_snapshot(user_id, period) when is_integer(period) do
    Repo.get_by(UserPeriodStat, user_id: user_id, period: period)
  end

  def get_most_liked_vn_review(user_id) do
    Review
    |> where([r], r.user_id == ^user_id and r.likes_count > 0)
    |> order_by(desc: :likes_count)
    |> limit(1)
    |> Repo.one()
  end

  def get_most_liked_vn_list(user_id, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    query =
      List
      |> where([l], l.user_id == ^user_id and l.is_public == true and l.likes_count > 0)
      |> order_by(desc: :likes_count)
      |> limit(1)

    query =
      case allowed do
        nil ->
          query

        cats ->
          allowed_strings = Enum.map(cats, &to_string/1)

          where(
            query,
            [l],
            fragment(
              "EXISTS (SELECT 1 FROM list_items li JOIN visual_novels vn ON vn.id = li.visual_novel_id WHERE li.list_id = ? AND vn.title_category = ANY(?))",
              l.id,
              ^allowed_strings
            )
          )
      end

    Repo.one(query)
  end
end
