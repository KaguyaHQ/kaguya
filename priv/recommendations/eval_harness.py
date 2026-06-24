#!/usr/bin/env python3
"""Offline evaluation of EASE and EASE+rerank recommendation quality.

Holds out 10% of each user's positive signals (cells ≥ 7.0), retrains EASE on
the 90%, and measures Recall@K / NDCG@K / Hit@K / Coverage for:

  - random baseline
  - popularity baseline
  - EASE-only (Stage 1)
  - EASE + multi-objective rerank (Stage 1 + Stage 2)

Shared scoring lives in scoring.py — guarantees eval sees the same code as
production user_recommendations.py.
"""

import argparse
import json
import os
import sys
import time

import numpy as np
from scipy import sparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scoring import (
    DEFAULT_WEIGHTS,
    build_feature_arrays,
    derive_liked_sets,
    mean_center_users,
    stage1_ease_scores,
    stage2_rerank,
)
from trainers import TRAINERS


POSITIVE_THRESHOLD = 7.0


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def split_train_holdout(X, holdout_fraction, min_positives, seed):
    rng = np.random.RandomState(seed)
    X = X.copy()
    heldout = {}
    n_held_total = 0
    for u in range(X.shape[0]):
        a, b = X.indptr[u], X.indptr[u + 1]
        if b <= a:
            continue
        row_data = X.data[a:b]
        row_indices = X.indices[a:b]
        pos_mask = row_data >= POSITIVE_THRESHOLD
        n_pos = int(pos_mask.sum())
        if n_pos < min_positives:
            continue
        n_hold = max(1, int(n_pos * holdout_fraction))
        pos_positions = np.where(pos_mask)[0]
        chosen = rng.choice(pos_positions, size=n_hold, replace=False)
        held_items = row_indices[chosen].tolist()
        X.data[a + chosen] = 0
        heldout[u] = held_items
        n_held_total += n_hold
    X.eliminate_zeros()
    log(f"  Held out {n_held_total:,} positives across {len(heldout):,} users")
    return X, heldout


def _score_metrics(predictions, held_set, k):
    hits = np.fromiter((1 if j in held_set else 0 for j in predictions), dtype=np.int8, count=len(predictions))
    recall = hits.sum() / max(len(held_set), 1)
    dcg = float(np.sum(hits / np.log2(np.arange(2, len(hits) + 2))))
    ideal = min(len(held_set), k)
    idcg = float(np.sum(1.0 / np.log2(np.arange(2, ideal + 2)))) if ideal > 0 else 0.0
    ndcg = dcg / idcg if idcg > 0 else 0.0
    return recall, ndcg, bool(hits.sum() > 0)


def _agg(recalls, ndcgs, hits, all_predicted, n_items):
    return {
        "recall_at_k": float(np.mean(recalls)) if recalls else 0.0,
        "ndcg_at_k": float(np.mean(ndcgs)) if ndcgs else 0.0,
        "hit_rate_at_k": float(np.mean(hits)) if hits else 0.0,
        "coverage": len(all_predicted) / n_items,
        "n_users_evaluated": len(recalls),
    }


def evaluate_popularity(X_train, heldout, vn_popularity, k):
    n_items = len(vn_popularity)
    pop_order = np.argsort(-vn_popularity)
    recalls, ndcgs, hits_at_k = [], [], []
    all_predicted = set()
    for u, held_items in heldout.items():
        seen = set(X_train.getrow(u).indices.tolist())
        top_k = []
        for j in pop_order:
            if j not in seen:
                top_k.append(int(j))
                if len(top_k) >= k:
                    break
        all_predicted.update(top_k)
        recall, ndcg, hit = _score_metrics(top_k, set(held_items), k)
        recalls.append(recall); ndcgs.append(ndcg); hits_at_k.append(hit)
    return _agg(recalls, ndcgs, hits_at_k, all_predicted, n_items)


def evaluate_random(X_train, heldout, n_items, k, seed):
    rng = np.random.RandomState(seed)
    recalls, ndcgs, hits_at_k = [], [], []
    all_predicted = set()
    for u, held_items in heldout.items():
        seen = X_train.getrow(u).indices
        unseen = np.setdiff1d(np.arange(n_items), seen, assume_unique=True)
        pick = rng.choice(unseen, size=min(k, len(unseen)), replace=False).tolist()
        all_predicted.update(pick)
        recall, ndcg, hit = _score_metrics(pick, set(held_items), k)
        recalls.append(recall); ndcgs.append(ndcg); hits_at_k.append(hit)
    return _agg(recalls, ndcgs, hits_at_k, all_predicted, n_items)


