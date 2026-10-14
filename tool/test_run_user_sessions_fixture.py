"""Artifact guards use generated events, never compiler/test text."""
import json
import unittest
from run_user_sessions_fixture import CASES, classify

class ArtifactGuards(unittest.TestCase):
    def events(self):
        rows = [{'type': 'testStart', 'test': {'id': 0, 'name': 'loading fixture'}},
                {'type': 'testDone', 'testID': 0, 'result': 'success', 'skipped': False, 'hidden': True}]
        for i, (name, code) in enumerate(CASES.items(), 1):
            rows.extend([{'type': 'testStart', 'test': {'id': i, 'name': name}},
                         {'type': 'print', 'testID': i, 'message': 'atomic_sessions_cleanup:' + code},
                         {'type': 'testDone', 'testID': i, 'result': 'success', 'skipped': False, 'hidden': False}])
        rows.append({'type': 'done', 'success': True})
        return rows
    def check(self, rows, code=0):
        return classify('\n'.join(json.dumps(row) for row in rows), code, 'loading fixture')
    def test_complete(self):
        self.assertEqual(self.check(self.events())['outcome'], 'pass')
    def test_failure_and_nonzero(self):
        rows = self.events(); rows[4]['result'] = 'failure'
        self.assertEqual(self.check(rows)['outcome'], 'fail')
        self.assertEqual(self.check(self.events(), 1)['outcome'], 'fail')
    def test_skip_refused(self):
        rows = self.events(); rows[4]['skipped'] = True
        self.assertEqual(self.check(rows)['outcome'], 'fail')
    def test_missing_cleanup(self):
        rows = self.events(); del rows[3]
        self.assertEqual(self.check(rows)['outcome'], 'fail')
    def test_duplicate_and_unknown(self):
        rows = self.events(); rows.insert(5, rows[4])
        self.assertEqual(self.check(rows)['outcome'], 'fail')
        rows = self.events(); rows[2]['test']['name'] = 'unrecognized'
        self.assertEqual(self.check(rows)['outcome'], 'fail')
    def test_messages_not_retained(self):
        rows = self.events(); rows.insert(5, {'type': 'print', 'message': 'untrusted fixture message'})
        report = self.check(rows)
        self.assertEqual(report['outcome'], 'pass')
        self.assertNotIn('untrusted fixture message', json.dumps(report))

if __name__ == '__main__':
    unittest.main()
