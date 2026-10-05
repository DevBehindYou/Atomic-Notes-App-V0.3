"""CI-only real client/server tests against one owned disposable Mongo namespace."""
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import tempfile
import threading


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions disposable fixture required')
    server = Path.cwd() / 'server-fixture'
    if not (server / 'tests/clientFixture.ts').is_file():
        raise RuntimeError('Pinned fixture checkout missing')
    environment = dict(os.environ)
    environment['MONGODB_URI'] = 'mongodb://127.0.0.1:27017/?replicaSet=rs0&directConnection=true'
    environment.pop('MONGODB_DB_NAME', None)
    ready = queue.Queue()
    descriptor = None
    with tempfile.TemporaryFile(mode='w+') as private_errors:
        child = subprocess.Popen(
            ['node', '--import', 'tsx', 'tests/clientFixture.ts'], cwd=server,
            env=environment, stdout=subprocess.PIPE, stderr=private_errors, text=True)
        # Bounded startup: do not block forever reading a failed child's pipe.
        def first_line():
            ready.put(child.stdout.readline(4096))
        reader = threading.Thread(target=first_line, daemon=True)
        reader.start()
        try:
            descriptor = json.loads(ready.get(timeout=60))
            origin = descriptor['origin']
            if not re.fullmatch(r'http://127\.0\.0\.1:[1-9][0-9]{0,4}', origin):
                raise RuntimeError('Fixture origin rejected')
            if int(origin.rsplit(':', 1)[1]) > 65535:
                raise RuntimeError('Fixture port rejected')
            if not re.fullmatch(r'atomic_test_[0-9a-f]{20}', descriptor['database']):
                raise RuntimeError('Fixture namespace rejected')
            # Drain future fixture output privately, never into CI evidence.
            threading.Thread(target=lambda: child.stdout.read(), daemon=True).start()
            subprocess.run([
                'flutter', 'test', '--no-pub', '--reporter', 'expanded',
                'test/server_wire_integration_test.dart',
                f'--dart-define=ATOMIC_FIXTURE_ORIGIN={origin}',
            ], check=True)
        finally:
            # This Popen handle owns the child; no PID lookup or unrelated kill.
            if child.poll() is None:
                child.terminate()
            try:
                result = child.wait(timeout=30)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=10)
                raise RuntimeError('Fixture graceful cleanup timed out') from None
            if result != 0:
                raise RuntimeError('Fixture startup or cleanup failed')
            if descriptor is not None:
                environment['ATOMIC_FIXTURE_DATABASE'] = descriptor['database']
                # Read-only catalog proof: close() must have removed exactly its DB.
                check = """
import { MongoClient } from 'mongodb';
const name = process.env.ATOMIC_FIXTURE_DATABASE;
if (!/^atomic_test_[0-9a-f]{20}$/.test(name)) throw new Error('namespace rejected');
const client = new MongoClient(process.env.MONGODB_URI);
try {
  const found = await client.db('admin').admin().listDatabases({ nameOnly: true, filter: { name } });
  if (found.databases.length !== 0) throw new Error('fixture namespace remains');
} finally { await client.close(); }
"""
                subprocess.run(['node', '--input-type=module', '-e', check],
                               cwd=server, env=environment, check=True)
                print('Owned disposable fixture namespace removed')


if __name__ == '__main__':
    main()
