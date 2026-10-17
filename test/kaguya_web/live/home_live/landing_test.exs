defmodule KaguyaWeb.HomeLive.LandingTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Discussions
  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Review
  alias Kaguya.Social
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders the signed-out landing page" do
    {:ok, _view, html} = live(build_conn(), "/")

    assert html =~ "The social tracker for VN readers."
    assert html =~ ~s(href="/signup")
    assert html =~ "Get started"
    assert html =~ "https://images.kaguya.io/ui/backdrop_cha_more.webp"
    assert html =~ "Full Metal Daemon Muramasa"
    assert html =~ "Log in"
    assert html =~ "Sign up"
    refute html =~ "HomeActivityFeed"
    refute html =~ "Welcome back"
  end

  test "renders the landing story with a window under each chapter" do
    {:ok, view, _html} = live(build_conn(), "/")

    assert has_element?(view, ~s(#landing-story[phx-hook="LandingStory"][phx-update="ignore"]))

    for chapter <- ~w(lists profile stats import) do
      assert has_element?(view, ~s([data-chapter="#{chapter}"] [data-panel="#{chapter}"]))
    end

    assert has_element?(view, ~s([data-chapter="lists"] h2), "Rank them. Defend the ranking.")
    assert has_element?(view, ~s([data-panel="lists"] a[href="/@eightpunch/list/2026-goals"]))
    assert has_element?(view, ~s([data-panel="profile"] a[href="/@vas"]), "Vas")
    assert has_element?(view, ~s([data-panel="stats"] [data-chart][data-hours]))

    # The traveling cover has a slot in every window except import.
    for slot <- ~w(lists profile stats) do
      assert has_element?(
               view,
               ~s([data-panel="#{slot}"] [data-slot="#{slot}"][href="/vn/the-house-in-fata-morgana"])
             )
    end

    refute has_element?(view, ~s([data-panel="import"] [data-slot]))
    assert has_element?(view, "#landing-wall-title", "Your next favorite is in here somewhere.")
    assert has_element?(view, ~s(.landing-wall-copy a[href="/signup"]), "Get started")
  end

  test "renders the signed-in home feed" do
    viewer = UserFixtures.insert_user!(username: "viewer", display_name: "Viewer")

    author =
      UserFixtures.insert_user!(username: "home_author", display_name: "Home Author")

    vn = insert_vn!("Home Feed VN")

    {:ok, _review} =
      Reviews.create_review(author.id, vn.id, %{
        content: "This home feed review has enough words to pass validation."
      })

    {:ok, list} =
      Lists.create_list(%{
        user_id: author.id,
        name: "Home Feed List",
        description: "A list on the signed-in homepage",
        vn_ids: [vn.id]
      })

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Home Feed Discussion",
        content: "Talking about the homepage feed.",
        category_type: :general
      })

    {:ok, _view, html} = live(conn_for(viewer), "/")

    assert html =~ "Viewer"
    assert html =~ "Feed"
    assert html =~ "Activity"
    assert html =~ "Home Author"
    assert html =~ vn.title
    assert html =~ "Home Feed List"
    assert html =~ "/@#{author.username}/list/#{list.slug}"
    assert html =~ "Home Feed Discussion"
    assert html =~ "/discussions/p/#{post.short_id}/#{post.slug}"
    refute html =~ "The social tracker for VN readers."
  end

  test "wires signed-in greeting for client-side local-time replacement" do
    viewer = UserFixtures.insert_user!(username: "greeting_test", display_name: "Dunk")

    {:ok, _view, html} = live(conn_for(viewer), "/")

    assert html =~ ~s(id="home-greeting")
    assert html =~ ~s(phx-hook="HomeGreeting")
    assert html =~ ~s(data-display-name="Dunk")
    assert html =~ "data-home-greeting-text"
  end

  test "Friends/Global filter only renders on the desktop sidebar when the viewer follows somebody" do
    # Philosophy: a control that can only show an empty state doesn't
    # earn its place. The filter appears once the viewer has at least
    # one follow, and never on mobile (where it's a power-user knob in
    # the wrong context).
    viewer = UserFixtures.insert_user!(username: "no_follows")
    {:ok, _view, html} = live(conn_for(viewer), "/")
    refute html =~ ~s(aria-label="Activity scope")

    followee = UserFixtures.insert_user!(username: "followee_for_filter")
    {:ok, _} = Social.follow_user(viewer.id, followee.id)

    {:ok, _view, html} = live(conn_for(viewer), "/")
    # Filter now present. Only rendered inside the desktop sidebar
    # wrapper (`lg:block` aside) — mobile never sees it.
    assert html =~ ~s(aria-label="Activity scope")
    assert html =~ "Friends"
    assert html =~ "Global"
  end

  test "signed-in users can like feed reviews" do
    viewer = UserFixtures.insert_user!(username: "feed_liker")
    author = UserFixtures.insert_user!(username: "feed_review_author")
    vn = insert_vn!("Like From Home VN")

    {:ok, review} =
      Reviews.create_review(author.id, vn.id, %{
        content: "This home feed review has enough text for a like test."
      })

    {:ok, view, _html} = live(conn_for(viewer), "/")

    view
    |> element(
      ~s|button[phx-click="toggle_feed_review_like"][phx-value-review-id="#{review.id}"]|
    )
    |> render_click()

    assert Repo.get!(Review, review.id).likes_count == 1
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end
