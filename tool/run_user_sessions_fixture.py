"""Retain fixed case outcomes only; never retain Flutter messages or streams."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

CASES = {'session inventory shows stored dates current guidance and unverified hints': 'inventory_render', 'session load error can retry without changing authentication': 'load_retry', 'empty session inventory remains refreshable': 'empty_refresh', 'cancelled session confirmation sends no revoke': 'cancel_confirm', 'confirmed other session revoke refreshes once and keeps current login': 'revoke_confirm', 'protected session revoke displays refusal without bypassing safe logout': 'protected_revoke', 'ambiguous revoke retries the identical handle and serializes writes': 'ambiguous_retry', 'late inventory is hidden after another account login': 'foreign_read', 'late inventory is hidden after same-owner reauthentication': 'same_owner_read', 'unmounted session page ignores its late inventory': 'unmount_read', 'late revoke cannot mutate a newer account screen or credentials': 'foreign_revoke', 'session change while confirmation is open prevents revoke': 'late_confirmation', 'session DTO rejects malformed identities dates bounds and current flags': 'invalid_dto'}

STAGES = {'init', 'body', 'body_done', 'show_mount', 'show_pump_first',
          'show_pump_second', 'show_done', 'tap_visible', 'tap_ready',
          'tap_pump', 'tap_done', 'inventory_visible', 'inventory_pump',
          'inventory_done', 'cleanup_unmount', 'cleanup_replies',
          'cleanup_pump', 'cleanup_close', 'render_current', 'render_deadline',
          'render_current_action', 'render_safe_logout', 'render_hint',
          'render_no_exception'}


def initial_report():
    return {'version': 1, 'scope': 'controlled App sign-in inventory and ownership',
            'phase': 'guard', 'outcome': 'fail',
            'cases': {code: 'not_run' for code in CASES.values()},
            'cleanup': {code: 'not_run' for code in CASES.values()}}


def source_line(text):
    if not isinstance(text, str):
        return None
    match = re.search(r'user_sessions_test\.dart(?::|\s+)([1-9][0-9]{0,2})(?![0-9])', text)
    return int(match.group(1)) if match is not None else None


def classify(stdout, returncode, loader_name):
    report = initial_report()
    report['phase'] = 'complete'
    ids, seen_cases, completed, loader_ids, completed_loaders = {}, set(), set(), set(), set()
    diagnostics = {}
    body_stages = {}
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
        elif kind == 'error':
            test_id = event.get('testID')
            if type(test_id) is int and test_id in ids:
                detail = diagnostics.setdefault(ids[test_id], {'overflow': False})
                if ids[test_id] in body_stages:
                    detail['stage'] = body_stages[ids[test_id]]
                error, stack = event.get('error'), event.get('stackTrace')
                if isinstance(error, str):
                    detail['category'] = ('missing_element' if 'Bad state: No element' in error
                                          else 'expectation' if 'Expected:' in error
                                          else 'image' if 'IMAGE RESOURCE SERVICE' in error
                                          else 'layout' if 'Render' in error
                                          else 'other')
                if isinstance(error, str) and 'RenderFlex overflowed' in error:
                    detail['overflow'] = True
                line_number = source_line(stack)
                if line_number is not None:
                    detail['sourceLine'] = line_number
        elif kind == 'print':
            message = event.get('message')
            if isinstance(message, str):
                parts = message.strip().split(':')
                test_id = event.get('testID')
                line_number = source_line(message)
                if type(test_id) is int and test_id in ids and line_number is not None:
                    diagnostics.setdefault(ids[test_id], {'overflow': False})['sourceLine'] = line_number
                if (len(parts) == 3 and parts[0] == 'atomic_sessions_stage'
                        and parts[1] in CASES.values() and parts[2] in STAGES
                        and not parts[2].startswith('cleanup_')
                        and type(test_id) is int and ids.get(test_id) == parts[1]):
                    body_stages[parts[1]] = parts[2]
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
    if diagnostics:
        report['failureDiagnostics'] = diagnostics
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
        # Partial fixed case/stage outcomes are useful even if one fake-async
        # test stalls. Private messages and streams are still discarded.
        if private_report.is_file() and private_report.stat().st_size <= 4 * 1024 * 1024:
            raw = private_report.read_text(encoding='utf-8')
            report = classify(raw, 1, 'loading ' + str(root / 'test/user_sessions_test.dart'))
            stages = {}
            for line in raw.splitlines():
                try:
                    event = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(event, dict) or event.get('type') != 'print':
                    continue
                message = event.get('message')
                if not isinstance(message, str):
                    continue
                parts = message.strip().split(':')
                if (len(parts) == 3 and parts[0] == 'atomic_sessions_stage'
                        and parts[1] in CASES.values() and parts[2] in STAGES):
                    stages[parts[1]] = parts[2]
            report['timeoutStages'] = stages
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
