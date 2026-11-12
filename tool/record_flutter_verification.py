"""Fixed build outcomes for review when GitHub omits per-step metadata.

Android packaging is explicit opt-in (repository variable
ATOMIC_ANDROID_PACKAGING). When it is deferred, the proof covers locked
analysis and tests only: the APK steps must not have run, are recorded as
"deferred", and no APK may exist. A deferred APK check is never reported as
passed.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

APK_STEPS = ('build', 'apkUpload')
STEP_NAMES = ('analyze', 'tests') + APK_STEPS
OUTCOMES = {'success', 'failure', 'skipped', 'cancelled'}


def hash_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def build_report(root, env):
    head = env.get('ATOMIC_VERIFY_SOURCE_HEAD', '')
    packaging = env.get('ATOMIC_VERIFY_PACKAGING', 'enabled')
    deferred = packaging == 'deferred'
    report = {'version': 2,
              'scope': ('locked Flutter analysis and tests; debug APK deferred'
                        if deferred else 'locked Flutter analysis tests and debug APK'),
              'packaging': packaging if packaging in {'enabled', 'deferred'} else 'unavailable',
              'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
              'outcome': 'fail', 'steps': {}, 'apk': None, 'lockSha256': None}
    for name in STEP_NAMES:
        value = env.get('ATOMIC_VERIFY_' + name.upper(), '')
        report['steps'][name] = value if value in OUTCOMES else 'unavailable'
    apk = root / 'build/app/outputs/flutter-apk/app-debug.apk'
    lock = root / 'pubspec.lock'
    base_ok = (env.get('GITHUB_ACTIONS') == 'true' and report['sourceHead']
               and report['packaging'] != 'unavailable' and lock.is_file()
               and report['steps']['analyze'] == 'success'
               and report['steps']['tests'] == 'success')
    if deferred:
        # The APK steps must have been skipped and no APK may have been made.
        apk_steps_skipped = all(report['steps'][name] == 'skipped' for name in APK_STEPS)
        if apk_steps_skipped:
            for name in APK_STEPS:
                report['steps'][name] = 'deferred'
        if base_ok and apk_steps_skipped and not apk.exists():
            report['lockSha256'] = hash_file(lock)
            report['outcome'] = 'pass'
        return report
    if (base_ok and all(report['steps'][name] == 'success' for name in APK_STEPS)
            and apk.is_file() and not apk.is_symlink()
            and 512_000 <= apk.stat().st_size <= 300_000_000):
        report['apk'] = {'bytes': apk.stat().st_size, 'sha256': hash_file(apk)}
        report['lockSha256'] = hash_file(lock)
        report['outcome'] = 'pass'
    return report


def main():
    root = Path(__file__).resolve().parent.parent
    report = build_report(root, os.environ)
    (root / 'ci-flutter-verification-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps({'outcome': report['outcome'], 'packaging': report['packaging'],
                      'steps': report['steps']}))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
