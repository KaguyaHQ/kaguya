defmodule Kaguya.SiteStats.Snapshot do
  @moduledoc """
  One row per UTC day. Holds 9 site-wide counters.

  The daily Oban worker writes a row keyed on today's UTC date; the read path
  for the `/site-stats` page is just a 30-row range query against this table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:date, :date, []}

  @counters ~w(
    ratings_count
    reading_statuses_count
    reviews_count
    users_count
    dau_count
    mau_30d_count
    vns_count
    characters_count
    producers_count
    releases_count
  )a

  schema "site_stat_snapshots" do
    field :ratings_count, :integer, default: 0
    field :reading_statuses_count, :integer, default: 0
    field :reviews_count, :integer, default: 0

    field :users_count, :integer, default: 0

    # Distinct users with any `user_activities` row on this UTC day.
    field :dau_count, :integer, default: 0

    # Distinct users with any `user_activities` row in the trailing 30
    # UTC days ending on (and including) this row's date.
    field :mau_30d_count, :integer, default: 0

    field :vns_count, :integer, default: 0
    field :characters_count, :integer, default: 0
    field :producers_count, :integer, default: 0
    field :releases_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:date | @counters])
    |> validate_required([:date | @counters])
  end
end
