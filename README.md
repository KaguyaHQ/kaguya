# Kaguya

Phoenix + LiveView application for Kaguya, a visual novel discovery,
tracking, recommendation, and community-editing platform. Kaguya is free.

It owns VN metadata, reviews, shelves, recommendations, VNDB imports,
image processing, search indexing, stats, notifications, and revision
history, and serves the browser surfaces directly via LiveView.

## Stack

- Elixir / Phoenix, served with Bandit
- Phoenix LiveView for browser surfaces
- PostgreSQL via Ecto
- Oban for background jobs and scheduled maintenance
- Cachex for browse/cache hot paths
- Meilisearch for search indexing
- Nx + EXLA for in-process recommendation inference
- ExAws S3 client for Cloudflare R2 uploads
- Auth: passwordless magic-link + Google OAuth (sessions owned by Phoenix)
- Sentry, PromEx, and Axiom-oriented structured logging

## Setup

Install dependencies and prepare the database:

```sh
mix setup
```

`mix setup` also enables local git hooks that enforce formatting on commit/push.
To set hooks on an already-initialized checkout, run:

```sh
sh scripts/setup-git-hooks.sh
```

Copy the example environment file and fill in values:

```sh
cp .env.example .env
```

Start the server:

```sh
mix phx.server
```

The development server uses `PORT` when set, otherwise `4000`.

## Common Commands

```sh
mix test
mix credo
mix format
mix format --check-formatted
mix setup
mix ecto.setup
mix assets.setup
mix assets.build
mix ecto.migrate
mix ecto.reset
```

For debugging Oban jobs inline in development:

```sh
OBAN_INLINE=true mix phx.server
```

## Architecture Map

| Area | Path | Notes |
|---|---|---|
| Web surfaces | `lib/kaguya_web` | Controllers, LiveView pages, components, plugs, policies |
| VNDB sync | `lib/kaguya/sync` | Dump/API import, field mapping, rate limiting, image sync |
| Recommendations | `lib/kaguya/recommendations` | EASE recommendation serving, Nx inference, feedback, pregenerated recs |
| Revisions | `lib/kaguya/revisions.ex` | Edit history, hist snapshots, reverts, system changes |
| VN merges | `lib/kaguya/visual_novels/merge.ex` | Canonicalization and duplicate VN collapse |
| Search | `lib/kaguya/search` | Meilisearch transforms and indexing |
| Stats | `lib/kaguya/stats` | User reading stats and scheduled refreshes |
| Uploads/images | `lib/kaguya/uploads`, `lib/kaguya/sync/dump_sync/images` | Variant generation and R2 upload |

## VNDB Dump Sync

The dump sync imports from a local VNDB PostgreSQL dump, then reconciles Kaguya's
normalized tables. It is intentionally ordered because later data depends on
earlier mappings.

```sh
mix kaguya.dump_sync
mix kaguya.dump_sync --overview
mix kaguya.dump_sync --dry-run
mix kaguya.dump_sync --step vns
mix kaguya.dump_sync --step vns,producers,tags
mix kaguya.dump_sync --vndb-db vndb_latest
```

Steps run in this order:

1. `vns` - VN core data, titles, ratings, descriptions
2. `producers` - producer entities and external links
3. `characters` - characters and VN-character junctions
4. `quotes` - VN quotes
5. `tags` - tag definitions, parents, VN-tag associations
6. `relations` - VN-VN relations
7. `releases` - releases, extlinks, VN-producer mappings
8. `removals` - stale entity cleanup
9. `images` - covers, character images, screenshots
10. `post_sync` - tag relevance, browse fields, series, search reindex, cache clears

Sync safety rules are part of the implementation: user-edited content is
protected from content overwrites, banned IDs are skipped, and VNDB IDs merged
into canonical VNs are not recreated on later syncs.

## Recommendations

Training is offline Python under `priv/recommendations`. Production inference
runs inside Elixir through `Kaguya.Recommendations.Nx.Engine` using Nx + EXLA.
The trained EASE matrix is loaded from `KAGUYA_MODEL_DIR` or `priv/data`.

```sh
python3 priv/recommendations/build_training_matrix.py --vote-only
python3 priv/recommendations/build_vn_features.py
python3 priv/recommendations/train.py ease

mix kaguya.generate_recommendations
mix kaguya.generate_recommendations --user vas
mix kaguya.explain_recommendations --user vas
```

