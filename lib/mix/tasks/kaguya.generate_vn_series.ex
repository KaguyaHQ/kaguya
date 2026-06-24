defmodule Mix.Tasks.Kaguya.GenerateVnSeries do
  @moduledoc """
  Generates VN series from sequel/prequel relations.

  ## Usage

      mix kaguya.generate_vn_series           # Generate all series
      mix kaguya.generate_vn_series --dry-run # Preview without inserting

  ## Algorithm

  1. Load all official sequel relations from vn_relations
  2. Build undirected graph for finding connected components
  3. For each component with 2+ VNs:
     - Find root (VN with no incoming sequel, or earliest release)
     - Follow sequel chain to determine order
     - Create series named after root VN
     - Assign positions 1, 2, 3...
  """

  use Mix.Task

  alias Kaguya.VisualNovels.SeriesGenerator

  @shortdoc "Generate VN series from sequel/prequel relations"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry-run" in args

    if dry_run do
      IO.puts("=== DRY RUN PREVIEW ===\n")

      SeriesGenerator.preview()
      |> Enum.take(20)
      |> Enum.each(fn {root_title, ordered} ->
        IO.puts("Series: #{root_title} (#{length(ordered)} entries)")

        ordered
        |> Enum.with_index(1)
        |> Enum.each(fn {vn, pos} ->
          date = if vn.release_date, do: " (#{vn.release_date})", else: ""
          IO.puts("  #{pos}. #{vn.title}#{date}")
        end)

        IO.puts("")
      end)
    else
      IO.puts("Generating series...")
      {:ok, count} = SeriesGenerator.regenerate()
      IO.puts("\nDone. Created #{count} series.")
    end
  end
end
