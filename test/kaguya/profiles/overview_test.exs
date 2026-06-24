defmodule Kaguya.Profiles.OverviewTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Profiles.Overview
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "profile_overview/2" do
    test "returns an empty view-model for a brand-new user" do
      user = UserFixtures.insert_user!()

      overview = Overview.profile_overview(user, nil)

      assert overview.favorite_visual_novels == []
      assert overview.favorite_characters == []
      assert overview.vn_finished == []
      assert overview.vn_currently_reading == []
      assert overview.vn_want_to_read == []
      assert overview.want_to_read_count == 0
      assert overview.shelves == []
      assert overview.popular_lists == []
      assert overview.popular_reviews == []
      assert overview.recent_reviews == []
      assert overview.following_preview == []
      assert overview.recent_activity == []
      assert overview.ratings.count == 0
      assert overview.ratings.average == 0.0
      assert overview.ratings.dist == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "pulls favorite VNs from the user.favorite_visual_novels array" do
      vn1 = insert_vn!("a")
      vn2 = insert_vn!("b")

      user =
        UserFixtures.insert_user!()
        |> set_favorite_vns([vn1.id, vn2.id])

      overview = Overview.profile_overview(user, nil)

      assert length(overview.favorite_visual_novels) == 2
      assert Enum.map(overview.favorite_visual_novels, & &1.id) == [vn1.id, vn2.id]
      assert Enum.all?(overview.favorite_visual_novels, &Map.has_key?(&1, :images))
    end

    test "limits favorite VNs to 4" do
      vns = for i <- 1..6, do: insert_vn!("fav#{i}")
      user = UserFixtures.insert_user!() |> set_favorite_vns(Enum.map(vns, & &1.id))

      overview = Overview.profile_overview(user, nil)
      assert length(overview.favorite_visual_novels) == 4
    end

    test "loads reading-status slices and counts the wishlist separately" do
      user = UserFixtures.insert_user!()
      vn_read = insert_vn!("r")
      vn_reading = insert_vn!("c")
      vn_wish1 = insert_vn!("w1")
      vn_wish2 = insert_vn!("w2")

      insert_status!(user.id, vn_read.id, :read)
      insert_status!(user.id, vn_reading.id, :currently_reading)
      insert_status!(user.id, vn_wish1.id, :want_to_read)
      insert_status!(user.id, vn_wish2.id, :want_to_read)

      overview = Overview.profile_overview(user, nil)

      assert Enum.map(overview.vn_finished, & &1.id) == [vn_read.id]
      assert Enum.map(overview.vn_currently_reading, & &1.id) == [vn_reading.id]
      assert length(overview.vn_want_to_read) == 2
      assert overview.want_to_read_count == 2
    end

    test "ratings block reflects the user's denormalized rating counters" do
      user = UserFixtures.insert_user!()
      dist = [1, 0, 0, 0, 0, 0, 5, 0, 0, 3]

      Repo.update_all(
        from(u in Kaguya.Users.User, where: u.id == ^user.id),
        set: [vn_ratings_count: 9, vn_average_rating: 4.1, vn_ratings_dist: dist]
      )

      user = Kaguya.Repo.get!(Kaguya.Users.User, user.id)
      overview = Overview.profile_overview(user, nil)

      assert overview.ratings.count == 9
      assert overview.ratings.dist == dist
    end
  end

  # ----- helpers ------------------------------------------------------------

  defp insert_vn!(title) do
    Repo.insert!(%VisualNovel{
      id: Ecto.UUID.generate(),
      title: title,
      slug: "vn-" <> title,
      title_category: :vn,
      ratings_count: 0,
      reviews_count: 0
    })
  end

  defp set_favorite_vns(user, ids) do
    Repo.update_all(
      from(u in Kaguya.Users.User, where: u.id == ^user.id),
      set: [favorite_visual_novels: ids]
    )

    Kaguya.Repo.get!(Kaguya.Users.User, user.id)
  end

  defp insert_status!(user_id, vn_id, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Kaguya.Shelves.ReadingStatus{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      visual_novel_id: vn_id,
      status: status,
      library_added_at: now,
      inserted_at: now,
      updated_at: now
    })
  end
end
