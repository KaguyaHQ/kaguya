#!/usr/bin/env python3
"""
EASE (Embarrassingly Shallow Autoencoders) VN similarity computation.

Reads votes from vndb_latest PostgreSQL database, computes item-item
similarity via EASE, outputs JSON mapping vndb_id → top similar VNs.

Usage:
    python3 priv/repo/scripts/similarities/ease_similarity.py [--lambda 500] [--top-n 20] [--min-votes 15] [--min-user-votes 5]

Reference: "Embarrassingly Shallow Autoencoders for Sparse Data" (Steck, 2019)
"""

import argparse
import json
import sys
import time

import numpy as np
import psycopg2
from scipy import sparse


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def load_votes(db_name, min_vn_votes, min_user_votes):
    """Load filtered votes from vndb_latest into sparse matrix."""
    log(f"Connecting to database '{db_name}'...")
    conn = psycopg2.connect(dbname=db_name)
    cur = conn.cursor()

    # Get qualifying VNs (min votes threshold)
    log(f"Finding VNs with >= {min_vn_votes} votes...")
    cur.execute("""
        SELECT vid, count(*) as cnt
        FROM ulist_vns
        WHERE vote IS NOT NULL
        GROUP BY vid
        HAVING count(*) >= %s
    """, (min_vn_votes,))
    vn_rows = cur.fetchall()
    qualifying_vns = {row[0]: idx for idx, row in enumerate(vn_rows)}
    vn_vote_counts = {row[0]: row[1] for row in vn_rows}
    log(f"  {len(qualifying_vns)} VNs qualify")

    # Get qualifying users (min votes threshold)
    log(f"Finding users with >= {min_user_votes} votes...")
    cur.execute("""
        SELECT uid, count(*) as cnt
        FROM ulist_vns
        WHERE vote IS NOT NULL
        GROUP BY uid
        HAVING count(*) >= %s
    """, (min_user_votes,))
    qualifying_users = {row[0]: idx for idx, row in enumerate(cur.fetchall())}
    log(f"  {len(qualifying_users)} users qualify")

    # Load all qualifying votes
    log("Loading votes...")
    cur.execute("""
        SELECT uid, vid, vote
        FROM ulist_vns
        WHERE vote IS NOT NULL
    """)

    rows, cols, vals = [], [], []
    skipped = 0
    for uid, vid, vote in cur:
        if uid in qualifying_users and vid in qualifying_vns:
            rows.append(qualifying_users[uid])
            cols.append(qualifying_vns[vid])
            vals.append(vote / 10.0)  # Convert 10-100 → 1.0-10.0
        else:
            skipped += 1

    cur.close()
    conn.close()

    n_users = len(qualifying_users)
    n_items = len(qualifying_vns)
    log(f"  {len(vals)} votes loaded, {skipped} skipped")
    log(f"  Matrix shape: {n_users} users × {n_items} items")

    X = sparse.csr_matrix((vals, (rows, cols)), shape=(n_users, n_items))

    # Build reverse mapping: column index → vndb_id
    idx_to_vndb = {idx: vid for vid, idx in qualifying_vns.items()}

    return X, idx_to_vndb, vn_vote_counts


def mean_center_users(X):
    """Subtract each user's mean rating (only over their rated items)."""
    log("Mean-centering per user...")
    X = X.copy().astype(np.float64)

    # For each row, subtract the mean of nonzero entries
    for i in range(X.shape[0]):
        row = X.getrow(i)
        if row.nnz > 0:
            mean = row.data.mean()
            X.data[X.indptr[i]:X.indptr[i + 1]] -= mean

    return X


def compute_ease(X, reg_lambda):
    """
    EASE: closed-form item-item similarity.

    G = X.T @ X + λI
    P = G^{-1}
    B = P / (-diag(P))
    diag(B) = 0
    """
    n_items = X.shape[1]
    log(f"Computing gram matrix ({n_items}×{n_items})...")
    G = (X.T @ X).toarray()

    log(f"Adding regularization (λ={reg_lambda})...")
    G += reg_lambda * np.eye(n_items)

    log("Inverting matrix...")
    t0 = time.time()
    P = np.linalg.inv(G)
    log(f"  Inversion took {time.time() - t0:.1f}s")

    log("Normalizing to similarity matrix...")
    diag = np.diag(P)
    B = P / (-diag[:, None])
    np.fill_diagonal(B, 0)

    return B


def discount_popularity(B, X, alpha):
    """
    Divide each column j of B by vote_count[j]^alpha.

    This penalizes items that appear similar to everything
    simply because they have massive vote counts. Genuine
    taste-driven similarity survives because the raw score
    is high relative to the item's popularity.
    """
    if alpha == 0:
        return B

    log(f"Applying popularity discount (α={alpha})...")

    # Number of nonzero ratings per item (column)
    counts = np.array(X.getnnz(axis=0), dtype=np.float64)

    # Avoid division by zero for any edge case
    counts = np.maximum(counts, 1.0)

    # Scale each column: B[:, j] /= counts[j]^alpha
    scale = 1.0 / np.power(counts, alpha)
    B = B * scale[np.newaxis, :]

    # Re-zero diagonal
    np.fill_diagonal(B, 0)

    return B


