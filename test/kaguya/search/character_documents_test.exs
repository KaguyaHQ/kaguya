defmodule Kaguya.SearchIndex.CharacterDocumentsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.SearchIndex
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  test "lists VN titles by role, then popularity, leaving out spoiler appearances" do
    mary = insert_character!("Mary", favorites_count: 12)
    cameo = insert_vn!("Cameo VN", 9_000)
    sequel = insert_vn!("Sequel", 50)
    original = insert_vn!("Original", 10)
    secret = insert_vn!("Secret Route", 99_999)

    link!(mary, cameo, :appears)
    link!(mary, sequel, :main)
    link!(mary, original, :main)
    link!(mary, secret, :main, 2)

    assert [doc] = SearchIndex.character_documents([mary])
    assert doc.name == "Mary"
    assert doc.favorites_count == 12
    assert doc.vn_titles == ["Sequel", "Original", "Cameo VN"]
  end

  test "characters without visible appearances get no titles" do
    assert [%{vn_titles: []}] = SearchIndex.character_documents([insert_character!("Loner")])
  end

  defp insert_character!(name, attrs \\ []) do
    %Character{}
    |> Character.changeset(%{name: name})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp insert_vn!(title, ratings_count) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{title: title, original_language: "en"})
    |> Ecto.Changeset.change(ratings_count: ratings_count)
    |> Repo.insert!()
  end

  defp link!(character, vn, role, spoiler_level \\ 0) do
    %VNCharacter{}
    |> VNCharacter.changeset(%{
      character_id: character.id,
      visual_novel_id: vn.id,
      role: role,
      spoiler_level: spoiler_level
    })
    |> Repo.insert!()
  end
end
