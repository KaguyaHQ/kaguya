defmodule Mix.Tasks.Kaguya.RenameVn do
  @moduledoc """
  CLI for renaming a single VN's slug and/or title without merging
  anything. The old slug is auto-recorded in `slug_redirects` so existing
  URLs keep resolving to this VN.

  Not exposed in the web app — the rename runs only via this mix task.

  ## Usage

      # Preview (dry-run): prints the resolved change set.
      mix kaguya.rename_vn --vn=<slug-or-uuid> --slug=<new-slug>

      # Execute
      mix kaguya.rename_vn \\
        --vn=elleria-book-1 \\
        --slug=elleria \\
        --title="Elleria" \\
        --execute

      # Title-only retitle (no slug redirect needed)
      mix kaguya.rename_vn \\
        --vn=summers-gone \\
        --title="Summer's Gone (Complete)" \\
        --execute

  ## Options

    * `--vn=<slug-or-uuid>` — the VN to rename. Slug is resolved through
      `slug_redirects` so a stale URL works too (returns the current
      canonical's id, which then gets renamed again — usually you want
      to pass the current slug or the UUID directly).
    * `--slug=<new>` — the new slug. Must be unique in `visual_novels`.
    * `--title=<new>` — the new title.
    * `--reason=<rename|merge|manual>` — recorded on the `slug_redirects`
      row when the slug changes. Default `rename`.
    * `--execute` — actually run. Without it, the task only previews.

  At least one of `--slug` / `--title` must be set; otherwise the task
  exits with `:no_changes`.

  See `Kaguya.VisualNovels.Rename.@moduledoc` for the function-level API
  and `docs/plans/vn-merge-plan.md` for the slug-resolution architecture.
  """

  use Mix.Task

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.{Rename, VisualNovel}

  @shortdoc "Rename a VN's slug and/or title (writes a slug_redirects row on slug change)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          vn: :string,
          slug: :string,
          title: :string,
          reason: :string,
          execute: :boolean
        ]
      )

    vn_input = Keyword.get(opts, :vn) || abort!("--vn is required (slug or uuid)")
    new_slug = Keyword.get(opts, :slug)
    new_title = Keyword.get(opts, :title)
    execute? = Keyword.get(opts, :execute, false)
    reason = parse_reason(Keyword.get(opts, :reason, "rename"))

    if is_nil(new_slug) and is_nil(new_title) do
      abort!("at least one of --slug or --title must be set")
    end

    vn = lookup_vn!(vn_input)
    print_preview(vn, new_slug, new_title, reason)

    attrs = build_attrs(new_slug, new_title)

    if execute? do
      case Rename.rename_vn(vn.id, attrs, reason: reason) do
        {:ok, updated} ->
          Mix.shell().info(
            "\nRename complete. id=#{updated.id} slug=#{updated.slug} title=#{inspect(updated.title)}"
          )

        {:error, :no_changes} ->
          Mix.shell().info("\nNothing to do — current values already match.")

        {:error, :not_found} ->
          Mix.shell().error("VN not found: #{vn.id}")
          System.halt(1)

        {:error, %Ecto.Changeset{} = cs} ->
          Mix.shell().error("Validation failed: #{inspect(cs.errors)}")
          System.halt(1)
      end
    else
      Mix.shell().info("\nDry run complete. Pass --execute to actually rename.")
    end
  end

  # ──────────────────────────────────────────────────────────────────

  defp build_attrs(slug, title) do
    %{}
    |> maybe_put(:slug, slug)
    |> maybe_put(:title, title)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp parse_reason("rename"), do: :rename
  defp parse_reason("merge"), do: :merge
  defp parse_reason("manual"), do: :manual

  defp parse_reason(other),
    do: abort!("invalid --reason: #{other} (allowed: rename, merge, manual)")

  defp lookup_vn!(input) do
    if Ecto.UUID.cast(input) == {:ok, input} do
      case Repo.get(VisualNovel, input) do
        nil -> abort!("VN not found for id=#{input}")
        vn -> vn
      end
    else
      case Repo.get_by(VisualNovel, slug: input) do
        nil ->
          case Kaguya.SlugRedirects.resolve(:vn, input) do
            nil ->
              abort!("VN not found for slug=#{input}")

            id ->
              Mix.shell().info(
                "Note: '#{input}' is a redirect; renaming the current VN at that target."
              )

              Repo.get!(VisualNovel, id)
          end

        vn ->
          vn
      end
    end
  end

  defp print_preview(vn, new_slug, new_title, reason) do
    Mix.shell().info("VN: #{vn.slug}  (#{vn.title})  id=#{vn.id}")

    if new_slug && new_slug != vn.slug do
      Mix.shell().info(
        "  slug:  #{vn.slug}  →  #{new_slug}    (slug_redirects entry, reason=#{reason})"
      )
    end

    if new_title && new_title != vn.title do
      Mix.shell().info("  title: #{inspect(vn.title)}  →  #{inspect(new_title)}")
    end
  end

  defp abort!(msg) do
    Mix.shell().error(msg)
    System.halt(1)
  end
end
