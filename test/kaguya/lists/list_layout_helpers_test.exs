defmodule Kaguya.Lists.ListLayoutHelpersTest do
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
    vns = for n <- 1..3, do: insert_vn!("List helper VN #{n}")

    %{user: user, vns: vns}
  end

  test "create_list_with_layout creates list and layout atomically", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    assert {:ok, list} =
             Lists.create_list_with_layout(
               user.id,
               %{name: "LiveView tiers", display_mode: "tier", is_public: true},
               %{
                 display_mode: "tier",
                 tiers: [
                   %{id: "tier-s", label: "S", color: "#f87171", position: 1},
                   %{id: "tier-a", label: "A", color: "#fb923c", position: 2}
                 ],
                 items: [
                   %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
                   %{visual_novel_id: vn2.id, tier_id: "tier-a", tier_position: 1}
                 ]
               }
             )

    assert list.name == "LiveView tiers"
    assert list.display_mode == "tier"
    assert Repo.get!(List, list.id).vns_count == 2

    tiers = Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))
    assert Enum.map(tiers, & &1.label) == ["S", "A"]

    assert Repo.aggregate(from(li in ListItem, where: li.list_id == ^list.id), :count) == 2
  end

  test "create_list_with_layout rolls back when layout is invalid", %{
    user: user,
    vns: [vn | _]
  } do
    assert {:error, :duplicate_visual_novel} =
             Lists.create_list_with_layout(
               user.id,
               %{name: "Rollback list", display_mode: "tier", is_public: true},
               %{
                 display_mode: "tier",
                 tiers: [%{id: "tier-s", label: "S", color: "#f87171", position: 1}],
                 items: [
                   %{visual_novel_id: vn.id, tier_id: "tier-s", tier_position: 1},
                   %{visual_novel_id: vn.id, tier_id: "tier-s", tier_position: 2}
                 ]
               }
             )

    refute Repo.get_by(List, user_id: user.id, name: "Rollback list")
  end

  test "update_list_with_layout rolls back metadata when layout is invalid", %{
    user: user,
    vns: [vn1, vn2 | _]
  } do
    {:ok, list} = Lists.create_list(%{user_id: user.id, name: "Original list", vn_ids: [vn1.id]})

    assert {:error, :duplicate_tier_position} =
             Lists.update_list_with_layout(
               list.id,
               user.id,
               %{name: "Updated name", display_mode: "tier"},
               %{
                 display_mode: "tier",
                 tiers: [%{id: "tier-s", label: "S", color: "#f87171", position: 1}],
                 items: [
                   %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
                   %{visual_novel_id: vn2.id, tier_id: "tier-s", tier_position: 1}
                 ]
               }
             )

    assert Repo.get!(List, list.id).name == "Original list"
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end
