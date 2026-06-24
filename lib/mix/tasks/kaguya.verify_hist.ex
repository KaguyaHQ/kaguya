defmodule Mix.Tasks.Kaguya.VerifyHist do
  @moduledoc """
  Verifies that _hist table columns match their live table counterparts.
  Run before deploy to catch forgotten _hist migrations.

  Usage:
    mix kaguya.verify_hist
  """
  use Mix.Task

  @shortdoc "Verify _hist tables match live tables"

  @tables [
    {"vn_hist", "visual_novels"},
    {"vn_titles_hist", "vn_titles"},
    {"vn_relations_hist", "vn_relations"},
    {"vn_screenshots_hist", "vn_screenshots"},
    {"vn_covers_hist", "vn_images"},
    {"characters_hist", "characters"},
    {"vn_characters_hist", "vn_characters"},
    {"producers_hist", "producers"},
    {"producer_external_links_hist", "producer_external_links"},
    {"releases_hist", "vn_releases"},
    {"release_extlinks_hist", "vn_release_extlinks"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    errors =
      Enum.flat_map(@tables, fn {hist, live} ->
        verify_table(hist, live)
      end)

    if errors == [] do
      IO.puts("All _hist tables match their live tables. ✓")
    else
      IO.puts("\n_hist table mismatches found:\n")
      Enum.each(errors, &IO.puts("  ✗ #{&1}"))
      IO.puts("\nFix these before deploying.")
      System.halt(1)
    end
  end

  # Per-table columns to skip: change_id (always), plus entity reference columns
  @skip_columns %{
    "vn_screenshots_hist" => ["change_id", "screenshot_id"],
    "vn_covers_hist" => ["change_id", "cover_id"]
  }

  defp verify_table(hist, live) do
    skip = Map.get(@skip_columns, hist, ["change_id"])
    hist_cols = get_columns(hist) |> Map.drop(skip)
    live_cols = get_columns(live)

    # Check that every _hist column exists in live with matching type
    type_mismatches =
      Enum.flat_map(hist_cols, fn {col, hist_type} ->
        case Map.get(live_cols, col) do
          nil -> ["#{hist}.#{col} exists in _hist but not in #{live}"]
          ^hist_type -> []
          live_type -> ["#{hist}.#{col} type mismatch: _hist=#{hist_type} live=#{live_type}"]
        end
      end)

    type_mismatches
  end

  defp get_columns(table) do
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        Kaguya.Repo,
        "SELECT column_name, udt_name FROM information_schema.columns WHERE table_name = $1",
        [table]
      )

    Map.new(result.rows, fn [name, type] -> {name, type} end)
  end
end
