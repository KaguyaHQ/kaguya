#!/usr/bin/env python3
"""Pre-generate top-30 EASE recommendations for every VNDB user with >=5 votes.

Mirrors `Kaguya.Recommendations.VndbUser.build_prefs_and_masks/1` verbatim
so the offline output matches what the live path would produce for the
same user against the same `ease_B.npy` model. That includes:

  * vote -> vote / 10.0 as pref value
  * else first-priority label from [4, 2, 5, 1, 3] -> LABEL_VALUE
  * Blacklist (6) excluded from prefs, added to mask
  * Any of labels {1, 2, 3, 4, 6} adds vid to mask (Wishlist deliberately not masked)
  * mean-centered pref values
  * Case-4 zeroing: (pref < 0) & (B < 0) -> contrib = 0
  * Suppress BOTH explicit mask_vids AND the user's pref indices
    (matches `suppress_prefs` in the Elixir Engine + `build_mask` in
    the Python reference `../recs/vn_recommender/scoring.py`).

Skips users with fewer than MIN_PREFS (3) vocabulary-matched prefs; those
can't be scored.

Outputs three files (default: priv/data/):

  * pregenerated_recs.bin
      <magic: "KGPR"> <version: u8 = 1>
      <n_users: u32>
        for each user:
          <uid_len: u8> <uid: bytes>
          <n_prefs: u16>                  # vocab-matched pref count (for display)
          <n_recs: u16>                   # always TOP_K (30)
          for each rec:
            <vid_len: u8> <vid: bytes>
            <score: f32>
            <total_positive: f32>         # denominator for tooltip %
            <n_reasons: u8>               # top-N_REASONS (3)
            for each reason:
              <rid_len: u8> <rid: bytes>  # source VN id ("vNNN")
              <contribution: f32>         # raw positive contribution
              <vote: u8>                  # VNDB vote 10-100 (1.0-10.0), 0=label-only
              <label_id: u8>              # VNDB label id 1-5 when vote=0, else 0

  * vndb_username_lookup.bin
      <magic: "KGUL"> <version: u8 = 1>
      <n_users: u32>
        for each user:
          <uid_len: u8> <uid: bytes>
          <uname_len: u16> <uname: bytes (UTF-8, LOWERCASED at gen time)>

    Usernames lowercased here so Elixir-side lookups are case-insensitive
    without a String.downcase per request.

  * pregenerated_recs_meta.json
      {"built_at": iso, "n_users_scored": int, "n_users_total": int,
       "model_version": str, "source_dump_date": str}

Usage:
    python priv/recommendations/pregenerate_user_recs.py \\
        [--db-url postgresql://...] [--out-dir priv/data] \\
        [--ease priv/data/ease_B.npy] [--meta priv/data/ease_B_meta.json]

Note: this script buffers the entire `ulist_vns` table in memory (per-user
grouping for scoring), so it needs a meaty box — roughly 4-10 GB RAM for
~10M rows. Run it on the server doing the model training, or similar.

Requires: numpy, psycopg2-binary (same deps as sibling training scripts).
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import time

import numpy as np
import psycopg2


# Mirror of Kaguya.Recommendations.VndbUser module attributes. Keep these
# in lockstep with the Elixir module; drifting here would produce offline
# recs that differ from the live path for the same user.
LABEL_VALUE = {2: 7.5, 1: 7.0, 5: 6.0, 3: 5.0, 4: 3.0}
LABEL_PRIORITY = [4, 2, 5, 1, 3]
MASK_LABELS = {1, 2, 3, 4, 6}
BLACKLIST = 6

# Cold-start floor. Must match @min_prefs in
# `lib/kaguya/recommendations/nx/engine.ex` (currently 3).
MIN_PREFS = 3

# Per the spec. Top-30 gives ~20% headroom over the displayed top-25 so
# that catalog-drift (vn_ids in the snapshot that aren't in Kaguya's
# local `visual_novels` at hydration time — VNDB added a VN after our
# last dump sync, a title got hidden, etc.) doesn't leave the widget
# with a short list. Bumping this costs ~30B per user per extra rec.
TOP_K = 30

# Matches @n_reasons in `lib/kaguya/recommendations/nx/engine.ex`. The
# tooltip on the frontend renders this many "because you liked" entries
# per rec.
N_REASONS = 3

# Signal floor for inclusion in the pregen set. "vote" here means "row
# with a vote" — matches the spec's ">=5 votes" phrasing. Users below
# this get skipped even if they have labels; the rationale is that a
# mostly-labeled user doesn't give EASE a reliable pref vector.
MIN_VOTES_FOR_INCLUSION = 5

# Fallback: when centered scoring produces fewer than N_FALLBACK_MIN
# positive candidates (typical of whales + harsh raters), rescore
# using only the user's top-N rated items with raw (non-centered)
# values. Centering starves whales of boost mass via Case-4 asymmetry;
# a bounded top-N input side-steps that without introducing the
# "popularity slop" that unbounded no-centering produces.
FALLBACK_TOP_N = 100
# Trigger the fallback when primary returns below this many recs — 1
# or 2 primary picks is effectively a broken experience, same as zero.
N_FALLBACK_MIN = 3

# Output-side vote floor per candidate VN. Mirrors Vasanth's
# `--min-display-votes` knob on the similar-VNs pipeline (see
# priv/repo/scripts/ease/README.md): VNs below this threshold still
# inform training (their correlation signal matters), but they never
# appear in served recommendations. Saves users from 6-vote niche
# titles surfacing as top picks.
MIN_DISPLAY_VOTES = 100

# Binary file framing. Bumps to version let the Elixir loader refuse to
# parse a format it doesn't know about rather than crashing on shape
# mismatches. Keep in lockstep with
# `Kaguya.Recommendations.PregeneratedRecs.Loader`.
RECS_MAGIC = b"KGPR"
USERNAME_MAGIC = b"KGUL"
FILE_VERSION = 1


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------


def load_model(ease_path, meta_path):
    log(f"Loading B from {ease_path}...")
    B = np.load(ease_path)
    log(f"  B shape: {B.shape}, dtype={B.dtype}")

    log(f"Loading meta from {meta_path}...")
    with open(meta_path) as f:
        meta = json.load(f)

    idx_to_vndb = meta["idx_to_vndb"]
    vndb_to_idx = {v: i for i, v in enumerate(idx_to_vndb)}

    if B.shape[0] != len(idx_to_vndb) or B.shape[1] != len(idx_to_vndb):
        raise ValueError(
            f"B shape {B.shape} doesn't match idx_to_vndb length {len(idx_to_vndb)}"
        )

    # Model version surfaces in the meta JSON so ops can verify which
    # snapshot the Elixir loader is serving. Fall back to the B file's
    # mtime if the meta doesn't carry a version string.
    model_version = meta.get("model_version") or meta.get("built_at") \
        or time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(os.path.getmtime(ease_path)))

    return B, idx_to_vndb, vndb_to_idx, model_version


# Eligible-users CTE — single source of truth for the ">=5 votes"
# inclusion floor. Pushed into SQL so neither `fetch_all_users` nor
# `fetch_ulist_rows` pulls the 100k+ light/dormant VNDB accounts that
# get skipped by MIN_VOTES_FOR_INCLUSION downstream anyway.
_ELIGIBLE_UIDS_CTE = f"""
    WITH eligible_uids AS (
        SELECT uid
        FROM ulist_vns
        WHERE vote IS NOT NULL
        GROUP BY uid
        HAVING COUNT(*) >= {MIN_VOTES_FOR_INCLUSION}
    )
