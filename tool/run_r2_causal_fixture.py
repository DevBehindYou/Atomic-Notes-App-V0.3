"""Actual historical/current repository proof. Never retain test messages/logs."""

import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from urllib.parse import urljoin

BASELINE = '2cdc0516935b0ae9b8d7770efcf0d66ae1b8b55a'
HISTORICAL_HASHES = {
    'lib/database/notes_repository.dart': '78be92ac5a04f831497b53363248cf99735c4636055b8bc956a1f0cfc33d6f51',
    'lib/page/settings_page.dart': 'c889ef5382e77935c3a46e0723f966108071bd4a9831ee6eb6976b38a426a1f2',
    'test/notes_repository_lifecycle_test.dart': '3dcf9f190e671656da1e9439a598ee53f1603880b0bff2b8c28eb89713d6dee5',
}
CASES = {
    'R2 busy sync preserves a later local edit': 'busy_logout',
    'R2 paused upload excludes later snapshot content': 'snapshot_control',
    'R2 clean acknowledged notes can be cleared': 'clean_control',
}
OBSERVATIONS = {
    'before': {'busy_logout': ['early_success', 'erased'],
               'snapshot_control': ['paused_snapshot'], 'clean_control': ['clean_clear']},
    'after': {'busy_logout': ['waited', 'preserved'],
              'snapshot_control': ['paused_snapshot'], 'clean_control': ['clean_clear']},
}
MAX_PRIVATE_REPORT = 4 * 1024 * 1024
TEST_PATH = 'test/r2_logout_causal_test.dart'


def phase_report():
    return {'outcome': 'fail', 'cases': {code: 'not_run' for code in CASES.values()},
            'cleanup': {code: 'not_run' for code in CASES.values()},
            'observations': {code: [] for code in CASES.values()}}


def initial_report():
    return {'version': 1, 'scope': 'actual repository R2 historical causal proof; no UI or native claim',
            'baselineHead': BASELINE, 'historicalHashes': HISTORICAL_HASHES.copy(),
            'commonBodySha256': None,
            'phase': 'guard', 'outcome': 'fail',
            'before': phase_report(), 'after': phase_report(), 'ownedCleanup': 'not_run'}


def classify(stream, returncode, loader_name, phase):
    report = phase_report()
    ids, completed, seen, loaders, loader_done = {}, set(), set(), set(), set()
    done_count, terminal, invalid = 0, None, False
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            invalid = True
            continue
        if not isinstance(event, dict):
            invalid = True
            continue
        kind = event.get('type')
        if kind == 'testStart':
            test = event.get('test')
            if not isinstance(test, dict) or type(test.get('id')) is not int:
                invalid = True
                continue
            number, name = test['id'], test.get('name')
            if number in ids or number in loaders:
                invalid = True
                continue
            if isinstance(name, str) and name in CASES:
                code = CASES[name]
                if code in seen:
                    invalid = True
                seen.add(code)
                ids[number] = code
            elif name == loader_name and not loaders:
                loaders.add(number)
            else:
                invalid = True
        elif kind == 'testDone':
            number = event.get('testID')
            if type(number) is not int:
                invalid = True
                continue
            if number in loaders:
                if (number in loader_done or event.get('result') != 'success'
                        or event.get('hidden') is not True or event.get('skipped') is not False):
                    invalid = True
                loader_done.add(number)
                continue
            if number not in ids or ids[number] in completed:
                invalid = True
                continue
            code = ids[number]
            completed.add(code)
            if event.get('hidden') is not False or event.get('skipped') is not False:
                invalid = True
            if event.get('result') not in ('success', 'failure', 'error'):
                invalid = True
            report['cases'][code] = 'pass' if event.get('result') == 'success' else 'fail'
        elif kind == 'print':
            message = event.get('message')
            if not isinstance(message, str):
                continue
            marker = message.strip()
            if not marker.startswith(('atomic_r2_cleanup:', 'atomic_r2_observation:')):
                continue
            number = event.get('testID')
            if type(number) is not int or number not in ids:
                invalid = True
                continue
            code = ids[number]
            if marker.startswith('atomic_r2_cleanup:'):
                if (marker != 'atomic_r2_cleanup:' + code or report['cleanup'][code] != 'not_run'):
                    invalid = True
                else:
                    report['cleanup'][code] = 'pass'
            else:
                parts = marker.split(':')
                if (len(parts) != 3 or parts[1] != code
                        or parts[2] not in OBSERVATIONS[phase][code]
                        or parts[2] in report['observations'][code]):
                    invalid = True
                else:
                    report['observations'][code].append(parts[2])
        elif kind == 'done':
            done_count += 1
            terminal = event.get('success')
    expected = {code: ('fail' if phase == 'before' and code == 'busy_logout' else 'pass')
                for code in CASES.values()}
    if (not invalid and report['cases'] == expected
            and report['observations'] == OBSERVATIONS[phase]
            and set(report['cleanup'].values()) == {'pass'}
            and len(loaders) == 1 and loader_done == loaders
            and completed == set(CASES.values()) and done_count == 1
            and terminal is (phase == 'after')
            and returncode == (0 if phase == 'after' else 1)):
        report['outcome'] = 'pass'
    return report


