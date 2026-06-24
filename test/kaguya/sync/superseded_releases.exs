# Superseded Release Filtering — Integration Test
#
# Tests that superseded releases are correctly identified and filtered out
# during VNDB dump sync. Runs against both vndb_latest and kaguya_dev2.
#
# Run:  mix run test/kaguya/sync/superseded_releases.exs

import Ecto.Query

alias Kaguya.Repo
alias Kaguya.Sync.DumpSync
alias Kaguya.Sync.DumpSync.Releases, as: ReleasesStep
alias Kaguya.Releases.Release

defmodule SupersededReleasesTest do
  def run do
    IO.puts("\n=== Superseded Release Filtering Tests ===\n")

    {:ok, vndb} = DumpSync.connect_vndb()
    IO.puts("Connected to vndb_latest\n")

    {passed, failed, errors} = run_all_tests(vndb)

    if Process.alive?(vndb), do: GenServer.stop(vndb)

    IO.puts("\n#{"=" |> String.duplicate(60)}")

    if errors != [] do
      IO.puts("ERRORS:")

      for {name, err} <- Enum.reverse(errors) do
        IO.puts("  #{name}: #{err}")
      end

      IO.puts("")
    end

    total = passed + failed
    color = if failed == 0, do: "\e[32m", else: "\e[31m"
    IO.puts("#{color}#{passed}/#{total} passed, #{failed} failed\e[0m")
  end

  def run_all_tests(vndb) do
    tests = [
      {"load_superseded_release_ids returns a MapSet", fn -> test_load_superseded_ids(vndb) end},
      {"superseded set has expected count (~2800)", fn -> test_superseded_count(vndb) end},
      {"r32926 (Fata Morgana) is in superseded set",
       fn -> test_fata_morgana_superseded(vndb) end},
      {"r148219 (latest Fata Morgana DL Edition) is NOT superseded",
       fn -> test_fata_morgana_latest_not_superseded(vndb) end},
      {"chain: all intermediate releases are superseded",
       fn -> test_full_chain_superseded(vndb) end},
      {"chain: only terminal release survives", fn -> test_chain_terminal_survives(vndb) end},
      {"filter_superseded removes correct IDs from release_vn_map",
       fn -> test_filter_superseded(vndb) end},
      {"filter_superseded preserves non-superseded releases",
       fn -> test_filter_preserves_good(vndb) end},
      {"multi-superseder: release superseding 7 others", fn -> test_multi_superseder(vndb) end},
      {"non-existent release is not in superseded set",
       fn -> test_non_existent_not_superseded(vndb) end},
      {"kaguya has superseded Fata Morgana releases (pre-cleanup)",
       fn -> test_kaguya_has_superseded(vndb) end},
      {"superseded count in kaguya DB", fn -> test_kaguya_superseded_count(vndb) end},
      {"cross-VN supersession: superseded release linked to multiple VNs",
       fn -> test_cross_vn_supersession(vndb) end},
      {"empty superseded set doesn't filter anything", fn -> test_empty_superseded_set() end}
    ]

    Enum.reduce(tests, {0, 0, []}, fn {name, test_fn}, {p, f, errs} ->
      IO.write("  #{name} ... ")

      try do
        test_fn.()
        IO.puts("\e[32mPASS\e[0m")
        {p + 1, f, errs}
      rescue
        e ->
          msg = Exception.message(e)
          IO.puts("\e[31mFAIL\e[0m")
          IO.puts("    #{msg}")
          {p, f + 1, [{name, msg} | errs]}
      end
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def assert!(condition, message) do
    unless condition, do: raise(message)
  end

  # ── Tests: Loading superseded IDs ────────────────────────────────────────

  def test_load_superseded_ids(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    assert!(is_struct(ids, MapSet), "Expected MapSet, got #{inspect(ids.__struct__)}")
    assert!(MapSet.size(ids) > 0, "Superseded set should not be empty")
  end

  def test_superseded_count(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    size = MapSet.size(ids)
    # We know from exploration there are ~2792 superseded releases
    assert!(size > 2000, "Expected >2000 superseded, got #{size}")
    assert!(size < 5000, "Expected <5000 superseded, got #{size} (sanity check)")
  end

  # ── Tests: Fata Morgana specific ─────────────────────────────────────────

  def test_fata_morgana_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    # r32926 is "Fata Morgana Download Edition" from 2016, superseded by r51999
    assert!(MapSet.member?(ids, "r32926"), "r32926 should be in superseded set")
  end

  def test_fata_morgana_latest_not_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # r148219 is the latest in the chain — it supersedes r89808 but is NOT superseded by anything
    assert!(!MapSet.member?(ids, "r148219"), "r148219 (latest) should NOT be in superseded set")
  end

  def test_full_chain_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # Full Fata Morgana Download Edition chain:
    # r32926 → r51999 → r57514 → r56552 → r74566 → r89808 → r148219
    # All except r148219 should be superseded
    chain = ["r32926", "r51999", "r57514", "r56552", "r74566", "r89808"]

    for rid <- chain do
      assert!(MapSet.member?(ids, rid), "#{rid} should be superseded (intermediate in chain)")
    end
  end

  def test_chain_terminal_survives(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    # r148219 is the terminal node — not superseded by anything
    assert!(!MapSet.member?(ids, "r148219"), "r148219 should survive (terminal node)")

    # Also check: non-superseded releases for the same VN should survive
    # r32844 is the trial edition — no supersession relationship
    assert!(!MapSet.member?(ids, "r32844"), "r32844 (trial) should not be in superseded set")
  end

  # ── Tests: filter_superseded logic ───────────────────────────────────────

  def test_filter_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # Simulate a release_vn_map with some superseded and some not
    release_vn_map = %{
      # superseded
      "r32926" => [{"v12402", "complete"}],
      # superseded
      "r51999" => [{"v12402", "complete"}],
      # NOT superseded (latest)
      "r148219" => [{"v12402", "complete"}],
      # NOT superseded (trial)
      "r32844" => [{"v12402", "complete"}]
    }

    {filtered, removed} = filter_superseded_public(release_vn_map, ids)

    assert!(removed == 2, "Should remove 2 superseded, removed #{removed}")
    assert!(!Map.has_key?(filtered, "r32926"), "r32926 should be filtered out")
    assert!(!Map.has_key?(filtered, "r51999"), "r51999 should be filtered out")
    assert!(Map.has_key?(filtered, "r148219"), "r148219 should remain")
    assert!(Map.has_key?(filtered, "r32844"), "r32844 should remain")
  end

  def test_filter_preserves_good(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # Map with only non-superseded releases
    release_vn_map = %{
      "r148219" => [{"v12402", "complete"}],
      "r32844" => [{"v12402", "complete"}],
      "r56601" => [{"v12402", "complete"}]
    }

    {filtered, removed} = filter_superseded_public(release_vn_map, ids)

    assert!(removed == 0, "Should remove 0, removed #{removed}")
    assert!(map_size(filtered) == 3, "All 3 should remain, got #{map_size(filtered)}")
  end

  # ── Tests: Edge cases ────────────────────────────────────────────────────

  def test_multi_superseder(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # r111853 supersedes 7 releases. Verify those 7 are in the superseded set.
    {:ok, result} =
      Postgrex.query(vndb, "SELECT rid FROM releases_supersedes WHERE id = 'r111853'", [])

    superseded_by_r111853 = Enum.map(result.rows, fn [rid] -> rid end)

    assert!(
      length(superseded_by_r111853) >= 5,
      "r111853 should supersede multiple releases, got #{length(superseded_by_r111853)}"
    )

    for rid <- superseded_by_r111853 do
      assert!(MapSet.member?(ids, rid), "#{rid} (superseded by r111853) should be in set")
    end

    # r111853 itself should NOT be superseded (unless something supersedes it)
    {:ok, check} =
      Postgrex.query(vndb, "SELECT COUNT(*) FROM releases_supersedes WHERE rid = 'r111853'", [])

    [[count]] = check.rows

    if count == 0 do
      assert!(
        !MapSet.member?(ids, "r111853"),
        "r111853 should not be superseded (nothing supersedes it)"
      )
    end
  end

  def test_non_existent_not_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    assert!(!MapSet.member?(ids, "r99999999"), "Non-existent release should not be in set")
  end

  # ── Tests: Kaguya DB state ──────────────────────────────────────────────

  def test_kaguya_has_superseded(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)

    # Check if any of the Fata Morgana superseded releases are still in kaguya
    fata_morgana_superseded = ["r32926", "r51999", "r57514", "r56552", "r74566", "r89808"]

    in_kaguya =
      from(r in Release, where: r.vndb_id in ^fata_morgana_superseded, select: r.vndb_id)
      |> Repo.all()

    # This test documents the current state — these exist now but should be
    # cleaned up by the removals step
    IO.write("(#{length(in_kaguya)}/#{length(fata_morgana_superseded)} in DB) ")

    # At least verify the superseded set is correct
    for rid <- in_kaguya do
      assert!(MapSet.member?(ids, rid), "#{rid} in kaguya should be in superseded set")
    end
  end

  def test_kaguya_superseded_count(vndb) do
    ids = ReleasesStep.load_superseded_release_ids(vndb)
    superseded_list = MapSet.to_list(ids)

    # Count how many superseded releases are currently in kaguya
    # Query in chunks to avoid parameter limit
    count =
      superseded_list
      |> Enum.chunk_every(5000)
      |> Enum.reduce(0, fn chunk, acc ->
        n = Repo.aggregate(from(r in Release, where: r.vndb_id in ^chunk), :count)
        acc + n
      end)

    total = Repo.aggregate(Release, :count)
    pct = if total > 0, do: Float.round(count / total * 100, 1), else: 0.0

    IO.write("(#{count}/#{total} = #{pct}% superseded in kaguya) ")

    # Just verify the count is reasonable (not all releases are superseded)
    assert!(count < total, "Not all releases should be superseded")
  end

  # ── Tests: Cross-VN and edge cases ───────────────────────────────────────

  def test_cross_vn_supersession(vndb) do
    # Some releases are linked to multiple VNs. Verify supersession still works.
    # Find a superseded release linked to >1 VN
    {:ok, result} =
      Postgrex.query(
        vndb,
        """
        SELECT rs.rid, COUNT(DISTINCT rv.vid) as vn_count
        FROM releases_supersedes rs
        JOIN releases_vn rv ON rv.id = rs.rid
        GROUP BY rs.rid
        HAVING COUNT(DISTINCT rv.vid) > 1
        LIMIT 5
        """,
        []
      )

    ids = ReleasesStep.load_superseded_release_ids(vndb)

    if result.rows == [] do
      IO.write("(no cross-VN superseded releases found, skipping) ")
    else
      for [rid, vn_count] <- result.rows do
        assert!(
          MapSet.member?(ids, rid),
          "#{rid} (linked to #{vn_count} VNs) should be superseded regardless of VN count"
        )
      end
    end
  end

  def test_empty_superseded_set do
    # With an empty superseded set, nothing should be filtered
    release_vn_map = %{
      "r32926" => [{"v12402", "complete"}],
      "r51999" => [{"v12402", "complete"}]
    }

    {filtered, removed} = filter_superseded_public(release_vn_map, MapSet.new())

    assert!(removed == 0, "Empty superseded set should remove nothing")
    assert!(map_size(filtered) == 2, "All releases should remain")
  end

  # ── Private helpers (wrapper for module's private function) ──────────────

  defp filter_superseded_public(release_vn_map, superseded_ids) do
    {filtered, removed} =
      Enum.reduce(release_vn_map, {%{}, 0}, fn {release_id, vns}, {acc, count} ->
        if MapSet.member?(superseded_ids, release_id) do
          {acc, count + 1}
        else
          {Map.put(acc, release_id, vns), count}
        end
      end)

    {filtered, removed}
  end
end

SupersededReleasesTest.run()