def evaluate_ease_only(B, X_train, heldout, k):
    """Stage 1 only — top-K by EASE score."""
    n_items = B.shape[0]
    recalls, ndcgs, hits_at_k = [], [], []
    all_predicted = set()
    for u, held_items in heldout.items():
        row = X_train.getrow(u)
        if row.nnz < 3:
            continue
        pref_idx = row.indices
        pref_val = row.data.astype(np.float32)
        pref_val_centered = pref_val - pref_val.mean()
        scores = stage1_ease_scores(B, pref_idx, pref_val_centered)
        scores[pref_idx] = -np.inf
        top = np.argpartition(-scores, k)[:k]
        top = top[np.argsort(-scores[top])].tolist()
        all_predicted.update(top)
        recall, ndcg, hit = _score_metrics(top, set(held_items), k)
        recalls.append(recall); ndcgs.append(ndcg); hits_at_k.append(hit)
    return _agg(recalls, ndcgs, hits_at_k, all_predicted, n_items)


def evaluate_ease_rerank(B, X_train, heldout, features, idx_to_vndb, vndb_to_idx,
                         feat_arrays, weights, n_candidates, k):
    """Stage 1 retrieve → Stage 2 rerank → top-K."""
    n_items = B.shape[0]
    recalls, ndcgs, hits_at_k = [], [], []
    all_predicted = set()
    for u, held_items in heldout.items():
        row = X_train.getrow(u)
        if row.nnz < 3:
            continue
        pref_idx = row.indices
        pref_val = row.data.astype(np.float32)
        pref_val_centered = pref_val - pref_val.mean()

        scores = stage1_ease_scores(B, pref_idx, pref_val_centered)
        scores[pref_idx] = -np.inf
        finite = int(np.isfinite(scores).sum())
        if finite == 0:
            continue
        n_cand = min(n_candidates, finite)
        top_cand = np.argpartition(-scores, n_cand - 1)[:n_cand]
        top_cand = top_cand[np.argsort(-scores[top_cand])]

        # likes = user's post-holdout signals ≥ 8.0 (from 1-10 scale)
        high_mask = pref_val >= 8.0
        liked_vids = [idx_to_vndb[int(pref_idx[i])] for i in np.where(high_mask)[0]]
        liked_writers, liked_producers, liked_series = derive_liked_sets(liked_vids, features)

        selected, _ = stage2_rerank(
            B, top_cand, scores[top_cand],
            liked_writers, liked_producers, liked_series,
            feat_arrays, weights, k, idx_to_vndb,
        )
        top_k = [int(top_cand[s]) for s in selected]
        all_predicted.update(top_k)
        recall, ndcg, hit = _score_metrics(top_k, set(held_items), k)
        recalls.append(recall); ndcgs.append(ndcg); hits_at_k.append(hit)
    return _agg(recalls, ndcgs, hits_at_k, all_predicted, n_items)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--training", default="priv/data/ease_training.npz")
    ap.add_argument("--meta", default="priv/data/ease_training_meta.json")
    ap.add_argument("--features", default="priv/data/vn_features.json")
    ap.add_argument("--lambda-reg", dest="reg_lambda", type=float, default=500.0)
    ap.add_argument("--holdout-fraction", type=float, default=0.1)
    ap.add_argument("--min-positives", type=int, default=5)
    ap.add_argument("--k", type=int, default=20)
    ap.add_argument("--n-candidates", type=int, default=500)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dtype", default="float32", choices=["float32", "float64"])
    ap.add_argument("--out", default="priv/data/ease_eval_results.json")
    ap.add_argument("--current-year", type=int, default=time.localtime().tm_year)
    ap.add_argument("--methods", default=None,
                    help="Comma-separated method names to evaluate (default: all)")
    ap.add_argument("--skip-rerank", action="store_true",
                    help="Reserved (Stage-2 rerank is not run in multi-method eval)")
    for k_, v in DEFAULT_WEIGHTS.items():
        ap.add_argument(f"--w-{k_.replace('_', '-')}", dest=f"w_{k_}", type=float, default=v)
    args = ap.parse_args()

    weights = {k_: getattr(args, f"w_{k_}") for k_ in DEFAULT_WEIGHTS}
    dtype = np.float32 if args.dtype == "float32" else np.float64

    log("Loading training data...")
    X = sparse.load_npz(args.training)
    with open(args.meta) as f:
        meta = json.load(f)
    idx_to_vndb = meta["idx_to_vndb"]
    vndb_to_idx = {v: i for i, v in enumerate(idx_to_vndb)}
    log(f"  X {X.shape}, nnz={X.nnz:,}")

    vn_popularity = np.zeros(X.shape[1], dtype=np.int64)
    for idx, vid in enumerate(idx_to_vndb):
        vn_popularity[idx] = meta["vn_counts"].get(vid, 0)

    log(f"Splitting (frac={args.holdout_fraction:.0%}, seed={args.seed})...")
    X_train, heldout = split_train_holdout(X, args.holdout_fraction, args.min_positives, args.seed)
    log(f"  X_train nnz={X_train.nnz:,}")

    results = {"k": args.k, "n_holdout_users": len(heldout), "weights": weights, "lambda": args.reg_lambda}

    log("Baseline: random")
    t0 = time.time()
    results["random"] = evaluate_random(X_train, heldout, X_train.shape[1], args.k, args.seed)
    log(f"  R@{args.k}={results['random']['recall_at_k']:.4f}  NDCG@{args.k}={results['random']['ndcg_at_k']:.4f}  ({time.time()-t0:.1f}s)")

    log("Baseline: popularity")
    t0 = time.time()
    results["popularity"] = evaluate_popularity(X_train, heldout, vn_popularity, args.k)
    log(f"  R@{args.k}={results['popularity']['recall_at_k']:.4f}  NDCG@{args.k}={results['popularity']['ndcg_at_k']:.4f}  ({time.time()-t0:.1f}s)")

    methods_to_run = args.methods.split(",") if args.methods else list(TRAINERS.keys())
    log(f"Will evaluate: {methods_to_run}")

    log("Mean-centering X_train (shared input for centered methods)...")
    X_centered = mean_center_users(X_train)

    for method in methods_to_run:
        if method not in TRAINERS:
            log(f"Skipping unknown method: {method}")
            continue
        input_kind, trainer, kwargs = TRAINERS[method]
        log(f"Training {method} (input={input_kind}, kwargs={kwargs})...")
        t0 = time.time()
        try:
            X_in = X_centered if input_kind == "centered" else X_train
            B = trainer(X_in, dtype=dtype, **kwargs)
        except Exception as e:
            log(f"  ERROR training {method}: {e!r}")
            continue
        train_t = time.time() - t0
        log(f"  Trained in {train_t:.1f}s")

        log(f"Evaluating {method} (sparse Stage-1 retrieval, k={args.k})...")
        t0 = time.time()
        results[method] = evaluate_ease_only(B, X_train, heldout, args.k)
        results[method]["train_seconds"] = round(train_t, 1)
        log(f"  R@{args.k}={results[method]['recall_at_k']:.4f}  "
            f"NDCG@{args.k}={results[method]['ndcg_at_k']:.4f}  "
            f"hit={results[method]['hit_rate_at_k']:.4f}  "
            f"coverage={results[method]['coverage']:.4f}  "
            f"({time.time()-t0:.1f}s)")
        del B  # free 0.5 GB before next method

    # Summary table
    table = [["method", "R@K", "NDCG@K", "hit@K", "coverage", "train_s"]]
    for name in ["random", "popularity"] + methods_to_run:
        if name in results:
            r = results[name]
            train_s = r.get("train_seconds", "—")
            table.append([name,
                          f"{r['recall_at_k']:.4f}", f"{r['ndcg_at_k']:.4f}",
                          f"{r['hit_rate_at_k']:.4f}", f"{r['coverage']:.4f}",
                          str(train_s)])
    log("=" * 88)
    for row in table:
        log(" | ".join(f"{c:<13}" for c in row))
    log("=" * 88)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(results, f, indent=2)
    log(f"Saved {args.out}")


if __name__ == "__main__":
    main()
