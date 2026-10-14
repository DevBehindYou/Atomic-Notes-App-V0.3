"""CI-only native browser open-lifecycle proof; no application enablement."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

CASES = (
    'O1 native delete queue times out and aborts late schema upgrade',
    'O2 native upgrade queue times out and closes late successful connection',
    'O3 synthetic unavailable IndexedDB returns safe failure and recovers',
    'O4 synthetic denied IndexedDB getter returns safe failure and recovers',
    'O5 synthetic denied owned factory open returns safe failure and recovers',
)
TEST_FILES = ('test/browser_open_lifecycle_test.dart',)
STREAM_LIMIT = 20 * 1024 * 1024

def run_private(command, root, timeout):
    """Keep bounded CI-private output transient; never serialize its contents."""
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(command, cwd=root, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout,
                                check=False)
        if output.tell() > STREAM_LIMIT:
            raise ValueError('stream bound')
        output.seek(0)
        return result.returncode, output.read().decode('utf-8', errors='replace')


def browser_cases(stream):
    """Only exact public test names and success bits can leave the runner."""
    ids, names, completed = {}, set(), set()
    passed, terminal, ended = {name: False for name in CASES}, False, False
    for line in stream.splitlines():
        if len(line) > 256_000:
            raise ValueError('event bound')
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'testStart':
            if ended:
                raise ValueError('event after terminal')
            test = event.get('test', {})
            if not isinstance(test, dict):
                raise ValueError('test shape')
            number, name = test.get('id'), test.get('name')
            if type(number) is not int or not 0 <= number < 1_000_000:
                raise ValueError('test ID')
            if not isinstance(name, str) or number in ids or name in names:
                raise ValueError('duplicate test identity')
            path = name.removeprefix('loading ').replace('\\', '/')
            loading = name.startswith('loading ') and any(
                path == filename or path.endswith('/' + filename)
                for filename in TEST_FILES)
            if name not in CASES and not loading:
                raise ValueError('unknown test')
            ids[number] = (name if name in CASES else None, loading)
            names.add(name)
        elif event.get('type') == 'testDone':
            if ended:
                raise ValueError('event after terminal')
            number = event.get('testID')
            if type(number) is not int or number not in ids or number in completed:
                raise ValueError('completion without unique start')
            name, loading = ids[number]
            hidden = event.get('hidden', False)
            if type(hidden) is not bool or hidden != loading:
                raise ValueError('hidden loading boundary')
            if type(event.get('skipped')) is not bool or event.get('result') not in (
                    'success', 'failure', 'error'):
                raise ValueError('completion shape')
            if loading and (event['result'] != 'success' or event['skipped']):
                raise ValueError('loading did not pass')
            completed.add(number)
            if name is not None:
                passed[name] = event['result'] == 'success' and not event['skipped']
        elif event.get('type') == 'done':
            if ended or type(event.get('success')) is not bool:
                raise ValueError('duplicate or malformed terminal')
            if completed != set(ids) or not set(CASES).issubset(names):
                raise ValueError('incomplete cases')
            ended = True
            terminal = event.get('success') is True
    if not ended:
        raise ValueError('missing terminal')
    return terminal, passed


def cleanup_receipts(stream):
    """A cleanup receipt belongs to one known active test, never raw output."""
    active, receipts = {}, set()
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'testStart':
            test = event.get('test', {})
            if isinstance(test, dict) and test.get('name') in CASES:
                active[test['id']] = test['name']
        elif event.get('type') == 'print' and event.get('message') == 'ATOMIC_OPEN_CLEANUP_OK':
            number = event.get('testID')
            if number not in active or active[number] in receipts:
                raise ValueError('cleanup identity')
            receipts.add(active[number])
        elif event.get('type') == 'testDone':
            active.pop(event.get('testID'), None)
    return {name: name in receipts for name in CASES}


def main():
    root = Path(__file__).resolve().parent.parent
    head = os.environ.get('ATOMIC_WEB_SOURCE_HEAD', '')
    report = {
        'version': 1, 'scope': 'CI-owned Chromium inactive native open lifecycle and synthetic denial only',
        'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
        'phase': 'guard', 'outcome': 'failed', 'flutterVersion': None,
        'chromeVersion': None, 'primitiveSha256': None,
        'testSha256': None, 'lockSha256': None,
        'browserExitCode': None, 'cases': {name: False for name in CASES},
        'cleanup': {name: False for name in CASES},
        'appEditingEnabled': False, 'cloudEnabled': False,
        'productionAdapterAccepted': False, 'pageReloadProved': False,
        'forcedCrashProved': False, 'crossTabProved': False,
    }
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or report['sourceHead'] is None:
            raise ValueError('CI source guard')
        code, identity = run_private(['git', 'rev-parse', 'HEAD'], root, 30)
        if code or identity.strip() != head:
            raise ValueError('checkout mismatch')
        lock = (root / 'pubspec.lock').read_bytes()
        report['lockSha256'] = hashlib.sha256(lock).hexdigest()
        report['primitiveSha256'] = hashlib.sha256(
            (root / 'lib/platform/browser_record_boundary.dart').read_bytes()).hexdigest()
        report['testSha256'] = hashlib.sha256(
            (root / TEST_FILES[0]).read_bytes()).hexdigest()
        report['phase'] = 'sdk'
        code, stream = run_private(['flutter', '--version', '--machine'], root, 90)
        sdk = json.loads(stream)
        if code or sdk.get('frameworkVersion') != '3.44.8':
            raise ValueError('SDK mismatch')
        report['flutterVersion'] = '3.44.8'
        chrome = os.environ.get('CHROME_EXECUTABLE', '')
        if not chrome.startswith('/'):
            raise ValueError('Chrome executable guard')
        code, version = run_private([chrome, '--version'], root, 30)
        match = re.fullmatch(r'Google Chrome(?: for Testing)? ([0-9]+(?:\.[0-9]+){3})\s*', version)
        if code or match is None:
            raise ValueError('Chrome identity')
        report['chromeVersion'] = match.group(1)
        report['phase'] = 'browser-tests'
        code, stream = run_private([
            'flutter', 'test', '--no-pub', '--platform', 'chrome',
            '--reporter', 'json', TEST_FILES[0],
        ], root, 300)
        report['browserExitCode'] = code
        terminal, report['cases'] = browser_cases(stream)
        report['cleanup'] = cleanup_receipts(stream)
        if code or not terminal or not all(report['cases'].values()) or not all(report['cleanup'].values()):
            raise ValueError('case or owned cleanup failure')
        report['phase'], report['outcome'] = 'complete', 'passed'
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    (root / 'ci-browser-open-proof.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'phase': report['phase'], 'outcome': report['outcome']}))
    return 0 if report['outcome'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

