#!/usr/bin/env python3
"""Replace the disposable WSL Kaguya database with a production snapshot."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dev_config import local_password

STATE = Path.home() / '.local/state/kaguya-refresh'
DATABASE = 'kaguya_dev2'
SERVICE = 'kaguya-dev.service'
# Explicit connection arguments and a clean libpq environment keep this local.
ENV = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
CONNECTION = ['-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-w']


def run(args, **kwargs):
    return subprocess.run(args, check=True, env=ENV, **kwargs)


def sql(query, database='postgres'):
    return run(['psql', '-X', *CONNECTION, '-d', database, '-At', '-v',
                'ON_ERROR_STOP=1', '-c', query], capture_output=True, text=True).stdout.strip()


@contextlib.contextmanager
def step(label):
    start = time.monotonic()
    print(f'\n{label}...', flush=True)
    yield
    print(f'{label}: done in {time.monotonic() - start:.1f}s', flush=True)


def archive_counts(archive):
    """Count COPY records from the exact snapshot, not from a later live query."""
    counts = {}
    table = None
    process = subprocess.Popen(['pg_restore', '--data-only', '-f', '-', str(archive)],
                               stdout=subprocess.PIPE, env=ENV)
    try:
        for line in process.stdout:
            if table is not None:
                if line.rstrip(b'\r\n') == b'\\.':
                    table = None
                else:
                    counts[table] += 1
            elif line.startswith(b'COPY '):
                table = line.split(b' (', 1)[0][5:].decode()
                counts[table] = 0
        if process.wait() != 0:
            raise RuntimeError('Archive validation failed; local database was not replaced.')
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
            process.wait()
    if not counts or table is not None or 'public.schema_migrations' not in counts:
        raise RuntimeError('Incomplete or unexpected Kaguya archive.')
    return counts


def download(args, target):
    with target.open('wb') as output:
        process = subprocess.Popen(args, stdout=output, env=ENV)
        try:
            while True:
                try:
                    status = process.wait(timeout=15)
                    if status:
                        raise subprocess.CalledProcessError(status, args)
                    break
                except subprocess.TimeoutExpired:
                    print(f'  Received {target.stat().st_size / 1024**2:.1f} MiB', flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait()


def owns_http_port(pid, port=4001):
    """Require the service process itself to own the IPv4 loopback listener."""
    try:
        sockets = set()
        for entry in Path(f'/proc/{pid}/fd').iterdir():
            try:
                sockets.add(entry.readlink().name)
            except FileNotFoundError:
                pass
        for line in Path('/proc/net/tcp').read_text().splitlines()[1:]:
            fields = line.split()
            if (fields[1] == f'0100007F:{port:04X}' and fields[3] == '0A'
                    and f'socket:[{fields[9]}]' in sockets):
                return True
    except (OSError, ValueError):
        return False
    return False


def service_ready():
    properties = run(['systemctl', '--user', 'show', SERVICE,
                      '-p', 'ActiveState', '-p', 'MainPID'],
                     capture_output=True, text=True).stdout
    state = dict(line.split('=', 1) for line in properties.splitlines() if '=' in line)
    pid = state.get('MainPID', '0')
    if state.get('ActiveState') != 'active' or not pid.isdigit() or not owns_http_port(pid):
        return False
    try:
        try:
            response = urllib.request.urlopen('http://127.0.0.1:4001/health', timeout=2)
        except urllib.error.HTTPError as error:
            if error.code != 503:
                raise
            response = error
        with response:
            result = json.load(response)
            return isinstance(result, dict) and result.get('db') == 'ok'
    except (OSError, ValueError):
        return False


def refresh_database(args):
    archive = STATE / 'production.dump'
    for command in ['psql', 'pg_restore', 'systemctl']:
        if not shutil.which(command):
            raise RuntimeError(f'Missing required tool: {command}')
    if run(['systemctl', '--user', 'show', SERVICE, '-p', 'LoadState', '--value'],
           capture_output=True, text=True).stdout.strip() != 'loaded':
        raise RuntimeError('Install the kaguya-dev user service first; see scripts/LOCAL_DEV.md.')
    sql('SELECT 1')
    started = time.monotonic()
    print(f'Target: local PostgreSQL 127.0.0.1:5432/{DATABASE} (will be replaced)', flush=True)
    if not args.reuse_dump:
        ssh = shutil.which(os.environ.get('KAGUYA_SSH', 'ssh'))
        if not ssh:
            raise RuntimeError('ssh is required.')
        partial = STATE / 'production.dump.part'
        with step('Dump and download production'):
            download([ssh, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
                      '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3', 'kaguya-prod',
                      'docker exec kaguya-postgres-1 sh -c '
                      "'PGOPTIONS=\"-c default_transaction_read_only=on\" pg_dump "
                      '-U "$POSTGRES_USER" -d kaguya -Fc --no-owner --no-acl' + "'"], partial)
            print(f'Downloaded {partial.stat().st_size / 1024**2:.1f} MiB', flush=True)
        with step('Validate downloaded archive'):
            expected = archive_counts(partial)
            partial.replace(archive)
    else:
        with step('Validate saved archive'):
            expected = archive_counts(archive)
    with archive.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    print(f'Snapshot: {len(expected)} tables, {sum(expected.values()):,} rows', flush=True)
    # Nothing destructive happens before the complete archive has been decoded.
    with step('Stop local Kaguya'):
        run(['systemctl', '--user', 'stop', SERVICE])
    with step('Replace local database'):
        sql(f'DROP DATABASE IF EXISTS {DATABASE} WITH (FORCE)')
        sql(f'CREATE DATABASE {DATABASE} TEMPLATE template0')
        log = STATE / 'restore.log'
        with log.open('w') as output:
            run(['pg_restore', *CONNECTION, '-d', DATABASE, '--no-owner', '--no-acl',
                 '--exit-on-error', '--single-transaction', '--verbose', str(archive)], stdout=output, stderr=output)
    with step('Verify every table'):
        queries = ["SELECT '" + table.replace("'", "''") + f"' AS name, count(*) AS n FROM {table}"
                   for table in expected]
        actual = json.loads(sql('SELECT json_object_agg(name, n) FROM (' +
                                ' UNION ALL '.join(queries) + ') counts', DATABASE))
        if actual != expected:
            raise RuntimeError('Restored row counts differ from the snapshot; Kaguya remains stopped.')
        if sql('SELECT count(*) FROM pg_index WHERE NOT indisvalid', DATABASE) != '0':
            raise RuntimeError('Restore has invalid indexes; Kaguya remains stopped.')
        (STATE / 'verification.json').write_text(json.dumps({
            'sha256': digest, 'database': DATABASE, 'counts': actual,
            'verified_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}, indent=2))
    with step('Update query statistics'):
        sql('ANALYZE', DATABASE)
    with step('Start local Kaguya'):
        run(['systemctl', '--user', 'start', SERVICE])
        for _ in range(60):
            if service_ready():
                break
            time.sleep(1)
        else:
            raise RuntimeError('Database verified, but app did not become healthy. Check journalctl --user -u kaguya-dev.')
    print(f'\nReady: http://localhost:4001 — total {time.monotonic() - started:.1f}s', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reuse-dump', action='store_true', help='restore the last verified download')
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        raise RuntimeError('Python 3.11 or newer is required.')
    ENV['PGPASSWORD'] = local_password()
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'refresh.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        refresh_database(args)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f'\nRefresh failed: {error}\nLogs/dump: {STATE}. Retry with --reuse-dump after fixing the error.', file=sys.stderr)
        sys.exit(1)
