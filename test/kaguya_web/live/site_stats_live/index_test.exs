defmodule KaguyaWeb.SiteStatsLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.SiteStats.Snapshot
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User

  test "renders public site stats charts" do
    insert_snapshots!()

    {:ok, _view, html} = live(build_conn(), "/site-stats")

    assert html =~ "Users"
    assert html =~ "Reviews"
    assert html =~ "Ratings"
    assert html =~ "Logged"
    assert html =~ "Users trend over the last 3 days"
    refute html =~ "Monthly Active Users"
    refute html =~ "Daily Active Users"
  end

  test "renders admin-only active user charts for admins" do
    insert_snapshots!()
    user = insert_admin!()

    {:ok, _view, html} = live(conn_for(user), "/site-stats")

    assert html =~ "Monthly Active Users"
    assert html =~ "Daily Active Users"
    assert html =~ "of 4,000 goal"
  end

  test "renders empty state when no snapshots are available" do
    {:ok, _view, html} = live(build_conn(), "/site-stats")

    assert html =~ "Site stats are not available yet"
  end

  defp insert_snapshots! do
    start = Date.utc_today() |> Date.add(-3)

    for index <- 0..2 do
      date = Date.add(start, index)

      %Snapshot{}
      |> Snapshot.changeset(%{
        date: date,
        ratings_count: 1_000 + index * 100,
        reading_statuses_count: 2_000 + index * 120,
        reviews_count: 100 + index * 10,
        users_count: 50 + index * 5,
        dau_count: 10 + index,
        mau_30d_count: 20 + index * 2,
        vns_count: 500,
        characters_count: 600,
        producers_count: 70,
        releases_count: 800
      })
      |> Repo.insert!()
    end
  end

  defp insert_admin! do
    user = UserFixtures.insert_user!()
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role: :admin])
    Repo.get!(User, user.id)
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end
end
