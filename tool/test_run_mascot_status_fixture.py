import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from run_mascot_status_fixture import CASES, classify, run_fixture


class MascotProofParserTests(unittest.TestCase):
    def events(self):
        result = [
            {'type': 'testStart', 'test': {'id': 99, 'name': 'loading fixture'}},
            {'type': 'testDone', 'testID': 99, 'result': 'success', 'skipped': False, 'hidden': True},
        ]
        for number, (name, code) in enumerate(CASES.items(), 1):
            result.extend([
                {'type': 'testStart', 'test': {'id': number, 'name': name}},
                {'type': 'print', 'testID': number, 'message': 'atomic_mascot_cleanup:' + code},
                {'type': 'testDone', 'testID': number, 'result': 'success', 'skipped': False, 'hidden': False},
            ])
        return result + [{'type': 'done', 'success': True}]

    def report(self, events, code=0):
        return classify('\n'.join(json.dumps(event) for event in events), code, 'loading fixture')

    def test_exact_cases_and_cleanup_pass(self):
        self.assertEqual(self.report(self.events())['outcome'], 'pass')

    def test_loader_hidden_only_at_completion_is_allowed(self):
        self.assertNotIn('hidden', self.events()[0]['test'])
        self.assertEqual(self.report(self.events())['outcome'], 'pass')

    def test_invalid_inputs_never_pass(self):
        for variant in ['missing_case', 'duplicate_case', 'duplicate_id', 'bool_id',
                        'unknown_case', 'unknown_hidden', 'missing_done', 'duplicate_done',
                        'false_done', 'nonbool_done', 'failed', 'skipped', 'missing_cleanup',
                        'duplicate_cleanup', 'unknown_cleanup', 'unknown_completion', 'bool_completion',
                        'missing_loader', 'failed_loader', 'missing_loader_done', 'duplicate_loader_done',
                        'visible_loader', 'skipped_loader', 'hidden_case', 'wrong_cleanup_id']:
            with self.subTest(variant=variant):
                complete_events = self.events()
                loader_events, events = complete_events[:2], complete_events[2:]
                if variant == 'missing_case':
                    del events[:3]
                elif variant == 'duplicate_case':
                    events.insert(3, {'type': 'testStart', 'test': {'id': 98, 'name': next(iter(CASES))}})
                elif variant == 'duplicate_id':
                    events[3]['test']['id'] = 1
                elif variant == 'bool_id':
                    events[0]['test']['id'] = True
                elif variant in ['unknown_case', 'unknown_hidden']:
                    events[0]['test']['name'] = 'unlisted'
                    events[0]['test']['hidden'] = variant == 'unknown_hidden'
                elif variant == 'missing_done':
                    events.pop()
                elif variant == 'duplicate_done':
                    events.append(events[-1])
                elif variant in ['false_done', 'nonbool_done']:
                    events[-1]['success'] = False if variant == 'false_done' else 1
                elif variant == 'failed':
                    events[2]['result'] = 'error'
                elif variant == 'skipped':
                    events[2]['skipped'] = True
                elif variant == 'missing_cleanup':
                    del events[1]
                elif variant == 'duplicate_cleanup':
                    events.insert(2, events[1])
                elif variant == 'unknown_cleanup':
                    events[1]['message'] = 'atomic_mascot_cleanup:unknown'
                elif variant in ['unknown_completion', 'bool_completion']:
                    events[2]['testID'] = 98 if variant == 'unknown_completion' else True
                elif variant == 'missing_loader':
                    loader_events = []
                elif variant == 'failed_loader':
                    loader_events[1]['result'] = 'error'
                elif variant == 'missing_loader_done':
                    loader_events.pop()
                elif variant == 'duplicate_loader_done':
                    loader_events.append(loader_events[1])
                elif variant == 'visible_loader':
                    loader_events[1]['hidden'] = False
                elif variant == 'skipped_loader':
                    loader_events[1]['skipped'] = True
                elif variant == 'hidden_case':
                    events[2]['hidden'] = True
                elif variant == 'wrong_cleanup_id':
                    events[1]['testID'] = 2
                self.assertEqual(self.report(loader_events + events)['outcome'], 'fail')

    def test_process_failure_never_passes(self):
        self.assertEqual(self.report(self.events(), 1)['outcome'], 'fail')

    def test_malformed_or_nonobject_stdout_never_passes(self):
        stream = '\n'.join(json.dumps(event) for event in self.events())
        for suffix in ['not json', '[]', 'null', 'true']:
            with self.subTest(suffix=suffix):
                self.assertEqual(classify(stream + '\n' + suffix, 0, 'loading fixture')['outcome'], 'fail')

    def test_private_report_is_required_and_strict(self):
        for variant in ['valid', 'missing', 'malformed', 'oversized', 'failed_process', 'timeout']:
            with self.subTest(variant=variant):
                owned = []

                def run(command, **kwargs):
                    self.assertEqual(kwargs['stdout'], subprocess.DEVNULL)
                    self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
                    report_path = Path(command[command.index('--file-reporter') + 1].removeprefix('json:'))
                    owned.append(report_path.parent)
                    if variant == 'timeout':
                        raise subprocess.TimeoutExpired('fixture', 180)
                    if variant != 'missing':
                        events = self.events()
                        events[0]['test']['name'] = 'loading ' + str(Path('fixture') / 'test/mascot_live_status_test.dart')
                        text = '\n'.join(json.dumps(event) for event in events)
                        if variant == 'malformed':
                            text += '\nnot json'
                        elif variant == 'oversized':
                            text = 'x' * (4 * 1024 * 1024 + 1)
                        report_path.write_text(text, encoding='utf-8')
                    return SimpleNamespace(returncode=1 if variant == 'failed_process' else 0)

                report = run_fixture(Path('fixture'), run=run)
                self.assertEqual(report['outcome'], 'pass' if variant == 'valid' else 'fail')
                self.assertTrue(owned)
                self.assertFalse(owned[0].exists())

    def test_private_report_cleanup_failure_never_passes(self):
        temporary = tempfile.TemporaryDirectory(prefix='atomic-mascot-parser-test-')
        real_cleanup = temporary.cleanup

        def broken_cleanup():
            raise OSError('synthetic_cleanup_failure')

        temporary.cleanup = broken_cleanup
        try:
            def run(command, **kwargs):
                report_path = Path(command[command.index('--file-reporter') + 1].removeprefix('json:'))
                events = self.events()
                events[0]['test']['name'] = 'loading ' + str(Path('fixture') / 'test/mascot_live_status_test.dart')
                report_path.write_text('\n'.join(json.dumps(event) for event in events), encoding='utf-8')
                return SimpleNamespace(returncode=0)

            report = run_fixture(Path('fixture'), run=run, temporary_factory=lambda **kwargs: temporary)
            self.assertEqual(report['phase'], 'cleanup_failure')
            self.assertEqual(report['outcome'], 'fail')
            self.assertEqual(set(report['cases'].values()), {'pass'})
        finally:
            real_cleanup()


if __name__ == '__main__':
    unittest.main()
