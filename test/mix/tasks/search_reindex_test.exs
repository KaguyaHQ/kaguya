defmodule Mix.Tasks.Search.ReindexTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "invalid index names and unknown options fail before starting work" do
    for args <- [["--only", "unknown"], ["--unknown"], ["characters"]] do
      assert_raise Mix.Error, ~r/Usage:/, fn -> Mix.Tasks.Search.Reindex.run(args) end
    end
  end

  test "setup skips unconfigured search with a useful hint" do
    output = capture_io(fn -> Mix.Tasks.Search.Reindex.run(["--if-available"]) end)
    assert output =~ "Search skipped"
    assert output =~ "mise run search"
  end

  test "explicit reindex refuses disabled search instead of claiming success" do
    assert_raise Mix.Error, ~r/Search indexing needs/, fn -> Mix.Tasks.Search.Reindex.run([]) end
  end
end
