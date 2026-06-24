defmodule Kaguya.Social.ProducerFollowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Social
  alias Kaguya.Social.ProducerFollow
  alias Kaguya.Producers.Producer
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Test.UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)

    user = UserFixtures.insert_user!()

    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    {:ok, producer} =
      %Producer{}
      |> Producer.changeset(%{name: "P_#{suffix}"})
      |> Repo.insert()

    %{user: user, producer: producer}
  end

  describe "follow_producer/2" do
    test "creates a follow row and increments the counter", %{user: u, producer: p} do
      assert {:ok, %{follower_count: 1, was_new: true}} = Social.follow_producer(u.id, p.id)

      assert Social.follows_producer?(u.id, p.id)
      assert Repo.get!(Producer, p.id).follower_count == 1
      assert Repo.aggregate(ProducerFollow, :count) == 1
    end

    test "is idempotent — repeated calls leave a single row and counter at 1", %{
      user: u,
      producer: p
    } do
      assert {:ok, %{was_new: true, follower_count: 1}} = Social.follow_producer(u.id, p.id)
      assert {:ok, %{was_new: false, follower_count: 1}} = Social.follow_producer(u.id, p.id)
      assert {:ok, %{was_new: false, follower_count: 1}} = Social.follow_producer(u.id, p.id)

      assert Repo.get!(Producer, p.id).follower_count == 1
      assert Repo.aggregate(ProducerFollow, :count) == 1
    end

    test "returns :not_found for an unknown producer", %{user: u} do
      missing = Ecto.UUID.generate()
      assert {:error, :not_found} = Social.follow_producer(u.id, missing)
    end

    test "two users following the same producer increment to 2", %{user: u, producer: p} do
      u2 = UserFixtures.insert_user!()

      assert {:ok, %{follower_count: 1}} = Social.follow_producer(u.id, p.id)
      assert {:ok, %{follower_count: 2}} = Social.follow_producer(u2.id, p.id)

      assert Repo.get!(Producer, p.id).follower_count == 2
    end
  end

  describe "unfollow_producer/2" do
    test "removes the row and decrements the counter", %{user: u, producer: p} do
      {:ok, _} = Social.follow_producer(u.id, p.id)

      assert {:ok, %{follower_count: 0, was_removed: true}} = Social.unfollow_producer(u.id, p.id)

      refute Social.follows_producer?(u.id, p.id)
      assert Repo.get!(Producer, p.id).follower_count == 0
    end

    test "is a no-op when not following — counter stays put", %{user: u, producer: p} do
      assert {:ok, %{follower_count: 0, was_removed: false}} =
               Social.unfollow_producer(u.id, p.id)

      assert Repo.get!(Producer, p.id).follower_count == 0
    end

    test "repeated unfollow stays idempotent", %{user: u, producer: p} do
      {:ok, _} = Social.follow_producer(u.id, p.id)

      assert {:ok, %{was_removed: true}} = Social.unfollow_producer(u.id, p.id)
      assert {:ok, %{was_removed: false}} = Social.unfollow_producer(u.id, p.id)

      assert Repo.get!(Producer, p.id).follower_count == 0
    end
  end

  describe "activity feed integration" do
    import Ecto.Query

    test "records a :followed activity with entity_type producer on follow", %{
      user: u,
      producer: p
    } do
      {:ok, _} = Social.follow_producer(u.id, p.id)

      activity =
        Repo.one(
          from a in UserActivity,
            where: a.user_id == ^u.id and a.action == :followed and a.entity_type == "producer"
        )

      assert activity
      assert activity.entity_id == p.id
      assert activity.metadata["followed_producer_name"] == p.name
      assert activity.metadata["followed_producer_slug"] == p.slug
    end

    test "deletes the activity on unfollow", %{user: u, producer: p} do
      {:ok, _} = Social.follow_producer(u.id, p.id)
      assert producer_follow_activity_count(u.id, p.id) == 1

      {:ok, _} = Social.unfollow_producer(u.id, p.id)
      assert producer_follow_activity_count(u.id, p.id) == 0
    end

    test "no activity row for an idempotent re-follow", %{user: u, producer: p} do
      {:ok, _} = Social.follow_producer(u.id, p.id)
      {:ok, _} = Social.follow_producer(u.id, p.id)
      {:ok, _} = Social.follow_producer(u.id, p.id)

      assert producer_follow_activity_count(u.id, p.id) == 1
    end
  end

  defp producer_follow_activity_count(user_id, producer_id) do
    import Ecto.Query

    Repo.aggregate(
      from(a in UserActivity,
        where:
          a.user_id == ^user_id and a.action == :followed and a.entity_type == "producer" and
            a.entity_id == ^producer_id
      ),
      :count
    )
  end

  describe "batch_followed_producer_ids/2" do
    test "returns the subset of producer ids the user follows", %{user: u, producer: p1} do
      {:ok, p2} = %Producer{} |> Producer.changeset(%{name: "P2"}) |> Repo.insert()
      {:ok, p3} = %Producer{} |> Producer.changeset(%{name: "P3"}) |> Repo.insert()

      {:ok, _} = Social.follow_producer(u.id, p1.id)
      {:ok, _} = Social.follow_producer(u.id, p3.id)

      result = Social.batch_followed_producer_ids(u.id, [p1.id, p2.id, p3.id])

      assert MapSet.equal?(result, MapSet.new([p1.id, p3.id]))
    end

    test "returns empty set for nil follower (anonymous viewer)", %{producer: p} do
      assert Social.batch_followed_producer_ids(nil, [p.id]) == MapSet.new()
    end
  end
end
