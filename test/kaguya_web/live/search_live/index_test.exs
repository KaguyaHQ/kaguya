defmodule KaguyaWeb.SearchLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
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
end
