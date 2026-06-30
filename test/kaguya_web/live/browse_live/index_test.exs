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

  test "renders the browse explore sections", %{conn: conn} do
    insert_vn!("Popular Browse VN", average_rating: 8.4, ratings_count: 120)

    {:ok, _view, html} = live(conn, ~p"/browse")

    assert html =~ "VNs"
    assert html =~ "Characters"
    assert html =~ "Popular"
    assert html =~ "AVNs"
    assert html =~ "Romance"
    assert html =~ "Free on Itch"
    assert html =~ "Popular Browse VN"
    assert html =~ ~s(phx-hook="BrowseSectionRow")
    assert html =~ ~s(aria-label="Scroll previous")
    assert html =~ ~s(aria-label="Scroll next")
  end

  test "bare browse is index,follow; filtered variants are noindex,follow", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/browse")
    assert html =~ ~s(<meta name="robots" content="index,follow")

    {:ok, _view, filtered} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")
    assert filtered =~ ~s(<meta name="robots" content="noindex,follow")
  end

  test "blurs sensitive VN covers in browse rows and grids", %{conn: conn} do
    avn =
      insert_vn!("Sensitive AVN Browse VN",
        average_rating: 8.4,
        ratings_count: 120,
        is_avn: true,
        is_image_nsfw: true
      )

    {:ok, _view, html} = live(conn, ~p"/browse")

    assert html =~ ~r/alt="#{Regex.escape(avn.title)}"[^>]+data-nsfw-blur="1"/
    assert html =~ ~r/alt="#{Regex.escape(avn.title)}"[^>]+--nsfw-blur-size: 172;/

    suggestive =
      insert_vn!("Suggestive Browse VN",
        average_rating: 7.7,
        ratings_count: 42,
        is_image_suggestive: true
      )

    {:ok, _view, html} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")

    assert html =~ ~r/alt="#{Regex.escape(suggestive.title)}"[^>]+data-nsfw-blur="1"/
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

  test "renders the filtered VN grid from query params", %{conn: conn} do
    insert_vn!("Filtered Browse VN", average_rating: 7.7, ratings_count: 42)
    insert_vn!("Too Few Ratings VN", average_rating: 9.1, ratings_count: 1)

    {:ok, _view, html} = live(conn, ~p"/browse?sort=most-popular&minRatings=5")

    assert html =~ "Filtered Browse VN"
    assert html =~ "7.7"
    assert html =~ "42"
    refute html =~ "Too Few Ratings VN"
    assert html =~ "Over 5 Ratings"
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
