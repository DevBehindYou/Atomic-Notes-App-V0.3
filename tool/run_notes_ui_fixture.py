"""Bounded UI test outcomes; never publish test messages or note contents."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

FILES = {'home': 'test/home_page_test.dart', 'editor': 'test/notes_editor_page_test.dart',
         'previews': 'test/notes_ui_preview_test.dart',
         'cloud': 'test/cloud_button_test.dart'}
FAILURE_CASES = {
    'four-second welcome collapses without removing controls': 'welcome_collapse',
    'background pause and resume reset date and welcome interval': 'welcome_resume',
    'muted home starts its four-second interval when shown': 'welcome_tab',
    'reduced motion collapses immediately after four seconds': 'welcome_reduced_motion',
    'disposing during welcome cancels timer and ticker': 'welcome_dispose',
    '320px and 2x text keep 123 pending notes and controls visible': 'welcome_large_text',
    'selection and responsive layout do not restart a collapsed welcome': 'welcome_selection',
    'on a short screen the header scrolls away with the notes': 'home_short_screen',
    'narrow large-text layout keeps search and cards usable': 'home_large_text',
    'cloud is purple when idle and black with a rotating busy ring': 'cloud_rotation',
    'foreground pause stops the ring and resume restarts it': 'cloud_resume',
    'receive-only source sync animates and returns to idle': 'cloud_receive',
    'manual connectivity check is busy without claiming an upload': 'cloud_connectivity',
}


def classify(raw, code, source):
    result = {'outcome': 'fail', 'passed': 0, 'failed': 0, 'skipped': 0,
              'failureLines': [], 'overflow': False}
    done, valid, started, ended = 0, True, set(), set()
    lines, failures, reported_lines, case_codes = set(), set(), {}, {}
    for line in raw.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            valid = False
            continue
        if not isinstance(event, dict):
            valid = False
            continue
        kind = event.get('type')
        if kind == 'testStart':
            test_id = event.get('test', {}).get('id')
            if type(test_id) is not int or test_id in started:
                valid = False
            else:
                started.add(test_id)
                name = event.get('test', {}).get('name', '')
                case_codes[test_id] = next((code for suffix, code in FAILURE_CASES.items()
                                           if isinstance(name, str) and name.endswith(suffix)), 'other_case')
        elif kind == 'testDone':
            test_id = event.get('testID')
            if test_id not in started or test_id in ended:
                valid = False
            ended.add(test_id)
            if event.get('skipped'):
                result['skipped'] += 1
            elif event.get('result') != 'success':
                result['failed'] += 1
                failures.add(test_id)
            elif event.get('hidden') is False:
                result['passed'] += 1
        elif kind in ('error', 'print'):
            # Only emit bounded numbers against these public source files.
            text = str(event.get('stackTrace', '')) + str(event.get('error', '')) + str(event.get('message', ''))
            # Flutter may publish the public test frame in a print event using
            # whitespace instead of a colon. Retain numbers only, and only for
            # events belonging to a test that actually failed.
            found = {int(match[1]) for match in re.finditer(
                re.escape(source) + r'(?::|\s+)([1-9][0-9]{0,4})(?::[0-9]+)?', text)}
            test_id = event.get('testID')
            if type(test_id) is int:
                reported_lines.setdefault(test_id, set()).update(found)
            if 'RenderFlex overflowed' in text:
                result['overflow'] = True
        elif kind == 'done':
            done += 1
            valid = valid and event.get('success') is True
    for test_id in failures:
        lines.update(reported_lines.get(test_id, set()))
    result['failureLines'] = sorted(lines)[:30]
    if failures:
        result['failureCases'] = sorted({case_codes.get(test_id, 'other_case') for test_id in failures})
    if (code == 0 and valid and done == 1 and started == ended
            and result['passed'] > 0 and result['failed'] == 0
            and result['skipped'] == 0 and not result['overflow']):
        result['outcome'] = 'pass'
    return result


def main():
    root = Path(__file__).resolve().parent.parent
    report = {'version': 1, 'scope': 'notes home and editor UI', 'outcome': 'fail',
              'sourceHead': os.environ.get('ATOMIC_REPAIR_SOURCE_HEAD'), 'suites': {}}
    if os.environ.get('CI') == 'true' and re.fullmatch('[0-9a-f]{40}', report['sourceHead'] or ''):
        for name, source in FILES.items():
            try:
                with tempfile.TemporaryDirectory(prefix='atomic-notes-ui-') as directory:
                    output = Path(directory) / 'machine.jsonl'
                    process = subprocess.run(
                        ['flutter', 'test', '--no-pub', '--reporter', 'silent',
                         '--file-reporter', 'json:' + str(output), source],
                        cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=240, check=False)
                    if not output.is_file() or output.stat().st_size > 8_000_000:
                        raise ValueError('report bound')
                    report['suites'][name] = classify(output.read_text(encoding='utf-8'), process.returncode, source)
            except Exception:
                report['suites'][name] = {'outcome': 'runner_failure'}
        if all(value['outcome'] == 'pass' for value in report['suites'].values()):
            report['outcome'] = 'pass'
    (root / 'ci-notes-ui-proof.json').write_text(json.dumps(report) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
