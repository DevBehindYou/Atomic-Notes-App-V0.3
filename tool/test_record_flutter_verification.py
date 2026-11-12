"""Tests for tool/record_flutter_verification.py (deferred Android packaging)."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from record_flutter_verification import build_report  # noqa: E402

HEAD = 'a' * 40


def env(**overrides):
    values = {'GITHUB_ACTIONS': 'true', 'ATOMIC_VERIFY_SOURCE_HEAD': HEAD,
              'ATOMIC_VERIFY_ANALYZE': 'success', 'ATOMIC_VERIFY_TESTS': 'success',
              'ATOMIC_VERIFY_BUILD': 'skipped', 'ATOMIC_VERIFY_APKUPLOAD': 'skipped',
              'ATOMIC_VERIFY_PACKAGING': 'deferred'}
    values.update(overrides)
    return {k: v for k, v in values.items() if v is not None}


class RecordTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        (self.root / 'pubspec.lock').write_text('packages: {}\n')

    def tearDown(self):
        self.dir.cleanup()

    def make_apk(self, size=600_000):
        apk = self.root / 'build/app/outputs/flutter-apk/app-debug.apk'
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b'x' * size)

    def test_deferred_packaging_passes_on_analysis_and_tests_only(self):
        report = build_report(self.root, env())
        self.assertEqual(report['outcome'], 'pass')
        self.assertEqual(report['packaging'], 'deferred')
        self.assertEqual(report['steps']['build'], 'deferred')
        self.assertEqual(report['steps']['apkUpload'], 'deferred')
        self.assertIsNone(report['apk'])
        self.assertIn('deferred', report['scope'])

    def test_deferred_never_reports_an_apk_check_as_passed(self):
        report = build_report(self.root, env())
        self.assertNotEqual(report['steps']['build'], 'success')
        self.assertNotEqual(report['steps']['apkUpload'], 'success')

    def test_deferred_fails_when_an_apk_was_built_anyway(self):
        self.make_apk()
        self.assertEqual(build_report(self.root, env())['outcome'], 'fail')

    def test_deferred_fails_when_apk_steps_ran(self):
        for step in ('ATOMIC_VERIFY_BUILD', 'ATOMIC_VERIFY_APKUPLOAD'):
            for value in ('success', 'failure', ''):
                report = build_report(self.root, env(**{step: value}))
                self.assertEqual(report['outcome'], 'fail', (step, value))

    def test_deferred_still_requires_analysis_and_tests(self):
        for step in ('ATOMIC_VERIFY_ANALYZE', 'ATOMIC_VERIFY_TESTS'):
            for value in ('failure', 'skipped', 'cancelled', ''):
                report = build_report(self.root, env(**{step: value}))
                self.assertEqual(report['outcome'], 'fail', (step, value))

    def test_deferred_requires_actions_head_and_lockfile(self):
        self.assertEqual(build_report(self.root, env(GITHUB_ACTIONS=None))['outcome'], 'fail')
        self.assertEqual(build_report(self.root, env(ATOMIC_VERIFY_SOURCE_HEAD='abc'))['outcome'], 'fail')
        (self.root / 'pubspec.lock').unlink()
        self.assertEqual(build_report(self.root, env())['outcome'], 'fail')

    def test_unknown_packaging_mode_fails_closed(self):
        report = build_report(self.root, env(ATOMIC_VERIFY_PACKAGING='maybe'))
        self.assertEqual(report['outcome'], 'fail')
        self.assertEqual(report['packaging'], 'unavailable')

    def test_enabled_packaging_keeps_the_original_apk_requirements(self):
        enabled = env(ATOMIC_VERIFY_PACKAGING='enabled', ATOMIC_VERIFY_BUILD='success',
                      ATOMIC_VERIFY_APKUPLOAD='success')
        self.assertEqual(build_report(self.root, enabled)['outcome'], 'fail', 'no APK yet')
        self.make_apk()
        report = build_report(self.root, enabled)
        self.assertEqual(report['outcome'], 'pass')
        self.assertEqual(report['apk']['bytes'], 600_000)
        skipped = dict(enabled, ATOMIC_VERIFY_APKUPLOAD='skipped')
        self.assertEqual(build_report(self.root, skipped)['outcome'], 'fail')

    def test_missing_packaging_variable_keeps_old_behaviour(self):
        legacy = env(ATOMIC_VERIFY_PACKAGING=None, ATOMIC_VERIFY_BUILD='success',
                     ATOMIC_VERIFY_APKUPLOAD='success')
        self.assertEqual(build_report(self.root, legacy)['outcome'], 'fail', 'no APK')
        self.make_apk()
        self.assertEqual(build_report(self.root, legacy)['outcome'], 'pass')


if __name__ == '__main__':
    unittest.main()
