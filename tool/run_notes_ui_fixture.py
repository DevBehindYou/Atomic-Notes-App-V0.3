"""Bounded UI test outcomes; never publish test messages or note contents."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

FILES = {'home': 'test/home_page_test.dart', 'editor': 'test/notes_editor_page_test.dart',
         'previews': 'test/notes_ui_preview_test.dart'}


def classify(raw, code, source):
    result = {'outcome': 'fail', 'passed': 0, 'failed': 0, 'skipped': 0,
              'failureLines': [], 'overflow': False}
    done, valid, started, ended = 0, True, set(), set()
    lines = set()
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
        elif kind == 'testDone':
            test_id = event.get('testID')
            if test_id not in started or test_id in ended:
                valid = False
            ended.add(test_id)
            if event.get('skipped'):
                result['skipped'] += 1
            elif event.get('result') != 'success':
                result['failed'] += 1
            elif event.get('hidden') is False:
                result['passed'] += 1
        elif kind in ('error', 'print'):
            # Only emit bounded numbers against these public source files.
            text = str(event.get('stackTrace', '')) + str(event.get('error', '')) + str(event.get('message', ''))
            for match in re.finditer(re.escape(source) + r':([1-9][0-9]{0,4})(?::[0-9]+)?', text):
                lines.add(int(match[1]))
            if 'RenderFlex overflowed' in text:
                result['overflow'] = True
        elif kind == 'done':
            done += 1
            valid = valid and event.get('success') is True
    result['failureLines'] = sorted(lines)[:30]
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
