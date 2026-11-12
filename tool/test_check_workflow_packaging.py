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


if __name__ == '__main__':
    unittest.main()
