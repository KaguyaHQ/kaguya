# EASE VN Similarity Pipeline

Computes item-item collaborative filtering similarities using EASE (Embarrassingly Shallow Autoencoders, Steck 2019). Reads votes from a local `vndb_latest` PostgreSQL database, outputs JSON, which gets imported into Kaguya's `vn_similarities` table.

## Scripts

- `ease_similarity.py` — Main computation. Outputs `priv/data/ease_similarities.json`
- `query_json.py` — Fast query tool for testing JSON output without DB import
- `query_similar.exs` — Query similarities from the Kaguya dev DB (post-import)

## Production Parameters

```
--min-votes 15          # VNs with <15 votes excluded from Gram matrix
--min-user-votes 5      # Users with <5 votes excluded
--lambda 500            # Regularization
--pop-alpha 0           # Popularity discount OFF
--min-display-votes 100 # Only VNs with 100+ votes appear in output JSON
--min-score 0.01        # Floor for inclusion
--max-per-vn 50         # Cap similar VNs per source
```

With these params: 11,191 VNs in the matrix, 2,575 VNs in output, ~85k similarity pairs, ~45s computation.

## Why These Parameters

### min-votes=15 and min-display-votes=100 (two separate knobs)

`--min-votes` controls what enters the Gram matrix for computation. `--min-display-votes` controls what appears in the output JSON and database. They serve different purposes.

Low min-votes (15) keeps niche VNs in the matrix even though they never appear in output. This matters because niche genre clusters (western 3D, BL mystery, extreme/dark) have members concentrated in the 15-100 vote range. Including them in the matrix strengthens within-cluster signal during inversion.

**Tested across mv=10, 15, 25, 50, 100 (all with mdv=100):**

For mainstream JP VNs (CLANNAD, Sengoku Rance, White Album 2), matrix size doesn't matter — top 7 are identical across all configs. The Rance franchise, Key VNs, and romance/drama clusters are well-defined regardless.

For niche/western clusters, lower min-votes preserves legitimate neighbors in positions 5-8:

