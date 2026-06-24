defmodule KaguyaWeb.ProfileLive.FavoritesTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Characters.Character
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/favorites" do
    test "renders the favorites page for any user", %{conn: conn} do
      _user = UserFixtures.insert_user!(username: "free_favorites", display_name: "Free")

      {:ok, _view, html} = live(conn, "/@free_favorites/favorites")

      assert html =~ "Favorite Visual Novels"
      assert html =~ "Favorite Characters"
      assert html =~ "No favorites added yet"
      refute html =~ "This feature is available to patrons."
      refute html =~ ~s(href="/patron")
    end

    test "renders favorite VNs and characters in pinned order", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "fav_order", display_name: "Fav Order")
      first_vn = insert_vn!("Second Pinned")
      second_vn = insert_vn!("First Pinned")
      first_character = insert_character!("Second Character")
      second_character = insert_character!("First Character")

      pin_vns!(owner, [second_vn.id, first_vn.id])
      pin_characters!(owner, [second_character.id, first_character.id])

      {:ok, _view, html} = live(conn, "/@fav_order/favorites")

      assert html =~ "First Pinned"
      assert html =~ "Second Pinned"
      assert html =~ ~s(href="/vn/#{second_vn.slug}")
      assert html =~ "First Character"
      assert html =~ "Second Character"
      assert html =~ ~s(href="/character/#{second_character.slug}")
      assert html =~ "Favorite Visual Novels"
      assert html =~ "Favorite Characters"
      refute html =~ "coming soon"
    end

    test "owner empty state opens the favorites editor", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "empty_owner", display_name: "Empty Owner")

      {:ok, view, html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@empty_owner/favorites")

      assert html =~ "Add your favorites"
      refute html =~ ~s(href="/account/edit/profile#favorite-visual-novels")
      refute html =~ "No favorites added yet"

      html = render_click(view, "open_editor")

      assert html =~ "Edit favorites"
      assert html =~ "Favorite Visual Novels"
      assert html =~ "Favorite Characters"
      assert html =~ "0/100"
      assert html =~ "Save"
      assert html =~ "Cancel"
    end

    test "owner sees restricted favorite VNs but visitors do not", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "filtered_faves", display_name: "Filtered")
      visible_vn = insert_vn!("Visible Favorite", title_category: :vn)
      hidden_vn = insert_vn!("Hidden Favorite", title_category: :nukige)

      pin_vns!(owner, [visible_vn.id, hidden_vn.id])

      {:ok, _view, visitor_html} = live(conn, "/@filtered_faves/favorites")

      assert visitor_html =~ "Visible Favorite"
      refute visitor_html =~ "Hidden Favorite"

      {:ok, _view, owner_html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@filtered_faves/favorites")

      assert owner_html =~ "Visible Favorite"
      assert owner_html =~ "Hidden Favorite"
    end

    test "owner edit mode exposes slot counts and reorder controls", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "edit_controls", display_name: "Edit Controls")
      vn = insert_vn!("Editable VN")
      character = insert_character!("Editable Character")

      pin_vns!(owner, [vn.id])
      pin_characters!(owner, [character.id])

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@edit_controls/favorites")

      html = render_click(view, "open_editor")

      assert html =~ "Edit favorites"
      assert html =~ "1/100"
      assert html =~ ~s(aria-label="Add Favorite Visual Novels")
      assert html =~ ~s(aria-label="Add Favorite Characters")
      assert html =~ ~s(aria-label="Remove Editable VN from favorites")
      assert html =~ ~s(aria-label="Move Editable VN up")
      assert html =~ ~s(aria-label="Move Editable VN down")
      assert html =~ "Move items to reorder"
    end

    test "owner can save added, removed, and reordered favorites", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "save_faves", display_name: "Save Faves")
      first_vn = insert_vn!("First Saved")
      second_vn = insert_vn!("Second Saved")
      removed_character = insert_character!("Removed Character")
      kept_character = insert_character!("Kept Character")

      pin_vns!(owner, [first_vn.id])
      pin_characters!(owner, [removed_character.id])

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@save_faves/favorites")

      render_click(view, "open_editor")
      render_click(view, "add_favorite", %{"type" => "visual_novels", "id" => second_vn.id})

      render_click(view, "move_favorite", %{
        "type" => "visual_novels",
        "id" => second_vn.id,
        "direction" => "up"
      })

      render_click(view, "remove_favorite", %{
        "type" => "characters",
        "id" => removed_character.id
      })

      render_click(view, "add_favorite", %{"type" => "characters", "id" => kept_character.id})

      html = render_click(view, "save_editor")

      assert html =~ "Second Saved"
      assert html =~ "First Saved"
      assert html =~ "Kept Character"
      refute html =~ "Removed Character"
      refute html =~ "Edit favorites</h1>"

      assert Repo.get!(Kaguya.Users.User, owner.id).favorite_visual_novels == [
               second_vn.id,
               first_vn.id
             ]

      assert [kept_character.id] ==
               Repo.all(
                 from(cf in Kaguya.Characters.CharacterFavorite,
                   where: cf.user_id == ^owner.id,
                   order_by: cf.position,
                   select: cf.character_id
                 )
               )
    end
  end

  defp insert_vn!(title, attrs \\ []) do
    attrs = Keyword.merge([title: title, original_language: "en"], attrs)

    %VisualNovel{}
    |> VisualNovel.changeset(Map.new(attrs))
    |> Repo.insert!()
  end

  defp insert_character!(name) do
    %Character{}
    |> Character.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp pin_vns!(user, ids) do
    Repo.update_all(
      from(u in Kaguya.Users.User, where: u.id == ^user.id),
      set: [favorite_visual_novels: ids]
    )
  end

  defp pin_characters!(user, ids) do
    user = Repo.get!(Kaguya.Users.User, user.id)
    {:ok, _user} = Users.update_user(user, %{favorite_characters: ids})
  end
end
