"""Tests for tool/check_workflow_packaging.py, including the real workflows."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_workflow_packaging import WorkflowShapeError, main, violations  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

GUARDED_JOB = """name: x
on: [pull_request]
jobs:
  build:
    if: vars.ATOMIC_ANDROID_PACKAGING == 'enabled'
    runs-on: ubuntu-24.04
    steps:
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v6
        with:
          path: build/app/outputs/flutter-apk/app-debug.apk
"""

UNGUARDED_BUILD = """name: x
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - name: Build
        run: flutter build apk --release
"""

UNGUARDED_UPLOAD = """name: x
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/upload-artifact@v6
        with:
          path: out/app-release.aab
"""

STEP_ENV_GUARD = """name: x
on: [pull_request]
jobs:
  flutter:
    runs-on: ubuntu-24.04
    env:
      ATOMIC_ANDROID_PACKAGING: ${{ vars.ATOMIC_ANDROID_PACKAGING == 'enabled' && 'enabled' || 'deferred' }}
    steps:
      - name: Build
        if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'
        run: flutter build apk --debug
"""

STEP_VARS_GUARD = """name: x
on: [pull_request]
jobs:
  flutter:
    runs-on: ubuntu-24.04
    steps:
      - name: Build
        if: vars.ATOMIC_ANDROID_PACKAGING == 'enabled'
        run: flutter build apk --debug
"""

STEP_ENV_GUARD_UNDEFINED = """name: x
on: [pull_request]
jobs:
  flutter:
    runs-on: ubuntu-24.04
    env:
      ATOMIC_ANDROID_PACKAGING: enabled
    steps:
      - name: Build
        if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'
        run: flutter build apk --debug
"""

FOLDED_IF = """name: x
on: [workflow_dispatch]
jobs:
  release:
    if: >-
      github.event_name == 'workflow_dispatch' &&
      vars.ATOMIC_ANDROID_PACKAGING == 'enabled'
    runs-on: ubuntu-24.04
    steps:
      - run: ./gradlew bundleRelease
"""

OTHER_GRADLE_AND_BUNDLETOOL = """name: x
on: [pull_request]
jobs:
  a:
    runs-on: ubuntu-24.04
    steps:
      - run: cd android && ./gradlew assembleDebug
  b:
    runs-on: ubuntu-24.04
    steps:
      - run: java -jar bundletool.jar build-apks --bundle=x.aab
"""

NOT_PACKAGING = """name: x
on: [pull_request]
jobs:
  web:
    runs-on: ubuntu-24.04
    steps:
      - run: flutter build web
      - run: flutter test
      - uses: actions/upload-artifact@v6
        with:
          path: ci-proof.json
