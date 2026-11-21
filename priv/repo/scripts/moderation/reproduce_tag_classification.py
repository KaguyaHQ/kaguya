"""Read-only reconstruction of the missing nukige tag mapping.

This is a prototype, not the recovered original mapping or an import command.
Uses Python's standard library and psql; connection settings come from PG* env.
"""

import argparse
import csv
import hashlib
import io
import json
import os
from collections import Counter, defaultdict
from pathlib import Path
import subprocess


RULES = {
    "version": "taxonomy-prototype-1",
    "narrative_root": "g1",
    "parent_edges": "main only",
    "erotic": "VNDB category ero",
    "narrative": "VNDB category cont under Theme; all other tags neutral",
    "minimum_weight": 20,
    "erotic_share": "3/4",
    "explicit_nukige_tag": "g214 (comparison only)",
    "legacy_cover_cutoff": 56000,
    "legacy_bestiality_tag": "g183",
    "legacy_rank_ties": "descending positive voter count, then numeric tag ID",
}


def id_key(value):
    return int(value[1:])


def build_mapping(tags, parents):
    by_id = {tag["id"]: tag for tag in tags}
    if by_id.get("g1", {}).get("name") != "Theme":
        raise ValueError("Expected g1 = Theme; inspect the source taxonomy before proceeding")
    children = defaultdict(set)
    for edge in parents:
        if edge["main"]:
            if edge["id"] not in by_id or edge["parent"] not in by_id:
                raise ValueError("Tag hierarchy contains an unknown tag")
            children[edge["parent"]].add(edge["id"])

    theme = set()
    pending = ["g1"]
    while pending:
        tag_id = pending.pop()
        if tag_id not in theme:
            theme.add(tag_id)
            pending.extend(children[tag_id] - theme)

    mapping = {}
    for tag in sorted(tags, key=lambda tag: id_key(tag["id"])):
        if tag["cat"] == "ero":
            role, reason = "ero", "VNDB erotic category"
        elif tag["cat"] == "cont" and tag["id"] in theme:
            role, reason = "narrative", "Non-erotic content under Theme"
        else:
            role, reason = "neutral", "Not an erotic or narrative signal in this prototype"
        mapping[tag["id"]] = {**tag, "classification": role, "reason": reason}
    return mapping


def ratio_matches(erotic, narrative):
    total = erotic + narrative
    return total >= RULES["minimum_weight"] and 4 * erotic >= 3 * total


def analyze(mapping, signals, novels):
    grouped = defaultdict(list)
    for vid, tag, weight, positive_voters, positive_sum in signals:
        grouped[vid].append((tag, int(weight), int(positive_voters), int(positive_sum)))

    results = []
    for novel in novels:
        vid = novel["id"]
        rows = grouped[vid]
        erotic = sum(weight for tag, weight, _, _ in rows if mapping[tag]["classification"] == "ero")
        narrative = sum(weight for tag, weight, _, _ in rows if mapping[tag]["classification"] == "narrative")
        ratio = ratio_matches(erotic, narrative)
        explicit = any(tag == "g214" and weight > 0 for tag, weight, _, _ in rows)
        cover = (
            novel["c_votecount"] == 0 and id_key(vid) < RULES["legacy_cover_cutoff"]
            and (novel["sexual_avg"] or 0) >= 150 and (novel["image_votes"] or 0) >= 3
        )
        ranked = sorted((row for row in rows if row[2] > 0), key=lambda row: (-row[2], id_key(row[0])))
        bestiality = False
        tied_rank = False
        for rank, (tag, _, voters, vote_sum) in enumerate(ranked, start=1):
            if tag == "g183":
                tied_rank = sum(other[2] == voters for other in ranked) > 1
                bestiality = (
                    rank == 1 or (rank <= 3 and vote_sum >= 2 * voters)
                    or (rank <= 5 and 2 * vote_sum >= 5 * voters)
                    or novel["no_description"]
                )
                break
        reasons = [name for name, match in [
            ("erotic_ratio", ratio), ("legacy_explicit_cover", cover),
            ("legacy_bestiality", bestiality)
        ] if match]
        top_tags = sorted(rows, key=lambda row: (-row[1], id_key(row[0])))[:8]
        results.append({
            "id": vid, "title": novel["title"], "erotic_weight": erotic,
            "narrative_weight": narrative, "ratio_match": ratio,
            "explicit_nukige_tag": explicit, "legacy_cover_match": cover,
            "legacy_bestiality_match": bestiality, "bestiality_rank_tied": tied_rank,
            "reconstructed_original_match": bool(reasons), "reasons": ";".join(reasons),
            "top_tags": "; ".join(f"{tag}:{mapping[tag]['name']}={weight}" for tag, weight, _, _ in top_tags),
        })
    return sorted(results, key=lambda row: id_key(row["id"]))


