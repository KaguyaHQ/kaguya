defmodule Kaguya.Stats.Compute do
  @moduledoc """
  Aggregates and computes user VN reading stats for a given period (year or all-time).
  """

  import Ecto.Query
  alias Kaguya.Producers
  alias Kaguya.Producers.VNProducer
  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.{VisualNovel, VNTag}

  def vn_hero_counts(user_id, period) do
    %{
      read_time_minutes: total_read_time(user_id, period),
      producers_count: unique_producers_read(user_id, period)
    }
  end

  defp total_read_time(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
    |> select([_rs, vn], coalesce(sum(vn.length_minutes), 0))
    |> Repo.one()
  end

  defp unique_producers_read(user_id, period) do
    user_id
    |> primary_producers_for_finished_vns(period)
    |> Enum.uniq_by(& &1.producer_id)
    |> length()
  end

  # Returns a flat list of vn_producer rows representing the *primary* producers
  # of every VN the user has finished in `period`. "Primary" means the same
  # developer-first selection used by the VN page resolver and the search index
  # — see `Kaguya.Producers.select_primary/1`.
  #
  # Single query: joins reading_statuses to vn_producers directly, no SQL
  # GROUP BY (the per-VN selection happens in Elixir). Same shape as the
  # resolver's batch loader.
  defp primary_producers_for_finished_vns(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], vp in VNProducer, on: vp.visual_novel_id == rs.visual_novel_id)
    |> select([_rs, vp], %{
      visual_novel_id: vp.visual_novel_id,
      producer_id: vp.producer_id,
      role: vp.role,
      earliest_release_date: vp.earliest_release_date
    })
    |> Repo.all()
    |> Enum.group_by(& &1.visual_novel_id)
    |> Enum.flat_map(fn {_vn_id, rows} -> Producers.select_primary(rows) end)
  end

  # Query helper: VNs the user has finished (status == :read), optionally
  # filtered to a calendar year by date_finished.
  #
  # Important: "finished" means status == :read, NOT "has a date_finished".
  # Many users have VNs marked as read with no date_finished set (legacy
  # imports, manual marks without picking a date). Filtering on date_finished
  # alone would silently drop those rows from every aggregate.
  #
  # The year-period branch DOES filter on date_finished — without a date you
  # can't know which year a VN belongs to.
  defp finished_vns_query(user_id, nil) do
    ReadingStatus
    |> where([rs], rs.user_id == ^user_id and rs.status == :read)
  end

  defp finished_vns_query(user_id, year) when is_integer(year) do
    {start_date, end_date} = year_range(year)

    ReadingStatus
    |> where(
      [rs],
      rs.user_id == ^user_id and rs.status == :read and
        rs.date_finished >= ^start_date and rs.date_finished < ^end_date
    )
  end

  # Subset of finished VNs that have a date_finished — required for the
  # histogram queries since they bucket by year/month.
  defp dated_finished_vns_query(user_id) do
    ReadingStatus
    |> where(
      [rs],
      rs.user_id == ^user_id and rs.status == :read and not is_nil(rs.date_finished)
    )
  end

  defp year_range(year) do
    {Date.new!(year, 1, 1), Date.new!(year + 1, 1, 1)}
  end

  # Converts [{year_int, avg_value}, ...] into a string-keyed float map.
  # avg() may return a Decimal or float depending on the column type;
  # Decimal.to_float/1 handles both via the protocol.
  defp into_float_hist(rows) do
    Enum.into(rows, %{}, fn {year_int, avg_val} ->
      val =
        if is_struct(avg_val, Decimal),
          do: Decimal.to_float(avg_val),
          else: avg_val / 1

      {Integer.to_string(year_int), Float.round(val, 2)}
    end)
  end

  @doc """
  Count of finished VNs bucketed by period.
  • period nil → yearly buckets  ("2023", "2024")
  • period 2024 → monthly buckets ("2024-01", "2024-02")
  """
  def vns_hist(user_id, nil) do
    dated_finished_vns_query(user_id)
    |> group_by([rs], fragment("EXTRACT(year FROM ?)::int", rs.date_finished))
    |> select([rs], {fragment("EXTRACT(year FROM ?)::int", rs.date_finished), count(rs.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {year_int, cnt} -> {Integer.to_string(year_int), cnt} end)
  end

  def vns_hist(user_id, year) when is_integer(year) do
    {start_date, end_date} = year_range(year)

    dated_finished_vns_query(user_id)
    |> where([rs], rs.date_finished >= ^start_date and rs.date_finished < ^end_date)
    |> group_by([rs], fragment("to_char(?, 'YYYY-MM')", rs.date_finished))
    |> select([rs], {fragment("to_char(?, 'YYYY-MM')", rs.date_finished), count(rs.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {yyyy_mm, cnt} -> {yyyy_mm, cnt} end)
  end

  @doc """
  Total read time (VN length minutes), bucketed by period.
  """
  def read_time_hist(user_id, nil) do
    dated_finished_vns_query(user_id)
    |> join(:inner, [rs], vn in assoc(rs, :visual_novel))
    |> group_by([rs], fragment("EXTRACT(year FROM ?)::int", rs.date_finished))
    |> select(
      [rs, vn],
      {fragment("EXTRACT(year FROM ?)::int", rs.date_finished),
       coalesce(sum(vn.length_minutes), 0)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {year_int, minutes} -> {Integer.to_string(year_int), minutes} end)
  end

  def read_time_hist(user_id, year) when is_integer(year) do
    {start_date, end_date} = year_range(year)

    dated_finished_vns_query(user_id)
    |> where([rs], rs.date_finished >= ^start_date and rs.date_finished < ^end_date)
    |> join(:inner, [rs], vn in assoc(rs, :visual_novel))
    |> group_by([rs], fragment("to_char(?, 'YYYY-MM')", rs.date_finished))
    |> select(
      [rs, vn],
      {fragment("to_char(?, 'YYYY-MM')", rs.date_finished), coalesce(sum(vn.length_minutes), 0)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {yyyy_mm, minutes} -> {yyyy_mm, minutes} end)
  end

  @top_languages_limit 10
  @top_tags_limit 10
  @top_producers_limit 25

  @doc "Top original languages by read count for a user in a given period"
  def most_read_languages(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
    |> where([_rs, vn], not is_nil(vn.original_language))
    |> group_by([_rs, vn], vn.original_language)
    |> order_by([_rs, vn], desc: count(vn.id))
    |> limit(^@top_languages_limit)
    |> select([_rs, vn], %{language: vn.original_language, count: count(vn.id)})
    |> Repo.all()
  end

  @doc "Top VN tags by read count for a user in a given period"
  def most_read_vn_tags(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], vt in VNTag, on: vt.visual_novel_id == rs.visual_novel_id)
    |> join(:inner, [rs, vt], t in Tag, on: t.id == vt.tag_id)
    |> group_by([_rs, _vt, t], t.id)
    |> order_by([_rs, _vt, t], desc: count(t.id))
    |> limit(^@top_tags_limit)
    |> select([_rs, _vt, t], %{tag_id: t.id, count: count(t.id)})
    |> Repo.all()
  end

  @doc "Top VN tags by *user's own* average rating in a given period"
  def highest_rated_vn_tags(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], r in Rating,
      on: r.user_id == ^user_id and r.visual_novel_id == rs.visual_novel_id
    )
    |> join(:inner, [_rs, r], vt in VNTag, on: vt.visual_novel_id == r.visual_novel_id)
    |> join(:inner, [_rs, r, vt], t in Tag, on: t.id == vt.tag_id)
    |> group_by([_rs, r, _vt, t], t.id)
    |> having([_rs, r, _vt, t], count(r.visual_novel_id) >= ^3)
    |> order_by([_rs, r, _vt, t], desc: avg(r.rating))
    |> limit(^@top_tags_limit)
    |> select([_rs, r, _vt, t], %{tag_id: t.id, avg_user_rating: avg(r.rating)})
    |> Repo.all()
  end

  @doc """
  Top producers by read count for a user in a given period. Counts only the
  primary developers per VN (see `primary_producers_for_finished_vns/2`),
  not every producer in the join — so the list reflects what the user
  actually sees on each VN's page rather than every localizer/distributor.
  """
  def most_read_producers(user_id, period) do
    user_id
    |> primary_producers_for_finished_vns(period)
    |> Enum.frequencies_by(& &1.producer_id)
    |> Enum.sort_by(fn {_producer_id, count} -> -count end)
    |> Enum.take(@top_producers_limit)
    |> Enum.map(fn {producer_id, count} ->
      %{producer_id: producer_id, count: count}
    end)
  end

  @doc """
  Top producers by the user's own average rating in a given period. Same
  primary-producer rule as `most_read_producers/2` — only credits the
  developers shown on each VN's page, not every producer in the join.
  """
  def highest_rated_producers(user_id, period) do
    finished_vns_query(user_id, period)
    |> join(:inner, [rs], r in Rating,
      on: r.user_id == ^user_id and r.visual_novel_id == rs.visual_novel_id
    )
    |> join(:inner, [rs, _r], vp in VNProducer, on: vp.visual_novel_id == rs.visual_novel_id)
    |> select([_rs, r, vp], %{
      visual_novel_id: vp.visual_novel_id,
      producer_id: vp.producer_id,
      role: vp.role,
      earliest_release_date: vp.earliest_release_date,
      rating: r.rating
    })
    |> Repo.all()
    |> Enum.group_by(& &1.visual_novel_id)
    |> Enum.flat_map(fn {_vn_id, rows} ->
      # All rows for the same VN carry the same rating (one rating per user/VN).
      # `select_primary/1` ignores the extra :rating field on the row maps.
      rows
      |> Producers.select_primary()
      |> Enum.map(fn row -> {row.producer_id, row.rating} end)
    end)
    |> Enum.group_by(fn {pid, _} -> pid end, fn {_, rating} -> rating end)
    |> Enum.map(fn {producer_id, ratings} ->
      %{producer_id: producer_id, avg_user_rating: Enum.sum(ratings) / length(ratings)}
    end)
    |> Enum.sort_by(& &1.avg_user_rating, :desc)
    |> Enum.take(@top_producers_limit)
  end

  @doc """
  Mean score (average user rating) bucketed by date_finished year.
  Only includes years where the user has at least one rated VN.
  """
  def mean_score_hist(user_id, nil) do
    dated_finished_vns_query(user_id)
    |> join(:inner, [rs], r in Rating,
      on: r.user_id == ^user_id and r.visual_novel_id == rs.visual_novel_id
    )
    |> group_by([rs, _r], fragment("EXTRACT(year FROM ?)::int", rs.date_finished))
    |> select(
      [rs, r],
      {fragment("EXTRACT(year FROM ?)::int", rs.date_finished), avg(r.rating)}
    )
    |> Repo.all()
    |> into_float_hist()
  end

  # Year-period clause not yet implemented — return empty to avoid crash.
  def mean_score_hist(_user_id, _period), do: %{}

  @doc """
  Count of finished VNs bucketed by VN release year.
  """
  def vns_by_release_year_hist(user_id, nil) do
    finished_vns_query(user_id, nil)
    |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
    |> where([_rs, vn], not is_nil(vn.release_date))
    |> group_by([_rs, vn], fragment("EXTRACT(year FROM ?)::int", vn.release_date))
    |> select([_rs, vn], {fragment("EXTRACT(year FROM ?)::int", vn.release_date), count(vn.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {year_int, cnt} -> {Integer.to_string(year_int), cnt} end)
  end

  def vns_by_release_year_hist(_user_id, _period), do: %{}

  @doc """
  Total read time (VN length minutes) bucketed by VN release year.
  """
  def read_time_by_release_year_hist(user_id, nil) do
    finished_vns_query(user_id, nil)
    |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
    |> where([_rs, vn], not is_nil(vn.release_date))
    |> group_by([_rs, vn], fragment("EXTRACT(year FROM ?)::int", vn.release_date))
    |> select(
      [_rs, vn],
      {fragment("EXTRACT(year FROM ?)::int", vn.release_date),
       coalesce(sum(vn.length_minutes), 0)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {year_int, minutes} -> {Integer.to_string(year_int), minutes} end)
  end

  def read_time_by_release_year_hist(_user_id, _period), do: %{}

  @doc """
  Mean score (average user rating) bucketed by VN release year.
  """
  def mean_score_by_release_year_hist(user_id, nil) do
    finished_vns_query(user_id, nil)
    |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
    |> join(:inner, [rs, _vn], r in Rating,
      on: r.user_id == ^user_id and r.visual_novel_id == rs.visual_novel_id
    )
    |> where([_rs, vn, _r], not is_nil(vn.release_date))
    |> group_by([_rs, vn, _r], fragment("EXTRACT(year FROM ?)::int", vn.release_date))
    |> select(
      [_rs, vn, r],
      {fragment("EXTRACT(year FROM ?)::int", vn.release_date), avg(r.rating)}
    )
    |> Repo.all()
    |> into_float_hist()
  end

  def mean_score_by_release_year_hist(_user_id, _period), do: %{}

  @doc "Full snapshot builder for all tracked VN stats"
  def full_snapshot(user_id, period) do
    %{read_time_minutes: read_time, producers_count: producers_cnt} =
      vn_hero_counts(user_id, period)

    %{
      user_id: user_id,
      period: period,
      read_time_minutes: read_time,
      producers_count: producers_cnt,
      most_read_vn_tags: most_read_vn_tags(user_id, period),
      highest_rated_vn_tags: highest_rated_vn_tags(user_id, period),
      most_read_producers: most_read_producers(user_id, period),
      highest_rated_producers: highest_rated_producers(user_id, period),
      vns_hist: vns_hist(user_id, period),
      read_time_hist: read_time_hist(user_id, period),
      mean_score_hist: mean_score_hist(user_id, period),
      vns_by_release_year_hist: vns_by_release_year_hist(user_id, period),
      read_time_by_release_year_hist: read_time_by_release_year_hist(user_id, period),
      mean_score_by_release_year_hist: mean_score_by_release_year_hist(user_id, period)
    }
  end
end
