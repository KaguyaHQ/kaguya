#!/usr/bin/env bash
set -euo pipefail

umask 077

deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backup_env="$deploy_dir/.backup.env"
restic_image="restic/restic:0.18.1"

if [[ ! -f "$backup_env" ]]; then
  echo "missing backup environment: $backup_env" >&2
  exit 1
fi

cd "$deploy_dir"

restic() {
  docker run --rm --env-file "$backup_env" "$restic_image" "$@"
}

if ! restic cat config >/dev/null 2>&1; then
  restic init
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

docker compose exec -T postgres \
  sh -lc 'pg_dump -U "$POSTGRES_USER" -d kaguya --format=custom --no-owner --no-acl' \
  | docker run --rm -i --env-file "$backup_env" "$restic_image" \
      backup --host kaguya-prod --stdin --stdin-filename "kaguya-$timestamp.dump" --tag postgres

restic forget \
  --host kaguya-prod \
  --tag postgres \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune
