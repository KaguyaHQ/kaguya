defmodule Kaguya.SlugRedirects do
  @moduledoc """
  Generic slug-history resolver. One table backs URL stability across every
  entity type that needs it.

  ## Resolver contract

  The entity's *current* `slug` column always wins. Callers should structure
  `get_*_by_slug/1` as:

      def get_visual_novel_by_slug(slug) do
        case Repo.get_by(VisualNovel, slug: slug) do
          nil ->
            case SlugRedirects.resolve(:vn, slug) do
              nil -> nil
              id -> Repo.get(VisualNovel, id)
            end

          vn -> vn
        end
      end

  Frontend compares the requested slug against the resolved entity's current
  `slug` and issues a 301 when they differ.

  ## Write contract

  Context modules call `record/4` inside the same `Repo.transact/1` block
  that performs a rename or merge:

      def rename_visual_novel(vn, attrs) do
        Repo.transact(fn ->
          old_slug = vn.slug
          with {:ok, updated} <- vn |> changeset(attrs) |> Repo.update() do
            if updated.slug != old_slug do
              SlugRedirects.record(:vn, old_slug, updated.id)
            end
            {:ok, updated}
          end
        end)
      end

  `record/4` is idempotent — same key upserts target_id (last writer wins,
  which is correct when a slug gets reused across entities over time).

  ## Cleanup contract

  Hard-deleting an entity must purge its redirects in the same transaction:

      SlugRedirects.purge_for_target(:vn, vn.id)

  Hard-deleting a user must purge scoped redirects:

      SlugRedirects.purge_for_scope(user.id)

  Soft-delete does not purge — redirects keep working until hard delete.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.SlugRedirects.SlugRedirect

  @type entity_type :: :vn | :character | :producer | :tag | :series | :list | :shelf

  # ---------------------------------------------------------------------------
  # Resolve
  # ---------------------------------------------------------------------------

  @doc """
  Returns the entity id for a historical slug, or `nil`.

  For scoped entity types (`:list`, `:shelf`), pass `scope_id:` — the owning
  user's id. Globally-scoped types must omit it.
  """
  def resolve(entity_type, old_slug, opts \\ [])
      when is_atom(entity_type) and is_binary(old_slug) do
    scope_id = Keyword.get(opts, :scope_id)

    SlugRedirect
    |> where([r], r.entity_type == ^entity_type and r.old_slug == ^old_slug)
    |> scope_filter(scope_id)
    |> select([r], r.target_id)
    |> Repo.one()
  end

  @doc """
  Bulk variant of `resolve/3`. Returns `%{old_slug => target_id}` for every
  input slug that has a redirect. Slugs without a match are absent from the
  returned map.

  Only supports a single scope_id for the whole batch — callers with mixed
  scopes should call this once per scope.
  """
  @spec resolve_many(entity_type(), [String.t()], keyword()) :: %{String.t() => Ecto.UUID.t()}
  def resolve_many(entity_type, old_slugs, opts \\ [])
      when is_atom(entity_type) and is_list(old_slugs) do
    if old_slugs == [] do
      %{}
    else
      scope_id = Keyword.get(opts, :scope_id)

      SlugRedirect
      |> where([r], r.entity_type == ^entity_type and r.old_slug in ^old_slugs)
      |> scope_filter(scope_id)
      |> select([r], {r.old_slug, r.target_id})
      |> Repo.all()
      |> Map.new()
    end
  end

  defp scope_filter(query, nil), do: where(query, [r], is_nil(r.scope_id))
  defp scope_filter(query, scope_id), do: where(query, [r], r.scope_id == ^scope_id)

  # ---------------------------------------------------------------------------
  # Record
  # ---------------------------------------------------------------------------

  @doc """
  Records a redirect from `old_slug` to `target_id`. Idempotent —
  re-recording the same key overwrites `target_id` and `reason`.

  Options:
    * `:scope_id` — required for `:list` / `:shelf`, forbidden otherwise.
    * `:reason` — `:rename` (default), `:merge`, or `:manual`.
  """
  def record(entity_type, old_slug, target_id, opts \\ [])
      when is_atom(entity_type) and is_binary(old_slug) and is_binary(target_id) do
    attrs = %{
      entity_type: entity_type,
      old_slug: old_slug,
      target_id: target_id,
      scope_id: Keyword.get(opts, :scope_id),
      reason: Keyword.get(opts, :reason, :rename)
    }

    %SlugRedirect{}
    |> SlugRedirect.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:target_id, :reason, :inserted_at]},
      conflict_target: [:entity_type, :scope_id, :old_slug]
    )
  end

  @doc """
  Bulk-records redirects via `Repo.insert_all`. Same idempotency contract
  as `record/4`. Caller is responsible for `:scope_id` / entity_type
  consistency — no per-row validation runs here.

  Each entry: `%{entity_type:, old_slug:, target_id:, scope_id: nil, reason: :rename}`.
  """
  def record_many(entries) when is_list(entries) do
    if entries == [] do
      {0, nil}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(entries, fn entry ->
          %{
            id: UUIDv7.bingenerate(),
            entity_type: to_string(Map.fetch!(entry, :entity_type)),
            old_slug: Map.fetch!(entry, :old_slug),
            target_id: dump_uuid!(Map.fetch!(entry, :target_id)),
            scope_id: dump_uuid(Map.get(entry, :scope_id)),
            reason: entry |> Map.get(:reason, :rename) |> to_string(),
            inserted_at: now
          }
        end)

      # Pass table name (not schema) so Ecto skips per-field cast — rows are
      # already in DB-native form (raw 16-byte UUID binaries, atom-as-string
      # for enums). Mirrors `Kaguya.VisualNovels.Merge.insert_vn_merges/4`.
      Repo.insert_all("slug_redirects", rows,
        on_conflict: {:replace, [:target_id, :reason, :inserted_at]},
        conflict_target: [:entity_type, :scope_id, :old_slug]
      )
    end
  end

  defp dump_uuid(nil), do: nil
  defp dump_uuid(<<_::128>> = bin), do: bin
  defp dump_uuid(uuid) when is_binary(uuid), do: Ecto.UUID.dump!(uuid)

  defp dump_uuid!(uuid), do: dump_uuid(uuid) || raise(ArgumentError, "missing uuid")

  # ---------------------------------------------------------------------------
  # Purge
  # ---------------------------------------------------------------------------

  @doc """
  Deletes every redirect pointing at `target_id`. Call inside the same
  transaction as a hard-delete of the entity.
  """
  def purge_for_target(entity_type, target_id)
      when is_atom(entity_type) and is_binary(target_id) do
    SlugRedirect
    |> where([r], r.entity_type == ^entity_type and r.target_id == ^target_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes every scoped redirect under `scope_id` (e.g. all list/shelf
  redirects owned by a user being hard-deleted).
  """
  def purge_for_scope(scope_id) when is_binary(scope_id) do
    SlugRedirect
    |> where([r], r.scope_id == ^scope_id)
    |> Repo.delete_all()
  end

  # ---------------------------------------------------------------------------
  # Admin / introspection
  # ---------------------------------------------------------------------------

  @doc """
  Lists every historical slug pointing at `target_id`, newest first.
  """
  def list_for_target(entity_type, target_id) do
    SlugRedirect
    |> where([r], r.entity_type == ^entity_type and r.target_id == ^target_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end
end
