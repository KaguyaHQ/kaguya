#!/usr/bin/env bash
# Rollback kaguya to a previous deploy by commit SHA.
#
# Usage:
#   ./scripts/rollback.sh              # list recent image tags
#   ./scripts/rollback.sh <commit-sha> # rollback to that version
set -euo pipefail

HETZNER_HOST="${HETZNER_HOST:?set HETZNER_HOST to your deploy host, e.g. export HETZNER_HOST=1.2.3.4}"
IMAGE="ghcr.io/kaguyahq/kaguya"

if [ $# -eq 0 ]; then
  echo "Recent image tags on GHCR:"
  echo ""
  gh api orgs/kaguyahq/packages/container/kaguya/versions \
    --jq '.[] | "\(.metadata.container.tags | join(", "))\t\(.updated_at)"' \
    | head -15
  echo ""
  echo "Usage: ./scripts/rollback.sh <commit-sha>"
  exit 0
fi

SHA="$1"

echo "==> Rolling back kaguya to ${SHA}..."
ssh "deploy@${HETZNER_HOST}" bash -s <<EOF
  set -euo pipefail
  cd /home/deploy/kaguya
  docker pull ${IMAGE}:${SHA}
  docker tag ${IMAGE}:${SHA} ${IMAGE}:latest
  docker compose up -d --no-deps kaguya
  echo "==> Rollback complete. Running container:"
  docker compose ps kaguya
EOF