The Oban `recommendations` queue is intentionally concurrency `1`: the EASE
matrix is roughly 500 MB and is cached in `persistent_term` during generation.

See `priv/recommendations/README.md` for the training runbook.

## Background Jobs

Oban queues are configured in `config/config.exs`:

- `import` - VNDB/API import jobs
- `images` - image variant generation and upload
- `recommendations` - Nx recommendation generation
- `stats` - user/site stat snapshots
- `maintenance` - pruning, public dumps, backfills

Scheduled jobs include recommendation generation, tag relevance recomputation,
daily stats refreshes, export cleanup, sitemap refresh, and public dump publishing.

## Revision History

Community edits are written through the revision system. Each edit applies to
the live entity and writes a corresponding `_hist` snapshot so moderators can
inspect and revert state.

Supported entity families include visual novels, characters, producers, and
releases. System/VNDB-sync revisions are tracked separately from user-authored
edits so operational imports do not flood activity feeds.

Useful maintenance commands:

```sh
mix kaguya.verify_hist
```

## VN Merge Operations

Duplicate VN rows can be collapsed into a canonical VN through a CLI-only merge
task. The merge preserves user data where possible, records slug redirects,
registers merged VNDB IDs, recomputes aggregates, and updates search/cache
state after the transaction.

Preview first:

```sh
mix kaguya.merge_vns \
  --canonical=summers-gone \
  --sources=summers-gone-season-1,summers-gone-season-2-constellations
```

Execute by adding `--execute`.

## Search

Search documents are indexed into Meilisearch. VN documents include normalized
title prefixes, aliases, original titles, producers, and ranking metadata so
search works across romanized/native titles and common punctuation variants.

The VNDB dump `post_sync` step reindexes search after large imports.

## Environment

Runtime config is loaded from `.env` plus process environment via Dotenvy.
See `.env.example` for the full list with placeholders.

Required (outside test):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | Phoenix secret (generate with `mix phx.gen.secret`) |
| `R2_APPLICATION_KEY_ID` | R2/S3 access key |
| `R2_APPLICATION_KEY` | R2/S3 secret |
| `R2_BUCKET_NAME` | Upload bucket |
| `MEILI_BASE_URL` | Meilisearch endpoint |
| `MEILI_MASTER_KEY` | Meilisearch key |

Optional integrations:

| Variable | Purpose |
|---|---|
| `PHX_HOST`, `PORT` | Public host / HTTP listen port |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_REDIRECT_URI` | Google sign-in |
| `KAGUYA_MODEL_DIR` | Directory containing recommendation model artifacts |
| `FRONTEND_URL` | Frontend callback/origin URL |
| `SSR_SECRET` | SSR rate-limit bypass secret |
| `AXIOM_TOKEN`, `AXIOM_DATASET` | Axiom log drain |
| `SENTRY_DSN`, `SENTRY_BROWSER_DSN` | Error reporting |
| `SES_SMTP_USERNAME`, `SES_SMTP_PASSWORD`, `SES_SMTP_HOST` | SMTP mailer |
| `CF_ZONE_ID`, `CF_API_TOKEN` | Cloudflare cache purge |
| `SKIP_IMAGE_DOWNLOAD` | Skip image download during dump image step |
| `DATABASE_POOL_SIZE`, `DATABASE_TIMEOUT`, `USE_IPV4` | Production DB tuning |

## Testing

```sh
mix test
```

Some integration-style tests/scripts expect a VNDB dump database, real model
artifacts, or external services. Test config provides fake/safe defaults for
Meilisearch, uploads, and OAuth where the unit tests do not need the real service.

## Deployment

The app runs as a standard Phoenix release behind any host that can run the
Docker image. Production runtime config is in `config/runtime.exs`; process
supervision and queues are configured in `lib/kaguya/application.ex` and
`config/config.exs`.

Operationally important constraints:

- Keep recommendation job concurrency low because the EASE matrix is large.
- Image jobs use libvips and can fan out CPU work; tune queue concurrency with
  host capacity in mind.
- VNDB sync is a write-heavy maintenance operation; prefer `--overview` and
  `--dry-run` before large changes.
- Search/cache invalidation happens in sync post-processing and selected
  mutation paths.

## License

Kaguya is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).
See [LICENSE](LICENSE). If you run a modified version as a network service, the
AGPL requires you to offer your users the corresponding source.

Copyright (C) 2026 Vasanth K.
