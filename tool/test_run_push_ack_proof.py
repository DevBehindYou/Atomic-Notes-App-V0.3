import json
import unittest

from run_push_ack_proof import CASES, classify


def stream():
    events = [{'type': 'testStart', 'test': {'id': 0, 'name': 'loading fixture'}},
              {'type': 'testDone', 'testID': 0, 'result': 'success', 'skipped': False, 'hidden': True}]
    for ident, (name, code) in enumerate(CASES.items(), 1):
        events.extend([
            {'type': 'testStart', 'test': {'id': ident, 'name': name}},
            {'type': 'print', 'testID': ident, 'message': 'atomic_push_ack_cleanup:' + code},
            {'type': 'testDone', 'testID': ident, 'result': 'success', 'skipped': False, 'hidden': False},
        ])
    events.append({'type': 'done', 'success': True})
    return events


class ProofParserTests(unittest.TestCase):
    def parse(self, events, code=0):
        return classify('\n'.join(json.dumps(event) for event in events), code, 'loading fixture')

    def test_complete(self):
        self.assertEqual(self.parse(stream())['outcome'], 'pass')

    def test_refuses_missing_cleanup(self):
        self.assertEqual(self.parse([e for e in stream() if e.get('type') != 'print'])['outcome'], 'fail')

    def test_refuses_duplicate_case(self):
        events = stream()
        events.insert(-1, {'type': 'testStart', 'test': {'id': 200, 'name': next(iter(CASES))}})
        self.assertEqual(self.parse(events)['outcome'], 'fail')

    def test_refuses_skipped(self):
        events = stream()
        events[4]['skipped'] = True
        self.assertEqual(self.parse(events)['outcome'], 'fail')

    def test_refuses_nonzero(self):
        self.assertEqual(self.parse(stream(), 1)['outcome'], 'fail')

    def test_refuses_unknown_case(self):
        events = stream()
        events[2]['test']['name'] = 'unrecognized case'
        self.assertEqual(self.parse(events)['outcome'], 'fail')

    def test_refuses_terminal_absence_duplicate_failure(self):
        self.assertEqual(self.parse(stream()[:-1])['outcome'], 'fail')
        self.assertEqual(self.parse(stream() + [{'type': 'done', 'success': True}])['outcome'], 'fail')
        events = stream()
        events[-1]['success'] = False
        self.assertEqual(self.parse(events)['outcome'], 'fail')

    def test_failure_retains_fixed_codes_without_messages(self):
        events = stream()
        events[4]['result'] = 'failure'
        events.insert(4, {'type': 'error', 'testID': 1, 'error': 'private message',
                          'stackTrace': 'push_ack_boundary_test.dart:123:4'})
        events[-1]['success'] = False
        report = self.parse(events, 1)
        self.assertEqual(report['cases']['later_date'], 'fail')
        self.assertTrue(report['streamValid'])
        self.assertEqual(report['failureLines'], {'later_date': [123]})
        self.assertNotIn('private message', json.dumps(report))


if __name__ == '__main__':
    unittest.main()
