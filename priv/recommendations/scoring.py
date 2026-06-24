"""Shared scoring primitives used by user_recommendations.py and eval_harness.py.

Having them in one place guarantees that the scoring seen at eval time matches
the scoring seen at serving time — otherwise the ship gate means nothing.

Training functions live in `trainers.py`. This module is strictly serving-side
math: mean-centering, Stage 1 retrieval, Stage 2 rerank, helpers.
"""

import numpy as np


# Production weights — kept in sync with @default_weights in
# lib/kaguya/recommendations/nx/engine.ex. content=0.00 since the
# 2026-04-15 audit (see docs/experiments/stage2-content-ablation.md).
DEFAULT_WEIGHTS = {
    "ease":       1.00,
    "content":    0.00,
    "series":     0.25,
    "freshness":  0.10,
    "pop_damp":   0.05,
    "diversity":  0.30,
}


def mean_center_users(X_csr):
    """Subtract each user's own mean from nonzero entries (returns a float64 CSR)."""
    X = X_csr.copy().astype(np.float64)
    for i in range(X.shape[0]):
        a, b = X.indptr[i], X.indptr[i + 1]
        if b > a:
            X.data[a:b] -= X.data[a:b].mean()
    return X


def build_feature_arrays(idx_to_vndb, features, current_year):
    """Precompute per-index numpy arrays and sets for fast rerank."""
    n = len(idx_to_vndb)
    vote_counts = np.array(
        [features.get(idx_to_vndb[i], {}).get("vote_count", 1) or 1 for i in range(n)],
        dtype=np.float32,
    )
    vote_counts[vote_counts < 1] = 1.0
    log_counts = np.log1p(vote_counts)
    pop_damp = log_counts / log_counts.max()

    years = np.array(
        [features.get(idx_to_vndb[i], {}).get("release_year") or 2000 for i in range(n)],
        dtype=np.float32,
    )
    freshness = 1.0 / (1.0 + np.maximum(current_year - years, 0) / 5.0)

    writers = [set(features.get(idx_to_vndb[i], {}).get("writers", [])) for i in range(n)]
    producers = [set(features.get(idx_to_vndb[i], {}).get("producers", [])) for i in range(n)]
    series = [set(features.get(idx_to_vndb[i], {}).get("series", [])) for i in range(n)]
    # Include VN's own id in its series set so liking X boosts other members of X's series.
    for i, vid in enumerate(idx_to_vndb):
        series[i].add(vid)

    return dict(pop_damp=pop_damp, freshness=freshness,
                writers=writers, producers=producers, series=series)


def stage1_ease_scores(B, pref_idx, pref_val_centered):
    """Sparse retrieval — O(k·n), not O(n²).

    Mirrors the Nx production engine (`Kaguya.Recommendations.Nx.Engine.
    stage1_ease_scores/3`) including Case-4 zeroing: when (pref < 0) AND
    (B < 0), the raw contribution (pref · B) is a spurious positive —
    "you disliked X, candidate is anti-similar to X, so boost." That
    quadrant is zeroed. Other three cases (liked×similar boost, liked×
    anti penalty, disliked×similar penalty) stay intact.

    Returns a dense (n_items,) score array. Caller masks and takes top-K.
    """
    b_slice = B[pref_idx, :]                     # (n_prefs, n_items)
    pref_col = pref_val_centered[:, None]        # (n_prefs, 1)
    contribs = pref_col * b_slice
    spurious = (pref_col < 0) & (b_slice < 0)
    contribs = np.where(spurious, 0.0, contribs)
    return contribs.sum(axis=0).astype(np.float32)


def stage2_rerank(
    B, top_cand, ease_scores_at_cand,
    liked_writers, liked_producers, liked_series,
    feat_arrays, weights, n_final,
    idx_to_vndb,
):
    """Multi-objective MMR rerank over the retrieval candidates.

    Returns (selected_positions_in_top_cand, final_mmr_scores).
    Both arrays have length min(n_final, len(top_cand)).
    """
    n_cand = len(top_cand)

    ese = ease_scores_at_cand
    ease_norm = (ese - ese.min()) / (ese.max() - ese.min() + 1e-9)

    writers_by_idx = feat_arrays["writers"]
    producers_by_idx = feat_arrays["producers"]
    series_by_idx = feat_arrays["series"]
    pop_damp = feat_arrays["pop_damp"]
    freshness = feat_arrays["freshness"]

    content_score = np.zeros(n_cand, dtype=np.float32)
    series_score = np.zeros(n_cand, dtype=np.float32)
    for ci, i in enumerate(top_cand):
        w_o = len(writers_by_idx[i] & liked_writers) if liked_writers else 0
        p_o = len(producers_by_idx[i] & liked_producers) if liked_producers else 0
        s_o = len(series_by_idx[i] & liked_series) if liked_series else 0
        content_score[ci] = 0.6 * min(w_o, 3) / 3.0 + 0.4 * min(p_o, 3) / 3.0
        series_score[ci] = min(s_o, 3) / 3.0

    fresh = freshness[top_cand]
    pop = pop_damp[top_cand]

    base = (
        weights["ease"] * ease_norm
        + weights["content"] * content_score
        + weights["series"] * series_score
        + weights["freshness"] * fresh
        - weights["pop_damp"] * pop
    )

    n_pick = min(n_final, n_cand)
    selected = np.empty(n_pick, dtype=np.int64)
    selected_mask = np.zeros(n_cand, dtype=bool)
    diversity_penalty = np.zeros(n_cand, dtype=np.float32)
    final_scores = np.empty(n_pick, dtype=np.float32)

    for step in range(n_pick):
        adj = base - weights["diversity"] * diversity_penalty
        adj[selected_mask] = -np.inf
        pick = int(np.argmax(adj))
        selected[step] = pick
        final_scores[step] = adj[pick]
        selected_mask[pick] = True
        picked_row = B[top_cand[pick], top_cand]
        diversity_penalty = np.maximum(diversity_penalty, np.clip(picked_row, 0.0, None))

    return selected, final_scores


def derive_liked_sets(liked_vids, features):
    """From a list of vndb_ids the user rated highly, build liked-writer/producer/series sets."""
    liked_writers, liked_producers, liked_series = set(), set(), set()
    for vid in liked_vids:
        f = features.get(vid)
        if not f:
            continue
        liked_writers.update(f.get("writers", []))
        liked_producers.update(f.get("producers", []))
        liked_series.update(f.get("series", []))
        liked_series.add(vid)
    return liked_writers, liked_producers, liked_series


def build_mask_array(n_items, pref_idx, mask_vndb_ids, vndb_to_idx):
    """Return a boolean mask of shape (n_items,) with True on items to exclude."""
    mask_set = set(int(i) for i in pref_idx.tolist())
    for vid in mask_vndb_ids:
        idx = vndb_to_idx.get(vid)
        if idx is not None:
            mask_set.add(idx)
    mask_arr = np.zeros(n_items, dtype=bool)
    if mask_set:
        mask_arr[list(mask_set)] = True
    return mask_arr
