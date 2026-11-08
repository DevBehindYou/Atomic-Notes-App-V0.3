"""Refuse to upload CI artifacts that contain a secret (C46).

Scans the text artifacts a job is about to upload for the exact values of
secret-named environment variables, credentialed URIs and credential shapes.
A per-run random canary (ATOMIC_CI_CANARY) is the scanner's positive control:
it must be detected in a synthetic sample before any result is trusted.
Writes ci-artifact-scan-proof.json with file names and finding kinds only,
never a value or its position, and exits 1 when uploading would be unsafe.

Usage: python3 tool/scan_ci_artifacts.py PATH [PATH ...]
PATH may be a file, a directory (scanned recursively) or a glob.
"""
import glob
import json
import os
from pathlib import Path
import re
import sys

OUTPUT = 'ci-artifact-scan-proof.json'
MAX_BYTES = 8 * 1024 * 1024
BINARY_SUFFIXES = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.apk', '.aab', '.zip'}
SECRET_NAME = re.compile(r'(KEY|SECRET|TOKEN|PASSWORD|CANARY)$')
CREDENTIALED_URI = re.compile(r'\b[a-z][a-z0-9+.-]*://[^\s:/@"\']+:[^\s/@"\']+@', re.I)
PATTERNS = [
    ('private_key', re.compile(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----')),
    ('google_access_token', re.compile(r'\bya29\.[0-9A-Za-z_-]{20,}')),
    ('google_refresh_token', re.compile(r'\b1//0[0-9A-Za-z_-]{20,}')),
    ('google_client_secret', re.compile(r'\bGOCSPX-[0-9A-Za-z_-]{20,}')),
    ('google_api_key', re.compile(r'\bAIza[0-9A-Za-z_-]{35}\b')),
    ('jwt', re.compile(r'\beyJ[0-9A-Za-z_-]{8,}\.eyJ[0-9A-Za-z_-]{8,}\.[0-9A-Za-z_-]{8,}')),
    ('credentialed_uri', CREDENTIALED_URI),
]


def secret_values(env):
    """Values of secret-named variables and credentialed URIs, 8+ characters."""
    values = set()
    for name, value in env.items():
        if value and len(value) >= 8 and (SECRET_NAME.search(name) or CREDENTIALED_URI.search(value)):
            values.add(value)
    return sorted(values)


def scan_text(name, text, secrets):
    kinds = set()
    if any(secret and secret in text for secret in secrets):
        kinds.add('environment_secret')
    for kind, pattern in PATTERNS:
        if pattern.search(text):
            kinds.add(kind)
    return [{'file': name, 'kind': kind} for kind in sorted(kinds)]


def expand(paths):
    files = []
    for raw in paths:
        matches = glob.glob(raw) or [raw]
        for match in matches:
            path = Path(match)
            if path.is_dir():
                files.extend(p for p in sorted(path.rglob('*')) if p.is_file())
            elif path.is_file():
                files.append(path)
    unique = []
    for path in files:
        if path not in unique and path.name != OUTPUT:
            unique.append(path)
    return unique


def scan(paths, env):
    canary = env.get('ATOMIC_CI_CANARY', '')
    secrets = secret_values(env)
    canary_detected = len(canary) >= 16 and scan_text('control', 'x' + canary + 'x', [canary]) != []
    findings, scanned, skipped = [], 0, 0
    for path in expand(paths):
        if path.suffix.lower() in BINARY_SUFFIXES or path.is_symlink():
            skipped += 1
            continue
        if path.stat().st_size > MAX_BYTES:
            findings.append({'file': path.as_posix(), 'kind': 'too_large_to_scan'})
            continue
        text = path.read_bytes().decode('utf-8', errors='replace')
        findings.extend(scan_text(path.as_posix(), text, secrets + [canary] if canary else secrets))
        scanned += 1
    return {
        'version': 1,
        'scope': 'text artifacts about to be uploaded; binary images and packages are not scanned',
        'scanned': scanned,
        'skippedBinary': skipped,
        'canaryDetected': canary_detected,
        'findings': findings,
        'outcome': 'pass' if canary_detected and not findings else 'fail',
    }


def main(argv):
    report = scan(argv, dict(os.environ))
    Path(OUTPUT).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('outcome', 'scanned', 'skippedBinary', 'findings')}))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