def extract_similar(B, idx_to_vndb, min_score, max_per_vn, vn_vote_counts, min_display_votes):
    """Extract similar VNs per item above score threshold, capped at max_per_vn."""
    log(f"Extracting similar VNs (min_score={min_score}, max={max_per_vn}, min_display_votes={min_display_votes})...")
    n_items = B.shape[0]
    results = {}
    count_dist = []

    for i in range(n_items):
        vndb_id = idx_to_vndb[i]

        # Source VN must also meet display threshold
        if vn_vote_counts.get(vndb_id, 0) < min_display_votes:
            continue

        row = B[i]

        # Find all indices above threshold
        above = np.where(row >= min_score)[0]
        # Sort by score descending
        above = above[np.argsort(-row[above])]

        similar = []
        for j in above:
            target_id = idx_to_vndb[j]
            if vn_vote_counts.get(target_id, 0) < min_display_votes:
                continue
            similar.append({
                "vndb_id": target_id,
                "score": round(float(row[j]), 6)
            })
            if len(similar) >= max_per_vn:
                break

        if similar:
            results[vndb_id] = similar
            count_dist.append(len(similar))

    if count_dist:
        arr = np.array(count_dist)
        log(f"  Similar VNs per item: min={arr.min()}, median={int(np.median(arr))}, "
            f"mean={arr.mean():.1f}, max={arr.max()}")

    return results


def print_samples(results, sample_ids=None):
    """Print sample results for sanity checking."""
    if sample_ids is None:
        # Well-known VNs for eyeball testing
        sample_ids = [
            "v2016",   # Muv-Luv Alternative
            "v2002",   # STEINS;GATE
            "v24",     # Fate/Stay Night
            "v51",     # Muramasa (Soukou Akki Muramasa)
            "v3144",   # Umineko When They Cry
            "v4",      # CLANNAD
        ]

    log("\n=== SAMPLE RESULTS ===")
    for vid in sample_ids:
        if vid in results:
            log(f"\n  {vid}:")
            for entry in results[vid][:10]:
                log(f"    {entry['vndb_id']:>8s}  score={entry['score']:.4f}")
        else:
            log(f"\n  {vid}: not in filtered set")


def main():
    parser = argparse.ArgumentParser(description="EASE VN similarity")
    parser.add_argument("--db", default="vndb_latest", help="PostgreSQL database name")
    parser.add_argument("--lambda", dest="reg_lambda", type=float, default=500,
                        help="Regularization parameter (default: 500)")
    parser.add_argument("--min-score", type=float, default=0.01,
                        help="Minimum similarity score to include (default: 0.01)")
    parser.add_argument("--max-per-vn", type=int, default=50,
                        help="Max similar VNs per item (default: 50)")
    parser.add_argument("--min-votes", type=int, default=15,
                        help="Min votes per VN (default: 15)")
    parser.add_argument("--min-user-votes", type=int, default=5,
                        help="Min votes per user (default: 5)")
    parser.add_argument("--output", default="priv/data/ease_similarities.json",
                        help="Output JSON file path")
    parser.add_argument("--pop-alpha", type=float, default=0.35,
                        help="Popularity discount exponent (0=off, default: 0.35)")
    parser.add_argument("--min-display-votes", type=int, default=50,
                        help="Min votes for a VN to appear in output (default: 50)")
    parser.add_argument("--no-mean-center", action="store_true",
                        help="Skip mean-centering (not recommended)")
    args = parser.parse_args()

    log("EASE VN Similarity Computation")
    log(f"  λ={args.reg_lambda}, min_score={args.min_score}, max_per_vn={args.max_per_vn}, min_votes={args.min_votes}, min_user_votes={args.min_user_votes}, min_display_votes={args.min_display_votes}")

    # Load data
    X, idx_to_vndb, vn_vote_counts = load_votes(args.db, args.min_votes, args.min_user_votes)

    # Mean-center
    if not args.no_mean_center:
        X = mean_center_users(X)

    # Compute EASE
    B = compute_ease(X, args.reg_lambda)

    # Suppress popularity-driven false similarities
    B = discount_popularity(B, X, args.pop_alpha)

    # Extract results
    results = extract_similar(B, idx_to_vndb, args.min_score, args.max_per_vn, vn_vote_counts, args.min_display_votes)
    log(f"Computed similarities for {len(results)} VNs")

    # Sanity check
    print_samples(results)

    # Save
    import os
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(results, f)
    log(f"Saved to {args.output}")

    # Summary stats
    total_pairs = sum(len(v) for v in results.values())
    log(f"Total similarity pairs: {total_pairs}")
    log("Done!")


if __name__ == "__main__":
    main()
