"""Tests for tool/check_workflow_packaging.py, including the real workflows."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_workflow_packaging import WorkflowShapeError, violations  # noqa: E402

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

    def test_step_guard_on_a_job_env_from_the_variable_passes(self):
        self.assertEqual(self.check(STEP_ENV_GUARD), [])

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

    def test_env_guard_needs_the_derived_job_env_and_no_override(self):
        guarded = ("- if: env.ATOMIC_ANDROID_PACKAGING == 'enabled'",
                   '  run: flutter build apk --release')
        self.assertTrue(self.accepted(job(env=DERIVED, step_lines=guarded)))
        self.assertFalse(self.accepted(job(env="'enabled'", step_lines=guarded)))
        self.assertFalse(self.accepted(job(step_lines=guarded)))
        writes = ('- run: echo "ATOMIC_ANDROID_PACKAGING=enabled" >> "$GITHUB_ENV"',
                  *guarded)
        self.assertFalse(self.accepted(job(env=DERIVED, step_lines=writes)))
        other_write = ('- run: echo "ATOMIC_CI_CANARY=x" >> "$GITHUB_ENV"', *guarded)
        self.assertTrue(self.accepted(job(env=DERIVED, step_lines=other_write)))

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


if __name__ == '__main__':
    unittest.main()
