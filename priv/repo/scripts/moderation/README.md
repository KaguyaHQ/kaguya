# Nukige classifier reconstruction prototype

The original `tag_classification.tsv` was absent from the public repository's
history. This prototype reconstructed a mapping from the supplied VNDB taxonomy
before the original was subsequently recovered from the private pre-AGPL archive
(`166e830a^`, before the June 22 moderation-directory removal). The archived file
and its review notes remain outside this public repository.

The TSV in this directory is still the reconstructed prototype, not the recovered
original. It does not recover the author's individual tag choices, write categories
to Kaguya, or tune thresholds to match existing labels. Compare against the
recovered mapping before adopting or extending the prototype.

## Reproduce

Use a restored, unchanged VNDB source database. Set normal PostgreSQL connection
variables (`PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD` or `.pgpass`). The script
enforces read-only PostgreSQL sessions and needs only Python 3 and `psql`.

```bash
python3 priv/repo/scripts/moderation/reproduce_tag_classification.py \
  --source-db vndb_20261011 \
  --dump-timestamp '2026-10-11 08:00:34+00' \
  --output-dir /tmp/kaguya-classifier
```

Optionally pass `--baseline-json /path/to/baseline.json` to compare against a
frozen catalog snapshot. Its format is a JSON array of
`[vndb_id, slug, title_category]` rows. For example, export one before a sync:

```bash
psql -X -w -d YOUR_CATALOG_DB -Atc \
  'SELECT json_agg(json_build_array(vndb_id, slug, title_category) ORDER BY vndb_id)
   FROM visual_novels WHERE vndb_id IS NOT NULL' > /tmp/baseline.json
```

The mapping and classification outputs are deterministic for the same source
data and rules. The comparison additionally needs the same baseline. The report
records the dump timestamp, rule version, generator hash, input hashes, and
baseline hash. Output is sorted and contains no execution timestamps.

## Reconstructed rules

- VNDB's `ero` tag category supplies erotic signals.
- `cont` tags under Theme (`g1`), following primary parent edges, supply narrative
  signals. Other tags are neutral. This broad mapping is a hypothesis for review.
- Each tag contributes its net, non-ignored vote total, clamped to zero. Classify
  when total weight is at least 20 and the erotic share is at least 75%.
- The explicit Nukige tag (`g214`) is a comparison signal, not an extra rule.
- Report the original cover and bestiality heuristics separately, plus their union
  with the weighted classifier. Their inclusion does not establish their quality.
- Equal positive voter counts in the bestiality rule are ordered by numeric tag
  ID. The original query had no tie-breaker and could return different results.

Using integer vote sums also avoids the old `COUNT * AVG` rounding error at exact
thresholds. Fixed examples cover both that boundary and tied ranks.

## Artifacts and review

- `tag_classification.tsv`: all tags with their inferred role and rule reason;
  compatible with the existing dump classifier's loader. The checked-in copy was
  generated from the October 11, 2026 dump (3,014 tags).
- `classification.csv`: scores, separate rule matches, explicit-tag evidence,
  strongest tags, and comparison labels for every source title.
- `disagreements.csv`: differing results for existing `vn` and `nukige` titles.
- `summary.json`: totals, provenance, and hashes. Existing labels are a reference,
  not ground truth; agreement is not an accuracy estimate. Missing source IDs are
  reported separately rather than counted as classifier failures.
- `input-*.csv`: frozen inputs needed to inspect the run.

The catalog sync remains separate: it preserves existing categories and does not
automatically invoke this classifier. Reports include banned/non-importable source
titles; filter those before treating results as import candidates. Review low-vote,
explicit-tag disagreements and legacy-only matches before publishing new titles.

```bash
python3 -m unittest discover -s priv/repo/scripts/moderation -p '*_test.py'
mix test test/kaguya/sync/nukige_classifier_test.exs
```
