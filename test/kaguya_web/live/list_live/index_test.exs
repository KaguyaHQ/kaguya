defmodule KaguyaWeb.ListLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  test "renders the migrated lists index sections", %{conn: conn} do
    owner = insert_user!("index_owner")
    liker = insert_user!("index_liker")
    vn = insert_vn!("Index VN")

    {:ok, popular} =
      Lists.create_list(%{
        user_id: owner.id,
        name: "Popular Index Picks",
        description: "A list with a description",
        vn_ids: [vn.id]
      })

    {:ok, _staff_pick} =
      Lists.create_list(%{
        user_id: owner.id,
        name: "Yuri",
        vn_ids: [vn.id]
      })

    {:ok, _new_list} =
      Lists.create_list(%{
        user_id: owner.id,
        name: "Fresh Index Picks",
        vn_ids: [vn.id]
      })

    assert {:ok, true} = Lists.like_list(popular.id, liker.id)

    {:ok, _view, html} = live(conn, ~p"/lists")

    assert html =~ "Start Your Own List"
    assert html =~ "Popular Lists"
    assert html =~ "Staff Picks"
    assert html =~ "Recently Liked"
    assert html =~ "New Lists"
    assert html =~ "Popular Index Picks"
    assert html =~ "A list with a description"
    assert html =~ "Fresh Index Picks"
    assert html =~ "/@#{owner.username}/list/#{popular.slug}"
    refute html =~ "The public index is still being ported"
  end

  test "renders the create button even when there are no public lists", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/lists")

    assert html =~ "Start Your Own List"
    assert html =~ ~s(<button)
    assert html =~ "Sign in to create a list"
    assert html =~ ~s(href="/login?redirectTo=%2Flists")
    assert html =~ ~s(href="/signup?redirectTo=%2Flists")
    refute html =~ "The direct list pages and editor routes are already available"
  end

  test "links directly to the new list page when signed in", %{conn: conn} do
    user = insert_user!("signed_in_index")

    {:ok, _view, html} =
      conn
      |> log_in(user)
      |> live(~p"/lists")

    assert html =~ ~s(href="/list/new")
    refute html =~ "Sign in to create a list"
    refute html =~ ~s(href="/login?redirectTo=%2Flists")
  end

  defp insert_user!(prefix) do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.create_changeset(%{
      id: Ecto.UUID.generate(),
      username: "#{prefix}_#{suffix}",
      display_name: "Index User #{suffix}",
      email: "#{prefix}-#{suffix}@example.com"
    })
    |> Repo.insert!()
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp log_in(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
  end
end
