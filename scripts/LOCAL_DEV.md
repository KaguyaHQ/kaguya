# Local production snapshots (Linux / WSL)

This optional maintainer workflow requires SSH access to the production database.
It replaces the entire local `kaguya_dev2` database with a production snapshot.
It is not required for ordinary contributor setup; see the project README.

## Prerequisites

- Python 3.11 or newer, PostgreSQL client tools (`psql`, `pg_restore`), and SSH.
- A compatible local PostgreSQL server on `127.0.0.1:5432`, with a `postgres`
  role allowed to create and drop databases. Use PostgreSQL client tools at least
  as new as the production server.
- The project's Elixir/OTP and Node toolchains, dependencies and development assets
  already installed/built. The launcher uses mise when available, otherwise PATH.
- A working systemd user session. On WSL, run the commands inside the distribution.
- An SSH alias named `kaguya-prod` that can run Docker on the production host.
  The source is database `kaguya` in container `kaguya-postgres-1`.

The default local password is `postgres`. For a different password, save its literal
value in `~/.config/kaguya/local-db-password` (one line, no shell quoting), with
permissions `0600` inside a private directory. Both commands read this file.
A conflicting `KAGUYA_LOCAL_DB_PASSWORD` environment variable is rejected to avoid
restoring with one password and starting the app with another.

## Install local commands

Run these commands from your checkout. The symlinks select that checkout; its path
can be anywhere on the Linux filesystem. Reinstall the symlinks if you move it.

```bash
mkdir -p ~/.local/bin ~/.config/systemd/user
ln -sfn "$PWD/scripts/kaguya-dev" ~/.local/bin/kaguya-dev
ln -sfn "$PWD/scripts/refresh-db.py" ~/.local/bin/kaguya-refresh-db
cp scripts/kaguya-dev.service ~/.config/systemd/user/
systemctl --user daemon-reload
```

Ensure `~/.local/bin` is on PATH. Start the app with either `kaguya-dev` in a terminal
or `systemctl --user start kaguya-dev`. Stop the foreground app before refreshing;
the refresh command manages the user service.

On WSL, keep a WSL terminal open while developing. Refresh does not start hidden
Windows clients, enable login startup, or manage the distribution's lifetime.

## Refresh

```bash
kaguya-refresh-db                # download, validate, replace, verify, start
kaguya-refresh-db --reuse-dump   # use the previously downloaded snapshot
journalctl --user -u kaguya-dev -f
```

SSH uses the Linux `ssh` command by default. To use another executable, set
`KAGUYA_SSH` to its path. For example, maintainers who explicitly want to use their
Windows OpenSSH configuration can set:

```bash
export KAGUYA_SSH=/mnt/c/Windows/System32/OpenSSH/ssh.exe
```

The restore target is fixed to `127.0.0.1:5432/kaguya_dev2`; inherited libpq
connection overrides are ignored. The launcher pins the app to that same database
and to port 4001. Open http://localhost:4001.

Refresh never builds assets, installs tools, runs migrations, or changes production.
It decodes the archive before stopping the service or replacing the local database,
then restores in a transaction and verifies table counts against that same snapshot.
Restore or verification failure leaves the service stopped. A startup failure is
reported separately; inspect its journal before retrying.

The dump, restore log and verification report remain under
`~/.local/state/kaguya-refresh`, with private permissions for newly created files.
These are unsanitized production snapshots; keep them out of Git and shared storage.
`--reuse-dump` uses the last downloaded archive, which may predate a failed download.

The development runner disables Oban jobs, outbound mail, search indexing, and
object-storage writes. Public image reads remain enabled. `/health` reports 503
while Oban is disabled; readiness requires the service process to own the loopback
HTTP listener and its health response to report a working database.
