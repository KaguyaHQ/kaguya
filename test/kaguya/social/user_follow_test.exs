defmodule Kaguya.Social.UserFollowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Social
  alias Kaguya.Social.{Notification, UserFollow}
  alias Kaguya.Test.UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "following is idempotent and rejects self-follows and missing users" do
    follower = UserFixtures.insert_user!()
    followed = UserFixtures.insert_user!()

    assert {:error, "A user cannot follow themselves"} =
             Social.follow_user(follower.id, follower.id)

    assert {:error, :not_found} = Social.follow_user(follower.id, Ecto.UUID.generate())
    assert {:ok, true} = Social.follow_user(follower.id, followed.id)
    assert {:ok, true} = Social.follow_user(follower.id, followed.id)
    assert Repo.aggregate(UserFollow, :count) == 1
    assert Repo.aggregate(Notification, :count) == 1
  end
end
