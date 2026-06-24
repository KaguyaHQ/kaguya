defmodule Mix.Tasks.Kaguya.MergeVns do
  @moduledoc """
  CLI for merging multiple VNs into a single canonical VN. Resolves slugs
  to UUIDs, shows a dry-run preview of the resolved canonical metadata,
  then delegates to `Kaguya.VisualNovels.Merge` for the actual work.

  Not exposed in the web app — the merge runs only via this mix task.

  ## Usage

      # Preview the merge — shows resolved canonical attrs and counts
      mix kaguya.merge_vns \\
        --canonical=summers-gone \\
        --sources=summers-gone-season-1,summers-gone-season-2-constellations

      # Execute (after preview looks right)
      mix kaguya.merge_vns \\
        --canonical=summers-gone \\
        --sources=summers-gone-season-1,summers-gone-season-2-constellations \\
        --execute

      # Pick season-1 as canonical but rename it to the base slug + title:
      mix kaguya.merge_vns \\
        --canonical=summers-gone-season-1 \\
        --sources=summers-gone-season-2-constellations \\
        --title="Summer's Gone" \\
        --slug=summers-gone \\
        --execute

  ## Options

    * `--canonical=<slug>` — slug of the surviving canonical VN
    * `--sources=<slug>,<slug>` — comma-separated slugs to be merged in
    * `--title=<text>` — override the canonical's title post-merge (otherwise
      keeps the canonical's existing title)
    * `--slug=<slug>` — override the canonical's slug post-merge (e.g. strip
      ": Season 1"). Must be unique in `visual_novels`.
    * `--execute` — actually run. Without it, the task does a dry-run only.

  Canonical and source(s) are resolved to UUIDs before delegation. Slugs
  must exist in `visual_novels.slug`; the task prints a clear error and
  exits if any are missing.

  After execute, sources are deleted, their slugs and VNDB ids are
  registered in `vn_merges` (so VNDB sync skips them and the URL router
  can 301 to the canonical), and the canonical row is updated with the
  resolved field values. See `docs/plans/vn-merge-plan.md` and the `Merge` module's
  `@moduledoc` for the full per-table conflict-resolution rules.
  """

  use Mix.Task

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.Merge
  alias Kaguya.VisualNovels.VisualNovel

  @shortdoc "Merge source VNs into a canonical VN"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          canonical: :string,
          sources: :string,
          title: :string,
          slug: :string,
          execute: :boolean
        ]
      )

    canonical_slug = Keyword.get(opts, :canonical) || abort!("--canonical is required")
    sources_str = Keyword.get(opts, :sources) || abort!("--sources is required")
    execute? = Keyword.get(opts, :execute, false)

    attrs_override =
      [title: Keyword.get(opts, :title), slug: Keyword.get(opts, :slug)]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    source_slugs =
      sources_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if source_slugs == [], do: abort!("--sources must list at least one slug")

    canonical = lookup_vn_by_slug!(canonical_slug)
    sources = Enum.map(source_slugs, &lookup_vn_by_slug!/1)

    if canonical.id in Enum.map(sources, & &1.id) do
      abort!("--canonical (#{canonical_slug}) appears in --sources; cannot self-merge")
    end

    print_preview(canonical, sources, attrs_override)

    case Merge.merge_vns(canonical.id, Enum.map(sources, & &1.id), nil,
           dry_run: true,
           attrs: attrs_override
         ) do
      {:ok, summary} ->
        print_resolved(summary)

      {:error, reason} ->
        Mix.shell().error("Validation failed: #{inspect(reason)}")
        System.halt(1)
    end

    if execute? do
      Mix.shell().info("\nExecuting merge...")

      case Merge.merge_vns(canonical.id, Enum.map(sources, & &1.id), nil, attrs: attrs_override) do
        {:ok, result} ->
          Mix.shell().info(
            "\nMerge complete. Canonical=#{result_slug(canonical, attrs_override)}; merged #{result.merged_count} source(s)."
          )

        {:error, reason} ->
          Mix.shell().error("Merge failed: #{inspect(reason)}")
          System.halt(1)
      end
    else
      Mix.shell().info("\nDry run complete. Pass --execute to actually merge.")
    end
  end

  defp result_slug(_canonical, %{slug: s}) when is_binary(s) and s != "", do: s
  defp result_slug(canonical, _), do: canonical.slug

  # ──────────────────────────────
  # Lookups
  # ──────────────────────────────

  defp lookup_vn_by_slug!(slug) do
    case Repo.get_by(VisualNovel, slug: slug) do
      nil -> abort!("VN not found for slug=#{slug}")
      vn -> vn
    end
  end

  defp abort!(msg) do
    Mix.shell().error(msg)
    System.halt(1)
  end

  # ──────────────────────────────
  # Display helpers
  # ──────────────────────────────

  defp print_preview(canonical, sources, attrs_override) do
    Mix.shell().info("Canonical: #{canonical.slug}  (#{canonical.title})  id=#{canonical.id}")

    if attrs_override != %{} do
      Mix.shell().info("Overrides: #{inspect(attrs_override)}")
    end

    Mix.shell().info("Sources to merge in:")

    Enum.each(sources, fn s ->
      vndb = if s.vndb_id, do: " vndb=#{s.vndb_id}", else: ""
      Mix.shell().info("  - #{s.slug}  (#{s.title})  id=#{s.id}#{vndb}")
    end)
  end

  defp print_resolved(%{resolved_attrs: attrs}) do
    Mix.shell().info("\nResolved canonical attrs (post-merge):")

    [
      :title,
      :slug,
      :development_status,
      :title_category,
      :has_ero,
      :is_avn,
      :is_image_nsfw,
      :is_image_suggestive,
      :release_date,
      :length_minutes,
      :length_category,
      :min_age,
      :original_language,
      :primary_image_id,
      :featured_screenshot_id,
      :hidden_at,
      :is_locked
    ]
    |> Enum.each(fn key ->
      val = Map.get(attrs, key)
      Mix.shell().info(String.pad_trailing("  #{key}", 28) <> "= #{inspect(val)}")
    end)

    aliases = Map.get(attrs, :aliases, [])
    Mix.shell().info("  aliases (#{length(aliases)})       = #{inspect(aliases)}")
  end

  defp print_resolved(other) do
    Mix.shell().info("Dry-run summary: #{inspect(other)}")
  end
end
