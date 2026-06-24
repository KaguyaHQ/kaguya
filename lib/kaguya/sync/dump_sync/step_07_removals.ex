defmodule Kaguya.Sync.DumpSync.Removals do
  @moduledoc """
  Detects and removes stale entities from Kaguya that no longer exist in the VNDB dump.

  Runs after all upserts so comparisons are against complete data.

  Three-phase execution:
  1. Analyze  — load dump + Kaguya data, compute stale sets
  2. Confirm  — display summary table, require user to type DELETE
  3. Execute  — batch-delete confirmed rows

  Cleanup order:
  1. Stale VN-tag rows
  2. Stale VN-character rows
  3. Stale VN-relation rows
  4. Stale VN-producer rows
  5. Stale tag-parent rows
  6. Producer/VN extlinks are preserved (local rows may share these tables)
  7. Stale release extlinks
  8. Stale releases (cascades remaining extlinks)
  9. Stale tags — VNDB-sourced only (FK CASCADE handles vn_tags + tag_parents)
  10. Orphaned characters (no VN junctions, VNDB-sourced only)
  11. Orphaned producers (cascade-deletes their extlinks, VNDB-sourced only)
  12. Removed VNs — delegates to `Kaguya.VisualNovels.Deletion` for full cleanup
      (CASCADE + user stats, notifications, favorites, blocklist, Meilisearch, R2, cache)
  """

  @max_stale_ratio 0.5

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbStorefrontMapper
  alias Kaguya.Tags.Tag
  alias Kaguya.Tags.TagParent
  alias Kaguya.Characters.{Character, VNCharacter, Quote}
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.{Release, ReleaseExtlink}
  alias Kaguya.VisualNovels.{Deletion, Relation, VNTag}

  def run(%{vndb: vndb, dry_run: dry_run, banned_ids: banned_ids} = _ctx) do
    Logger.info("Analyzing stale data...")

    # Reload mappings since earlier steps may have inserted new entities
    tag_mapping = DumpSync.load_tag_mapping()
    vn_mapping = DumpSync.load_vn_mapping()
    char_mapping = DumpSync.load_char_mapping()
    producer_mapping = DumpSync.load_producer_mapping()

    # Name caches for human-readable report details
    names = load_name_caches()

    # Phase 1: Analyze junction and entity removal candidates.
    # Orphans are analyzed AFTER junction deletions execute, so entities that
    # lose their last link during this pass are caught in the same run.
    primary_analyses = [
      {:vn_tags, "VN-tag pairs", analyze_vn_tags(vndb, tag_mapping, vn_mapping)},
      {:vn_characters, "VN-character pairs",
       analyze_vn_characters(vndb, char_mapping, vn_mapping)},
      {:vn_relations, "VN-relation pairs", analyze_vn_relations(vndb, vn_mapping)},
      {:vn_producers, "VN-producer pairs",
       analyze_vn_producers(vndb, producer_mapping, vn_mapping)},
      {:tag_parents, "Tag-parent pairs", analyze_tag_parents(vndb, tag_mapping)},
      {:producer_external_links, "Producer extlinks", analyze_producer_extlinks()},
      {:vn_external_links, "VN extlinks", analyze_vn_extlinks()},
      {:vn_release_extlinks, "Release extlinks", analyze_release_extlinks(vndb)},
      {:releases, "Releases", analyze_releases(vndb)},
      {:quotes, "Quotes", analyze_quotes(vndb)},
      {:tags, "Tags (VNDB-sourced)", analyze_tags(vndb)},
      {:removed_vns, "Removed VNs (CASCADE!)", analyze_removed_vns(vndb, banned_ids)}
    ]

    # Placeholder orphan analyses for the initial summary (pre-deletion counts)
    orphan_analyses = [
      {:orphaned_characters, "Orphaned characters", analyze_orphaned_characters()},
      {:orphaned_producers, "Orphaned producers", analyze_orphaned_producers()}
    ]

    all_analyses = primary_analyses ++ orphan_analyses

    # Phase 2: Display summary table
    display_summary(all_analyses)

    total_deletable =
      all_analyses
      |> Enum.filter(fn {_, _, a} -> a.safe and a.stale_count > 0 and a.delete_fn != nil end)
      |> Enum.reduce(0, fn {_, _, a}, acc -> acc + a.stale_count end)

    # Phase 3: Confirm & execute
    results =
      cond do
        dry_run ->
          Logger.info("DRY RUN — no deletions performed")
          record_all_removals(all_analyses, names)
          display_stale_samples(all_analyses, names)
          Map.new(all_analyses, fn {key, _, a} -> {key, a.stale_count} end)

        total_deletable == 0 ->
          Logger.info("Nothing to remove")
          Map.new(all_analyses, fn {key, _, _} -> {key, 0} end)

        not confirm_deletions(total_deletable) ->
          Logger.info("Removals cancelled by user")
          Map.new(all_analyses, fn {key, _, _} -> {key, 0} end)

        true ->
          Logger.info("Executing deletions...")

          # Execute primary deletions first (junctions, entities, VNs)
          primary_results =
            Map.new(primary_analyses, fn {key, _label, a} ->
              if a.safe and a.stale_count > 0 and a.delete_fn do
                Logger.info("  Deleting #{a.stale_count} #{key}...")
                {key, a.delete_fn.()}
              else
                {key, 0}
              end
            end)

          # Re-analyze orphans AFTER junction deletions so entities that just
          # lost their last link are caught in the same run
          Logger.info("  Re-analyzing orphans after junction removals...")

          fresh_orphan_analyses = [
            {:orphaned_characters, "Orphaned characters", analyze_orphaned_characters()},
            {:orphaned_producers, "Orphaned producers", analyze_orphaned_producers()}
          ]

          orphan_results =
            Map.new(fresh_orphan_analyses, fn {key, _label, a} ->
              if a.stale_count > 0 and a.delete_fn do
                Logger.info("  Deleting #{a.stale_count} #{key}...")
                {key, a.delete_fn.()}
              else
                {key, 0}
              end
            end)

          # Use fresh orphan analyses for reporting
          record_all_removals(primary_analyses ++ fresh_orphan_analyses, names)
          Map.merge(primary_results, orphan_results)
      end

    Logger.info("Removal step complete: #{inspect(results)}")
    {:ok, results}
  end

  # ── Analysis Functions ─────────────────────────────────────────────────────
  #
  # Each returns %{stale_count, kaguya_count, dump_size, safe, delete_fn, stale_rows}.
  # The delete_fn closure captures the stale data for deferred execution.
  # stale_rows are kept for report detail generation.

  defp analyze_vn_tags(vndb, tag_mapping, vn_mapping) do
    dump_pairs = load_dump_vn_tag_pairs(vndb, tag_mapping, vn_mapping)
    Logger.info("  VN-tags: dump has #{MapSet.size(dump_pairs)} valid pairs")

    kaguya_rows =
      from(vt in VNTag,
        join: t in assoc(vt, :tag),
        join: vn in assoc(vt, :visual_novel),
        where: not is_nil(t.vndb_tag_id) and not is_nil(vn.vndb_id),
        select: {vt.visual_novel_id, vt.tag_id, t.vndb_tag_id, vn.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_vn_uuid, _tag_uuid, vndb_tag_id, vn_vndb_id} ->
        not MapSet.member?(dump_pairs, {vndb_tag_id, vn_vndb_id})
      end)

    safe = safe_to_delete?(MapSet.size(dump_pairs), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        fn ->
          batch_delete_composite(stale, VNTag, fn {vn_uuid, tag_uuid, _, _} ->
            dynamic([vt], vt.visual_novel_id == ^vn_uuid and vt.tag_id == ^tag_uuid)
          end)
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_pairs),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_vn_characters(vndb, char_mapping, vn_mapping) do
    dump_pairs = load_dump_char_vn_pairs(vndb, char_mapping, vn_mapping)
    Logger.info("  VN-characters: dump has #{MapSet.size(dump_pairs)} pairs")

    kaguya_rows =
      from(vc in VNCharacter,
        join: c in assoc(vc, :character),
        join: vn in assoc(vc, :visual_novel),
        where: not is_nil(c.vndb_id) and not is_nil(vn.vndb_id),
        select: {vc.visual_novel_id, vc.character_id, c.vndb_id, vn.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_vn_uuid, _char_uuid, char_vndb_id, vn_vndb_id} ->
        not MapSet.member?(dump_pairs, {char_vndb_id, vn_vndb_id})
      end)

    safe = safe_to_delete?(MapSet.size(dump_pairs), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        fn ->
          batch_delete_composite(stale, VNCharacter, fn {vn_uuid, char_uuid, _, _} ->
            dynamic([vc], vc.visual_novel_id == ^vn_uuid and vc.character_id == ^char_uuid)
          end)
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_pairs),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_vn_relations(vndb, vn_mapping) do
    dump_pairs = load_dump_relation_pairs(vndb, vn_mapping)
    Logger.info("  VN-relations: dump has #{MapSet.size(dump_pairs)} pairs")

    kaguya_rows =
      from(vr in Relation,
        join: vn1 in assoc(vr, :visual_novel),
        join: vn2 in assoc(vr, :related_vn),
        where: not is_nil(vn1.vndb_id) and not is_nil(vn2.vndb_id),
        select: {vr.visual_novel_id, vr.related_vn_id, vn1.vndb_id, vn2.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_vn_uuid, _related_uuid, vn_vndb_id, related_vndb_id} ->
        not MapSet.member?(dump_pairs, {vn_vndb_id, related_vndb_id})
      end)

    safe = safe_to_delete?(MapSet.size(dump_pairs), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        fn ->
          batch_delete_composite(stale, Relation, fn {vn_uuid, related_uuid, _, _} ->
            dynamic([vr], vr.visual_novel_id == ^vn_uuid and vr.related_vn_id == ^related_uuid)
          end)
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_pairs),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_vn_producers(vndb, producer_mapping, vn_mapping) do
    dump_pairs = load_dump_vn_producer_pairs(vndb, producer_mapping, vn_mapping)
    Logger.info("  VN-producers: dump has #{MapSet.size(dump_pairs)} valid pairs")

    kaguya_rows =
      from(vp in VNProducer,
        join: p in assoc(vp, :producer),
        join: vn in assoc(vp, :visual_novel),
        where: not is_nil(p.vndb_id) and not is_nil(vn.vndb_id),
        select: {vp.visual_novel_id, vp.producer_id, p.vndb_id, vn.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_vn_uuid, _prod_uuid, prod_vndb_id, vn_vndb_id} ->
        not MapSet.member?(dump_pairs, {prod_vndb_id, vn_vndb_id})
      end)

    safe = safe_to_delete?(MapSet.size(dump_pairs), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        fn ->
          batch_delete_composite(stale, VNProducer, fn {vn_uuid, prod_uuid, _, _} ->
            dynamic([vp], vp.visual_novel_id == ^vn_uuid and vp.producer_id == ^prod_uuid)
          end)
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_pairs),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_tag_parents(vndb, tag_mapping) do
    dump_pairs = load_dump_tag_parent_pairs(vndb, tag_mapping)
    Logger.info("  Tag-parents: dump has #{MapSet.size(dump_pairs)} valid pairs")

    kaguya_rows =
      from(tp in TagParent,
        join: t in assoc(tp, :tag),
        join: p in assoc(tp, :parent_tag),
        where: not is_nil(t.vndb_tag_id) and not is_nil(p.vndb_tag_id),
        select: {tp.tag_id, tp.parent_tag_id, t.vndb_tag_id, p.vndb_tag_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_tag_uuid, _parent_uuid, tag_vndb_id, parent_vndb_id} ->
        not MapSet.member?(dump_pairs, {tag_vndb_id, parent_vndb_id})
      end)

    safe = safe_to_delete?(MapSet.size(dump_pairs), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        fn ->
          batch_delete_composite(stale, TagParent, fn {tag_uuid, parent_uuid, _, _} ->
            dynamic([tp], tp.tag_id == ^tag_uuid and tp.parent_tag_id == ^parent_uuid)
          end)
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_pairs),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_producer_extlinks do
    Logger.info("  Producer extlinks: preservation mode enabled; skipping stale-link deletion")

    %{
      stale_count: 0,
      kaguya_count: nil,
      dump_size: nil,
      safe: true,
      delete_fn: nil,
      stale_rows: []
    }
  end

  defp analyze_vn_extlinks do
    Logger.info("  VN extlinks: preservation mode enabled; skipping stale-link deletion")

    %{
      stale_count: 0,
      kaguya_count: nil,
      dump_size: nil,
      safe: true,
      delete_fn: nil,
      stale_rows: []
    }
  end

  defp analyze_release_extlinks(vndb) do
    dump_triples = load_dump_release_extlink_triples(vndb)
    Logger.info("  Release extlinks: dump has #{MapSet.size(dump_triples)} valid triples")

    kaguya_rows =
      from(re in ReleaseExtlink,
        join: r in assoc(re, :vn_release),
        where: not is_nil(r.vndb_id),
        select: {re.id, r.vndb_id, re.site, re.url}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_id, release_vndb_id, site, url} ->
        not MapSet.member?(dump_triples, {release_vndb_id, site, url})
      end)

    safe = safe_to_delete?(MapSet.size(dump_triples), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        stale_ids = Enum.map(stale, fn {id, _, _, _} -> id end)
        fn -> batch_delete_by_ids(stale_ids, ReleaseExtlink) end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_triples),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_releases(vndb) do
    dump_release_ids =
      DumpSync.query_vndb_raw!(vndb, "SELECT id FROM releases")
      |> Enum.map(fn [id] -> id end)
      |> MapSet.new()

    # Also load superseded release IDs — these should be removed even though
    # they still exist in the dump, because a newer version replaces them
    superseded_ids = Kaguya.Sync.DumpSync.Releases.load_superseded_release_ids(vndb)

    Logger.info(
      "  Releases: dump has #{MapSet.size(dump_release_ids)}, #{MapSet.size(superseded_ids)} superseded"
    )

    kaguya_rows =
      from(r in Release,
        where: not is_nil(r.vndb_id),
        select: {r.id, r.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_uuid, vndb_id} ->
        not MapSet.member?(dump_release_ids, vndb_id) or MapSet.member?(superseded_ids, vndb_id)
      end)

    safe = safe_to_delete?(MapSet.size(dump_release_ids), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        stale_ids = Enum.map(stale, fn {id, _} -> id end)
        fn -> batch_delete_by_ids(stale_ids, Release) end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_release_ids),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_quotes(vndb) do
    dump_quote_ids =
      DumpSync.query_vndb_raw!(vndb, "SELECT id FROM quotes WHERE score >= 0")
      |> Enum.map(fn [id] -> to_string(id) end)
      |> MapSet.new()

    Logger.info("  Quotes: dump has #{MapSet.size(dump_quote_ids)} (score >= 0)")

    kaguya_rows =
      from(q in Quote,
        where: not is_nil(q.vndb_id),
        select: {q.id, q.vndb_id}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_uuid, vndb_id} ->
        not MapSet.member?(dump_quote_ids, vndb_id)
      end)

    safe = safe_to_delete?(MapSet.size(dump_quote_ids), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        stale_ids = Enum.map(stale, fn {id, _} -> id end)
        fn -> batch_delete_by_ids(stale_ids, Quote) end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_quote_ids),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_tags(vndb) do
    dump_tag_ids =
      DumpSync.query_vndb_raw!(vndb, "SELECT id FROM tags")
      |> Enum.map(fn [id] -> id end)
      |> MapSet.new()

    Logger.info("  Tags: dump has #{MapSet.size(dump_tag_ids)}")

    kaguya_rows =
      from(t in Tag,
        where: t.source == "vndb" and not is_nil(t.vndb_tag_id),
        select: {t.id, t.vndb_tag_id, t.name}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_id, vndb_tag_id, _name} ->
        not MapSet.member?(dump_tag_ids, vndb_tag_id)
      end)

    if stale != [] do
      Enum.each(Enum.take(stale, 20), fn {_id, vndb_tag_id, name} ->
        Logger.info("    Stale tag: #{vndb_tag_id} — #{name}")
      end)

      if length(stale) > 20, do: Logger.info("    ... and #{length(stale) - 20} more")
    end

    safe = safe_to_delete?(MapSet.size(dump_tag_ids), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        stale_ids = Enum.map(stale, fn {id, _, _} -> id end)
        # FK CASCADE handles vn_tags and tag_parents cleanup
        fn -> batch_delete_by_ids(stale_ids, Tag) end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_tag_ids),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  defp analyze_orphaned_characters do
    orphaned =
      from(c in Character,
        left_join: vc in VNCharacter,
        on: vc.character_id == c.id,
        where: is_nil(vc.character_id) and not is_nil(c.vndb_id),
        select: {c.id, c.vndb_id, c.name}
      )
      |> Repo.all()

    Logger.info("  Orphaned characters: #{length(orphaned)}")

    delete_fn =
      if orphaned != [] do
        ids = Enum.map(orphaned, &elem(&1, 0))
        fn -> batch_delete_by_ids(ids, Character) end
      end

    %{
      stale_count: length(orphaned),
      kaguya_count: nil,
      dump_size: nil,
      safe: true,
      delete_fn: delete_fn,
      stale_rows: orphaned
    }
  end

  defp analyze_orphaned_producers do
    orphaned =
      from(p in Producer,
        left_join: vp in assoc(p, :vn_producers),
        where: is_nil(vp.producer_id) and not is_nil(p.vndb_id),
        select: {p.id, p.vndb_id, p.name}
      )
      |> Repo.all()

    Logger.info("  Orphaned producers: #{length(orphaned)}")

    delete_fn =
      if orphaned != [] do
        ids = Enum.map(orphaned, &elem(&1, 0))
        fn -> batch_delete_by_ids(ids, Producer) end
      end

    %{
      stale_count: length(orphaned),
      kaguya_count: nil,
      dump_size: nil,
      safe: true,
      delete_fn: delete_fn,
      stale_rows: orphaned
    }
  end

  # ── Removed VNs ─────────────────────────────────────────────────────────────
  # Uses the shared Deletion module for full cleanup: CASCADE delete + user stats,
  # notifications, favorites, Meilisearch, R2 files, caches, and blocklist.

  defp analyze_removed_vns(vndb, banned_ids) do
    dump_vn_ids =
      DumpSync.query_vndb_raw!(vndb, "SELECT id FROM vn")
      |> Enum.map(fn [id] -> id end)
      |> MapSet.new()

    Logger.info("  Removed VNs: dump has #{MapSet.size(dump_vn_ids)}")

    kaguya_rows =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: not is_nil(vn.vndb_id),
        select: {vn.id, vn.vndb_id, vn.title}
      )
      |> Repo.all()

    stale =
      Enum.filter(kaguya_rows, fn {_id, vndb_id, _title} ->
        not MapSet.member?(dump_vn_ids, vndb_id) and not MapSet.member?(banned_ids, vndb_id)
      end)

    if stale != [] do
      Logger.warning("Found #{length(stale)} VNs in Kaguya not in dump:")

      Enum.each(Enum.take(stale, 20), fn {_id, vndb_id, title} ->
        Logger.warning("  #{vndb_id}: #{title}")
      end)

      if length(stale) > 20, do: Logger.warning("  ... and #{length(stale) - 20} more")
    end

    safe = safe_to_delete?(MapSet.size(dump_vn_ids), length(kaguya_rows), length(stale))

    delete_fn =
      if safe and stale != [] do
        stale_ids = Enum.map(stale, fn {id, _, _} -> id end)
        reasons = Map.new(stale, fn {id, _vndb_id, _title} -> {id, "removed from VNDB dump"} end)

        fn ->
          case Deletion.delete_vns(stale_ids, reasons: reasons, skip_blocklist: true) do
            {:ok, result} ->
              result.deleted_vns

            {:error, reason} ->
              Logger.error("VN deletion failed: #{inspect(reason)}")
              0
          end
        end
      end

    %{
      stale_count: length(stale),
      kaguya_count: length(kaguya_rows),
      dump_size: MapSet.size(dump_vn_ids),
      safe: safe,
      delete_fn: delete_fn,
      stale_rows: stale
    }
  end

  # ── Name Caches & Report ─────────────────────────────────────────────────

  defp load_name_caches do
    %{
      vn:
        from(v in Kaguya.VisualNovels.VisualNovel,
          where: not is_nil(v.vndb_id),
          select: {v.id, {v.title, v.slug}}
        )
        |> Repo.all()
        |> Map.new(),
      tag:
        from(t in Tag, where: not is_nil(t.vndb_tag_id), select: {t.id, {t.name, t.slug}})
        |> Repo.all()
        |> Map.new(),
      char:
        from(c in Character, where: not is_nil(c.vndb_id), select: {c.id, {c.name, c.slug}})
        |> Repo.all()
        |> Map.new(),
      producer:
        from(p in Producer, where: not is_nil(p.vndb_id), select: {p.id, {p.name, p.slug}})
        |> Repo.all()
        |> Map.new()
    }
  end

  defp record_all_removals(analyses, names) do
    Enum.each(analyses, fn {key, _label, a} ->
      if a.stale_count > 0 do
        details = build_removal_details(key, a.stale_rows, names)
        Report.record_removal(key, a.stale_count, details)
      end
    end)
  end

  defp build_removal_details(:vn_tags, rows, names) do
    Enum.map(rows, fn {vn_uuid, tag_uuid, tag_vndb, vn_vndb} ->
      {vn_name, vn_slug} = name_slug(names.vn, vn_uuid)
      {tag_name, tag_slug} = name_slug(names.tag, tag_uuid)

      %{
        id: "#{tag_vndb} + #{vn_vndb}",
        tag: tag_name,
        tag_slug: tag_slug,
        vn: vn_name,
        vn_slug: vn_slug
      }
    end)
  end

  defp build_removal_details(:vn_characters, rows, names) do
    Enum.map(rows, fn {vn_uuid, char_uuid, char_vndb, vn_vndb} ->
      {vn_name, vn_slug} = name_slug(names.vn, vn_uuid)
      {char_name, char_slug} = name_slug(names.char, char_uuid)

      %{
        id: "#{char_vndb} + #{vn_vndb}",
        character: char_name,
        char_slug: char_slug,
        vn: vn_name,
        vn_slug: vn_slug
      }
    end)
  end

  defp build_removal_details(:vn_relations, rows, names) do
    Enum.map(rows, fn {vn1_uuid, vn2_uuid, vn1_vndb, vn2_vndb} ->
      {vn1_name, vn1_slug} = name_slug(names.vn, vn1_uuid)
      {vn2_name, vn2_slug} = name_slug(names.vn, vn2_uuid)

      %{
        id: "#{vn1_vndb} → #{vn2_vndb}",
        vn: vn1_name,
        vn_slug: vn1_slug,
        related: vn2_name,
        related_slug: vn2_slug
      }
    end)
  end

  defp build_removal_details(:vn_producers, rows, names) do
    Enum.map(rows, fn {vn_uuid, prod_uuid, prod_vndb, vn_vndb} ->
      {vn_name, vn_slug} = name_slug(names.vn, vn_uuid)
      {prod_name, prod_slug} = name_slug(names.producer, prod_uuid)

      %{
        id: "#{prod_vndb} + #{vn_vndb}",
        producer: prod_name,
        producer_slug: prod_slug,
        vn: vn_name,
        vn_slug: vn_slug
      }
    end)
  end

  defp build_removal_details(:tag_parents, rows, names) do
    Enum.map(rows, fn {tag_uuid, parent_uuid, tag_vndb, parent_vndb} ->
      {tag_name, tag_slug} = name_slug(names.tag, tag_uuid)
      {parent_name, parent_slug} = name_slug(names.tag, parent_uuid)

      %{
        id: "#{tag_vndb} → #{parent_vndb}",
        tag: tag_name,
        tag_slug: tag_slug,
        parent: parent_name,
        parent_slug: parent_slug
      }
    end)
  end

  defp build_removal_details(:producer_external_links, rows, names) do
    Enum.map(rows, fn {prod_uuid, site, prod_vndb} ->
      {prod_name, prod_slug} = name_slug(names.producer, prod_uuid)
      %{id: "#{prod_vndb} #{site}", producer: prod_name, producer_slug: prod_slug}
    end)
  end

  defp build_removal_details(:vn_external_links, rows, names) do
    Enum.map(rows, fn {vn_uuid, site, vn_vndb} ->
      {vn_name, vn_slug} = name_slug(names.vn, vn_uuid)
      %{id: "#{vn_vndb} #{site}", vn: vn_name, vn_slug: vn_slug}
    end)
  end

  defp build_removal_details(:vn_release_extlinks, rows, _names) do
    Enum.map(rows, fn {_id, release_vndb, site, url} ->
      %{id: "#{release_vndb} #{site}", url: url}
    end)
  end

  defp build_removal_details(:releases, rows, _names) do
    Enum.map(rows, fn {_uuid, vndb_id} ->
      %{id: vndb_id}
    end)
  end

  defp build_removal_details(:quotes, rows, _names) do
    Enum.map(rows, fn {_uuid, vndb_id} ->
      %{id: vndb_id}
    end)
  end

  defp build_removal_details(:tags, rows, names) do
    Enum.map(rows, fn {id, vndb_tag_id, _name} ->
      {name, slug} = name_slug(names.tag, id)
      %{id: vndb_tag_id, name: name, slug: slug}
    end)
  end

  defp build_removal_details(:orphaned_characters, rows, names) do
    Enum.map(rows, fn {id, vndb_id, _name} ->
      {name, slug} = name_slug(names.char, id)
      %{id: vndb_id, name: name, slug: slug}
    end)
  end

  defp build_removal_details(:orphaned_producers, rows, names) do
    Enum.map(rows, fn {id, vndb_id, _name} ->
      {name, slug} = name_slug(names.producer, id)
      %{id: vndb_id, name: name, slug: slug}
    end)
  end

  defp build_removal_details(:removed_vns, rows, names) do
    Enum.map(rows, fn {id, vndb_id, _title} ->
      {name, slug} = name_slug(names.vn, id)
      %{id: vndb_id, name: name, slug: slug}
    end)
  end

  defp name_slug(cache, uuid) do
    case Map.get(cache, uuid) do
      {name, slug} -> {name || "?", slug || "—"}
      nil -> {"?", "—"}
    end
  end

  # ── Dump Loading ───────────────────────────────────────────────────────────

  defp load_dump_vn_tag_pairs(vndb, tag_mapping, vn_mapping) do
    rows =
      DumpSync.query_vndb_raw!(vndb, """
      SELECT tag, vid
      FROM tags_vn
      WHERE NOT ignore
      GROUP BY tag, vid
      HAVING AVG(vote) >= 1.0
      """)

    Enum.reduce(rows, MapSet.new(), fn [tag_id, vid], acc ->
      if Map.has_key?(tag_mapping, tag_id) and Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, {tag_id, vid})
      else
        acc
      end
    end)
  end

  defp load_dump_char_vn_pairs(vndb, char_mapping, vn_mapping) do
    rows = DumpSync.query_vndb_raw!(vndb, "SELECT id, vid FROM chars_vns")

    Enum.reduce(rows, MapSet.new(), fn [char_id, vid], acc ->
      if Map.has_key?(char_mapping, char_id) and Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, {char_id, vid})
      else
        acc
      end
    end)
  end

  defp load_dump_relation_pairs(vndb, vn_mapping) do
    rows = DumpSync.query_vndb_raw!(vndb, "SELECT id, vid FROM vn_relations")

    Enum.reduce(rows, MapSet.new(), fn [id, vid], acc ->
      if Map.has_key?(vn_mapping, id) and Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, {id, vid})
      else
        acc
      end
    end)
  end

  defp load_dump_vn_producer_pairs(vndb, producer_mapping, vn_mapping) do
    rows =
      DumpSync.query_vndb_raw!(vndb, """
      SELECT DISTINCT rp.pid, rv.vid
      FROM releases_producers rp
      JOIN releases_vn rv ON rv.id = rp.id
      """)

    Enum.reduce(rows, MapSet.new(), fn [pid, vid], acc ->
      if Map.has_key?(producer_mapping, pid) and Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, {pid, vid})
      else
        acc
      end
    end)
  end

  defp load_dump_tag_parent_pairs(vndb, tag_mapping) do
    rows = DumpSync.query_vndb_raw!(vndb, "SELECT id, parent FROM tags_parents")

    Enum.reduce(rows, MapSet.new(), fn [id, parent], acc ->
      if Map.has_key?(tag_mapping, id) and Map.has_key?(tag_mapping, parent) do
        MapSet.put(acc, {id, parent})
      else
        acc
      end
    end)
  end

  defp load_dump_release_extlink_triples(vndb) do
    rows =
      DumpSync.query_vndb_raw!(vndb, """
      SELECT re.id, e.site::text, e.value
      FROM releases_extlinks re
      JOIN extlinks e ON e.id = re.link
      """)

    Enum.reduce(rows, MapSet.new(), fn [release_id, site, value], acc ->
      if is_nil(value) do
        acc
      else
        url = VndbStorefrontMapper.build_url(site, to_string(value))

        # Mirror step_06: steam entries also generate a steamdb entry
        cond do
          is_nil(url) ->
            acc

          site == "steam" ->
            acc
            |> MapSet.put({release_id, site, url})
            |> MapSet.put({release_id, "steamdb", "https://steamdb.info/app/#{value}"})

          true ->
            MapSet.put(acc, {release_id, site, url})
        end
      end
    end)
  end

  # ── Summary Display ────────────────────────────────────────────────────────

  defp display_summary(analyses) do
    IO.puts("")

    IO.puts(
      "  #{String.pad_trailing("Entity", 24)} #{String.pad_leading("Kaguya", 10)} " <>
        "#{String.pad_leading("Dump", 10)} #{String.pad_leading("Stale", 10)} " <>
        "#{String.pad_leading("%", 7)} #{String.pad_leading("Status", 10)}"
    )

    IO.puts("  #{String.duplicate("~", 75)}")

    Enum.each(analyses, fn {_key, label, a} ->
      kaguya = if a.kaguya_count, do: format_number(a.kaguya_count), else: "—"
      dump = if a.dump_size, do: format_number(a.dump_size), else: "—"
      stale = format_number(a.stale_count)

      pct =
        if is_integer(a.kaguya_count) and a.kaguya_count > 0 and a.stale_count > 0 do
          "#{Float.round(a.stale_count / a.kaguya_count * 100, 1)}%"
        else
          "—"
        end

      status =
        cond do
          a.stale_count == 0 -> "—"
          not a.safe -> "BLOCKED"
          true -> "OK"
        end

      IO.puts(
        "  #{String.pad_trailing(label, 24)} #{String.pad_leading(kaguya, 10)} " <>
          "#{String.pad_leading(dump, 10)} #{String.pad_leading(stale, 10)} " <>
          "#{String.pad_leading(pct, 7)} #{String.pad_leading(status, 10)}"
      )
    end)

    total = Enum.reduce(analyses, 0, fn {_, _, a}, acc -> acc + a.stale_count end)

    blocked =
      analyses
      |> Enum.filter(fn {_, _, a} -> not a.safe and a.stale_count > 0 end)
      |> Enum.reduce(0, fn {_, _, a}, acc -> acc + a.stale_count end)

    IO.puts("  #{String.duplicate("~", 75)}")

    IO.puts(
      "  #{String.pad_trailing("Total", 24)} #{String.pad_leading("", 10)} " <>
        "#{String.pad_leading("", 10)} #{String.pad_leading(format_number(total), 10)}"
    )

    if blocked > 0 do
      IO.puts(
        "  #{String.pad_trailing("Blocked (safety)", 24)} #{String.pad_leading("", 10)} " <>
          "#{String.pad_leading("", 10)} #{String.pad_leading(format_number(blocked), 10)}"
      )
    end

    IO.puts("")
  end

  # ── Stale Samples (dry-run detail output) ─────────────────────────────────

  @sample_limit 20

  defp display_stale_samples(analyses, names) do
    Enum.each(analyses, fn {key, label, a} ->
      if a.stale_count > 0 do
        sample_rows = Enum.take(a.stale_rows, @sample_limit)
        samples = build_removal_details(key, sample_rows, names)

        IO.puts("\n── #{label} (#{format_number(a.stale_count)} stale) ──")

        Enum.each(samples, fn detail ->
          id = Map.get(detail, :id, "?")
          rest = detail |> Map.drop([:id]) |> Enum.sort_by(&elem(&1, 0))

          fields =
            Enum.map_join(rest, "  ", fn {k, v} -> "#{k}: #{v || "—"}" end)

          IO.puts("  #{id}  #{fields}")
        end)

        remaining = a.stale_count - length(samples)
        if remaining > 0, do: IO.puts("  ... and #{format_number(remaining)} more")
      end
    end)

    IO.puts("")
  end

  # ── Confirmation ───────────────────────────────────────────────────────────

  defp confirm_deletions(total) do
    IO.puts("This will permanently delete #{format_number(total)} rows.")

    case IO.gets("Type DELETE to confirm, or press Enter to cancel: ") do
      :eof -> false
      response -> String.trim(response) == "DELETE"
    end
  end

  # ── Safety Check ───────────────────────────────────────────────────────────

  # Returns true if it's safe to proceed with deletions.
  # Blocks if the dump set is empty (connection issue) or if more than 50% of
  # Kaguya rows would be deleted (likely a bad dump or query mismatch).
  defp safe_to_delete?(_dump_size, _kaguya_count, 0), do: true
  defp safe_to_delete?(0, _kaguya_count, _stale_count), do: false

  defp safe_to_delete?(_dump_size, kaguya_count, stale_count) do
    not (kaguya_count > 100 and stale_count / kaguya_count > @max_stale_ratio)
  end

  # ── Batch Deletion ─────────────────────────────────────────────────────────

  # Batch-deletes rows from a composite-keyed table using chunked dynamic OR clauses.
  # Much faster than one DELETE per row — generates a single SQL statement per chunk.
  defp batch_delete_composite(stale_rows, schema, condition_fn) do
    stale_rows
    |> Enum.chunk_every(200)
    |> Enum.reduce(0, fn chunk, acc ->
      conditions =
        Enum.reduce(chunk, dynamic(false), fn row, dyn ->
          dynamic(^dyn or ^condition_fn.(row))
        end)

      {n, _} = from(s in schema, where: ^conditions) |> Repo.delete_all()
      acc + n
    end)
  end

  # Batch-deletes rows by primary key ID in chunks.
  defp batch_delete_by_ids(ids, schema) do
    ids
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {n, _} = Repo.delete_all(from(s in schema, where: s.id in ^chunk))
      acc + n
    end)
  end

  # ── Formatting ─────────────────────────────────────────────────────────────

  defp format_number(n) when is_integer(n) and n < 1000, do: Integer.to_string(n)

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
