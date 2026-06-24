defmodule Mix.Tasks.Kaguya.DeleteVns do
  @moduledoc """
  CLI for bulk-deleting VNs. Resolves input IDs, shows a dry-run summary,
  then delegates to `Kaguya.VisualNovels.Deletion` for the actual work.

  ## Usage

      mix kaguya.delete_vns --vndb-ids v12345,v67890    # dry run
      mix kaguya.delete_vns --ids <uuid1>,<uuid2>       # by Kaguya UUIDs
      mix kaguya.delete_vns --csv /path/to/file.csv     # CSV: Title, Kaguya link, VNDB link, Notes
      mix kaguya.delete_vns --vndb-ids v12345 --reason "duplicate"
      mix kaguya.delete_vns --vndb-ids v12345 --execute  # actually delete

  ## Options

    * `--vndb-ids` - Comma-separated VNDB IDs (e.g. v12345,v67890)
    * `--ids` - Comma-separated Kaguya UUIDs
    * `--csv` - Path to CSV with columns: Title, Kaguya link, VNDB link, Notes
    * `--reason` - Reason for blocklist (default: "not a visual novel"); CSV Notes column overrides per-VN
    * `--execute` - Actually perform the deletion (without this, dry run only)
  """

  use Mix.Task

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.Deletion
  alias Kaguya.VisualNovels.VisualNovel

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          vndb_ids: :string,
          ids: :string,
          csv: :string,
          reason: :string,
          execute: :boolean
        ],
        aliases: []
      )

    execute? = Keyword.get(opts, :execute, false)

    default_reason = Keyword.get(opts, :reason, "not a visual novel")

    {vn_ids, vn_reasons} = resolve_vn_ids(opts, default_reason)

    if vn_ids == [] do
      Mix.shell().info("No VNs found. Nothing to do.")
      System.halt(0)
    end

    # Phase 2: Pre-gather all affected data before cascade destroys child rows
    data = Deletion.gather_affected_data(vn_ids)

    # Phase 3: Print summary
    print_summary(data, vn_reasons, execute?)

    if execute? do
      # Phase 4: Execute via shared module (pass pre-gathered data to avoid re-querying)
      Mix.shell().info("\nExecuting deletion...")

      case Deletion.delete_vns(vn_ids, reasons: vn_reasons, data: data) do
        {:ok, _result} ->
          Mix.shell().info("\nDeletion complete.")

        {:error, reason} ->
          Mix.shell().error("Deletion failed: #{inspect(reason)}")
          System.halt(1)
      end
    else
      Mix.shell().info("\nDry run complete. Pass --execute to actually delete.")
    end
  end

  # ──────────────────────────
  # Phase 1: Resolve & Validate
  # ──────────────────────────

  defp resolve_vn_ids(opts, default_reason) do
    cond do
      csv_path = Keyword.get(opts, :csv) ->
        resolve_csv(csv_path, default_reason)

      vndb_ids_str = Keyword.get(opts, :vndb_ids) ->
        vndb_ids = String.split(vndb_ids_str, ",", trim: true)
        vn_ids = resolve_vndb_ids(vndb_ids)
        {vn_ids, Map.new(vn_ids, &{&1, default_reason})}

      ids_str = Keyword.get(opts, :ids) ->
        ids = String.split(ids_str, ",", trim: true)
        vn_ids = verify_ids(ids)
        {vn_ids, Map.new(vn_ids, &{&1, default_reason})}

      true ->
        Mix.shell().error("Must provide --vndb-ids, --ids, or --csv")
        System.halt(1)
    end
  end

  defp resolve_csv(csv_path, default_reason) do
    unless File.exists?(csv_path) do
      Mix.shell().error("CSV file not found: #{csv_path}")
      System.halt(1)
    end

    # Parse CSV → %{slug => reason}
    [_header | rows] =
      csv_path
      |> File.read!()
      |> String.split("\n", trim: true)

    slug_reasons =
      Enum.reduce(rows, %{}, fn line, acc ->
        case String.split(line, ",", parts: 4) do
          [_title, kaguya_link, _vndb_link, notes] ->
            case extract_slug(kaguya_link) do
              nil ->
                acc

              slug ->
                reason =
                  case notes |> String.trim() |> String.trim_trailing(",") |> String.trim("\"") do
                    "" -> default_reason
                    r -> r
                  end

                Map.put(acc, slug, reason)
            end

          [_title, kaguya_link | _rest] ->
            case extract_slug(kaguya_link) do
              nil -> acc
              slug -> Map.put(acc, slug, default_reason)
            end

          _ ->
            acc
        end
      end)

    slugs = Map.keys(slug_reasons)
    Mix.shell().info("Parsed #{length(slugs)} slugs from CSV")

    # Single batch query: resolve all slugs → {slug, vn_id}
    found =
      from(vn in VisualNovel,
        where: vn.slug in ^slugs,
        select: {vn.slug, vn.id}
      )
      |> Repo.all()

    found_slugs = Enum.map(found, &elem(&1, 0))
    missing = slugs -- found_slugs

    if missing != [] do
      Mix.shell().info("Warning: slugs not found in database: #{Enum.join(missing, ", ")}")
    end

    # Build vn_id → reason map
    vn_reasons =
      Map.new(found, fn {slug, vn_id} ->
        {vn_id, Map.fetch!(slug_reasons, slug)}
      end)

    vn_ids = Enum.map(found, &elem(&1, 1))
    {vn_ids, vn_reasons}
  end

  defp extract_slug(kaguya_link) do
    case String.trim(kaguya_link) do
      "" ->
        nil

      url ->
        url
        |> URI.parse()
        |> Map.get(:path, "")
        |> String.split("/vn/")
        |> List.last()
        |> case do
          "" -> nil
          slug -> slug
        end
    end
  end

  defp resolve_vndb_ids(vndb_ids) do
    found =
      from(vn in VisualNovel,
        where: vn.vndb_id in ^vndb_ids,
        select: {vn.vndb_id, vn.id}
      )
      |> Repo.all()

    found_vndb_ids = Enum.map(found, &elem(&1, 0))
    missing = vndb_ids -- found_vndb_ids

    if missing != [] do
      Mix.shell().info("Warning: VNs not found in database: #{Enum.join(missing, ", ")}")
    end

    Enum.map(found, &elem(&1, 1))
  end

  defp verify_ids(ids) do
    found =
      from(vn in VisualNovel, where: vn.id in ^ids, select: vn.id)
      |> Repo.all()

    missing = ids -- Enum.map(found, &to_string/1)

    if missing != [] do
      Mix.shell().info("Warning: UUIDs not found: #{Enum.join(missing, ", ")}")
    end

    found
  end

  # ──────────────────────
  # Phase 3: Summary
  # ──────────────────────

  defp print_summary(data, vn_reasons, execute?) do
    IO.puts("\n" <> String.duplicate("=", 90))
    IO.puts("  VN DELETION #{if execute?, do: "EXECUTION", else: "DRY RUN"} SUMMARY")
    IO.puts(String.duplicate("=", 90))

    # VN table
    IO.puts("\nVNs to delete (#{length(data.vn_details)}):")
    IO.puts(String.duplicate("-", 110))

    IO.puts(
      "  #{pad("VNDB ID", 10)} | #{pad("Title", 40)} | #{pad("Ratings", 8)} | #{pad("Reviews", 8)} | #{pad("Reason", 25)}"
    )

    IO.puts("  " <> String.duplicate("-", 106))

    Enum.each(data.vn_details, fn vn ->
      title = String.slice(vn.title || "", 0, 40)
      reason = Map.get(vn_reasons, vn.id, "?") |> String.slice(0, 25)

      IO.puts(
        "  #{pad(vn.vndb_id || "?", 10)} | #{pad(title, 40)} | #{pad(to_string(vn.ratings_count || 0), 8)} | #{pad(to_string(vn.reviews_count || 0), 8)} | #{pad(reason, 25)}"
      )
    end)

    total_ratings = data.ratings_by_user |> Map.values() |> List.flatten() |> length()
    unique_rating_users = map_size(data.ratings_by_user)
    total_reviews = data.reviews_by_user |> Map.values() |> List.flatten() |> length()
    unique_review_users = map_size(data.reviews_by_user)

    cover_files = length(data.vn_image_ids) * 4
    screenshot_files = length(data.vn_screenshot_ids) * 3
    char_files = length(data.orphaned_char_image_ids)
    total_r2_files = cover_files + screenshot_files + char_files

    IO.puts("\nAffected data:")
    IO.puts("  User ratings:        #{total_ratings} (#{unique_rating_users} unique users)")
    IO.puts("  User reviews:        #{total_reviews} (#{unique_review_users} unique users)")
    IO.puts("  Orphaned characters: #{length(data.orphaned_char_ids)}")
    IO.puts("  Orphaned producers:  #{length(data.orphaned_producer_ids)}")
    IO.puts("  Orphaned series:     #{length(data.orphaned_series_ids)}")
    IO.puts("  Orphaned tags:       #{length(data.candidate_orphaned_tag_ids)} (candidates)")
    IO.puts("  Shelf adjustments:   #{length(data.shelf_counts)}")

    IO.puts(
      "  List adjustments:    #{length(data.list_counts)} (#{length(data.ranked_list_ids)} ranked)"
    )

    IO.puts(
      "  Notifications:       #{data.notification_count} review + #{data.vn_list_notif_count} list"
    )

    IO.puts(
      "  R2 files:            #{total_r2_files} (covers: #{length(data.vn_image_ids)}×4, screenshots: #{length(data.vn_screenshot_ids)}×3, characters: #{length(data.orphaned_char_image_ids)}×1)"
    )

    IO.puts(
      "  Meilisearch docs:    #{length(data.vn_ids)} VNs + #{length(data.orphaned_char_ids)} characters"
    )

    vndb_id_count = data.vn_details |> Enum.count(& &1.vndb_id)

    reason_counts =
      vn_reasons
      |> Map.values()
      |> Enum.frequencies()
      |> Enum.map_join(", ", fn {r, c} -> "#{r}: #{c}" end)

    IO.puts("  Import blocklist:    #{vndb_id_count} VNDB IDs to record (#{reason_counts})")

    IO.puts(String.duplicate("=", 90))
  end

  defp pad(str, width) do
    String.pad_trailing(str, width)
  end
end
