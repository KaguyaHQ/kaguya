defmodule Kaguya.Sync.DumpSync.PostSync do
  @moduledoc """
  Post-sync cleanup: recompute tag relevance, repopulate languages/platforms,
  regenerate series, re-index Meilisearch, clear caches.

  Step 10: Runs after all data is finalized.
  """

  require Logger

  alias Kaguya.Repo

  def run(%{dry_run: dry_run} = ctx) do
    target_ids = ctx[:target_vndb_ids]

    if dry_run do
      Logger.info(
        "[DRY RUN] Would recompute tag relevance, repopulate languages/platforms, regenerate series, reindex search, recompute content scores, and clear caches"
      )

      {:ok, :dry_run}
    else
      if target_ids do
        run_targeted_post_sync(target_ids)
      else
        run_full_post_sync()
      end
    end
  end

  defp run_targeted_post_sync(target_ids) do
    import Ecto.Query

    vn_uuids =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: vn.vndb_id in ^target_ids,
        select: vn.id
      )
      |> Repo.all()

    # 1. Repopulate languages/platforms/engines for target VNs
    Logger.info("Repopulating languages/platforms/engines for #{length(vn_uuids)} VN(s)...")
    repopulate_languages_for(target_ids)
    repopulate_platforms_for(target_ids)
    repopulate_engines_for(target_ids)

    # 2. Regenerate series (fast, handles our VN's series)
    Logger.info("Regenerating VN series...")
    {:ok, series_count} = Kaguya.VisualNovels.SeriesGenerator.regenerate()
    Logger.info("VN series regenerated: #{series_count} series")

    # 3. Reindex target VNs
    Logger.info("Re-indexing #{length(vn_uuids)} VN(s) in Meilisearch...")
    reindex_vns_by_ids(vn_uuids)

    # 4. Reindex characters linked to target VNs
    Logger.info("Re-indexing characters for target VNs...")
    reindex_characters_for_vns(vn_uuids)

    # 5. Recompute content score for target VNs (bulk sync writes bypass
    #    Revisions.submit_edit, so the on-edit recompute hook never fires).
    Logger.info("Recomputing content_score for #{length(vn_uuids)} target VN(s)...")
    %{scored: scored} = Kaguya.ContentScore.recompute_for_vns(vn_uuids)
    Logger.info("Content scores recomputed: #{scored}")

    # 6. Clear caches + re-warm explore-mode sections asynchronously
    KaguyaWeb.BrowseLive.TagSnapshot.invalidate()
    Kaguya.VisualNovels.BrowseSections.refresh()
    Logger.info("Caches cleared (explore sections re-warming)")

    {:ok, :done}
  end

  defp run_full_post_sync do
    # 1. Recompute tag relevance scores
    Logger.info("Recomputing tag relevance scores...")
    Kaguya.Tags.TagRelevance.recompute_all_vn_tags()
    Logger.info("Tag relevance recomputation complete")

    # 2. Repopulate VN languages from releases
    Logger.info("Repopulating VN languages...")
    lang_count = repopulate_languages()
    Logger.info("VN languages repopulated: #{lang_count} rows")

    # 3. Repopulate VN platforms from releases
    Logger.info("Repopulating VN platforms...")
    plat_count = repopulate_platforms()
    Logger.info("VN platforms repopulated: #{plat_count} rows")

    # 4. Repopulate VN engines from releases
    Logger.info("Repopulating VN engines...")
    engine_count = repopulate_engines()
    Logger.info("VN engines repopulated: #{engine_count} rows")

    # 5. Regenerate VN series from sequel relations
    Logger.info("Regenerating VN series...")
    {:ok, series_count} = Kaguya.VisualNovels.SeriesGenerator.regenerate()
    Logger.info("VN series regenerated: #{series_count} series")

    # 6. Configure Meilisearch index settings (searchable attributes, ranking)
    Logger.info("Configuring Meilisearch visual_novels index settings...")
    Kaguya.SearchIndex.configure_visual_novels_index()
    Logger.info("Configuring Meilisearch producers index settings...")
    Kaguya.SearchIndex.configure_producers_index()

    # 7. Re-index VNs in Meilisearch
    Logger.info("Re-indexing VNs in Meilisearch...")
    reindex_vns()
    Logger.info("VN re-indexing complete")

    # 8. Re-index characters in Meilisearch
    Logger.info("Re-indexing characters in Meilisearch...")
    reindex_characters()
    Logger.info("Character re-indexing complete")

    # 9. Re-index producers in Meilisearch
    Logger.info("Re-indexing producers in Meilisearch...")
    reindex_producers()
    Logger.info("Producer re-indexing complete")

    # 10. Recompute content score for every visible VN (bulk sync writes
    #     bypass Revisions.submit_edit, so the on-edit hook never fires).
    Logger.info("Recomputing content_score for the corpus...")
    %{scored: scored, not_found: not_found} = Kaguya.ContentScore.recompute_all()
    Logger.info("Content scores recomputed: scored=#{scored} not_found=#{not_found}")

    # 11. Clear caches + re-warm explore-mode sections asynchronously
    Logger.info("Clearing caches...")
    KaguyaWeb.BrowseLive.TagSnapshot.invalidate()
    Kaguya.VisualNovels.BrowseSections.refresh()
    Logger.info("Caches cleared (explore sections re-warming)")

    {:ok, :done}
  end

  # ── Languages & Platforms ─────────────────────────────────────────────────

  # Each rebuild is wrapped in a transaction so an interrupted run rolls back
  # to the previous data instead of leaving the table empty. The browse cache
  # is invalidated on success because filters reading from these tables would
  # otherwise return stale results until the 7-day TTL expires.

  defp repopulate_languages do
    {:ok, count} =
      Repo.transaction(fn ->
        Repo.query!("DELETE FROM vn_languages")

        %{num_rows: c} =
          Repo.query!("""
          INSERT INTO vn_languages (visual_novel_id, language)
          SELECT DISTINCT r.visual_novel_id, unnest(r.languages)
          FROM vn_releases r
          WHERE r.languages != '{}'
          ON CONFLICT DO NOTHING
          """)

        c
      end)

    Cachex.clear(:vn_browse_cache)
    Kaguya.VisualNovels.VNPageCache.clear_all()
    count
  end

  defp repopulate_platforms do
    {:ok, count} =
      Repo.transaction(fn ->
        Repo.query!("DELETE FROM vn_platforms")

        %{num_rows: c} =
          Repo.query!("""
          INSERT INTO vn_platforms (visual_novel_id, platform)
          SELECT DISTINCT r.visual_novel_id, unnest(r.platforms)
          FROM vn_releases r
          WHERE r.platforms != '{}'
          ON CONFLICT DO NOTHING
          """)

        c
      end)

    Cachex.clear(:vn_browse_cache)
    Kaguya.VisualNovels.VNPageCache.clear_all()
    count
  end

  defp repopulate_engines do
    {:ok, count} =
      Repo.transaction(fn ->
        Repo.query!("DELETE FROM vn_engines")

        %{num_rows: c} =
          Repo.query!("""
          INSERT INTO vn_engines (visual_novel_id, engine)
          SELECT DISTINCT r.visual_novel_id, r.engine
          FROM vn_releases r
          WHERE r.engine IS NOT NULL AND r.engine != ''
            AND r.official = true
          ON CONFLICT DO NOTHING
          """)

        c
      end)

    Cachex.clear(:vn_browse_cache)
    Kaguya.VisualNovels.VNPageCache.clear_all()
    count
  end

  # ── Search Reindex ────────────────────────────────────────────────────────

  defp reindex_vns do
    import Ecto.Query

    # Stream in ID-ordered batches to avoid loading all 59K+ VNs into memory
    stream_in_batches(
      Kaguya.VisualNovels.VisualNovel
      |> preload([:vn_titles, :vn_producers, vn_producers: :producer])
      |> order_by(:id),
      500,
      &Kaguya.SearchIndex.index_visual_novels/1
    )
  end

  defp reindex_characters do
    import Ecto.Query

    stream_in_batches(
      Kaguya.Characters.Character |> order_by(:id),
      500,
      &Kaguya.SearchIndex.index_characters/1
    )
  end

  defp reindex_producers do
    import Ecto.Query

    stream_in_batches(
      Kaguya.Producers.Producer |> order_by(:id),
      500,
      &Kaguya.SearchIndex.index_producers/1
    )
  end

  defp stream_in_batches(query, batch_size, index_fn) do
    import Ecto.Query

    do_batch(query, batch_size, index_fn, nil, 0)
  end

  defp do_batch(query, batch_size, index_fn, last_id, count) do
    import Ecto.Query

    page_query =
      if last_id do
        where(query, [r], r.id > ^last_id)
      else
        query
      end

    batch = page_query |> limit(^batch_size) |> Repo.all()

    if batch == [] do
      count
    else
      index_fn.(batch)
      new_last_id = List.last(batch).id
      do_batch(query, batch_size, index_fn, new_last_id, count + length(batch))
    end
  end

  # ── Targeted Helpers ─────────────────────────────────────────────────────

  # Scoped by vndb_id (text) via subquery — avoids UUID encoding issues with raw SQL params.
  # Mirrors the full-sync helpers but scoped instead of global DELETE + INSERT.

  defp repopulate_languages_for(target_ids) do
    Repo.query!(
      """
      INSERT INTO vn_languages (visual_novel_id, language)
      SELECT DISTINCT r.visual_novel_id, unnest(r.languages)
      FROM vn_releases r
      WHERE r.visual_novel_id IN (SELECT id FROM visual_novels WHERE vndb_id = ANY($1))
        AND r.languages != '{}'
      ON CONFLICT DO NOTHING
      """,
      [target_ids]
    )
  end

  defp repopulate_platforms_for(target_ids) do
    Repo.query!(
      """
      INSERT INTO vn_platforms (visual_novel_id, platform)
      SELECT DISTINCT r.visual_novel_id, unnest(r.platforms)
      FROM vn_releases r
      WHERE r.visual_novel_id IN (SELECT id FROM visual_novels WHERE vndb_id = ANY($1))
        AND r.platforms != '{}'
      ON CONFLICT DO NOTHING
      """,
      [target_ids]
    )
  end

  defp repopulate_engines_for(target_ids) do
    Repo.query!(
      """
      INSERT INTO vn_engines (visual_novel_id, engine)
      SELECT DISTINCT r.visual_novel_id, r.engine
      FROM vn_releases r
      WHERE r.visual_novel_id IN (SELECT id FROM visual_novels WHERE vndb_id = ANY($1))
        AND r.engine IS NOT NULL AND r.engine != ''
        AND r.official = true
      ON CONFLICT DO NOTHING
      """,
      [target_ids]
    )
  end

  defp reindex_vns_by_ids(vn_uuids) do
    import Ecto.Query

    vns =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: vn.id in ^vn_uuids,
        preload: [:vn_titles, :vn_producers, vn_producers: :producer]
      )
      |> Repo.all()

    Kaguya.SearchIndex.index_visual_novels(vns)
    Logger.info("Indexed #{length(vns)} VN(s)")
  end

  defp reindex_characters_for_vns(vn_uuids) do
    import Ecto.Query

    char_ids =
      from(vc in Kaguya.Characters.VNCharacter,
        where: vc.visual_novel_id in ^vn_uuids,
        select: vc.character_id
      )
      |> Repo.all()

    if char_ids != [] do
      chars = from(c in Kaguya.Characters.Character, where: c.id in ^char_ids) |> Repo.all()
      Kaguya.SearchIndex.index_characters(chars)
      Logger.info("Indexed #{length(chars)} character(s)")
    end
  end
end
