#!/usr/bin/env python3
"""Answer 6 key questions about VNDB data distribution for graph autoencoder decision.

Requires:
  - vndb_latest database with ulist_vns, vn_relations, vn_staff, releases_producers
  - priv/data/ease_B.npy and ease_B_meta.json (for Q5)

Usage:
    python3 priv/recommendations/analyze_data_distribution.py
"""

import json
import os
import sys
import time
from collections import Counter, defaultdict

import numpy as np
import psycopg2
from scipy import stats
from scipy.sparse import csr_matrix

DB_NAME = "vndb_latest"
MIN_VN_VOTES = 15
MIN_USER_VOTES = 5

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def get_filtered_vns_and_users(cur):
    """Get VNs with 15+ votes and users with 5+ votes."""
    log("Getting filtered VN and user sets...")

    # Get vote counts per VN
    cur.execute("""
        SELECT vid, COUNT(*) as cnt
        FROM ulist_vns
        WHERE vote IS NOT NULL AND vote > 0
        GROUP BY vid
        HAVING COUNT(*) >= %s
    """, (MIN_VN_VOTES,))
    vn_vote_counts = {row[0]: row[1] for row in cur.fetchall()}
    filtered_vns = set(vn_vote_counts.keys())

    # Get users with 5+ votes on filtered VNs
    cur.execute("""
        SELECT uid, COUNT(*) as cnt
        FROM ulist_vns
        WHERE vote IS NOT NULL AND vote > 0
        GROUP BY uid
        HAVING COUNT(*) >= %s
    """, (MIN_USER_VOTES,))
    filtered_users = {row[0] for row in cur.fetchall()}

    log(f"  Filtered VNs: {len(filtered_vns):,}")
    log(f"  Filtered users: {len(filtered_users):,}")

    return filtered_vns, filtered_users, vn_vote_counts


def q1_content_graph_connectivity(cur, filtered_vns):
    """Q1: What % of filtered VNs have series/writer/producer connections?"""
    log("\n=== Q1: Content Graph Connectivity ===")

    connected_vns = set()

    # Series relations (seq, preq, ser, par, side)
    cur.execute("""
        SELECT DISTINCT id, vid
        FROM vn_relations
        WHERE relation IN ('seq', 'preq', 'ser', 'par', 'side')
    """)
    series_pairs = [(r[0], r[1]) for r in cur.fetchall()]
    series_connected = set()
    for a, b in series_pairs:
        if a in filtered_vns and b in filtered_vns:
            series_connected.add(a)
            series_connected.add(b)
    connected_vns.update(series_connected)
    log(f"  VNs with series connection (both in filtered): {len(series_connected):,}")

    # Shared writers
    cur.execute("""
        SELECT id, aid FROM vn_staff WHERE role = 'scenario'
    """)
    writer_to_vns = defaultdict(set)
    for vid, aid in cur.fetchall():
        if vid in filtered_vns:
            writer_to_vns[aid].add(vid)

    writer_connected = set()
    for aid, vns in writer_to_vns.items():
        if len(vns) > 1:
            writer_connected.update(vns)
    connected_vns.update(writer_connected)
    log(f"  VNs sharing a writer with another filtered VN: {len(writer_connected):,}")

    # Shared producers (developers)
    cur.execute("""
        SELECT DISTINCT rv.vid, rp.pid
        FROM releases_vn rv
        JOIN releases_producers rp ON rp.id = rv.id
        WHERE rp.developer = true
    """)
    producer_to_vns = defaultdict(set)
    for vid, pid in cur.fetchall():
        if vid in filtered_vns:
            producer_to_vns[pid].add(vid)

    producer_connected = set()
    for pid, vns in producer_to_vns.items():
        if len(vns) > 1:
            producer_connected.update(vns)
    connected_vns.update(producer_connected)
    log(f"  VNs sharing a producer with another filtered VN: {len(producer_connected):,}")

    pct_connected = len(connected_vns) / len(filtered_vns) * 100
    pct_standalone = 100 - pct_connected

    log(f"\n  RESULT: {len(connected_vns):,} / {len(filtered_vns):,} VNs ({pct_connected:.1f}%) have at least one content connection")
    log(f"  RESULT: {pct_standalone:.1f}% are standalone (no series/writer/producer overlap)")

    return connected_vns, writer_to_vns, producer_to_vns


