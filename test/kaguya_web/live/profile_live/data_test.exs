defmodule KaguyaWeb.ProfileLive.DataTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Social
  alias Kaguya.Test.UserFixtures
  alias KaguyaWeb.ProfileLive.Data

  describe "load_header/2" do
    test "returns a normalized view-model for an existing user" do
      user =
        UserFixtures.insert_user!(
          username: "alice",
          display_name: "Alice",
          bio: "hello"
        )

      assert {:ok, header} = Data.load_header("alice", nil)

      assert header.id == user.id
      assert header.username == "alice"
      assert header.display_name == "Alice"
      assert header.bio == "hello"
      assert header.counts.followers == 0
      assert header.counts.following == 0
      assert header.viewer.is_mine == false
      assert header.viewer.is_logged_in == false
      assert header.viewer.follow_state == :not_following
    end

    test "returns :not_found for an unknown username" do
      assert {:error, :not_found} = Data.load_header("nobody_here", nil)
    end

    test "is_mine reflects the viewer matching the profile owner" do
      user = UserFixtures.insert_user!(username: "bob")

      viewer = Map.from_struct(user) |> Map.drop([:__meta__])
      assert {:ok, header} = Data.load_header("bob", viewer)
      assert header.viewer.is_mine == true
      assert header.viewer.follow_state == :self
    end

    test "follow_state and is_followed_by_me reflect the social graph" do
      target = UserFixtures.insert_user!(username: "target")
      viewer_user = UserFixtures.insert_user!(username: "viewer")
      {:ok, _} = Social.follow_user(viewer_user.id, target.id)

      viewer = Map.from_struct(viewer_user) |> Map.drop([:__meta__])
      assert {:ok, header} = Data.load_header("target", viewer)
      assert header.viewer.follow_state == :following
      assert header.viewer.is_followed_by_me == true
      assert header.counts.followers == 1
    end
  end

  describe "viewer_permissions/1" do
    test "returns no permissions for anonymous viewers" do
      assert Data.viewer_permissions(nil) == %{any?: false}
    end

    test "admins get every flag" do
      perms = Data.viewer_permissions(%{role: :admin})
      assert perms.is_admin
      assert perms.can_moderate_db
      assert perms.can_moderate_lists
      assert perms.can_manage_users
      assert perms.any?
    end

    test "granular mod flags surface independently" do
      perms = Data.viewer_permissions(%{role: :user, mod_lists: true})
      refute perms.is_admin
      assert perms.can_moderate_lists
      refute perms.can_moderate_db
      assert perms.any?
    end
  end

  describe "parse_username/1" do
    test "strips a leading @" do
      assert Data.parse_username("@alice") == "alice"
    end

    test "returns the username unchanged when no @ is present" do
      assert Data.parse_username("alice") == "alice"
    end
  end
end
