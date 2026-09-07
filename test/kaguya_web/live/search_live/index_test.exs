defmodule KaguyaWeb.SearchLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Lists.List, as: VNList
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.Series, as: VNSeries

  test "renders the search shell with tabs and navbar actions" do
    {:ok, _view, html} = live(build_conn(), "/search?type=series")

    assert html =~ "Search by name"
    assert html =~ "Visual Novels"
    assert html =~ "Series"
    assert html =~ "Characters"
    assert html =~ "Lists"
    assert html =~ "Log in"
    assert html =~ "Sign up"
    assert html =~ ~s(name="robots" content="noindex,follow")
  end

  test "searches series from query params" do
    series = insert_series!("Clockwork Search Suite")

    {:ok, _view, html} = live(build_conn(), "/search?type=series&q=Clockwork")

    assert html =~ series.name
    assert html =~ "/series/#{series.slug}"
    assert html =~ "(1 results)"
    refute html =~ "No results found"
  end

  test "preserves the query when switching tabs" do
    {:ok, _view, html} = live(build_conn(), "/search?type=series&q=umineko")

    assert html =~ ~s(href="/search?type=visualNovels&amp;q=umineko")
    assert html =~ ~s(href="/search?type=characters&amp;q=umineko")
    assert html =~ ~s(href="/search?type=lists&amp;q=umineko")
  end

  defp insert_series!(name) do
    %VNSeries{}
    |> VNSeries.changeset(%{name: name})
    |> Repo.insert!()
  end

  test "blank list search paginates distinct trending results and supports direct pages" do
    user = UserFixtures.insert_user!()

    lists =
      for n <- 1..25 do
        %VNList{trending_score: 100.0 - n}
        |> VNList.changeset(%{user_id: user.id, name: "Trending list #{n}"})
        |> Repo.insert!()
      end

    private = insert_list!(user, "Private list", is_public: false)

    hidden =
      insert_list!(user, "Hidden list",
        hidden_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    first = hd(lists)
    last = List.last(lists)
    {:ok, view, _} = live(build_conn(), "/search?type=lists")

    assert has_element?(view, "#search-list-#{first.id}")
    refute has_element?(view, "#search-list-#{last.id}")
    refute has_element?(view, "#search-list-#{private.id}")
    refute has_element?(view, "#search-list-#{hidden.id}")
    assert has_element?(view, "#search-pagination", "Page 1 of 2")

    view |> element("#search-next-page") |> render_click()
    assert_patch(view, "/search?type=lists&page=2")
    assert has_element?(view, "#search-list-#{last.id}")
    refute has_element?(view, "#search-list-#{first.id}")
    refute has_element?(view, "#search-next-page")

    view |> element("#search-previous-page") |> render_click()
    assert has_element?(view, "#search-list-#{first.id}")

    {:ok, direct, _} = live(build_conn(), "/search?type=lists&page=2")
    assert has_element?(direct, "#search-list-#{last.id}")
    assert has_element?(direct, "#search-pagination", "Page 2 of 2")
  end

  defp insert_list!(user, name, attrs) do
    %VNList{trending_score: 200.0}
    |> VNList.changeset(%{user_id: user.id, name: name})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
