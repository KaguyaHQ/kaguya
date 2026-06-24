defmodule KaguyaWeb.MembersLive.IndexTest do
  use KaguyaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kaguya.Repo
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Social.UserFollow
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders members with favorite covers and counts" do
    [vn1, vn2] = insert_vns!("Member Cover")
    user = insert_member!("alice", "Alice Reader", [vn1, vn2])
    insert_library_status!(user, vn1)
    insert_review!(user, vn1)

    {:ok, _view, html} = live(build_conn(), "/members")

    assert html =~ "Members"
    assert html =~ "Alice Reader"
    assert html =~ "1 VN"
    assert html =~ "1 review"
    assert html =~ "Member Cover 1"
    assert html =~ "Member Cover 2"
  end

  test "searches members by username" do
    [vn1, vn2] = insert_vns!("Search Cover")
    insert_member!("alpha", "Alpha Reader", [vn1, vn2])
    insert_member!("betty", "Betty Reader", [vn1, vn2])

    {:ok, _view, html} = live(build_conn(), "/members?q=bet")

    assert html =~ "1 result"
    assert html =~ "bet"
    assert html =~ "Betty Reader"
    refute html =~ "Alpha Reader"
  end

  test "supports cursor pagination" do
    [vn1, vn2] = insert_vns!("Paged Cover")

    for index <- 1..21 do
      insert_member!("paged_#{index}", "Paged Member #{index}", [vn1, vn2])
    end

    {:ok, view, html} = live(build_conn(), "/members?sort=newest")

    assert html =~ "Load More"

    html =
      view
      |> element("button", "Load More")
      |> render_click()

    assert html =~ "Paged Member"
    refute html =~ "Load More"
  end

  test "signed-in viewers can follow and unfollow a member" do
    [vn1, vn2] = insert_vns!("Follow Cover")
    viewer = UserFixtures.insert_user!(username: "viewer")
    target = insert_member!("follow_target", "Follow Target", [vn1, vn2])

    {:ok, view, html} = live(conn_for(viewer), "/members?q=follow_target")

    assert html =~ ~s(aria-label="Follow Follow Target")

    html =
      view
      |> element(~s(button[aria-label="Follow Follow Target"]))
      |> render_click()

    assert html =~ ~s(aria-label="Unfollow Follow Target")

    html =
      view
      |> element(~s(button[aria-label="Unfollow Follow Target"]))
      |> render_click()

    assert html =~ ~s(aria-label="Follow Follow Target")

    refute Repo.get_by(UserFollow, follower_id: viewer.id, followed_id: target.id)
  end

  defp insert_member!(username, display_name, favorite_vns) do
    UserFixtures.insert_user!(
      username: username,
      display_name: display_name,
      favorite_visual_novels: Enum.map(favorite_vns, & &1.id)
    )
  end

  defp insert_vns!(prefix) do
    for index <- 1..2 do
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "#{prefix} #{index}",
        temp_image_url: "https://images.example.test/#{prefix}-#{index}.webp"
      })
      |> Repo.insert!()
    end
  end

  defp insert_library_status!(user, vn) do
    %ReadingStatus{}
    |> ReadingStatus.changeset(%{
      user_id: user.id,
      visual_novel_id: vn.id,
      status: :read,
      library_added_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp insert_review!(user, vn) do
    %Review{}
    |> Review.changeset(%{
      user_id: user.id,
      visual_novel_id: vn.id,
      content: "This review has enough words to satisfy the minimum length."
    })
    |> Repo.insert!()
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end
end
