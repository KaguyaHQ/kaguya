defmodule Kaguya.SiteStats.Compute do
  @moduledoc """
  Aggregations for the daily site-stats snapshot.

  Counters apply a temporal cutoff so the same code powers both:

    * the daily worker (`snapshot_for(yesterday)`), which records the
      previous day's end-of-day totals
    * the one-off backfill (`mix kaguya.backfill_site_stats`), which
      reconstructs prior days from `inserted_at`

  For tables with a `hidden_at` column we also filter
  `hidden_at IS NULL OR hidden_at > cutoff` — an approximation, since we
  don't track unhide events, but accurate enough for trend lines.

  DAU is sourced from `user_activities` — distinct `user_id` values whose
  `inserted_at` falls on the snapshot's UTC day. "Active" = "took at
  least one rating / list / review / comment / like / follow / etc.
  action," matching the engagement actions enumerated in
  `Kaguya.Activities.UserActivity`.

  Rolling 30-day MAU uses the same activity signal over the trailing 30
  UTC days ending on (and including) the snapshot date.

  Failures bubble up so Oban retries (or the Mix task) cover them.
  """

  import Ecto.Query

  alias Kaguya.Activities.UserActivity
  alias Kaguya.Characters.Character
  alias Kaguya.Producers.Producer
  alias Kaguya.Releases.Release
  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @doc """
  Build a daily snapshot map for the given UTC date.

  The cutoff is end-of-day UTC. Pass yesterday (or earlier) so the day
  is complete; passing today would freeze a partial-day count.
  """
  def snapshot_for(%Date{} = date) do
    cutoff = end_of_day_utc(date)

    %{
      date: date,
      ratings_count: ratings_count_at(cutoff),
      reading_statuses_count: reading_statuses_count_at(cutoff),
      reviews_count: reviews_count_at(cutoff),
      users_count: users_count_at(cutoff),
      dau_count: dau_count_at(date),
      mau_30d_count: mau_30d_count_at(date),
      vns_count: vns_count_at(cutoff),
      characters_count: characters_count_at(cutoff),
      producers_count: producers_count_at(cutoff),
      releases_count: releases_count_at(cutoff)
    }
  end

  defp end_of_day_utc(date) do
    DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")
  end

  defp ratings_count_at(cutoff) do
    Rating
    |> where([r], r.inserted_at <= ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp reading_statuses_count_at(cutoff) do
    ReadingStatus
    |> where([rs], rs.inserted_at <= ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp reviews_count_at(cutoff) do
    Review
    |> where([r], r.inserted_at <= ^cutoff)
    |> where([r], is_nil(r.hidden_at) or r.hidden_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp users_count_at(cutoff) do
    User
    |> where([u], u.inserted_at <= ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  # Distinct users with any user_activities row on this single UTC day.
  defp dau_count_at(%Date{} = date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    next_day_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    from(a in UserActivity,
      where: a.inserted_at >= ^start_dt and a.inserted_at < ^next_day_dt,
      select: count(a.user_id, :distinct)
    )
    |> Repo.one()
  end

  # Distinct users with any user_activities row in the trailing 30 UTC
  # days ending on (and including) `date`. The window is [date-29, date].
  defp mau_30d_count_at(%Date{} = date) do
    start_dt = DateTime.new!(Date.add(date, -29), ~T[00:00:00], "Etc/UTC")
    next_day_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    from(a in UserActivity,
      where: a.inserted_at >= ^start_dt and a.inserted_at < ^next_day_dt,
      select: count(a.user_id, :distinct)
    )
    |> Repo.one()
  end

  defp vns_count_at(cutoff) do
    VisualNovel
    |> where([v], v.inserted_at <= ^cutoff)
    |> where([v], is_nil(v.hidden_at) or v.hidden_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp characters_count_at(cutoff) do
    Character
    |> where([c], c.inserted_at <= ^cutoff)
    |> where([c], is_nil(c.hidden_at) or c.hidden_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp producers_count_at(cutoff) do
    Producer
    |> where([p], p.inserted_at <= ^cutoff)
    |> where([p], is_nil(p.hidden_at) or p.hidden_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end

  defp releases_count_at(cutoff) do
    Release
    |> where([r], r.inserted_at <= ^cutoff)
    |> where([r], is_nil(r.hidden_at) or r.hidden_at > ^cutoff)
    |> Repo.aggregate(:count, :id)
  end
end
