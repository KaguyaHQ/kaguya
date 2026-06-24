defmodule KaguyaWeb.ProfileLive.ReviewsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Review
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/reviews" do
    test "renders the empty state when the user has no reviews" do
      _user = UserFixtures.insert_user!(username: "empty_reviewer", display_name: "Empty")

      {:ok, _view, html} = live(build_conn(), "/@empty_reviewer/reviews")

      assert html =~ "No reviews yet."
      refute html =~ "&apos;s reviews"
    end

    test "renders a paginated list of reviews with VN cover + title" do
      author = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
      vn = insert_vn!("Steins;Gate")

      {:ok, _review} =
        Reviews.create_review(author.id, vn.id, %{content: long_content("amazing")})

      {:ok, _view, html} = live(build_conn(), "/@alice/reviews")

      # Header line uses display name + apostrophe ("Alice's reviews")
      assert html =~ "Alice"
      assert html =~ "reviews"
      assert html =~ vn.title
      assert html =~ ~s(href="/vn/#{vn.slug}")
      assert html =~ ~s(href="/@alice/reviews/#{vn.slug}")
      # Sort dropdown defaults to Popular.
      assert html =~ "Popular"
      # No pagination chrome for a single page.
      refute html =~ ">Next<"
    end

    test "advances pagination via the URL" do
      author = UserFixtures.insert_user!(username: "prolific")

      # 13 reviews → 2 pages at pageSize=12.
      for n <- 1..13 do
        vn = insert_vn!("VN #{n}")

        {:ok, _} =
          Reviews.create_review(author.id, vn.id, %{content: long_content("review ##{n}")})
      end

      {:ok, view, html} = live(build_conn(), "/@prolific/reviews")
      # Page 1 of 2: Previous is disabled, Next is a patch link to page=2.
      assert html =~ "/@prolific/reviews?page=2"

      # Navigate to page 2 via the next-page patch link.
      html_page2 = render_patch(view, "/@prolific/reviews?page=2")
      # On page 2: Previous is a patch link back to page 1.
      assert html_page2 =~ ~s(href="/@prolific/reviews")
      assert html_page2 =~ "Previous"
    end

    test "sort=NEWEST changes the order of reviews" do
      author = UserFixtures.insert_user!(username: "sortable")
      vn_old = insert_vn!("Older VN")

      {:ok, older} =
        Reviews.create_review(author.id, vn_old.id, %{content: long_content("older")})

      # Backdate the first review by a day so :newest ordering is deterministic.
      one_day_ago =
        DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)

      Repo.update_all(
        from(r in Review, where: r.id == ^older.id),
        set: [inserted_at: one_day_ago]
      )

      vn_new = insert_vn!("Newer VN")

      {:ok, _newer} =
        Reviews.create_review(author.id, vn_new.id, %{content: long_content("newer")})

      {:ok, _view, newest_html} = live(build_conn(), "/@sortable/reviews?sort=NEWEST")

      # Newer VN's title appears before the older VN's title in the rendered HTML.
      idx_newer = :binary.match(newest_html, "Newer VN")
      idx_older = :binary.match(newest_html, "Older VN")
      assert is_tuple(idx_newer) and is_tuple(idx_older)
      {newer_pos, _} = idx_newer
      {older_pos, _} = idx_older
      assert newer_pos < older_pos
    end

    test "spoiler reviews render a reveal affordance instead of exposed body first" do
      author =
        UserFixtures.insert_user!(
          username: "spoiler_author",
          display_name: "Spoiler Author"
        )

      vn = insert_vn!("Spoiler VN")

      {:ok, _review} =
        Reviews.create_review(author.id, vn.id, %{
          content: long_content("secret body"),
          is_spoiler: true
        })

      {:ok, _view, html} = live(build_conn(), "/@spoiler_author/reviews")

      assert html =~ "This review may contain spoilers."
      assert html =~ "Show review"
      assert html =~ "Contains spoilers"
    end
  end

  describe "like toggle" do
    test "anonymous viewers get a sign-in flash and no DB change" do
      author = UserFixtures.insert_user!(username: "alice")
      vn = insert_vn!("Tsukihime")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("ok")})

      {:ok, view, _html} = live(build_conn(), "/@alice/reviews")

      flash =
        view
        |> element(~s(button[phx-click="toggle_review_like"]))
        |> render_click()

      assert flash =~ "Sign in"
      assert Repo.get!(Review, review.id).likes_count == 0
    end

    test "logged-in viewer flips likes_count and the heart state optimistically" do
      author = UserFixtures.insert_user!(username: "alice")
      viewer = UserFixtures.insert_user!()
      vn = insert_vn!("Fate/Stay Night")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("solid")})

      conn = build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => viewer.id})
      {:ok, view, html} = live(conn, "/@alice/reviews")

      # Start state: not liked, count=0.
      assert html =~ ~s(aria-pressed="false")
      refute html =~ ~s(aria-label="Unlike")

      after_like =
        view
        |> element(~s(button[phx-click="toggle_review_like"]))
        |> render_click()

      assert after_like =~ ~s(aria-pressed="true")
      assert after_like =~ ~s(aria-label="Unlike")
      assert Repo.get!(Review, review.id).likes_count == 1

      after_unlike =
        view
        |> element(~s(button[phx-click="toggle_review_like"]))
        |> render_click()

      assert after_unlike =~ ~s(aria-pressed="false")
      assert Repo.get!(Review, review.id).likes_count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp long_content(seed),
    do: seed <> String.duplicate(" filler for the 40-char min length", 5)
end
