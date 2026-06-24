defmodule Kaguya.FriendsTest do
  use ExUnit.Case, async: false

  alias Kaguya.{Friends, Repo, Reviews, Shelves, Social}
  alias Kaguya.Reviews.Ratings
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "list_friend_reviews/3 returns reviews with users preloaded" do
    viewer = UserFixtures.insert_user!()
    friend = UserFixtures.insert_user!()
    vn = insert_vn!()

    assert {:ok, true} = Social.follow_user(viewer.id, friend.id)

    assert {:ok, expected_review} =
             Reviews.create_review(friend.id, vn.id, %{
               content: "This friend review is long enough to satisfy the review validation."
             })

    assert {:ok, %{items: [review]}} = Friends.list_friend_reviews(viewer.id, vn.id, limit: 5)

    assert review.id == expected_review.id
    assert Ecto.assoc_loaded?(review.user)
    assert review.user.id == friend.id
  end

  test "list_friend_activity/3 returns activity with joined user, rating, and review flag" do
    viewer = UserFixtures.insert_user!()
    friend = UserFixtures.insert_user!()
    vn = insert_vn!()

    assert {:ok, true} = Social.follow_user(viewer.id, friend.id)
    assert {:ok, _status} = Shelves.set_reading_status(friend.id, vn.id, %{status: :read})
    assert {:ok, _rating} = Ratings.create_rating(friend.id, vn.id, 4.5)

    assert {:ok, _review} =
             Reviews.create_review(friend.id, vn.id, %{
               content: "This friend activity review is long enough to satisfy validation."
             })

    assert {:ok, %{items: [item], status_counts: status_counts, total_count: 1}} =
             Friends.list_friend_activity(viewer.id, vn.id, 10)

    assert item.user.id == friend.id
    assert item.rating == 4.5
    assert item.has_review
    assert status_counts["READ"] == 1
    assert status_counts["CURRENTLY_READING"] == 0
  end

  defp insert_vn! do
    suffix = System.unique_integer([:positive])

    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "Friend Reviews Test VN #{suffix}",
      slug: "friend-reviews-test-vn-#{suffix}",
      description: "A" <> String.duplicate(" friend reviews visual novel description", 3)
    })
    |> Repo.insert!()
  end
end
