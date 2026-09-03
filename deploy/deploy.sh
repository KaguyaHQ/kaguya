#!/bin/bash
# /home/deploy/kaguya/deploy.sh
# Called by GitHub Actions after image transfer.
# Usage: ./deploy.sh kaguya
set -euo pipefail

APP="${1:-kaguya}"

cd /home/deploy/kaguya

if [ "$APP" = "kaguya" ]; then
    CURRENT_CONTAINER="$(docker compose ps -q kaguya || true)"
    PREVIOUS_IMAGE=""
    if [ -n "$CURRENT_CONTAINER" ]; then
        PREVIOUS_IMAGE="$(docker inspect --format '{{.Image}}' "$CURRENT_CONTAINER")"
    fi

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

echo "==> Waiting for kaguya health check..."
HEALTHY=false
for attempt in $(seq 1 24); do
    if docker compose exec -T kaguya sh -c \
        'curl -fsS http://127.0.0.1:8080/health | grep -q healthy'; then
        HEALTHY=true
        break
    fi

    sleep 5
done

if [ "$HEALTHY" != "true" ]; then
    echo "==> New kaguya container failed its health check" >&2
    docker compose ps kaguya >&2
    docker compose logs --tail=100 kaguya >&2

    if [ -n "$PREVIOUS_IMAGE" ] && docker image inspect "$PREVIOUS_IMAGE" >/dev/null 2>&1; then
        echo "==> Rolling back to previous image $PREVIOUS_IMAGE..." >&2
        docker tag "$PREVIOUS_IMAGE" ghcr.io/kaguyahq/kaguya:latest
        docker compose up -d --no-deps --force-recreate kaguya

        for attempt in $(seq 1 24); do
            if docker compose exec -T kaguya sh -c \
                'curl -fsS http://127.0.0.1:8080/health | grep -q healthy'; then
                echo "==> Rollback healthy" >&2
                exit 1
            fi

            sleep 5
        done

        echo "==> Rollback also failed its health check" >&2
        docker compose logs --tail=100 kaguya >&2
    fi

    exit 1
fi

echo "==> Kaguya is healthy"

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