"""


class PackagingPolicyTest(unittest.TestCase):
    def check(self, *workflows):
        with tempfile.TemporaryDirectory() as directory:
            for index, text in enumerate(workflows):
                Path(directory, f'w{index}.yml').write_text(text, encoding='utf-8')
            return violations(directory)

    def test_guarded_job_passes(self):
        self.assertEqual(self.check(GUARDED_JOB), [])

    def test_unguarded_build_fails(self):
        self.assertEqual(len(self.check(UNGUARDED_BUILD)), 1)

    def test_unguarded_package_upload_fails(self):
        self.assertEqual(len(self.check(UNGUARDED_UPLOAD)), 1)

    def test_step_guard_on_a_job_env_from_the_variable_is_not_a_guard(self):
        # R12: env can be rewritten by any earlier step or action, so only
        # the repository variable counts (this test used to expect a pass).
        self.assertEqual(len(self.check(STEP_ENV_GUARD)), 1)
        self.assertEqual(self.check(STEP_VARS_GUARD), [])

    def test_step_guard_on_a_hard_coded_env_fails(self):
        self.assertEqual(len(self.check(STEP_ENV_GUARD_UNDEFINED)), 1)

    def test_folded_job_condition_is_read(self):
        self.assertEqual(self.check(FOLDED_IF), [])

    def test_gradle_assemble_and_bundletool_are_packaging(self):
        self.assertEqual(len(self.check(OTHER_GRADLE_AND_BUNDLETOOL)), 2)

    def test_web_builds_tests_and_proof_uploads_are_not_packaging(self):
        self.assertEqual(self.check(NOT_PACKAGING), [])

    def test_unreadable_shape_fails_closed(self):
        with self.assertRaises(WorkflowShapeError):
            self.check('name: x\non: [push]\n')

    def test_the_repository_workflows_are_all_guarded(self):
        self.assertEqual(violations(ROOT / '.github/workflows'), [])


def job(condition=None, env=None, step_lines=('- run: flutter build apk --release',),
        step_indent=6):
    """A one-job workflow; [condition] goes on the job, [env] on the job."""
    lines = ['name: x', 'on: [pull_request]', 'jobs:', '  build:']
    if condition is not None:
        lines.append(f'    if: {condition}')
    lines.append('    runs-on: ubuntu-latest')
    if env is not None:
        lines += ['    env:', f'      ATOMIC_ANDROID_PACKAGING: {env}']
    lines.append('    steps:')
    lines += [' ' * step_indent + line for line in step_lines]
    return '\n'.join(lines) + '\n'


DERIVED = ("${{ vars.ATOMIC_ANDROID_PACKAGING == 'enabled' && 'enabled' "
           "|| 'deferred' }}")


class ReviewR08Test(unittest.TestCase):
    """Codex review R08: a guard must require the opt-in; unread shapes fail."""

    def accepted(self, workflow):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'w.yml').write_text(workflow, encoding='utf-8')
            try:
                return not violations(directory)
            except WorkflowShapeError:
                return False

    def test_reviewer_fixtures(self):
        cases = {
            'unguarded': (job(), False),
            'job-or-true': (job("vars.ATOMIC_ANDROID_PACKAGING == 'enabled' || true"), False),
            'unsupported-step-indent': (job(step_indent=4), False),
            'step-env-override': (job(env=DERIVED, step_lines=(
                "- if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                '  env:',
                '    ATOMIC_ANDROID_PACKAGING: enabled',
                '  run: flutter build apk --release')), False),
            'guard-comment': (job("always() # vars.ATOMIC_ANDROID_PACKAGING == 'enabled'"), False),
            'legitimate-guard': (job("vars.ATOMIC_ANDROID_PACKAGING == 'enabled'"), True),
        }
        for name, (workflow, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.accepted(workflow), expected)

    def test_conditions_that_do_not_require_the_opt_in(self):
        for condition in (
                "!(vars.ATOMIC_ANDROID_PACKAGING == 'enabled')",
                "always() && vars.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                "vars.ATOMIC_ANDROID_PACKAGING != 'enabled'",
                "vars.ATOMIC_ANDROID_PACKAGING == 'enabled ' ",
                "vars.ATOMIC_ANDROID_PACKAGING == 'Enabled'",
                "\"vars.ATOMIC_ANDROID_PACKAGING == 'enabled'\"",
                "${{ vars.ATOMIC_ANDROID_PACKAGING == 'enabled' }} || true",
                "contains('vars.ATOMIC_ANDROID_PACKAGING == enabled', 'x')",
                "github.ref == 'refs/heads/main' || vars.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                "env.ATOMIC_ANDROID_PACKAGING == 'enabled'"):  # env is not a job guard
            with self.subTest(condition):
                self.assertFalse(self.accepted(job(condition)))

    def test_conditions_that_do_require_the_opt_in(self):
        for condition in (
                "vars.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                "${{ vars.ATOMIC_ANDROID_PACKAGING == 'enabled' }}",
                "github.event_name == 'pull_request' && vars.ATOMIC_ANDROID_PACKAGING == 'enabled'"):
            with self.subTest(condition):
                self.assertTrue(self.accepted(job(condition)))

    def test_env_guards_never_count_and_vars_step_guards_do(self):
        # R12: this test used to accept the job-derived env guard. Every env
        # form is now refused; the same steps guarded by vars pass.
        env_guarded = ("- if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                       '  run: flutter build apk --release')
        vars_guarded = ("- if: vars.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                        '  run: flutter build apk --release')
        self.assertFalse(self.accepted(job(env=DERIVED, step_lines=env_guarded)))
        self.assertFalse(self.accepted(job(env="'enabled'", step_lines=env_guarded)))
        self.assertFalse(self.accepted(job(step_lines=env_guarded)))
        self.assertTrue(self.accepted(job(env=DERIVED, step_lines=vars_guarded)))
        self.assertTrue(self.accepted(job(step_lines=vars_guarded)))
        writes = ('- run: echo "ATOMIC_ANDROID_PACKAGING=enabled" >> "$GITHUB_ENV"',
                  *vars_guarded)
        self.assertTrue(self.accepted(job(env=DERIVED, step_lines=writes)))
        other_write = ('- run: echo "ATOMIC_CI_CANARY=x" >> "$GITHUB_ENV"', *vars_guarded)
        self.assertTrue(self.accepted(job(env=DERIVED, step_lines=other_write)))
        combined = ("- if: steps.scan.outcome == 'success' && "
                    "vars.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                    '  run: flutter build apk --release')
        self.assertTrue(self.accepted(job(step_lines=combined)))

    def test_shapes_it_cannot_read_fail_closed(self):
        reusable = ('name: x\non: [push]\njobs:\n  build:\n'
                    '    uses: ./.github/workflows/other.yml\n')
        flow_steps = ('name: x\non: [push]\njobs:\n  build:\n    runs-on: x\n'
                      '    steps: [{run: flutter build apk}]\n')
        for name, workflow in {
                'reusable job': reusable,
                'flow-style steps': flow_steps,
                'tab': job().replace('      - run', '\t- run'),
                'anchor': job(step_lines=('- &build', '  run: flutter build apk --release')),
                'local action': job(step_lines=('- uses: ./.github/actions/package',)),
                'seven-space step key': job(step_lines=('- name: Build',
                                                         ' run: flutter build apk')),
        }.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as directory:
                Path(directory, 'w.yml').write_text(workflow, encoding='utf-8')
                with self.assertRaises(WorkflowShapeError):
                    violations(directory)


GUARD = "vars.ATOMIC_ANDROID_PACKAGING == 'enabled'"
HEAD = 'name: x\non: [pull_request]\njobs:\n'


class ReviewR12Test(unittest.TestCase):
    """Codex review R12: every structure is read or refused, never skipped."""

    def outcome(self, workflow):
        """'accepted', 'violation' or 'refused' (WorkflowShapeError)."""
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'w.yml').write_bytes(
                workflow if isinstance(workflow, bytes) else workflow.encode('utf-8'))
            try:
                return 'violation' if violations(directory) else 'accepted'
            except WorkflowShapeError:
                return 'refused'

    def test_reviewer_packet_4_probes(self):
        derived_job = ('  build:\n    runs-on: ubuntu-latest\n    env:\n'
                       f'      ATOMIC_ANDROID_PACKAGING: {DERIVED}\n    steps:\n')
        cases = {
            'quoted-steps-key': (
                '  build:\n    runs-on: ubuntu-latest\n    "steps":\n'
                '      - run: flutter build apk --release\n', 'refused'),
            'job-fields-six-spaces': (
                '  build:\n      runs-on: ubuntu-latest\n      steps:\n'
                '        - run: flutter build apk --release\n', 'refused'),
            'flow-step-env': (
                derived_job + "      - if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'\n"
                '        env: {ATOMIC_ANDROID_PACKAGING: enabled}\n'
                '        run: flutter build apk --release\n', 'refused'),
            'quoted-step-env': (
                derived_job + "      - if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'\n"
                '        "env":\n          ATOMIC_ANDROID_PACKAGING: enabled\n'
                '        run: flutter build apk --release\n', 'refused'),
            'github-env-indirection': (
                derived_job + '      - run: |\n          TARGET=ATOMIC_ANDROID_PACKAGING\n'
                '          printf "%s=enabled\\n" "$TARGET" >> "$GITHUB_ENV"\n'
                "      - if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'\n"
                '        run: flutter build apk --release\n', 'violation'),
            'folded-conjunction-control': (
                "  build:\n    if: >-\n      github.event_name == 'push' &&\n"
                f'      {GUARD}\n    runs-on: ubuntu-latest\n    steps:\n'
                '      - run: flutter build apk --release\n', 'accepted'),
            'wrapped-conjunction-control': (
                f"  build:\n    if: ${{{{ {GUARD} && github.event_name != 'x' }}}}\n"
                '    runs-on: ubuntu-latest\n    steps:\n'
                '      - run: flutter build apk --release\n', 'accepted'),
            'negation-control': (
                f'  build:\n    if: ${{{{ !({GUARD}) }}}}\n    runs-on: ubuntu-latest\n'
                '    steps:\n      - run: flutter build apk --release\n', 'violation'),
        }
        for name, (jobs, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.outcome(HEAD + jobs), expected)

    def test_structures_it_cannot_read_are_refused(self):
        build = '      - run: flutter build apk --release\n'
        guarded = f'    if: {GUARD}\n'
        cases = {
            'quoted top-level key': 'name: x\non: [pull_request]\n"jobs":\n'
                                    '  build:\n    runs-on: x\n    steps:\n' + build,
            'unknown top-level key': 'name: x\non: [pull_request]\nenv:\n  A: b\njobs:\n'
                                     '  build:\n    runs-on: x\n    steps:\n' + build,
            'duplicate jobs key': HEAD + '  a:\n    runs-on: x\n    steps:\n' + build
                                  + 'jobs:\n  b:\n    runs-on: x\n    steps:\n' + build,
            'document marker': '---\n' + HEAD + '  build:\n    runs-on: x\n    steps:\n' + build,
            'quoted job id': HEAD + '  "build":\n    runs-on: x\n    steps:\n' + build,
            'inline job': HEAD + '  build: {runs-on: x}\n',
            'quoted job key': HEAD + "  build:\n    'if': x\n    runs-on: x\n    steps:\n" + build,
            'explicit key': HEAD + '  build:\n    ? steps\n    runs-on: x\n    steps:\n' + build,
            'job keys at three spaces': HEAD + '  build:\n   runs-on: x\n   steps:\n' + build,
            'job keys at five spaces': HEAD + '  build:\n     runs-on: x\n     steps:\n' + build,
            'unknown job key': HEAD + '  build:\n    runs-on: x\n    container: y\n    steps:\n' + build,
            'reusable job': HEAD + '  build:\n    uses: org/repo/.github/workflows/w.yml@v1\n',
            'duplicate job key': HEAD + '  build:\n' + guarded + '    if: always()\n'
                                 '    runs-on: x\n    steps:\n' + build,
            'duplicate steps': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                               '      - run: echo ok\n    steps:\n' + build,
            'no steps': HEAD + '  build:\n    runs-on: x\n',
            'empty steps': HEAD + '  build:\n    runs-on: x\n    steps:\n  other:\n'
                           '    runs-on: x\n    steps:\n' + build,
            'inline job env': HEAD + '  build:\n    runs-on: x\n    env: {A: b}\n    steps:\n' + build,
            'job env entry at eight': HEAD + '  build:\n    runs-on: x\n    env:\n'
                                      '        A: b\n    steps:\n' + build,
            'job env flow value': HEAD + '  build:\n    runs-on: x\n    env:\n'
                                  '      A: [b]\n    steps:\n' + build,
            'runs-on flow list': HEAD + '  build:\n    runs-on: [self-hosted]\n    steps:\n' + build,
            'name continued': HEAD + '  build:\n    name: one\n      two\n    runs-on: x\n'
                              '    steps:\n' + build,
            'key without space': HEAD + '  build:\n    runs-on:x\n    steps:\n' + build,
            'flow step': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                         '      - {run: flutter build apk}\n',
            'bare dash': HEAD + '  build:\n    runs-on: x\n    steps:\n      -\n'
                         '        run: flutter build apk\n',
            'extra spaces after dash': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                       '      -   run: flutter build apk\n',
            'quoted step key': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                               '      - "run": flutter build apk\n',
            'unknown step key': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                '      - run: flutter build apk\n        working-directory: a\n',
            'duplicate step key': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                  f'      - if: {GUARD}\n        if: always()\n'
                                  '        run: flutter build apk\n',
            'step key at nine': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                '      - name: a\n         run: flutter build apk\n',
            'step env entry at twelve': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                        '      - run: flutter build apk\n        env:\n'
                                        '            A: b\n',
            'quoted step env name': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                    '      - run: flutter build apk\n        env:\n'
                                    '          "A": b\n',
            'inline with': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                           '      - uses: actions/upload-artifact@v6\n'
                           '        with: {path: app.apk}\n',
            'quoted with key': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                               '      - uses: actions/upload-artifact@v6\n        with:\n'
                               "          'path': app.apk\n",
            'flow run': HEAD + '  build:\n    runs-on: x\n    steps:\n'
                        '      - run: [flutter build apk]\n',
            # A YAML reader may break the line inside the comment and see a
            # second `if:` that this reader would not.
            **{f'comment hiding an if after {name}': HEAD + '  build:\n' + guarded
               + '    # note' + separator + '    if: always()\n    runs-on: x\n'
               '    steps:\n' + build
               for name, separator in (('a carriage return', '\r'),
                                       ('a next line', chr(0x85)),
                                       ('a line separator', chr(0x2028)),
                                       ('a paragraph separator', chr(0x2029)))},
            'byte order mark': chr(0xfeff) + HEAD + '  build:\n    runs-on: x\n    steps:\n' + build,
            'control character': HEAD + '  build:\n    runs-on: x' + chr(0) + '\n    steps:\n' + build,
            'not utf-8': (HEAD + '  build:\n    runs-on: x\n    steps:\n' + build).encode('utf-8')
                         + b'      - run: echo \xff\n',
        }
        for name, workflow in cases.items():
            with self.subTest(name):
                self.assertEqual(self.outcome(workflow), 'refused')

    def test_conditions_are_read_whole(self):
        build = ('    runs-on: x\n    steps:\n      - run: flutter build apk --release\n')
        step = '    runs-on: x\n    steps:\n      - if: {}\n{}        run: flutter build apk\n'
        cases = {
            'job plain continued by || true': (
                f'  build:\n    if: {GUARD}\n      || true\n' + build, 'violation'),
            'step plain continued by || true': (
                '  build:\n' + step.format(GUARD, '          || true\n'), 'violation'),
            'job plain continued by a conjunct': (
                f"  build:\n    if: {GUARD}\n      && github.ref == 'refs/heads/main'\n" + build,
                'accepted'),
            'comment after a one-line step guard': (
                '  build:\n' + step.format(GUARD, '        # why it is guarded\n'), 'accepted'),
            'line continued after a comment': (
                f'  build:\n    if: {GUARD}\n      # note\n      || true\n' + build, 'violation'),
            'folded block hiding a comment': (
                f'  build:\n    if: >-\n      {GUARD} &&\n      # always()\n' + build,
                'violation'),
            'literal block': (f'  build:\n    if: |\n      {GUARD}\n' + build, 'violation'),
            'quoted whole condition': (f'  build:\n    if: "{GUARD}"\n' + build, 'violation'),
        }
        for name, (jobs, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.outcome(HEAD + jobs), expected)

    def test_packaging_commands_are_recognised(self):
        def outcome(command):
            return self.outcome(HEAD + '  build:\n    runs-on: x\n    steps:\n'
                                f'      - run: {command}\n')
        for command in ('flutter --verbose build apk', 'flutter build appbundle',
                        'flutter build ${{ matrix.target }}', 'flutter build "$TARGET"',
                        'flutter build aar', './gradlew installDebug',
                        'cd android && ./gradlew packageRelease'):
            with self.subTest(command):
                self.assertEqual(outcome(command), 'violation')
        for command in ('flutter build web', 'flutter build ios --no-codesign',
                        'flutter build linux', 'flutter test', './gradlew test'):
            with self.subTest(command):
                self.assertEqual(outcome(command), 'accepted')

    def test_the_supported_job_shapes_are_read(self):
        workflow = HEAD + (
            '  build:\n    name: Build ${{ matrix.mode }}\n'
            f'    if: {GUARD}\n    runs-on: ubuntu-24.04\n    timeout-minutes: 30\n'
            '    strategy:\n      fail-fast: false\n      matrix:\n        mode: [debug, profile]\n'
            '    defaults:\n      run:\n        shell: bash\n'
            "    env:\n      A: 'true'\n    environment:\n      name: pages\n"
            '      url: ${{ steps.d.outputs.page_url }}\n    steps:\n'
            '      - uses: actions/checkout@v5 # v5\n        with:\n          persist-credentials: false\n'
            '          path: |\n            a\n            b\n'
            '      - name: Build\n        id: build\n        shell: bash\n'
            '        continue-on-error: true\n        env:\n          B: ${{ github.sha }}\n'
            '        run: |\n          flutter build apk --${{ matrix.mode }}\n'
            '  web:\n    runs-on: x\n    environment: github-pages\n    steps:\n'
            '      - run: flutter build web\n')
        self.assertEqual(self.outcome(workflow), 'accepted')
        self.assertEqual(self.outcome(workflow.replace(f'    if: {GUARD}\n', '')), 'violation')

    def test_main_exit_codes(self):
        for workflow, code in ((job(GUARD), 0), (job(), 1), ('name: x\n', 2)):
            with self.subTest(code), tempfile.TemporaryDirectory() as directory:
                Path(directory, 'w.yml').write_text(workflow, encoding='utf-8')
                self.assertEqual(main(['check', directory]), code)


if __name__ == '__main__':
    unittest.main()
