defmodule Kaguya.Activities.GroupedFeedTest do
  use ExUnit.Case, async: true

  alias Kaguya.Activities.GroupedFeed

  defp activity(opts) do
    %{
      id: Keyword.get(opts, :id, Ecto.UUID.generate()),
      user_id: Keyword.fetch!(opts, :user_id),
      action: Keyword.fetch!(opts, :action),
      entity_type: Keyword.get(opts, :entity_type),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
    }
  end

  describe "group_entries/1 — singletons" do
    test "empty input returns empty list" do
      assert GroupedFeed.group_entries([]) == []
    end

    test "non-groupable actions never merge, even from same user" do
      a = activity(user_id: "u1", action: :rated, metadata: %{"vn_slug" => "x"})
      b = activity(user_id: "u1", action: :reviewed, metadata: %{"vn_slug" => "x"})
      c = activity(user_id: "u1", action: :liked_review, metadata: %{"vn_slug" => "x"})

      entries = GroupedFeed.group_entries([a, b, c])

      assert length(entries) == 3
      assert Enum.all?(entries, &(&1.group_size == 1))
    end

    test "groupable action with missing context falls back to singleton" do
      # status_changed without metadata.status — context is nil, can't group
      a = activity(user_id: "u1", action: :status_changed, metadata: %{})
      b = activity(user_id: "u1", action: :status_changed, metadata: %{})

      entries = GroupedFeed.group_entries([a, b])

      assert length(entries) == 2
      assert Enum.all?(entries, &(&1.group_size == 1))
    end
  end

  describe "group_entries/1 — grouping rules" do
    test "consecutive liked_screenshot from same user/vn merge" do
      meta = %{"vn_slug" => "steins-gate"}
      acts = for _ <- 1..5, do: activity(user_id: "u1", action: :liked_screenshot, metadata: meta)

      [entry] = GroupedFeed.group_entries(acts)

      assert entry.group_size == 5
      assert length(entry.members) == GroupedFeed.members_cap()
      assert entry.representative == hd(acts)
      assert entry.last_member == List.last(acts)
    end

    test "different vn_slug breaks the group" do
      a = activity(user_id: "u1", action: :liked_screenshot, metadata: %{"vn_slug" => "a"})
      b = activity(user_id: "u1", action: :liked_screenshot, metadata: %{"vn_slug" => "b"})

      entries = GroupedFeed.group_entries([a, b])

      assert length(entries) == 2
      assert Enum.all?(entries, &(&1.group_size == 1))
    end

    test "different user breaks the group" do
      a = activity(user_id: "u1", action: :liked_cover, metadata: %{"vn_slug" => "x"})
      b = activity(user_id: "u2", action: :liked_cover, metadata: %{"vn_slug" => "x"})

      assert [_, _] = GroupedFeed.group_entries([a, b])
    end

    test "different action breaks the group (cover vs screenshot)" do
      a = activity(user_id: "u1", action: :liked_screenshot, metadata: %{"vn_slug" => "x"})
      b = activity(user_id: "u1", action: :liked_cover, metadata: %{"vn_slug" => "x"})

      assert [_, _] = GroupedFeed.group_entries([a, b])
    end

    test "non-groupable row between groupable runs splits the run" do
      meta = %{"vn_slug" => "x"}
      a = activity(user_id: "u1", action: :liked_screenshot, metadata: meta)
      b = activity(user_id: "u1", action: :liked_screenshot, metadata: meta)
      c = activity(user_id: "u1", action: :rated)
      d = activity(user_id: "u1", action: :liked_screenshot, metadata: meta)

      [g1, single, g2] = GroupedFeed.group_entries([a, b, c, d])

      assert g1.group_size == 2
      assert single.group_size == 1
      assert single.representative.action == :rated
      assert g2.group_size == 1
    end

    test "status_changed groups by status string" do
      a = activity(user_id: "u1", action: :status_changed, metadata: %{"status" => "read"})
      b = activity(user_id: "u1", action: :status_changed, metadata: %{"status" => "read"})
      c = activity(user_id: "u1", action: :status_changed, metadata: %{"status" => "wishlisted"})

      [g_read, g_wish] = GroupedFeed.group_entries([a, b, c])

      assert g_read.group_size == 2
      assert g_wish.group_size == 1
    end

    test "followed groups by user only (no context)" do
      a = activity(user_id: "u1", action: :followed)
      b = activity(user_id: "u1", action: :followed)
      c = activity(user_id: "u1", action: :followed)

      [entry] = GroupedFeed.group_entries([a, b, c])
      assert entry.group_size == 3
    end
  end

  describe "group_entries/1 — caps" do
    test "members capped at members_cap; group_size keeps counting" do
      cap = GroupedFeed.members_cap()
      meta = %{"vn_slug" => "x"}

      acts =
        for _ <- 1..(cap + 4), do: activity(user_id: "u1", action: :liked_cover, metadata: meta)

      [entry] = GroupedFeed.group_entries(acts)

      assert length(entry.members) == cap
      assert entry.group_size == cap + 4
    end

    test "group_size hard-capped; overflow rolls into a fresh entry" do
      cap = GroupedFeed.group_size_cap()
      meta = %{"vn_slug" => "x"}

      acts =
        for _ <- 1..(cap + 3),
            do: activity(user_id: "u1", action: :liked_screenshot, metadata: meta)

      [first, second] = GroupedFeed.group_entries(acts)

      assert first.group_size == cap
      assert second.group_size == 3
    end
  end

  describe "group_entries/1 — last_member is the cursor anchor" do
    test "last_member tracks the deepest raw row of the entry" do
      meta = %{"vn_slug" => "x"}
      first = activity(user_id: "u1", action: :liked_cover, metadata: meta)
      mid = activity(user_id: "u1", action: :liked_cover, metadata: meta)
      last = activity(user_id: "u1", action: :liked_cover, metadata: meta)

      [entry] = GroupedFeed.group_entries([first, mid, last])

      assert entry.representative == first
      assert entry.last_member == last
    end
  end
end
