"""Exercise the workflow's real provenance verifier with public APK metadata fixtures."""
import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/staging-android.yml'


class StagingVersionTest(unittest.TestCase):
    certificate = b'public-certificate-fixture'

    def certs(self, label='Signer #1', certificate=None):
        data = self.certificate if certificate is None else certificate
        return (label + ' certificate SHA-1 digest: ' + hashlib.sha1(data).hexdigest() + '\n'
                + label + ' certificate SHA-256 digest: ' + hashlib.sha256(data).hexdigest() + '\n'
                + '-----BEGIN CERTIFICATE-----\n' + base64.b64encode(data).decode() + '\n'
                + '-----END CERTIFICATE-----\n')

    def verify(self, version_code, version_name='2.03.9', cert_output=None):
        workflow = WORKFLOW.read_text(encoding='utf-8')
        step = workflow.split('      - name: Verify APK identity, signer, embedded configuration and provenance\n', 1)[1]
        body = step.split("          python3 - <<'PY'\n", 1)[1].split('\n          PY', 1)[0]
        script = '\n'.join(line[10:] for line in body.splitlines())
        with tempfile.TemporaryDirectory(prefix='.staging-version-test-', dir=ROOT) as directory:
            folder = Path(directory)
            (folder / 'pubspec.yaml').write_text('version: 2.03.9+9\n')
            (folder / 'staging-badging.txt').write_text(
                f"package: name='com.notes.atomic.staging' versionCode='{version_code}' versionName='{version_name}'\n"
                "application-label:'Atomic Staging'\n"
                "launchable-activity: name='com.notes.atomic.MainActivity' label=''\n"
                "native-code: 'arm64-v8a'\n")
            (folder / 'staging-certs.txt').write_text(
                'Number of signers: 1\n' + self.certs() if cert_output is None else cert_output)
            apk = folder / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
            apk.parent.mkdir(parents=True)
            endpoint = 'https://atomic-notes-app-server-staging.vercel.app/api'
            client = '123456789012-abcdefghijklmnop.apps.googleusercontent.com'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libapp.so', endpoint + '\n' + client)
            environment = {'RUNNER_TEMP': str(folder), 'GITHUB_RUN_NUMBER': '2',
                           'API_BASE_URL': endpoint, 'GOOGLE_SERVER_CLIENT_ID': client,
                           'GITHUB_SHA': 'c' * 40, 'GITHUB_WORKFLOW_REF': 'fixture',
                           'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1',
                           'GITHUB_SERVER_URL': 'https://github.com',
                           'GITHUB_REPOSITORY': 'DevBehindYou/Atomic-Notes-App-V0.3',
                           'GITHUB_STEP_SUMMARY': str(folder / 'summary.md')}
            original = Path.cwd()
            try:
                os.chdir(folder)
                with patch.dict(os.environ, environment), patch('subprocess.check_output', return_value='c' * 40):
                    exec(compile(script, str(WORKFLOW), 'exec'), {})
                return json.loads((folder / 'staging-artifact/provenance.json').read_text())
            finally:
                os.chdir(original)

    def test_arm64_split_version_is_recorded(self):
        # Flutter adds ABI_VERSION(arm64=2) * 1000 to the input build number.
        self.assertEqual(self.verify(2002)['versionCode'], 2002)

    def test_unsplit_version_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Unexpected APK version'):
            self.verify(2)

    def test_wrong_split_version_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Unexpected APK version'):
            self.verify(2003)

    def test_wrong_version_name_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Unexpected APK version'):
            self.verify(2002, '2.03.8')

    def test_sdk_scoped_signer_is_accepted(self):
        output = 'Number of signers: 1\n' + self.certs('Signer (minSdkVersion=28, maxSdkVersion=2147483647)')
        proof = self.verify(2002, cert_output=output)
        expected = ':'.join(f'{byte:02X}' for byte in hashlib.sha256(self.certificate).digest())
        self.assertEqual(proof['certificateFingerprints']['SHA-256'], expected)

    def test_repeated_identical_certificate_is_accepted(self):
        self.verify(2002, cert_output='Number of signers: 1\n' + self.certs() + self.certs())

    def test_different_certificates_are_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Expected exactly one distinct signing certificate'):
            self.verify(2002, cert_output='Number of signers: 1\n' + self.certs() + self.certs(certificate=b'different-certificate'))

    def test_missing_certificate_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Missing or malformed signing certificate'):
            self.verify(2002, cert_output='Number of signers: 1\n' + self.certs().split('-----BEGIN')[0])

    def test_malformed_certificate_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Missing or malformed signing certificate'):
            self.verify(2002, cert_output='Number of signers: 1\n-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----\n')

    def test_multiple_signers_are_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'Expected exactly one staging signer'):
            self.verify(2002, cert_output='Number of signers: 2\n' + self.certs())


if __name__ == '__main__':
    unittest.main()
