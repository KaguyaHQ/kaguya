defmodule KaguyaWeb.BrowseLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Characters.Character
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    Cachex.clear(:vn_browse_cache)
    Cachex.clear(:character_browse_cache)
    :ok
  end

  test "browse defaults to a catalogue ordered by popularity", %{conn: conn} do
    popular = insert_vn!("Popular Browse VN", average_rating: 4.2, ratings_count: 120)
    rated = insert_vn!("Highly Rated VN", average_rating: 4.7, ratings_count: 20)

    {:ok, view, _html} = live(conn, ~p"/browse")

    assert has_element?(view, "#browse-catalogue tbody tr:first-child#browse-vn-#{popular.id}")
    assert has_element?(view, "#browse-vn-#{rated.id}")

    assert has_element?(
             view,
             "#browse-vn-#{popular.id} span[title='Average rating out of 5']",
             "4.20"
           )

    assert has_element?(view, "#browse-sort-top-rated", "Rating / 5")
    assert has_element?(view, "#browse-catalogue th[aria-sort='descending']", "Votes")
    assert has_element?(view, "#browse-vn-#{popular.id} th[scope='row']", popular.title)
    assert has_element?(view, "#browse-vn-link-#{popular.id}[data-phx-link='redirect']")
    assert has_element?(view, "#browse-discover-link[href='/discover']")
    refute has_element?(view, "[phx-hook='BrowseSectionRow']")

    view |> element("#browse-sort-top-rated") |> render_click()
    assert_patch(view, ~p"/browse?sort=top-rated")
    assert has_element?(view, "#browse-catalogue tbody tr:first-child#browse-vn-#{rated.id}")

    view |> element("#browse-sort-top-rated") |> render_click()
    assert_patch(view, ~p"/browse?sort=lowest-rated")
    assert has_element?(view, "#browse-catalogue tbody tr:first-child#browse-vn-#{popular.id}")
  end

  test "discover preserves shelves and links into the catalogue", %{conn: conn} do
    insert_vn!("Popular Browse VN", average_rating: 4.2, ratings_count: 120)
    {:ok, view, _html} = live(conn, ~p"/discover")

    assert has_element?(view, "#browse-section-row-popular")
    assert has_element?(view, "#discover-browse-link[href='/browse']")

    assert has_element?(
             view,
             "[data-section-id='popular'] a[data-phx-link='redirect'][href='/browse?sort=most-popular']"
           )

    refute has_element?(view, "#browse-catalogue")
  end

  test "column sorting retains filters and resets the page", %{conn: conn} do
    insert_vn!("Filtered VN", average_rating: 4.0, ratings_count: 20)
    {:ok, view, _html} = live(conn, ~p"/browse?minRatings=5&page=2")

    view |> element("#browse-sort-newest") |> render_click()
    assert_patch(view, ~p"/browse?minRatings=5&sort=newest")
    assert has_element?(view, "#browse-catalogue th[aria-sort='descending']", "Released")
  end

  test "empty results can clear filters", %{conn: conn} do
    insert_vn!("Low Rating VN", average_rating: 2.5, ratings_count: 10)
    {:ok, view, _html} = live(conn, ~p"/browse?minRating=4.5")
    assert has_element?(view, "#browse-empty")
    view |> element("#browse-clear-filters") |> render_click()
    assert_patch(view, ~p"/browse")
    assert has_element?(view, "#browse-catalogue")
  end

  test "catalogue pagination reaches beyond ten pages and clamps out-of-range pages" do
    novels = for n <- 1..12, do: insert_vn!("Catalogue #{n}", ratings_count: n)

    result =
      Kaguya.VisualNovels.browse_visual_novels(
        page: 11,
        page_size: 1,
        sort_by: :total_ratings_desc
      )

    assert result.pagination.total_count == 12
    assert result.pagination.total_pages == 12
    assert result.pagination.page == 11
    assert hd(result.items).id == Enum.at(novels, 1).id

    last =
      Kaguya.VisualNovels.browse_visual_novels(
        page: 999,
        page_size: 1,
        sort_by: :total_ratings_desc
      )

    assert last.pagination.page == 12
    assert hd(last.items).id == hd(novels).id
  end

  test "bare browse is index,follow; filtered variants are noindex,follow", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/browse")
    assert html =~ ~s(<meta name="robots" content="index,follow")

    {:ok, _view, filtered} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")
    assert filtered =~ ~s(<meta name="robots" content="noindex,follow")
  end

  test "blurs sensitive VN covers in the catalogue", %{conn: conn} do
    avn =
      insert_vn!("Sensitive AVN Browse VN",
        average_rating: 4.2,
        ratings_count: 120,
        is_avn: true,
        is_image_nsfw: true
      )

    {:ok, view, _html} = live(conn, ~p"/browse")

    assert has_element?(view, "#browse-vn-#{avn.id} img[data-nsfw-blur='1']")

    suggestive =
      insert_vn!("Suggestive Browse VN",
        average_rating: 3.8,
        ratings_count: 42,
        is_image_suggestive: true
      )

    {:ok, view, _html} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")

    assert has_element?(view, "#browse-vn-#{suggestive.id} img[data-nsfw-blur='1']")
  end

  test "renders polished desktop browse filter chips", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/browse")

    assert html =~ "Change browse type"
    assert html =~ "Sort"
    assert html =~ "Tags"
    assert html =~ "Platform"
    assert html =~ "Nintendo Switch"
    assert html =~ "Search tags..."
    assert html =~ ~s(href="/browse?sort=most-popular")
  end

  test "renders the filtered VN catalogue from query params", %{conn: conn} do
    filtered = insert_vn!("Filtered Browse VN", average_rating: 3.8, ratings_count: 42)
    excluded = insert_vn!("Too Few Ratings VN", average_rating: 4.6, ratings_count: 1)

    {:ok, view, _html} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")

    assert has_element?(view, "#browse-vn-#{filtered.id}", filtered.title)

    assert has_element?(
             view,
             "#browse-vn-#{filtered.id} span[title='Average rating out of 5']",
             "3.80"
           )

    assert has_element?(view, "#browse-vn-#{filtered.id} td:last-child", "42")
    refute has_element?(view, "#browse-vn-#{excluded.id}")
    assert has_element?(view, "#browse-desktop-range-minRatings-trigger", "Over 5 Ratings")
  end

  test "renders character browse route with sort controls", %{conn: conn} do
    insert_character!("Browse Character")

    {:ok, _view, html} = live(conn, ~p"/browse/characters?sort=name-a-z")

    assert html =~ "Browse Character"
    assert html =~ "Most Popular"
    assert html =~ "Name A-Z"
    assert html =~ "Recently Added"
  end

  defp insert_vn!(title, attrs) do
    suffix = System.unique_integer([:positive])

    %VisualNovel{}
    |> VisualNovel.changeset(
      Map.merge(
        %{
          title: "#{title} #{suffix}",
          original_language: "en",
          title_category: :vn,
          temp_image_url: "https://images.example/#{suffix}.jpg"
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  defp insert_character!(name) do
    suffix = System.unique_integer([:positive])

    %Character{}
    |> Character.changeset(%{
      name: "#{name} #{suffix}",
      favorites_count: 10
    })
    |> Repo.insert!()
  end
end
