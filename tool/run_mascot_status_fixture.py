"""Retain fixed case outcomes only; never retain Flutter messages or streams."""

import json
import os
from pathlib import Path
import subprocess
import sys

CASES = {
    'idle local notes do not claim cloud equality': 'idle_local',
    'cloud wipe retains local notes without a synced verdict': 'post_wipe',
    'an open bubble follows activity errors and successful retry': 'live_activity',
    'an open bubble follows pending edits and cleared cooldown': 'live_pending',
    'live updates do not extend the original bubble lifetime': 'auto_hide',
    'disposing an open bubble cancels its hide timer': 'dispose_timer',
}


def initial_report():
    return {'version': 1, 'scope': 'controlled live mascot local sync status',
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
            if isinstance(message, str) and message.strip().startswith('atomic_mascot_cleanup:'):
                code = message.strip().removeprefix('atomic_mascot_cleanup:')
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


def main():
    root = Path(__file__).resolve().parent.parent
    report = initial_report()
    try:
        if os.environ.get('CI') != 'true':
            raise ValueError('guard')
        report['phase'] = 'tests'
        result = subprocess.run(
            ['flutter', 'test', '--no-pub', '--machine', 'test/mascot_live_status_test.dart'],
            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=180, check=False, encoding='utf-8', errors='replace')
        report = classify(result.stdout, result.returncode,
                          'loading ' + str(root / 'test/mascot_live_status_test.dart'))
    except subprocess.TimeoutExpired:
        report['phase'] = 'timeout'
    except Exception:
        report['phase'] = 'runner_failure' if report['phase'] != 'guard' else 'guard'
    (root / 'ci-mascot-status-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
