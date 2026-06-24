defmodule Kaguya.Stats.Hero do
  @moduledoc """
  The five "hero" numbers shown at the top of a user's VN stats page.

  • `period = nil`   → all-time
  • `period = 2025`  → that calendar year

  Two of the five (`read_time_minutes`, `producers_count`) are read directly
  from the snapshot row, which is computed in the background by
  `Kaguya.Stats.Worker`. The caller is expected to fetch the snapshot once
  and pass it in — we no longer re-fetch it here.

  `vns_count`, `reviews_count`, and `lists_count` are computed live —
  they're cheap indexed COUNTs and the alternative would be storing yet more
  denormalized scalars on `UserPeriodStat`.

  `vns_count` deliberately counts every `status == :read` row, NOT just rows
  with a `date_finished` set. Many users have read VNs without a finish date
  (legacy imports, manual marks); filtering on `date_finished` would silently
  drop them and produce a number that disagrees with the library's "Read" tab.
  The year-period branch DOES require `date_finished`, since by definition you
  can't bucket a date-less row into a calendar year.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Reviews.Review
  alias Kaguya.Lists.List
  alias Kaguya.Shelves.ReadingStatus

  defstruct ~w[
    vns_count reviews_count lists_count read_time_minutes producers_count
  ]a

  @doc """
  Build the hero stats for `user` over `period`, using a pre-fetched snapshot
  (or an empty map if the user has no snapshot row yet — typically a brand-new
  user before the first scheduled refresh).
  """
  def fetch(%{id: uid, vn_reviews_count: rc}, period, snapshot) do
    %__MODULE__{
      vns_count: count_finished_vns(uid, period),
      reviews_count: get_vn_reviews_count(uid, rc, period),
      lists_count: count_vn_lists(uid, period),
      read_time_minutes: snapshot_field(snapshot, :read_time_minutes, 0),
      producers_count: snapshot_field(snapshot, :producers_count, 0)
    }
  end

  defp snapshot_field(nil, _key, default), do: default
  defp snapshot_field(snapshot, key, default), do: Map.get(snapshot, key, default)

  defp count_finished_vns(uid, nil) do
    ReadingStatus
    |> where([rs], rs.user_id == ^uid and rs.status == :read)
    |> Repo.aggregate(:count, :id)
  end

  defp count_finished_vns(uid, year) when is_integer(year) do
    {start_date, end_date} = year_range_date(year)

    ReadingStatus
    |> where(
      [rs],
      rs.user_id == ^uid and rs.status == :read and
        rs.date_finished >= ^start_date and rs.date_finished < ^end_date
    )
    |> Repo.aggregate(:count, :id)
  end

  defp year_range_date(year) do
    {Date.new!(year, 1, 1), Date.new!(year + 1, 1, 1)}
  end

  defp count_vn_lists(uid, nil) do
    from(l in List, where: l.user_id == ^uid and l.is_public == true)
    |> Repo.aggregate(:count, :id)
  end

  defp count_vn_lists(uid, year) when is_integer(year) do
    {start_date, end_date} = year_range(year)

    from(l in List,
      where:
        l.user_id == ^uid and l.is_public == true and
          l.inserted_at >= ^start_date and l.inserted_at < ^end_date
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_vn_reviews_count(_uid, rc, nil), do: rc

  defp get_vn_reviews_count(uid, _rc, year) when is_integer(year) do
    {start_date, end_date} = year_range(year)

    from(r in Review,
      where:
        r.user_id == ^uid and
          r.inserted_at >= ^start_date and r.inserted_at < ^end_date
    )
    |> Repo.aggregate(:count, :id)
  end

  defp year_range(year) do
    {
      DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC"),
      DateTime.new!(Date.new!(year + 1, 1, 1), ~T[00:00:00], "Etc/UTC")
    }
  end
end
