defmodule Kaguya.ActivitiesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Activities
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures

  @relaxed [
    allowed_categories: [:vn, :nukige, :adjacent],
    screenshot_prefs: %{show_nsfw: true, show_brutal: true}
  ]

  @base ~U[2026-01-01 00:00:00Z]

  setup do
    :ok = Sandbox.checkout(Repo)
    %{user: UserFixtures.insert_user!()}
  end

  # Bypass `record_activity/1` so we can fix `inserted_at` explicitly.
  # `record_activity` relies on Ecto autogen timestamps (second precision)
  # plus UUIDv7 ids, and within the same millisecond UUIDv7 ordering isn't
  # strictly monotonic — the cursor `(inserted_at desc, id desc)` then
  # interleaves rows non-deterministically and breaks consecutive runs.
  defp insert!(user, action, opts) do
    ts = Keyword.fetch!(opts, :at)

    Repo.insert!(%UserActivity{
      user_id: user.id,
      action: action,
      entity_type: Keyword.get(opts, :entity_type, "rating"),
      entity_id: Keyword.get(opts, :entity_id, Ecto.UUID.generate()),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: ts,
      updated_at: ts
    })
  end

  defp at(seconds), do: DateTime.add(@base, seconds, :second)

  describe "list_global_activities/4 — entry shape" do
    test "non-groupable rows yield singleton entries", %{user: user} do
      insert!(user, :rated, at: at(1))
      insert!(user, :rated, at: at(2))
      insert!(user, :rated, at: at(3))

      {:ok, %{entries: entries, has_next: has_next}} =
        Activities.list_global_activities(nil, nil, 10, @relaxed)

      assert length(entries) == 3
      assert Enum.all?(entries, &(&1.group_size == 1))
      assert has_next == false
    end

    test "consecutive liked_screenshot for same vn collapses to one entry", %{user: user} do
      meta = %{"vn_slug" => "steins-gate"}

      for i <- 1..4 do
        insert!(user, :liked_screenshot,
          at: at(i),
          entity_type: "screenshot",
          metadata: meta
        )
      end

      {:ok, %{entries: [entry], has_next: false}} =
        Activities.list_global_activities(nil, nil, 10, @relaxed)

      assert entry.group_size == 4
      assert length(entry.members) == 3
      assert entry.representative.action == :liked_screenshot
    end

    test "different vn_slug values do not group", %{user: user} do
      insert!(user, :liked_screenshot,
        at: at(1),
        entity_type: "screenshot",
        metadata: %{"vn_slug" => "a"}
      )

      insert!(user, :liked_screenshot,
        at: at(2),
        entity_type: "screenshot",
        metadata: %{"vn_slug" => "b"}
      )

      {:ok, %{entries: entries}} =
        Activities.list_global_activities(nil, nil, 10, @relaxed)

      assert length(entries) == 2
      assert Enum.all?(entries, &(&1.group_size == 1))
    end
  end

  describe "list_global_activities/4 — cursor pagination" do
    test "cursor anchored on last consumed raw row, second page resumes correctly",
         %{user: user} do
      for i <- 1..6, do: insert!(user, :rated, at: at(i))

      {:ok, page1} = Activities.list_global_activities(nil, nil, 3, @relaxed)
      assert length(page1.entries) == 3
      assert page1.has_next == true
      assert is_binary(page1.next_cursor)

      {:ok, page2} =
        Activities.list_global_activities(nil, page1.next_cursor, 3, @relaxed)

      assert length(page2.entries) == 3
      assert page2.has_next == false

      page1_ids = Enum.map(page1.entries, & &1.id)
      page2_ids = Enum.map(page2.entries, & &1.id)
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
      assert length(page1_ids ++ page2_ids) == 6
    end

    test "grouped page-1 entry advances cursor past every raw row in the group",
         %{user: user} do
      meta = %{"vn_slug" => "x"}
      # Older :rated rows first; the 5 :liked_screenshot rows are newest and
      # form the page-1 grouped entry. The next page must skip all 5 raw
      # rows, not just the representative.
      for i <- 1..2, do: insert!(user, :rated, at: at(i))

      for i <- 1..5,
          do:
            insert!(user, :liked_screenshot,
              at: at(10 + i),
              entity_type: "screenshot",
              metadata: meta
            )

      {:ok, page1} = Activities.list_global_activities(nil, nil, 1, @relaxed)
      [first] = page1.entries
      assert first.group_size == 5
      assert first.representative.action == :liked_screenshot
      assert page1.has_next == true

      {:ok, page2} =
        Activities.list_global_activities(nil, page1.next_cursor, 1, @relaxed)

      [second] = page2.entries

      assert second.representative.action == :rated,
             "page 2 must not contain a leftover liked_screenshot row from the group"
    end
  end

  describe "list_global_activities/4 — filter then group" do
    test "nsfw filter drops members before grouping; surviving rows form one entry",
         %{user: user} do
      # Both flag keys must be present on every row — a missing key would
      # become NULL in the SQL fragment and the WHERE would reject the row.
      meta_safe = %{
        "vn_slug" => "x",
        "screenshot_is_nsfw" => false,
        "screenshot_is_brutal" => false
      }

      meta_nsfw = %{
        "vn_slug" => "x",
        "screenshot_is_nsfw" => true,
        "screenshot_is_brutal" => false
      }

      for i <- 1..2,
          do:
            insert!(user, :liked_screenshot,
              at: at(i),
              entity_type: "screenshot",
              metadata: meta_nsfw
            )

      for i <- 1..3,
          do:
            insert!(user, :liked_screenshot,
              at: at(10 + i),
              entity_type: "screenshot",
              metadata: meta_safe
            )

      hide_nsfw = [
        allowed_categories: [:vn, :nukige, :adjacent],
        screenshot_prefs: %{show_nsfw: false, show_brutal: false}
      ]

      {:ok, %{entries: [entry]}} =
        Activities.list_global_activities(nil, nil, 10, hide_nsfw)

      # 2 nsfw rows excluded at SQL; the remaining 3 safe rows stay grouped.
      assert entry.group_size == 3

      total =
        from(a in UserActivity, where: a.action == :liked_screenshot)
        |> Repo.aggregate(:count, :id)

      assert total == 5
    end
  end
end
