"""CI-only same-owner handoff: fresh owned database per fixed scenario."""
import json
import os
from pathlib import Path

from run_server_wire_fixture import run_fixture

CASES = ('paid_commit_loss', 'completed_old_session')
SCOPE = 'explicit same-owner logout recovery; real Hive HTTP Mongo; synthetic auth vault Drive'


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Dedicated GitHub Actions disposable fixture required')
    proof = {'version': 1, 'scope': SCOPE, 'outcomes': {}, 'cleanup': {}}
    try:
        for code in CASES:
            proof['outcomes'][code] = 'starting'
            run_fixture('test/logout_same_owner_wire_integration_test.dart',
                        fixture_args=('--logout-sync',),
                        dart_defines=(f'--dart-define=ATOMIC_RECOVERY_CASE={code}',))
            proof['cleanup'][code] = 'owned_namespace_removed'
            result = json.loads(Path(f'ci-recovery-handoff-{code}.json').read_text())
            if result != {'version': 1, 'case': code, 'outcome': 'passed', 'phase': 'complete'}:
                raise RuntimeError('Recovery handoff proof rejected')
            proof['outcomes'][code] = 'passed'
    finally:
        for code in CASES:
            artifact = Path(f'ci-recovery-handoff-{code}.json')
            if proof['outcomes'].get(code) == 'starting' and artifact.is_file():
                result = json.loads(artifact.read_text())
                if result.get('case') == code and result.get('phase') in {
                    'setup', 'preparing', 'first_logout', 'restart', 'commit_loss', 'retry', 'checking', 'complete'}:
                    proof['outcomes'][code] = 'failed_' + result['phase']
        Path('ci-logout-handoff-server-wire-proof.json').write_text(json.dumps(proof))


if __name__ == '__main__':
    main()
