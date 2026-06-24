defmodule KaguyaWeb.ProfileLive.LibraryTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Shelves.{ReadingStatus, Shelf, ShelfItem}
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  defp insert_vn!(title) do
    Repo.insert!(%VisualNovel{
      title: title,
      slug: "#{Slug.slugify(title)}-#{System.unique_integer([:positive])}"
    })
  end

  defp insert_status!(user, vn, status, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ReadingStatus{
      user_id: user.id,
      visual_novel_id: vn.id,
      status: status,
      library_added_at: Map.get(attrs, :added_at, now),
      date_started: attrs[:date_started],
      date_finished: attrs[:date_finished]
    })
  end

  describe "GET /@:username/library" do
    test "renders the toolbar and the user's VNs", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "reader", display_name: "Reader")
      vn1 = insert_vn!("Steins;Gate")
      vn2 = insert_vn!("Clannad")
      insert_status!(user, vn1, :read)
      insert_status!(user, vn2, :currently_reading)

      {:ok, _view, html} = live(conn, "/@reader/library")

      # Header + library nav
      assert html =~ "Reader"
      assert html =~ ~s(data-tab="library")
      # Shelf tabs render with counts
      assert html =~ ~s(data-shelf="ALL")
      assert html =~ ~s(data-shelf="READ")
      assert html =~ ~s(phx-value-value="READ" value="READ")
      assert html =~ ~s(data-shelf="CURRENTLY_READING")
      # Both VNs appear in the grid
      assert html =~ "Steins;Gate"
      assert html =~ "Clannad"
    end

    test "marks the library noindex,follow so filter/page variants aren't indexed",
         %{conn: conn} do
      UserFixtures.insert_user!(username: "reader2")

      {:ok, _view, html} = live(conn, "/@reader2/library")

      assert html =~ ~s(<meta name="robots" content="noindex,follow")
    end

    test "filters by shelf path segment", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "shelfer")
      vn_read = insert_vn!("Saya no Uta")
      vn_wishlist = insert_vn!("Higurashi")
      insert_status!(user, vn_read, :read)
      insert_status!(user, vn_wishlist, :want_to_read)

      {:ok, _view, html} = live(conn, "/@shelfer/library/read")

      assert html =~ "Saya no Uta"
      refute html =~ "Higurashi"
    end

    test "filters by status when a non-default shelf is selected", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "wisher")
      vn_w = insert_vn!("Umineko")
      vn_r = insert_vn!("Fate")
      insert_status!(user, vn_w, :want_to_read)
      insert_status!(user, vn_r, :read)

      {:ok, _view, html} = live(conn, "/@wisher/library/wishlist")

      assert html =~ "Umineko"
      refute html =~ "Fate"
    end

    test "search filter narrows results via push_patch", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "searcher")
      _v1 = insert_status!(user, insert_vn!("Tsukihime"), :read)
      _v2 = insert_status!(user, insert_vn!("Muv-Luv"), :read)

      {:ok, _view, html} = live(conn, "/@searcher/library?q=tsuki")

      assert html =~ "Tsukihime"
      refute html =~ "Muv-Luv"
    end

    test "rating filter restricts to a specific rating", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "rater")
      vn_high = insert_vn!("High Rated")
      vn_low = insert_vn!("Low Rated")
      insert_status!(user, vn_high, :read)
      insert_status!(user, vn_low, :read)

      Repo.insert!(%Rating{user_id: user.id, visual_novel_id: vn_high.id, rating: 5.0})
      Repo.insert!(%Rating{user_id: user.id, visual_novel_id: vn_low.id, rating: 2.0})

      {:ok, _view, html} = live(conn, "/@rater/library?rating=5")

      assert html =~ "High Rated"
      refute html =~ "Low Rated"
    end

    test "renders custom shelf when slug matches a user shelf", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "labeller")
      vn = insert_vn!("Tagged VN")
      insert_status!(user, vn, :read)

      shelf =
        %Shelf{}
        |> Shelf.changeset(%{user_id: user.id, name: "Favourites", slug: "favourites"})
        |> Repo.insert!()

      Repo.insert!(%ShelfItem{shelf_id: shelf.id, visual_novel_id: vn.id})
      Repo.update!(Ecto.Changeset.change(shelf, vns_count: 1))

      {:ok, _view, html} = live(conn, "/@labeller/library/favourites")

      assert html =~ "Tagged VN"
      assert html =~ "Favourites"
    end

    test "uses production desktop page size on the server render", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "page_sized")
      base = ~U[2026-01-01 00:00:00Z]

      for n <- 1..43 do
        vn = insert_vn!("Page Size VN #{String.pad_leading(to_string(n), 3, "0")}")
        insert_status!(user, vn, :read, %{added_at: DateTime.add(base, n, :second)})
      end

      {:ok, _view, html} = live(conn, "/@page_sized/library")

      assert KaguyaWeb.ProfileLive.LibraryData.page_size() == 42
      assert html =~ "Page Size VN 043"
      assert html =~ "Page Size VN 002"
      refute html =~ "Page Size VN 001"
    end

    test "mobile load more control appends remaining items using mobile page size", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "mobile_more")
      base = ~U[2026-01-01 00:00:00Z]

      for n <- 1..50 do
        vn = insert_vn!("Load More VN #{String.pad_leading(to_string(n), 3, "0")}")
        insert_status!(user, vn, :read, %{added_at: DateTime.add(base, n, :second)})
      end

      {:ok, view, html} = live(conn, "/@mobile_more/library")

      assert KaguyaWeb.ProfileLive.LibraryData.mobile_page_size() == 40
      assert html =~ ~s(data-mobile-load-more)
      assert html =~ ~s(data-mobile-page-size="40")
      refute html =~ "Load More VN 001"

      html = render_click(view, "load_more")

      assert html =~ "Load More VN 001"
      assert html =~ "Load More VN 050"
    end

    test "owner sees mobile more controls and visible show-dates toggle", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "owner_show_dates")
      insert_status!(user, insert_vn!("Owner Menu VN"), :read)

      conn =
        conn |> Plug.Test.init_test_session(%{current_user_id: user.id})

      {:ok, view, html} = live(conn, "/@owner_show_dates/library")

      assert html =~ ~s(data-is-owner="true")
      assert html =~ ~s(aria-label="More library filters")
      assert html =~ ~s(aria-label="Library actions")
      assert html =~ "Rating"
      assert html =~ "Tags"
      assert html =~ "Labels"
      assert html =~ "Show dates"
      assert html =~ ~s(data-show-dates-toggle)

      # Opening the cover action dropdown reveals the three action rows.
      html =
        render_click(element(view, ~s(button[aria-label="Library actions"])))

      assert html =~ "Edit labels"
      assert html =~ "Change status"
      assert html =~ "Edit dates"
    end

    test "non-owner viewer sees fade-read controls in desktop and mobile more menu", %{conn: conn} do
      _owner = UserFixtures.insert_user!(username: "library_owner")
      viewer = UserFixtures.insert_user!(username: "library_viewer")

      conn =
        conn |> Plug.Test.init_test_session(%{current_user_id: viewer.id})

      {:ok, _view, html} = live(conn, "/@library_owner/library")

      assert html =~ ~s(data-fade-toggle)
      assert html =~ ~s(data-is-owner="false")
      assert html =~ ~s(data-is-logged-in="true")
      assert html =~ "Fade read"
    end

    test "signed-out viewer still renders the grid for a public profile", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "public_user")
      vn = insert_vn!("Anon Visible")
      insert_status!(user, vn, :read)

      {:ok, _view, html} = live(conn, "/@public_user/library")

      assert html =~ "Anon Visible"
      assert html =~ ~s(data-is-logged-in="false")
      # Fade-read is hidden for signed-out viewers (production hides it too).
      refute html =~ ~s(data-fade-toggle)
    end

    test "renders user-not-found for an unknown username", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/@no_such_library")
      assert html =~ "User not found"
    end

    test "sorting via set_sort event pushes a new patch", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "sorter")
      vn1 = insert_vn!("Alpha Sort")
      vn2 = insert_vn!("Beta Sort")
      insert_status!(user, vn1, :read)
      insert_status!(user, vn2, :read)
      Repo.insert!(%Rating{user_id: user.id, visual_novel_id: vn1.id, rating: 5.0})
      Repo.insert!(%Rating{user_id: user.id, visual_novel_id: vn2.id, rating: 2.0})

      {:ok, view, _html} = live(conn, "/@sorter/library/read")

      html = render_click(view, "set_sort", %{"value" => "my-highest-rated"})

      # The grid still shows both items; the URL should now carry the sort param.
      assert html =~ "Alpha Sort"
      assert html =~ "Beta Sort"
      assert_patched(view, "/@sorter/library/read?sort=my-highest-rated")
    end

    test "review icon links to the VN review page when the user has a review", %{conn: conn} do
      user = UserFixtures.insert_user!(username: "review_writer")
      vn = insert_vn!("Reviewed VN")
      insert_status!(user, vn, :read)

      Repo.insert!(%Review{
        user_id: user.id,
        visual_novel_id: vn.id,
        content: String.duplicate("good ", 20)
      })

      {:ok, _view, html} = live(conn, "/@review_writer/library")

      assert html =~ "/@review_writer/reviews/" <> vn.slug
    end
  end
end
