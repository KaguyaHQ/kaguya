#!/usr/bin/env bash
# Deploy to Hetzner via GitHub Actions workflow.
# Usage: ./scripts/deploy.sh         (deploys kaguya)
# Requires: gh CLI (brew install gh)
set -euo pipefail

REPO="KaguyaHQ/kaguya"
WORKFLOW="deploy.yml"
HEAD_SHA="$(git rev-parse HEAD)"

echo "==> Triggering deploy workflow..."
gh workflow run "$WORKFLOW" --repo "$REPO"

echo "==> Waiting for workflow run..."
RUN_ID=""

for _ in {1..20}; do
  RUN_ID="$(
    gh run list \
      --repo "$REPO" \
      --workflow "$WORKFLOW" \
      --json databaseId,headSha,createdAt \
      --jq "map(select(.headSha == \"$HEAD_SHA\")) | sort_by(.createdAt) | reverse | .[0].databaseId // \"\""
  )"

  if [[ -n "$RUN_ID" ]]; then
    break
  fi

  sleep 3
done

if [[ -z "$RUN_ID" ]]; then
  echo "Could not find deploy workflow run for $HEAD_SHA" >&2
  exit 1
fi

echo "==> Watching run $RUN_ID..."
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
