"""Retain fixed case outcomes only; never retain Flutter messages or streams."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CASES = {'session inventory shows stored dates current guidance and unverified hints': 'inventory_render', 'session load error can retry without changing authentication': 'load_retry', 'empty session inventory remains refreshable': 'empty_refresh', 'cancelled session confirmation sends no revoke': 'cancel_confirm', 'confirmed other session revoke refreshes once and keeps current login': 'revoke_confirm', 'protected session revoke displays refusal without bypassing safe logout': 'protected_revoke', 'ambiguous revoke retries the identical handle and serializes writes': 'ambiguous_retry', 'late inventory is hidden after another account login': 'foreign_read', 'late inventory is hidden after same-owner reauthentication': 'same_owner_read', 'unmounted session page ignores its late inventory': 'unmount_read', 'late revoke cannot mutate a newer account screen or credentials': 'foreign_revoke', 'session change while confirmation is open prevents revoke': 'late_confirmation', 'session DTO rejects malformed identities dates bounds and current flags': 'invalid_dto'}


def initial_report():
    return {'version': 1, 'scope': 'controlled App sign-in inventory and ownership',
            'phase': 'guard', 'outcome': 'fail',
            'cases': {code: 'not_run' for code in CASES.values()},
            'cleanup': {code: 'not_run' for code in CASES.values()}}


def classify(stdout, returncode, loader_name):
    report = initial_report()
    report['phase'] = 'complete'
    ids, seen_cases, completed, loader_ids, completed_loaders = {}, set(), set(), set(), set()
    done_count, successful_done, invalid = 0, False, False
    for line in stdout.splitlines():
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
            test_id, name = test['id'], test.get('name')
            if test_id in ids or test_id in loader_ids:
                invalid = True
                continue
            if isinstance(name, str) and name in CASES:
                case = CASES[name]
                if case in seen_cases:
                    invalid = True
                seen_cases.add(case)
                ids[test_id] = case
            elif name == loader_name and not loader_ids:
                loader_ids.add(test_id)
            else:
                invalid = True
        elif kind == 'testDone':
            test_id = event.get('testID')
            if type(test_id) is not int:
                invalid = True
                continue
            if test_id in loader_ids:
                if (test_id in completed_loaders or event.get('result') != 'success'
                        or event.get('skipped') is not False or event.get('hidden') is not True):
                    invalid = True
                completed_loaders.add(test_id)
                continue
            if test_id not in ids:
                invalid = True
                continue
            case = ids[test_id]
            if case in completed or event.get('hidden') is not False:
                invalid = True
            completed.add(case)
            report['cases'][case] = ('pass' if event.get('result') == 'success'
                                     and event.get('skipped') is False else 'fail')
        elif kind == 'print':
            message = event.get('message')
            if isinstance(message, str) and message.strip().startswith('atomic_sessions_cleanup:'):
                code = message.strip().removeprefix('atomic_sessions_cleanup:')
                test_id = event.get('testID')
                if (code not in report['cleanup'] or report['cleanup'][code] == 'pass'
                        or type(test_id) is not int or ids.get(test_id) != code):
                    invalid = True
                else:
                    report['cleanup'][code] = 'pass'
        elif kind == 'done':
            done_count += 1
            successful_done = event.get('success') is True
    if (returncode == 0 and done_count == 1 and successful_done and not invalid
            and len(loader_ids) == 1 and completed_loaders == loader_ids
            and len(completed) == len(CASES)
            and set(report['cases'].values()) == {'pass'}
            and set(report['cleanup'].values()) == {'pass'}):
        report['outcome'] = 'pass'
    return report


def run_fixture(root, run=subprocess.run, temporary_factory=tempfile.TemporaryDirectory):
    report = initial_report()
    report['phase'] = 'tests'
    temporary = None
    try:
        temporary = temporary_factory(prefix='atomic-sessions-proof-')
        directory = Path(temporary.name)
        private_report = directory / 'report.jsonl'
        result = run(
            ['flutter', 'test', '--no-pub', '--reporter', 'silent',
             '--file-reporter', 'json:' + str(private_report), 'test/user_sessions_test.dart'],
            cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=180, check=False)
        if not private_report.is_file() or private_report.stat().st_size > 4 * 1024 * 1024:
            raise ValueError('private_report_invalid')
        report = classify(private_report.read_text(encoding='utf-8'), result.returncode,
                          'loading ' + str(root / 'test/user_sessions_test.dart'))
    except subprocess.TimeoutExpired:
        report['phase'] = 'timeout'
    except Exception:
        report['phase'] = 'runner_failure'
    finally:
        if temporary is not None:
            try:
                temporary.cleanup()
                if Path(temporary.name).exists():
                    raise ValueError('private_report_cleanup_failed')
            except Exception:
                report['phase'] = 'cleanup_failure'
                report['outcome'] = 'fail'
    return report


def main():
    root = Path(__file__).resolve().parent.parent
    report = run_fixture(root) if os.environ.get('CI') == 'true' else initial_report()
    (root / 'ci-user-sessions-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
