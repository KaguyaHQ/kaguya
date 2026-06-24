# Kaguya Scripts

## Directory Structure

```
scripts/
├── vndb/           # VNDB account blacklist sync (Kana API push)
│                  (entity imports + image processing are in `mix kaguya.dump_sync`)
├── similarities/   # VN-to-VN EASE similarity pipeline → vn_similarities
│                  (feeds `mix kaguya.import_ease_similarities`; distinct from
│                  the user-recs training stack in `priv/recommendations/`)
├── images/         # Cross-env image-mapping import (prod replay of local R2 UUIDs)
├── maintenance/    # Operational scripts (delete users, merge tags, rebuild/recompute derived data)
├── analytics/      # Ad-hoc reporting queries
└── moderation/     # Moderation review data
```

## Running Scripts

```bash
MIX_ENV=dev mix run priv/repo/scripts/<dir>/script_name.exs
MIX_ENV=dev mix run --no-start priv/repo/scripts/<dir>/script_name.exs  # no app boot

# Mix tasks (reusable operations)
mix kaguya.dump_sync
mix kaguya.backfill_vn_stats
```

## Conventions

- **`--dry-run`** supported by most backfill scripts
- **Mix tasks** (`lib/mix/tasks/kaguya.*.ex`) for repeatable operations; `.exs` scripts for ad-hoc work
- Done with a one-off script? Decide on two axes — *still useful?* and *costly to reconstruct?*
  - **Recurring / reusable** → keep it in its dir (e.g. `maintenance/`)
  - **Done one-off** → delete it. git history is the backup, and if the same
    logic now lives in `lib/` (e.g. `mix kaguya.dump_sync`) there's nothing to keep.

  "Already ran" alone is not a reason to keep a file. Don't hoard a strictly-
  worse duplicate of code that lives and is maintained in `lib/`.
