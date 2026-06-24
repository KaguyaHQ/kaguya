#!/usr/bin/env bash
# Ship a locally-trained B matrix to the Hetzner prod box and drop the
# running app's cached context so the next call reloads the new model.
#
# Re-running is safe. rsync skips files that are already up to date, the
# size-verify is cheap, and persistent_term:erase/1 is a no-op when the
# cache isn't populated.
#
# First-time server setup (NOT handled by this script):
#   1. Create the volume dir:            ssh $host mkdir -p /home/deploy/kaguya/data
#   2. Mount it in docker-compose.yml:   /home/deploy/kaguya/data:/srv/kaguya/data:ro
#   3. Set env on kaguya:                KAGUYA_MODEL_DIR=/srv/kaguya/data
#   4. docker compose up -d kaguya
#
# Overrides via env:
#   KAGUYA_REMOTE_HOST   required, e.g. deploy@1.2.3.4 (or set HETZNER_HOST)
#   KAGUYA_REMOTE_DIR    default: /home/deploy/kaguya/data
#   KAGUYA_CONTAINER     default: kaguya-kaguya-1

set -euo pipefail

REMOTE_HOST="${KAGUYA_REMOTE_HOST:-deploy@${HETZNER_HOST:?set HETZNER_HOST or KAGUYA_REMOTE_HOST}}"
REMOTE_DIR="${KAGUYA_REMOTE_DIR:-/home/deploy/kaguya/data}"
CONTAINER_NAME="${KAGUYA_CONTAINER:-kaguya-kaguya-1}"
DATA_DIR="priv/data"
MIN_NPY_BYTES=$((10 * 1024 * 1024))   # 10 MB; real B matrices are 100s of MB

method="ease"
dry_run=0
reload=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [--method NAME] [--dry-run] [--no-reload]

  --method NAME   Which trained model to ship (default: ease).
  --dry-run       Show what rsync would transfer, skip the hot-reload.
  --no-reload     Transfer the files but leave the in-memory cache alone.
                  Useful when staging a new model before a planned restart.
  -h, --help      Show this message.

Re-runs are safe — unchanged files are skipped and the reload is idempotent.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --method)    method="${2:?--method needs a value}"; shift 2 ;;
        --dry-run)   dry_run=1; shift ;;
        --no-reload) reload=0; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Method name ends up interpolated into an Elixir expression for the
# hot-reload rpc, so keep it strictly alphanumeric.
if ! [[ "$method" =~ ^[a-z0-9_]+$ ]]; then
    echo "error: bad method name '$method' (lowercase alphanumeric + underscore only)" >&2
    exit 2
fi

b_file="${DATA_DIR}/${method}_B.npy"
meta_file="${DATA_DIR}/${method}_B_meta.json"

for f in "$b_file" "$meta_file"; do
    if [ ! -f "$f" ]; then
        echo "error: $f not found." >&2
        echo "       Train first, e.g.:  cd ../recs && python -m scripts.train $method" >&2
        exit 1
    fi
done

b_bytes=$(wc -c < "$b_file")
if [ "$b_bytes" -lt "$MIN_NPY_BYTES" ]; then
    echo "error: $b_file is only $b_bytes bytes — did training actually complete?" >&2
    exit 1
fi

echo "==> local    $b_file ($(du -h "$b_file" | cut -f1))"
echo "==> remote   ${REMOTE_HOST}:${REMOTE_DIR}/"

rsync_flags=(--archive --compress --partial --progress --human-readable)
if [ "$dry_run" -eq 1 ]; then
    rsync_flags+=(--dry-run)
    echo "(dry run)"
fi

# Remote dir should already exist from first-time setup, but mkdir -p is
# cheap insurance that keeps this script usable for a clean machine too.
ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR'"

echo "==> rsync"
rsync "${rsync_flags[@]}" "$b_file" "$meta_file" "${REMOTE_HOST}:${REMOTE_DIR}/"

if [ "$dry_run" -eq 1 ]; then
    exit 0
fi

# rsync doesn't normally produce size-mismatched files, but if an SSH
# connection drops mid-write you can end up with a short .npy that the
# Elixir engine will load and then crash on. One round-trip to verify.
remote_bytes=$(ssh "$REMOTE_HOST" "wc -c < '${REMOTE_DIR}/$(basename "$b_file")'")
# Use arithmetic comparison — `wc -c` pads with whitespace on macOS, which
# breaks string `!=`. Integer comparison sidesteps that.
if [ "$b_bytes" -ne "$remote_bytes" ]; then
    echo "error: size mismatch (local=$b_bytes, remote=$remote_bytes)" >&2
    echo "       Rerun to retry — rsync --partial picked up where it left off." >&2
    exit 1
fi
echo "==> verified $b_bytes bytes"

if [ "$reload" -eq 0 ]; then
    echo "==> skipping hot-reload (--no-reload)"
    exit 0
fi

# Drop the cached context in the running app. Next call to the engine
# reloads from the volume. Safe even if the cache was already empty.
echo "==> hot-reload  ($CONTAINER_NAME)"
ssh "$REMOTE_HOST" bash <<EOF
docker exec $CONTAINER_NAME /app/bin/kaguya rpc \
  ':persistent_term.erase({Kaguya.Recommendations.Nx.Engine, :context, "$method"})'
EOF

echo "==> done"
