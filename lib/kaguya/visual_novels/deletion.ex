defmodule Kaguya.VisualNovels.Deletion do
  @moduledoc """
  Shared VN deletion logic used by both `mix kaguya.delete_vns` and
  the dump sync removal step (step_07).

  ## Pipeline

  ### 1. Pre-Gather (`gather_affected_data/1`)
  Collects all affected data before CASCADE destroys child rows:
  user ratings/reviews by user, review comment IDs, VN image/screenshot IDs,
  orphaned characters/producers/series/tags, shelf/list item counts, notifications.

  ### 2. DB Transaction (single transaction, all-or-nothing)
    0. Records VNDB IDs in `banned_vndb_ids` blocklist (prevents re-import)
    1. Deletes VN rows (CASCADE handles ~20 child tables)
    2. Deletes orphaned characters (only those linked solely to the deleted VNs)
    3. Deletes orphaned producers (only those linked solely to the deleted VNs)
    4. Deletes orphaned series
    5. Re-verifies and deletes orphaned tags
    6. Adjusts user rating stats (vn_ratings_dist, vn_ratings_count, vn_average_rating)
    7. Adjusts user review counts (vn_reviews_count)
    8. Decrements shelf vns_count
    9. Decrements list vns_count
    10. Compacts ranked list positions to close gaps
    11. Cleans deleted VN IDs from users.favorite_visual_novels arrays
    12. (No-op — character_favorites is FK-cascaded, counter rides with character row)
    13. Deletes stale notifications (review + review comment)
    14. Deletes stale VN list notifications (broken cover URLs)
    15. Deletes orphaned user_activities (via metadata->>'vn_id')

  ### 3. Post-Transaction (idempotent, non-critical)
    * Removes VNs and orphaned characters from Meilisearch
    * Clears vn_browse_cache
    * Deletes R2 files (covers ×4 sizes, screenshots ×3, character images ×1)
  """

  import Ecto.Query

  alias Kaguya.Cdn
  alias Kaguya.Repo
  alias Kaguya.RatingDistribution
  alias Kaguya.SearchIndex
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Characters.Character
  alias Kaguya.Producers.Producer
  alias Kaguya.VisualNovels.Series
  alias Kaguya.VisualNovels.BannedVndbId
  alias Kaguya.Tags.Tag

  require Logger

  @doc """
  Full deletion pipeline: gather → execute transaction → post-transaction cleanup.

  Returns `{:ok, %{deleted_vns: n, ...}}` or `{:error, reason}`.

  ## Options

    * `:reasons` - `%{vn_id => reason}` map (default: all get "removed from VNDB dump")
    * `:skip_r2` - boolean, skip R2 file deletion (default: false)
    * `:skip_blocklist` - boolean, skip adding to banned_vndb_ids (default: false)
    * `:data`    - pre-gathered data from `gather_affected_data/1` (skips re-gathering)
  """
  def delete_vns(vn_ids, opts \\ []) when is_list(vn_ids) do
    if vn_ids == [] do
      {:ok, %{deleted_vns: 0}}
    else
      data = Keyword.get(opts, :data) || gather_affected_data(vn_ids)
      reasons = Keyword.get(opts, :reasons, default_reasons(vn_ids))
      skip_r2 = Keyword.get(opts, :skip_r2, false)
      skip_blocklist = Keyword.get(opts, :skip_blocklist, false)

      case execute_transaction(data, reasons, skip_blocklist) do
        {:ok, result} ->
          post_transaction_cleanup(data, skip_r2: skip_r2)
          {:ok, result}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Pre-deletion analysis: collects all affected data before CASCADE destroys child rows.

  Returns a map with all the data needed for the deletion transaction and summary display.
  """
  def gather_affected_data(vn_ids) when is_list(vn_ids) do
    Logger.info("Gathering affected data for #{length(vn_ids)} VNs...")

    vn_details =
      from(vn in VisualNovel,
        where: vn.id in ^vn_ids,
        select: %{
          id: vn.id,
          title: vn.title,
          slug: vn.slug,
          vndb_id: vn.vndb_id,
          ratings_count: vn.ratings_count,
          reviews_count: vn.reviews_count
        }
      )
      |> Repo.all()

    Logger.info("  Found #{length(vn_details)} VNs")

    # (a) Ratings by user
    ratings =
      from(r in "ratings",
        where: r.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        select: %{user_id: r.user_id, rating: r.rating}
      )
      |> Repo.all()
      |> Enum.map(fn r -> %{r | user_id: Ecto.UUID.cast!(r.user_id)} end)

    ratings_by_user = Enum.group_by(ratings, & &1.user_id)
    Logger.info("  Ratings: #{length(ratings)} (#{map_size(ratings_by_user)} users)")

    # (b) Reviews
    reviews =
      from(r in "reviews",
        where: r.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        select: %{id: r.id, user_id: r.user_id, visual_novel_id: r.visual_novel_id}
      )
      |> Repo.all()
      |> Enum.map(fn r -> %{r | user_id: Ecto.UUID.cast!(r.user_id)} end)

    review_ids = Enum.map(reviews, & &1.id)
    reviews_by_user = Enum.group_by(reviews, & &1.user_id)
    Logger.info("  Reviews: #{length(reviews)} (#{map_size(reviews_by_user)} users)")

    # (b2) Review comment IDs (for notification cleanup)
    review_comment_ids =
      if review_ids != [] do
        from(rc in "review_comments", where: rc.review_id in ^review_ids, select: rc.id)
        |> Repo.all()
      else
        []
      end

    Logger.info("  Review comments: #{length(review_comment_ids)}")

    # (c) VN images
    vn_image_ids =
      from(i in "vn_images",
        where: i.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        select: i.id
      )
      |> Repo.all()
      |> Enum.map(&Ecto.UUID.cast!/1)

    # (d) VN screenshots
    vn_screenshot_ids =
      from(s in "vn_screenshots",
        where: s.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        select: s.id
      )
      |> Repo.all()
      |> Enum.map(&Ecto.UUID.cast!/1)

    Logger.info(
      "  Images: #{length(vn_image_ids)} covers, #{length(vn_screenshot_ids)} screenshots"
    )

    # (e) Orphaned characters
    orphaned_character_tuples =
      from(c in Character,
        join: vc in "vn_characters",
        on: vc.character_id == c.id,
        where: vc.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        where:
          fragment(
            "NOT EXISTS (SELECT 1 FROM vn_characters vc2 WHERE vc2.character_id = ? AND vc2.visual_novel_id != ALL(?))",
            c.id,
            type(^vn_ids, {:array, Ecto.UUID})
          ),
        select: {c.id, c.primary_image_id, c.slug},
        distinct: true
      )
      |> Repo.all()

    orphaned_char_ids = Enum.map(orphaned_character_tuples, &elem(&1, 0))

    orphaned_char_image_ids =
      orphaned_character_tuples |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)

    orphaned_char_slugs = Enum.map(orphaned_character_tuples, &elem(&1, 2))

    # (f) Orphaned producers
    orphaned_producer_tuples =
      from(p in Producer,
        join: vp in "vn_producers",
        on: vp.producer_id == p.id,
        where: vp.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        where:
          fragment(
            "NOT EXISTS (SELECT 1 FROM vn_producers vp2 WHERE vp2.producer_id = ? AND vp2.visual_novel_id != ALL(?))",
            p.id,
            type(^vn_ids, {:array, Ecto.UUID})
          ),
        select: {p.id, p.slug},
        distinct: true
      )
      |> Repo.all()

    orphaned_producer_ids = Enum.map(orphaned_producer_tuples, &elem(&1, 0))
    orphaned_producer_slugs = Enum.map(orphaned_producer_tuples, &elem(&1, 1))

    # (g) Orphaned series
    orphaned_series_ids =
      from(s in Series,
        join: si in "vn_series_items",
        on: si.vn_series_id == s.id,
        where: si.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        where:
          fragment(
            "NOT EXISTS (SELECT 1 FROM vn_series_items si2 WHERE si2.vn_series_id = ? AND si2.visual_novel_id != ALL(?))",
            s.id,
            type(^vn_ids, {:array, Ecto.UUID})
          ),
        select: s.id,
        distinct: true
      )
      |> Repo.all()

    # (h) Candidate orphaned tags (will re-verify after cascade)
    candidate_orphaned_tag_ids =
      from(t in Tag,
        join: vt in "vn_tags",
        on: vt.tag_id == t.id,
        where: vt.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        where:
          fragment(
            "NOT EXISTS (SELECT 1 FROM vn_tags vt2 WHERE vt2.tag_id = ? AND vt2.visual_novel_id != ALL(?))",
            t.id,
            type(^vn_ids, {:array, Ecto.UUID})
          ),
        select: t.id,
        distinct: true
      )
      |> Repo.all()

    Logger.info(
      "  Orphans: #{length(orphaned_char_ids)} chars, #{length(orphaned_producer_ids)} producers, #{length(orphaned_series_ids)} series, #{length(candidate_orphaned_tag_ids)} tags (candidates)"
    )

    # (i) Shelf item counts
    shelf_counts =
      from(si in "shelf_items",
        where: si.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        group_by: si.shelf_id,
        select: {si.shelf_id, count(si.visual_novel_id)}
      )
      |> Repo.all()

    # (j) List item counts
    list_counts =
      from(li in "list_items",
        where: li.visual_novel_id in type(^vn_ids, {:array, Ecto.UUID}),
        group_by: li.list_id,
        select: {li.list_id, count(li.visual_novel_id)}
      )
      |> Repo.all()

    # (k) Ranked lists with items being deleted
    affected_list_ids = Enum.map(list_counts, &elem(&1, 0))

    ranked_list_ids =
      if affected_list_ids != [] do
        from(l in "lists",
          where: l.id in ^affected_list_ids and l.is_ranked == true,
          select: l.id
        )
        |> Repo.all()
      else
        []
      end

    Logger.info(
      "  Shelves: #{length(shelf_counts)}, Lists: #{length(list_counts)} (#{length(ranked_list_ids)} ranked)"
    )

    # Notification counts
    review_notif_count =
      if review_ids != [] do
        from(n in "notifications",
          where: n.entity_type == "review" and n.entity_id in ^review_ids
        )
        |> Repo.aggregate(:count)
      else
        0
      end

    comment_notif_count =
      if review_comment_ids != [] do
        from(n in "notifications",
          where: n.entity_type == "comment" and n.entity_id in ^review_comment_ids
        )
        |> Repo.aggregate(:count)
      else
        0
      end

    notification_count = review_notif_count + comment_notif_count

    # (l) VN list notifications with stale cover URLs
    vn_list_notif_count =
      if affected_list_ids != [] do
        from(n in "notifications",
          where: n.entity_type == "list" and n.entity_id in ^affected_list_ids
        )
        |> Repo.aggregate(:count)
      else
        0
      end

    Logger.info("  Notifications: #{notification_count} review, #{vn_list_notif_count} list")
    Logger.info("  Data gathering complete.")

    %{
      vn_ids: vn_ids,
      vn_details: vn_details,
      ratings_by_user: ratings_by_user,
      reviews_by_user: reviews_by_user,
      review_ids: review_ids,
      review_comment_ids: review_comment_ids,
      vn_image_ids: vn_image_ids,
      vn_screenshot_ids: vn_screenshot_ids,
      orphaned_char_ids: orphaned_char_ids,
      orphaned_char_image_ids: orphaned_char_image_ids,
      orphaned_char_slugs: orphaned_char_slugs,
      orphaned_producer_ids: orphaned_producer_ids,
      orphaned_producer_slugs: orphaned_producer_slugs,
      orphaned_series_ids: orphaned_series_ids,
      candidate_orphaned_tag_ids: candidate_orphaned_tag_ids,
      shelf_counts: shelf_counts,
      list_counts: list_counts,
      ranked_list_ids: ranked_list_ids,
      notification_count: notification_count,
      vn_list_notif_count: vn_list_notif_count
    }
  end

  # ──────────────────────────────
  # Transaction
  # ──────────────────────────────

  defp execute_transaction(data, reasons, skip_blocklist) do
    case Repo.transaction(fn -> execute_in_transaction(data, reasons, skip_blocklist) end,
           timeout: :infinity
         ) do
      {:ok, result} ->
        Logger.info("Transaction committed successfully.")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Deletion transaction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_in_transaction(data, reasons, skip_blocklist) do
    vn_ids = data.vn_ids

    # 0. Record deleted VNDB IDs for future import blocklist
    unless skip_blocklist do
      banned_at = DateTime.utc_now() |> DateTime.truncate(:second)

      blocklist_rows =
        data.vn_details
        |> Enum.filter(& &1.vndb_id)
        |> Enum.map(fn vn ->
          %{
            vndb_id: vn.vndb_id,
            title: vn.title,
            reason: Map.get(reasons, vn.id, "removed from VNDB dump"),
            banned_at: banned_at
          }
        end)

      if blocklist_rows != [] do
        Repo.insert_all(BannedVndbId, blocklist_rows, on_conflict: :nothing)
        Logger.info("  Recorded #{length(blocklist_rows)} VNDB IDs in blocklist")
      end
    end

    # 1. Nullify image FKs before CASCADE delete.
    #    visual_novels.primary_image_id → vn_images and
    #    visual_novels.featured_screenshot_id → vn_screenshots
    #    CASCADE will delete these image/screenshot rows (owned by the
    #    deleted VNs), but ANY VN referencing them — not just the ones
    #    being deleted — must have its FK nullified first.
    if data.vn_image_ids != [] do
      from(vn in VisualNovel, where: vn.primary_image_id in ^data.vn_image_ids)
      |> Repo.update_all(set: [primary_image_id: nil])
    end

    if data.vn_screenshot_ids != [] do
      from(vn in VisualNovel, where: vn.featured_screenshot_id in ^data.vn_screenshot_ids)
      |> Repo.update_all(set: [featured_screenshot_id: nil])
    end

    # Delete VN rows (CASCADE handles ~20 child tables)
    {vn_count, _} =
      from(vn in VisualNovel, where: vn.id in ^vn_ids)
      |> Repo.delete_all()

    Logger.info("  Deleted #{vn_count} VNs (+ cascaded children)")

    # 2. Delete orphaned characters
    if data.orphaned_char_ids != [] do
      {char_count, _} =
        from(c in Character, where: c.id in ^data.orphaned_char_ids)
        |> Repo.delete_all()

      Logger.info("  Deleted #{char_count} orphaned characters")
    end

    # 3. Delete orphaned producers
    if data.orphaned_producer_ids != [] do
      {prod_count, _} =
        from(p in Producer, where: p.id in ^data.orphaned_producer_ids)
        |> Repo.delete_all()

      Logger.info("  Deleted #{prod_count} orphaned producers")
    end

    # 4. Delete orphaned series
    if data.orphaned_series_ids != [] do
      {series_count, _} =
        from(s in Series, where: s.id in ^data.orphaned_series_ids)
        |> Repo.delete_all()

      Logger.info("  Deleted #{series_count} orphaned series")
    end

    # 5. Delete orphaned tags (re-verify post-cascade)
    if data.candidate_orphaned_tag_ids != [] do
      orphaned_tag_ids =
        from(t in Tag,
          where: t.id in ^data.candidate_orphaned_tag_ids,
          where: fragment("NOT EXISTS (SELECT 1 FROM vn_tags vt WHERE vt.tag_id = ?)", t.id),
          select: t.id
        )
        |> Repo.all()

      if orphaned_tag_ids != [] do
        {tag_count, _} =
          from(t in Tag, where: t.id in ^orphaned_tag_ids)
          |> Repo.delete_all()

        Logger.info("  Deleted #{tag_count} orphaned tags")
      end
    end

    # 6. Adjust user rating stats
    rating_users = map_size(data.ratings_by_user)

    if rating_users > 0 do
      user_ids = Map.keys(data.ratings_by_user)

      current_dists =
        from(u in User,
          where: u.id in ^user_ids,
          select: {u.id, u.vn_ratings_dist}
        )
        |> Repo.all()
        |> Map.new()

      json_data =
        Enum.map(data.ratings_by_user, fn {user_id, ratings} ->
          dist = Map.get(current_dists, user_id) || RatingDistribution.default_dist()

          updated_dist =
            Enum.reduce(ratings, dist, fn %{rating: r}, acc ->
              RatingDistribution.adjust_bucket(acc, r, -1)
            end)

          total_count = Enum.sum(updated_dist)
          total_sum = RatingDistribution.total_sum(updated_dist)
          avg = if total_count > 0, do: total_sum / total_count, else: 0.0

          %{id: user_id, dist: updated_dist, cnt: total_count, avg: avg}
        end)

      json_str = Jason.encode!(json_data)

      Repo.query!(
        """
        UPDATE users SET
          ratings_dist = v.dist,
          ratings_count = v.cnt,
          average_rating = v.avg
        FROM jsonb_to_recordset($1::text::jsonb)
          AS v(id uuid, dist int[], cnt int, avg float8)
        WHERE users.id = v.id
        """,
        [json_str]
      )

      Logger.info("  Adjusted rating stats for #{rating_users} users")
    end

    # 7. Adjust user review counts
    review_users = map_size(data.reviews_by_user)

    if review_users > 0 do
      {bin_ids, decrements} =
        data.reviews_by_user
        |> Enum.map(fn {user_id, reviews} -> {Ecto.UUID.dump!(user_id), length(reviews)} end)
        |> Enum.unzip()

      Repo.query!(
        """
        UPDATE users SET reviews_count = users.reviews_count - v.dec
        FROM unnest($1::uuid[], $2::int[]) AS v(id, dec)
        WHERE users.id = v.id
        """,
        [bin_ids, decrements]
      )

      Logger.info("  Adjusted review counts for #{review_users} users")
    end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 8. Decrement shelf vns_count
    if data.shelf_counts != [] do
      {bin_ids, decrements} = Enum.unzip(data.shelf_counts)

      Repo.query!(
        """
        UPDATE shelves SET vns_count = shelves.vns_count - v.dec, updated_at = $3
        FROM unnest($1::uuid[], $2::int[]) AS v(id, dec)
        WHERE shelves.id = v.id
        """,
        [bin_ids, decrements, now]
      )

      Logger.info("  Adjusted #{length(data.shelf_counts)} shelf counts")
    end

    # 9. Decrement list vns_count
    if data.list_counts != [] do
      {bin_ids, decrements} = Enum.unzip(data.list_counts)

      Repo.query!(
        """
        UPDATE lists SET vns_count = lists.vns_count - v.dec, updated_at = $3
        FROM unnest($1::uuid[], $2::int[]) AS v(id, dec)
        WHERE lists.id = v.id
        """,
        [bin_ids, decrements, now]
      )

      Logger.info("  Adjusted #{length(data.list_counts)} list counts")
    end

    # 10. Compact ranked list positions
    if data.ranked_list_ids != [] do
      bin_list_ids = data.ranked_list_ids

      Repo.query!(
        """
        UPDATE list_items SET position = sub.new_pos
        FROM (
          SELECT list_id, visual_novel_id,
                 row_number() OVER (PARTITION BY list_id ORDER BY position) AS new_pos
          FROM list_items
          WHERE list_id = ANY($1::uuid[])
        ) sub
        WHERE list_items.list_id = sub.list_id
          AND list_items.visual_novel_id = sub.visual_novel_id
          AND list_items.position != sub.new_pos
        """,
        [bin_list_ids]
      )

      Logger.info("  Compacted positions in #{length(data.ranked_list_ids)} ranked lists")
    end

    # 11. Clean favorite_visual_novels arrays
    binary_vn_ids = Enum.map(vn_ids, &Ecto.UUID.dump!/1)

    {fav_vn_count, _} =
      Repo.query!(
        """
        UPDATE users SET favorite_visual_novels = (
          SELECT COALESCE(array_agg(elem), '{}')
          FROM unnest(favorite_visual_novels) AS elem
          WHERE elem != ALL($1::uuid[])
        )
        WHERE favorite_visual_novels && $1::uuid[]
        """,
        [binary_vn_ids]
      )
      |> then(fn %{num_rows: n} -> {n, nil} end)

    if fav_vn_count > 0 do
      Logger.info("  Cleaned favorite_visual_novels for #{fav_vn_count} users")
    end

    # 12. character_favorites rows — no explicit cleanup needed. The FK
    # `on_delete: :delete_all` on character_favorites.character_id drops
    # the rows automatically when a character row is deleted, and the
    # characters.favorites_count counter goes with the character row
    # itself, so there's nothing to decrement.

    # 13. Delete stale notifications (review + review comment)
    notif_deleted = 0

    notif_deleted =
      if data.review_ids != [] do
        {count, _} =
          from(n in "notifications",
            where: n.entity_type == "review" and n.entity_id in ^data.review_ids
          )
          |> Repo.delete_all()

        notif_deleted + count
      else
        notif_deleted
      end

    notif_deleted =
      if data.review_comment_ids != [] do
        {count, _} =
          from(n in "notifications",
            where: n.entity_type == "comment" and n.entity_id in ^data.review_comment_ids
          )
          |> Repo.delete_all()

        notif_deleted + count
      else
        notif_deleted
      end

    if notif_deleted > 0 do
      Logger.info("  Deleted #{notif_deleted} stale review notifications")
    end

    # 14. Delete stale VN list notifications (contain broken cover URLs)
    affected_list_ids = Enum.map(data.list_counts, &elem(&1, 0))

    if affected_list_ids != [] do
      {list_notif_count, _} =
        from(n in "notifications",
          where: n.entity_type == "list" and n.entity_id in ^affected_list_ids
        )
        |> Repo.delete_all()

      if list_notif_count > 0 do
        Logger.info("  Deleted #{list_notif_count} stale VN list notifications")
      end
    end

    # 15. Delete orphaned user_activities (references deleted VNs via metadata->>'vn_id')
    activity_deleted =
      Repo.query!(
        """
        DELETE FROM user_activities
        WHERE (metadata->>'vn_id')::uuid = ANY($1::uuid[])
        """,
        [binary_vn_ids]
      ).num_rows

    # Also clean similarity activities where either source or similar VN was deleted
    similarity_activity_deleted =
      Repo.query!(
        """
        DELETE FROM user_activities
        WHERE entity_type = 'similarity'
          AND ((metadata->>'source_vn_id')::uuid = ANY($1::uuid[])
            OR (metadata->>'similar_vn_id')::uuid = ANY($1::uuid[]))
        """,
        [binary_vn_ids]
      ).num_rows

    total_activities = activity_deleted + similarity_activity_deleted

    if total_activities > 0 do
      Logger.info("  Deleted #{total_activities} orphaned user activities")
    end

    %{deleted_vns: vn_count}
  end

  # ──────────────────────────────────
  # Post-Transaction Cleanup
  # ──────────────────────────────────

  defp post_transaction_cleanup(data, opts) do
    Logger.info("Post-transaction cleanup...")

    # 1. Remove from Meilisearch
    SearchIndex.remove_visual_novels(data.vn_ids)
    Logger.info("  Removed #{length(data.vn_ids)} VNs from Meilisearch")

    if data.orphaned_char_ids != [] do
      SearchIndex.remove_characters(data.orphaned_char_ids)
      Logger.info("  Removed #{length(data.orphaned_char_ids)} characters from Meilisearch")
    end

    # 2. Invalidate cache + re-warm explore-mode sections asynchronously
    Kaguya.VisualNovels.BrowseSections.refresh()
    Logger.info("  Cleared vn_browse_cache (explore sections re-warming)")

    # 3. Delete R2 files (skippable)
    unless Keyword.get(opts, :skip_r2, false) do
      delete_r2_files(data)
    end

    # 4. Purge Cloudflare CDN cache
    vn_slugs = data.vn_details |> Enum.map(& &1.slug) |> Enum.reject(&is_nil/1)

    Cdn.purge_pages(
      vn_slugs: vn_slugs,
      character_slugs: data.orphaned_char_slugs,
      producer_slugs: data.orphaned_producer_slugs
    )

    total_purged =
      length(vn_slugs) + length(data.orphaned_char_slugs) + length(data.orphaned_producer_slugs)

    if total_purged > 0, do: Logger.info("  Purging CDN cache for #{total_purged} pages")
  end

  defp delete_r2_files(data) do
    cover_suffixes = ~w(128w 256w 512w 1024w)
    screenshot_suffixes = ~w(320w 640w 1280w)

    cover_keys =
      for image_id <- data.vn_image_ids, suffix <- cover_suffixes do
        "visual_novels/#{image_id}-#{suffix}.webp"
      end

    screenshot_keys =
      for screenshot_id <- data.vn_screenshot_ids, suffix <- screenshot_suffixes do
        "visual_novels/screenshots/#{screenshot_id}-#{suffix}.webp"
      end

    character_keys =
      for image_id <- data.orphaned_char_image_ids do
        "characters/#{image_id}-240w.webp"
      end

    all_keys = cover_keys ++ screenshot_keys ++ character_keys
    total = length(all_keys)

    if total > 0 do
      Logger.info("  Deleting #{total} R2 files in batch...")

      bucket = Kaguya.Images.bucket()

      {ok_count, err_count} =
        all_keys
        |> Enum.chunk_every(1000)
        |> Enum.reduce({0, 0}, fn chunk, {ok, err} ->
          case ExAws.S3.delete_multiple_objects(bucket, chunk, quiet: true) |> ExAws.request() do
            {:ok, _} ->
              {ok + length(chunk), err}

            {:error, reason} ->
              Logger.warning("Batch R2 delete failed (#{length(chunk)} keys): #{inspect(reason)}")
              {ok, err + length(chunk)}
          end
        end)

      Logger.info("  R2 cleanup: #{ok_count} deleted, #{err_count} failed")
    end
  end

  defp default_reasons(vn_ids) do
    Map.new(vn_ids, &{&1, "removed from VNDB dump"})
  end
end
