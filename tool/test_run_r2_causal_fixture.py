"""Parser, historical-source, package-relocation and cleanup guard controls."""

import json
import hashlib
import io
from pathlib import Path
import subprocess
import tempfile
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from run_r2_causal_fixture import (
    CASES, OBSERVATIONS, classify, execute_package, relocated_config, resolved_graph, run_fixture,
)


class R2CausalProofControls(unittest.TestCase):
    def events(self, phase):
        events = [
            {'type': 'testStart', 'test': {'id': 99, 'name': 'loading fixture'}},
            {'type': 'testDone', 'testID': 99, 'hidden': True,
             'skipped': False, 'result': 'success'},
        ]
        for number, (name, code) in enumerate(CASES.items(), 1):
            events.append({'type': 'testStart', 'test': {'id': number, 'name': name}})
            for observation in OBSERVATIONS[phase][code]:
                events.append({'type': 'print', 'testID': number,
                               'message': 'atomic_r2_observation:' + code + ':' + observation})
            events.extend([
                {'type': 'print', 'testID': number, 'message': 'atomic_r2_cleanup:' + code},
                {'type': 'testDone', 'testID': number, 'hidden': False, 'skipped': False,
                 'result': 'failure' if phase == 'before' and code == 'busy_logout' else 'success'},
            ])
        return events + [{'type': 'done', 'success': phase == 'after'}]

    def classify(self, events, phase, returncode=None):
        return classify('\n'.join(json.dumps(event) for event in events),
                        returncode if returncode is not None else (1 if phase == 'before' else 0),
                        'loading fixture', phase)

    def test_before_requires_expected_failure_and_controls_pass(self):
        report = self.classify(self.events('before'), 'before')
        self.assertEqual(report['outcome'], 'pass')
        self.assertEqual(report['cases']['busy_logout'], 'fail')
        self.assertEqual(report['observations'], OBSERVATIONS['before'])

    def test_after_requires_preservation_and_all_pass(self):
        self.assertEqual(self.classify(self.events('after'), 'after')['outcome'], 'pass')

    def test_unknown_or_missing_or_duplicate_events_fail_closed(self):
        for phase in ['before', 'after']:
            for variant in ['missing_case', 'unknown_case', 'duplicate_case', 'bool_id',
                            'wrong_observation', 'duplicate_observation', 'missing_observation',
                            'unknown_cleanup', 'wrong_cleanup_id', 'missing_cleanup',
                            'duplicate_cleanup', 'missing_loader', 'loader_failure',
                            'duplicate_loader_done', 'unknown_completion', 'hidden_case',
                            'skipped_case', 'wrong_case_result', 'missing_done', 'duplicate_done',
                            'wrong_done', 'nonbool_done', 'duplicate_testdone']:
                with self.subTest(phase=phase, variant=variant):
                    events = self.events(phase)
                    first_done = next(i for i, event in enumerate(events)
                                      if event.get('type') == 'testDone' and event.get('testID') == 1)
                    first_cleanup = next(i for i, event in enumerate(events)
                                         if event.get('type') == 'print'
                                         and event.get('message') == 'atomic_r2_cleanup:busy_logout')
                    if variant == 'missing_case':
                        events = [event for event in events if event.get('testID') != 1
                                  and event.get('test', {}).get('id') != 1]
                    elif variant == 'unknown_case':
                        events[2]['test']['name'] = 'unlisted'
                    elif variant == 'duplicate_case':
                        events.insert(3, {'type': 'testStart', 'test': {'id': 22, 'name': next(iter(CASES))}})
                    elif variant == 'bool_id':
                        events[2]['test']['id'] = True
                    elif variant == 'wrong_observation':
                        events[3]['message'] = 'atomic_r2_observation:busy_logout:unlisted'
                    elif variant == 'duplicate_observation':
                        events.insert(4, events[3])
                    elif variant == 'missing_observation':
                        del events[3]
                    elif variant == 'unknown_cleanup':
                        events[first_cleanup]['message'] = 'atomic_r2_cleanup:unlisted'
                    elif variant == 'wrong_cleanup_id':
                        events[first_cleanup]['testID'] = 2
                    elif variant == 'missing_cleanup':
                        del events[first_cleanup]
                    elif variant == 'duplicate_cleanup':
                        events.insert(first_cleanup, events[first_cleanup])
                    elif variant == 'missing_loader':
                        del events[:2]
                    elif variant == 'loader_failure':
                        events[1]['result'] = 'failure'
                    elif variant == 'duplicate_loader_done':
                        events.insert(2, events[1])
                    elif variant == 'unknown_completion':
                        events[first_done]['testID'] = 22
                    elif variant == 'hidden_case':
                        events[first_done]['hidden'] = True
                    elif variant == 'skipped_case':
                        events[first_done]['skipped'] = True
                    elif variant == 'wrong_case_result':
                        events[first_done]['result'] = 'success' if phase == 'before' else 'failure'
                    elif variant == 'missing_done':
                        events.pop()
                    elif variant == 'duplicate_done':
                        events.append(events[-1])
                    elif variant == 'wrong_done':
                        events[-1]['success'] = phase != 'after'
                    elif variant == 'nonbool_done':
                        events[-1]['success'] = 1 if phase == 'after' else 0
                    elif variant == 'duplicate_testdone':
                        events.insert(first_done, events[first_done])
                    self.assertEqual(self.classify(events, phase)['outcome'], 'fail')

    def test_wrong_exit_never_passes(self):
        for phase in ['before', 'after']:
            self.assertEqual(self.classify(self.events(phase), phase, 9)['outcome'], 'fail')

    def test_malformed_and_nonobject_events_never_pass(self):
        stream = '\n'.join(json.dumps(event) for event in self.events('after'))
        for suffix in ['invalid', '[]', 'null', 'true']:
            self.assertEqual(classify(stream + '\n' + suffix, 0, 'loading fixture', 'after')['outcome'], 'fail')

    def test_unknown_raw_error_and_print_are_discarded(self):
        events = self.events('before')
        events.insert(4, {'type': 'error', 'testID': 1, 'error': 'synthetic-private-text'})
        events.insert(4, {'type': 'print', 'testID': 1, 'message': 'synthetic-private-text'})
        report = self.classify(events, 'before')
        self.assertEqual(report['outcome'], 'pass')
        self.assertNotIn('synthetic-private-text', json.dumps(report))

    def test_package_paths_relocate_without_changing_dependencies(self):
        original = {'configVersion': 2, 'packages': [
            {'name': 'atomic_notes', 'rootUri': '../', 'packageUri': 'lib/'},
            {'name': 'fake_dependency', 'rootUri': 'file:///fixture-cache/dependency/', 'packageUri': 'lib/'},
        ]}
        config_path = Path('fixture/app/.dart_tool/package_config.json').resolve()
        destination = Path('fixture/owned/before').resolve()
        output = relocated_config(original, config_path, destination)
        self.assertEqual(output['packages'][0]['rootUri'], destination.as_uri() + '/')
        self.assertEqual(output['packages'][1], original['packages'][1])
        self.assertEqual(original['packages'][0]['rootUri'], '../')

    def test_own_package_must_be_unique(self):
        for packages in [[], [{'name': 'atomic_notes', 'rootUri': '../'}] * 2]:
            with self.assertRaises(ValueError):
                relocated_config({'packages': packages}, Path('/fixture/config.json'), Path('/fixture/owned'))

    def test_private_file_required_strict_bounded_and_streams_hidden(self):
        for variant in ['valid', 'missing', 'malformed', 'oversized', 'wrong_exit']:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory(
                    dir=Path(__file__).resolve().parent.parent) as temp:
                root = Path(temp)

                def run(command, **kwargs):
                    self.assertEqual(kwargs['stdout'], subprocess.DEVNULL)
                    self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
                    self.assertEqual(kwargs['timeout'], 180)
                    self.assertEqual(kwargs['env']['ATOMIC_R2_OWNED_ROOT'], str(root))
                    events = self.events('after')
                    events[0]['test']['name'] = 'loading ' + str(root / 'test/r2_logout_causal_test.dart')
                    contents = '\n'.join(json.dumps(event) for event in events)
                    if variant == 'malformed':
                        contents += '\ninvalid'
                    if variant == 'oversized':
                        contents = 'x' * (4 * 1024 * 1024 + 1)
                    if variant != 'missing':
                        (root / 'private-events.jsonl').write_text(contents, encoding='utf-8')
                    return SimpleNamespace(returncode=9 if variant == 'wrong_exit' else 0)

                if variant in ['missing', 'oversized']:
                    with self.assertRaises(ValueError):
                        execute_package(root, 'after', run)
                else:
                    report = execute_package(root, 'after', run)
                    self.assertEqual(report['outcome'], 'pass' if variant == 'valid' else 'fail')

    def test_missing_or_changed_historical_source_fails_before_running(self):
        with patch('run_r2_causal_fixture.read_source', return_value='altered-source'):
            report = run_fixture(Path('/fixture'), run=lambda *args, **kwargs: self.fail('must not run'))
        self.assertEqual(report['outcome'], 'fail')
        self.assertEqual(report['phase'], 'runner_failure')
        self.assertEqual(report['ownedCleanup'], 'not_run')

    def test_owned_cleanup_after_success_failure_and_timeout(self):
        for variant in ['success', 'failed_phase', 'timeout', 'cleanup_failure']:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory(
                    dir=Path(__file__).resolve().parent.parent) as outer:
                parent = Path(outer).resolve()
                fixture_root = parent / 'fixture'
                (fixture_root / '.dart_tool').mkdir(parents=True)
                (fixture_root / '.dart_tool/package_config.json').write_text('{}')
                (fixture_root / 'test').mkdir()
                (fixture_root / 'test/r2_logout_causal_test.dart').write_text('void main() {}')
                temporary = tempfile.TemporaryDirectory(dir=parent)
                owned = Path(temporary.name).resolve()
                self.assertTrue(owned.is_relative_to(parent))
                real_cleanup = temporary.cleanup
                if variant == 'cleanup_failure':
                    temporary.cleanup = lambda: (_ for _ in ()).throw(OSError('synthetic-private-text'))

                def execute(root, phase, run):
                    if variant == 'timeout':
                        raise subprocess.TimeoutExpired('fixture', 180)
                    result = self.classify(self.events(phase), phase)
                    if variant == 'failed_phase':
                        result['outcome'] = 'fail'
                    return result

                try:
                    with patch('run_r2_causal_fixture.HISTORICAL_HASHES',
                               {'lib/fixture.dart': hashlib.sha256(b'source').hexdigest()}), \
                            patch('run_r2_causal_fixture.read_source', return_value='source'), \
                            patch('run_r2_causal_fixture.resolved_graph', return_value=b'{}'), \
                            patch('run_r2_causal_fixture.prepare_package'), \
                            patch('run_r2_causal_fixture.execute_package', side_effect=execute):
                        report = run_fixture(fixture_root, temporary_factory=lambda **kwargs: temporary)
                    self.assertEqual(report['outcome'], 'pass' if variant == 'success' else 'fail')
                    self.assertNotIn('synthetic-private-text', json.dumps(report))
                    self.assertEqual(report['ownedCleanup'], 'fail' if variant == 'cleanup_failure' else 'pass')
                    self.assertEqual(owned.exists(), variant == 'cleanup_failure')
                finally:
                    real_cleanup()

    def test_locked_graph_is_copied_only_when_valid_and_bounded(self):
        graph = {'configVersion': 1, 'roots': ['atomic_notes'], 'packages': [
            {'name': 'atomic_notes', 'dependencies': ['fixture_dependency'], 'devDependencies': []},
            {'name': 'fixture_dependency', 'dependencies': []},
        ]}
        for variant in ['valid', 'missing', 'oversized', 'invalid_json', 'wrong_root',
                        'duplicate_own', 'bool_version', 'bad_dependencies']:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory(
                    dir=Path(__file__).resolve().parent.parent) as temp:
                root = Path(temp)
                (root / '.dart_tool').mkdir()
                data = json.dumps(graph).encode()
                if variant == 'oversized':
                    data = b'x' * (2 * 1024 * 1024 + 1)
                elif variant == 'invalid_json':
                    data = b'invalid'
                else:
                    changed = json.loads(data)
                    if variant == 'wrong_root':
                        changed['roots'] = ['foreign']
                    elif variant == 'duplicate_own':
                        changed['packages'].append(changed['packages'][0])
                    elif variant == 'bool_version':
                        changed['configVersion'] = True
                    elif variant == 'bad_dependencies':
                        changed['packages'][0]['dependencies'] = 'bad'
                    data = json.dumps(changed).encode()
                if variant != 'missing':
                    (root / '.dart_tool/package_graph.json').write_bytes(data)
                if variant == 'valid':
                    self.assertEqual(resolved_graph(root), data)
                else:
                    with self.assertRaises(ValueError):
                        resolved_graph(root)


if __name__ == '__main__':
    result = unittest.TextTestRunner(stream=io.StringIO()).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(R2CausalProofControls))
    print(json.dumps({'version': 1, 'scope': 'R2 causal parser controls',
                      'tests': result.testsRun, 'failures': len(result.failures),
                      'errors': len(result.errors),
                      'outcome': 'pass' if result.wasSuccessful() else 'fail'}))
    sys.exit(0 if result.wasSuccessful() else 1)
