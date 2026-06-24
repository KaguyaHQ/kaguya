defmodule Kaguya.Sync.DumpSync.Quotes do
  @moduledoc """
  Syncs VN quotes from VNDB dump.

  Upserts quotes with `score >= 0` (filters out downvoted quotes).
  Maps `vid` → VN UUID and `cid` → character UUID (nullable).
  """

  require Logger

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Characters.Quote

  def run(
        %{vndb: vndb, dry_run: dry_run, vn_mapping: vn_mapping, char_mapping: char_mapping} = ctx
      ) do
    target_ids = ctx[:target_vndb_ids]

    # Targeted import: reload mappings to include entities just inserted in prior steps
    # (entity steps share the initial mapping; VNs/characters from steps 01/03 aren't in it yet)
    {vn_mapping, char_mapping} =
      if target_ids do
        {DumpSync.load_vn_mapping(), DumpSync.load_char_mapping()}
      else
        {vn_mapping, char_mapping}
      end

    Logger.info("Loading quotes from VNDB dump...")

    rows =
      if target_ids do
        phs = DumpSync.placeholders(target_ids)

        DumpSync.query_vndb!(
          vndb,
          """
          SELECT id, vid, cid, score, quote
          FROM quotes
          WHERE score >= 0 AND vid IN (#{phs})
          """,
          target_ids
        )
      else
        DumpSync.query_vndb!(vndb, """
        SELECT id, vid, cid, score, quote
        FROM quotes
        WHERE score >= 0
        """)
      end

    Logger.info("Found #{length(rows)} quotes with score >= 0 in dump")

    # Filter to quotes where the VN exists in Kaguya (character is optional)
    valid_rows =
      Enum.flat_map(rows, fn row ->
        case Map.get(vn_mapping, row.vid) do
          nil ->
            []

          vn_uuid ->
            char_uuid = Map.get(char_mapping, row.cid)
            [Map.merge(row, %{vn_uuid: vn_uuid, char_uuid: char_uuid})]
        end
      end)

    Logger.info("#{length(valid_rows)} quotes match Kaguya VNs")

    if dry_run do
      Logger.info("[DRY RUN] Would upsert #{length(valid_rows)} quotes")
      {:ok, length(valid_rows)}
    else
      upsert_quotes(valid_rows)
    end
  end

  defp upsert_quotes(rows) do
    now = DumpSync.now()

    # Load existing vndb_ids to separate new vs updated
    existing_vndb_ids = load_existing_vndb_ids()

    {existing, new} =
      Enum.split_with(rows, fn r -> MapSet.member?(existing_vndb_ids, to_string(r.id)) end)

    insert_rows =
      Enum.map(new, fn r ->
        %{
          id: UUIDv7.generate(),
          vndb_id: to_string(r.id),
          visual_novel_id: r.vn_uuid,
          character_id: r.char_uuid,
          quote: r.quote,
          score: r.score,
          inserted_at: now,
          updated_at: now
        }
      end)

    new_count =
      DumpSync.chunked_insert(Quote, insert_rows,
        on_conflict: :nothing,
        conflict_target: [:vndb_id]
      )

    update_rows =
      Enum.map(existing, fn r ->
        %{
          id: UUIDv7.generate(),
          vndb_id: to_string(r.id),
          visual_novel_id: r.vn_uuid,
          character_id: r.char_uuid,
          quote: r.quote,
          score: r.score,
          inserted_at: now,
          updated_at: now
        }
      end)

    updated_count =
      DumpSync.chunked_insert(Quote, update_rows,
        on_conflict: {:replace, [:score, :character_id, :quote, :updated_at]},
        conflict_target: [:vndb_id]
      )

    new_ids =
      Enum.map(new, fn r ->
        %{id: to_string(r.id), vn: r.vid, quote: String.slice(r.quote || "", 0..60)}
      end)

    Report.record(:quotes, new_count, updated_count, new_ids)

    total = new_count + updated_count
    Logger.info("Upserted #{total} quotes (#{new_count} new, #{updated_count} updated)")
    {:ok, total}
  end

  defp load_existing_vndb_ids do
    import Ecto.Query

    from(q in Quote, where: not is_nil(q.vndb_id), select: q.vndb_id)
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end
end
