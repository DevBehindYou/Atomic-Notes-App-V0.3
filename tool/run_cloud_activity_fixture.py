"""Run controlled Cloud Notes tests and retain only fixed-schema outcomes."""

import json
import os
from pathlib import Path
import subprocess
import sys

CASES = {
    'opening during automatic sync is busy without starting another request': 'mount_busy',
    'automatic sync activity starts and ends with source notifications': 'automatic_enter_exit',
    'an idle source notification cannot release a manual request': 'manual_owner',
    'manual completion cannot hide current source activity': 'automatic_after_manual',
    'Cloud Notes shows background activity and disables overlapping actions': 'visible_controls',
}
WIDGET_PHASES = {'mounted', 'automatic_indicator', 'disabled_controls', 'idle_indicator', 'retry_action', 'complete'}


def main():
    root = Path(__file__).resolve().parent.parent
    report = {'version': 1, 'scope': 'controlled Cloud Notes automatic activity',
              'phase': 'guard', 'outcome': 'fail',
              'cases': {value: 'not_run' for value in CASES.values()},
              'widgetPhase': 'not_run'}
    try:
        if os.environ.get('CI') != 'true':
            raise ValueError('guard')
        report['phase'] = 'tests'
        result = subprocess.run(
            ['flutter', 'test', '--no-pub', '--machine', 'test/cloud_automatic_activity_test.dart'],
            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=180, check=False, encoding='utf-8', errors='replace')
        ids = {}
        completed = set()
        done = False
        invalid = False
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                continue
            if not isinstance(event, dict):
                continue
            kind = event.get('type')
            if kind == 'testStart':
                test = event.get('test', {})
                if not isinstance(test, dict):
                    invalid = True
                    continue
                name = test.get('name')
                if name in CASES:
                    test_id = test.get('id')
                    if type(test_id) is not int or test_id in ids:
                        invalid = True
                        continue
                    ids[test_id] = CASES[name]
                elif test.get('hidden') is not True:
                    invalid = True
            elif kind == 'testDone' and event.get('testID') in ids:
                case = ids[event['testID']]
                if case in completed:
                    invalid = True
                completed.add(case)
                report['cases'][case] = ('pass' if event.get('result') == 'success'
                                         and event.get('skipped') is not True else 'fail')
            elif kind == 'print':
                message = event.get('message')
                if isinstance(message, str):
                    for phase in WIDGET_PHASES:
                        if message.strip() == 'atomic_cloud_activity_phase:' + phase:
                            report['widgetPhase'] = phase
            elif kind == 'done':
                done = event.get('success') is True
        passed = (result.returncode == 0 and done and not invalid
                  and set(report['cases'].values()) == {'pass'}
                  and len(completed) == len(CASES)
                  and report['widgetPhase'] == 'complete')
        report['phase'] = 'complete'
        report['outcome'] = 'pass' if passed else 'fail'
    except subprocess.TimeoutExpired:
        report['phase'] = 'timeout'
    except Exception:
        # No raw exception, message, stack, stream or note data is retained.
        report['phase'] = 'runner_failure' if report['phase'] != 'guard' else 'guard'
    (root / 'ci-cloud-activity-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
