"""CI-only read-only recovery inspection; a fresh owned localhost namespace."""
import json
import os
from pathlib import Path

from run_server_wire_fixture import run_fixture


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions disposable fixture required')
    proof = {'version': 1, 'scope': 'real App recovery status and receipts; disposable Mongo and Hive; fake Drive',
             'case': 'settled_readonly_inspection', 'outcome': 'starting', 'cleanup': 'pending'}
    try:
        run_fixture('test/logout_recovery_server_wire_test.dart', fixture_args=('--logout-sync',))
        proof['cleanup'] = 'owned_namespace_removed'
        result = json.loads(Path('ci-logout-recovery-wire-case.json').read_text())
        if result != {'version': 1, 'case': proof['case'], 'outcome': 'passed', 'phase': 'complete'}:
            raise RuntimeError('Read-only recovery wire proof rejected')
        proof['outcome'] = 'passed'
    finally:
        artifact = Path('ci-logout-recovery-wire-case.json')
        if proof['outcome'] == 'starting' and artifact.is_file():
            result = json.loads(artifact.read_text())
            if result.get('case') == proof['case'] and result.get('phase') in {
                'setup', 'active_session_refusal', 'settling', 'inspection', 'receipt_delivery', 'checking', 'complete'
            }:
                proof['outcome'] = 'failed_' + result['phase']
        Path('ci-logout-recovery-server-wire-proof.json').write_text(json.dumps(proof))


if __name__ == '__main__':
    main()
