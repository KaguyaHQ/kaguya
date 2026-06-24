defmodule KaguyaWeb.CharacterLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query
  import Kaguya.Test.UserFixtures, only: [insert_user!: 1]

  alias Kaguya.Characters.{Character, Quote, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.VisualNovels.VisualNovel

  test "renders a character page from direct contexts", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Sky After",
        description: "A test visual novel",
        average_rating: 8.2,
        ratings_count: 25
      })
      |> Repo.insert!()

    character =
      %Character{}
      |> Character.changeset(%{
        name: "Shinohara Sora",
        description: "A **careful** student. <script>alert(1)</script>"
      })
      |> Repo.insert!()

    {1, _} =
      Character
      |> where([c], c.id == ^character.id)
      |> Repo.update_all(set: [favorites_count: 1200])

    character = Repo.reload!(character)

    %VNCharacter{}
    |> VNCharacter.changeset(%{
      visual_novel_id: vn.id,
      character_id: character.id,
      role: :main
    })
    |> Repo.insert!()

    %Quote{}
    |> Quote.changeset(%{
      visual_novel_id: vn.id,
      character_id: character.id,
      quote: "The sky is still ours.",
      likes_count: 2
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/character/#{character.slug}")

    assert html =~ "Shinohara Sora"
    assert html =~ "1.2K"
    assert html =~ ~s(href="/character/#{character.slug}/fans")
    assert html =~ "student."
    assert html =~ "<strong>careful</strong>"
    refute html =~ "alert(1)</script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ "The sky is still ours."
    assert html =~ "Appears in"
    assert html =~ "Main"
  end

  test "renders character fans", %{conn: conn} do
    character =
      %Character{}
      |> Character.changeset(%{name: "Fan Favorite"})
      |> Repo.insert!()

    fan = insert_user!(username: "reader_one", display_name: "Reader One")
    {:ok, _user} = Users.update_user(fan, %{favorite_characters: [character.id]})

    {:ok, _view, html} = live(conn, ~p"/character/#{character.slug}/fans")

    assert html =~ "Fans of"
    assert html =~ "Fan Favorite"
    assert html =~ "Reader One"
    assert html =~ "@reader_one"
  end
end
