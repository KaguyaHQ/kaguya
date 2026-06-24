defmodule Kaguya.Sync.DumpSync.Relations do
  @moduledoc """
  Syncs VN-VN relations from VNDB dump.

  Step 5: VN relations (~29K rows, processed in batches).
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbFieldMapper
  alias Kaguya.VisualNovels.Relation
  alias Kaguya.Sync.DumpSync.SyncProtection

  @batch_size 10_000

  def run(%{vndb: vndb, dry_run: dry_run, vn_mapping: vn_mapping} = ctx) do
    target_ids = ctx[:target_vndb_ids]

    protected_vn_uuids = SyncProtection.user_edited_ids(:visual_novel)

    if target_ids do
      Logger.info("Importing relations for #{length(target_ids)} targeted VN(s)...")
      process_targeted_relations(vndb, target_ids, vn_mapping, protected_vn_uuids)
    else
      Logger.info("Loading VN relations from VNDB dump...")

      total = count_relations(vndb)
      Logger.info("Total VN relations in dump: #{total}")

      if dry_run do
        Logger.info("[DRY RUN] Would process #{total} VN relations")
        {:ok, total}
      else
        existing_pairs = load_existing_pairs()
        Logger.info("Existing relation pairs in DB: #{MapSet.size(existing_pairs)}")

        {upserted, new_count, updated_count, new_ids} =
          do_relation_batches(
            vndb,
            vn_mapping,
            existing_pairs,
            protected_vn_uuids,
            0,
            0,
            0,
            0,
            []
          )

        Report.record(:relations, new_count, updated_count, new_ids)

        Logger.info(
          "VN relation sync complete: #{upserted} upserted (#{new_count} new, #{updated_count} updated)"
        )

        {:ok, upserted}
      end
    end
  end

  defp process_targeted_relations(vndb, target_ids, vn_mapping, protected_vn_uuids) do
    phs = DumpSync.placeholders(target_ids)
    # Double params: once for id IN, once for vid IN
    params = target_ids ++ target_ids

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, vid, relation::text, official
        FROM vn_relations
        WHERE id IN (#{phs}) OR vid IN (#{shift_placeholders(length(target_ids), length(target_ids))})
        """,
        params
      )

    now = DumpSync.now()
    existing_pairs = load_existing_pairs()

    {insert_rows, new_ids} =
      Enum.reduce(rows, {[], []}, fn r, {rows_acc, ids} ->
        with vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, r.id),
             false <- MapSet.member?(protected_vn_uuids, vn_uuid),
             related_uuid when not is_nil(related_uuid) <- Map.get(vn_mapping, r.vid) do
          row = %{
            visual_novel_id: vn_uuid,
            related_vn_id: related_uuid,
            relation_type: VndbFieldMapper.map_relation_type(r.relation),
            is_official: r.official,
            inserted_at: now,
            updated_at: now
          }

          is_new = not MapSet.member?(existing_pairs, {vn_uuid, related_uuid})
          new_id = if is_new, do: [%{id: "#{r.id}→#{r.vid}", relation: r.relation}], else: []
          {[row | rows_acc], new_id ++ ids}
        else
          _ -> {rows_acc, ids}
        end
      end)

    count =
      DumpSync.chunked_insert(Relation, insert_rows,
        on_conflict: {:replace, [:relation_type, :is_official, :updated_at]},
        conflict_target: [:visual_novel_id, :related_vn_id]
      )

    new_count = length(new_ids)
    Report.record(:relations, new_count, count - new_count, new_ids)
    Logger.info("Targeted relation import: #{count} upserted (#{new_count} new)")
    {:ok, count}
  end

  # Build $N+1, $N+2, ... for the second set of params
  defp shift_placeholders(offset, count) do
    Enum.map_join(1..count, ", ", fn i -> "$#{offset + i}" end)
  end

  defp do_relation_batches(
         vndb,
         vn_mapping,
         existing_pairs,
         protected_vn_uuids,
         offset,
         acc,
         new_acc,
         updated_acc,
         ids_acc
       ) do
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT id, vid, relation::text, official
      FROM vn_relations
      ORDER BY id, vid
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if rows == [] do
      {acc, new_acc, updated_acc, ids_acc}
    else
      Logger.info("Processing relation batch at offset #{offset} (#{length(rows)} rows)...")
      now = DumpSync.now()

      # Build rows and track new vs existing
      {insert_rows, batch_new_ids} =
        Enum.reduce(rows, {[], []}, fn r, {rows_acc, ids} ->
          with vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, r.id),
               false <- MapSet.member?(protected_vn_uuids, vn_uuid),
               related_uuid when not is_nil(related_uuid) <- Map.get(vn_mapping, r.vid) do
            row = %{
              visual_novel_id: vn_uuid,
              related_vn_id: related_uuid,
              relation_type: VndbFieldMapper.map_relation_type(r.relation),
              is_official: r.official,
              inserted_at: now,
              updated_at: now
            }

            is_new = not MapSet.member?(existing_pairs, {vn_uuid, related_uuid})
            new_id = if is_new, do: [%{id: "#{r.id}→#{r.vid}", relation: r.relation}], else: []
            {[row | rows_acc], new_id ++ ids}
          else
            _ -> {rows_acc, ids}
          end
        end)

      batch_new = length(batch_new_ids)
      batch_updated = length(insert_rows) - batch_new

      count =
        DumpSync.chunked_insert(Relation, insert_rows,
          on_conflict: {:replace, [:relation_type, :is_official, :updated_at]},
          conflict_target: [:visual_novel_id, :related_vn_id]
        )

      do_relation_batches(
        vndb,
        vn_mapping,
        existing_pairs,
        protected_vn_uuids,
        offset + @batch_size,
        acc + count,
        new_acc + batch_new,
        updated_acc + batch_updated,
        ids_acc ++ batch_new_ids
      )
    end
  end

  defp count_relations(vndb) do
    [[count]] = DumpSync.query_vndb_raw!(vndb, "SELECT COUNT(*) FROM vn_relations")
    count
  end

  defp load_existing_pairs do
    from(r in Relation, select: {r.visual_novel_id, r.related_vn_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