def q2_corater_distribution(cur, filtered_vns, filtered_users, vn_vote_counts):
    """Q2: Distribution of pairwise co-rater counts.

    Pair counts computed as XᵀX on a sparse binary user×VN matrix — BLAS
    replaces a pure-Python quadratic. Q5 only needs top-100 × top-100
    lookups, so we extract that submatrix and return it as a small dict
    instead of holding the full (n_vns × n_vns) Gramian in memory after
    the stats pass.
    """
    log("\n=== Q2: Co-rater Distribution ===")

    log("  Loading ulist_vns rows...")
    cur.execute("""
        SELECT uid, vid
        FROM ulist_vns
        WHERE vote IS NOT NULL AND vote > 0
    """)
    user_vns = defaultdict(list)
    for uid, vid in cur.fetchall():
        if uid in filtered_users and vid in filtered_vns:
            user_vns[uid].append(vid)

    log("  Building sparse user×VN matrix...")
    vns_sorted = sorted(filtered_vns)
    vn_idx = {v: i for i, v in enumerate(vns_sorted)}
    n_vns = len(vns_sorted)

    rows, cols = [], []
    for ui, (uid, vns) in enumerate(user_vns.items()):
        for v in vns:
            rows.append(ui)
            cols.append(vn_idx[v])

    data = np.ones(len(rows), dtype=np.int32)
    X = csr_matrix((data, (rows, cols)), shape=(len(user_vns), n_vns))

    log(f"  Computing XᵀX ({X.shape[0]:,} users × {n_vns:,} VNs)...")
    G = (X.T @ X).tocoo()
    upper = G.row < G.col              # exclude diagonal (= per-VN vote count)
    counts_arr = G.data[upper]

    total_pairs_with_overlap = int(counts_arr.size)
    total_possible_pairs = n_vns * (n_vns - 1) // 2
    pairs_with_zero = total_possible_pairs - total_pairs_with_overlap

    log(f"\n  Total VN pairs possible: {total_possible_pairs:,}")
    log(f"  Pairs with 0 co-raters: {pairs_with_zero:,} ({pairs_with_zero/total_possible_pairs*100:.2f}%)")
    log(f"  Pairs with 1+ co-raters: {total_pairs_with_overlap:,} ({total_pairs_with_overlap/total_possible_pairs*100:.2f}%)")

    log(f"\n  Distribution of pairs WITH overlap:")
    for label, lo, hi in [("1-5", 1, 5), ("6-20", 6, 20), ("21-100", 21, 100), ("100+", 101, None)]:
        if hi is None:
            count = int((counts_arr > 100).sum())
        else:
            count = int(((counts_arr >= lo) & (counts_arr <= hi)).sum())
        pct = count / total_pairs_with_overlap * 100 if total_pairs_with_overlap > 0 else 0
        log(f"    {label} co-raters: {count:,} ({pct:.1f}%)")

    if total_pairs_with_overlap > 0:
        log(f"\n  Co-rater count stats (pairs with 1+ overlap):")
        log(f"    Mean: {counts_arr.mean():.1f}")
        log(f"    Median: {float(np.median(counts_arr)):.1f}")
        log(f"    Max: {int(counts_arr.max()):,}")
        log(f"    P90: {float(np.percentile(counts_arr, 90)):.0f}")
        log(f"    P99: {float(np.percentile(counts_arr, 99)):.0f}")

    # Q5 only looks up co-rater counts for top-100 VNs by vote count. Extract
    # just that submatrix and return a small dict; the full Gramian (~480 MB)
    # can be GC'd after this function returns.
    log("  Extracting top-100 submatrix for Q5...")
    top_vids = [
        v for v, _ in sorted(
            ((v, c) for v, c in vn_vote_counts.items() if v in vn_idx),
            key=lambda x: -x[1],
        )[:100]
    ]
    top_indices = np.array([vn_idx[v] for v in top_vids], dtype=np.int64)
    sub = G.tocsr()[top_indices[:, None], top_indices].toarray()

    pair_counts = {}
    for i, v1 in enumerate(top_vids):
        for j in range(i + 1, len(top_vids)):
            v2 = top_vids[j]
            pair_counts[(min(v1, v2), max(v1, v2))] = int(sub[i, j])

    return pair_counts


def q3_vote_count_distribution(vn_vote_counts):
    """Q3: Vote count distribution at inclusion boundary."""
    log("\n=== Q3: Vote Count Distribution ===")

    buckets = {
        "15-30": 0,
        "31-50": 0,
        "51-100": 0,
        "101-500": 0,
        "501-1000": 0,
        "1000+": 0
    }

    for vid, count in vn_vote_counts.items():
        if count <= 30:
            buckets["15-30"] += 1
        elif count <= 50:
            buckets["31-50"] += 1
        elif count <= 100:
            buckets["51-100"] += 1
        elif count <= 500:
            buckets["101-500"] += 1
        elif count <= 1000:
            buckets["501-1000"] += 1
        else:
            buckets["1000+"] += 1

    total = len(vn_vote_counts)
    log(f"  Vote count distribution ({total:,} VNs):")
    cumulative = 0
    for bucket, count in buckets.items():
        pct = count / total * 100
        cumulative += count
        cum_pct = cumulative / total * 100
        log(f"    {bucket:>10} votes: {count:>5,} ({pct:>5.1f}%)  [cumulative: {cum_pct:.1f}%]")

    noisy_zone = buckets["15-30"]
    log(f"\n  RESULT: {noisy_zone:,} VNs ({noisy_zone/total*100:.1f}%) in 'noisy zone' (15-30 votes)")

    return buckets


