import importlib.util
from importlib.machinery import SourceFileLoader
import io
import os
import socket
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('refresh_db', Path(__file__).with_name('refresh-db.py'))
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


class RefreshSafetyTest(unittest.TestCase):
    def archive_process(self, data, status=0):
        process = MagicMock()
        process.stdout = io.BytesIO(data)
        process.wait.return_value = status
        process.poll.return_value = status
        return process

    def test_counts_copy_records_without_interpreting_row_contents(self):
        data = (b'COPY public.schema_migrations (version) FROM stdin;\n1\n\\.\n'
                b'COPY public.notes (body) FROM stdin;\nCOPY is data here\n\\\\.\n\\.\n')
        with patch.object(refresh.subprocess, 'Popen', return_value=self.archive_process(data)):
            self.assertEqual(refresh.archive_counts(Path('dump')), {
                'public.schema_migrations': 1, 'public.notes': 2})

    def test_truncated_copy_rejected(self):
        data = b'COPY public.schema_migrations (version) FROM stdin;\n1\n'
        with patch.object(refresh.subprocess, 'Popen', return_value=self.archive_process(data)):
            with self.assertRaisesRegex(RuntimeError, 'Incomplete'):
                refresh.archive_counts(Path('dump'))

    def test_archive_decoder_failure_rejected_even_after_valid_records(self):
        data = b'COPY public.schema_migrations (version) FROM stdin;\n1\n\\.\n'
        with patch.object(refresh.subprocess, 'Popen', return_value=self.archive_process(data, 1)):
            with self.assertRaisesRegex(RuntimeError, 'validation failed'):
                refresh.archive_counts(Path('dump'))

    def test_bad_saved_dump_never_stops_app_or_replaces_database(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(refresh, 'STATE', Path(directory)), \
             patch.object(refresh.sys, 'argv', ['refresh-db.py', '--reuse-dump']), \
             patch.object(refresh.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(refresh, 'run', return_value=subprocess.CompletedProcess([], 0, 'loaded\n')) as run, \
             patch.object(refresh, 'sql', return_value='1') as sql, \
             patch.object(refresh, 'archive_counts', side_effect=RuntimeError('bad archive')):
            with self.assertRaisesRegex(RuntimeError, 'bad archive'):
                refresh.main()
            sql.assert_called_once_with('SELECT 1')
            self.assertEqual(len(run.call_args_list), 1)
            self.assertIn('show', run.call_args.args[0])

    def test_failed_restore_leaves_app_stopped(self):
        def command(args, **kwargs):
            if args[0] == 'pg_restore':
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0, 'loaded\n')

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(refresh, 'STATE', Path(directory)), \
             patch.object(refresh.sys, 'argv', ['refresh-db.py', '--reuse-dump']), \
             patch.object(refresh.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(refresh, 'run', side_effect=command) as run, \
             patch.object(refresh, 'sql', return_value='1'), \
             patch.object(refresh, 'archive_counts', return_value={'public.schema_migrations': 1}):
            (Path(directory) / 'production.dump').write_bytes(b'fixture')
            with self.assertRaises(subprocess.CalledProcessError):
                refresh.main()
            commands = [call.args[0] for call in run.call_args_list]
            self.assertIn(['systemctl', '--user', 'stop', refresh.SERVICE], commands)
            self.assertNotIn(['systemctl', '--user', 'start', refresh.SERVICE], commands)

    def test_unrelated_http_server_is_not_ready(self):
        result = subprocess.CompletedProcess([], 0, 'ActiveState=active\nMainPID=123\n')
        with patch.object(refresh, 'run', return_value=result), \
             patch.object(refresh, 'owns_http_port', return_value=False), \
             patch.object(refresh.urllib.request, 'urlopen') as request:
            self.assertFalse(refresh.service_ready())
            request.assert_not_called()

    def test_failed_service_is_not_ready(self):
        result = subprocess.CompletedProcess([], 0, 'ActiveState=failed\nMainPID=0\n')
        with patch.object(refresh, 'run', return_value=result), \
             patch.object(refresh, 'owns_http_port') as ownership:
            self.assertFalse(refresh.service_ready())
            ownership.assert_not_called()

    def test_service_owned_degraded_health_with_database_ok_is_ready(self):
        result = subprocess.CompletedProcess([], 0, f'ActiveState=active\nMainPID={os.getpid()}\n')
        response = refresh.urllib.error.HTTPError('http://local', 503, 'degraded', {},
                                                 io.BytesIO(b'{"db":"ok","oban":"fail"}'))
        with patch.object(refresh, 'run', return_value=result), \
             patch.object(refresh, 'owns_http_port', return_value=True), \
             patch.object(refresh.urllib.request, 'urlopen', side_effect=response):
            self.assertTrue(refresh.service_ready())

    def test_listener_ownership_matches_actual_process(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            port = listener.getsockname()[1]
            self.assertTrue(refresh.owns_http_port(os.getpid(), port))
            self.assertFalse(refresh.owns_http_port(0, port))

    def test_shared_password_file_and_conflicting_environment(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch('dev_config.Path.home', return_value=Path(directory)), \
             patch.dict(os.environ, {}, clear=True):
            self.assertEqual(refresh.local_password(), 'postgres')
            path = Path(directory) / '.config/kaguya/local-db-password'
            path.parent.mkdir(parents=True)
            path.write_text('custom password\n')
            self.assertEqual(refresh.local_password(), 'custom password')
            os.environ['KAGUYA_LOCAL_DB_PASSWORD'] = 'different'
            with self.assertRaisesRegex(RuntimeError, 'both the service and refresh'):
                refresh.local_password()

    def test_launcher_pins_checkout_environment_and_shared_credentials(self):
        path = Path(__file__).with_name('kaguya-dev')
        loader = SourceFileLoader('kaguya_dev_launcher', str(path))
        launcher_spec = importlib.util.spec_from_loader(loader.name, loader)
        launcher = importlib.util.module_from_spec(launcher_spec)
        loader.exec_module(launcher)
        with patch.dict(os.environ, {'MIX_ENV': 'prod', 'PORT': '9999'}, clear=True), \
             patch.object(launcher, 'local_password', return_value='shared-secret'), \
             patch.object(launcher.os, 'chdir') as chdir, \
             patch.object(launcher.shutil, 'which', return_value='/usr/bin/mise'), \
             patch.object(launcher.os, 'execvp') as execute:
            launcher.main()
            chdir.assert_called_once_with(path.resolve().parent.parent)
            self.assertEqual(os.environ['KAGUYA_LOCAL_DB_PASSWORD'], 'shared-secret')
            self.assertEqual(os.environ['MIX_ENV'], 'dev')
            self.assertEqual(os.environ['PORT'], '4001')
            self.assertEqual(execute.call_args.args[1], [
                '/usr/bin/mise', 'exec', '--', 'mix', 'run', '--no-start',
                '--no-halt', 'scripts/dev-server.exs'])

    def test_linux_ssh_default_and_explicit_override(self):
        for override, expected in [(None, 'ssh'), ('/custom/ssh', '/custom/ssh')]:
            with self.subTest(override=override), tempfile.TemporaryDirectory() as directory, \
                 patch.dict(os.environ, {}, clear=True), \
                 patch.object(refresh, 'STATE', Path(directory)), \
                 patch.object(refresh.shutil, 'which', side_effect=lambda command: command) as which, \
                 patch.object(refresh, 'run', return_value=subprocess.CompletedProcess([], 0, 'loaded\n')), \
                 patch.object(refresh, 'sql', return_value='1'), \
                 patch.object(refresh, 'download', side_effect=RuntimeError('stop before download')) as download:
                if override:
                    os.environ['KAGUYA_SSH'] = override
                with self.assertRaisesRegex(RuntimeError, 'stop before download'):
                    refresh.refresh_database(type('Args', (), {'reuse_dump': False})())
                self.assertEqual(download.call_args.args[0][0], expected)


if __name__ == '__main__':
    unittest.main()
