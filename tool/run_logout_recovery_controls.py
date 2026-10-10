"""Fixed-code controlled recovery proof; discard all raw machine/log output."""
import json
import os
from pathlib import Path
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
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise ValueError('guard')
        result = subprocess.run(['flutter', 'test', '--no-pub', '--machine',
                                 'test/logout_same_owner_recovery_test.dart'],
                                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=180, check=False, encoding='utf-8', errors='replace')
        ids, loader_ids, seen, completed = {}, set(), set(), set()
        invalid, done = False, False
        done_count = 0
        loader_name = 'loading ' + str(root / 'test/logout_same_owner_recovery_test.dart')
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                invalid = True
                continue
            if not isinstance(event, dict):
                invalid = True
                continue
            if event.get('type') == 'testStart':
                test = event.get('test')
                if not isinstance(test, dict) or type(test.get('id')) is not int:
                    invalid = True
                    continue
                test_id = test['id']
                code = NAMES.get(test.get('name'))
                if test_id in ids or test_id in loader_ids:
                    invalid = True
                    continue
                if code is not None:
                    if code in seen or test.get('hidden') is True:
                        invalid = True
                        continue
                    seen.add(code)
                    ids[test_id] = code
                    proof['outcomes'][code] = 'started'
                elif test.get('name') == loader_name and test.get('hidden') is True:
                    loader_ids.add(test_id)
                else:
                    invalid = True
            elif event.get('type') == 'testDone':
                test_id = event.get('testID')
                if type(test_id) is not int or (test_id not in ids and test_id not in loader_ids):
                    invalid = True
                    continue
                if test_id in loader_ids:
                    continue
                code = ids[test_id]
                if code in completed or proof['outcomes'][code] != 'started':
                    invalid = True
                completed.add(code)
                proof['outcomes'][code] = (
                    'passed' if event.get('result') == 'success' and event.get('skipped') is False else 'failed')
            elif event.get('type') == 'done':
                done_count += 1
                done = event.get('success') is True
        if not invalid and result.returncode == 0 and done and done_count == 1 and len(seen) == len(NAMES) and len(completed) == len(NAMES) and all(value == 'passed' for value in proof['outcomes'].values()):
            proof['outcome'] = 'passed'
    except Exception:
        # Timeout, crash, guard and parse failures retain fixed failed outcomes;
        # no raw output, exception, stack or data is written or printed.
        pass
    finally:
        (root / 'ci-logout-recovery-controls-proof.json').write_text(json.dumps(proof))
    return 0 if proof['outcome'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