def q4_noisy_zone_connections(vn_vote_counts, filtered_vns, writer_to_vns, producer_to_vns, cur):
    """Q4: Noisy-zone VNs with connections to popular VNs."""
    log("\n=== Q4: Noisy Zone Content Graph Connections ===")

    noisy_vns = {vid for vid, cnt in vn_vote_counts.items() if 15 <= cnt <= 30}
    popular_vns = {vid for vid, cnt in vn_vote_counts.items() if cnt >= 100}

    log(f"  Noisy zone VNs (15-30 votes): {len(noisy_vns):,}")
    log(f"  Popular VNs (100+ votes): {len(popular_vns):,}")

    # Check series connections
    cur.execute("""
        SELECT DISTINCT id, vid
        FROM vn_relations
        WHERE relation IN ('seq', 'preq', 'ser', 'par', 'side')
    """)
    series_edges = [(r[0], r[1]) for r in cur.fetchall()]

    noisy_with_popular_series = set()
    for a, b in series_edges:
        if a in noisy_vns and b in popular_vns:
            noisy_with_popular_series.add(a)
        if b in noisy_vns and a in popular_vns:
            noisy_with_popular_series.add(b)

    # Check writer connections
    noisy_with_popular_writer = set()
    for aid, vns in writer_to_vns.items():
        noisy_in_group = vns & noisy_vns
        popular_in_group = vns & popular_vns
        if noisy_in_group and popular_in_group:
            noisy_with_popular_writer.update(noisy_in_group)

    # Check producer connections
    noisy_with_popular_producer = set()
    for pid, vns in producer_to_vns.items():
        noisy_in_group = vns & noisy_vns
        popular_in_group = vns & popular_vns
        if noisy_in_group and popular_in_group:
            noisy_with_popular_producer.update(noisy_in_group)

    noisy_with_any_popular = noisy_with_popular_series | noisy_with_popular_writer | noisy_with_popular_producer

    log(f"\n  Noisy VNs with series connection to popular: {len(noisy_with_popular_series):,}")
    log(f"  Noisy VNs with shared writer to popular: {len(noisy_with_popular_writer):,}")
    log(f"  Noisy VNs with shared producer to popular: {len(noisy_with_popular_producer):,}")
    log(f"\n  RESULT: {len(noisy_with_any_popular):,} / {len(noisy_vns):,} noisy VNs ({len(noisy_with_any_popular)/len(noisy_vns)*100:.1f}%) have content connection to a popular VN")


def q5_ease_vs_corater_correlation(pair_counts, filtered_vns, vn_vote_counts):
    """Q5: EASE similarity vs co-rater count correlation for top VNs."""
    log("\n=== Q5: EASE Similarity vs Co-rater Correlation ===")

    b_path = "priv/data/ease_B.npy"
    meta_path = "priv/data/ease_B_meta.json"

    if not os.path.exists(b_path) or not os.path.exists(meta_path):
        log(f"  SKIP: {b_path} or {meta_path} not found. Run training first.")
        return

    log("  Loading EASE B matrix...")
    B = np.load(b_path)
    with open(meta_path) as f:
        meta = json.load(f)
    idx_to_vndb = meta["idx_to_vndb"]
    vndb_to_idx = {v: i for i, v in enumerate(idx_to_vndb)}

    # Get top 100 most-rated VNs that are in the B matrix
    top_vns = sorted(
        [(vid, cnt) for vid, cnt in vn_vote_counts.items() if vid in vndb_to_idx],
        key=lambda x: -x[1]
    )[:100]
    top_vids = [v[0] for v in top_vns]

    log(f"  Analyzing top {len(top_vids)} VNs by vote count...")

    # For each top VN, get EASE similarities and co-rater counts to other top VNs
    ease_sims = []
    corater_counts = []

    for i, v1 in enumerate(top_vids):
        for v2 in top_vids[i+1:]:
            idx1, idx2 = vndb_to_idx[v1], vndb_to_idx[v2]
            ease_sim = B[idx1, idx2]

            pair_key = (min(v1, v2), max(v1, v2))
            coraters = pair_counts.get(pair_key, 0)

            ease_sims.append(ease_sim)
            corater_counts.append(coraters)

    # Compute rank correlation
    ease_ranks = stats.rankdata(ease_sims)
    corater_ranks = stats.rankdata(corater_counts)

    spearman_r, spearman_p = stats.spearmanr(ease_sims, corater_counts)
    pearson_r, pearson_p = stats.pearsonr(ease_sims, corater_counts)

    log(f"\n  Pairs analyzed: {len(ease_sims):,}")
    log(f"  Spearman rank correlation: {spearman_r:.3f} (p={spearman_p:.2e})")
    log(f"  Pearson correlation: {pearson_r:.3f} (p={pearson_p:.2e})")

    if spearman_r > 0.9:
        log("  INTERPRETATION: Very high correlation — EASE isn't adding much over raw co-rating for popular titles")
    elif spearman_r > 0.7:
        log("  INTERPRETATION: High correlation — EASE mostly tracks co-rating but does some reweighting")
    elif spearman_r > 0.5:
        log("  INTERPRETATION: Moderate correlation — matrix inverse is doing real work in reweighting")
    else:
        log("  INTERPRETATION: Low correlation — EASE significantly transforms the co-occurrence signal")


