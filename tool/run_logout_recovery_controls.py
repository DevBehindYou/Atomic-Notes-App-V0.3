"""Fixed-code controlled recovery proof; discard all raw machine/log output."""
import json
import os
from pathlib import Path
import subprocess

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
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions controlled proof required')
    proof = {'version': 1, 'scope': SCOPE,
             'outcomes': {code: 'not_executed' for code in NAMES.values()},
             'outcome': 'failed'}
    ids = {}
    seen = set()
    invalid = False
    process = subprocess.Popen(['flutter', 'test', '--no-pub', '--machine',
                                'test/logout_same_owner_recovery_test.dart'],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True, encoding='utf-8', errors='replace')
    try:
        for line in process.stdout:
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                invalid = True
                continue
            if not isinstance(event, dict):
                invalid = True
                continue
            if event.get('type') == 'testStart' and isinstance(event.get('test'), dict):
                test = event['test']
                code = NAMES.get(test.get('name'))
                if code is not None:
                    if code in seen or not isinstance(test.get('id'), int) or test['id'] in ids:
                        invalid = True
                        continue
                    seen.add(code)
                    ids[test['id']] = code
                    proof['outcomes'][code] = 'started'
            elif event.get('type') == 'testDone' and event.get('testID') in ids:
                if proof['outcomes'][ids[event['testID']]] != 'started':
                    invalid = True
                proof['outcomes'][ids[event['testID']]] = (
                    'passed' if event.get('result') == 'success' and not event.get('skipped') else 'failed')
        exit_code = process.wait()
        if not invalid and exit_code == 0 and len(seen) == len(NAMES) and all(value == 'passed' for value in proof['outcomes'].values()):
            proof['outcome'] = 'passed'
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        process.stdout.close()
        Path('ci-logout-recovery-controls-proof.json').write_text(json.dumps(proof))
    if proof['outcome'] != 'passed':
        raise RuntimeError('Controlled logout recovery proof failed; inspect fixed outcome codes')


if __name__ == '__main__':
    main()
