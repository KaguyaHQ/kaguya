defmodule KaguyaWeb.CharacterLive.HistoryTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Characters.Character
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Test.UserFixtures

  test "renders absolute revision timestamps for history rows", %{conn: conn} do
    editor =
      UserFixtures.insert_user!(
        username: "history_editor",
        display_name: "History Editor"
      )

    character = insert_character!("History Character")

    inserted_at = ~U[2026-04-28 17:10:00Z]

    Repo.insert!(%Change{
      entity_type: :character,
      entity_id: character.id,
      revision_number: 3,
      action: :edit,
      changed_fields: ["description"],
      summary: "Expanded biography",
      source: :user,
      user_id: editor.id,
      inserted_at: inserted_at
    })

    {:ok, _view, html} = live(conn, ~p"/character/#{character.slug}/history")

    assert html =~ "History Character"
    assert html =~ "Expanded biography"
    assert html =~ "History Editor"
    assert html =~ "Apr 28, 2026 17:10"
    refute html =~ "ago"
  end

  defp insert_character!(name) do
    suffix = System.unique_integer([:positive])

    %Character{}
    |> Character.changeset(%{
      name: "#{name} #{suffix}",
      vndb_image_id: "ch#{suffix}"
    })
    |> Repo.insert!()
  end
end
