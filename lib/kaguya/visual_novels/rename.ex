defmodule Kaguya.VisualNovels.Rename do
  @moduledoc """
  Rename a single VN's slug and/or title without merging anything. Same
  trust boundary as `Kaguya.VisualNovels.Merge` (mix-task only, no
  web exposure).

  When the slug changes, a `slug_redirects` row is recorded so old URLs
  keep resolving to this VN — every `get_*_by_slug/1` call site already
  falls through that table.

  Compared to `Merge`: nothing is deleted, no FK migration runs, no
  aggregates need recomputing. The whole operation is a single row
  update + at most one `slug_redirects` row + a `:edit` revision row,
  all in one transaction.
  """

  require Logger

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.SearchIndex
  alias Kaguya.SlugRedirects
  alias Kaguya.VisualNovels.{BrowseSections, VisualNovel}

  @valid_attrs [:slug, :title]

  @doc """
  Rename a VN.

  ## Args

    * `vn_id` — UUID string of the VN to rename.
    * `attrs` — map with optional `:slug` and/or `:title`.

  ## Options

    * `:reason` — `:rename` (default), `:merge`, or `:manual`. Recorded
      on the `slug_redirects` row when the slug changes; informational
      only, doesn't change behavior.

  ## Returns

    * `{:ok, vn}` — the updated VN row.
    * `{:error, :not_found}` — vn_id doesn't exist.
    * `{:error, :no_changes}` — neither slug nor title differ from current.
    * `{:error, %Ecto.Changeset{}}` — validation failure (e.g. slug
      collides with another VN's current slug).
  """
  def rename_vn(vn_id, attrs, opts \\ []) when is_binary(vn_id) and is_map(attrs) do
    reason = Keyword.get(opts, :reason, :rename)
    cleaned = clean_attrs(attrs)

    Repo.transact(fn ->
      with {:ok, vn} <- fetch_vn(vn_id),
           :ok <- validate_changes(vn, cleaned),
           {:ok, updated} <- apply_changes(vn, cleaned),
           :ok <- maybe_record_redirect(vn, updated, reason),
           :ok <- write_revision(vn, updated) do
        {:ok, updated}
      end
    end)
    |> case do
      {:ok, updated} ->
        post_transaction_cleanup(updated)
        {:ok, updated}

      other ->
        other
    end
  end

  # ──────────────────────────────────────────────────────────────────

  defp clean_attrs(attrs) do
    attrs
    |> Map.take(@valid_attrs)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp fetch_vn(vn_id) do
    case Repo.get(VisualNovel, vn_id) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp validate_changes(vn, attrs) do
    slug_changed? = Map.get(attrs, :slug, vn.slug) != vn.slug
    title_changed? = Map.get(attrs, :title, vn.title) != vn.title

    if slug_changed? or title_changed?, do: :ok, else: {:error, :no_changes}
  end

  # `:slug` is intentionally absent from `VisualNovel.changeset`'s public
  # cast list (the schema treats it as immutable post-creation under
  # normal user editing). We bypass via `put_change/3` — same trick
  # `Merge.update_canonical_row/3` uses for sync-only fields.
  defp apply_changes(vn, attrs) do
    title_attrs = Map.take(attrs, [:title])

    changeset =
      vn
      |> VisualNovel.changeset(title_attrs)
      |> maybe_put_slug(attrs)

    case Repo.update(changeset) do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} -> {:error, cs}
    end
  end

  defp maybe_put_slug(changeset, %{slug: slug}) when is_binary(slug),
    do: Ecto.Changeset.put_change(changeset, :slug, slug)

  defp maybe_put_slug(changeset, _), do: changeset

  defp maybe_record_redirect(%{slug: old_slug}, %{slug: new_slug, id: id}, reason)
       when old_slug != new_slug do
    case SlugRedirects.record(:vn, old_slug, id, reason: reason) do
      {:ok, _} -> :ok
      {:error, cs} -> {:error, cs}
    end
  end

  defp maybe_record_redirect(_vn, _updated, _reason), do: :ok

  defp write_revision(old_vn, updated_vn) do
    changed_fields =
      [:slug, :title]
      |> Enum.filter(&(Map.get(old_vn, &1) != Map.get(updated_vn, &1)))
      |> Enum.map(&Atom.to_string/1)

    Revisions.bulk_create_system_changes([
      %{
        entity_type: :visual_novel,
        entity_id: updated_vn.id,
        action: :edit,
        source: :system,
        changed_fields: changed_fields,
        summary: summary(old_vn, updated_vn, changed_fields)
      }
    ])

    :ok
  end

  defp summary(old, new, ["slug", "title"]),
    do:
      "Renamed `#{old.slug}` → `#{new.slug}`; retitled #{inspect(old.title)} → #{inspect(new.title)}"

  defp summary(old, new, ["slug"]), do: "Renamed `#{old.slug}` → `#{new.slug}`"
  defp summary(old, new, ["title"]), do: "Retitled #{inspect(old.title)} → #{inspect(new.title)}"
  defp summary(_old, _new, _), do: "Edit"

  # ──────────────────────────────────────────────────────────────────
  # Post-transaction (idempotent, non-critical)
  # ──────────────────────────────────────────────────────────────────

  # Mirrors `Kaguya.VisualNovels.Merge.post_transaction_cleanup/2`. Runs
  # outside the transaction so a search-index/cache hiccup doesn't roll
  # back the rename. Failure is logged and swallowed — the DB row is the
  # source of truth; the index and cache catch up on their own retry.
  defp post_transaction_cleanup(vn) do
    SearchIndex.index_visual_novels(vn)
    BrowseSections.refresh()
    :ok
  rescue
    e ->
      Logger.warning("rename: post-cleanup failed (non-fatal): #{inspect(e)}")
      :ok
  end

  # ──────────────────────────────────────────────────────────────────
  # Bulk
  # ──────────────────────────────────────────────────────────────────

  @doc """
  Sequentially apply `rename_vn/3` to each `{vn_id, attrs}` pair. Each
  rename runs in its own transaction (so a failure on one doesn't roll
  back earlier successes — useful for batch fixups).

  Returns `%{ok: [vn_id, ...], errors: [{vn_id, reason}, ...]}`.
  """
  @spec rename_many([{Ecto.UUID.t(), map()}], keyword()) :: %{
          ok: [Ecto.UUID.t()],
          errors: [{Ecto.UUID.t(), term()}]
        }
  def rename_many(entries, opts \\ []) when is_list(entries) do
    Enum.reduce(entries, %{ok: [], errors: []}, fn {vn_id, attrs}, acc ->
      case rename_vn(vn_id, attrs, opts) do
        {:ok, _} -> %{acc | ok: [vn_id | acc.ok]}
        {:error, reason} -> %{acc | errors: [{vn_id, reason} | acc.errors]}
      end
    end)
    |> Map.update!(:ok, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  @doc """
  Convenience for the common dedup-doc rename: look up the VN by its
  current slug, then rename. Returns the same shape as `rename_vn/3`.
  """
  def rename_by_slug(current_slug, attrs, opts \\ []) when is_binary(current_slug) do
    case Repo.one(from v in VisualNovel, where: v.slug == ^current_slug, select: v.id, limit: 1) do
      nil -> {:error, :not_found}
      id -> rename_vn(id, attrs, opts)
    end
  end
end