def fetch(database, query, output, name):
    env = {**os.environ, "PGOPTIONS": os.environ.get("PGOPTIONS", "") + " -c default_transaction_read_only=on"}
    result = subprocess.run(
        ["psql", "-X", "-w", "-v", "ON_ERROR_STOP=1", "-d", database,
         "-c", f"COPY ({query}) TO STDOUT WITH CSV"],
        check=True, capture_output=True, env=env,
    )
    (output / name).write_bytes(result.stdout)
    return list(csv.reader(io.StringIO(result.stdout.decode("utf-8"))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-db", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dump-timestamp", required=True)
    parser.add_argument("--baseline-json", type=Path, help="Frozen [vndb_id, slug, category] rows; comparison only")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    tags = [dict(zip(["id", "name", "cat"], row)) for row in fetch(args.source_db,
        'SELECT id,name,cat::text FROM tags ORDER BY id COLLATE "C"', args.output_dir, "input-tags.csv")]
    parents = [{"id": row[0], "parent": row[1], "main": row[2] == "t"} for row in fetch(args.source_db,
        'SELECT id,parent,main FROM tags_parents ORDER BY id COLLATE "C",parent COLLATE "C"',
        args.output_dir, "input-parents.csv")]
    signals = fetch(args.source_db, """
        SELECT vid,tag,GREATEST(SUM(vote),0),COUNT(*) FILTER (WHERE vote>0),
               COALESCE(SUM(vote) FILTER (WHERE vote>0),0)
        FROM tags_vn WHERE NOT ignore GROUP BY vid,tag
        HAVING COUNT(*) FILTER (WHERE vote>0)>0
        ORDER BY vid COLLATE "C",tag COLLATE "C"
    """, args.output_dir, "input-signals.csv")
    novels = []
    for row in fetch(args.source_db, """
        SELECT v.id,COALESCE(t.title,v.id),v.c_votecount,i.c_sexual_avg,i.c_votecount,
               v.description IS NULL OR v.description=''
        FROM vn v LEFT JOIN vn_titles t ON t.id=v.id AND t.lang=v.olang
        LEFT JOIN images i ON i.id=v.c_image ORDER BY v.id COLLATE "C"
    """, args.output_dir, "input-novels.csv"):
        novels.append({"id": row[0], "title": row[1], "c_votecount": int(row[2]),
                       "sexual_avg": int(row[3]) if row[3] else None,
                       "image_votes": int(row[4]) if row[4] else None, "no_description": row[5] == "t"})
    mapping = build_mapping(tags, parents)
    with (args.output_dir / "tag_classification.tsv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        writer.writerow(["tag_id", "name", "category", "classification", "reason"])
        for row in mapping.values():
            name = " ".join(row["name"].split())
            writer.writerow([row["id"], name, row["cat"], row["classification"], row["reason"]])
    results = analyze(mapping, signals, novels)
    baseline = {}
    if args.baseline_json:
        baseline = {vid: category for vid, _slug, category in json.loads(args.baseline_json.read_text()) if vid}
    for row in results:
        row["existing_category"] = baseline.get(row["id"], "")
    fields = list(results[0])
    for name, rows in [
        ("classification.csv", results),
        ("disagreements.csv", [row for row in results if row["existing_category"] in ("vn", "nukige")
                              and row["reconstructed_original_match"] != (row["existing_category"] == "nukige")]),
    ]:
        with (args.output_dir / name).open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
    available_ids = {row["id"] for row in results}
    missing_baseline = set(baseline) - available_ids
    comparable_baseline = {vid: category for vid, category in baseline.items() if vid in available_ids}
    summary = {"rules": RULES, "dump_timestamp": args.dump_timestamp,
               "comparison_note": "Agreement with existing labels is not an accuracy measurement",
               "baseline_titles_missing_from_dump": len(missing_baseline),
               "tags": dict(Counter(row["classification"] for row in mapping.values())), "titles": len(results)}
    for key in ["ratio_match", "explicit_nukige_tag", "reconstructed_original_match", "legacy_cover_match", "legacy_bestiality_match"]:
        ids = {row["id"] for row in results if row[key]}
        known_nukige = {vid for vid, category in comparable_baseline.items() if category == "nukige"}
        summary[key] = {"total": len(ids), "existing_nukige_matched": len(ids & known_nukige),
                        "existing_nukige_missed": len(known_nukige - ids),
                        "existing_vn_flagged": sum(vid in ids and category == "vn" for vid, category in comparable_baseline.items()),
                        "outside_baseline": len(ids - baseline.keys())}
    fingerprint = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    summary["generator_sha256"] = fingerprint(Path(__file__))
    summary["input_sha256"] = {path.name: fingerprint(path) for path in sorted(args.output_dir.glob("input-*.csv"))}
    if args.baseline_json:
        summary["baseline_sha256"] = fingerprint(args.baseline_json)
    summary["mapping_sha256"] = fingerprint(args.output_dir / "tag_classification.tsv")
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
