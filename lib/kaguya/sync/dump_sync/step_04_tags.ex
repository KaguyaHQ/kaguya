defmodule Kaguya.Sync.DumpSync.Tags do
  @moduledoc """
  Syncs tag definitions, tag parent hierarchy, and VN-tag associations from VNDB dump.

  Tag definitions (~2,982 rows including parent tags),
  tag parents (~3,500 hierarchy rows),
  then VN-tag associations (aggregated from ~1.7M votes).
  """

  require Logger

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbFieldMapper
  alias Kaguya.Tags.Tag
  alias Kaguya.Tags.TagParent
  alias Kaguya.Utils.SlugUtils
  alias Kaguya.VisualNovels.VNTag

  def run(ctx) do
    if ctx[:target_vndb_ids] do
      # Targeted: skip global tag/parent sync (already up to date), only do VN-tag associations
      vn_tag_count = sync_vn_tags(ctx)
      {:ok, vn_tag_count}
    else
      useless_vndb_ids = compute_useless_vndb_tag_ids(ctx.vndb)
      Logger.info("Computed #{MapSet.size(useless_vndb_ids)} useless VNDB tag IDs to skip")

      tag_count = sync_tags(ctx, useless_vndb_ids)
      parent_count = sync_tag_parents(ctx)
      delete_useless_tags(useless_vndb_ids)
      vn_tag_count = sync_vn_tags(ctx)
      {:ok, tag_count + parent_count + vn_tag_count}
    end
  end

  # ── Tag Definitions ──────────────────────────────────────────────────────────

  defp sync_tags(%{vndb: vndb, dry_run: dry_run}, useless_vndb_ids) do
    Logger.info("Loading tags from VNDB dump...")

    tags =
      DumpSync.query_vndb!(vndb, """
      SELECT id, name, description, cat::text, defaultspoil
      FROM tags
      """)

    # Skip useless tags (descendants of Setting, Style, Plot, Character, Sexual Content)
    tags = Enum.reject(tags, fn t -> MapSet.member?(useless_vndb_ids, t.id) end)
    Logger.info("Found #{length(tags)} displayable tags in dump (after filtering useless)")

    if dry_run do
      Logger.info("[DRY RUN] Would upsert #{length(tags)} tags")
      length(tags)
    else
      upsert_tags(tags)
    end
  end

  @tag_replace_fields [:name, :description, :category, :default_spoiler_level, :updated_at]

  defp upsert_tags(tags) do
    now = DumpSync.now()
    existing_vndb_tag_ids = load_existing_vndb_tag_ids()

    {existing_tags, new_tags} =
      Enum.split_with(tags, fn t -> MapSet.member?(existing_vndb_tag_ids, t.id) end)

    # Generate slugs for new tags
    new_slug_map = generate_tag_slugs(new_tags)

    # Insert new tags with real slugs
    new_rows = Enum.map(new_tags, &build_tag_row(&1, new_slug_map, now))

    new_count =
      DumpSync.chunked_insert(Tag, new_rows,
        on_conflict: :nothing,
        conflict_target: {:unsafe_fragment, "(vndb_tag_id) WHERE vndb_tag_id IS NOT NULL"}
      )

    # Update existing tags — only @tag_replace_fields, slug is never touched
    existing_rows = Enum.map(existing_tags, &build_tag_row(&1, %{}, now))

    existing_count =
      DumpSync.chunked_insert(Tag, existing_rows,
        on_conflict: {:replace, @tag_replace_fields},
        conflict_target: {:unsafe_fragment, "(vndb_tag_id) WHERE vndb_tag_id IS NOT NULL"}
      )

    new_ids =
      Enum.map(new_tags, fn t ->
        name = VndbFieldMapper.sanitize_utf8(t.name) || "Unknown"
        slug = Map.get(new_slug_map, t.id, "—")
        %{id: t.id, name: name, slug: slug}
      end)

    Report.record(:tags, new_count, existing_count, new_ids)

    count = new_count + existing_count
    Logger.info("Upserted #{count} tags (#{new_count} new, #{existing_count} updated)")
    count
  end

  defp build_tag_row(t, slug_map, now) do
    vndb_tag_id = t.id

    # New tags: real slug from slug_map, inserted via on_conflict: :nothing.
    # Existing tags: called with empty slug_map, so falls back to UUID placeholder.
    # Placeholder satisfies NOT NULL but is discarded — existing path uses
    # on_conflict: {:replace, @tag_replace_fields} which excludes :slug.
    slug = Map.get(slug_map, vndb_tag_id) || UUIDv7.generate()

    %{
      id: UUIDv7.generate(),
      vndb_tag_id: vndb_tag_id,
      name: VndbFieldMapper.sanitize_utf8(t.name) || "Unknown Tag",
      description: VndbFieldMapper.clean_description(t.description),
      category: map_category(t.cat),
      default_spoiler_level: map_default_spoiler(t.defaultspoil),
      slug: slug,
      source: "vndb",
      inserted_at: now,
      updated_at: now
    }
  end

  defp generate_tag_slugs([]), do: %{}

  defp generate_tag_slugs(new_tags) do
    slug_items =
      Enum.map(new_tags, fn t ->
        %{title: VndbFieldMapper.sanitize_utf8(t.name) || "tag-#{t.id}", tag: t}
      end)

    slugged = SlugUtils.build_unique_slugs(slug_items, Tag, :slug, & &1.title)
    Map.new(slugged, fn s -> {s.tag.id, s._slug} end)
  end

  # ── Tag Parent Hierarchy ─────────────────────────────────────────────────────

  defp sync_tag_parents(%{vndb: vndb, dry_run: dry_run}) do
    Logger.info("Loading tag parent hierarchy from VNDB dump...")

    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT id, parent, main
      FROM tags_parents
      """)

    Logger.info("Found #{length(rows)} tag parent relationships in dump")

    if dry_run do
      Logger.info("[DRY RUN] Would upsert #{length(rows)} tag parent relationships")
      length(rows)
    else
      upsert_tag_parents(rows)
    end
  end

  defp upsert_tag_parents(rows) do
    # Load fresh tag mapping since tags were just synced
    tag_mapping = DumpSync.load_tag_mapping()

    valid_rows =
      Enum.flat_map(rows, fn r ->
        with tag_uuid when not is_nil(tag_uuid) <- Map.get(tag_mapping, r.id),
             parent_uuid when not is_nil(parent_uuid) <- Map.get(tag_mapping, r.parent) do
          [
            %{
              tag_id: tag_uuid,
              parent_tag_id: parent_uuid,
              is_main: r.main
            }
          ]
        else
          _ -> []
        end
      end)

    count =
      DumpSync.chunked_insert(TagParent, valid_rows,
        on_conflict: {:replace, [:is_main]},
        conflict_target: [:tag_id, :parent_tag_id]
      )

    Report.record(:tag_parents, count, 0)
    Logger.info("Upserted #{count} tag parent relationships")
    count
  end

  # ── VN-Tag Associations ──────────────────────────────────────────────────────

  defp sync_vn_tags(%{vndb: vndb, dry_run: dry_run} = ctx) do
    target_ids = ctx[:target_vndb_ids]
    Logger.info("Loading VN-tag associations from VNDB dump...")

    # Load fresh mappings since tags may have just been synced
    tag_mapping = DumpSync.load_tag_mapping()
    vn_mapping = DumpSync.load_vn_mapping()

    Logger.info("Tag mapping: #{map_size(tag_mapping)}, VN mapping: #{map_size(vn_mapping)}")

    # Aggregate individual votes into per-(tag, vid) scores.
    # Full sync loads all at once (~948K rows, 50–80MB — acceptable).
    # Targeted import scopes to specific VNs.
    rows =
      if target_ids do
        phs = DumpSync.placeholders(target_ids)

        DumpSync.query_vndb!(
          vndb,
          """
          SELECT tag, vid,
                 ROUND(AVG(vote)::numeric, 1)::float as avg_score,
                 COUNT(*) as vote_count,
                 CASE WHEN COUNT(spoiler) = 0 THEN 0
                      WHEN AVG(spoiler) > 1.3 THEN 2
                      WHEN AVG(spoiler) > 0.4 THEN 1
                      ELSE 0
                 END as spoiler_level
          FROM tags_vn
          WHERE NOT ignore AND vid IN (#{phs})
          GROUP BY tag, vid
          HAVING AVG(vote) >= 1.0
          """,
          target_ids
        )
      else
        DumpSync.query_vndb!(vndb, """
        SELECT tag, vid,
               ROUND(AVG(vote)::numeric, 1)::float as avg_score,
               COUNT(*) as vote_count,
               CASE WHEN COUNT(spoiler) = 0 THEN 0
                    WHEN AVG(spoiler) > 1.3 THEN 2
                    WHEN AVG(spoiler) > 0.4 THEN 1
                    ELSE 0
               END as spoiler_level
        FROM tags_vn
        WHERE NOT ignore
        GROUP BY tag, vid
        HAVING AVG(vote) >= 1.0
        """)
      end

    Logger.info("Found #{length(rows)} aggregated VN-tag pairs in dump")

    # Skip VN-tag sync for user-edited VNs (user may have curated their tags)
    protected_vn_uuids = Kaguya.Sync.DumpSync.SyncProtection.user_edited_ids(:visual_novel)

    # Filter to pairs where both tag and VN exist in Kaguya.
    # Useless tags aren't in the DB so they're naturally excluded via tag_mapping.
    # Dump IDs are already prefixed strings ("g133", "v8213") matching our mapping keys.
    valid_rows =
      Enum.flat_map(rows, fn row ->
        with tag_uuid when not is_nil(tag_uuid) <- Map.get(tag_mapping, row.tag),
             vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, row.vid),
             false <- MapSet.member?(protected_vn_uuids, vn_uuid) do
          [Map.merge(row, %{tag_uuid: tag_uuid, vn_uuid: vn_uuid})]
        else
          _ -> []
        end
      end)

    Logger.info("#{length(valid_rows)} VN-tag pairs match Kaguya entities")

    if dry_run do
      Logger.info("[DRY RUN] Would upsert #{length(valid_rows)} VN-tag associations")
      length(valid_rows)
    else
      upsert_vn_tags(valid_rows)
    end
  end

  defp upsert_vn_tags(rows) do
    now = DumpSync.now()

    insert_rows =
      Enum.map(rows, fn r ->
        %{
          visual_novel_id: r.vn_uuid,
          tag_id: r.tag_uuid,
          vndb_avg_score: r.avg_score,
          vndb_vote_count: r.vote_count,
          spoiler_level: map_spoiler_level(r.spoiler_level),
          inserted_at: now,
          updated_at: now
        }
      end)

    count =
      DumpSync.chunked_insert(VNTag, insert_rows,
        on_conflict: {:replace, [:vndb_avg_score, :vndb_vote_count, :spoiler_level, :updated_at]},
        conflict_target: [:visual_novel_id, :tag_id]
      )

    Report.record(:vn_tags, count, 0)
    Logger.info("Upserted #{count} VN-tag associations")
    count
  end

  # ── Useless Tag Filtering ────────────────────────────────────────────────────

  # VNDB root tags whose descendants are not imported (Setting, Style, Plot, Character, Sexual Content)
  @useless_root_tags ~w(g22 g674 g24 g20 g23)
  # Override: keep these descendants despite being under useless roots
  @useful_override_tags ~w(g21 g709 g553 g304 g214 g235 g236 g542 g596 g693 g2223 g1056 g413 g1909 g3104 g134)
  # Explicit per-tag exclusions: tags not under a useless root that we still don't want.
  # g1955 = "Kissing Scene" (under Other Elements)
  @explicit_useless_tags ~w(g1955)

  @doc """
  Static list of explicitly-excluded VNDB tag IDs.
  Available without a VNDB dump connection, for partial-sync paths that auto-create tags.
  """
  def explicit_useless_tags, do: @explicit_useless_tags

  @doc """
  Computes the set of useless VNDB tag IDs from the VNDB dump's tag hierarchy.
  These tags (descendants of useless roots, minus useful overrides, plus explicit exclusions) are never imported.
  """
  def compute_useless_vndb_tag_ids(vndb) do
    useless_roots = Enum.map_join(@useless_root_tags, ", ", &"'#{&1}'")
    useful_overrides = Enum.map_join(@useful_override_tags, ", ", &"'#{&1}'")

    rows =
      DumpSync.query_vndb_raw!(vndb, """
      WITH RECURSIVE useless_descendants AS (
        SELECT id FROM tags WHERE id IN (#{useless_roots})
        UNION
        SELECT tp.id FROM tags_parents tp
        JOIN useless_descendants ud ON tp.parent = ud.id
        WHERE tp.main = true
      ),
      useful_overrides AS (
        SELECT id FROM tags WHERE id IN (#{useful_overrides})
        UNION
        SELECT tp.id FROM tags_parents tp
        JOIN useful_overrides uo ON tp.parent = uo.id
        WHERE tp.main = true
      )
      SELECT id FROM useless_descendants
      WHERE id NOT IN (SELECT id FROM useful_overrides)
      """)

    from_hierarchy = rows |> Enum.map(fn [id] -> id end) |> MapSet.new()
    MapSet.union(from_hierarchy, MapSet.new(@explicit_useless_tags))
  end

  @doc """
  Deletes any tags in the Kaguya DB that match useless VNDB tag IDs.
  FK cascades handle cleanup of tag_parents, vn_tags, and vn_tag_votes.
  Called after tag_parents sync so the hierarchy is up to date.
  """
  def delete_useless_tags(useless_vndb_ids) do
    import Ecto.Query

    useless_ids = MapSet.to_list(useless_vndb_ids)

    if useless_ids != [] do
      {deleted, _} =
        from(t in Tag, where: t.vndb_tag_id in ^useless_ids)
        |> Kaguya.Repo.delete_all()

      Logger.info("Deleted #{deleted} useless tags from Kaguya DB")
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp load_existing_vndb_tag_ids do
    import Ecto.Query

    from(t in Tag, where: not is_nil(t.vndb_tag_id), select: t.vndb_tag_id)
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end

  # VNDB dump cat values → Ecto.Enum atoms
  defp map_category("cont"), do: :content
  defp map_category("ero"), do: :sexual
  defp map_category("tech"), do: :technical
  defp map_category(_), do: nil

  # VNDB dump defaultspoil → Ecto.Enum atoms
  defp map_default_spoiler(0), do: :none
  defp map_default_spoiler(1), do: :minor
  defp map_default_spoiler(2), do: :major
  defp map_default_spoiler(_), do: :none

  # spoiler_level integer → Ecto.Enum atoms
  defp map_spoiler_level(0), do: :none
  defp map_spoiler_level(1), do: :minor
  defp map_spoiler_level(2), do: :major
  defp map_spoiler_level(nil), do: :none
  defp map_spoiler_level(_), do: :none
end
