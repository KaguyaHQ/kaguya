defmodule Kaguya.Recommendations do
  @moduledoc """
  Personalized VN recommendations.

  Training (building the EASE B matrix) runs offline in Python — see the
  scripts under `priv/recommendations/`. Inference runs in-process via
  `Kaguya.Recommendations.Nx.Engine` on the EXLA backend; this module is
  the Elixir-side glue:

    * export per-user preferences / masks / likes CSVs for the Nx engine
    * invoke the engine via `GenerateWorker`
    * import the resulting CSV into `user_recommendations`
    * serve top-K rows to product callers (empty list when the user hasn't been
      scored yet — the UI shows a "rate more VNs" empty state rather than
      a popularity fallback, which would pretend to be personalized)

  Training matrix: VNDB votes only — see `docs/architecture/recommendations.md` for the
  full design rationale.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Recommendations.{Feedback, Percentiles, UserVnRecommendation}
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  # Minimum signals a user needs to be included in the batch-scoring run.
  # Below this threshold the inference pipeline can't build a stable
  # preference vector, so the user gets no rows in
  # `user_recommendations` — callers return an empty list and the UI prompts
  # them to rate more VNs.
  @min_signals 3

  @doc "Minimum rating-like signals a user needs to be scored."
  def min_signals, do: @min_signals

  # Status → 1-10 pref value. Only used when the user has NO rating AND NO
  # rec signal (+1 / -1) on that VN — precedence is rating > signal >
  # status, enforced by `export_prefs_csv`. Once a stronger signal exists,
  # these values don't apply.
  #
  # `:not_interested` is listed for reference but is explicitly filtered out
  # of prefs in `export_prefs_csv` — its strong negative value was triggering
  # double-negative EASE boosts (disliked × anti-similar = spurious +score).
  # The item still gets masked from output, so `:not_interested` VNs are
  # never recommended; they just don't train scoring.
  #
  # Rebalanced 2026-04: `:read` (consumed without rating) is the strongest
  # implicit positive — they actually got through it. `:want_to_read` is
  # weaker than `:read` because wishlist is intent (driven by hype/covers/
  # recs from friends), not consumed taste. Previously wishlist sat above
  # `:read` at 7.5, which inflated wishlists' contribution to the user's
  # preference vector and polluted the "because you liked" attribution
  # (audit on @vas: 23% of reasons were wishlisted items the user never
  # actually liked).
  @status_value %{
    # finished, no rating — strongest implicit positive
    read: 7.5,
    # engaged, in progress
    currently_reading: 7.0,
    # intent only, ~user-mean — won't dominate centering
    want_to_read: 6.0,
    # neutral / paused
    on_hold: 5.0,
    # explicit drop, weak negative
    did_not_finish: 3.0,
    # EXCLUDED from prefs (see export_prefs_csv)
    not_interested: 1.5
  }

  # Statuses that count toward the eligibility threshold (anything that
  # signals taste — wishlist / on_hold are intent / ambiguous, ignored here).
  @signal_statuses [:read, :currently_reading, :did_not_finish, :not_interested]

  # Postgres caps a single query at 65535 parameters. Each row has 9 columns
  # (user_id, visual_novel_id, score, ease_score, rank, reasons,
  # total_positive_contribution, model_version, generated_at), so 5,000 rows
  # per insert = 45k params (under the cap with margin).
  @insert_chunk_size 5_000

  # Currently only EASE is generated and served. The `method` column was
  # dropped from `user_recommendations` — any algorithm-identification
  # info lives in `model_version` (e.g. "ease-nx-2026-04-20"). Re-enabling
  # multi-method generation would require adding `method` back to the PK
  # via a migration.
  @method "ease"
  def method, do: @method

  # Rec-feedback signal → 1-10 pref value. Stronger on both sides than
  # statuses because the signal is less ambiguous:
  #
  #   +1 (user clicked "+Wishlist" from a rec) → 8.0
  #     stronger than raw `:want_to_read` (6.0) because it's an explicit
  #     "yes, this is a good rec for me" — not just idle wishlist curiosity.
  #
  #   -1 (user clicked "Not for me" on a rec) → 2.5
  #     stronger than `:did_not_finish` (3.0), weaker than library
  #     `:not_interested` (1.5, still EXCLUDED from prefs due to noise).
  #     Included in training because rec-dismiss is pointwise and clean
  #     ("we recommended this as good for you, you said no") — unlike the
  #     library `:not_interested` status which mixes genre aversion,
  #     content concerns, mood, etc. Case-4 zeroing in `ease_scores`
  #     protects against double-negative spurious boosts.
  @signal_value %{1 => 8.0, -1 => 2.5}

  # ---------------------------------------------------------------------------
  # Query API
  # ---------------------------------------------------------------------------

  @doc "Top-K recommendations for a user, ordered by rank ascending."
  def list_for_user(%User{id: user_id}, opts \\ []), do: list_for_user_id(user_id, opts)

  def list_for_user_id(user_id, opts) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    tag_slug = Keyword.get(opts, :tag_slug)

    base =
      from(r in UserVnRecommendation,
        where: r.user_id == ^user_id,
        where: r.visual_novel_id not in subquery(hidden_via_feedback_vn_ids(user_id)),
        order_by: [asc: r.rank],
        preload: [:visual_novel]
      )

    # Optional tag filter — applied at SQL level so pagination remains
    # consistent across pages (don't load 20 and filter to 3 on the client).
    filtered =
      case tag_slug do
        nil ->
          base

        slug ->
          from(r in base,
            join: vt in "vn_tags",
            on: vt.visual_novel_id == r.visual_novel_id,
            join: t in Kaguya.Tags.Tag,
            on: t.id == vt.tag_id,
            where: t.slug == ^slug
          )
      end

    filtered
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  # Subquery of VN ids this user has acted on via rec feedback — EITHER
  # signal: dismissing (-1) OR wishlisting-from-rec (+1). Both count as
  # "user engaged with this rec, don't show it again in the live list."
  # They differ only in what ELSE happened: dismiss pushes the item down
  # in training, wishlist also adds a library status. Factored out so the
  # three call sites (list_for_user_id, max_score_for, tag_counts_for)
  # share one definition — shape drift would produce inconsistent "what
  # does the user see" answers.
  defp hidden_via_feedback_vn_ids(user_id) do
    from(f in Feedback,
      where: f.user_id == ^user_id,
      select: f.visual_novel_id
    )
  end

  @doc """
  Max rec `score` across a user's stored recs (excluding dismissed items —
  those never surface, so they shouldn't influence the displayed match %).
  Cheap aggregate; used to normalize per-user match % on the client.
  Stable across pagination.
  """
  def max_score_for(user_id) do
    Repo.one(
      from r in UserVnRecommendation,
        where: r.user_id == ^user_id,
        where: r.visual_novel_id not in subquery(hidden_via_feedback_vn_ids(user_id)),
        select: max(r.score)
    )
  end

  @doc """
  Aggregate tag counts across a user's surviving recs. One row per tag the
  user's recs touch, with the number of recs carrying that tag. Returned
  sorted desc by count (most popular tags first).
  """
  def tag_counts_for(user_id) do
    from(r in UserVnRecommendation,
      where: r.user_id == ^user_id,
      where: r.visual_novel_id not in subquery(hidden_via_feedback_vn_ids(user_id)),
      join: vt in "vn_tags",
      on: vt.visual_novel_id == r.visual_novel_id,
      join: t in Kaguya.Tags.Tag,
      on: t.id == vt.tag_id,
      where: t.category == ^:content,
      group_by: [t.slug, t.name],
      order_by: [desc: count(r.visual_novel_id)],
      select: %{slug: t.slug, name: t.name, count: count(r.visual_novel_id)}
    )
    |> Repo.all()
  end

  @doc """
  Hydrate precomputed rec rows into the shape `:recommended_vn` expects.

  Each `because_you_liked` item carries the user's own rating (nullable) on
  the source VN so the UI can render "Subahibi (5)" next to the title.

  Two extra batched queries — one for the reason VNs, one for the user's
  ratings on those VNs. No N+1.
  """
  def hydrate_reasons(recs) when is_list(recs) do
    reason_ids =
      recs
      |> Enum.flat_map(fn r -> Enum.map(r.reasons, &reason_vn_id/1) end)
      |> Enum.uniq()

    rec_vn_ids = recs |> Enum.map(& &1.visual_novel_id) |> Enum.uniq()
    user_ids = recs |> Enum.map(& &1.user_id) |> Enum.uniq()

    reason_lookup = lookup_vns_by_id(reason_ids)
    rating_lookup = lookup_user_ratings(user_ids, reason_ids)
    status_lookup = lookup_user_statuses(user_ids, reason_ids)
    # Statuses for the rec's own VN (the candidate) — drives the "hide
    # wishlisted" filter. The filter applies to the PROFILE OWNER's library
    # (rec.user_id), not the viewer's, because the recs are for the profile
    # owner and "already wishlisted" is only meaningful in their library.
    rec_status_lookup = lookup_user_statuses(user_ids, rec_vn_ids)
    signal_lookup = lookup_user_signals(user_ids, rec_vn_ids)

    Enum.map(recs, fn r ->
      %{
        visual_novel: r.visual_novel,
        rank: r.rank,
        score: r.score,
        ease_score: r.ease_score,
        relevance_pct: Percentiles.relevance_pct(r.score),
        total_positive_contribution: r.total_positive_contribution,
        user_signal: Map.get(signal_lookup, {r.user_id, r.visual_novel_id}),
        user_reading_status:
          case Map.get(rec_status_lookup, {r.user_id, r.visual_novel_id}) do
            nil -> nil
            # Status consumers expect an object with a `status` field; the
            # lookup returns just the atom, so wrap it.
            status -> %{status: status}
          end,
        because_you_liked: build_reasons(r, reason_lookup, rating_lookup, status_lookup)
      }
    end)
  end

  # JSONB maps come back from Ecto with string keys; writers (importer +
  # pregen) also use string keys for consistency. Support both so
  # in-memory maps built via the changeset API don't fall through.
  defp reason_vn_id(%{"visual_novel_id" => id}), do: id
  defp reason_vn_id(%{visual_novel_id: id}), do: id

  defp reason_contribution(%{"contribution" => c}), do: c
  defp reason_contribution(%{contribution: c}), do: c

  defp build_reasons(rec, vn_lookup, rating_lookup, status_lookup) do
    Enum.flat_map(rec.reasons, fn reason ->
      vid = reason_vn_id(reason)

      case Map.fetch(vn_lookup, vid) do
        {:ok, vn} ->
          rating = Map.get(rating_lookup, {rec.user_id, vid})
          status = Map.get(status_lookup, {rec.user_id, vid})

          [
            %{
              visual_novel: vn,
              user_rating: rating,
              # Status is only meaningful when there's no rating — a rated
              # item already conveys "consumed + opinion", showing both is
              # noise. Frontend uses status to pick the right verb when
              # there's no rating ("you wishlisted X" vs "you liked X").
              user_status: if(is_nil(rating), do: status, else: nil),
              contribution: reason_contribution(reason)
            }
          ]

        :error ->
          []
      end
    end)
  end

  defp lookup_vns_by_id([]), do: %{}

  defp lookup_vns_by_id(ids) do
    from(vn in VisualNovel, where: vn.id in ^ids, select: {vn.id, vn})
    |> Repo.all()
    |> Map.new()
  end

  defp lookup_user_ratings([], _), do: %{}
  defp lookup_user_ratings(_, []), do: %{}

  defp lookup_user_ratings(user_ids, vn_ids) do
    from(r in Rating,
      where: r.user_id in ^user_ids and r.visual_novel_id in ^vn_ids,
      select: {{r.user_id, r.visual_novel_id}, r.rating}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp lookup_user_statuses([], _), do: %{}
  defp lookup_user_statuses(_, []), do: %{}

  defp lookup_user_statuses(user_ids, vn_ids) do
    from(s in ReadingStatus,
      where: s.user_id in ^user_ids and s.visual_novel_id in ^vn_ids,
      select: {{s.user_id, s.visual_novel_id}, s.status}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp lookup_user_signals([], _), do: %{}
  defp lookup_user_signals(_, []), do: %{}

  defp lookup_user_signals(user_ids, vn_ids) do
    from(f in Feedback,
      where: f.user_id in ^user_ids and f.visual_novel_id in ^vn_ids,
      select: {{f.user_id, f.visual_novel_id}, f.signal}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Most recent `generated_at` timestamp on this user's stored recs, or nil
  if none. Used by the refresh endpoint to enforce a per-user rate limit.
  """
  def last_generated_at(user_id) do
    Repo.one(
      from r in UserVnRecommendation,
        where: r.user_id == ^user_id,
        select: max(r.generated_at)
    )
  end

  @doc """
  How many rating-like signals this user has (ratings + reading statuses that
  count as taste evidence). The refresh endpoint gates on this: users with
  fewer than `@min_signals` can't generate recs, since the Nx engine needs
  enough preference vector entries to produce stable scores.
  """
  def signals_count(user_id) do
    rating_count =
      Repo.one(from r in Rating, where: r.user_id == ^user_id, select: count(r.id)) || 0

    status_count =
      Repo.one(
        from s in ReadingStatus,
          where: s.user_id == ^user_id and s.status in ^@signal_statuses,
          select: count(s.id)
      ) || 0

    rating_count + status_count
  end

  # 5-minute cooldown measured from the LAST SUCCESSFUL generation
  # (`last_generated_at`), not from the last click. A failed refresh never
  # touches the clock, so users can retry immediately.
  @refresh_cooldown_seconds 5 * 60

  @doc """
  Synchronously regenerate recommendations for one user.

  Shared by LiveView and controller callers so the refresh contract lives
  in the recommendations context instead of a web-specific module.
  """
  def refresh_for_user(user_id) do
    if signals_count(user_id) < min_signals() do
      {:error, "Not enough data to recommend."}
    else
      case last_generated_at(user_id) do
        nil ->
          run_sync_refresh(user_id)

        %DateTime{} = last ->
          elapsed = DateTime.diff(DateTime.utc_now(), last, :second)

          if elapsed >= @refresh_cooldown_seconds do
            run_sync_refresh(user_id)
          else
            {:error, format_cooldown_wait(@refresh_cooldown_seconds - elapsed)}
          end
      end
    end
  end

  defp format_cooldown_wait(seconds) do
    minutes = div(seconds + 59, 60)
    unit = if minutes == 1, do: "minute", else: "minutes"
    "Try again in #{minutes} #{unit}."
  end

  defp run_sync_refresh(user_id) do
    job = %Oban.Job{args: %{"user_ids" => [user_id]}}

    case Kaguya.Recommendations.GenerateWorker.perform(job) do
      {:ok, {:ok, _multi}} ->
        {:ok, true}

      {:ok, :no_eligible_users} ->
        {:ok, true}

      {:ok, {:error, _reason}} ->
        {:error, "Failed to refresh recommendations — please try again."}
    end
  end

  @doc """
  Wipe rec state for a user: precomputed rows AND feedback signals. Called
  from `Users.reset_library` and similar flows that invalidate training
  inputs (their ratings/statuses are gone, so old rec rows no longer
  reflect what the user has signaled).

  Hard account deletion is covered by the DB `ON DELETE CASCADE` on both
  `user_recommendations.user_id` and `user_recommendation_feedback.user_id`, so
  this function is NOT needed there — it's for wiping state while keeping
  the user row alive.
  """
  def clear_for_user(user_id) do
    Repo.transact(fn ->
      Repo.delete_all(from r in UserVnRecommendation, where: r.user_id == ^user_id)
      Repo.delete_all(from f in Feedback, where: f.user_id == ^user_id)
      {:ok, :ok}
    end)
  end

  @doc "User ids with at least `@min_signals` rating-like signals — eligible for batch."
  def list_eligible_user_ids do
    rating_counts =
      group_count(from r in Rating, group_by: r.user_id, select: {r.user_id, count(r.id)})

    status_counts =
      group_count(
        from(s in ReadingStatus,
          where: s.status in ^@signal_statuses,
          group_by: s.user_id,
          select: {s.user_id, count(s.id)}
        )
      )

    rating_counts
    |> Map.merge(status_counts, fn _k, v1, v2 -> v1 + v2 end)
    |> Enum.filter(fn {_u, n} -> n >= @min_signals end)
    |> Enum.map(fn {u, _} -> u end)
  end

  defp group_count(query), do: query |> Repo.all() |> Map.new()

  # ---------------------------------------------------------------------------
  # Feedback mutations (rec-card actions)
  # ---------------------------------------------------------------------------

  @doc """
  User clicked "+Wishlist" on a rec card. Atomic: upserts a
  `:want_to_read` row in `reading_statuses` AND a `signal: +1` row in
  `user_recommendation_feedback` (so we retain rec-provenance — "this wishlist
  came from a rec").

  `set_reading_status` has upsert semantics: if the user already has a
  non-`:want_to_read` status on this VN (e.g. `:read`, `:currently_reading`),
  this would overwrite it. In practice that can't happen through the UI —
  the mask exporter excludes everything except `:want_to_read` from being
  masked (see `export_masks_csv`), so only `:want_to_read` VNs can reach
  `user_recommendations` with a pre-existing library status, and
  overwriting `:want_to_read` with `:want_to_read` is a no-op. If this
  gets called outside the rec-card flow, that invariant is the caller's
  responsibility.

  The signal row carries a different semantic than the status row: the
  status is the user's intent toward the VN (true regardless of source),
  the signal captures rec-system engagement specifically. See the
  `@signal_value` comment for how the signal feeds training.
  """
  def wishlist_from_rec(user_id, vn_id) do
    Repo.transact(fn ->
      _ = Kaguya.Shelves.set_reading_status(user_id, vn_id, %{status: :want_to_read})
      set_signal(user_id, vn_id, 1)
      {:ok, :ok}
    end)
  end

  @doc """
  Inverse of `wishlist_from_rec/2` — user clicked the "Wishlisted" state
  to un-wishlist. Atomic: deletes the `:want_to_read` status row AND the
  `signal: +1` feedback row. Mirror of `undo_recommendation_dismiss/2`.

  Only deletes a status row that is currently `:want_to_read`, so if the
  user somehow has a stronger status (`:read`, etc.) on the VN we don't
  clobber it. Similarly, only signal=+1 rows are deleted — a stray -1
  (dismiss) isn't touched by this path.
  """
  def undo_wishlist_from_rec(user_id, vn_id) do
    Repo.transact(fn ->
      {_status_deleted, _} =
        Repo.delete_all(
          from s in ReadingStatus,
            where:
              s.user_id == ^user_id and
                s.visual_novel_id == ^vn_id and
                s.status == :want_to_read
        )

      {n, _} =
        Repo.delete_all(
          from f in Feedback,
            where:
              f.user_id == ^user_id and
                f.visual_novel_id == ^vn_id and
                f.signal == 1
        )

      {:ok, n}
    end)
  end

  @doc """
  User clicked "Not for me" on a rec. Writes `signal: -1`. The rec gets
  hidden from `/recs` on next read (see `hidden_via_feedback_vn_ids/1`) and gets
  pushed down in future training rounds (negative pref). Idempotent —
  repeat dismiss of same (user, vn) just updates `updated_at`.
  """
  def dismiss_recommendation(user_id, vn_id),
    do: set_signal(user_id, vn_id, -1)

  @doc """
  User clicked "Undo" on a recently-dismissed rec. Deletes the signal row
  so the item reappears in the live rec list and drops out of the
  training signal set.
  """
  def undo_recommendation_dismiss(user_id, vn_id) do
    from(f in Feedback,
      where: f.user_id == ^user_id and f.visual_novel_id == ^vn_id and f.signal == -1
    )
    |> Repo.delete_all()
    |> case do
      {n, _} -> {:ok, n}
    end
  end

  @doc "Fetch the current signal value for (user, vn), or nil."
  def get_signal(user_id, vn_id) do
    Repo.one(
      from(f in Feedback,
        where: f.user_id == ^user_id and f.visual_novel_id == ^vn_id,
        select: f.signal
      )
    )
  end

  defp set_signal(user_id, vn_id, signal) when signal in [-1, 1] do
    now = DateTime.utc_now()

    attrs = %{
      user_id: user_id,
      visual_novel_id: vn_id,
      signal: signal,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(Feedback, [attrs],
      on_conflict: {:replace, [:signal, :updated_at]},
      conflict_target: [:user_id, :visual_novel_id]
    )

    {:ok, :ok}
  end

  # ---------------------------------------------------------------------------
  # Export — writes prefs/masks CSVs that the Nx engine reads
  # ---------------------------------------------------------------------------

  @doc """
  Writes two CSVs to `<prefix>_{prefs,masks}.csv` for the inference
  pipeline. Returns a map of their paths.
  """
  def export_user_data(prefix, user_ids) when is_list(user_ids) do
    %{
      prefs: export_prefs_csv("#{prefix}_prefs.csv", user_ids),
      masks: export_masks_csv("#{prefix}_masks.csv", user_ids)
    }
  end

  @doc """
  Per-user prefs. Priority for a given (user, vn):

      rating > signal > status

  Rating wins because it's ground truth after consumption. Signal wins over
  status because "I engaged with this rec positively/negatively" is a more
  explicit taste signal than any library status. Status is the weakest
  positive / negative indicator.
  """
  def export_prefs_csv(path, user_ids) do
    rating_rows =
      from(r in Rating,
        join: vn in VisualNovel,
        on: vn.id == r.visual_novel_id,
        where: r.user_id in ^user_ids,
        where: not is_nil(vn.vndb_id),
        select: {r.user_id, r.visual_novel_id, vn.vndb_id, r.rating}
      )
      |> Repo.all()

    signal_rows =
      from(f in Feedback,
        join: vn in VisualNovel,
        on: vn.id == f.visual_novel_id,
        where: f.user_id in ^user_ids,
        where: not is_nil(vn.vndb_id),
        select: {f.user_id, f.visual_novel_id, vn.vndb_id, f.signal}
      )
      |> Repo.all()

    status_rows =
      from(s in ReadingStatus,
        join: vn in VisualNovel,
        on: vn.id == s.visual_novel_id,
        where: s.user_id in ^user_ids,
        where: not is_nil(vn.vndb_id),
        select: {s.user_id, s.visual_novel_id, vn.vndb_id, s.status}
      )
      |> Repo.all()

    rated_pairs = MapSet.new(rating_rows, fn {u, vn_id, _, _} -> {u, vn_id} end)
    signal_pairs = MapSet.new(signal_rows, fn {u, vn_id, _, _} -> {u, vn_id} end)

    write_csv(path, ["user_id", "vndb_id", "value"], fn write ->
      for {uid, _vn_id, vndb_id, rating} <- rating_rows do
        write.([uid, vndb_id, rating * 2.0])
      end

      # Signal loses to rating — a rating is ground truth after consumption,
      # signal is a pre-consumption "more/less like this" indicator. Writing
      # both would double-weight the item in the pref vector.
      for {uid, vn_id, vndb_id, signal} <- signal_rows,
          {uid, vn_id} not in rated_pairs,
          val = Map.get(@signal_value, signal),
          val != nil do
        write.([uid, vndb_id, val])
      end

      # `not_interested` is excluded from prefs: the "I don't want to see
      # this again" signal is noisy as a taste indicator (people mark it
      # for many reasons — aesthetics, content concerns, genre aversion).
      # Leaving it in triggered unreliable double-negative boosts in EASE
      # scoring (centered-negative × anti-correlated-similarity = boost),
      # surfacing candidates that didn't match user positive signals. It
      # stays in `export_masks_csv` so these items are never recommended.
      for {uid, vn_id, vndb_id, status} <- status_rows,
          status != :not_interested,
          {uid, vn_id} not in rated_pairs,
          {uid, vn_id} not in signal_pairs,
          val = Map.get(@status_value, status),
          val != nil do
        write.([uid, vndb_id, val])
      end
    end)

    path
  end

  @doc """
  Mask: every (user, vn) pair the user has committed on — ratings, completed
  or rejected reading statuses, rec feedback. `want_to_read` is DELIBERATELY
  not masked: wishlisted items can appear as recs so the user sees a match-%
  prediction for what they already flagged as interesting. The UI has a
  "hide wishlisted" toggle for users who want to suppress them.
  """
  def export_masks_csv(path, user_ids) do
    status_mask_pairs =
      from(s in ReadingStatus,
        join: vn in VisualNovel,
        on: vn.id == s.visual_novel_id,
        where: s.user_id in ^user_ids,
        where: not is_nil(vn.vndb_id),
        where: s.status != :want_to_read,
        select: {s.user_id, vn.vndb_id}
      )
      |> Repo.all()

    pairs =
      Enum.uniq(
        user_vn_pairs(user_ids, Rating) ++
          status_mask_pairs ++
          user_vn_pairs(user_ids, Feedback)
      )

    write_pairs_csv(path, pairs)
  end

  # Generic {user_id, vndb_id} pairs from any user-VN association table.
  # Both Rating and ReadingStatus have a `user_id` and `visual_novel_id`
  # column, so a single helper covers both via the schema module.
  defp user_vn_pairs(user_ids, schema) do
    from(t in schema,
      join: vn in VisualNovel,
      on: vn.id == t.visual_novel_id,
      where: t.user_id in ^user_ids,
      where: not is_nil(vn.vndb_id),
      select: {t.user_id, vn.vndb_id}
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Import — reads the scored CSV written by the worker and upserts rows
  # ---------------------------------------------------------------------------

  @doc """
  Read the CSV written by `GenerateWorker` and upsert rows. For each user
  appearing in the CSV, that user's previous rec rows are deleted first —
  no stale ranks.
  """
  def import_recommendations_csv(path, model_version) do
    parsed = parse_recommendations_csv(path)

    if parsed == [] do
      {:ok, %{insert: {0, nil}, clear: {0, nil}}}
    else
      do_import(parsed, model_version)
    end
  end

  defp do_import(parsed, model_version) do
    now = DateTime.utc_now()

    vndb_ids =
      parsed
      |> Enum.flat_map(fn r ->
        [r.vndb_id | Enum.map(r.reasons, & &1.vndb_id)]
      end)
      |> Enum.uniq()

    vn_lookup = vndb_to_vn_id_map(vndb_ids)
    user_ids = parsed |> Enum.map(& &1.user_id) |> Enum.uniq()

    rows =
      parsed
      |> Stream.map(&to_db_row(&1, vn_lookup, model_version, now))
      |> Stream.reject(&is_nil/1)
      |> Enum.to_list()

    Multi.new()
    |> Multi.delete_all(
      :clear,
      from(r in UserVnRecommendation, where: r.user_id in ^user_ids)
    )
    |> add_insert_chunks(rows)
    |> Repo.transaction()
  end

  defp to_db_row(parsed_row, vn_lookup, model_version, generated_at) do
    case Map.fetch(vn_lookup, parsed_row.vndb_id) do
      {:ok, vn_id} ->
        resolved_reasons =
          parsed_row.reasons
          |> Enum.flat_map(fn r ->
            case Map.fetch(vn_lookup, r.vndb_id) do
              {:ok, id} ->
                [%{"visual_novel_id" => id, "contribution" => r.contribution}]

              :error ->
                []
            end
          end)

        %{
          user_id: parsed_row.user_id,
          visual_novel_id: vn_id,
          score: parsed_row.score,
          ease_score: parsed_row.ease_score,
          rank: parsed_row.rank,
          reasons: resolved_reasons,
          total_positive_contribution: parsed_row.total_positive_contribution,
          model_version: model_version,
          generated_at: generated_at
        }

      :error ->
        nil
    end
  end

  defp add_insert_chunks(multi, rows) do
    rows
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {chunk, idx}, acc ->
      Multi.insert_all(acc, {:insert, idx}, UserVnRecommendation, chunk,
        on_conflict: :replace_all,
        conflict_target: [:user_id, :visual_novel_id]
      )
    end)
  end

  defp parse_recommendations_csv(path) do
    path
    |> File.stream!()
    |> Stream.with_index()
    |> Stream.reject(fn {_line, i} -> i == 0 end)
    |> Stream.map(fn {line, _} -> parse_recommendation_line(String.trim_trailing(line)) end)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
  end

  # CSV columns: user_id, vndb_id, score, ease_score, rank, reasons,
  # total_positive_contribution. `reasons` is pipe-delimited
  # "<vndb_id>:<contrib>|..." — paired so the importer can store the raw
  # contribution values the frontend needs for percentage display.
  defp parse_recommendation_line(line) do
    with [user_id, vndb_id, score, ease_score, rank, reasons, total_positive] <-
           String.split(line, ","),
         {:ok, uuid} <- Ecto.UUID.cast(user_id),
         {score_f, _} <- Float.parse(score),
         {ease_f, _} <- Float.parse(ease_score),
         {rank_i, _} <- Integer.parse(rank),
         {total_pos_f, _} <- Float.parse(total_positive) do
      %{
        user_id: uuid,
        vndb_id: vndb_id,
        score: score_f,
        ease_score: ease_f,
        rank: rank_i,
        reasons: parse_reasons(reasons),
        total_positive_contribution: total_pos_f
      }
    else
      _ -> nil
    end
  end

  defp parse_reasons(""), do: []

  defp parse_reasons(reasons) do
    reasons
    |> String.split("|", trim: true)
    |> Enum.flat_map(fn entry ->
      case String.split(entry, ":", parts: 2) do
        [vndb_id, contrib_str] ->
          case Float.parse(contrib_str) do
            {contrib, _} -> [%{vndb_id: vndb_id, contribution: contrib}]
            :error -> []
          end

        _ ->
          []
      end
    end)
  end

  defp vndb_to_vn_id_map(vndb_ids) do
    from(vn in VisualNovel,
      where: vn.vndb_id in ^vndb_ids,
      select: {vn.vndb_id, vn.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_csv(path, header, body_fn) do
    File.mkdir_p!(Path.dirname(path))

    File.open!(path, [:write, :utf8], fn io ->
      IO.binwrite(io, Enum.join(header, ",") <> "\n")
      body_fn.(fn row -> IO.binwrite(io, Enum.map_join(row, ",", &csv_field/1) <> "\n") end)
    end)
  end

  defp write_pairs_csv(path, pairs) do
    write_csv(path, ["user_id", "vndb_id"], fn write ->
      Enum.each(pairs, fn {uid, vid} -> write.([uid, vid]) end)
    end)

    path
  end

  defp csv_field(v) when is_float(v), do: :erlang.float_to_binary(v, [:compact, decimals: 4])
  defp csv_field(v) when is_binary(v), do: v
  defp csv_field(v) when is_atom(v), do: Atom.to_string(v)
  defp csv_field(v), do: to_string(v)
end
