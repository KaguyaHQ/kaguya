defmodule KaguyaWeb.AccountLive.EditProfileTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Characters.Character
  alias Kaguya.Users

  test "redirects anonymous visitors to login" do
    assert {:error, {:redirect, %{to: "/login"}}} =
             live(build_conn(), "/account/edit/profile")
  end

  test "renders the profile edit page and anchor sections" do
    user =
      UserFixtures.insert_user!(
        username: "profile_owner",
        display_name: "Profile Owner",
        bio: "Old bio"
      )

    {:ok, _view, html} = live(conn_for(user), "/account/edit/profile")

    assert html =~ "Edit profile"
    assert html =~ "Profile Owner"
    assert html =~ "Old bio"
    assert html =~ ~s(id="basic-information")
    assert html =~ ~s(id="favorite-visual-novels")
    assert html =~ ~s(id="favorite-characters")
  end

  test "updates editable profile fields" do
    user = UserFixtures.insert_user!(username: "profile_editor", display_name: "Old")

    {:ok, view, _html} = live(conn_for(user), "/account/edit/profile")

    assert {:error, {:live_redirect, %{to: "/@profile_editor"}}} =
             render_submit(view, "save_profile", %{
               "profile" => %{
                 "display_name" => "New Name",
                 "username" => "profile_editor",
                 "bio" => "Updated bio",
                 "social_links" => %{
                   "website" => "https://example.com",
                   "twitter" => "@kaguya"
                 }
               }
             })

    updated = Repo.get!(User, user.id)
    assert updated.display_name == "New Name"
    assert updated.bio == "Updated bio"
    assert updated.social_links.website == "https://example.com"
    assert updated.social_links.twitter == "kaguya"
  end

  test "blocks profile save while a cropped profile image is still uploading" do
    user =
      UserFixtures.insert_user!(username: "profile_image_editor", display_name: "Old")

    {:ok, view, _html} = live(conn_for(user), "/account/edit/profile")

    render_hook(view, "image-cropped", %{"image_type" => "avatar"})

    assert render(view) =~ "Uploading image"

    render_submit(view, "save_profile", %{
      "profile" => %{
        "display_name" => "New Name",
        "username" => "profile_image_editor",
        "bio" => "",
        "social_links" => %{"website" => "", "twitter" => ""}
      }
    })

    assert render(view) =~ "Please wait for your profile image to finish uploading."

    render_hook(view, "image-upload-failed", %{
      "image_type" => "avatar",
      "message" => "Upload failed. Try again."
    })

    html = render(view)
    assert html =~ "Upload failed. Try again."
    refute html =~ "Uploading image"
  end

  test "saves reordered top profile favorites while preserving hidden tail favorites" do
    user =
      UserFixtures.insert_user!(
        username: "favorite_editor",
        display_name: "Old"
      )

    [vn1, vn2, vn3, vn4, vn5] = for title <- ~w(One Two Three Four Five), do: insert_vn!(title)
    [char1, char2] = for name <- ["Akiha", "Ciel"], do: insert_character!(name)

    {:ok, user} =
      Users.update_user(user, %{
        favorite_visual_novels: Enum.map([vn1, vn2, vn3, vn4, vn5], & &1.id),
        favorite_characters: Enum.map([char1, char2], & &1.id)
      })

    {:ok, view, html} = live(conn_for(user), "/account/edit/profile")

    assert html =~ "Drag to reorder"
    assert html =~ "+ 1 more not shown."

    render_hook(view, "reorder_favorite", %{"kind" => "visual_novels", "from" => 1, "to" => 0})
    render_hook(view, "remove_favorite", %{"type" => "characters", "id" => char1.id})

    render_submit(view, "save_profile", %{
      "profile" => %{
        "display_name" => user.display_name,
        "username" => user.username,
        "bio" => "",
        "social_links" => %{"website" => "", "twitter" => ""}
      }
    })

    updated = Repo.get!(User, user.id)
    assert updated.favorite_visual_novels == [vn2.id, vn1.id, vn3.id, vn4.id, vn5.id]

    assert [char2.id] == favorite_character_ids(user.id)
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  defp insert_vn!(title) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{title: title, original_language: "en"})
    |> Repo.insert!()
  end

  defp insert_character!(name) do
    %Character{}
    |> Character.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp favorite_character_ids(user_id) do
    import Ecto.Query

    Kaguya.Characters.CharacterFavorite
    |> where([cf], cf.user_id == ^user_id)
    |> order_by([cf], asc: cf.position, asc: cf.inserted_at)
    |> select([cf], cf.character_id)
    |> Repo.all()
  end
end
