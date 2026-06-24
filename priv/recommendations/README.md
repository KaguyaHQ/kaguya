# User VN Recommendations Pipeline

End-to-end personalized recommendation system. Two-stage architecture:

- **Stage 1 (retrieval)** — item-item similarity from the trained EASE B matrix. Gives top ~500 candidates per user.
- **Stage 2 (rerank)** — multi-objective MMR: content affinity (writer / producer / series), freshness, popularity damping, diversity. Trims 500 → 100.

Training is offline Python. **Inference runs in Elixir via Nx + EXLA** — see `lib/kaguya/recommendations/nx/engine.ex`. No Python in production.

For the conceptual walkthrough, method explanations, and operations runbook,
read [`../../docs/architecture/recommendations.md`](../../docs/architecture/recommendations.md).
This README is the dev quick-reference for the training side.

## Files (training only)

| File | Purpose |
|---|---|
| `build_training_matrix.py` | VNDB dump → sparse user × VN matrix |
| `build_vn_features.py`     | VNDB dump → per-VN content features |
| `train.py`                 | Trains one method → `{method}_B.npy` (single entrypoint) |
| `trainers.py`              | Shared training fns + tuning variants |
| `eval_harness.py`          | Holdout eval — R@K / NDCG@K / coverage |

Inference (`scoring.py`, `user_recommendations.py`) was removed after the
Nx cutover — `Kaguya.Recommendations.Nx.Engine` is the single source of
truth for serving.

## One-time training

```bash
# Requires:
#   - vndb_latest PostgreSQL database (from dl.vndb.org/dump/)
#   - python3 deps:
#       pip3 install numpy scipy psycopg2-binary implicit gensim \
#                    lightfm scikit-surprise pandas
#   - system python3 works on macOS / most Linux distros

python3 priv/recommendations/build_training_matrix.py --vote-only   # ~2s
python3 priv/recommendations/build_vn_features.py                   # ~1s

python3 priv/recommendations/train.py ease
# ~20s. Other methods (svd, als, lda, pmi, lightfm, surprise_svd) still
# work as bake-off entries — call `train.py all` to train all of them —
# but only EASE ships in production (see docs/architecture/recommendations.md).
```

Outputs:

| File | Size | What |
|---|---|---|
| `priv/data/ease_training.npz`        | ~4 MB   | sparse user × VN training matrix |
| `priv/data/ease_training_meta.json`  | ~830 KB | user/VN index maps |
| `priv/data/{method}_B.npy`           | ~485 MB | dense item-item B matrix |
| `priv/data/{method}_B_meta.json`     | ~30 KB  | per-method config + index |
| `priv/data/vn_features.json`         | ~1.3 MB | producer / writer / series / year |

Retrain whenever the VNDB dump refreshes meaningfully (monthly is reasonable).
Commit the new artifacts so the Docker image picks them up on next deploy.

## Generating per-user recs

```bash
mix kaguya.generate_recommendations              # all eligible users
mix kaguya.generate_recommendations --user vas   # one user
mix kaguya.explain_recommendations --user vas    # admin inspector
```

The Oban worker (`Kaguya.Recommendations.GenerateWorker`) exports CSVs of
prefs / masks / likes, hands them to the Nx engine per user, and upserts
the result into `user_vn_recommendations`.

A weekly cron entry in `config/config.exs` runs the worker on Monday 04:20 UTC.

## Evaluation

```bash
# Hold out 10% of each user's positives, retrain every method on the 90%,
# report R@K / NDCG@K / Hit@K / coverage side-by-side.
python3 priv/recommendations/eval_harness.py --k 20

# Restrict to specific methods or tuning variants
python3 priv/recommendations/eval_harness.py --methods ease,als,svd_k64,svd_sigma2
```

Tuning variants live in `trainers.TRAINERS` — append entries there to expose
new configs to the harness without code duplication.

## Tuned defaults (locked 2026-04-14)

| Method | Config | R@20 (holdout) |
|---|---|---|
| EASE | `λ=500` | **0.375** |
| SVD | `factors=128, weight=sigma` | 0.329 |
| ALS | `factors=64, iterations=20, alpha=1.0` | 0.307 |
| LDA | `num_topics=128, threshold=7.0` | 0.140 |
| PMI | `percentile=70` | 0.055 (high coverage) |

Stage-2 reranker weights (hardcoded in `engine.ex` `@default_weights`):
`ease=1.0, content=0.35, series=0.25, freshness=0.10, pop_damp=0.05, diversity=0.30`

## Production deployment

- Ship `priv/data/ease_B.npy` + `ease_B_meta.json` + `vn_features.json`
  alongside the app, or pull from object storage on first run.
- Keep the `recommendations` Oban queue at concurrency **1** — the B matrix
  lives in `persistent_term` at ~485 MB; double-loading would OOM the 4 GB box.
- The `model_version` column in `user_vn_recommendations` lets us audit
  which training+inference config produced each row (e.g. `ease-nx-2026-04-20`).
