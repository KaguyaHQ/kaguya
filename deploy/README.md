# Deploying Kaguya

Kaguya ships as a single Docker image (Phoenix LiveView app), with Meilisearch
for search and (optionally) Grafana Alloy for metrics.

There are two ways to run it:

- **`deploy/` (this directory)** is the app stack **without** a bundled reverse
  proxy. Use this when TLS/ingress is handled separately (a standalone Caddy,
  Cloudflare, an existing nginx, etc.). The app + meilisearch join a shared
  external `edge` network that your proxy routes to. This is how kaguya.io runs.
- **`deploy/example/`** is a **self-contained** stack that bundles Caddy with
  automatic HTTPS. Clone, point DNS at the box, `docker compose up`, and you get
  a working TLS site with no separate proxy. Best starting point for self-hosting.

The commands below assume you've set `HETZNER_HOST` to your server's address:

```bash
export HETZNER_HOST=your.server.ip   # or hostname
```

(The name is historical; it can point at any host.)

## What's here

| File                  | Purpose                                                  |
| --------------------- | -------------------------------------------------------- |
| `docker-compose.yml`  | App stack (kaguya, meilisearch, alloy), no proxy         |
| `alloy/config.alloy`  | Grafana Alloy scrape targets + remote write (optional)   |
| `server-setup.sh`     | One-shot bootstrap for a fresh Ubuntu box                |
| `deploy.sh`           | Run on the server by CI after an image push              |
| `example/`            | Self-contained stack (bundles Caddy + auto-HTTPS)        |

## First-time setup

> Self-hosting from scratch with no separate proxy? Use `deploy/example/`
> instead: it bundles Caddy and serves TLS out of the box. The steps below are
> for the proxy-less stack (you bring your own ingress).

1. Provision a Linux box (the app runs comfortably in ~4 GB RAM).
2. Run the bootstrap as root. It creates a `deploy` user, hardens SSH, installs
   Docker, sets up a firewall and swap:
   ```bash
   ssh root@$HETZNER_HOST 'bash -s' < deploy/server-setup.sh
   ```
3. Create the shared ingress network your proxy and these apps both join:
   ```bash
   ssh deploy@$HETZNER_HOST 'docker network create edge'
   ```
4. Copy the config files to the server:
   ```bash
   scp deploy/docker-compose.yml deploy/deploy.sh "deploy@${HETZNER_HOST}:/home/deploy/kaguya/"
   scp -r deploy/alloy "deploy@${HETZNER_HOST}:/home/deploy/kaguya/"
   ```
5. Create `/home/deploy/kaguya/.env` from `.env.example` with real values.
6. Bring it up:
   ```bash
   ssh deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose up -d'
   ```
7. Point your reverse proxy at `kaguya:8080` (app) and `meilisearch:7700`
   (search) over the `edge` network, and have it terminate TLS.

## Deploy

Deploys run through GitHub Actions (`.github/workflows/deploy.yml`): it builds
the image, pushes it to GHCR, syncs the ops files, and restarts the container on
the server. Set `HETZNER_HOST` and `HETZNER_SSH_KEY` as repository secrets so the
workflow can reach your box.

```bash
# Trigger a deploy from your machine (uses the gh CLI)
./scripts/deploy.sh
```

On deploy, the server-side `deploy.sh` runs Ecto migrations and restarts the app
container with the new image. Ingress is not touched (your proxy is separate).

## TLS

This stack does not terminate TLS; your reverse proxy does. For a turnkey setup,
`deploy/example/` ships a Caddy with automatic HTTPS via Let's Encrypt: point
your domain's DNS at the box and Caddy provisions and renews certificates on its
own.

## Day-to-day operations

```bash
# Status
ssh deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose ps'

# Logs
ssh deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose logs -f kaguya'

# Restart a service
ssh deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose restart kaguya'

# Ecto migrations (also run automatically on deploy)
ssh deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose run --rm kaguya /app/bin/migrate'

# IEx console on the running release
ssh -t deploy@$HETZNER_HOST 'cd /home/deploy/kaguya && docker compose exec kaguya /app/bin/kaguya remote'

# Rollback to a previous image (see scripts/rollback.sh)
./scripts/rollback.sh           # list recent deploys
./scripts/rollback.sh <sha>     # roll back to a specific build
```

## Environment variables

See `.env.example` for the full list. Runtime essentials:

| Variable           | Purpose                          |
| ------------------ | -------------------------------- |
| `DATABASE_URL`     | Postgres connection string       |
| `PHX_HOST`         | Public hostname                  |
| `SECRET_KEY_BASE`  | Phoenix secret                   |
| `MEILI_MASTER_KEY` | Meilisearch auth                 |
| `SUPABASE_*`       | Auth (JWKS verification)         |
| `SENTRY_DSN`       | Error tracking (optional)        |

## Monitoring (optional)

`alloy/config.alloy` scrapes Caddy, the Phoenix backend (PromEx metrics at
`/metrics`), and host metrics, and remote-writes to a Prometheus endpoint. It's
entirely optional. Drop the `alloy` service from `docker-compose.yml` if you
don't want it. Configure the remote-write target via the `GRAFANA_CLOUD_*` env
vars.

| Target  | Endpoint              | Metrics                                          |
| ------- | --------------------- | ------------------------------------------------ |
| Caddy   | `caddy:2019`          | HTTP request rate, latency, in-flight            |
| Backend | `kaguya:8080/metrics` | Phoenix HTTP, Ecto queries, BEAM VM, Oban jobs   |
| Host    | node_exporter         | CPU, memory, disk, network, load                 |
