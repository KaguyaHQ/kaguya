defmodule Kaguya.Lists.PlacementTest do
  use ExUnit.Case, async: true

  alias Kaguya.Lists.Placement

  @s %{id: "s", position: 1}
  @a %{id: "a", position: 2}
  @tiers %{tiers: [@s, @a], id_map: %{"s" => "s", "a" => "a"}}

  describe "validate_items/1" do
    test "returns ids in submitted order" do
      assert {:ok, ["x", "y"]} = Placement.validate_items([%{item_id: "x"}, %{item_id: "y"}])
    end

    test "rejects duplicates, missing ids, and non-positive positions" do
      assert {:error, :duplicate_item} =
               Placement.validate_items([%{item_id: "x"}, %{item_id: "x"}])

      assert {:error, :missing_item_id} = Placement.validate_items([%{position: 1}])

      assert {:error, :invalid_position} =
               Placement.validate_items([%{item_id: "x", tier_position: 0}])

      assert {:error, :invalid_list_items} = Placement.validate_items(%{})
    end
  end

  describe "arrange/4 in tier mode" do
    test "orders by tier, then tier position, and puts unplaced items last" do
      items = [
        %{item_id: "free", tier_id: nil},
        %{item_id: "a1", tier_id: "a", tier_position: 1},
        %{item_id: "s2", tier_id: "s", tier_position: 2},
        %{item_id: "s1", tier_id: "s", tier_position: 1}
      ]

      assert {:ok, arranged} = Placement.arrange("tier", items, %{}, @tiers)

      assert Enum.map(arranged, &{&1.item_id, &1.position, &1.tier_id, &1.tier_position}) == [
               {"s1", 1, "s", 1},
               {"s2", 2, "s", 2},
               {"a1", 3, "a", 1},
               {"free", 4, nil, nil}
             ]
    end

    test "renumbers sparse tier positions from 1" do
      items = [
        %{item_id: "x", tier_id: "s", tier_position: 5},
        %{item_id: "y", tier_id: "s", tier_position: 9}
      ]

      assert {:ok, arranged} = Placement.arrange("tier", items, %{}, @tiers)
      assert Enum.map(arranged, & &1.tier_position) == [1, 2]
    end

    test "resolves temporary tier ids through the id map" do
      tiers = %{@tiers | id_map: Map.put(@tiers.id_map, "tier-temp", "a")}

      assert {:ok, [%{tier_id: "a"}]} =
               Placement.arrange("tier", [%{item_id: "x", tier_id: "tier-temp"}], %{}, tiers)
    end

    test "falls back to saved placement when tier fields are omitted" do
      previous = %{"x" => %{tier_id: "a", tier_position: 1}}

      assert {:ok, [%{tier_id: "a", tier_position: 1}]} =
               Placement.arrange("tier", [%{item_id: "x"}], previous, @tiers)
    end

    test "an explicit nil tier wins over the saved placement" do
      previous = %{"x" => %{tier_id: "a", tier_position: 1}}

      assert {:ok, [%{tier_id: nil, tier_position: nil}]} =
               Placement.arrange("tier", [%{item_id: "x", tier_id: nil}], previous, @tiers)
    end

    test "rejects unknown tiers and duplicate positions within a tier" do
      assert {:error, :tier_not_found} =
               Placement.arrange("tier", [%{item_id: "x", tier_id: "zzz"}], %{}, @tiers)

      assert {:error, :duplicate_tier_position} =
               Placement.arrange(
                 "tier",
                 [
                   %{item_id: "x", tier_id: "s", tier_position: 1},
                   %{item_id: "y", tier_id: "s", tier_position: 1}
                 ],
                 %{},
                 @tiers
               )
    end
  end

  describe "arrange/4 in grid mode" do
    test "keeps flat order and leaves tier placement untouched" do
      items = [
        %{item_id: "x", position: 2, tier_id: "a", tier_position: 4},
        %{item_id: "y", position: 1}
      ]

      assert {:ok, arranged} = Placement.arrange("grid", items, %{}, @tiers)

      assert Enum.map(arranged, &{&1.item_id, &1.position, &1.tier_id, &1.tier_position}) == [
               {"y", 1, nil, nil},
               {"x", 2, "a", 4}
             ]
    end
  end

  test "reorder/2 numbers ids in order and keeps saved placement" do
    previous = %{"x" => %{tier_id: "s", tier_position: 1}}

    assert Placement.reorder(["y", nil, "x"], previous) == [
             %{item_id: "y", position: 1, tier_id: nil, tier_position: nil},
             %{item_id: "x", position: 2, tier_id: "s", tier_position: 1}
           ]
  end
end
