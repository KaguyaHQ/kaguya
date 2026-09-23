"""Shared credentials for the local snapshot database and development server."""
import os
from pathlib import Path


def local_password():
    path = Path.home() / '.config/kaguya/local-db-password'
    password = path.read_text().rstrip('\r\n') if path.exists() else 'postgres'
    override = os.environ.get('KAGUYA_LOCAL_DB_PASSWORD')
    if override is not None and override != password:
        raise RuntimeError(f'Save the local database password in {path}; both the service and refresh must use it.')
    if not password:
        raise RuntimeError(f'Empty local database password in {path}')
    return password