"""


def fetch_all_users(cur):
    """Return list of (uid, username) for every ELIGIBLE user.

    "Eligible" = at least MIN_VOTES_FOR_INCLUSION votes in ulist_vns.
    Users with fewer votes get dropped downstream anyway, so there's no
    value in carrying them through memory or writing them into the
    username lookup binary (searches against unscored users correctly
    return :not_found).

    Username is lowercased here so the downstream lookup file doesn't
    need a normalization pass at load time. Rows with NULL usernames
    (shouldn't happen on VNDB, but defensive) are skipped.
    """
    cur.execute(
        _ELIGIBLE_UIDS_CTE
        + """
        SELECT u.id, u.username
        FROM users u
        JOIN eligible_uids e ON e.uid = u.id
        WHERE u.username IS NOT NULL
        """
    )
    users = []
    for uid, username in cur:
        # VNDB uids are stored without the leading 'u' in older dump
        # snapshots and with it in newer ones. Normalize to `u<n>` —
        # matches `@uid_regex` on the Elixir side (`^u\d{1,10}$`).
        uid_str = uid if str(uid).startswith("u") else f"u{uid}"
        users.append((uid_str, username.lower()))
    log(f"  Found {len(users):,} eligible users (>= {MIN_VOTES_FOR_INCLUSION} votes)")
    return users


def compute_recommendable_mask(cur, vndb_to_idx, min_display_votes):
    """Return a numpy bool array of shape (n_items,) — True for VNs
    with >= `min_display_votes` votes in ulist_vns, in the same index
    order as the B matrix's `idx_to_vndb`. Applied as an output-side
    mask at scoring time; niche VNs stay in the Gram matrix for
    similarity quality but can't surface as recs.
    """
    log(f"Computing recommendable mask (min-display-votes={min_display_votes})...")
    cur.execute(
        """
        SELECT vid
        FROM ulist_vns
        WHERE vote IS NOT NULL
        GROUP BY vid
        HAVING COUNT(*) >= %s
        """,
        (min_display_votes,),
    )

    eligible = set()
    for (vid,) in cur:
        vid_str = vid if str(vid).startswith("v") else f"v{vid}"
        eligible.add(vid_str)

    n_items = len(vndb_to_idx)
    mask = np.zeros(n_items, dtype=np.bool_)
    for vid, idx in vndb_to_idx.items():
        if vid in eligible:
            mask[idx] = True

    log(
        f"  {int(mask.sum()):,}/{n_items:,} VNs eligible for recs "
        f"({100.0 * mask.sum() / n_items:.1f}%)"
    )
    return mask


def fetch_ulist_rows(cur):
    """Stream uid -> list of (vid, vote, labels) from ulist_vns,
    restricted to eligible users only.
    """
    log("Querying ulist_vns...")
    cur.execute(
        _ELIGIBLE_UIDS_CTE
        + """
        SELECT ul.uid, ul.vid, ul.vote, ul.labels
        FROM ulist_vns ul
        JOIN eligible_uids e ON e.uid = ul.uid
        WHERE ul.vote IS NOT NULL
           OR ul.labels && ARRAY[1,2,3,4,5,6]::smallint[]
        """
    )
    per_user = {}
    for uid, vid, vote, labels in cur:
        uid_str = uid if str(uid).startswith("u") else f"u{uid}"
        vid_str = vid if str(vid).startswith("v") else f"v{vid}"
        per_user.setdefault(uid_str, []).append((vid_str, vote, labels or []))
    log(f"  Grouped rows across {len(per_user):,} users")
    return per_user


# --------------------------------------------------------------------------
# Pref / mask construction (mirror of Elixir build_prefs_and_masks/1)
# --------------------------------------------------------------------------


def build_prefs_and_masks(rows):
    """Apply the VndbUser.build_prefs_and_masks semantics to one user's rows.

    Returns (ratings, mask_vids, vote_count, sources) where:
      * ratings: {vid: value}    — pref items (votes or label-derived)
      * mask_vids: list[str]     — explicit mask (consumed labels + blacklist)
      * vote_count: int          — for the >=5 votes filter upstream
      * sources: {vid: (vote, label_id)} — original VNDB signal per pref vid;
        vote is the int (10-100) or 0, label_id is 1-5 or 0. Exactly one of
        the two is nonzero. Used at binary-write time so the reason rows
        carry the user's original signal into the served tooltip.
    """
    ratings = {}
    mask_vids = []
    vote_count = 0
    sources = {}

    for vid, vote, labels in rows:
        label_set = set(labels) if labels else set()

        if label_set & MASK_LABELS:
            mask_vids.append(vid)

        if BLACKLIST in label_set:
            # Blacklist: already in mask, skip from prefs.
            continue

        if vote is not None:
            ratings[vid] = float(vote) / 10.0
            sources[vid] = (int(vote), 0)
            vote_count += 1
            continue

        for label_id in LABEL_PRIORITY:
            if label_id in label_set:
                ratings[vid] = LABEL_VALUE[label_id]
                sources[vid] = (0, label_id)
                break

    return ratings, mask_vids, vote_count, sources


def build_user_vector(ratings, vndb_to_idx):
    """Intersect ratings with model vocab. Returns
    (prefs_idx: np.int64[K], raw_vals: np.float32[K], vid_list) or None
    when fewer than MIN_PREFS prefs survive. Centering happens at the
    call site so downstream can pass centered or raw values.
    """
    pairs = [(vndb_to_idx[v], float(r), v) for v, r in ratings.items() if v in vndb_to_idx]
    if len(pairs) < MIN_PREFS:
        return None

    idx = np.array([p[0] for p in pairs], dtype=np.int64)
    vals = np.array([p[1] for p in pairs], dtype=np.float32)
    vid_list = [p[2] for p in pairs]
    return idx, vals, vid_list


def build_topn_vector(vocab_votes, top_n, vndb_to_idx):
    """Fallback input builder: take the user's TOP_N highest-rated VNs
    (vote-based only — labels without a vote are dropped since they
    carry no ranking). Returns (prefs_idx, raw_vals, vid_list) at
    most TOP_N long, or None if fewer than MIN_PREFS clear the cut.
    """
    sorted_votes = sorted(vocab_votes.items(), key=lambda kv: kv[1], reverse=True)[:top_n]
    if len(sorted_votes) < MIN_PREFS:
        return None

    idx = np.array([vndb_to_idx[v] for v, _ in sorted_votes], dtype=np.int64)
    vals = np.array([r for _, r in sorted_votes], dtype=np.float32)
    vid_list = [v for v, _ in sorted_votes]
    return idx, vals, vid_list


# --------------------------------------------------------------------------
# Scoring (mirror of ease_scores + suppress_prefs in the Elixir Engine and
# score_items/build_mask in the Python reference scoring.py)
# --------------------------------------------------------------------------


def score_user(
    B, prefs_idx, prefs_val, mask_vids, vndb_to_idx, pref_vids, sources,
    recommendable_mask,
):
    """Returns `(top_indices, scores, reasons_per_rec)` where
    `reasons_per_rec[i]` is `(top_reasons, total_positive)` for the i-th
    rec in `top_indices`. `top_reasons` is a list of
    `(pref_vndb_id, contribution, vote, label_id)` tuples sorted by
    contribution desc, length <= N_REASONS. vote/label_id come from
    `sources` — carried through so the served tooltip can render
    "Because they rated X N★" / status text, not just a title.
    """
    rows = B[prefs_idx]                         # (k, n_items)
    col = prefs_val[:, None]                    # (k, 1)
    contrib = col * rows

    # Case-4 zeroing: (pref < 0) & (B < 0) -> 0. Avoids "you hated X,
    # here's the opposite" spurious-positive recs.
    contrib = np.where((col < 0) & (rows < 0), 0.0, contrib)
    scores = contrib.sum(axis=0).astype(np.float32)

    # Suppress: explicit mask_vids PLUS the user's pref indices. Matches
    # engine.ex suppress_prefs/2 and scoring.py build_mask's `mask[prefs] = True`.
    scores[prefs_idx] = -np.inf
    for vid in mask_vids:
        i = vndb_to_idx.get(vid)
        if i is not None:
            scores[i] = -np.inf

    # Output-side vote floor: VNs with <MIN_DISPLAY_VOTES can't surface
    # even if their score is high. They contributed to training (their
    # correlations help position neighbors); they just don't deserve a
    # display slot. See `compute_recommendable_mask`.
    scores[~recommendable_mask] = -np.inf

    # EASE score <= 0 means active anti-signal (the model predicts the
    # user would dislike this candidate). Don't surface those.
    scores[scores <= 0] = -np.inf

    # Top-K. argpartition gives O(n) unsorted top — then a small sort on
    # k elements for the final order.
    n_finite = int(np.isfinite(scores).sum())
    if n_finite == 0:
        return []
    k = min(TOP_K, n_finite)
    top = np.argpartition(-scores, k - 1)[:k]
    top = top[np.argsort(-scores[top])]

    # Per-rec reasons. For each picked column j, find the top-N_REASONS
    # positive rows of `contrib[:, j]` and the sum of all positive rows
    # (the denominator the Elixir engine calls `total_positive_contribution`).
    reasons_per_rec = []
    for j in top:
        col_j = contrib[:, j]
        pos_mask = col_j > 0
        if not np.any(pos_mask):
            reasons_per_rec.append(([], 0.0))
            continue

        total_positive = float(col_j[pos_mask].sum())
        pos_indices = np.where(pos_mask)[0]
        pos_vals = col_j[pos_indices]
        order = np.argsort(-pos_vals)[:N_REASONS]

        picks = []
        for k_idx in order:
            pref_pos = int(pos_indices[k_idx])
            pref_vid = pref_vids[pref_pos]
            vote, label_id = sources.get(pref_vid, (0, 0))
            picks.append(
                (pref_vid, float(pos_vals[k_idx]), vote, label_id)
            )
        reasons_per_rec.append((picks, total_positive))

    return top.tolist(), scores, reasons_per_rec


# --------------------------------------------------------------------------
# Percentile table (baked into ease_B_meta.json; serving side looks it up)
# --------------------------------------------------------------------------


def _merge_percentiles_into_ease_meta(ease_meta_path, boundaries, fallback_scale):
    """Embed percentile boundaries + the fallback-score rescale factor
    in the B matrix meta. The serving side (Python here, Elixir
    Engine on the logged-in path) reads both: rescales fallback
    scores inline before percentile lookup so fallback users land in
    the same distribution as primary users.
    """
    with open(ease_meta_path) as f:
        meta = json.load(f)
    meta["score_percentiles"] = boundaries
    meta["fallback_score_scale"] = fallback_scale
    with open(ease_meta_path, "w") as f:
        json.dump(meta, f)
    log(f"Wrote score_percentiles + fallback_score_scale into {ease_meta_path}")


# --------------------------------------------------------------------------
# Packed binary writers
# --------------------------------------------------------------------------


def write_recs(out_path, entries):
    """entries: list of (uid, pref_count, [(vid, score, total_positive, [(rid, contrib, vote, label_id), ...]), ...])."""
    with open(out_path, "wb") as f:
        f.write(RECS_MAGIC)
        f.write(struct.pack(">B", FILE_VERSION))
        f.write(struct.pack(">I", len(entries)))
        for uid, pref_count, recs in entries:
            uid_b = uid.encode("ascii")
            if len(uid_b) > 255:
                raise ValueError(f"uid {uid!r} too long")
            f.write(struct.pack(">B", len(uid_b)))
            f.write(uid_b)
            f.write(struct.pack(">H", min(pref_count, 0xFFFF)))
            f.write(struct.pack(">H", len(recs)))
            for vid, score, total_positive, reasons in recs:
                vb = vid.encode("ascii")
                if len(vb) > 255:
                    raise ValueError(f"vid {vid!r} too long")
                f.write(struct.pack(">B", len(vb)))
                f.write(vb)
                f.write(struct.pack(">f", float(score)))
                f.write(struct.pack(">f", float(total_positive)))
                if len(reasons) > 255:
                    raise ValueError(f"too many reasons for {vid!r}: {len(reasons)}")
                f.write(struct.pack(">B", len(reasons)))
                for rid, contrib, vote, label_id in reasons:
                    rb = rid.encode("ascii")
                    if len(rb) > 255:
                        raise ValueError(f"reason vid {rid!r} too long")
                    # vote: VNDB integer 10-100 (1.0-10.0 displayed), 0 = label-only
                    # label_id: VNDB label id 1-5 when vote=0; 0 when vote is set.
                    if not (0 <= vote <= 100):
                        raise ValueError(f"vote out of range for {rid!r}: {vote}")
                    if not (0 <= label_id <= 5):
                        raise ValueError(
                            f"label_id out of range for {rid!r}: {label_id}"
                        )
                    f.write(struct.pack(">B", len(rb)))
                    f.write(rb)
                    f.write(struct.pack(">f", float(contrib)))
                    f.write(struct.pack(">B", vote))
                    f.write(struct.pack(">B", label_id))


def write_username_lookup(out_path, users):
    """users: list of (uid, lowercased_username)."""
    with open(out_path, "wb") as f:
        f.write(USERNAME_MAGIC)
        f.write(struct.pack(">B", FILE_VERSION))
        f.write(struct.pack(">I", len(users)))
        for uid, uname in users:
            uid_b = uid.encode("ascii")
            uname_b = uname.encode("utf-8")
            if len(uid_b) > 255:
                raise ValueError(f"uid {uid!r} too long")
            if len(uname_b) > 0xFFFF:
                raise ValueError(f"username {uname!r} too long")
            f.write(struct.pack(">B", len(uid_b)))
            f.write(uid_b)
            f.write(struct.pack(">H", len(uname_b)))
            f.write(uname_b)


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--db-url",
        default=os.environ.get("VNDB_DB_URL") or "dbname=vndb_latest",
        help="Postgres connection string (libpq keyword form or URL). "
             "Defaults to VNDB_DB_URL env or `dbname=vndb_latest`.",
    )
    ap.add_argument("--ease", default="priv/data/ease_B.npy")
    ap.add_argument("--meta", default="priv/data/ease_B_meta.json")
    ap.add_argument("--out-dir", default="priv/data")
    ap.add_argument("--source-dump-date", default=time.strftime("%Y-%m-%d"),
                    help="Date string of the source VNDB dump (default: today)")
    ap.add_argument(
        "--min-display-votes",
        type=int,
        default=MIN_DISPLAY_VOTES,
        help=(
            "Min vote count per VN for it to be eligible as a recommendation. "
            "Does NOT affect training — low-vote VNs still contribute to the "
            f"Gram matrix. Default: {MIN_DISPLAY_VOTES}."
        ),
    )
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    B, idx_to_vndb, vndb_to_idx, model_version = load_model(args.ease, args.meta)

    log(f"Connecting to Postgres: {args.db_url}")
    conn = psycopg2.connect(args.db_url)
    cur = conn.cursor(name="pregen_cur")  # server-side cursor for big streams
    # Separate non-server cursor for the small queries.
    small = conn.cursor()

    users = fetch_all_users(small)
    recommendable_mask = compute_recommendable_mask(
        small, vndb_to_idx, args.min_display_votes
    )
    small.close()

    per_user_rows = fetch_ulist_rows(cur)
    cur.close()
    conn.close()

    n_users_total = len(users)
    n_scored = 0
    n_skipped_few_votes = 0
    n_skipped_few_prefs = 0
    n_fallback = 0
    entries = []

    t0 = time.time()
    log("Scoring users...")

    for i, (uid, _uname) in enumerate(users):
        rows = per_user_rows.get(uid)
        if not rows:
            n_skipped_few_votes += 1
            continue

        ratings, mask_vids, vote_count, sources = build_prefs_and_masks(rows)
        if vote_count < MIN_VOTES_FOR_INCLUSION:
            n_skipped_few_votes += 1
            continue

        vec = build_user_vector(ratings, vndb_to_idx)
        if vec is None:
            n_skipped_few_prefs += 1
            continue

        prefs_idx, raw_vals, vid_list = vec
        centered_vals = raw_vals - raw_vals.mean()

        # Primary: centered scoring with Case-4 zeroing.
        result = score_user(
            B, prefs_idx, centered_vals, mask_vids, vndb_to_idx, vid_list,
            sources, recommendable_mask,
        )
        scoring_path = 0  # primary

        # Fallback fires when primary returns fewer than N_FALLBACK_MIN
        # picks — one-or-two-rec slates are effectively broken.
        if not result or len(result[0]) < N_FALLBACK_MIN:
            votes_only = {v: vote for v, (vote, _) in sources.items()
                          if vote > 0 and v in vndb_to_idx}
            fb_vec = build_topn_vector(
                {v: vote / 10.0 for v, vote in votes_only.items()},
                FALLBACK_TOP_N,
                vndb_to_idx,
            )
            if fb_vec is not None:
                fb_idx, fb_vals, fb_vids = fb_vec
                full_mask = list({*mask_vids, *ratings.keys()})
                fb_result = score_user(
                    B, fb_idx, fb_vals, full_mask, vndb_to_idx, fb_vids,
                    sources, recommendable_mask,
                )
                if fb_result:
                    n_fallback += 1
                    result = fb_result
                    scoring_path = 1  # fallback

        if not result:
            n_skipped_few_prefs += 1
            continue

        top_indices, scores, reasons_per_rec = result
        recs = [
            (
                idx_to_vndb[j],
                float(scores[j]),
                total_positive,
                top_reasons,
            )
            for j, (top_reasons, total_positive) in zip(top_indices, reasons_per_rec)
        ]
        # Path is tracked per-user (every rec of a given user came from the
        # same scoring pass). Stripped before writing to the binary —
        # rescaling below brings fallback scores into the primary range so
        # the served distribution is single-scale.
        entries.append((uid, len(prefs_idx), recs, scoring_path))
        n_scored += 1

        if n_scored % 5000 == 0:
            elapsed = time.time() - t0
            log(f"  scored {n_scored:,} users ({elapsed:.1f}s, {n_scored / max(elapsed, 0.001):.0f}/s)")

    log(f"Scoring complete: {n_scored:,} scored "
        f"({n_fallback:,} via top-{FALLBACK_TOP_N} fallback), "
        f"{n_skipped_few_votes:,} skipped for <{MIN_VOTES_FOR_INCLUSION} votes, "
        f"{n_skipped_few_prefs:,} skipped for <{MIN_PREFS} vocab prefs")

    # Rescale fallback users' scores so they mix cleanly into a single
    # percentile distribution with primary users. Without this,
    # fallback's ~10x-larger raw magnitudes saturate the upper tail
    # (fallback recs all land at p99+, primary users' top picks get
    # pulled down 1-2 pctile). We pick the scale factor empirically
    # from each path's p99 so the two distributions' upper tails align.
    def _pctile(scores, p):
        arr = np.asarray(scores, dtype=np.float32)
        arr.sort()
        return float(arr[min(int(p * (len(arr) - 1) / 100), len(arr) - 1)])

    primary_scores = [s for _, _, recs, path in entries for _, s, _, _ in recs if path == 0]
    fallback_scores = [s for _, _, recs, path in entries for _, s, _, _ in recs if path == 1]

    fallback_scale = 1.0
    if primary_scores and fallback_scores:
        p99_primary = _pctile(primary_scores, 99)
        p99_fallback = _pctile(fallback_scores, 99)
        if p99_fallback > 0:
            fallback_scale = p99_primary / p99_fallback
        log(f"Fallback rescale: primary_p99={p99_primary:.3f}, "
            f"fallback_p99={p99_fallback:.3f}, scale={fallback_scale:.4f}")

    # Apply the scale + strip the per-user path flag before serializing.
    rescaled_entries = []
    for uid, pref_count, recs, path in entries:
        if path == 1 and fallback_scale != 1.0:
            recs = [
                (vid, s * fallback_scale, tp * fallback_scale,
                 [(rid, c * fallback_scale, vote, lid) for rid, c, vote, lid in rs])
                for vid, s, tp, rs in recs
            ]
        rescaled_entries.append((uid, pref_count, recs))
    entries = rescaled_entries

    # Now all scores live on one distribution — compute a single
    # percentile table for the serving side.
    all_scores = np.array(
        [s for _, _, recs in entries for _, s, _, _ in recs],
        dtype=np.float32,
    )
    all_scores.sort()
    percentile_boundaries = [
        float(all_scores[min(int(p * (len(all_scores) - 1) / 100), len(all_scores) - 1)])
        for p in range(101)
    ]
    log(f"Percentile distribution: p0={percentile_boundaries[0]:.3f}, "
        f"p50={percentile_boundaries[50]:.3f}, p99={percentile_boundaries[99]:.3f}, "
        f"p100={percentile_boundaries[100]:.3f}")

    _merge_percentiles_into_ease_meta(
        args.meta, percentile_boundaries, fallback_scale,
    )

    recs_path = os.path.join(args.out_dir, "pregenerated_recs.bin")
    lookup_path = os.path.join(args.out_dir, "vndb_username_lookup.bin")
    meta_path = os.path.join(args.out_dir, "pregenerated_recs_meta.json")

    log(f"Writing recs to {recs_path}...")
    write_recs(recs_path, entries)

    log(f"Writing username lookup to {lookup_path}...")
    write_username_lookup(lookup_path, users)

    meta = {
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "n_users_scored": n_scored,
        "n_users_total": n_users_total,
        "model_version": model_version,
        "source_dump_date": args.source_dump_date,
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    log(f"Wrote meta to {meta_path}")

    for p in (recs_path, lookup_path, meta_path):
        log(f"  {p}: {os.path.getsize(p) / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
