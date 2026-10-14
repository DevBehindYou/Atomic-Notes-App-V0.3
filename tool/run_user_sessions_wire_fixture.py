"""CI-only actual session APIs; own generated Mongo and Hive namespace."""
import json
import os
from pathlib import Path
from run_server_wire_fixture import run_fixture

def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions disposable fixture required')
    proof = {'version': 1, 'scope': 'real App session inventory revoke and retained Hive; disposable Mongo; fake Drive',
             'case': 'session_management_hive', 'outcome': 'starting', 'cleanup': 'pending'}
    try:
        run_fixture('test/user_sessions_wire_integration_test.dart')
        proof['cleanup'] = 'owned_namespace_removed'
        result = json.loads(Path('ci-user-sessions-wire-case.json').read_text())
        if result != {'version': 1, 'case': proof['case'], 'outcome': 'passed', 'phase': 'complete'}:
            raise RuntimeError('User session wire proof rejected')
        proof['outcome'] = 'passed'
    finally:
        artifact = Path('ci-user-sessions-wire-case.json')
        if proof['outcome'] == 'starting' and artifact.is_file():
            result = json.loads(artifact.read_text())
            if result.get('case') == proof['case'] and result.get('phase') in {
                'setup', 'inventory_and_current_refusal', 'foreign_handle_noop',
                'revoke_other_and_idempotent_retry', 'real401_retains_hive_and_same_owner_restore', 'complete'}:
                proof['outcome'] = 'failed_' + result['phase']
                line = result.get('failureLine')
                if type(line) is int and 1 <= line <= 1000:
                    proof['failureLine'] = line
        Path('ci-user-sessions-server-wire-proof.json').write_text(json.dumps(proof))

if __name__ == '__main__':
    main()
