defmodule Kaguya.Lists.CharacterListsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListCharacterItem, ListItem}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  @tiers [
    %{id: "tier-s", label: "S", color: "#f87171", position: 1},
    %{id: "tier-a", label: "A", color: "#fb923c", position: 2}
  ]

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    %{user: UserFixtures.insert_user!(), characters: for(n <- 1..3, do: insert_character!(n))}
  end

  test "creates a character tier list with placements", %{user: user, characters: [c1, c2, c3]} do
    assert {:ok, list} =
             Lists.create_list_with_layout(
               user.id,
               %{name: "Best girls", item_type: "character", display_mode: "tier"},
               %{
                 display_mode: "tier",
                 tiers: @tiers,
                 items: [
                   %{character_id: c1.id, tier_id: "tier-a", tier_position: 1},
                   %{character_id: c2.id, tier_id: "tier-s", tier_position: 1},
                   %{character_id: c3.id, tier_id: nil}
                 ]
               }
             )

    assert list.item_type == "character"
    assert list.vns_count == 3
    refute Repo.exists?(from(li in ListItem, where: li.list_id == ^list.id))

    assert {:ok, rows} = Lists.list_all_characters_for_list(list)
    assert Enum.map(rows, & &1.character.id) == [c2.id, c1.id, c3.id]
    assert Enum.map(rows, & &1.tier_position) == [1, 1, nil]
  end

  test "item_type defaults to vn and can't be changed by update", %{user: user} do
    vn = insert_vn!(:vn)
    {:ok, list} = Lists.create_list(%{user_id: user.id, name: "VNs", vn_ids: [vn.id]})
    assert list.item_type == "vn"

    {:ok, updated} = Lists.update_list(list.id, %{user_id: user.id, item_type: "character"})
    assert updated.item_type == "vn"
  end

  test "rejects VN ids, duplicates, and hidden characters", %{user: user, characters: [c1 | _]} do
    vn = insert_vn!(:vn)
    list = character_list!(user, [c1])
    layout = &%{display_mode: "tier", items: &1}

    assert {:error, :unknown_items} =
             Lists.save_list_layout(list.id, user.id, layout.([%{character_id: vn.id}]))

    assert {:error, :duplicate_item} =
             Lists.save_list_layout(
               list.id,
               user.id,
               layout.([%{character_id: c1.id}, %{character_id: c1.id}])
             )

    hidden = insert_character!(99)
    Repo.update_all(from(c in Character, where: c.id == ^hidden.id), set: [hidden_at: now()])

    assert {:error, :unknown_items} =
             Lists.save_list_layout(list.id, user.id, layout.([%{character_id: hidden.id}]))
  end

  test "removing a tier unassigns its characters", %{user: user, characters: [c1, c2 | _]} do
    list = character_list!(user, [c1, c2])
    {:ok, [s, a | _]} = Lists.list_tiers_for_list(list)

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        items: [%{character_id: c1.id, tier_id: s.id}, %{character_id: c2.id, tier_id: a.id}]
      })

    # Drop the S tier; items omit tier fields so they keep their saved placement.
    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [%{id: a.id, label: a.label, color: a.color, position: 1}],
        items: [%{character_id: c1.id}, %{character_id: c2.id}]
      })

    placements =
      Repo.all(
        from(li in ListCharacterItem,
          where: li.list_id == ^list.id,
          select: {li.character_id, li.tier_id}
        )
      )
      |> Map.new()

    assert placements == %{c1.id => nil, c2.id => a.id}
  end

  test "VN membership helpers ignore character lists", %{user: user, characters: [c1 | _]} do
    vn = insert_vn!(:vn)
    list = character_list!(user, [c1])

    assert {:error, :wrong_item_type} = Lists.add_vns_to_list(list.id, [vn.id], user.id)
    assert {:error, :wrong_item_type} = Lists.remove_vns_from_list(list.id, [vn.id], user.id)
    assert {:ok, lists} = Lists.list_my_lists_with_membership(user.id, vn.id)
    refute Enum.any?(lists, &(&1.id == list.id))
  end

  test "safe mode shows a character list only through allowed VNs", %{
    user: user,
    characters: [c1, c2 | _]
  } do
    safe_vn = insert_vn!(:vn)
    nukige = insert_vn!(:nukige)
    link!(c1, safe_vn)
    link!(c2, nukige)

    safe_list = character_list!(user, [c1])
    nukige_list = character_list!(user, [c2])

    visible_ids =
      List
      |> Lists.Query.filter_by_allowed_categories([:vn])
      |> select([l], l.id)
      |> Repo.all()

    assert safe_list.id in visible_ids
    refute nukige_list.id in visible_ids
  end

  test "batch_list_characters_for_lists returns leading characters per list", %{
    user: user,
    characters: [c1, c2, c3]
  } do
    list = character_list!(user, [c1, c2, c3])

    assert %{} = batch = Lists.batch_list_characters_for_lists([list.id], 2)
    assert Enum.map(batch[list.id], & &1.id) == [c1.id, c2.id]
  end

  defp character_list!(user, characters) do
    {:ok, list} =
      Lists.create_list_with_layout(
        user.id,
        %{name: "Characters #{System.unique_integer([:positive])}", item_type: "character"},
        %{display_mode: "tier", items: Enum.map(characters, &%{character_id: &1.id})}
      )

    list
  end

  defp insert_character!(n) do
    %Character{}
    |> Character.changeset(%{name: "List Character #{n} #{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp insert_vn!(category) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "Character list VN #{System.unique_integer([:positive])}",
      original_language: "en",
      title_category: category
    })
    |> Repo.insert!()
  end

  defp link!(character, vn) do
    %VNCharacter{}
    |> VNCharacter.changeset(%{character_id: character.id, visual_novel_id: vn.id, role: :main})
    |> Repo.insert!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
