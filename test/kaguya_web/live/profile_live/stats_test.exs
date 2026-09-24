defmodule KaguyaWeb.ProfileLive.StatsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Stats
  alias Kaguya.Stats.UserPeriodStat
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/stats" do
    test "renders the first stats dashboard slice from existing stats data", %{conn: conn} do
      user =
        UserFixtures.insert_user!(username: "stats_reader", display_name: "Stats Reader")

      vn_2024 =
        insert_vn!("Release Year VN",
          release_date: ~D[2024-01-01],
          length_minutes: 180,
          original_language: "en",
          min_age: 12
        )

      vn_2025 =
        insert_vn!("Read Year VN",
          release_date: ~D[2025-01-01],
          length_minutes: 900,
          original_language: "ja",
          min_age: 18
        )

      insert_status!(user, vn_2024, ~D[2024-02-03])
      insert_status!(user, vn_2025, ~D[2025-04-05])
      insert_rating!(user, vn_2024, 4.0)
      insert_rating!(user, vn_2025, 5.0)

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [
          vn_ratings_count: 2,
          vn_ratings_dist: [0, 0, 0, 0, 0, 0, 0, 1, 0, 1],
          vn_average_rating: 4.5
        ]
      )

      {:ok, _snapshot} = Stats.compute_and_upsert_snapshot(user.id)

      {:ok, _view, html} = live(conn, "/@stats_reader/stats")

      assert html =~ "A Life in VNs"
      assert html =~ "Stats Reader"
      assert html =~ "Release Year"
      assert html =~ "Read Year"
      assert html =~ "Ratings"
      assert html =~ "Length"
      assert html =~ "Languages"
      assert html =~ "The H factor"
      assert html =~ "2"
      refute html =~ "coming soon"
    end

    test "renders all-time hero numbers in the stored digit order", %{conn: conn} do
      user =
        UserFixtures.insert_user!(username: "stats_digits", display_name: "Stats Digits")

      for index <- 1..11 do
        vn =
          insert_vn!("Digit Regression VN #{index}",
            release_date: ~D[2026-01-01],
            length_minutes: 60,
            original_language: "en",
            min_age: 12
          )

        insert_status!(user, vn, ~D[2026-01-01])
      end

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [vn_reviews_count: 3]
      )

      insert_snapshot!(user, read_time_minutes: 19_133, producers_count: 10)

      {:ok, _view, html} = live(conn, "/@stats_digits/stats")
      text = page_text(html)

      assert text =~ "11 VNs"
      assert text =~ "3 Reviews"
      assert text =~ "319 Hours"
      assert text =~ "10 Developers"
      refute text =~ "913 Hours"
      refute text =~ "01 Developers"
    end
  end

  test "H factor buckets and library links agree, including missing release data", %{conn: conn} do
    user = UserFixtures.insert_user!()
    mixed = insert_vn!("Mixed editions", has_ero: false, min_age: 0)
    without = insert_vn!("No H-scenes", has_ero: false, min_age: 18)
    unknown = insert_vn!("Missing releases", has_ero: false)
    positive = insert_vn!("Confirmed VN flag", has_ero: true)
    hidden = insert_vn!("Only hidden releases", has_ero: false)
    vns = [mixed, without, unknown, positive, hidden]
    Enum.each(vns, &insert_status!(user, &1, ~D[2026-01-01]))

    for {vn, ero, hidden_at} <- [
          {mixed, true, nil},
          {mixed, false, nil},
          {without, false, nil},
          {hidden, false, ~U[2026-01-01 00:00:00Z]}
        ] do
      Repo.insert!(%Kaguya.Releases.Release{
        visual_novel_id: vn.id,
        title: vn.title,
        has_ero: ero,
        hidden_at: hidden_at
      })
    end

    assert Kaguya.Library.library_h_content_dist(user.id, %{status: :read}) == %{
             "with" => 2,
             "without" => 1,
             "unknown" => 2
           }

    for {bucket, expected, label} <- [
          {"with", [mixed, positive], "With H"},
          {"without", [without], "No H"},
          {"unknown", [unknown, hidden], "Unknown"}
        ] do
      {:ok, stats_view, _} = live(conn, "/@#{user.username}/stats")
      path = "/@#{user.username}/library/read?hContent=#{bucket}"
      assert has_element?(stats_view, "h2", "The H factor")
      result = stats_view |> element("li a[href='#{path}']", label) |> render_click()
      {:ok, library_view, _} = follow_redirect(result, conn, path)

      for vn <- vns do
        assert has_element?(library_view, "#library-item-#{vn.id}") == vn in expected
      end

      library_view
      |> element("button[phx-click=remove_filter][phx-value-key=hContent]")
      |> render_click()

      assert_patch(library_view, "/@#{user.username}/library/read")
      Enum.each(vns, &assert(has_element?(library_view, "#library-item-#{&1.id}")))
    end
  end

  defp insert_vn!(title, attrs) do
    attrs =
      Map.merge(
        %{
          title: title,
          slug: "#{Slug.slugify(title)}-#{System.unique_integer([:positive])}"
        },
        Map.new(attrs)
      )

    Repo.insert!(struct(VisualNovel, attrs))
  end

  defp insert_status!(user, vn, date_finished) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ReadingStatus{
      user_id: user.id,
      visual_novel_id: vn.id,
      status: :read,
      library_added_at: now,
      date_finished: date_finished,
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_rating!(user, vn, rating) do
    %Rating{}
    |> Rating.changeset(%{user_id: user.id, visual_novel_id: vn.id, rating: rating})
    |> Repo.insert!()
  end

  defp insert_snapshot!(user, attrs) do
    attrs =
      %{
        user_id: user.id,
        period: nil,
        read_time_minutes: 0,
        producers_count: 0,
        vns_hist: %{"2026" => 11},
        read_time_hist: %{"2026" => 19_133}
      }
      |> Map.merge(Map.new(attrs))

    %UserPeriodStat{}
    |> UserPeriodStat.changeset(attrs)
    |> Repo.insert!()
  end

  defp page_text(html) do
    html
    |> Floki.parse_document!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
  end
end
