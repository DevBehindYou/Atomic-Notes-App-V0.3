"""Fixed-code controlled recovery proof; discard all raw machine/log output."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SCOPE = 'controlled same-owner logout recovery; real Hive; synthetic auth and receipts'
NAMES = {
    'newer edit is retained after recovery and only a new explicit attempt uploads it': 'newer_edit',
    'foreign account is blocked before receipt delivery without erasing owner cache': 'foreign_owner',
    'locked protected rows remain byte-for-byte retained before recovery network': 'locked_ciphertext',
    'missing receipt refuses recovery and retains exact old plan and request': 'missing_receipt',
    'late same-owner replaced-session reply cannot apply or erase notes': 'late_session',
    'tampered frozen pending snapshot is blocked before commit': 'tampered_pending',
    'settled conflict uses deterministic copy and a reset pull, retaining both versions': 'conflict_copy',
    'interrupted conflict recovery never overwrites an edited copy on replay': 'edited_copy_replay',
    'aborted failed old receipt does not regress an already newer acknowledged row': 'newer_acknowledged',
    'partial settled recovery keeps failed work and never uploads the accepted row again': 'partial_settlement',
    'same-content post-plan vault migration remains dirty until a new sealed attempt': 'vault_same_content',
}
for funding in ('free', 'paid'):
    for stage in ('push', 'completion'):
        NAMES[f'same owner recovers {funding} {stage} without upload'] = f'{funding}_{stage}'
for fault in ('reply', 'put', 'flush'):
    NAMES[f'{fault} loss after Server settlement survives real Hive reopen without another debit or upload'] = f'lost_{fault}'
for reopen in ('false', 'true'):
    NAMES[f'conflict-copy put loss retries durably (reopen={reopen})'] = f'copy_put_reopen_{reopen}'
for key, code in (('__pending_sync_operation', 'pending'), ('__pending_logout_attempt__', 'plan')):
    for after in ('false', 'true'):
        NAMES[f'metadata deletion interruption keeps notes (key={key} after={after})'] = f'delete_{code}_after_{after}'


def main():
    root = Path(__file__).resolve().parent.parent
    proof = {'version': 1, 'scope': SCOPE,
             'outcomes': {code: 'not_executed' for code in NAMES.values()},
             'outcome': 'failed'}
    head = os.environ.get('ATOMIC_REPAIR_SOURCE_HEAD', '')
    diagnostic = {'version': 1, 'scope': 'redacted controlled recovery machine metadata',
                  'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
                  'phase': 'guard', 'exitStatus': 'unavailable',
                  'privateStderrLines': 0,
                  'started': 0, 'completed': 0, 'terminalCount': 0, 'terminalSuccess': False,
                  'rejections': {code: 0 for code in ('parse', 'not_object', 'invalid_start',
                                'duplicate_start', 'unknown_hidden', 'unknown_visible',
                                'invalid_done', 'duplicate_done')}}
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise ValueError('guard')
        diagnostic['phase'] = 'tests'
        result = subprocess.run(['flutter', 'test', '--no-pub', '--machine',
                                 'test/logout_same_owner_recovery_test.dart'],
                                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=180, check=False, encoding='utf-8', errors='replace')
        ids, loader_ids, loader_completed, seen, completed = {}, set(), set(), set(), set()
        invalid, done = False, False
        diagnostic['exitStatus'] = 'zero' if result.returncode == 0 else 'nonzero'
        diagnostic['privateStderrLines'] = min(100, len((getattr(result, 'stderr', '') or '').splitlines()))
        def reject(code):
            nonlocal invalid
            invalid = True
            diagnostic['rejections'][code] = min(100, diagnostic['rejections'][code] + 1)
        done_count = 0
        loader_name = 'loading ' + str(root / 'test/logout_same_owner_recovery_test.dart')
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                reject('parse')
                continue
            if not isinstance(event, dict):
                reject('not_object')
                continue
            if event.get('type') == 'testStart':
                test = event.get('test')
                if not isinstance(test, dict) or type(test.get('id')) is not int:
                    reject('invalid_start')
                    continue
                test_id = test['id']
                code = NAMES.get(test.get('name'))
                if test_id in ids or test_id in loader_ids:
                    reject('duplicate_start')
                    continue
                if code is not None:
                    if code in seen or test.get('hidden') is True:
                        reject('duplicate_start')
                        continue
                    seen.add(code)
                    ids[test_id] = code
                    proof['outcomes'][code] = 'started'
                # JsonReporter puts hidden on testDone, not testStart. The
                # loading case is accepted only by its exact controlled path;
                # its successful hidden completion is checked separately.
                elif test.get('name') == loader_name:
                    loader_ids.add(test_id)
                else:
                    reject('unknown_hidden' if test.get('hidden') is True else 'unknown_visible')
            elif event.get('type') == 'testDone':
                test_id = event.get('testID')
                if type(test_id) is not int or (test_id not in ids and test_id not in loader_ids):
                    reject('invalid_done')
                    continue
                if test_id in loader_ids:
                    if test_id in loader_completed:
                        reject('duplicate_done')
                    if event.get('hidden') is not True or event.get('result') != 'success' or event.get('skipped') is not False:
                        reject('invalid_done')
                    loader_completed.add(test_id)
                    continue
                code = ids[test_id]
                if code in completed or proof['outcomes'][code] != 'started':
                    reject('duplicate_done')
                completed.add(code)
                proof['outcomes'][code] = (
                    'passed' if event.get('result') == 'success' and event.get('skipped') is False and event.get('hidden') is False else 'failed')
            elif event.get('type') == 'done':
                done_count += 1
                done = event.get('success') is True
        if not invalid and result.returncode == 0 and done and done_count == 1 and loader_ids == loader_completed and len(seen) == len(NAMES) and len(completed) == len(NAMES) and all(value == 'passed' for value in proof['outcomes'].values()):
            proof['outcome'] = 'passed'
        diagnostic.update(phase='complete', started=len(seen), completed=len(completed),
                          terminalCount=min(100, done_count), terminalSuccess=done)
    except subprocess.TimeoutExpired:
        diagnostic['phase'] = 'timeout'
    except Exception:
        # Timeout, crash, guard and parse failures retain fixed failed outcomes;
        # no raw output, exception, stack or data is written or printed.
        diagnostic['phase'] = 'guard' if diagnostic['phase'] == 'guard' else 'runner_failure'
    finally:
        (root / 'ci-logout-machine-diagnostics.json').write_text(json.dumps(diagnostic))
        (root / 'ci-logout-recovery-controls-proof.json').write_text(json.dumps(proof))
    return 0 if proof['outcome'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
