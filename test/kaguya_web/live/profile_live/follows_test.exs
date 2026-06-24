defmodule KaguyaWeb.ProfileLive.FollowsTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Shelves
  alias Kaguya.Social
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/followers" do
    test "renders the followers page with tabs, counts, and read VN covers" do
      profile_user = UserFixtures.insert_user!(username: "vas", display_name: "Vas")

      follower =
        UserFixtures.insert_user!(username: "reader_one", display_name: "Reader One")

      first_vn = insert_vn!("Steins;Gate Follow Preview")
      second_vn = insert_vn!("Umineko Follow Preview")

      assert {:ok, true} = Social.follow_user(follower.id, profile_user.id)
      assert {:ok, _} = Shelves.set_reading_status(follower.id, first_vn.id, %{status: :read})
      assert {:ok, _} = Shelves.set_reading_status(follower.id, second_vn.id, %{status: :read})

      {:ok, _view, html} = live(build_conn(), "/@vas/followers")

      assert html =~ "Followers"
      assert html =~ "Following"
      assert html =~ ~s(href="/@vas/followers")
      assert html =~ ~s(href="/@vas/following")
      assert html =~ "Reader One"
      assert html =~ ~s(href="/@reader_one")
      assert html =~ "2"
      assert html =~ "VNs"
      assert html =~ "Reviews"
      assert html =~ "Steins;Gate Follow Preview"
      assert html =~ "Umineko Follow Preview"
      assert html =~ ~s(href="/vn/#{first_vn.slug}")
      assert html =~ ~s(href="/vn/#{second_vn.slug}")
      refute html =~ "coming soon"
    end

    test "renders the empty state" do
      _profile_user = UserFixtures.insert_user!(username: "no_followers")

      {:ok, _view, html} = live(build_conn(), "/@no_followers/followers")

      assert html =~ "No followers found"
      refute html =~ "coming soon"
    end
  end

  describe "GET /@:username/following" do
    test "renders users the profile owner follows" do
      profile_user =
        UserFixtures.insert_user!(username: "vas_following", display_name: "Vas")

      followed =
        UserFixtures.insert_user!(
          username: "followed_user",
          display_name: "Followed User"
        )

      assert {:ok, true} = Social.follow_user(profile_user.id, followed.id)

      {:ok, _view, html} = live(build_conn(), "/@vas_following/following?tw=1")

      assert html =~ "Followed User"
      assert html =~ ~s(href="/@followed_user")
      assert html =~ ~s(href="/@vas_following/followers?tw=1")
      assert html =~ ~s(href="/@vas_following/following?tw=1")
      refute html =~ "Not following anyone"
      refute html =~ "coming soon"
    end
  end

  defp insert_vn!(title) do
    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: title,
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end
end
