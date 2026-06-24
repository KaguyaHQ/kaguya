defmodule Kaguya.Lists.TierListsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListItem, ListTier}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    user = UserFixtures.insert_user!()
    vns = for n <- 1..4, do: insert_vn!("Tier List Test #{n}")

    %{user: user, vns: vns}
  end

  test "creating a tier list creates default S-D tiers", %{user: user, vns: [vn | _]} do
    assert {:ok, list} =
             Lists.create_list(%{
               user_id: user.id,
               name: "Tiered favorites",
               display_mode: "tier",
               vn_ids: [vn.id]
             })

    tiers = Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert list.display_mode == "tier"
    assert Enum.map(tiers, & &1.label) == ~w(S A B C D)
    assert Enum.map(tiers, & &1.position) == [1, 2, 3, 4, 5]
  end

  test "save_list_layout persists tiers, item placement, and fallback order", %{
    user: user,
    vns: [vn1, vn2, vn3 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1])
    s_id = UUIDv7.generate()
    a_id = UUIDv7.generate()

    assert {:ok, saved} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [
                 %{id: s_id, label: "S", color: "#ff5555", position: 1},
                 %{id: a_id, label: "A", color: "#55aaff", position: 2}
               ],
               items: [
                 %{visual_novel_id: vn2.id, tier_id: a_id, tier_position: 1},
                 %{visual_novel_id: vn1.id, tier_id: s_id, tier_position: 1},
                 %{visual_novel_id: vn3.id, tier_id: nil, tier_position: 1}
               ]
             })

    assert saved.display_mode == "tier"
    assert Repo.get!(List, list.id).vns_count == 3

    rows =
      Repo.all(
        from(li in ListItem,
          where: li.list_id == ^list.id,
          order_by: li.position,
          select: {li.visual_novel_id, li.position, li.tier_id, li.tier_position}
        )
      )

    assert rows == [
             {vn1.id, 1, s_id, 1},
             {vn2.id, 2, a_id, 1},
             {vn3.id, 3, nil, nil}
           ]
  end

  test "save_list_layout accepts temporary frontend tier ids", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1])

    assert {:ok, saved} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [
                 %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
                 %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
               ],
               items: [
                 %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
                 %{visual_novel_id: vn2.id, tier_id: "tier-a", tier_position: 1}
               ]
             })

    assert saved.display_mode == "tier"

    tiers = Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))
    assert Enum.map(tiers, & &1.label) == ["S", "A"]
    refute Enum.any?(tiers, &(&1.id in ["tier-s", "tier-a"]))

    [s_tier, a_tier] = tiers

    assert Repo.all(
             from(li in ListItem,
               where: li.list_id == ^list.id,
               order_by: li.position,
               select: {li.visual_novel_id, li.tier_id, li.tier_position}
             )
           ) == [{vn1.id, s_tier.id, 1}, {vn2.id, a_tier.id, 1}]
  end

  test "save_list_layout supports expanding a tier list up to eight rows", %{
    user: user,
    vns: [vn1, vn2, vn3, vn4 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1, vn2, vn3, vn4])

    tiers =
      [
        {"S", "#f87171"},
        {"A", "#fb923c"},
        {"B", "#facc15"},
        {"C", "#4ade80"},
        {"D", "#60a5fa"},
        {"E", "#a78bfa"},
        {"F", "#34d399"},
        {"G", "#f472b6"}
      ]
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, color}, position} ->
        %{id: UUIDv7.generate(), label: label, color: color, position: position}
      end)

    [s_tier, a_tier, b_tier, c_tier | _] = tiers

    assert {:ok, saved} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: tiers,
               items: [
                 %{visual_novel_id: vn1.id, tier_id: s_tier.id, tier_position: 1},
                 %{visual_novel_id: vn2.id, tier_id: a_tier.id, tier_position: 1},
                 %{visual_novel_id: vn3.id, tier_id: b_tier.id, tier_position: 1},
                 %{visual_novel_id: vn4.id, tier_id: c_tier.id, tier_position: 1}
               ]
             })

    assert saved.display_mode == "tier"

    persisted = Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert Enum.map(persisted, & &1.label) == ~w(S A B C D E F G)
    assert Enum.map(persisted, & &1.position) == Enum.to_list(1..8)
  end

  test "adding a tier to existing rows commits final positions without offset leakage", %{
    user: user,
    vns: [vn1 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [
          %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
          %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
        ],
        items: [%{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1}]
      })

    [s_tier, a_tier] =
      Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [
                 %{id: s_tier.id, label: "S", color: "#ff5555", position: 1},
                 %{id: a_tier.id, label: "A", color: "#55aaff", position: 2},
                 %{id: "tier-new", label: "New bottom", color: "#f472b6", position: 3}
               ],
               items: [%{visual_novel_id: vn1.id, tier_id: s_tier.id, tier_position: 1}]
             })

    assert Repo.all(
             from(t in ListTier,
               where: t.list_id == ^list.id,
               order_by: t.position,
               select: {t.label, t.position}
             )
           ) == [{"S", 1}, {"A", 2}, {"New bottom", 3}]
  end

  test "swapping existing tier positions is handled by deferred uniqueness", %{
    user: user,
    vns: [vn1 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [
          %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
          %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
        ],
        items: [%{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1}]
      })

    [s_tier, a_tier] =
      Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [
                 %{id: a_tier.id, label: "A", color: "#55aaff", position: 1},
                 %{id: s_tier.id, label: "S", color: "#ff5555", position: 2}
               ],
               items: [%{visual_novel_id: vn1.id, tier_id: s_tier.id, tier_position: 1}]
             })

    assert Repo.all(
             from(t in ListTier,
               where: t.list_id == ^list.id,
               order_by: t.position,
               select: {t.label, t.position}
             )
           ) == [{"A", 1}, {"S", 2}]

    assert Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn1.id).tier_id == s_tier.id
  end

  test "removing a saved tier unassigns its items instead of losing them", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1, vn2])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [
          %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
          %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
        ],
        items: [
          %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
          %{visual_novel_id: vn2.id, tier_id: "tier-a", tier_position: 1}
        ]
      })

    [s_tier, _a_tier] =
      Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [%{id: s_tier.id, label: "S", color: "#ff5555", position: 1}],
               items: [
                 %{visual_novel_id: vn1.id, tier_id: s_tier.id, tier_position: 1},
                 %{visual_novel_id: vn2.id, position: 2}
               ]
             })

    [remaining_tier] =
      Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

    assert Repo.all(
             from(li in ListItem,
               where: li.list_id == ^list.id,
               order_by: li.position,
               select: {li.visual_novel_id, li.tier_id, li.tier_position}
             )
           ) == [{vn1.id, remaining_tier.id, 1}, {vn2.id, nil, nil}]
  end

  test "duplicate VN placements fail without partially rewriting the list", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1, vn2])

    assert {:error, :duplicate_visual_novel} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [%{label: "S", color: "#ff5555", position: 1}],
               items: [
                 %{visual_novel_id: vn1.id, tier_position: 1},
                 %{visual_novel_id: vn1.id, tier_position: 2}
               ]
             })

    assert Repo.get!(List, list.id).display_mode == "grid"
    assert Repo.aggregate(from(t in ListTier, where: t.list_id == ^list.id), :count, :id) == 0

    assert Repo.aggregate(
             from(li in ListItem, where: li.list_id == ^list.id),
             :count,
             :visual_novel_id
           ) == 2
  end

  test "items cannot reference a tier owned by another list", %{user: user, vns: [vn1, vn2 | _]} do
    {:ok, list} = create_grid_list!(user, [vn1])
    {:ok, other} = create_grid_list!(user, [vn2], "Other list")

    foreign_tier =
      Repo.insert!(%ListTier{list_id: other.id, label: "S", color: "#ff5555", position: 1})

    assert {:error, :tier_not_found} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               tiers: [%{id: UUIDv7.generate(), label: "S", color: "#ff5555", position: 1}],
               items: [%{visual_novel_id: vn1.id, tier_id: foreign_tier.id, tier_position: 1}]
             })
  end

  test "omitting tiers preserves existing custom tiers", %{user: user, vns: [vn1, vn2 | _]} do
    {:ok, list} = create_grid_list!(user, [vn1])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [%{id: "tier-masterpiece", label: "Masterpiece", color: "#ff5555", position: 1}],
        items: [%{visual_novel_id: vn1.id, tier_id: "tier-masterpiece", tier_position: 1}]
      })

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               items: [
                 %{visual_novel_id: vn1.id, position: 1},
                 %{visual_novel_id: vn2.id, position: 2}
               ]
             })

    assert [%ListTier{label: "Masterpiece"}] =
             Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))
  end

  test "grid to tier restores previous placements when tier fields are omitted", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1, vn2])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [%{id: "tier-s", label: "S", color: "#ff5555", position: 1}],
        items: [
          %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
          %{visual_novel_id: vn2.id, tier_id: nil, tier_position: 1}
        ]
      })

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "grid",
        items: [
          %{visual_novel_id: vn2.id, position: 1},
          %{visual_novel_id: vn1.id, position: 2}
        ]
      })

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               items: [
                 %{visual_novel_id: vn2.id, position: 1},
                 %{visual_novel_id: vn1.id, position: 2}
               ]
             })

    tier = Repo.one!(from(t in ListTier, where: t.list_id == ^list.id and t.label == "S"))

    assert Repo.all(
             from(li in ListItem,
               where: li.list_id == ^list.id,
               order_by: li.position,
               select: {li.visual_novel_id, li.position, li.tier_id, li.tier_position}
             )
           ) == [{vn1.id, 1, tier.id, 1}, {vn2.id, 2, nil, nil}]
  end

  test "grid to tier keeps reordered unranked items in submitted flat order", %{
    user: user,
    vns: [vn1, vn2, vn3 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1, vn2, vn3])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [%{id: "tier-s", label: "S", color: "#ff5555", position: 1}],
        items: [
          %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
          %{visual_novel_id: vn2.id, tier_id: nil, tier_position: 1},
          %{visual_novel_id: vn3.id, tier_id: nil, tier_position: 2}
        ]
      })

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "grid",
        items: [
          %{visual_novel_id: vn3.id, position: 1},
          %{visual_novel_id: vn2.id, position: 2},
          %{visual_novel_id: vn1.id, position: 3}
        ]
      })

    assert {:ok, _} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "tier",
               items: [
                 %{visual_novel_id: vn3.id, position: 1},
                 %{visual_novel_id: vn2.id, position: 2},
                 %{visual_novel_id: vn1.id, position: 3}
               ]
             })

    tier = Repo.one!(from(t in ListTier, where: t.list_id == ^list.id and t.label == "S"))

    assert Repo.all(
             from(li in ListItem,
               where: li.list_id == ^list.id,
               order_by: li.position,
               select: {li.visual_novel_id, li.position, li.tier_id, li.tier_position}
             )
           ) == [
             {vn1.id, 1, tier.id, 1},
             {vn3.id, 2, nil, nil},
             {vn2.id, 3, nil, nil}
           ]
  end

  test "grid saves respect explicit flat order while preserving tier placements", %{
    user: user,
    vns: [vn1, vn2, vn3 | _]
  } do
    {:ok, list} = create_grid_list!(user, [vn1])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [
          %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
          %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
        ],
        items: [
          %{visual_novel_id: vn2.id, tier_id: "tier-a", tier_position: 1},
          %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
          %{visual_novel_id: vn3.id, tier_id: nil, tier_position: 1}
        ]
      })

    assert {:ok, saved} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "grid",
               items: [
                 %{visual_novel_id: vn2.id, position: 1},
                 %{visual_novel_id: vn1.id, position: 2},
                 %{visual_novel_id: vn3.id, position: 3}
               ]
             })

    assert saved.display_mode == "grid"

    assert Repo.all(
             from(li in ListItem,
               where: li.list_id == ^list.id,
               order_by: li.position,
               select: li.visual_novel_id
             )
           ) == [vn2.id, vn1.id, vn3.id]
  end

  test "invalid positions are rejected before writing", %{user: user, vns: [vn1 | _]} do
    {:ok, list} = create_grid_list!(user, [vn1])

    assert {:error, :invalid_position} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "grid",
               items: [%{visual_novel_id: vn1.id, tier_position: 0}]
             })
  end

  test "save_list_layout accepts empty items to clear a list", %{user: user, vns: [vn1, vn2 | _]} do
    {:ok, list} = create_grid_list!(user, [vn1, vn2])

    assert {:ok, saved} =
             Lists.save_list_layout(list.id, user.id, %{
               display_mode: "grid",
               items: []
             })

    assert saved.vns_count == 0
    assert Repo.aggregate(from(li in ListItem, where: li.list_id == ^list.id), :count) == 0
  end

  test "legacy reorder preserves tier placement metadata", %{user: user, vns: [vn1, vn2 | _]} do
    {:ok, list} = create_grid_list!(user, [vn1, vn2])

    {:ok, _} =
      Lists.save_list_layout(list.id, user.id, %{
        display_mode: "tier",
        tiers: [%{id: "tier-s", label: "S", color: "#ff5555", position: 1}],
        items: [
          %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
          %{visual_novel_id: vn2.id, tier_id: nil, tier_position: 1}
        ]
      })

    assert {:ok, true} = Lists.set_list_vns(list.id, [vn2.id, vn1.id], user.id)

    tier = Repo.one!(from(t in ListTier, where: t.list_id == ^list.id and t.label == "S"))

    assert Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn1.id).tier_id == tier.id
    assert Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn1.id).tier_position == 1
  end

  defp create_grid_list!(user, vns, name \\ "Grid list") do
    Lists.create_list(%{
      user_id: user.id,
      name: "#{name} #{System.unique_integer([:positive])}",
      display_mode: "grid",
      vn_ids: Enum.map(vns, & &1.id)
    })
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end
