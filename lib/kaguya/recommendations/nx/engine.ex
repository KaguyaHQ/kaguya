defmodule Kaguya.Recommendations.Nx.Engine do
  @moduledoc """
  In-process EASE scoring pipeline.

  Training (producing the B matrix) is a separate offline step that still
  runs in Python — see `priv/recommendations/`. Inference runs here,
  end-to-end in the BEAM via Nx on the EXLA backend — no Python process
  in prod.

  Trained B matrices (`priv/data/*_B.npy`) are loaded via `Npy.load!/1`.

  Public entry point: `score_user/3`. Invoked per-user by
  `Kaguya.Recommendations.GenerateWorker`.
  """

  import Ecto.Query, only: [from: 2]
  import Nx.Defn

  alias Kaguya.Recommendations.Nx.Npy
  alias Kaguya.Recommendations.Percentiles
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel

  @min_prefs 3
  @n_reasons 3

  # Fallback: when centered scoring produces fewer than
  # @fallback_min_recs positive candidates (typical of whales + harsh
  # raters with broad distributions), rescore using the user's top-N
  # rated items with raw values. Centering + Case-4 zeroing interact
  # asymmetrically for users whose pref distribution puts many items
  # on both sides of their mean — boost mass gets eaten while penalty
  # mass survives, biasing scores negative. Bounding to the top rated
  # items concentrates signal and avoids the whole centering issue.
  @fallback_top_n 100
  @fallback_min_recs 3

  # Output-side vote-count floor for served recs. VNs below this stay in
  # training (their correlations help position neighbors in the Gram
  # matrix), they just can't surface as a recommendation. Mirrors the
  # `--min-display-votes` knob on the similar-VNs pipeline
  # (`priv/repo/scripts/ease/ease_similarity.py`). Keep this in sync with
  # the Python pregen's `MIN_DISPLAY_VOTES`.
  @min_display_votes 100

  # EASE is the only retrieval model we currently serve — the `method` column
  # on `user_recommendations` was dropped, algorithm identity now lives in
  # `model_version`. Swapping this back to a runtime arg is straightforward
  # if we ever add a second model.
  @method "ease"

  @type vndb_id :: String.t()
  @type pref_row :: %{vndb_id: vndb_id, value: float}
  @type reason :: %{vndb_id: vndb_id, contribution: float}
  @type rec_row :: %{
          rank: pos_integer,
          vndb_id: vndb_id,
          final_score: float,
          ease_score: float,
          reasons: [reason],
          total_positive_contribution: float
        }

  @doc """
  Score one user. Inputs are the per-user row lists the worker loads from
  the exported prefs / masks CSVs.

  Returns `nil` if the user has fewer than `@min_prefs` vocabulary-matched
  prefs (cold start — the Elixir resolver returns an empty page in that
  case, and the UI prompts the user to rate more VNs).
  """
  @spec score_user([pref_row], [vndb_id], keyword) :: [rec_row] | nil
  def score_user(prefs_rows, mask_rows, opts \\ []) do
    n_final = Keyword.get(opts, :n_final, 100)

    ctx = load_context!()
    {pref_idx, pref_val_centered} = build_pref_vector(prefs_rows, ctx)

    if is_nil(pref_idx) do
      nil
    else
      # Primary: centered scoring with Case-4 zeroing. Fall through to
      # top-N fallback when the primary's positive count is below the
      # useful minimum — 1-2 picks is effectively the same as zero.
      primary =
        case score_with(ctx, pref_idx, pref_val_centered, mask_rows, n_final) do
          {:ok, rows} -> rows
          :no_positives -> []
        end

      if length(primary) >= @fallback_min_recs do
        primary
      else
        case build_topn_pref_vector(prefs_rows, ctx) do
          {fb_idx, fb_vals} ->
            # Mask covers every pref the user has (not just the
            # top-N we fed to scoring), so rank-N+1 items below the
            # fallback cut can't come back as recs.
            full_mask = Enum.uniq(mask_rows ++ Enum.map(prefs_rows, & &1.vndb_id))

            case score_with(ctx, fb_idx, fb_vals, full_mask, n_final) do
              {:ok, rows} ->
                # Rescale fallback scores so they mix cleanly into
                # the percentile distribution (fallback raw is ~10x
                # primary; without this their recs saturate at 99%+
                # on display). Scale comes from pregen's meta and is
                # cached in Percentiles.
                rescale_fallback(rows, Percentiles.fallback_score_scale())

              :no_positives ->
                primary
            end

          nil ->
            primary
        end
      end
    end
  end

  # Rescale fallback-generated recs so their scores fit in the same
  # distribution as primary-path scores. The scale factor was chosen
  # at pregen time to align fallback's p99 with primary's p99.
  # total_positive_contribution and each reason's contribution also
  # scale so the tooltip's `contribution / total_positive` ratio is
  # preserved bit-for-bit.
  defp rescale_fallback(rows, 1.0), do: rows

  defp rescale_fallback(rows, scale) when is_float(scale) do
    Enum.map(rows, fn row ->
      %{
        row
        | final_score: row.final_score * scale,
          ease_score: row.ease_score * scale,
          total_positive_contribution: row.total_positive_contribution * scale,
          reasons:
            Enum.map(row.reasons, fn r ->
              %{r | contribution: r.contribution * scale}
            end)
      }
    end)
  end

  defp score_with(ctx, pref_idx, pref_vals, mask_rows, n_final) do
    scores = ease_scores(ctx.b, pref_idx, pref_vals)
    mask = build_mask_array(ctx, mask_rows)
    neg_inf = Nx.Constants.neg_infinity(Nx.type(scores))

    scores = Nx.select(mask, neg_inf, scores)
    scores = suppress_prefs(scores, pref_idx)

    scores =
      Nx.select(
        Nx.equal(ctx.recommendable_mask, Nx.u8(0)),
        neg_inf,
        scores
      )

    # Drop non-positive scores.
    scores = Nx.select(Nx.greater(scores, 0.0), scores, neg_inf)

    n_finite =
      scores
      |> Nx.is_infinity()
      |> Nx.logical_not()
      |> Nx.sum()
      |> Nx.to_number()

    n_pick = min(n_final, n_finite)

    if n_pick == 0 do
      :no_positives
    else
      top_items = top_k_desc(scores, n_pick)
      {:ok, build_rec_rows(ctx, top_items, scores, pref_idx, pref_vals)}
    end
  end

  # Mask the user's own pref indices with -inf so they can't be recommended
  # back. `Nx.indexed_put` wants indices shaped `{n, rank}`; pref_idx is a
  # 1-D vector so we add a trailing axis.
  defnp suppress_prefs(scores, pref_idx) do
    neg_inf = Nx.Constants.neg_infinity(Nx.type(scores))
    updates = Nx.broadcast(neg_inf, Nx.shape(pref_idx))
    Nx.indexed_put(scores, Nx.new_axis(pref_idx, 1), updates)
  end

  # EASE retrieval with Case-4 double-negative zeroing. defn: compiles to an
  # Nx expression graph so the whole pass is one shot of ops (no per-user
  # Elixir overhead on the hot path).
  defn ease_scores(b, pref_idx, pref_val_centered) do
    b_slice = Nx.take(b, pref_idx, axis: 0)

    pref_col = Nx.new_axis(pref_val_centered, 1)
    contribs = pref_col * b_slice

    # Case-4 zeroing: when (pref < 0) AND (B < 0), the math yields a spurious
    # positive ("you disliked X, candidate is anti-similar to X, so boost").
    # Zero that quadrant. Other three cases (liked×similar boost, liked×anti
    # penalty, disliked×similar penalty) stay intact.
    spurious = Nx.logical_and(pref_col < 0, b_slice < 0)
    contribs = Nx.select(spurious, 0.0, contribs)

    Nx.sum(contribs, axes: [0])
  end

  # ---------------------------------------------------------------------------
  # Masking + top-K selection
  # ---------------------------------------------------------------------------

  defp build_mask_array(ctx, mask_vndb_ids) do
    indices =
      mask_vndb_ids
      |> Enum.flat_map(fn vid ->
        case Map.get(ctx.vndb_to_idx, vid) do
          nil -> []
          i -> [i]
        end
      end)

    mask = Nx.broadcast(Nx.u8(0), {ctx.n_items})

    case indices do
      [] ->
        mask

      _ ->
        Nx.indexed_put(
          mask,
          Nx.tensor(Enum.map(indices, fn i -> [i] end)),
          Nx.broadcast(Nx.u8(1), {length(indices)})
        )
    end
  end

  defp top_k_desc(scores, k) do
    # argsort ascending then slice the tail; Nx doesn't ship topk yet.
    n = Nx.size(scores)
    sorted_indices = Nx.argsort(scores)
    Nx.slice(sorted_indices, [n - k], [k]) |> Nx.reverse()
  end

  # ---------------------------------------------------------------------------
  # Build output rec rows with "because you liked" attribution
  # ---------------------------------------------------------------------------

  defp build_rec_rows(ctx, top_items, scores, pref_idx, pref_val_centered) do
    top_list = Nx.to_flat_list(top_items)
    scores_list = Nx.to_flat_list(scores)
    pref_idx_list = Nx.to_flat_list(pref_idx)
    pref_val_list = Nx.to_flat_list(pref_val_centered)

    # Pre-fetch the pref rows of B, restrict to just the picked columns,
    # transpose so each row == one pick's column of b_pref_rows. All in one
    # Nx crossing; the per-rec `compute_reasons` does pure-Elixir tuple
    # lookup.
    b_cols_by_pick =
      ctx.b
      |> Nx.take(pref_idx, axis: 0)
      |> Nx.take(top_items, axis: 1)
      |> Nx.transpose()
      |> Nx.to_list()
      |> List.to_tuple()

    top_list
    |> Enum.with_index(1)
    |> Enum.map(fn {j, rank} ->
      ease = Enum.at(scores_list, j)
      b_col = elem(b_cols_by_pick, rank - 1)
      rec_vndb_id = elem(ctx.idx_to_vndb, j)

      sorted_contribs =
        score_contributions(b_col, pref_idx_list, pref_val_list, ctx)

      total_positive =
        sorted_contribs
        |> Enum.reduce(0.0, fn c, acc -> acc + c.contrib end)

      reasons =
        sorted_contribs
        |> Enum.take(@n_reasons)
        |> Enum.map(fn c -> %{vndb_id: c.vndb_id, contribution: c.contrib} end)

      %{
        rank: rank,
        vndb_id: rec_vndb_id,
        final_score: ease,
        ease_score: ease,
        reasons: reasons,
        total_positive_contribution: total_positive
      }
    end)
  end

  # Returns the full sorted list of positive contributors, each as
  # `%{vndb_id, pref, b, contrib}`. `compute_reasons`-style callers can
  # take the first N ids; the debug logger takes top-5 with all fields.
  defp score_contributions(b_col, pref_idx_list, pref_val_list, ctx) do
    pref_val_list
    |> Enum.zip(b_col)
    |> Enum.zip(pref_idx_list)
    |> Enum.map(fn {{pref, b}, idx} ->
      contrib = if pref < 0 and b < 0, do: 0.0, else: pref * b
      %{idx: idx, pref: pref, b: b, contrib: contrib}
    end)
    |> Enum.filter(&(&1.pref > 0 and &1.contrib > 0))
    |> Enum.sort_by(&(-&1.contrib))
    |> Enum.map(&Map.put(&1, :vndb_id, elem(ctx.idx_to_vndb, &1.idx)))
  end

  # ---------------------------------------------------------------------------
  # Preference vector construction
  # ---------------------------------------------------------------------------

  defp build_pref_vector(prefs_rows, ctx) do
    pref_items =
      prefs_rows
      |> Enum.flat_map(fn row ->
        case Map.get(ctx.vndb_to_idx, row.vndb_id) do
          nil -> []
          idx -> [{idx, row.value * 1.0}]
        end
      end)

    if length(pref_items) < @min_prefs do
      {nil, nil}
    else
      indices = Enum.map(pref_items, fn {i, _} -> i end)
      values = Enum.map(pref_items, fn {_, v} -> v end)
      mean = Enum.sum(values) / length(values)
      centered = Enum.map(values, &(&1 - mean))

      {Nx.tensor(indices, type: {:s, 64}), Nx.tensor(centered, type: {:f, 32})}
    end
  end

  # Fallback input: top-N prefs by raw value, no centering. Returns nil
  # when fewer than @min_prefs vocab-matched prefs exist (same gate as
  # primary — if we can't build the primary, we can't build the
  # fallback either).
  defp build_topn_pref_vector(prefs_rows, ctx) do
    pref_items =
      prefs_rows
      |> Enum.flat_map(fn row ->
        case Map.get(ctx.vndb_to_idx, row.vndb_id) do
          nil -> []
          idx -> [{idx, row.value * 1.0}]
        end
      end)
      |> Enum.sort_by(fn {_, v} -> -v end)
      |> Enum.take(@fallback_top_n)

    if length(pref_items) < @min_prefs do
      nil
    else
      indices = Enum.map(pref_items, fn {i, _} -> i end)
      values = Enum.map(pref_items, fn {_, v} -> v end)

      {Nx.tensor(indices, type: {:s, 64}), Nx.tensor(values, type: {:f, 32})}
    end
  end

  # ---------------------------------------------------------------------------
  # Context loading — B matrix + id ↔ index maps
  # ---------------------------------------------------------------------------

  # Load once; cache via `:persistent_term` since the B matrix is ~510MB
  # and we don't want to re-parse on every score_user call.
  defp load_context! do
    key = {__MODULE__, :context, @method}

    case :persistent_term.get(key, :miss) do
      :miss ->
        ctx = do_load_context!()
        :persistent_term.put(key, ctx)
        ctx

      ctx ->
        ctx
    end
  end

  defp do_load_context! do
    # Prod mounts the trained B matrix at a host-managed volume (`KAGUYA_MODEL_DIR`)
    # so the image stays small and the model can be updated without a redeploy.
    # Dev falls back to the app's priv dir.
    root = System.get_env("KAGUYA_MODEL_DIR") || Application.app_dir(:kaguya, "priv/data")
    t0 = System.monotonic_time(:millisecond)
    IO.puts("[Nx] loading #{@method}_B.npy from #{root} (~500MB)...")
    b = Npy.load!(Path.join(root, "#{@method}_B.npy"))
    {n_items, _} = Nx.shape(b)

    meta = File.read!(Path.join(root, "#{@method}_B_meta.json")) |> Jason.decode!()

    idx_to_vndb = meta["idx_to_vndb"] |> List.to_tuple()
    vndb_to_idx = idx_to_vndb |> Tuple.to_list() |> Enum.with_index() |> Map.new()

    recommendable_mask = build_recommendable_mask(idx_to_vndb, n_items)

    IO.puts("[Nx] context loaded in #{System.monotonic_time(:millisecond) - t0}ms")

    %{
      b: b,
      n_items: n_items,
      idx_to_vndb: idx_to_vndb,
      vndb_to_idx: vndb_to_idx,
      recommendable_mask: recommendable_mask
    }
  end

  # Build the recommendable mask from Kaguya's own `visual_novels` table.
  # `1` = VN has enough community votes (from the weekly VNDB sync) to
  # surface as a rec; `0` = too niche, suppress at output time regardless
  # of score. One indexed query at context-load time; cached in
  # `:persistent_term` alongside the B matrix.
  defp build_recommendable_mask(idx_to_vndb, n_items) do
    eligible_set =
      from(v in VisualNovel,
        where: not is_nil(v.vndb_id) and v.vndb_vote_count >= @min_display_votes,
        select: v.vndb_id
      )
      |> Repo.all()
      |> MapSet.new()

    indices =
      idx_to_vndb
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.flat_map(fn {vndb_id, idx} ->
        if MapSet.member?(eligible_set, vndb_id), do: [idx], else: []
      end)

    IO.puts(
      "[Nx] recommendable mask: #{length(indices)}/#{n_items} VNs eligible " <>
        "(vndb_vote_count >= #{@min_display_votes})"
    )

    case indices do
      [] ->
        Nx.broadcast(Nx.u8(0), {n_items})

      _ ->
        base = Nx.broadcast(Nx.u8(0), {n_items})

        Nx.indexed_put(
          base,
          Nx.tensor(Enum.map(indices, fn i -> [i] end)),
          Nx.broadcast(Nx.u8(1), {length(indices)})
        )
    end
  end
end
