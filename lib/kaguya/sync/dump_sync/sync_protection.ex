defmodule Kaguya.Sync.DumpSync.SyncProtection do
  @moduledoc """
  Protects user-edited entities from being overwritten by VNDB dump sync.

  Entities with any user-submitted revision (source: :user) have their content
  fields skipped during sync. VNDB reference data (ratings, vote counts) still syncs.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change

  @doc """
  Returns a MapSet of entity UUIDs that have user edits for the given entity type.
  """
  def user_edited_ids(entity_type) do
    from(c in Change,
      where: c.entity_type == ^entity_type and c.source == :user,
      select: c.entity_id,
      distinct: true
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns a MapSet of VNDB IDs for user-edited entities.
  Resolves UUID → vndb_id via the given schema.
  """
  def user_edited_vndb_ids(entity_type, schema) do
    uuids = user_edited_ids(entity_type)

    if MapSet.size(uuids) == 0 do
      MapSet.new()
    else
      uuid_list = MapSet.to_list(uuids)

      from(e in schema,
        where: e.id in ^uuid_list and not is_nil(e.vndb_id),
        select: e.vndb_id
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  @doc """
  Upserts existing entity rows with sync protection.
  User-edited entities only get reference fields updated.
  Unprotected entities get full content + reference fields updated.

  `protected_vndb_ids` is a MapSet of VNDB IDs that should be protected.
  `vndb_id_fn` extracts the vndb_id from a row (e.g. `& &1.vndb_id` or `& &1[:vndb_id]`).
  """
  def protected_upsert(schema, rows, protected_vndb_ids, vndb_id_fn, opts) do
    full_fields = Keyword.fetch!(opts, :full_replace_fields)
    ref_fields = Keyword.fetch!(opts, :reference_replace_fields)
    conflict_target = Keyword.fetch!(opts, :conflict_target)

    {unprotected, protected} =
      Enum.split_with(rows, fn row ->
        vndb_id = vndb_id_fn.(row)
        vndb_id == nil or not MapSet.member?(protected_vndb_ids, vndb_id)
      end)

    count1 =
      if unprotected != [] do
        Kaguya.Sync.DumpSync.chunked_insert(schema, unprotected,
          on_conflict: {:replace, full_fields},
          conflict_target: conflict_target
        )
      else
        0
      end

    count2 =
      if protected != [] do
        require Logger

        Logger.info(
          "  ⚡ #{length(protected)} user-edited entries protected from content overwrite"
        )

        Kaguya.Sync.DumpSync.chunked_insert(schema, protected,
          on_conflict: {:replace, ref_fields},
          conflict_target: conflict_target
        )
      else
        0
      end

    count1 + count2
  end
end
