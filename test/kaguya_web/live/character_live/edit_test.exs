defmodule KaguyaWeb.CharacterLive.EditTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.Hist.VnCharacterHist
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.{VisualNovel, VNPageCache, VNTitle}
  alias KaguyaWeb.UserAuth

  setup %{conn: conn} do
    user = UserFixtures.insert_user!(username: "appearance_editor")
    conn = conn |> Plug.Test.init_test_session(%{}) |> UserAuth.log_in_user(user)
    %{conn: conn, user: user}
  end

  test "creates a character with multiple appearances and records them in history", %{conn: conn} do
    first = vn!("Appearance Alpha")
    second = vn!("Appearance Beta")
    {:ok, view, _} = live(conn, ~p"/contribute/character")

    add_vn(view, first)
    add_vn(view, second)

    render_submit(element(view, "#character-edit"), %{
      "character" => %{
        "name" => "Linked Heroine",
        "description" => "Appears across two games.",
        "appearances" => %{
          first.id => %{"role" => "main", "spoiler_level" => "2"},
          second.id => %{"role" => "primary", "spoiler_level" => "1"}
        }
      }
    })

    character = Repo.get_by!(Character, name: "Linked Heroine")
    assert_redirect(view, "/character/#{character.slug}")

    assert %{role: :main, spoiler_level: 2} =
             Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: first.id)

    assert %{role: :primary, spoiler_level: 1} =
             Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: second.id)

    assert Repo.aggregate(
             from(h in VnCharacterHist, where: h.character_id == ^character.id),
             :count
           ) == 2
  end

  test "edits and removes links, invalidates VN pages, and supports revision reverts", %{
    conn: conn,
    user: user
  } do
    first = vn!("Appearance Existing")
    second = vn!("Appearance Removed")

    {:ok, %{entity: character, change: initial}} =
      Revisions.create_entity(
        :character,
        %{
          name: "Existing Heroine",
          appearances: [appearance(first), appearance(second)]
        },
        "Created with cast links",
        user
      )

    cache_key = {:vn_page, second.id, :appearance_test}
    Cachex.put(VNPageCache.cache(), cache_key, :old_cast)
    on_exit(fn -> Cachex.del(VNPageCache.cache(), cache_key) end)
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    assert has_element?(view, "#appearance-role-#{first.id} option[value=side][selected]")
    render_click(element(view, "#remove-appearance-#{second.id}"))

    render_submit(element(view, "#character-edit"), %{
      "character" => %{
        "summary" => "Correct cast",
        "appearances" => %{first.id => %{"role" => "appears", "spoiler_level" => "1"}}
      }
    })

    assert %{role: :appears, spoiler_level: 1} =
             Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: first.id)

    refute Repo.get_by(VNCharacter, character_id: character.id, visual_novel_id: second.id)
    assert {:ok, nil} = Cachex.get(VNPageCache.cache(), cache_key)
    assert {:ok, _} = Revisions.revert_to_revision(initial.id, "Restore original cast", user)

    assert Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: second.id).role ==
             :side
  end

  test "search includes alternate titles and excludes hidden or already selected VNs", %{
    conn: conn
  } do
    vn = vn!("A Different Title")
    Repo.insert!(%VNTitle{visual_novel_id: vn.id, title: "Appearance Alias", lang: "en"})
    hidden = vn!("Appearance Hidden", hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    render_change(element(view, "#character-vn-search"), %{"appearance_query" => "Appearance"})
    assert has_element?(view, "#appearance_results-#{vn.id}")
    refute has_element?(view, "#appearance_results-#{hidden.id}")
    render_click(element(view, "#appearance_results-#{vn.id}"))
    render_change(element(view, "#character-vn-search"), %{"appearance_query" => "Appearance"})
    refute has_element?(view, "#appearance_results-#{vn.id}")
    assert has_element?(view, "#character-vn-no-results")
  end

  test "preserves hidden existing links when editing a description", %{conn: conn, user: user} do
    hidden = vn!("Secret Appearance", hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))

    {:ok, %{entity: character}} =
      Revisions.create_entity(
        :character,
        %{name: "Hidden Link", appearances: [appearance(hidden)]},
        "Created",
        user
      )

    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    assert has_element?(view, "#appearances-#{hidden.id}", "Hidden visual novel")
    refute has_element?(view, "#appearances-#{hidden.id} a")

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"description" => "Updated description"}
    })

    assert Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: hidden.id)
  end

  test "rejects invalid role values without creating a partial character", %{conn: conn} do
    vn = vn!("Appearance Validation")
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    add_vn(view, vn)

    render_submit(view, "save", %{
      "character" => %{
        "name" => "Invalid Heroine",
        "appearances" => %{vn.id => %{"role" => "arbitrary-role", "spoiler_level" => "9"}}
      }
    })

    assert has_element?(view, "#character-edit")
    refute Repo.get_by(Character, name: "Invalid Heroine")
  end

  test "stale edits cannot overwrite another editor's cast changes", %{conn: conn, user: user} do
    vn = vn!("Appearance Conflict")

    {:ok, %{entity: character}} =
      Revisions.create_entity(:character, %{name: "Concurrent Heroine"}, "Created", user)

    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")

    {:ok, _} =
      Revisions.submit_edit(
        :character,
        character.id,
        %{appearances: [appearance(vn)]},
        "Added cast link",
        user
      )

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"description" => "Stale change"}
    })

    assert has_element?(view, "#character-edit")
    assert Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: vn.id)
    refute Repo.get!(Character, character.id).description == "Stale change"
  end

  test "removing the final appearance saves an empty cast", %{conn: conn, user: user} do
    vn = vn!("Appearance Final")

    {:ok, %{entity: character}} =
      Revisions.create_entity(
        :character,
        %{name: "Final Link", appearances: [appearance(vn)]},
        "Created",
        user
      )

    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    render_click(element(view, "#remove-appearance-#{vn.id}"))
    refute has_element?(view, "#appearance-role-#{vn.id}")

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"summary" => "Remove mistaken appearance"}
    })

    refute Repo.get_by(VNCharacter, character_id: character.id)
  end

  test "invalid appearance edits roll back existing links and scalar changes", %{user: user} do
    vn = vn!("Appearance Atomic")

    {:ok, %{entity: character}} =
      Revisions.create_entity(
        :character,
        %{name: "Atomic Heroine", appearances: [appearance(vn)]},
        "Created",
        user
      )

    for invalid <- [
          [%{appearance(vn) | role: "invalid-role"}],
          [%{appearance(vn) | spoiler_level: 9}],
          [appearance(vn), appearance(vn)],
          [%{appearance(vn) | visual_novel_id: Ecto.UUID.generate()}]
        ] do
      assert {:error, _} =
               Revisions.submit_edit(
                 :character,
                 character.id,
                 %{description: "Should roll back", appearances: invalid},
                 "Invalid cast",
                 user
               )

      assert Repo.get_by!(VNCharacter, character_id: character.id, visual_novel_id: vn.id).role ==
               :side

      refute Repo.get!(Character, character.id).description == "Should roll back"
      assert Revisions.latest_revision_number(:character, character.id) == 1
    end
  end

  test "forged search-result IDs cannot add appearances", %{conn: conn} do
    vn = vn!("Appearance Forged")
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    render_click(view, "add_appearance", %{"id" => vn.id})
    refute has_element?(view, "#appearance-role-#{vn.id}")
  end

  test "locked characters do not accept forged editor events", %{conn: conn} do
    character =
      %Character{}
      |> Character.changeset(%{name: "Locked Heroine"})
      |> Ecto.Changeset.change(is_locked: true)
      |> Repo.insert!()

    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    refute has_element?(view, "#character-edit")
    render_submit(view, "save", %{"character" => %{"description" => "Forged change"}})
    refute Repo.get!(Character, character.id).description == "Forged change"
  end

  defp add_vn(view, vn) do
    render_change(element(view, "#character-vn-search"), %{"appearance_query" => vn.title})
    render_click(element(view, "#appearance_results-#{vn.id}"))
    assert has_element?(view, "#appearance-role-#{vn.id}")
  end

  defp vn!(title, attrs \\ []) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{title: title})
    |> Ecto.Changeset.change(Map.new(attrs))
    |> Repo.insert!()
  end

  defp appearance(vn), do: %{visual_novel_id: vn.id, role: :side, spoiler_level: 0}
end
