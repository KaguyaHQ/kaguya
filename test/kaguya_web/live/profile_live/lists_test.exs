defmodule KaguyaWeb.ProfileLive.ListsTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/lists" do
    test "renders list rows with stacked cover data and no coming-soon stub", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
      vn = insert_vn!("Tsukihime")

      {:ok, list} =
        Lists.create_list(%{
          user_id: owner.id,
          name: "Alice Picks",
          description: "A public list",
          vn_ids: [vn.id]
        })

      {:ok, _view, html} = live(conn, "/@alice/lists")

      assert html =~ "Alice Picks"
      assert html =~ "1 VN"
      assert html =~ ~s(href="/@alice/list/#{list.slug}")
      assert html =~ vn.title
      refute html =~ "coming soon"
      refute html =~ "Start a new list"
    end

    test "owner sees the new-list CTA and row edit link", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "list_owner", display_name: "Owner")
      vn = insert_vn!("Owner VN")

      {:ok, list} =
        Lists.create_list(%{
          user_id: owner.id,
          name: "Owner Picks",
          is_public: false,
          vn_ids: [vn.id]
        })

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@list_owner/lists")

      assert html =~ "Owner Picks"
      assert html =~ "Start a new list"
      assert html =~ "/list/new"
      assert html =~ ~s(href="/@list_owner/list/#{list.slug}/edit")
    end

    test "renders the empty state when the profile has no lists", %{conn: conn} do
      _owner = UserFixtures.insert_user!(username: "empty_lists", display_name: "Empty")

      {:ok, _view, html} = live(conn, "/@empty_lists/lists")

      assert html =~ "No lists yet."
      refute html =~ "lists are private"
    end

    test "renders the private state when only private lists exist for another viewer", %{
      conn: conn
    } do
      owner =
        UserFixtures.insert_user!(username: "private_lists", display_name: "Private")

      vn = insert_vn!("Private VN")

      {:ok, _list} =
        Lists.create_list(%{
          user_id: owner.id,
          name: "Secret Picks",
          is_public: false,
          vn_ids: [vn.id]
        })

      {:ok, _view, html} = live(conn, "/@private_lists/lists")

      assert html =~ "lists are private"
      refute html =~ "Secret Picks"
    end

    test "paginates profile lists through the URL", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "paged_lists", display_name: "Paged")
      vn = insert_vn!("Paged VN")

      for n <- 1..13 do
        {:ok, _list} =
          Lists.create_list(%{
            user_id: owner.id,
            name: "Paged List #{n}",
            vn_ids: [vn.id]
          })
      end

      {:ok, view, html} = live(conn, "/@paged_lists/lists")

      assert html =~ "/@paged_lists/lists?page=2"

      page_2_html = render_patch(view, "/@paged_lists/lists?page=2")

      assert page_2_html =~ "Paged List"
      assert page_2_html =~ ~s(href="/@paged_lists/lists")
    end
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end
