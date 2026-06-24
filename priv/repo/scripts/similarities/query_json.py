#!/usr/bin/env python3
"""Query EASE similarities JSON with VNDB title lookup.

Usage:
    python3 priv/repo/scripts/similarities/query_json.py "CLANNAD"
    python3 priv/repo/scripts/similarities/query_json.py v2002
    python3 priv/repo/scripts/similarities/query_json.py --file priv/data/other.json "Fate"
"""
import argparse
import json
import sys

import psycopg2


def load_titles(db_name):
    conn = psycopg2.connect(dbname=db_name)
    cur = conn.cursor()
    # English title → latin romanization of original → original title
    cur.execute("""
        SELECT v.id,
               COALESCE(en.title, ol.latin, ol.title) as title,
               COALESCE(vc.cnt, 0) as vote_count
        FROM vn v
        LEFT JOIN vn_titles en ON en.id = v.id AND en.lang = 'en'
        LEFT JOIN vn_titles ol ON ol.id = v.id AND ol.lang = v.olang
        LEFT JOIN (
            SELECT vid, count(*) as cnt FROM ulist_vns
            WHERE vote IS NOT NULL GROUP BY vid
        ) vc ON vc.vid = v.id
    """)
    rows = cur.fetchall()
    titles = {row[0]: row[1] for row in rows}
    vote_counts = {row[0]: row[2] for row in rows}

    # Get ratings
    cur2 = conn.cursor()
    cur2.execute("""
        SELECT vid, round(avg(vote) / 10.0, 2) as avg_rating
        FROM ulist_vns WHERE vote IS NOT NULL
        GROUP BY vid
    """)
    ratings = {row[0]: float(row[1]) for row in cur2}
    cur2.close()
    conn.close()
    return titles, vote_counts, ratings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("search", help="VN title (fuzzy) or vndb_id (e.g. v2002)")
    parser.add_argument("--file", default="priv/data/ease_similarities.json")
    parser.add_argument("--db", default="vndb_latest")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    titles, vote_counts, ratings = load_titles(args.db)

    with open(args.file) as f:
        data = json.load(f)

    # Find VN
    if args.search.startswith("v") and args.search[1:].isdigit():
        vid = args.search
    else:
        term = args.search.lower()
        matches = [(k, t) for k, t in titles.items() if term in t.lower()]
        matches.sort(key=lambda x: -vote_counts.get(x[0], 0))
        if not matches:
            print(f"No VN found for: {args.search}")
            sys.exit(1)
        vid = matches[0][0]

    title = titles.get(vid, "?")
    vc = vote_counts.get(vid, 0)
    rt = ratings.get(vid, 0)
    print(f"\n  {title} ({vid}) — {vc} votes, {rt:.2f} avg\n")

    if vid not in data:
        print("  No similarities in this JSON.")
        return

    for i, entry in enumerate(data[vid][:args.limit], 1):
        sid = entry["vndb_id"]
        score = entry["score"]
        stitle = titles.get(sid, "?")
        svc = vote_counts.get(sid, 0)
        srt = ratings.get(sid, 0)
        print(f"  {i:>2}. {score:.4f} | {svc:>5} votes | {srt:.1f} | {sid:>8} | {stitle}")
    print()


if __name__ == "__main__":
    main()