def q6_rating_distribution_per_vn(cur, filtered_vns, vn_vote_counts):
    """Q6: Rating distribution (stddev, skew) per VN across popularity tiers."""
    log("\n=== Q6: Rating Distribution Per VN ===")

    # Sample VNs from different tiers
    tiers = {
        "15-30": [],
        "31-100": [],
        "101-500": [],
        "500+": []
    }

    for vid, cnt in vn_vote_counts.items():
        if cnt <= 30:
            tiers["15-30"].append(vid)
        elif cnt <= 100:
            tiers["31-100"].append(vid)
        elif cnt <= 500:
            tiers["101-500"].append(vid)
        else:
            tiers["500+"].append(vid)

    # Get all ratings for filtered VNs
    log("  Loading all ratings...")
    cur.execute("""
        SELECT vid, vote
        FROM ulist_vns
        WHERE vote IS NOT NULL AND vote > 0
    """)
    vn_ratings = defaultdict(list)
    for vid, vote in cur.fetchall():
        if vid in filtered_vns:
            vn_ratings[vid].append(vote / 10.0)  # Convert to 1-10 scale

    log(f"\n  Rating distribution stats by popularity tier:")
    for tier_name, tier_vns in tiers.items():
        if not tier_vns:
            continue

        stds = []
        skews = []
        means = []

        for vid in tier_vns:
            ratings = vn_ratings.get(vid, [])
            if len(ratings) >= 5:
                stds.append(np.std(ratings))
                means.append(np.mean(ratings))
                if len(ratings) >= 8:  # Need more samples for skew
                    skews.append(stats.skew(ratings))

        if stds:
            log(f"\n  Tier {tier_name} ({len(tier_vns):,} VNs):")
            log(f"    Mean rating: {np.mean(means):.2f} (std across VNs: {np.std(means):.2f})")
            log(f"    Avg within-VN stddev: {np.mean(stds):.2f}")
            log(f"    Stddev range: [{min(stds):.2f}, {max(stds):.2f}]")
            if skews:
                log(f"    Avg skew: {np.mean(skews):.2f} (negative = left-skewed / harsh raters)")

    # Overall assessment
    all_stds = [np.std(r) for r in vn_ratings.values() if len(r) >= 5]
    avg_std = np.mean(all_stds)

    log(f"\n  INTERPRETATION:")
    if avg_std < 1.0:
        log(f"    Avg within-VN stddev is {avg_std:.2f} — tight distributions, percentile normalization may amplify noise")
    elif avg_std < 1.5:
        log(f"    Avg within-VN stddev is {avg_std:.2f} — moderate spread, percentile normalization could help")
    else:
        log(f"    Avg within-VN stddev is {avg_std:.2f} — good spread, percentile normalization would capture meaningful signal")


def main():
    log("Connecting to database...")
    conn = psycopg2.connect(dbname=DB_NAME)
    cur = conn.cursor()

    # Get filtered data
    filtered_vns, filtered_users, vn_vote_counts = get_filtered_vns_and_users(cur)

    # Q1: Content graph connectivity
    connected_vns, writer_to_vns, producer_to_vns = q1_content_graph_connectivity(cur, filtered_vns)

    # Q2: Co-rater distribution (vectorized via XᵀX)
    pair_counts = q2_corater_distribution(cur, filtered_vns, filtered_users, vn_vote_counts)

    # Q3: Vote count distribution
    q3_vote_count_distribution(vn_vote_counts)

    # Q4: Noisy zone connections
    q4_noisy_zone_connections(vn_vote_counts, filtered_vns, writer_to_vns, producer_to_vns, cur)

    # Q5: EASE vs co-rater correlation
    q5_ease_vs_corater_correlation(pair_counts, filtered_vns, vn_vote_counts)

    # Q6: Rating distribution per VN
    q6_rating_distribution_per_vn(cur, filtered_vns, vn_vote_counts)

    cur.close()
    conn.close()

    log("\n=== Done ===")


if __name__ == "__main__":
    main()
