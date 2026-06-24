defmodule KaguyaWeb.ProfileLive.StatsDataTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Stats
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.ProfileLive.StatsData

  describe "load_stats/3" do
    test "builds an empty render model for a user without stats" do
      user = UserFixtures.insert_user!()
      profile = profile_for(user)

      stats = StatsData.load_stats(user, profile, nil)

      refute stats.has_content?
      assert stats.hero.vns_count == 0
      assert stats.release_year_chart.titles == []
      assert stats.read_year_chart.titles == []
      assert stats.length_items == []
      assert stats.language_items == []
      assert stats.age_items == []
    end

    test "builds charts and distribution items from existing reading stats" do
      user = UserFixtures.insert_user!()

      vn =
        insert_vn!("Stats Data VN",
          release_date: ~D[2024-01-01],
          length_minutes: 180,
          original_language: "en",
          min_age: 18
        )

      insert_status!(user, vn, ~D[2025-02-03])
      insert_rating!(user, vn, 4.0)
      {:ok, _snapshot} = Stats.compute_and_upsert_snapshot(user.id)

      stats = StatsData.load_stats(user, profile_for(user), nil)

      assert stats.has_content?
      assert stats.hero.vns_count == 1
      assert [%{period: "2024", value: 1}] = stats.release_year_chart.titles
      assert [%{period: "2025", value: 1}] = stats.read_year_chart.titles
      assert [%{label: "English", value: 1}] = stats.language_items
      assert Enum.any?(stats.length_items, &(&1.key == "short" and &1.value == 1))
      assert Enum.any?(stats.age_items, &(&1.key == "18+" and &1.value == 1))
    end
  end

  defp profile_for(user) do
    {:ok, user} = Users.get_user(user.id)

    %{
      id: user.id,
      avatar_urls: Users.build_avatar_urls(user.avatar_id),
      ratings_count: user.vn_ratings_count || 0
    }
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
end
