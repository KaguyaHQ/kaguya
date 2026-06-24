#!/bin/bash
# /home/deploy/kaguya/deploy.sh
# Called by GitHub Actions after image transfer.
# Usage: ./deploy.sh kaguya
set -euo pipefail

APP="${1:-kaguya}"

cd /home/deploy/kaguya

if [ "$APP" = "kaguya" ]; then
    echo "==> Running Ecto migrations..."
    docker compose run --rm kaguya /app/bin/migrate

    echo "==> Restarting kaguya..."
    # --remove-orphans cleans up any services no longer in compose (e.g. legacy
    # kaguya-vn container after the LiveView cutover). Safe no-op once clean.
    docker compose up -d --no-deps --remove-orphans kaguya || {
        echo "==> Single-service restart failed, reconciling all services..."
        docker compose up -d --remove-orphans
    }
else
    echo "Unknown app: $APP (expected: kaguya)" >&2
    exit 1
fi

echo "==> Waiting for containers..."
sleep 10

# Ingress (Caddy) lives in the separate edge project (/home/deploy/edge); this
# script only manages the kaguya app + meilisearch. Routing changes are handled
# by edge-ops, not here.

# Purge Cloudflare edge cache
if [ -f .env ]; then
    CF_ZONE_ID=$(grep -m1 '^CF_ZONE_ID=' .env | cut -d= -f2-)
    CF_API_TOKEN=$(grep -m1 '^CF_API_TOKEN=' .env | cut -d= -f2-)
    if [ -n "${CF_ZONE_ID:-}" ] && [ -n "${CF_API_TOKEN:-}" ]; then
        echo "==> Purging Cloudflare edge cache..."
        curl -sS -X POST \
          "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data '{"prefixes":["kaguya.io/vn/","kaguya.io/character/","kaguya.io/producer/","kaguya.io/series/","kaguya.io/favicon"]}' || true
        echo ""
    fi
fi

docker image prune -f
echo "==> Deploy complete!"
