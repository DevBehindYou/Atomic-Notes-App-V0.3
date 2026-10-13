"""CI-only guarded-main compile evidence; no build bundles or raw logs exported."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

CASES = (
    'actual browser entry stays outside native startup and routes',
    'browser transport failures keep bounded retry policy',
    'portable HTTP failures retain retries without message matching',
)
TEST_FILES = (
    'test/web/browser_startup_test.dart',
    'test/web/network_failure_browser_test.dart',
    'test/network_failure_portable_test.dart',
)
OUTPUTS = ('index.html', 'flutter_bootstrap.js', 'main.dart.js')
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


def main():
    root = Path(__file__).resolve().parent.parent
    head = os.environ.get('ATOMIC_WEB_SOURCE_HEAD', '')
    report = {
        'version': 1, 'scope': 'guarded main web compile feasibility only',
        'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
        'entryPoint': 'lib/main.dart', 'flutterVersion': None,
        'phase': 'guard', 'outcome': 'incomplete',
        'buildExitCode': None, 'browserExitCode': None,
        'cases': {name: False for name in CASES}, 'outputs': [],
        'nativeStartupEnabled': False, 'cloudEnabled': False,
        'notesEnabled': False, 'published': False,
        'serviceWorkerRegistered': False,
    }
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or report['sourceHead'] is None:
            raise ValueError('CI source guard')
        code, checked_out = run_private(['git', 'rev-parse', 'HEAD'], root, 30)
        if code != 0 or checked_out.strip() != report['sourceHead']:
            raise ValueError('checkout identity')
        report['phase'] = 'sdk'
        code, stream = run_private(['flutter', '--version', '--machine'], root, 90)
        sdk = json.loads(stream)
        if code != 0 or not isinstance(sdk, dict) or sdk.get('frameworkVersion') != '3.44.8':
            raise ValueError('SDK mismatch')
        report['flutterVersion'] = '3.44.8'
        report['phase'] = 'build'
        # Compile the actual main, not a second entrypoint that omits App imports.
        code, _ = run_private([
            'flutter', 'build', 'web', '--release', '--no-pub',
            '--target', 'lib/main.dart', '--pwa-strategy=none',
            '--no-web-resources-cdn', '--no-source-maps',
        ], root, 900)
        report['buildExitCode'] = code
        if code != 0:
            raise ValueError('build failure')
        output_root = root / 'build/web'
        for name in OUTPUTS:
            output = output_root / name
            size = output.stat().st_size
            if not 0 < size <= STREAM_LIMIT or output.is_symlink():
                raise ValueError('output bound')
            report['outputs'].append({
                'file': name, 'bytes': size,
                'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            })
        bootstrap = (output_root / 'flutter_bootstrap.js').read_text(encoding='utf-8')
        if 'serviceWorkerSettings:' in bootstrap or 'serviceWorkerVersion:' in bootstrap:
            raise ValueError('worker registration configuration')
        report['phase'] = 'browser-tests'
        code, stream = run_private([
            'flutter', 'test', '--no-pub', '--platform', 'chrome', '--reporter', 'json',
            'test/web/browser_startup_test.dart',
            'test/web/network_failure_browser_test.dart',
            'test/network_failure_portable_test.dart',
        ], root, 300)
        report['browserExitCode'] = code
        terminal, report['cases'] = browser_cases(stream)
        if code != 0 or not terminal or not all(report['cases'].values()):
            raise ValueError('browser proof failure')
        report['phase'], report['outcome'] = 'complete', 'passed'
    except (OSError, ValueError, subprocess.TimeoutExpired):
        report['outcome'] = 'failed'
    (root / 'ci-web-compile-proof.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'phase': report['phase'], 'outcome': report['outcome']}))
    return 0 if report['outcome'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
