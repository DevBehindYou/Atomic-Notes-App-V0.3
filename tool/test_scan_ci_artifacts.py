import json
import os
from pathlib import Path
import tempfile
import unittest

import scan_ci_artifacts as scanner

CANARY = 'canary-' + 'c' * 32


class ScanCiArtifactsTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        self._cwd = os.getcwd()
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self._cwd)
        self._dir.cleanup()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return name

    def test_clean_artifacts_pass_with_a_working_canary(self):
        self.write('ci-a-proof.json', '{"outcome":"pass"}')
        self.write('previews/one.png', 'not really a png')
        report = scanner.scan(['ci-*.json', 'previews'], {'ATOMIC_CI_CANARY': CANARY})
        self.assertEqual(report['outcome'], 'pass')
        self.assertEqual([report['scanned'], report['skippedBinary']], [1, 1])

    def test_without_a_canary_the_scan_is_not_trusted(self):
        self.write('ci-a-proof.json', '{}')
        self.assertEqual(scanner.scan(['ci-a-proof.json'], {})['outcome'], 'fail')
        self.assertFalse(scanner.scan(['ci-a-proof.json'], {'ATOMIC_CI_CANARY': 'short'})['canaryDetected'])

    def test_leaked_secret_or_canary_fails_without_echoing_it(self):
        secret = 'S3cretValue-for-the-test-only'
        self.write('ci-ok.json', '{}')
        self.write('ci-leak.json', '{"error":"bad %s"}' % secret)
        self.write('dir/ci-canary.json', '{"x":"%s"}' % CANARY)
        report = scanner.scan(['ci-ok.json', 'ci-leak.json', 'dir'],
                              {'ATOMIC_CI_CANARY': CANARY, 'ADMIN_API_KEY': secret})
        self.assertEqual(report['outcome'], 'fail')
        self.assertEqual(report['findings'], [
            {'file': 'ci-leak.json', 'kind': 'environment_secret'},
            {'file': 'dir/ci-canary.json', 'kind': 'environment_secret'},
        ])
        serialized = json.dumps(report)
        self.assertNotIn(secret, serialized)
        self.assertNotIn(CANARY, serialized)

    def test_credential_shapes_found_and_safe_text_not(self):
        shaped = {
            'private_key': '-----BEGIN PRIVATE KEY-----\nMIIE',
            'google_access_token': 'ya29.' + 'a' * 40,
            'google_refresh_token': '1//0' + 'b' * 40,
            'google_client_secret': 'GOCSPX-' + 'c' * 28,
            'google_api_key': 'AIza' + 'd' * 35,
            'jwt': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.c2lnbmF0dXJlLXZhbHVl',
            'credentialed_uri': 'mongodb+srv://user:pa55word@cluster.example.net/db',
        }
        for kind, text in shaped.items():
            self.assertEqual(scanner.scan_text('f', text, []), [{'file': 'f', 'kind': kind}], kind)
        for text in ['{"name":"GOOGLE_CLIENT_SECRET","problem":"not set"}',
                     'mongodb://127.0.0.1:27017/?replicaSet=rs0',
                     '{"sha256":"%s"}' % ('e' * 64),
                     'http://127.0.0.1:8080/api/notes/push']:
            self.assertEqual(scanner.scan_text('f', text, []), [], text)

    def test_secret_values_only_from_secret_names_and_credentialed_uris(self):
        values = scanner.secret_values({
            'ADMIN_API_KEY': 'a' * 32, 'ATOMIC_CI_CANARY': CANARY, 'SHORT_TOKEN': 'abc',
            'MONGODB_URI': 'mongodb://u:p4ssword@host/db', 'PLAIN_URI': 'mongodb://127.0.0.1/',
            'PATH': '/usr/bin', 'GITHUB_SHA': 'f' * 40,
        })
        self.assertEqual(values, sorted(['a' * 32, CANARY, 'mongodb://u:p4ssword@host/db']))

    def test_main_writes_the_report_and_exit_status(self):
        self.write('ci-a.json', '{}')
        os.environ['ATOMIC_CI_CANARY'] = CANARY
        try:
            self.assertEqual(scanner.main(['ci-a.json']), 0)
            self.write('ci-b.json', 'ya29.' + 'z' * 30)
            self.assertEqual(scanner.main(['ci-a.json', 'ci-b.json']), 1)
        finally:
            del os.environ['ATOMIC_CI_CANARY']
        report = json.loads((self.root / scanner.OUTPUT).read_text(encoding='utf-8'))
        self.assertEqual(report['findings'], [{'file': 'ci-b.json', 'kind': 'google_access_token'}])


if __name__ == '__main__':
    unittest.main()
