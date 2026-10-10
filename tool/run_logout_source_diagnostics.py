"""Repair-only analyzer metadata. Never retain messages, paths or raw streams."""
import json
import os
from pathlib import Path
import re
import subprocess

FILES = {'lib/api/atomic_notes_api.dart', 'lib/database/logout_plan.dart',
         'lib/database/notes_logout.dart', 'lib/database/notes_repository.dart',
         'test/logout_recovery_receipts_test.dart', 'test/logout_same_owner_recovery_test.dart',
         'test/logout_same_owner_wire_integration_test.dart'}
CODES = {'argument_type_not_assignable', 'invalid_override', 'undefined_method',
         'undefined_getter', 'ambiguous_import', 'unnecessary_non_null_assertion',
         'unused_import', 'prefer_const_constructors', 'dead_code',
         'invalid_use_of_protected_member', 'return_of_invalid_type',
         'missing_required_argument', 'not_enough_positional_arguments',
         'extra_positional_arguments', 'assignment_to_final_local',
         'undefined_identifier', 'unnecessary_cast', 'avoid_dynamic_calls',
         'invalid_annotation', 'unused_local_variable', 'unused_element',
         'override_on_non_overriding_member', 'unchecked_use_of_nullable_value',
         'const_with_non_const', 'undefined_named_parameter',
         'type_argument_not_matching_bounds', 'non_abstract_class_inherits_abstract_member',
         'undefined_operator', 'curly_braces_in_flow_control_structures'}


def main():
    root = Path(__file__).resolve().parent.parent
    head = os.environ.get('ATOMIC_REPAIR_SOURCE_HEAD', '')
    report = {'version': 1, 'scope': 'redacted changed-source analyzer diagnostics',
              'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
              'phase': 'guard', 'outcome': 'incomplete', 'diagnostics': []}
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or report['sourceHead'] is None:
            raise ValueError('guard')
        report['phase'] = 'analyzing'
        result = subprocess.run(['flutter', 'analyze', '--no-pub', '--fatal-warnings',
                                 '--fatal-infos', '--no-preamble'], cwd=root,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=180, check=False, encoding='utf-8', errors='replace',
                                env={**os.environ, 'NO_COLOR': '1'})
        invalid, terminal = False, False
        for raw in result.stdout.splitlines():
            line = re.sub(r'\x1b\[[0-9;]*m', '', raw).strip()
            if re.fullmatch(r'(\d+ issues? found\.|No issues found!) \(ran in [0-9.]+s\)', line):
                terminal = True
                continue
            fields = line.split(' • ')
            if len(fields) != 4:
                continue
            severity, _, location, code = fields
            match = re.fullmatch(r'(.+):(\d+):(\d+)', location)
            if severity not in {'error', 'warning', 'info'} or code not in CODES or match is None:
                invalid = True
                continue
            filename, row, column = match.groups()
            filename = filename.replace('\\', '/')
            if filename not in FILES or len(report['diagnostics']) >= 100:
                invalid = True
                continue
            row, column = int(row), int(column)
            source = (root / filename).read_text(encoding='utf-8').splitlines()
            if not (1 <= row <= len(source) and 1 <= column <= len(source[row - 1]) + 1):
                invalid = True
                continue
            report['diagnostics'].append({'file': filename, 'line': row,
                                          'column': column, 'severity': severity, 'code': code})
        if terminal and not invalid and result.returncode in {0, 1}:
            report['phase'] = 'complete'
            report['outcome'] = ('issues' if report['diagnostics'] else
                                 'clean' if result.returncode == 0 else 'incomplete')
    except subprocess.TimeoutExpired:
        report['phase'] = 'timeout'
    except Exception:
        report['phase'] = 'guard' if report['phase'] == 'guard' else 'runner_failure'
    (root / 'ci-logout-source-diagnostics.json').write_text(json.dumps(report))


if __name__ == '__main__':
    main()
