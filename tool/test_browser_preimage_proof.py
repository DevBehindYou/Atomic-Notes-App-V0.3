import json
import unittest

from run_browser_preimage_proof import CASES, TEST_FILES, browser_cases, cleanup_receipts


def case_events(*, skipped=False, terminal=True):
    events = []
    for number, name in enumerate(CASES):
        events.append({'type': 'testStart', 'test': {'id': number, 'name': name}})
        events.append({'type': 'testDone', 'testID': number,
                       'result': 'success', 'skipped': skipped})
    if terminal:
        events.append({'type': 'done', 'success': True})
    return events


def event_stream(events):
    return '\n'.join(json.dumps(event) for event in events)


class BrowserPreimageProofParserTest(unittest.TestCase):
    def test_cleanup_receipts_require_exact_active_case(self):
        events = []
        for number, name in enumerate(CASES):
            events.extend([
                {'type': 'testStart', 'test': {'id': number, 'name': name}},
                {'type': 'print', 'testID': number, 'message': 'ATOMIC_PREIMAGE_CLEANUP_OK'},
                {'type': 'testDone', 'testID': number},
            ])
        self.assertTrue(all(cleanup_receipts(event_stream(events)).values()))

    def test_missing_cleanup_is_not_success(self):
        self.assertFalse(any(cleanup_receipts(event_stream(case_events())).values()))

    def test_unowned_and_duplicate_cleanup_rejected(self):
        receipt = {'type': 'print', 'testID': 0, 'message': 'ATOMIC_PREIMAGE_CLEANUP_OK'}
        with self.assertRaises(ValueError):
            cleanup_receipts(event_stream([receipt]))
        with self.assertRaises(ValueError):
            cleanup_receipts(event_stream([
                {'type': 'testStart', 'test': {'id': 0, 'name': CASES[0]}},
                receipt, receipt,
            ]))

    def test_raw_messages_do_not_count_as_cleanup(self):
        self.assertFalse(any(cleanup_receipts(event_stream([
            {'type': 'print', 'message': 'ATOMIC_PREIMAGE_CLEANUP_OK details'},
        ])).values()))

    def test_complete_exact_cases_pass(self):
        terminal, cases = browser_cases(event_stream(case_events()))
        self.assertTrue(terminal)
        self.assertTrue(all(cases.values()))

    def test_skipped_tests_never_count_as_browser_proof(self):
        terminal, cases = browser_cases(event_stream(case_events(skipped=True)))
        self.assertTrue(terminal)
        self.assertFalse(any(cases.values()))

    def test_missing_terminal_is_rejected(self):
        with self.assertRaises(ValueError):
            browser_cases(event_stream(case_events(terminal=False)))

    def test_unknown_messages_are_never_retained(self):
        stream = '\n'.join([
            'public diagnostic fixture',
            json.dumps({'type': 'print', 'message': 'public fixture text'}),
            event_stream(case_events()),
        ])
        terminal, cases = browser_cases(stream)
        self.assertTrue(terminal)
        self.assertEqual(cases, {name: True for name in CASES})

    def test_duplicate_target_name_is_rejected(self):
        events = case_events()
        events.insert(2, {'type': 'testStart', 'test': {'id': 40, 'name': CASES[0]}})
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_duplicate_id_with_another_target_name_is_rejected(self):
        events = case_events()
        events[2]['test']['id'] = 0
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_duplicate_terminal_is_rejected(self):
        events = case_events() + [{'type': 'done', 'success': True}]
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_completion_without_start_is_rejected(self):
        events = case_events()[1:]
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_duplicate_completion_is_rejected(self):
        events = case_events()
        events.insert(2, dict(events[1]))
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_unknown_nonhidden_test_is_rejected(self):
        events = case_events()
        events.insert(0, {'type': 'testStart', 'test': {'id': 40, 'name': 'unknown'}})
        events.insert(1, {'type': 'testDone', 'testID': 40, 'hidden': False,
                          'result': 'success', 'skipped': False})
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_known_loading_events_require_hidden_true(self):
        events = []
        for number, filename in enumerate(TEST_FILES, 20):
            events.append({'type': 'testStart', 'test': {
                'id': number, 'name': 'loading /public-fixture/' + filename}})
            events.append({'type': 'testDone', 'testID': number, 'hidden': True,
                           'result': 'success', 'skipped': False})
        complete = events + case_events()
        terminal, cases = browser_cases(event_stream(complete))
        self.assertTrue(terminal)
        self.assertTrue(all(cases.values()))
        events[1]['hidden'] = False
        with self.assertRaises(ValueError):
            browser_cases(event_stream(complete))

    def test_unknown_hidden_loading_file_is_rejected(self):
        events = case_events()
        events.insert(0, {'type': 'testStart', 'test': {
            'id': 40, 'name': 'loading test/other_test.dart'}})
        events.insert(1, {'type': 'testDone', 'testID': 40, 'hidden': True,
                          'result': 'success', 'skipped': False})
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_incomplete_case_set_is_rejected(self):
        events = case_events()[2:]
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_event_after_terminal_is_rejected(self):
        events = case_events() + [{'type': 'testDone', 'testID': 0,
                                  'result': 'success', 'skipped': False}]
        with self.assertRaises(ValueError):
            browser_cases(event_stream(events))

    def test_oversized_event_is_rejected(self):
        with self.assertRaises(ValueError):
            browser_cases('x' * 256_001)


if __name__ == '__main__':
    unittest.main()
