import json
from pathlib import Path
import unittest

from run_sync_envelope_proof import CONTROLS, NODE_CONTROL, TEST_FILE, WIRE_MARKER, case_results, emitted_wires, node_results, vectors

CASES = vectors(Path(__file__).resolve().parent.parent) + CONTROLS


def events():
    values = []
    for number, name in enumerate(CASES):
        values.extend([{'type': 'testStart', 'test': {'id': number, 'name': name}},
                       {'type': 'testDone', 'testID': number, 'result': 'success', 'skipped': False}])
    return values + [{'type': 'done', 'success': True}]


def stream(values):
    return '\n'.join(json.dumps(value) for value in values)


class EnvelopeProofControls(unittest.TestCase):
    def test_complete_exact_non_skipped_cases(self):
        terminal, results = case_results(stream(events()), CASES)
        self.assertTrue(terminal)
        self.assertTrue(all(results.values()))

    def test_skipped_or_failed_case_cannot_pass(self):
        for change in [{'skipped': True}, {'result': 'failure'}, {'result': 'error'}]:
            values = events()
            values[1].update(change)
            self.assertFalse(all(case_results(stream(values), CASES)[1].values()))

    def test_missing_duplicate_or_foreign_events_fail_closed(self):
        values = events()
        variants = [values[:-1], values[2:], values[1:], values + [values[-1]],
                    values[:2] + [values[1]] + values[2:],
                    values + [values[1]],
                    [{'type': 'testStart', 'test': {'id': 100, 'name': 'foreign'}}] + values]
        for variant in variants:
            with self.assertRaises(ValueError):
                case_results(stream(variant), CASES)

    def test_duplicate_case_or_id_and_invalid_boolean_rejected(self):
        for change in [('name', CASES[0]), ('id', 0)]:
            values = events()
            values[2]['test'][change[0]] = change[1]
            with self.assertRaises(ValueError):
                case_results(stream(values), CASES)
        for field in ['hidden', 'skipped']:
            values = events()
            values[1][field] = 0
            with self.assertRaises(ValueError):
                case_results(stream(values), CASES)

    def test_only_known_loading_file_can_be_hidden(self):
        loading = [{'type': 'testStart', 'test': {'id': 100, 'name': 'loading /owned/' + TEST_FILE}},
                   {'type': 'testDone', 'testID': 100, 'hidden': True, 'result': 'success', 'skipped': False}]
        self.assertTrue(case_results(stream(loading + events()), CASES)[0])
        loading[1]['hidden'] = False
        with self.assertRaises(ValueError):
            case_results(stream(loading + events()), CASES)

    def test_error_events_and_second_loader_fail_closed(self):
        for error in [{'type': 'error'}, {'type': 'error', 'testID': 999},
                      {'type': 'error', 'testID': True}, {'type': 'error', 'testID': 0}]:
            for values in [[error] + events(), events() + [error]]:
                with self.assertRaises(ValueError):
                    case_results(stream(values), CASES)
        loading = [{'type': 'testStart', 'test': {'id': 100, 'name': 'loading /owned/' + TEST_FILE}},
                   {'type': 'testDone', 'testID': 100, 'hidden': True, 'result': 'success', 'skipped': False},
                   {'type': 'testStart', 'test': {'id': 101, 'name': 'loading /other/' + TEST_FILE}},
                   {'type': 'testDone', 'testID': 101, 'hidden': True, 'result': 'success', 'skipped': False}]
        with self.assertRaises(ValueError):
            case_results(stream(loading + events()), CASES)

    def test_raw_diagnostics_are_discarded_and_events_bounded(self):
        diagnostic = json.dumps({'type': 'print', 'message': 'Public synthetic discarded diagnostic'})
        results = case_results('public fixture\n' + diagnostic + '\n' + stream(events()), CASES)[1]
        self.assertEqual(results, dict.fromkeys(CASES, True))
        with self.assertRaises(ValueError):
            case_results('x' * 256001, CASES)

    def test_node_schema_is_exact_boolean_complete_set(self):
        names = CASES[:-len(CONTROLS)] + (NODE_CONTROL,)
        value = {'version': 1, 'outcomes': dict.fromkeys(names, True)}
        self.assertTrue(all(node_results(json.dumps(value), names).values()))
        variants = [{'version': True, 'outcomes': value['outcomes']},
                    {**value, 'diagnostic': 'public fixture'},
                    {'version': 1, 'outcomes': {}},
                    {'version': 1, 'outcomes': {**value['outcomes'], names[0]: 1}}]
        for variant in variants:
            with self.assertRaises(ValueError):
                node_results(json.dumps(variant), names)

    def test_emitted_wire_receipts_are_exact_active_complete_and_bounded(self):
        values, names = [], CASES[:-len(CONTROLS)]
        for number, name in enumerate(names):
            values.extend([
                {'type': 'testStart', 'test': {'id': number, 'name': name}},
                {'type': 'print', 'testID': number, 'message': WIRE_MARKER + json.dumps({'case': name, 'wire': '{}'})},
                {'type': 'testDone', 'testID': number},
            ])
        self.assertEqual(len(emitted_wires(stream(values), names)), 16)
        for variant in [values[3:], values[1:], values + [values[1]], values[:2] + [values[1]] + values[2:]]:
            with self.assertRaises(ValueError):
                emitted_wires(stream(variant), names)
        for change in [{'testID': []}, {'testID': True},
                       {'message': WIRE_MARKER + json.dumps({'case': [], 'wire': '{}'})},
                       {'message': WIRE_MARKER + json.dumps({'case': names[0], 'wire': 0})},
                       {'message': WIRE_MARKER + json.dumps({'case': names[0], 'wire': '{}', 'extra': True})}]:
            variant = [dict(value) for value in values]
            variant[1].update(change)
            with self.assertRaises(ValueError):
                emitted_wires(stream(variant), names)
        values[1]['message'] = WIRE_MARKER + json.dumps({'case': names[0], 'wire': 'x' * 4097})
        with self.assertRaises(ValueError):
            emitted_wires(stream(values), names)


if __name__ == '__main__':
    unittest.main()
