"""Fixed build outcomes for review when GitHub omits per-step metadata.

Android packaging is explicit opt-in (repository variable
ATOMIC_ANDROID_PACKAGING). When it is deferred, the proof covers locked
analysis and tests only: the APK steps must not have run, are recorded as
"deferred", and no Android package (APK, split APK, AAB or APK set) may exist
in any generated output location. A deferred APK check is never reported as
passed.

Proof schema: version 1 (before packaging was opt-in) had version, scope,
sourceHead, outcome, steps, apk and lockSha256. Version 2 adds "packaging"
("enabled", "deferred" or "unavailable"), allows the step value "deferred",
and in deferred mode adds "androidArtifacts" (the generated packages found,
at most 20 paths; null when a root could not be read) and, on such a failure,
"inspectionError". Enabled-mode pass/fail, hash and size rules are those of
version 1. No reader of this proof exists in the repository; it is uploaded
for human review only.
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

# Where Gradle, Flutter and this repository's workflows put Android packages:
# Flutter's build directory (flutter-apk, apk/<variant>, bundle/<variant>),
# Gradle's own app outputs, and the staging workflow's copy directory. The
# scan never leaves these roots, so source, assets and private data are not
# read.
ARTIFACT_ROOTS = ('build/app/outputs', 'android/app/build/outputs', 'staging-artifact')
ARTIFACT_SUFFIXES = ('.apk', '.aab', '.apks')
MAX_ENTRIES = 50_000
MAX_LISTED = 20


class InspectionError(Exception):
    """A generated-output root could not be fully inspected."""


def hash_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def find_android_packages(root, walk=os.walk):
    """Relative paths of Android packages under the generated-output roots.

    Raises InspectionError when a root exists but cannot be read completely,
    or holds more than MAX_ENTRIES entries, so a deferred proof fails closed
    instead of passing on a partial scan.
    """
    found, seen = [], 0
    for name in ARTIFACT_ROOTS:
        base = root / name
        if os.path.lexists(base) and not os.path.isdir(base):
            # A root replaced by a file or a dangling link is not a clean tree.
            raise InspectionError(f'{name}: not a directory')
        if not os.path.isdir(base):
            continue

        def fail(error, name=name):
            raise InspectionError(f'{name}: {error.__class__.__name__}')

        for directory, subdirs, files in walk(base, onerror=fail, followlinks=False):
            seen += len(subdirs) + len(files)
            if seen > MAX_ENTRIES:
                raise InspectionError(f'more than {MAX_ENTRIES} generated entries')
            # Symlinked directories are listed but not followed; anything
            # named like a package counts.
            for entry in subdirs + files:
                if entry.lower().endswith(ARTIFACT_SUFFIXES):
                    found.append(Path(directory, entry).relative_to(root).as_posix())
    return sorted(found)


def build_report(root, env, walk=os.walk):
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
        # The APK steps must have been skipped and no Android package of any
        # kind may exist in the generated outputs.
        apk_steps_skipped = all(report['steps'][name] == 'skipped' for name in APK_STEPS)
        if apk_steps_skipped:
            for name in APK_STEPS:
                report['steps'][name] = 'deferred'
        try:
            packages = find_android_packages(root, walk)
            report['androidArtifacts'] = packages[:MAX_LISTED]
        except InspectionError as error:
            packages = None
            report['androidArtifacts'] = None
            report['inspectionError'] = str(error)
        if base_ok and apk_steps_skipped and packages == []:
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
                      'steps': report['steps'],
                      'androidArtifacts': report.get('androidArtifacts')}))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
