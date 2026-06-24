defmodule Kaguya.SiteStats do
  @moduledoc """
  Public API for the global `/site-stats` page.

  Daily counters — including DAU and rolling-30-day MAU — live in
  `site_stat_snapshots` (one row per UTC day, written by
  `Kaguya.SiteStats.Worker`). The page is Cloudflare-cached for 24h with
  an active purge after each daily worker run.
  """

  import Ecto.Query

  alias Kaguya.Cdn
  alias Kaguya.Repo
  alias Kaguya.SiteStats.Snapshot

  @history_days 30

  @doc """
  Returns the last `days` complete daily snapshots, oldest → newest.
  Latest row is yesterday's UTC snapshot; today is excluded because the
  worker only writes a row once a day is complete.
  """
  def history(days \\ @history_days) when is_integer(days) and days > 0 do
    yesterday = Date.add(Date.utc_today(), -1)
    cutoff = Date.add(yesterday, -(days - 1))

    from(s in Snapshot,
      where: s.date >= ^cutoff and s.date <= ^yesterday,
      order_by: [asc: s.date]
    )
    |> Repo.all()
  end

  @doc """
  Purge the `/site-stats` page from Cloudflare's edge cache. Called by
  the worker after a successful snapshot write and by the backfill task
  after completing its loop.
  """
  def purge_cache, do: Cdn.purge_site_stats()
end