**Eternum** (western 3D cluster):
- mv10-25: Artemis (#7), Desert Stalker (#8-9), Summertime Saga (#10) — all genuine western 3D matches
- mv50: Artemis drops to borderline, Desert Stalker and Summertime Saga gone
- mv100: Artemis (#6 but weaker), replaced by unrelated JP titles (Koiiro Soramoyou, Astraythem)

**Pale Carnations** (same cluster):
- mv10-25: Leap of Faith at #6 (0.025+), Acting Lessons at #7
- mv50: Leap of Faith drops to #7 (0.018)
- mv100: Leap of Faith gone entirely, replaced by Seeds of Chaos, MIST

**Ooe** (BL murder mystery — the decisive test case):
- mv10-15: Slow Damage at #9 — dark psychological BL, excellent match for a Showa-era BL mystery
- mv25: Slow Damage gone, replaced by Misericorde (mystery but not BL)
- mv50-100: Both Slow Damage and quality BL titles drop off, replaced by UsoNatsu (summer romance, no connection)

mv10 and mv15 are functionally identical across every VN tested. mv15 chosen over mv10 for a marginally safer data quality floor with no measurable quality loss.

**Important caveat:** Positions 8-10 have noise in ALL configurations. Persona 4 Arena Ultimax appears for Ooe regardless of min-votes. Men at Work! 2 (JP charage) appears for Pale Carnations at every threshold. Lower min-votes preserves more legitimate entries in borderline positions 6-8, but no CF configuration produces a clean tail. That's where the voting system comes in.

**When comparing configs, always apply the same display filter to all.** Without this, you're comparing filtering differences, not computation differences. This was a mistake we made early on that led to wrong conclusions about matrix size.

### min-user-votes=5

Higher values (10, 15, 20) concentrate on power users who play across all genres, increasing cross-cluster contamination. Tested on CLANNAD: Steins;Gate climbs from #13 (mu=5) to #6 (mu=20) — power users rate both Key VNs and sci-fi, so the algorithm sees a false connection. mu=5 keeps clusters clean.

### pop-alpha=0 (popularity discount OFF)

Popularity discount (alpha > 0) divides each column of B by vote_count^alpha, penalizing popular targets. Tested alpha=0.15, 0.25, 0.35. Problem: it penalizes VNs whose genuine neighbors happen to be popular. For Saya no Uta, Kara no Shojo drops from #2 to #14 at alpha=0.15 — that's collateral damage, not a quality improvement. The min-votes threshold already handles popularity noise naturally.

### min-display-votes=100

Filter applied in Python before writing JSON, NOT at query time in Elixir. This avoids importing thousands of similarity pairs into the database that would never be displayed. Every row in the DB is displayable.

## Tested VNs (final params: mv=15, mu=5, alpha=0, mdv=100)

- **CLANNAD**: Kanon, Little Busters!, AIR, Rewrite — pure Key cluster, no Steins;Gate
- **Saya no Uta**: Kikokugai, Kara no Shojo, Totono — dark/psychological
- **Eternum**: Once in a Lifetime, Summer's Gone, Pale Carnations, Being a DIK — western 3D
- **Hentai Prison**: NUKITASHI 2 & 1 — comedy/nukige
- **White Album 2**: Mini After Story, Parfait, MUSICUS! — romance/drama
- **Maggot Baits**: Restless Sheep, DeadΩAegis, Eternal Torment — extreme/dark
- **Fata Morgana**: Requiem for Innocence (0.75), then story-heavy titles
- **Sengoku Rance**: Rance VI, Daibanchou, Kichikuou Rance — Alice Soft strategy
- **Amakano 2+**: Entire franchise fills top slots — series cluster
- **Ooe**: UuultraC (same dev), Shingakkou, Hashihime — BL mystery/dark
- **Pale Carnations**: Desert Stalker, Ripples, Eternum, Being a DIK — western 3D

## Known Limitations

- **Tail noise (positions 8+)**: Scores are bunched within 0.01 at these positions. Ordering is essentially random and unrelated titles appear in every configuration. The voting system handles this — users can downvote bad matches.
- **Cross-cluster bleed for popular VNs**: VNs with 5,000+ votes (euphoria, Fate/Stay Night) show weak similarity to many things because so many users rated them. This is inherent to CF and can't be fully solved by parameter tuning.
- **CF captures "same audience" not "same content"**: Snow Daze appears for Maggot Baits because the same users rate both, despite completely different content. Tag-based or staff-based similarity would complement CF for content-level matching.
- **No content signal**: EASE only uses vote patterns. Two VNs by the same writer with different audiences won't be connected. Hybrid approaches (CF + tags + staff) would improve coverage.

## Running

```bash
# Setup (one-time)
python3 -m venv priv/repo/scripts/similarities/.venv
source priv/repo/scripts/similarities/.venv/bin/activate
pip install numpy scipy psycopg2-binary

# Requires vndb_latest database (from vndb-db-*.tar.zst dump)
# Download from https://dl.vndb.org/dump/ — get the full dump, not just votes
# Extract and import:
#   tar --zstd -xf vndb-db-*.tar.zst -C /tmp/vndb-dump
#   createdb -U postgres vndb_latest
#   psql -U postgres vndb_latest -f /tmp/vndb-dump/import.sql

# Compute (production params)
source priv/repo/scripts/similarities/.venv/bin/activate
python3 priv/repo/scripts/similarities/ease_similarity.py \
  --min-votes 15 --min-user-votes 5 --pop-alpha 0 --min-display-votes 100

# Query JSON directly (fast iteration, no DB import needed)
python3 priv/repo/scripts/similarities/query_json.py "CLANNAD"
python3 priv/repo/scripts/similarities/query_json.py v2002
python3 priv/repo/scripts/similarities/query_json.py --file priv/data/other.json "Fate"

# Import into Kaguya dev DB
# IMPORTANT: truncate vn_similarities first if reimporting with new params
#   psql -U postgres kaguya_dev2 -c "TRUNCATE vn_similarities CASCADE"
mix kaguya.import_ease_similarities

# Query from Kaguya DB (both directions via union)
mix run priv/repo/scripts/similarities/query_similar.exs "CLANNAD"
mix run priv/repo/scripts/similarities/query_similar.exs v2002
mix run priv/repo/scripts/similarities/query_similar.exs --slug henpri-hentai-prison
```

## Architecture Notes

- EASE is closed-form: B = P / (-diag(P)) where P = (X^T X + lambda I)^{-1}
- Mean-centering per user normalizes for generous/harsh raters
- Similarity table has constraint `visual_novel_id < similar_vn_id` (symmetric storage)
- Import takes max(A->B, B->A) score when normalizing directional pairs
- Import uses `on_conflict: :nothing` — truncate table before reimporting with new params
- Community voting (upvotes/downvotes) sorts by net_votes DESC, EASE score as tiebreaker
- Display shows 5 per row on VN pages, with optional "add recommendation" button

## Parameter Tuning Guide

If you need to re-tune, here's what we tested and what to look for:

1. **Use `query_json.py` for fast iteration** — no DB import needed, reads JSON directly
2. **Always compare with the same display filter applied** — otherwise you're measuring filtering, not computation
3. **Test across genre clusters**: mainstream JP (CLANNAD), niche JP (Maggot Baits), western 3D (Eternum, Pale Carnations), BL (Ooe), series (Amakano)
4. **Top 5-7 are stable** — if those change, something fundamental shifted. Focus evaluation on positions 6-10 where configs actually diverge.
5. **Don't chase tail quality** — positions 8+ are inherently noisy in CF. The voting system exists for this reason.
