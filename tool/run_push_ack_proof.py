"""Controlled native reply outcomes only; never publish note/test messages."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REFUSALS = ('later_date', 'calendar_date', 'fractional_version', 'regressing_version',
            'duplicate_id', 'missing_id', 'foreign_id', 'fractional_seq',
            'nonboolean_ok', 'nonboolean_unchanged', 'empty_error')
CONTROLS = ('valid_write', 'legacy_billing', 'unknown_billing', 'unchanged',
            'mixed_failure', 'first_delete', 'omitted_seq')
CASES = {**{f'push ack refusal {code} preserves the complete batch': code for code in REFUSALS},
         **{f'push ack control {code} preserves compatible results': code for code in CONTROLS}}


def classify(raw, returncode, loader_name):
    report = {'outcome': 'fail', 'cases': {code: 'not_run' for code in CASES.values()},
              'cleanup': {code: 'not_run' for code in CASES.values()}}
    ids, loaders, ended, loader_ended, clean = {}, set(), set(), set(), set()
    terminal, success, valid = 0, False, True
    source_lines = {}
    for line in raw.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            valid = False
            continue
        if not isinstance(event, dict):
            valid = False
            continue
        kind = event.get('type')
        if kind == 'testStart':
            test = event.get('test')
            if not isinstance(test, dict) or type(test.get('id')) is not int:
                valid = False
                continue
            ident, name = test['id'], test.get('name')
            if ident in ids or ident in loaders:
                valid = False
            elif name in CASES and CASES[name] not in ids.values():
                ids[ident] = CASES[name]
            elif name == loader_name and not loaders:
                loaders.add(ident)
            else:
                valid = False
        elif kind == 'testDone':
            ident = event.get('testID')
            if ident in loaders:
                if ident in loader_ended or event.get('result') != 'success' or event.get('skipped') is not False:
                    valid = False
                loader_ended.add(ident)
            elif ident in ids:
                if ident in ended or event.get('hidden') is not False:
                    valid = False
                ended.add(ident)
                report['cases'][ids[ident]] = ('pass' if event.get('result') == 'success'
                                              and event.get('skipped') is False else 'fail')
            else:
                valid = False
        elif kind == 'print':
            ident, message = event.get('testID'), event.get('message')
            if isinstance(message, str) and message.startswith('atomic_push_ack_cleanup:'):
                code = message.strip().removeprefix('atomic_push_ack_cleanup:')
                if code not in CASES.values() or ids.get(ident) != code or code in clean:
                    valid = False
                else:
                    clean.add(code)
                    report['cleanup'][code] = 'pass'
        elif kind == 'error':
            ident = event.get('testID')
            if ident in ids and isinstance(event.get('stackTrace'), str):
                matches = re.findall(r'push_ack_boundary_test\.dart:([1-9][0-9]{0,3})(?::|\s)',
                                     event['stackTrace'])
                if matches:
                    source_lines[ids[ident]] = sorted({int(value) for value in matches})[:8]
        elif kind == 'done':
            terminal += 1
            success = event.get('success') is True
    report['streamValid'] = (valid and terminal == 1 and len(loaders) == 1
                             and loaders == loader_ended and set(ids) == ended
                             and set(ids.values()) == set(CASES.values())
                             and clean == set(CASES.values()))
    if returncode == 0 and success and report['streamValid'] and set(report['cases'].values()) == {'pass'}:
        report['outcome'] = 'pass'
    if source_lines:
        report['failureLines'] = source_lines
    return report


def main():
    root = Path(__file__).resolve().parents[1]
    proof = {'version': 1, 'scope': 'native full-batch push acknowledgement preservation',
             'sourceHead': os.environ.get('ATOMIC_PUSH_ACK_SOURCE_HEAD', ''),
             'testBodySha256': hashlib.sha256((root / 'test/push_ack_boundary_test.dart').read_bytes()).hexdigest(),
             'apiSourceSha256': hashlib.sha256((root / 'lib/api/atomic_notes_api.dart').read_bytes()).hexdigest(),
             'productionAccess': False, 'phase': 'tests', 'outcome': 'fail'}
    try:
        with tempfile.TemporaryDirectory(prefix='atomic-push-ack-proof-') as directory:
            report_path = Path(directory) / 'private.jsonl'
            result = subprocess.run(['flutter', 'test', '--no-pub', '--reporter', 'silent',
                                     '--file-reporter', 'json:' + str(report_path),
                                     'test/push_ack_boundary_test.dart'], cwd=root,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    timeout=180, check=False)
            if not report_path.is_file() or report_path.stat().st_size > 4 * 1024 * 1024:
                raise ValueError('invalid_private_report')
            proof.update(classify(report_path.read_text(encoding='utf-8'), result.returncode,
                                  'loading ' + str(root / 'test/push_ack_boundary_test.dart')))
            proof['phase'] = 'complete'
    except Exception:
        proof['phase'] = 'fixture_failure'
    (root / 'ci-push-ack-proof.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'outcome': proof['outcome'], 'phase': proof['phase']}))
    return 0 if proof['outcome'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
