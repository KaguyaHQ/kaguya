#!/usr/bin/env python3
"""Extract per-VN content features from vndb_latest for Stage 2 reranking.

For each VN in the EASE B matrix, we emit:
  - release_year: earliest released year (VNDB stores YYYYMMDD as int)
  - writers: list of staff aids with role='scenario' (aid is stable across aliases)
  - producers: list of developer producer ids (not publishers — we want studio)
  - series: list of vndb_ids linked via seq/preq/ser/par/side relations
  - vote_count: from the training metadata

Writes a single JSON mapping vndb_id → features to keep user_recommendations.py I/O simple.
Features are only emitted for VNs in the B matrix; serving time never sees others.

Usage:
    python3 priv/recommendations/build_vn_features.py \\
        --b-meta priv/data/ease_B_meta.json \\
        --out priv/data/vn_features.json
"""

import argparse
import json
import os
import time
from collections import defaultdict

import psycopg2


SERIES_RELATIONS = {"seq", "preq", "ser", "par", "side"}


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", default="vndb_latest")
    ap.add_argument("--b-meta", default="priv/data/ease_B_meta.json")
    ap.add_argument("--out", default="priv/data/vn_features.json")
    args = ap.parse_args()

    log(f"Loading B metadata {args.b_meta}...")
    with open(args.b_meta) as f:
        meta = json.load(f)
    target_vids = set(meta["idx_to_vndb"])
    vn_counts = meta["vn_counts"]
    log(f"  {len(target_vids)} VNs in B matrix")

    conn = psycopg2.connect(dbname=args.db)
    cur = conn.cursor()

    # In-memory accumulators keyed by vndb_id.
    features = {vid: {
        "release_year": None,
        "writers": [],
        "producers": [],
        "series": [],
        "vote_count": vn_counts.get(vid, 0),
    } for vid in target_vids}

    # --- release year (earliest non-zero released across any release) ---
    log("Querying release years...")
    cur.execute("""
        SELECT rv.vid, min(r.released) AS earliest
        FROM releases_vn rv
        JOIN releases r ON rv.id = r.id
        WHERE r.released > 0
        GROUP BY rv.vid
    """)
    hits = 0
    for vid, earliest in cur:
        if vid in features:
            # earliest is YYYYMMDD int; rough year = earliest // 10000
            features[vid]["release_year"] = int(earliest // 10000)
            hits += 1
    log(f"  release_year set on {hits:,} VNs")

    # --- writers (scenario role, by stable staff aid) ---
    log("Querying scenario writers...")
    cur.execute("""
        SELECT vs.id, vs.aid
        FROM vn_staff vs
        WHERE vs.role = 'scenario'
    """)
    hits = 0
    for vid, aid in cur:
        if vid in features:
            features[vid]["writers"].append(int(aid))
            hits += 1
    log(f"  writers recorded: {hits:,} entries")

    # --- producers (developer only, not publisher) ---
    log("Querying developer producers...")
    cur.execute("""
        SELECT DISTINCT rv.vid, rp.pid
        FROM releases_vn rv
        JOIN releases_producers rp ON rp.id = rv.id
        WHERE rp.developer = true
    """)
    hits = 0
    for vid, pid in cur:
        if vid in features:
            features[vid]["producers"].append(pid)
            hits += 1
    log(f"  producer entries: {hits:,}")

    # --- series (by qualifying vn_relation types) ---
    log("Querying series relations...")
    cur.execute("""
        SELECT id, vid, relation
        FROM vn_relations
    """)
    hits = 0
    for vid_a, vid_b, rel in cur:
        if rel not in SERIES_RELATIONS:
            continue
        # Keep related VN ids — even if related VN isn't in B matrix we may
        # still want it for matching (user could have rated it elsewhere).
        if vid_a in features:
            features[vid_a]["series"].append(vid_b)
            hits += 1
    log(f"  series edges: {hits:,}")

    cur.close()
    conn.close()

    # Deduplicate small lists in-place
    for vid, f in features.items():
        f["writers"] = sorted(set(f["writers"]))
        f["producers"] = sorted(set(f["producers"]))
        f["series"] = sorted(set(f["series"]))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    log(f"Writing {len(features):,} VN feature records to {args.out}...")
    with open(args.out, "w") as f:
        json.dump(features, f)

    size_mb = os.path.getsize(args.out) / 1e6
    log(f"  {size_mb:.1f} MB on disk")
    log("Done.")


if __name__ == "__main__":
    main()
