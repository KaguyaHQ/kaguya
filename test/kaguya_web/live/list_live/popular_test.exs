defmodule KaguyaWeb.ListLive.PopularTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.ListLive.Data

  test "renders the popular lists page and list links", %{conn: conn} do
    owner = UserFixtures.insert_user!()
    liker = UserFixtures.insert_user!()
    vn = insert_vn!("Popular Page VN")
    list = insert_liked_list!(owner, liker, vn, "Popular Page Picks")

    {:ok, view, _html} = live(conn, ~p"/lists/popular")

    assert has_element?(view, "#popular-lists-heading")
    assert has_element?(view, "#popular-list-#{list.id}")

    assert has_element?(
             view,
             ~s(#popular-list-#{list.id} a[href="/@#{owner.username}/list/#{list.slug}"])
           )
  end

  test "loads the next cursor page", %{conn: conn} do
    owner = UserFixtures.insert_user!()
    liker = UserFixtures.insert_user!()
    vn = insert_vn!("Popular Pagination VN")

    for index <- 1..11 do
      insert_liked_list!(owner, liker, vn, "Popular Page #{index}")
    end

    assert {:ok, first_page} = Data.load_popular_lists(nil, nil, 10)
    assert first_page.has_next
    assert {:ok, %{items: [next_list]}} = Data.load_popular_lists(nil, first_page.next_cursor, 10)

    {:ok, view, _html} = live(conn, ~p"/lists/popular")

    assert has_element?(view, "button#popular-lists-load-more")
    refute has_element?(view, "#popular-list-#{next_list.id}")

    view
    |> element("button#popular-lists-load-more")
    |> render_click()

    assert has_element?(view, "#popular-list-#{next_list.id}")
    refute has_element?(view, "button#popular-lists-load-more")
  end

  test "renders an empty state when no lists have likes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lists/popular")

    assert has_element?(view, "#popular-lists-empty")
    refute has_element?(view, "button#popular-lists-load-more")
  end

  defp insert_liked_list!(owner, liker, vn, name) do
    {:ok, list} = Lists.create_list(%{user_id: owner.id, name: name, vn_ids: [vn.id]})
    assert {:ok, true} = Lists.like_list(list.id, liker.id)
    list
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end