def git_bytes(root, arguments, bound):
    result = subprocess.run(['git', '-c', 'safe.directory=' + str(root), '-C', str(root), *arguments],
                            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            timeout=30, check=False)
    if result.returncode != 0 or len(result.stdout) > bound:
        raise ValueError('git_source_guard')
    return result.stdout


def read_source(root, revision, path):
    normalized = PurePosixPath(path)
    if (not path.endswith('.dart') or normalized.is_absolute() or '..' in normalized.parts
            or normalized.parts[0] not in ('lib', 'test') or path.endswith('/cred.dart')):
        raise ValueError('source_path_guard')
    return git_bytes(root, ['show', revision + ':' + path], 512 * 1024).decode('utf-8')


def export_dependencies(root, revision, destination, path, source, visited):
    if path in visited:
        return
    if len(visited) >= 120:
        raise ValueError('source_count_guard')
    visited.add(path)
    target = destination / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source, encoding='utf-8')
    for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", source):
        if uri.startswith('package:atomic_notes/'):
            child = 'lib/' + uri.removeprefix('package:atomic_notes/')
        elif ':' not in uri:
            child = str(PurePosixPath(path).parent / uri)
        else:
            continue
        if child.endswith('/cred.dart'):
            # Only public example configuration is ever exported/read.
            example = child.removesuffix('cred.dart') + 'cred.example.dart'
            public_source = read_source(root, revision, example)
            config_target = destination / child
            config_target.parent.mkdir(parents=True, exist_ok=True)
            config_target.write_text(public_source, encoding='utf-8')
            continue
        if child not in visited:
            export_dependencies(root, revision, destination, child,
                                read_source(root, revision, child), visited)


def relocated_config(config, source_path, destination):
    result = copy.deepcopy(config)
    if not isinstance(result, dict) or not isinstance(result.get('packages'), list):
        raise ValueError('package_config_guard')
    own = 0
    for package in result['packages']:
        if not isinstance(package, dict) or not isinstance(package.get('rootUri'), str):
            raise ValueError('package_config_guard')
        package['rootUri'] = urljoin(source_path.as_uri(), package['rootUri'])
        if package.get('name') == 'atomic_notes':
            own += 1
            package['rootUri'] = destination.as_uri() + '/'
    if own != 1:
        raise ValueError('own_package_guard')
    return result


