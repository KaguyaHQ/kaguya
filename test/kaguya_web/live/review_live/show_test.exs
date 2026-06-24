defmodule KaguyaWeb.ReviewLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Ratings
  alias Kaguya.Reviews.Review
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "render" do
    test "renders a review for anonymous viewers" do
      owner = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
      vn = insert_vn!("Test VN")
      {:ok, _review} = Reviews.create_review(owner.id, vn.id, %{content: long_content("First!")})

      {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/reviews/#{vn.slug}")

      assert html =~ "Review by"
      assert html =~ "Alice"
      assert html =~ vn.title
      assert html =~ "application/ld+json"
      assert html =~ ~s(id="review-menu-dropdown-trigger")
      assert html =~ ~s(popovertarget="review-menu-dropdown-panel")
      # Comments section renders for everyone.
      assert html =~ "Comments"
    end

    test "emits route metadata and Google-valid Review JSON-LD once" do
      owner = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
      vn = insert_vn!("Structured Data VN")
      {:ok, _rating} = Ratings.create_rating(owner.id, vn.id, 4.5)
      {:ok, _review} = Reviews.create_review(owner.id, vn.id, %{content: long_content("schema")})

      {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/reviews/#{vn.slug}")

      assert html_attr(html, ~s(link[rel="canonical"]), "href") ==
               ["https://kaguya.io/@alice/reviews/#{vn.slug}"]

      assert [description] = html_attr(html, ~s(meta[name="description"]), "content")
      assert description =~ "schema filler"

      review_json_ld =
        html
        |> json_ld_payloads()
        |> Enum.filter(&(&1["@type"] == "Review"))

      assert [review_schema] = review_json_ld
      assert review_schema["itemReviewed"]["@type"] == "VideoGame"
      assert review_schema["itemReviewed"]["@id"] == "https://kaguya.io/vn/#{vn.slug}"
      assert review_schema["itemReviewed"]["name"] == vn.title
      assert review_schema["reviewRating"]["ratingValue"] == 9.0
    end

    test "renders not-found when the review doesn't exist" do
      owner = UserFixtures.insert_user!(username: "alice")
      vn = insert_vn!("Solo VN")

      {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/reviews/#{vn.slug}")

      assert html =~ "https://images.kaguya.io/ui/404.webp"
      assert html =~ "Return home"
    end

    test "hides moderator-hidden reviews from anonymous viewers" do
      author = UserFixtures.insert_user!()
      vn = insert_vn!("Hidden Review VN")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("hi")})
      {:ok, _} = Reviews.hide_review(review.id)

      {:ok, _view, html} = live(build_conn(), "/@#{author.username}/reviews/#{vn.slug}")

      assert html =~ "https://images.kaguya.io/ui/404.webp"
      assert html =~ "Return home"
    end

    test "shows moderator-hidden reviews to the author with a hidden banner" do
      author = UserFixtures.insert_user!()
      vn = insert_vn!("Hidden Author VN")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("hi")})
      {:ok, _} = Reviews.hide_review(review.id)

      {:ok, _view, html} = live(conn_for(author), "/@#{author.username}/reviews/#{vn.slug}")

      assert html =~ "Hidden by moderators"
      # Edit/delete affordances reachable.
      assert html =~ "open_edit"
    end
  end

  describe "viewer-aware actions" do
    test "liking a review toggles likes_count" do
      author = UserFixtures.insert_user!()
      viewer = UserFixtures.insert_user!()
      vn = insert_vn!("Likeable VN")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("ok")})

      {:ok, view, _html} = live(conn_for(viewer), "/@#{author.username}/reviews/#{vn.slug}")

      view |> element(~s|button[phx-click="toggle_like"]|) |> render_click()
      assert Repo.get!(Review, review.id).likes_count == 1

      view |> element(~s|button[phx-click="toggle_like"]|) |> render_click()
      assert Repo.get!(Review, review.id).likes_count == 0
    end

    test "anonymous like falls back to flash" do
      author = UserFixtures.insert_user!()
      vn = insert_vn!("Anon Like VN")
      {:ok, _review} = Reviews.create_review(author.id, vn.id, %{content: long_content("ok")})

      {:ok, view, _html} = live(build_conn(), "/@#{author.username}/reviews/#{vn.slug}")

      assert view
             |> element(~s|button[phx-click="toggle_like"]|)
             |> render_click() =~ "Sign in to like reviews."
    end
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
  end

  defp long_content(seed),
    do: seed <> String.duplicate(" filler for the 40-char min length", 5)

  defp html_attr(html, selector, attr) do
    html
    |> Floki.parse_document!()
    |> Floki.attribute(selector, attr)
  end

  defp json_ld_payloads(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(script[type="application/ld+json"]))
    |> Enum.map(&script_content/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end

  defp script_content({"script", _attrs, children}) do
    children
    |> Enum.map_join(fn
      child when is_binary(child) -> child
      child -> Floki.raw_html(child)
    end)
    |> String.trim()
  end
end
