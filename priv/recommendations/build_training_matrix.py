#!/usr/bin/env python3
"""Build the EASE training matrix from merged VNDB votes + labels.

Reads `ulist_vns` from the `vndb_latest` PostgreSQL database and produces a
sparse user × VN matrix where each cell is a 1-10 training value derived from
either an explicit vote or an implicit label (Finished / Wishlist / Dropped /
etc.). Filter thresholds drop low-signal users and VNs before write.

Writes:
    <out>.npz            — scipy CSR sparse matrix
    <out_stem>_meta.json — index maps, vote counts, source mix, build params

Priority when a row has multiple applicable signals:
    vote > Blacklist > Dropped > Finished > Wishlist > Playing > Stalled

Negative signals are included deliberately — the plan treats them as training
input (they pull item j toward other items the user disliked, away from items
they liked). Masking at serving time is a separate concern.

Usage:
    python3 priv/recommendations/build_training_matrix.py \\
        --min-user-signals 5 --min-vn-signals 15 \\
        --out priv/data/ease_training.npz
"""

import argparse
import json
import os
import sys
import time
from collections import Counter

import numpy as np
import psycopg2
from scipy import sparse


# Per-label training value on the 1-10 scale. Chosen so labels express
# confidence + direction without borrowing vote magnitude, and so that the
# merged matrix keeps the same mean-centering semantics as the vote-only one.
LABEL_VALUE = {
    6: 1.5,   # Blacklist  — explicit strong negative
    4: 2.5,   # Dropped    — explicit negative
    3: 4.5,   # Stalled    — ambiguous weak negative
    1: 6.5,   # Playing    — engaged, provisional positive
    2: 7.0,   # Finished   — consumed without rating
    5: 7.5,   # Wishlist   — strong positive intent
    # 7 = Voted: redundant with `vote IS NOT NULL`, skipped.
}

# Applied in order when no vote is set — first match wins.
LABEL_PRIORITY = [6, 4, 2, 5, 1, 3]


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def load_merged_signals(db_name, include_labels):
    log(f"Connecting to '{db_name}'...")
    conn = psycopg2.connect(dbname=db_name)
    cur = conn.cursor()

    if include_labels:
        sql = """
            SELECT uid, vid, vote, labels
            FROM ulist_vns
            WHERE vote IS NOT NULL
               OR labels && ARRAY[1,2,3,4,5,6]::smallint[]
        """
    else:
        sql = """
            SELECT uid, vid, vote, NULL::smallint[]
            FROM ulist_vns
            WHERE vote IS NOT NULL
        """
    log("Querying ulist_vns...")
    cur.execute(sql)

    rows = []
    source_counts = Counter()
    for uid, vid, vote, labels in cur:
        if vote is not None:
            rows.append((uid, vid, float(vote) / 10.0))
            source_counts["vote"] += 1
            continue
        if not labels:
            continue
        label_set = set(labels)
        for label_id in LABEL_PRIORITY:
            if label_id in label_set:
                rows.append((uid, vid, LABEL_VALUE[label_id]))
                source_counts[f"label_{label_id}"] += 1
                break

    cur.close()
    conn.close()
    log(f"  Loaded {len(rows):,} merged signals")
    for k in sorted(source_counts):
        log(f"    {k}: {source_counts[k]:,}")
    return rows, source_counts


def build_matrix(rows, min_user_signals, min_vn_signals):
    log("Counting signals per user and per VN...")
    user_counts = Counter()
    vn_counts = Counter()
    for uid, vid, _ in rows:
        user_counts[uid] += 1
        vn_counts[vid] += 1

    qualifying_users = sorted(u for u, c in user_counts.items() if c >= min_user_signals)
    qualifying_vns = sorted(v for v, c in vn_counts.items() if c >= min_vn_signals)
    log(f"  {len(user_counts):,} users → {len(qualifying_users):,} qualify (≥{min_user_signals})")
    log(f"  {len(vn_counts):,} VNs → {len(qualifying_vns):,} qualify (≥{min_vn_signals})")

    user_to_idx = {u: i for i, u in enumerate(qualifying_users)}
    vn_to_idx = {v: i for i, v in enumerate(qualifying_vns)}

    log("Building sparse matrix...")
    row_idx, col_idx, data = [], [], []
    skipped = 0
    for uid, vid, value in rows:
        ui = user_to_idx.get(uid)
        vi = vn_to_idx.get(vid)
        if ui is None or vi is None:
            skipped += 1
            continue
        row_idx.append(ui)
        col_idx.append(vi)
        data.append(value)

    shape = (len(qualifying_users), len(qualifying_vns))
    X = sparse.csr_matrix((data, (row_idx, col_idx)), shape=shape, dtype=np.float32)
    # (uid, vid) is the PK in vndb_latest so duplicates shouldn't exist,
    # but sum_duplicates is cheap insurance and canonicalizes the CSR layout.
    X.sum_duplicates()

    if shape[0] and shape[1]:
        density = X.nnz / (shape[0] * shape[1]) * 100
    else:
        density = 0.0
    log(f"  Matrix: {shape[0]:,} × {shape[1]:,}, nnz={X.nnz:,} ({density:.4f}% density)")
    log(f"  Skipped {skipped:,} signals below thresholds")

    return X, qualifying_users, qualifying_vns, dict(vn_counts)


def save_output(X, users, vns, vn_counts, source_counts, args):
    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    log(f"Writing matrix to {args.out}...")
    sparse.save_npz(args.out, X)

    meta_path = args.out[:-4] + "_meta.json" if args.out.endswith(".npz") else args.out + "_meta.json"
    meta = {
        "idx_to_uid": users,
        "idx_to_vndb": vns,
        "vn_counts": {vid: vn_counts[vid] for vid in vns},
        "source_counts": dict(source_counts),
        "shape": list(X.shape),
        "nnz": int(X.nnz),
        "min_user_signals": args.min_user_signals,
        "min_vn_signals": args.min_vn_signals,
        "include_labels": not args.vote_only,
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "label_value_map": LABEL_VALUE,
        "label_priority": LABEL_PRIORITY,
    }
    log(f"Writing metadata to {meta_path}...")
    with open(meta_path, "w") as f:
        json.dump(meta, f)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", default="vndb_latest",
                    help="PostgreSQL database name (default: vndb_latest)")
    ap.add_argument("--min-user-signals", type=int, default=5,
                    help="Drop users with fewer qualifying rows (default: 5)")
    ap.add_argument("--min-vn-signals", type=int, default=15,
                    help="Drop VNs with fewer qualifying rows (default: 15)")
    ap.add_argument("--vote-only", action="store_true",
                    help="Train on explicit votes only (disables label merge)")
    ap.add_argument("--out", default="priv/data/ease_training.npz",
                    help="Output .npz path (default: priv/data/ease_training.npz)")
    args = ap.parse_args()

    log("Build training matrix")
    log(f"  db={args.db}, min_user_signals={args.min_user_signals}, "
        f"min_vn_signals={args.min_vn_signals}, vote_only={args.vote_only}")

    rows, source_counts = load_merged_signals(args.db, include_labels=not args.vote_only)
    if not rows:
        log("No qualifying rows. Is the database populated?")
        sys.exit(1)

    X, users, vns, vn_counts = build_matrix(rows, args.min_user_signals, args.min_vn_signals)
    if X.nnz == 0:
        log("Empty matrix after filtering. Adjust thresholds.")
        sys.exit(1)

    save_output(X, users, vns, vn_counts, source_counts, args)
    log("Done.")


if __name__ == "__main__":
    main()