def prepare_package(root, destination, revision, fixture, config, config_path):
    destination.mkdir()
    pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8')
    parts = re.split(r'^flutter:\s*$', pubspec, flags=re.MULTILINE)
    if len(parts) != 2:
        raise ValueError('pubspec_guard')
    # These repository-only tests use no artwork. Dependencies remain unchanged.
    (destination / 'pubspec.yaml').write_text(parts[0] + 'flutter:\n  uses-material-design: false\n',
                                           encoding='utf-8')
    (destination / 'pubspec.lock').write_bytes((root / 'pubspec.lock').read_bytes())
    dart_tool = destination / '.dart_tool'
    dart_tool.mkdir()
    (dart_tool / 'package_config.json').write_text(
        json.dumps(relocated_config(config, config_path, destination)), encoding='utf-8')
    export_dependencies(root, revision, destination, TEST_PATH, fixture, set())


def execute_package(root, phase, run=subprocess.run):
    private = root / 'private-events.jsonl'
    env = os.environ.copy()
    env['ATOMIC_R2_OWNED_ROOT'] = str(root)
    result = run(['flutter', 'test', '--no-pub', '--reporter', 'silent',
                  '--file-reporter', 'json:' + str(private), TEST_PATH],
                 cwd=root, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 timeout=180, check=False)
    if not private.is_file() or private.stat().st_size > MAX_PRIVATE_REPORT:
        raise ValueError('private_report_guard')
    return classify(private.read_text(encoding='utf-8'), result.returncode,
                    'loading ' + str(root / TEST_PATH), phase)


def run_fixture(root, run=subprocess.run, temporary_factory=tempfile.TemporaryDirectory):
    report = initial_report()
    temporary = None
    try:
        report['phase'] = 'source_guard'
        for path, digest in HISTORICAL_HASHES.items():
            source = read_source(root, BASELINE, path)
            if hashlib.sha256(source.encode()).hexdigest() != digest:
                raise ValueError('historical_hash_guard')
        config_path = root / '.dart_tool/package_config.json'
        if not config_path.is_file() or config_path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('package_config_guard')
        config = json.loads(config_path.read_text(encoding='utf-8'))
        fixture = (root / TEST_PATH).read_text(encoding='utf-8')
        if fixture.count('void main() {') != 1:
            raise ValueError('common_fixture_guard')
        report['commonBodySha256'] = hashlib.sha256(
            fixture.split('void main() {', 1)[1].encode()).hexdigest()
        historical = read_source(root, BASELINE, 'test/notes_repository_lifecycle_test.dart')
        prefix = historical.split('void main() {', 1)[0]
        before_fixture = ("import 'package:flutter/foundation.dart' show debugPrint;\n" + prefix
                          + 'void main() {' + fixture.split('void main() {', 1)[1])
        temporary = temporary_factory(prefix='atomic-r2-causal-')
        owned = Path(temporary.name).resolve()
        prepare_package(root, owned / 'before', BASELINE, before_fixture, config, config_path)
        prepare_package(root, owned / 'after', 'HEAD', fixture, config, config_path)
        report['phase'] = 'tests'
        report['before'] = execute_package(owned / 'before', 'before', run)
        report['after'] = execute_package(owned / 'after', 'after', run)
        report['phase'] = 'complete'
        if report['before']['outcome'] == report['after']['outcome'] == 'pass':
            report['outcome'] = 'pass'
    except subprocess.TimeoutExpired:
        report['phase'] = 'timeout'
    except Exception:
        report['phase'] = 'runner_failure'
    finally:
        if temporary is not None:
            try:
                temporary.cleanup()
                if Path(temporary.name).exists():
                    raise ValueError('owned_cleanup_guard')
                report['ownedCleanup'] = 'pass'
            except Exception:
                report['ownedCleanup'] = 'fail'
                report['phase'] = 'cleanup_failure'
                report['outcome'] = 'fail'
    return report


def main():
    root = Path(__file__).resolve().parent.parent
    report = run_fixture(root) if os.environ.get('CI') == 'true' else initial_report()
    (root / 'ci-r2-causal-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
