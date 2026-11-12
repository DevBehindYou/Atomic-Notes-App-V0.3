"""Tests for tool/record_flutter_verification.py (deferred Android packaging)."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import record_flutter_verification as recorder  # noqa: E402
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


class DeferredArtifactScanTest(unittest.TestCase):
    """Review R02: no Android package of any kind may pass a deferred proof."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        (self.root / 'pubspec.lock').write_text('packages: {}')

    def tearDown(self):
        self.dir.cleanup()

    def put(self, relative, data=b'x'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def report(self, **kwargs):
        return build_report(self.root, env(), **kwargs)

    def test_reviewer_sentinels_release_apk_and_aab_fail(self):
        for relative in ('build/app/outputs/flutter-apk/app-release.apk',
                         'build/app/outputs/bundle/release/app-release.aab'):
            with self.subTest(relative):
                path = self.put(relative)
                report = self.report()
                self.assertEqual(report['outcome'], 'fail')
                self.assertEqual(report['androidArtifacts'], [relative])
                path.unlink()

    def test_every_generated_package_location_fails(self):
        for relative in (
                'build/app/outputs/flutter-apk/app-debug.apk',
                'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
                'build/app/outputs/flutter-apk/app-armeabi-v7a-profile.apk',
                'build/app/outputs/apk/release/app-release.apk',
                'build/app/outputs/apk/profile/app-profile.apk',
                'build/app/outputs/bundle/profileRelease/app.aab',
                'android/app/build/outputs/apk/debug/app-debug.apk',
                'android/app/build/outputs/bundle/release/app-release.aab',
                'staging-artifact/atomic-staging-arm64.apk',
                'build/app/outputs/universal.apks',
                'build/app/outputs/flutter-apk/APP-RELEASE.APK'):
            with self.subTest(relative):
                path = self.put(relative)
                self.assertEqual(self.report()['outcome'], 'fail')
                path.unlink()

    def test_a_directory_named_like_a_package_fails(self):
        (self.root / 'build/app/outputs/flutter-apk/app.apk').mkdir(parents=True)
        self.assertEqual(self.report()['outcome'], 'fail')

    def test_non_package_outputs_pass(self):
        self.put('build/app/outputs/flutter-apk/output-metadata.json', b'{}')
        self.put('build/app/outputs/mapping/release/mapping.txt')
        self.put('staging-artifact/provenance.json', b'{}')
        report = self.report()
        self.assertEqual(report['outcome'], 'pass')
        self.assertEqual(report['androidArtifacts'], [])

    def test_the_scan_stays_inside_generated_roots(self):
        # Source, assets and fixtures are never read, even if a file there
        # happens to be named like a package.
        self.put('assets/sample.apk')
        self.put('test/fixtures/fake.aab')
        self.assertEqual(self.report()['outcome'], 'pass')

    def test_an_unreadable_root_fails_closed(self):
        self.put('build/app/outputs/flutter-apk/output-metadata.json', b'{}')

        def broken_walk(top, onerror=None, followlinks=False):
            onerror(PermissionError('denied'))
            return iter(())

        report = self.report(walk=broken_walk)
        self.assertEqual(report['outcome'], 'fail')
        self.assertIsNone(report['androidArtifacts'])
        self.assertIn('PermissionError', report['inspectionError'])

    def test_a_root_replaced_by_a_file_fails_closed(self):
        self.put('staging-artifact', b'not a directory')
        report = self.report()
        self.assertEqual(report['outcome'], 'fail')
        self.assertIn('not a directory', report['inspectionError'])

    def test_too_many_entries_fails_closed(self):
        for index in range(5):
            self.put(f'build/app/outputs/logs/{index}.txt')
        saved = recorder.MAX_ENTRIES
        recorder.MAX_ENTRIES = 3
        try:
            report = self.report()
        finally:
            recorder.MAX_ENTRIES = saved
        self.assertEqual(report['outcome'], 'fail')
        self.assertIn('generated entries', report['inspectionError'])

    def test_the_listing_is_bounded(self):
        for index in range(recorder.MAX_LISTED + 5):
            self.put(f'build/app/outputs/flutter-apk/app-{index}.apk')
        report = self.report()
        self.assertEqual(report['outcome'], 'fail')
        self.assertEqual(len(report['androidArtifacts']), recorder.MAX_LISTED)

    def test_enabled_mode_does_not_scan_or_add_fields(self):
        enabled = env(ATOMIC_VERIFY_PACKAGING='enabled', ATOMIC_VERIFY_BUILD='success',
                      ATOMIC_VERIFY_APKUPLOAD='success')
        self.put('build/app/outputs/flutter-apk/app-debug.apk', b'x' * 600_000)
        self.put('build/app/outputs/bundle/release/app-release.aab')
        report = build_report(self.root, enabled)
        self.assertEqual(report['outcome'], 'pass')
        self.assertNotIn('androidArtifacts', report)
        self.assertEqual(report['version'], 2)


if __name__ == '__main__':
    unittest.main()
