"""Fixed build outcomes for review when GitHub omits per-step metadata."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys


def hash_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    root = Path(__file__).resolve().parent.parent
    head = os.environ.get('ATOMIC_VERIFY_SOURCE_HEAD', '')
    names = ('analyze', 'tests', 'build', 'apkUpload')
    report = {'version': 1, 'scope': 'locked Flutter analysis tests and debug APK',
              'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
              'outcome': 'fail', 'steps': {}, 'apk': None, 'lockSha256': None}
    for name in names:
        value = os.environ.get('ATOMIC_VERIFY_' + name.upper(), '')
        report['steps'][name] = value if value in {'success', 'failure', 'skipped', 'cancelled'} else 'unavailable'
    apk = root / 'build/app/outputs/flutter-apk/app-debug.apk'
    lock = root / 'pubspec.lock'
    if (os.environ.get('GITHUB_ACTIONS') == 'true' and report['sourceHead']
            and all(value == 'success' for value in report['steps'].values())
            and apk.is_file() and not apk.is_symlink()
            and 512_000 <= apk.stat().st_size <= 300_000_000 and lock.is_file()):
        report['apk'] = {'bytes': apk.stat().st_size, 'sha256': hash_file(apk)}
        report['lockSha256'] = hash_file(lock)
        report['outcome'] = 'pass'
    (root / 'ci-flutter-verification-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps({'outcome': report['outcome'], 'steps': report['steps']}))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
