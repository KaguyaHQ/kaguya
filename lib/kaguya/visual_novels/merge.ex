defmodule Kaguya.VisualNovels.Merge do
  @moduledoc """
  Collapse N source VNs into a single canonical VN. Mirrors the
  `Kaguya.VisualNovels.Deletion` pattern (pre-gather → transaction →
  post-cleanup) and the historical `Kaguya.Librarian.Books.merge_book/3`
  precedent (delete-conflicts-then-update + duplicate-work registry).

  ## When to use

  When two or more `visual_novels` rows actually represent the same work
  and should collapse to one — typically VNDB-split season/chapter/part
  entries that VNDB splits but which represent a single ongoing
  project. Example:

      summers-gone-season-1                  ┐
      summers-gone-season-2-constellations   ├─►  summers-gone   (canonical)
      summers-gone-season-3                  ┘

  Caller picks one slug as canonical and lists the others as sources.
  Every association on a source row is migrated to the canonical with
  conflict resolution per the rules in `docs/plans/vn-merge-plan.md`. Source slugs
  + VNDB ids are registered in `vn_merges` (so VNDB sync skips them and
  the audit trail survives the source row's deletion). Source slugs are
  also recorded in `slug_redirects` so old URLs resolve to the canonical.
  Source `visual_novels` rows are then deleted; cascades clean up
  anything that survived migration.

  ## Pipeline

  ### 1. Validate
    * No self-merge (canonical must not appear in source list).
    * All IDs must exist.
    * No source can already be a canonical of another merge (we don't
      collapse merge chains in v1 — collapse them flat first).

  ### 2. Resolve canonical attrs (`gather_canonical_resolution/3`)
    Computes the post-merge value of every field on the `visual_novels`
    row from canonical + sources, with optional overrides from the
    caller (mod-curated edits). Returns a plain map for the changeset.

  ### 3. Transaction (`Repo.transact/1`, all-or-nothing)
    1. Migrate all 27 dependent tables (see `Per-table rules` in
       `docs/plans/vn-merge-plan.md`)
    2. Update the canonical `visual_novels` row with resolved attrs
    3. Recompute aggregates (rating stats, tag relevance)
    4. Insert `vn_merges` registry rows for each source
    5. Write `audit_log` + `changes` rows
    6. Delete source `visual_novels` rows (cascades handle anything that
       slipped through migration)

  ### 4. Post-transaction (idempotent, non-critical)
    * Remove sources from search index
    * Reindex canonical
    * Clear browse cache

  ## User-data preservation

  PK constraints on `ratings`, `reviews`, `reading_statuses`
  permit only one row per `(user_id, vn_id)`. When a user has rows on
  multiple sources (or canonical + source), the *winning* row is kept:

  | Table | Winner |
  |---|---|
  | `ratings`             | Most recent `updated_at`. The user's current opinion. |
  | `reviews`             | Most recent `updated_at`, falling back to longest `body`. The user's most current published take. |
  | `reading_statuses`    | Most progressed (`read > currently_reading > on_hold > did_not_finish > not_interested > want_to_read`); ties break on `updated_at`. |
  | `shelf_items`         | Per-shelf dedup; user's multi-shelf placements all survive. |
  | `list_items`          | Per-list dedup; lowest position wins. |
  | `vn_tag_votes`        | Per-tag dedup; max upvotes/downvotes (no double counting). |
  | `vn_similarity_votes` | Most recent. |

  The principle: never silently drop a user's standalone content; the
  only "loss" is replacing an older record with a newer one written by
  the same user.
  """

  import Ecto.Query

  alias Kaguya.AuditLog
  alias Kaguya.RatingDistribution
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.SearchIndex
  alias Kaguya.Tags.TagRelevance
  alias Kaguya.VisualNovels.VisualNovel

  require Logger

  # Reading-status priority: highest wins when the same user has different
  # statuses across the merged VNs.
  @reading_status_priority %{
    "read" => 6,
    "currently_reading" => 5,
    "on_hold" => 4,
    "did_not_finish" => 3,
    "not_interested" => 2,
    "want_to_read" => 1
  }

  # development_status priority: most-active wins.
  @development_status_priority %{
    "in_development" => 4,
    "on_hiatus" => 3,
    "finished" => 2,
    "abandoned" => 1,
    # Historical rows used this spelling before the May 2026 rename.
    "cancelled" => 1
  }

  # title_category priority: most-specific wins.
  @title_category_priority %{
    nukige: 3,
    adjacent: 2,
    vn: 1
  }

  # vn_characters role priority: most-prominent wins.
  @character_role_priority %{
    "primary" => 4,
    "main" => 3,
    "side" => 2,
    "appears" => 1
  }

  # vn_relations type priority: stronger wins.
  @relation_type_priority %{
    "sequel" => 9,
    "prequel" => 8,
    "side_story" => 7,
    "parent_story" => 7,
    "shares_characters" => 6,
    "same_series" => 5,
    "same_setting" => 4,
    "alternative" => 3,
    "original" => 2,
    "fandisc" => 1
  }

  # ──────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Merge `source_ids` into `canonical_id` as the surviving VN.

  ## Options

    * `:attrs` — map of canonical-VN field overrides (title, slug,
      description, etc.). Auto-resolved values are used for any field
      not in the override.
    * `:dry_run` — boolean. If true, returns the resolved attrs and
      counts without mutating the DB. Default false.

  Returns `{:ok, %{canonical_id, merged: n, …}}` or `{:error, reason}`.
  """
  def merge_vns(canonical_id, source_ids, actor_user_id, opts \\ []) when is_list(source_ids) do
    with :ok <- validate_inputs(canonical_id, source_ids),
         {:ok, canonical} <- fetch_vn(canonical_id),
         {:ok, sources} <- fetch_sources(source_ids),
         :ok <- validate_no_existing_merges(source_ids) do
      attrs_override = Keyword.get(opts, :attrs, %{})
      dry_run = Keyword.get(opts, :dry_run, false)
      resolved = gather_canonical_resolution(canonical, sources, attrs_override)

      if dry_run do
        {:ok, dry_run_summary(canonical, sources, resolved)}
      else
        run_merge(canonical, sources, resolved, actor_user_id)
      end
    end
  end

  @doc """
  All VNDB ids registered in `vn_merges.merged_vndb_id` — the set of
  source-VN VNDB ids that were folded into a canonical and should be
  skipped by future VNDB sync runs to avoid resurrecting the source row.

  Both `Kaguya.Sync.DumpSync` and `Kaguya.Sync.VndbSync` consult this.
  """
  def merged_vndb_ids do
    from(m in "vn_merges", where: not is_nil(m.merged_vndb_id), select: m.merged_vndb_id)
    |> Repo.all()
  end

  @doc """
  Compute the canonical VN's post-merge field values without mutating
  anything. Useful for a compose-and-confirm preview.
  """
  def gather_canonical_resolution(canonical, sources, attrs_override \\ %{}) do
    all = [canonical | sources]

    # Aggregate fields (ratings_count, ratings_dist, average_rating,
    # reviews_count) are deliberately NOT in here — they're rebuilt by
    # `recompute_canonical_aggregates/2` at the end of the transaction
    # from the actual surviving association rows, so per-user dedup
    # isn't double-counted.
    auto = %{
      title: canonical.title,
      slug: canonical.slug,
      description: pick_longest_string(all, :description),
      aliases: union_aliases(canonical, sources),
      has_ero: any_true(all, :has_ero),
      is_image_nsfw: any_true(all, :is_image_nsfw),
      is_image_suggestive: any_true(all, :is_image_suggestive),
      is_avn: any_true(all, :is_avn),
      development_status: pick_priority(all, :development_status, @development_status_priority),
      title_category: pick_priority_atom(all, :title_category, @title_category_priority),
      release_date: pick_min(all, :release_date),
      length_minutes: sum(all, :length_minutes),
      length_category: nil,
      min_age: pick_max(all, :min_age),
      vndb_rating: weighted_avg_decimal(all, :vndb_rating, :vndb_vote_count),
      vndb_vote_count: sum(all, :vndb_vote_count),
      primary_image_id: pick_first_non_nil([canonical | sources], :primary_image_id),
      featured_screenshot_id: pick_first_non_nil([canonical | sources], :featured_screenshot_id),
      is_cover_pinned: any_true(all, :is_cover_pinned),
      hidden_at: pick_min(all, :hidden_at),
      is_locked: any_true(all, :is_locked),
      original_language: canonical.original_language,
      vndb_id: canonical.vndb_id,
      primary_vn_series_id: nil,
      primary_series_position: nil
    }

    auto = Map.put(auto, :length_category, derive_length_category(auto.length_minutes))

    Map.merge(auto, atom_keyed(attrs_override))
  end

  # ──────────────────────────────────────────────────────────────────────
  # Validation
  # ──────────────────────────────────────────────────────────────────────

  defp validate_inputs(canonical_id, source_ids) do
    cond do
      source_ids == [] ->
        {:error, :no_sources}

      canonical_id in source_ids ->
        {:error, :self_merge}

      length(source_ids) != length(Enum.uniq(source_ids)) ->
        {:error, :duplicate_source_ids}

      true ->
        :ok
    end
  end

  defp fetch_vn(id) do
    case Repo.get(VisualNovel, id) do
      nil -> {:error, {:vn_not_found, id}}
      vn -> {:ok, vn}
    end
  end

  defp fetch_sources(ids) do
    found =
      from(v in VisualNovel, where: v.id in ^ids)
      |> Repo.all()

    if length(found) == length(ids) do
      missing = ids -- Enum.map(found, & &1.id)
      if missing == [], do: {:ok, found}, else: {:error, {:sources_not_found, missing}}
    else
      missing = ids -- Enum.map(found, & &1.id)
      {:error, {:sources_not_found, missing}}
    end
  end

  # In v1 we don't collapse merge chains. If a source is itself the
  # canonical of an earlier merge (vn_merges.canonical_id = source.id),
  # the caller must un-merge it first or pick a different canonical.
  defp validate_no_existing_merges(source_ids) do
    chain =
      from(m in "vn_merges",
        where: m.canonical_id in ^Enum.map(source_ids, &Ecto.UUID.dump!/1),
        select: type(m.canonical_id, Ecto.UUID),
        limit: 1
      )
      |> Repo.one()

    if chain, do: {:error, {:source_is_canonical, chain}}, else: :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # Transaction
  # ──────────────────────────────────────────────────────────────────────

  defp run_merge(canonical, sources, resolved, actor_user_id) do
    canonical_id = canonical.id
    source_ids = Enum.map(sources, & &1.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transact(fn ->
      # Acquire per-canonical advisory lock so concurrent merges/edits on the
      # same canonical can't interleave. Sources are about to be deleted;
      # locking them is unnecessary.
      lock_canonical(canonical_id)

      # 1) Migrate all dependents in dependency-safe order. Each helper
      #    operates inside this transaction.
      # Simple re-point — tables with no per-(vn,X) unique constraint.
      migrate_simple_repoint("vn_screenshots", :visual_novel_id, canonical_id, source_ids, now)
      migrate_simple_repoint("vn_quotes", :visual_novel_id, canonical_id, source_ids, now)

      # Secondary uniques — duplicate (vn_id, key) is possible across
      # canonical + sources, so route through the composite-PK migrator.
      migrate_composite_pk("vn_titles", :visual_novel_id, [:lang], canonical_id, source_ids)
      migrate_composite_pk("vn_images", :visual_novel_id, [:vndb_cv_id], canonical_id, source_ids)
      migrate_composite_pk("vn_releases", :visual_novel_id, [:vndb_id], canonical_id, source_ids)

      migrate_composite_pk("vn_engines", :visual_novel_id, [:engine], canonical_id, source_ids)

      migrate_composite_pk(
        "vn_platforms",
        :visual_novel_id,
        [:platform],
        canonical_id,
        source_ids
      )

      migrate_composite_pk(
        "vn_languages",
        :visual_novel_id,
        [:language],
        canonical_id,
        source_ids
      )

      migrate_external_links(canonical_id, source_ids, now)
      migrate_producers(canonical_id, source_ids, now)
      migrate_characters(canonical_id, source_ids, now)
      migrate_tags(canonical_id, source_ids, now)

      migrate_self_relation_table(
        "vn_relations",
        :visual_novel_id,
        :related_vn_id,
        :relation_type,
        @relation_type_priority,
        canonical_id,
        source_ids,
        now
      )

      migrate_vn_similarities(canonical_id, source_ids)

      migrate_composite_pk(
        "vn_series_items",
        :visual_novel_id,
        [:vn_series_id],
        canonical_id,
        source_ids
      )

      # User-data preservation tables — pick a winner per user, drop losers.
      migrate_user_unique_ratings(canonical_id, source_ids, now)
      migrate_user_unique_reviews(canonical_id, source_ids, now)
      migrate_user_unique_reading_statuses(canonical_id, source_ids, now)

      migrate_composite_pk("shelf_items", :visual_novel_id, [:shelf_id], canonical_id, source_ids)
      migrate_composite_pk("list_items", :visual_novel_id, [:list_id], canonical_id, source_ids)

      migrate_tag_votes(canonical_id, source_ids, now)

      migrate_composite_pk(
        "vn_similarity_votes",
        :visual_novel_id,
        [:similar_vn_id, :user_id],
        canonical_id,
        source_ids
      )

      migrate_composite_pk(
        "user_recommendations",
        :visual_novel_id,
        [:user_id],
        canonical_id,
        source_ids
      )

      migrate_composite_pk(
        "user_recommendation_feedback",
        :visual_novel_id,
        [:user_id],
        canonical_id,
        source_ids
      )

      # 2) Update the canonical row with resolved fields.
      update_canonical_row(canonical, resolved, now)

      # 3) Re-point un-FK'd polymorphic and array references so users
      # don't lose favorites, feed entries, audit/report context.
      migrate_polymorphic_refs(canonical_id, source_ids)

      # 4) Insert vn_merges audit rows BEFORE deleting sources, and
      # record every old slug in `slug_redirects` so historical URLs
      # keep resolving to the surviving canonical.
      insert_vn_merges(canonical, sources, actor_user_id, now)
      record_slug_redirects(canonical, sources, resolved)

      # 5) Audit trail.
      write_audit(canonical_id, sources, actor_user_id, resolved)

      # 6) Delete the source rows. CASCADE cleans up anything we missed.
      delete_source_rows(source_ids)

      # 7) Recompute aggregates from the now-surviving dependents.
      # `update_canonical_row` set non-aggregate fields; aggregates
      # (ratings_count, ratings_dist, average_rating, reviews_count) are
      # rebuilt here so that per-user dedup isn't double-counted.
      recompute_canonical_aggregates(canonical_id, now)
      TagRelevance.recompute_vn_tags_for_visual_novel(canonical_id)

      {:ok,
       %{
         canonical_id: canonical_id,
         merged_source_ids: source_ids,
         merged_count: length(source_ids)
       }}
    end)
    |> case do
      {:ok, summary} ->
        post_transaction_cleanup(canonical_id, source_ids)
        {:ok, summary}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_canonical(canonical_id) do
    # Per-VN advisory lock keyed on the UUID's first 8 bytes as a bigint.
    # Released automatically at end of transaction.
    <<key::signed-64, _::binary>> = Ecto.UUID.dump!(canonical_id)
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
  end

  # ──────────────────────────────────────────────────────────────────────
  # Per-table migrators
  # ──────────────────────────────────────────────────────────────────────

  # A) Simple re-point — for tables with NO unique constraint on
  # (vn_col, …) beyond the row's own PK. Just rewrite the FK; no conflict
  # possible. Used for `vn_screenshots` (unique on `vndb_sf_id` global,
  # no per-VN unique) and `vn_quotes` (unique on `vndb_id` global). We
  # don't touch updated_at — the row's content didn't change, just owner.
  defp migrate_simple_repoint(table, vn_col, canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    %{num_rows: count} =
      Repo.query!(
        ~s|UPDATE "#{table}" SET "#{vn_col}" = $1::uuid WHERE "#{vn_col}" = ANY($2::uuid[])|,
        [canonical_bin, source_bins]
      )

    Logger.debug("merge: #{table} re-pointed #{count} rows")
    count
  end

  # B) (vn_col, X[, Y…]) carries a uniqueness constraint — either as a
  # composite PK or as a secondary `unique_index`. Three classes of
  # conflict to resolve before re-pointing source rows to canonical:
  #
  #   1. canonical-vs-source: canonical already has (canonical, X); a
  #      source has (source, X). Drop the source row.
  #   2. cross-source: source1 has (s1, X); source2 has (s2, X). Both
  #      would re-point to (canonical, X) → unique violation. Drop one.
  #   3. canonical alone: canonical has the row, no source does. Keep.
  #
  # The DELETE below does (1) and (2) in one pass via ROW_NUMBER over
  # PARTITION BY conflict_cols, ordered to prefer canonical's row, then
  # an arbitrary stable tiebreak by ctid. The remaining sources are then
  # safely re-pointed.
  defp migrate_composite_pk(table, vn_col, conflict_cols, canonical_id, source_ids) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)
    all_bins = [canonical_bin | source_bins]
    cols_csv = Enum.map_join(conflict_cols, ", ", &"\"#{&1}\"")

    Repo.query!(
      """
        DELETE FROM "#{table}" d
        USING (
          SELECT ctid, ROW_NUMBER() OVER (
            PARTITION BY #{cols_csv}
            ORDER BY ("#{vn_col}" = $2::uuid) DESC, ctid
          ) AS rn
          FROM "#{table}"
          WHERE "#{vn_col}" = ANY($1::uuid[])
        ) ranked
        WHERE d.ctid = ranked.ctid AND ranked.rn > 1
      """,
      [all_bins, canonical_bin]
    )

    # Re-point survivors to canonical. Any (canonical, X) survivor stays
    # as-is; sources that had unique (X) get re-homed.
    {count, _} =
      Repo.update_all(
        from(t in table,
          where: field(t, ^vn_col) in type(^source_ids, {:array, Ecto.UUID})
        ),
        set: [{vn_col, canonical_bin}]
      )

    Logger.debug("merge: #{table} migrated #{count} rows (composite #{cols_csv})")
    count
  end

  # vn_external_links is composite-PK (vn_id, site) but the row also has a
  # `value` field; conflict resolution prefers canonical's existing value
  # (mod can edit post-merge).
  defp migrate_external_links(canonical_id, source_ids, _now) do
    migrate_composite_pk("vn_external_links", :vn_id, [:site], canonical_id, source_ids)
  end

  # vn_producers — composite-PK (vn_id, producer_id). Same skeleton; role
  # conflict (developer vs publisher) resolved by preferring canonical.
  defp migrate_producers(canonical_id, source_ids, _now) do
    migrate_composite_pk(
      "vn_producers",
      :visual_novel_id,
      [:producer_id],
      canonical_id,
      source_ids
    )
  end

  # vn_characters — composite-PK (vn_id, character_id). Role priority:
  # primary > main > side > appears. When the same character is on both
  # canonical and source, keep the higher-priority role on canonical.
  defp migrate_characters(canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    role_case = role_priority_sql(@character_role_priority)

    # Resolve role conflicts — pick the row with highest role priority and
    # apply its role to the canonical's row.
    Repo.query!(
      """
        UPDATE vn_characters c
        SET role = winner.role
        FROM (
          SELECT DISTINCT ON (character_id) character_id, role
          FROM vn_characters
          WHERE visual_novel_id = $1::uuid
             OR visual_novel_id = ANY($2::uuid[])
          ORDER BY character_id, #{role_case} DESC
        ) winner
        WHERE c.visual_novel_id = $1::uuid
          AND c.character_id = winner.character_id
      """,
      [canonical_bin, source_bins]
    )

    # Now standard composite-PK migrate.
    migrate_composite_pk(
      "vn_characters",
      :visual_novel_id,
      [:character_id],
      canonical_id,
      source_ids
    )
  end

  # vn_tags — aggregate VNDB vote totals and moderation flags from every
  # source into the canonical row. Aggregation rules:
  #   vndb_vote_count = sum
  #   vndb_avg_score  = vote-weighted avg (NULL when total votes = 0)
  #   spoiler_level   = max (NULL-safe)
  #   is_overruled    = OR
  #   overruled_by    = preserve canonical's first; otherwise arbitrary
  #   relevance_score is reset; `TagRelevance.recompute_…` rebuilds it
  #   right after the per-table migrators finish.
  #
  # We INSERT (canonical, tag_id, …) with cross-source-aggregated values
  # via ON CONFLICT DO UPDATE so that:
  #   - a tag only on sources lands as a fresh canonical row
  #   - a tag on canonical+sources merges into the existing canonical row
  #   - multiple sources sharing a tag are GROUP-BY collapsed before insert
  # Then we DELETE every source vn_tag row in one shot.
  defp migrate_tags(canonical_id, source_ids, now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    Repo.query!(
      """
        INSERT INTO vn_tags (
          visual_novel_id, tag_id,
          vndb_vote_count, vndb_avg_score,
          spoiler_level, is_overruled, overruled_by,
          relevance_score, inserted_at, updated_at
        )
        SELECT
          $1::uuid,
          tag_id,
          SUM(vndb_vote_count)::int,
          CASE
            WHEN SUM(vndb_vote_count) = 0 THEN NULL
            ELSE (SUM(COALESCE(vndb_avg_score, 0::float) * vndb_vote_count)
                  / NULLIF(SUM(vndb_vote_count), 0)::float)::float
          END,
          MAX(spoiler_level)::smallint,
          BOOL_OR(is_overruled),
          -- Postgres has no MAX(uuid); cast to text for the aggregate, back to uuid.
          MAX(CASE WHEN is_overruled THEN overruled_by::text ELSE NULL END)::uuid,
          0.0::float,
          $3::timestamp,
          $3::timestamp
        FROM vn_tags
        WHERE visual_novel_id = ANY($2::uuid[])
        GROUP BY tag_id
        ON CONFLICT (visual_novel_id, tag_id) DO UPDATE
        SET
          vndb_vote_count = vn_tags.vndb_vote_count + EXCLUDED.vndb_vote_count,
          vndb_avg_score = CASE
            WHEN (vn_tags.vndb_vote_count + EXCLUDED.vndb_vote_count) = 0 THEN NULL
            ELSE ((COALESCE(vn_tags.vndb_avg_score, 0::float) * vn_tags.vndb_vote_count
                   + COALESCE(EXCLUDED.vndb_avg_score, 0::float) * EXCLUDED.vndb_vote_count)
                  / (vn_tags.vndb_vote_count + EXCLUDED.vndb_vote_count)::float)::float
          END,
          spoiler_level = GREATEST(
            COALESCE(vn_tags.spoiler_level, 0::smallint),
            COALESCE(EXCLUDED.spoiler_level, 0::smallint)
          )::smallint,
          is_overruled = vn_tags.is_overruled OR EXCLUDED.is_overruled,
          overruled_by = COALESCE(vn_tags.overruled_by, EXCLUDED.overruled_by),
          updated_at = EXCLUDED.updated_at
      """,
      [canonical_bin, source_bins, now]
    )

    # Sources are about to be deleted; clear their tag rows now so the
    # FK cascade has nothing left to do for vn_tags. Avoids leaving rows
    # whose visual_novel_id is about to dangle.
    Repo.query!(
      "DELETE FROM vn_tags WHERE visual_novel_id = ANY($1::uuid[])",
      [source_bins]
    )
  end

  # Self-relation tables (vn_relations, vn_similarities). The unique key
  # is (vn_col, related_col); both ends FK back to visual_novels. Each
  # column is re-pointed independently, and either pass can produce a
  # duplicate that violates the composite unique mid-statement. Sequence:
  #
  #   1. Dissolve relations between any two of the merged set
  #      (canonical↔source, source↔source) — they collapse.
  #   2. Pre-dedup for the vn_col re-point: for each related_col group,
  #      pick a single survivor among the merged-set rows (canonical
  #      first; otherwise highest priority). Delete losers.
  #   3. Re-point vn_col source → canonical.
  #   4. Pre-dedup for the related_col re-point: same, partitioned by
  #      vn_col now that all source-vn rows live on canonical.
  #   5. Re-point related_col source → canonical.
  defp migrate_self_relation_table(
         table,
         vn_col,
         related_col,
         priority_col,
         priority_map,
         canonical_id,
         source_ids,
         _now
       ) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)
    all_merged_bins = [canonical_bin | source_bins]

    # 1. Dissolve relations between any two of the merged set.
    Repo.query!(
      """
        DELETE FROM "#{table}"
        WHERE "#{vn_col}" = ANY($1::uuid[])
          AND "#{related_col}" = ANY($1::uuid[])
      """,
      [all_merged_bins]
    )

    # 2 + 3. vn_col side.
    self_relation_prededup(
      table,
      vn_col,
      related_col,
      priority_col,
      priority_map,
      all_merged_bins,
      canonical_bin
    )

    {_, _} =
      Repo.update_all(
        from(r in table,
          where: field(r, ^vn_col) in type(^source_ids, {:array, Ecto.UUID})
        ),
        set: [{vn_col, canonical_bin}]
      )

    # 4 + 5. related_col side. After step 3, all source-vn rows now live
    # on canonical, so dedup by vn_col with `related_col` IN the merged
    # set ensures the upcoming UPDATE doesn't violate the composite key.
    self_relation_prededup(
      table,
      related_col,
      vn_col,
      priority_col,
      priority_map,
      all_merged_bins,
      canonical_bin
    )

    {_, _} =
      Repo.update_all(
        from(r in table,
          where: field(r, ^related_col) in type(^source_ids, {:array, Ecto.UUID})
        ),
        set: [{related_col, canonical_bin}]
      )
  end

  # Drop merged-set rows that would conflict on the composite unique
  # after `target_col` is re-pointed to canonical. PARTITION BY the
  # OTHER column. Winner ranking:
  #   1. Highest priority via the priority map (e.g. sequel beats
  #      fandisc for vn_relations).
  #   2. ctid as a deterministic final tiebreak.
  # No canonical-first preference on purpose — the priority map is
  # already the semantic winner.
  defp self_relation_prededup(
         table,
         target_col,
         partition_col,
         priority_col,
         priority_map,
         all_merged_bins,
         _canonical_bin
       ) do
    Repo.query!(
      """
        DELETE FROM "#{table}" d
        USING (
          SELECT ctid, ROW_NUMBER() OVER (
            PARTITION BY "#{partition_col}"
            ORDER BY #{priority_sql(priority_col, priority_map)} DESC, ctid
          ) AS rn
          FROM "#{table}"
          WHERE "#{target_col}" = ANY($1::uuid[])
        ) ranked
        WHERE d.ctid = ranked.ctid AND ranked.rn > 1
      """,
      [all_merged_bins]
    )
  end

  # vn_similarities is structurally a self-relation, but it carries an
  # extra CHECK constraint `visual_novel_id < similar_vn_id` so each
  # unordered VN pair has exactly one canonical row (no `(A,B)` AND
  # `(B,A)` duplicates). The naive two-axis re-point used for
  # vn_relations breaks that invariant when canonical's UUID lands on
  # the wrong side of the inequality vs. the outside VN.
  #
  # Same shape as `migrate_tags`: source rows are folded into canonical
  # via `INSERT … ON CONFLICT DO UPDATE` (with `LEAST`/`GREATEST` to
  # normalize the canonical-pair representation), then source rows are
  # deleted in bulk.
  #
  # `vn_similarity_votes` (per-user vote rows) is migrated separately
  # via `migrate_composite_pk` further down the pipeline.
  defp migrate_vn_similarities(canonical_id, source_ids) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    # Step 1. Fold every row that touches a source into a normalized
    # canonical-pair INSERT. Two sources may share an outside VN (each
    # with their own row), so we GROUP BY the normalized pair *before*
    # the INSERT — `ON CONFLICT` can't collapse multiple new rows that
    # map to the same target within one statement (cardinality_violation).
    # ON CONFLICT then folds the aggregated source row into canonical's
    # pre-existing row when applicable. Self-loops (a (s, c) or (s1, s2)
    # that would become (c, c) after replacement) are dropped via WHERE.
    Repo.query!(
      """
        INSERT INTO vn_similarities (
          visual_novel_id, similar_vn_id,
          upvotes_count, downvotes_count,
          inserted_at, updated_at
        )
        SELECT
          pair_lo,
          pair_hi,
          SUM(upvotes_count)::int,
          SUM(downvotes_count)::int,
          MIN(inserted_at),
          MAX(updated_at)
        FROM (
          SELECT
            LEAST(new_vid, new_svid)    AS pair_lo,
            GREATEST(new_vid, new_svid) AS pair_hi,
            upvotes_count,
            downvotes_count,
            inserted_at,
            updated_at
          FROM (
            SELECT
              CASE WHEN visual_novel_id = ANY($2::uuid[]) THEN $1::uuid ELSE visual_novel_id END
                AS new_vid,
              CASE WHEN similar_vn_id  = ANY($2::uuid[]) THEN $1::uuid ELSE similar_vn_id  END
                AS new_svid,
              upvotes_count,
              downvotes_count,
              inserted_at,
              updated_at
            FROM vn_similarities
            WHERE visual_novel_id = ANY($2::uuid[]) OR similar_vn_id = ANY($2::uuid[])
          ) replaced
          WHERE new_vid <> new_svid
        ) normalized
        GROUP BY pair_lo, pair_hi
        ON CONFLICT (visual_novel_id, similar_vn_id) DO UPDATE
        SET
          upvotes_count   = vn_similarities.upvotes_count   + EXCLUDED.upvotes_count,
          downvotes_count = vn_similarities.downvotes_count + EXCLUDED.downvotes_count,
          updated_at      = GREATEST(vn_similarities.updated_at, EXCLUDED.updated_at)
      """,
      [canonical_bin, source_bins]
    )

    # Step 2. Sources are about to be deleted from `visual_novels`
    # (cascade would clean these up, but doing it explicitly avoids
    # any chance of leftover state racing the delete).
    Repo.query!(
      "DELETE FROM vn_similarities WHERE visual_novel_id = ANY($1::uuid[]) OR similar_vn_id = ANY($1::uuid[])",
      [source_bins]
    )
  end

  # ratings — per-user winner is most recent updated_at.
  defp migrate_user_unique_ratings(canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    # Delete losing rows: for each user with multiple rows across
    # canonical+sources, keep only the most-recent.
    Repo.query!(
      """
        DELETE FROM ratings r
        USING (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY updated_at DESC, id) AS rn
          FROM ratings
          WHERE visual_novel_id = $1::uuid OR visual_novel_id = ANY($2::uuid[])
        ) ranked
        WHERE r.id = ranked.id AND ranked.rn > 1
      """,
      [canonical_bin, source_bins]
    )

    # Re-point survivors that were on a source.
    Repo.update_all(
      from(r in "ratings",
        where: field(r, :visual_novel_id) in type(^source_ids, {:array, Ecto.UUID})
      ),
      set: [visual_novel_id: canonical_bin]
    )
  end

  # reviews — same shape; tiebreak on content length.
  defp migrate_user_unique_reviews(canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    Repo.query!(
      """
        DELETE FROM reviews r
        USING (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY user_id
                   ORDER BY updated_at DESC, length(content) DESC, id
                 ) AS rn
          FROM reviews
          WHERE visual_novel_id = $1::uuid OR visual_novel_id = ANY($2::uuid[])
        ) ranked
        WHERE r.id = ranked.id AND ranked.rn > 1
      """,
      [canonical_bin, source_bins]
    )

    Repo.update_all(
      from(r in "reviews",
        where: field(r, :visual_novel_id) in type(^source_ids, {:array, Ecto.UUID})
      ),
      set: [visual_novel_id: canonical_bin]
    )
  end

  # reading_statuses — winner = most-progressed status, tiebreak recent.
  defp migrate_user_unique_reading_statuses(canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)
    priority_case = priority_sql(:status, @reading_status_priority)

    Repo.query!(
      """
        DELETE FROM reading_statuses r
        USING (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY user_id
                   ORDER BY #{priority_case} DESC, updated_at DESC, id
                 ) AS rn
          FROM reading_statuses
          WHERE visual_novel_id = $1::uuid OR visual_novel_id = ANY($2::uuid[])
        ) ranked
        WHERE r.id = ranked.id AND ranked.rn > 1
      """,
      [canonical_bin, source_bins]
    )

    Repo.update_all(
      from(r in "reading_statuses",
        where: field(r, :visual_novel_id) in type(^source_ids, {:array, Ecto.UUID})
      ),
      set: [visual_novel_id: canonical_bin]
    )
  end

  # vn_tag_votes — UNIQUE (user, vn, tag). Each row stores the user's
  # `value` for one tag on one VN. When the same user voted on the same
  # tag across multiple sources/canonical, we keep the most-recent vote
  # (highest inserted_at) — that's their current opinion.
  defp migrate_tag_votes(canonical_id, source_ids, _now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    # Drop losers across canonical+sources for each (user, tag) combo.
    Repo.query!(
      """
        DELETE FROM vn_tag_votes v
        USING (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY user_id, tag_id
                   ORDER BY inserted_at DESC, id
                 ) AS rn
          FROM vn_tag_votes
          WHERE visual_novel_id = $1::uuid OR visual_novel_id = ANY($2::uuid[])
        ) ranked
        WHERE v.id = ranked.id AND ranked.rn > 1
      """,
      [canonical_bin, source_bins]
    )

    # Re-point survivors that were on a source.
    Repo.update_all(
      from(v in "vn_tag_votes",
        where: field(v, :visual_novel_id) in type(^source_ids, {:array, Ecto.UUID})
      ),
      set: [visual_novel_id: canonical_bin]
    )
  end

  # ──────────────────────────────────────────────────────────────────────
  # Canonical row update + registry + audit
  # ──────────────────────────────────────────────────────────────────────

  # Fields that VisualNovel.changeset deliberately omits from its public cast
  # list — `:slug` is immutable post-creation under normal user editing; the
  # rest are sync-only or moderation flags. The merge resolver computes
  # values for all of them, so we put_change them onto the changeset
  # directly after the cast-driven validations have run.
  @merge_put_change_fields [
    :slug,
    :length_minutes,
    :hidden_at,
    :is_locked,
    :is_cover_pinned,
    :featured_screenshot_id
  ]

  # Cast-list-eligible fields the merge resolver computes. Aggregate fields
  # (average_rating / ratings_count / ratings_dist / reviews_count) are
  # rebuilt later by `recompute_canonical_aggregates/2` so they're absent
  # from `resolved` and therefore from this list.
  @merge_cast_fields [
    :title,
    :description,
    :vndb_id,
    :development_status,
    :length_category,
    :original_language,
    :release_date,
    :min_age,
    :has_ero,
    :is_avn,
    :is_image_nsfw,
    :is_image_suggestive,
    :vndb_rating,
    :vndb_vote_count,
    :aliases,
    :primary_image_id,
    :primary_vn_series_id,
    :primary_series_position,
    :title_category
  ]

  defp update_canonical_row(canonical, resolved, now) do
    cast_attrs = Map.take(resolved, @merge_cast_fields)
    put_attrs = Map.take(resolved, @merge_put_change_fields)

    changeset =
      canonical
      |> VisualNovel.changeset(cast_attrs)
      |> Ecto.Changeset.put_change(:updated_at, now)

    changeset =
      Enum.reduce(put_attrs, changeset, fn {field, value}, cs ->
        Ecto.Changeset.put_change(cs, field, value)
      end)

    {:ok, _vn} = Repo.update(changeset)
  end

  # Re-point polymorphic / array references to the canonical so user data
  # threading (favorites, activity feed, mod queue) survives the merge
  # without dangling source ids. Each table is handled with its own
  # uniqueness rules:
  #
  #   - users.favorite_visual_novels (uuid[]) — replace source ids with
  #     canonical id, dedup via DISTINCT
  #   - notifications, audit_log — no relevant unique on the polymorphic
  #     pair, so a bare UPDATE is fine
  #   - reports, user_activities — have a unique that the rewrite would
  #     violate when a user has activity/report on canonical AND source;
  #     pre-dedup by deleting losers (most-recent or arbitrary survivor)
  #
  # `revisions.changes` is intentionally NOT re-pointed — its (entity_type,
  # entity_id, revision_number) unique would require renumbering source's
  # revision history into canonical's, which v1 doesn't support. The
  # merge itself is captured by `Revisions.bulk_create_system_changes`
  # in `write_audit/4`, so canonical's edit history shows the merge
  # without inheriting source's per-revision history.
  defp migrate_polymorphic_refs(canonical_id, source_ids) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)
    source_bins = Enum.map(source_ids, &Ecto.UUID.dump!/1)

    # 1) users.favorite_visual_novels — array_agg(DISTINCT) drops
    # duplicates if the user already had canonical alongside a source.
    Repo.query!(
      """
        UPDATE users
        SET favorite_visual_novels = (
          SELECT COALESCE(ARRAY_AGG(DISTINCT
            CASE WHEN elem = ANY($1::uuid[]) THEN $2::uuid ELSE elem END
          ), '{}'::uuid[])
          FROM unnest(favorite_visual_novels) AS elem
        )
        WHERE favorite_visual_novels && $1::uuid[]
      """,
      [source_bins, canonical_bin]
    )

    # 2) notifications.entity_id where entity_type identifies a VN.
    Repo.query!(
      """
        UPDATE notifications
        SET entity_id = $2::uuid
        WHERE entity_type = 'visual_novel' AND entity_id = ANY($1::uuid[])
      """,
      [source_bins, canonical_bin]
    )

    # 3) audit_log.target_id — historical entries. No unique constraint
    # on (target_type, target_id), so a bare update is safe.
    Repo.query!(
      """
        UPDATE audit_log
        SET target_id = $2::uuid
        WHERE target_type = 'visual_novel' AND target_id = ANY($1::uuid[])
      """,
      [source_bins, canonical_bin]
    )

    # 4) reports.entity_id — has a partial unique on
    # (reporter_id, entity_type, entity_id) WHERE status IN ('new','in_progress').
    # Drop conflicting open reports per (reporter, canonical) before re-point.
    Repo.query!(
      """
        DELETE FROM reports d
        USING (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY reporter_id
            ORDER BY (entity_id = $1::uuid) DESC, inserted_at DESC, id
          ) AS rn
          FROM reports
          WHERE entity_type = 'visual_novel'
            AND status IN ('new', 'in_progress')
            AND entity_id = ANY($2::uuid[])
        ) ranked
        WHERE d.id = ranked.id AND ranked.rn > 1
      """,
      [canonical_bin, [canonical_bin | source_bins]]
    )

    Repo.query!(
      """
        UPDATE reports
        SET entity_id = $2::uuid
        WHERE entity_type = 'visual_novel' AND entity_id = ANY($1::uuid[])
      """,
      [source_bins, canonical_bin]
    )

    # 5) user_activities — unique on (user_id, action, entity_type, entity_id).
    # Pre-dedup: keep most-recent per (user, action) within the merged set.
    Repo.query!(
      """
        DELETE FROM user_activities d
        USING (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY user_id, action
            ORDER BY inserted_at DESC, id
          ) AS rn
          FROM user_activities
          WHERE entity_type = 'visual_novel'
            AND entity_id = ANY($1::uuid[])
        ) ranked
        WHERE d.id = ranked.id AND ranked.rn > 1
      """,
      [[canonical_bin | source_bins]]
    )

    Repo.query!(
      """
        UPDATE user_activities
        SET entity_id = $2::uuid
        WHERE entity_type = 'visual_novel' AND entity_id = ANY($1::uuid[])
      """,
      [source_bins, canonical_bin]
    )

    # 6) user_activities.metadata — JSON-embedded VN refs (vn_id,
    # source_vn_id, similar_vn_id). Best-effort string-replacement on the
    # casted-text uuid; mirrors the deletion path's coverage.
    Enum.each(["vn_id", "source_vn_id", "similar_vn_id"], fn key ->
      Repo.query!(
        """
          UPDATE user_activities
          SET metadata = jsonb_set(metadata, $3::text[], to_jsonb($2::text))
          WHERE (metadata->>$1)::uuid = ANY($4::uuid[])
        """,
        [key, canonical_id, [key], source_bins]
      )
    end)
  end

  # `vn_merges` is the merge audit trail + the VNDB-sync skip-list. One
  # row per *deleted* source VN. Slug-resolution lives elsewhere now
  # (see `record_slug_redirects/3` + `Kaguya.SlugRedirects`), so this
  # function only concerns itself with sources, never canonical renames.
  defp insert_vn_merges(canonical, sources, actor_user_id, now) do
    canonical_id_bin = Ecto.UUID.dump!(canonical.id)
    user_bin = actor_user_id && Ecto.UUID.dump!(actor_user_id)

    rows =
      Enum.map(sources, fn s ->
        %{
          merged_id: Ecto.UUID.dump!(s.id),
          canonical_id: canonical_id_bin,
          merged_slug: s.slug,
          merged_title: s.title,
          merged_vndb_id: s.vndb_id,
          merged_by_user_id: user_bin,
          inserted_at: now
        }
      end)

    Repo.insert_all("vn_merges", rows)
  end

  # Record every old VN URL the merge invalidates, so the resolver
  # transparently sends old links to the surviving canonical:
  #
  #   * Each source slug → canonical (reason: :merge)
  #   * Canonical's OLD slug → canonical (reason: :merge), iff the caller
  #     passed `--slug=…` and changed it
  #
  # Idempotent — `SlugRedirects.record_many/1` upserts on
  # (entity_type, scope_id, old_slug). VNs are globally-scoped, so no
  # `scope_id`.
  defp record_slug_redirects(canonical, sources, resolved) do
    source_entries =
      Enum.map(sources, fn s ->
        %{entity_type: :vn, old_slug: s.slug, target_id: canonical.id, reason: :merge}
      end)

    rename_entry =
      case resolved[:slug] do
        new_slug when is_binary(new_slug) and new_slug != canonical.slug ->
          [%{entity_type: :vn, old_slug: canonical.slug, target_id: canonical.id, reason: :merge}]

        _ ->
          []
      end

    Kaguya.SlugRedirects.record_many(source_entries ++ rename_entry)
  end

  defp write_audit(canonical_id, sources, actor_user_id, _resolved) do
    if actor_user_id do
      Enum.each(sources, fn s ->
        details =
          Jason.encode!(%{
            merged_id: s.id,
            merged_slug: s.slug,
            merged_title: s.title,
            merged_vndb_id: s.vndb_id
          })

        AuditLog.log(actor_user_id, "merge_vn", "visual_novel", canonical_id, details)
      end)
    end

    # Single :merge revision on the canonical so it shows in edit history.
    Revisions.bulk_create_system_changes([
      %{
        entity_type: :visual_novel,
        entity_id: canonical_id,
        action: :edit,
        source: :system,
        changed_fields: ["merged_from"],
        summary:
          "Merged in #{length(sources)} VN(s): " <>
            Enum.map_join(sources, ", ", & &1.slug)
      }
    ])
  end

  defp delete_source_rows(source_ids) do
    {count, _} =
      Repo.delete_all(from(v in VisualNovel, where: v.id in ^source_ids))

    count
  end

  # ──────────────────────────────────────────────────────────────────────
  # Post-transaction (idempotent)
  # ──────────────────────────────────────────────────────────────────────

  defp post_transaction_cleanup(canonical_id, source_ids) do
    SearchIndex.remove_visual_novels(source_ids)
    canonical = Repo.get!(VisualNovel, canonical_id)
    SearchIndex.index_visual_novels(canonical)
    # Refresh browse cache so the newly-merged canonical replaces the
    # source rows in any cached browse sections. Mirrors `Deletion`.
    Kaguya.VisualNovels.BrowseSections.refresh()
    :ok
  rescue
    e ->
      Logger.warning("merge: post-cleanup failed (non-fatal): #{inspect(e)}")
      :ok
  end

  # Rebuilds aggregate columns on the canonical from surviving associations.
  # Runs after per-user dedup so counts don't double-count users who had
  # rows on multiple sources.
  defp recompute_canonical_aggregates(canonical_id, now) do
    canonical_bin = Ecto.UUID.dump!(canonical_id)

    %{rows: [[counts, dist, reviews]]} =
      Repo.query!(
        """
          SELECT
            (SELECT COUNT(*) FROM ratings WHERE visual_novel_id = $1::uuid),
            (SELECT ARRAY[
              COUNT(*) FILTER (WHERE rating = 0.5),
              COUNT(*) FILTER (WHERE rating = 1.0),
              COUNT(*) FILTER (WHERE rating = 1.5),
              COUNT(*) FILTER (WHERE rating = 2.0),
              COUNT(*) FILTER (WHERE rating = 2.5),
              COUNT(*) FILTER (WHERE rating = 3.0),
              COUNT(*) FILTER (WHERE rating = 3.5),
              COUNT(*) FILTER (WHERE rating = 4.0),
              COUNT(*) FILTER (WHERE rating = 4.5),
              COUNT(*) FILTER (WHERE rating = 5.0)
            ]::int[] FROM ratings WHERE visual_novel_id = $1::uuid),
            (SELECT COUNT(*) FROM reviews WHERE visual_novel_id = $1::uuid)
        """,
        [canonical_bin]
      )

    total_sum = RatingDistribution.total_sum(dist)
    avg = RatingDistribution.bayesian_average(3.5, 10, total_sum, counts)

    Repo.update_all(
      from(v in VisualNovel, where: v.id == ^canonical_id),
      set: [
        ratings_count: counts,
        ratings_dist: dist,
        reviews_count: reviews,
        average_rating: avg,
        updated_at: now
      ]
    )
  end

  # ──────────────────────────────────────────────────────────────────────
  # Resolution helpers
  # ──────────────────────────────────────────────────────────────────────

  defp pick_longest_string(rows, key) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.max_by(&String.length/1, fn -> Map.get(hd(rows), key) end)
  end

  defp union_aliases(canonical, sources) do
    canonical_aliases = canonical.aliases || []
    extra = Enum.flat_map(sources, fn s -> [s.title | s.aliases || []] end)

    (canonical_aliases ++ extra)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 == canonical.title))
    |> Enum.uniq()
  end

  defp any_true(rows, key), do: Enum.any?(rows, &Map.get(&1, key))

  defp pick_priority(rows, key, priority_map) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&Map.get(priority_map, &1, 0), fn -> nil end)
  end

  defp pick_priority_atom(rows, key, priority_map) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&Map.get(priority_map, &1, 0), fn -> nil end)
  end

  defp pick_min(rows, key) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      vals -> Enum.min(vals, Date)
    end
  rescue
    # Date.compare doesn't apply to DateTime; fall back to <.
    _ ->
      rows
      |> Enum.map(&Map.get(&1, key))
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)
  end

  defp pick_max(rows, key) do
    rows
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      vals -> Enum.max(vals)
    end
  end

  defp sum(rows, key) do
    rows
    |> Enum.map(&(Map.get(&1, key) || 0))
    |> Enum.sum()
  end

  defp pick_first_non_nil(rows, key) do
    Enum.find_value(rows, fn r -> Map.get(r, key) end)
  end

  defp weighted_avg_decimal(rows, value_key, weight_key) do
    {sum, weight} =
      Enum.reduce(rows, {Decimal.new(0), 0}, fn r, {acc_sum, acc_weight} ->
        v = Map.get(r, value_key)
        w = Map.get(r, weight_key) || 0

        if v == nil or w == 0 do
          {acc_sum, acc_weight}
        else
          v_dec = if is_struct(v, Decimal), do: v, else: Decimal.new(to_string(v))
          {Decimal.add(acc_sum, Decimal.mult(v_dec, Decimal.new(w))), acc_weight + w}
        end
      end)

    if weight == 0 do
      nil
    else
      Decimal.div(sum, Decimal.new(weight)) |> Decimal.round(2)
    end
  end

  defp derive_length_category(0), do: nil
  defp derive_length_category(min) when min < 300, do: "short"
  defp derive_length_category(min) when min < 600, do: "medium"
  defp derive_length_category(min) when min < 1800, do: "long"
  defp derive_length_category(_), do: "very_long"

  defp atom_keyed(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end

  # ──────────────────────────────────────────────────────────────────────
  # SQL fragment helpers
  # ──────────────────────────────────────────────────────────────────────

  # CASE expression that maps a string column's values to their priority
  # integer. For unaliased use (inside ORDER BY where the column isn't
  # ambiguous).
  defp priority_sql(col, priority_map) do
    cases =
      Enum.map_join(priority_map, " ", fn {value, priority} ->
        "WHEN '#{value}' THEN #{priority}"
      end)

    ~s|CASE "#{col}" #{cases} ELSE 0 END|
  end

  defp role_priority_sql(priority_map), do: priority_sql(:role, priority_map)

  # ──────────────────────────────────────────────────────────────────────
  # Dry-run summary
  # ──────────────────────────────────────────────────────────────────────

  defp dry_run_summary(canonical, sources, resolved) do
    %{
      dry_run: true,
      canonical_id: canonical.id,
      canonical_slug: canonical.slug,
      sources: Enum.map(sources, &Map.take(&1, [:id, :slug, :title, :vndb_id])),
      resolved_attrs: resolved
    }
  end
end
