"""CI-only logout acceptance: a fresh owned fixture/database per scenario."""
import json
import os
from pathlib import Path

from run_server_wire_fixture import run_fixture

CASES = (
    'paid_logout',
    'emergency_logout',
    'lost_push_restart',
    'lost_completion_restart',
    'paid_second_batch_restart',
    'partial_failure_retry',
    'conflict_copy_retry',
)
SCOPE = 'real Flutter API/repository/Hive to opt-in notes/auth/admin routes; disposable Mongo; fake Drive'


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions disposable fixture required')
    proof = {'version': 1, 'scope': SCOPE, 'outcomes': {}, 'cleanup': {}}
    try:
        for code in CASES:
            proof['outcomes'][code] = 'starting'
            run_fixture('test/logout_server_wire_integration_test.dart',
                        fixture_args=('--logout-sync',),
                        dart_defines=(f'--dart-define=ATOMIC_LOGOUT_CASE={code}',))
            # run_fixture returns only after graceful close and catalog proof.
            proof['cleanup'][code] = 'owned_namespace_removed'
            artifact = Path(f'ci-logout-wire-{code}.json')
            result = json.loads(artifact.read_text())
            if result != {'version': 1, 'case': code, 'outcome': 'passed', 'phase': 'complete'}:
                raise RuntimeError('Logout wire proof rejected')
            proof['outcomes'][code] = 'passed'
    finally:
        # Fixed codes only. Never capture tokens, IDs, note text or raw logs.
        for code in CASES:
            artifact = Path(f'ci-logout-wire-{code}.json')
            if proof['outcomes'].get(code) == 'starting' and artifact.is_file():
                result = json.loads(artifact.read_text())
                if result.get('case') == code and result.get('phase') in {
                    'setup', 'preparing', 'first_logout', 'restart', 'retry', 'checking', 'complete'
                }:
                    proof['outcomes'][code] = 'failed_' + result['phase']
        Path('ci-logout-server-wire-proof.json').write_text(json.dumps(proof))


if __name__ == '__main__':
    main()
