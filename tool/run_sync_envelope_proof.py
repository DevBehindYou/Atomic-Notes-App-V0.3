"""CI-only fixed Server <-> Dart VM <-> owned Chrome envelope proof."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from run_browser_preimage_proof import run_private

SERVER_HEAD = '95070c0cff488e4984bd669d31bfdf348ec74aca'
TEST_FILE = 'test/sync_envelope_test.dart'
CONTROLS = (
    'C16 prepared inputs detach before async hashing and all nested output is immutable',
    'C17 invalid identities row shapes aliases and duplicates are refused',
    'C18 ordinary numeric guards and safe version boundary preserve native legacy validation',
    'C19 exact client row and UTF8 byte limits include envelope metadata and escaping',
    'C20 native logout validation errors remain exact',
)
NODE_CONTROL = 'N1 actual Server numeric and mixed checklist controls'
WIRE_MARKER = 'ATOMIC_SYNC_ENVELOPE_WIRE:'


def vectors(root):
    content = (root / 'test/fixtures/sync_envelope_vectors.dart').read_text(encoding='utf-8')
    values = json.loads(content.split("r'''", 1)[1].split("'''", 1)[0])
    names = tuple(value['case'] for value in values)
    if len(names) != 16 or len(set(names)) != len(names):
        raise ValueError('fixture set')
    return names


def case_results(stream, cases):
    """Fail closed for missing, skipped, repeated or foreign test events."""
    ids, names, completed = {}, set(), set()
    passed, ended, terminal = dict.fromkeys(cases, False), False, False
    loader_seen = False
    for line in stream.splitlines():
        if len(line) > 256_000:
            raise ValueError('event bound')
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'error':
            raise ValueError('test error')
        if kind not in {'testStart', 'testDone', 'done'}:
            continue
        if ended:
            raise ValueError('event after terminal')
        if kind == 'testStart':
            test = event.get('test')
            if not isinstance(test, dict):
                raise ValueError('test shape')
            number, name = test.get('id'), test.get('name')
            if type(number) is not int or not 0 <= number < 1_000_000 or not isinstance(name, str):
                raise ValueError('identity')
            path = name.removeprefix('loading ').replace('\\', '/')
            loading = name.startswith('loading ') and (path == TEST_FILE or path.endswith('/' + TEST_FILE))
            if number in ids or name in names or (name not in cases and not loading):
                raise ValueError('duplicate or unknown case')
            if loading:
                if loader_seen:
                    raise ValueError('duplicate loader')
                loader_seen = True
            ids[number] = (name, loading)
            names.add(name)
        elif kind == 'testDone':
            number = event.get('testID')
            if type(number) is not int or number not in ids or number in completed:
                raise ValueError('completion identity')
            name, loading = ids[number]
            hidden = event.get('hidden', False)
            if type(hidden) is not bool or hidden != loading or type(event.get('skipped')) is not bool:
                raise ValueError('completion shape')
            if event.get('result') not in {'success', 'failure', 'error'}:
                raise ValueError('result shape')
            success = event['result'] == 'success' and not event['skipped']
            if loading and not success:
                raise ValueError('loading failure')
            completed.add(number)
            if not loading:
                passed[name] = success
        else:
            if type(event.get('success')) is not bool or completed != set(ids) or not set(cases).issubset(names):
                raise ValueError('terminal completeness')
            terminal, ended = event['success'], True
    if not ended:
        raise ValueError('missing terminal')
    return terminal, passed


def node_results(stream, cases):
    value = json.loads(stream)
    if not isinstance(value, dict) or set(value) != {'version', 'outcomes'} or type(value['version']) is not int or value['version'] != 1:
        raise ValueError('Node schema')
    outcomes = value['outcomes']
    if not isinstance(outcomes, dict) or set(outcomes) != set(cases) or any(type(bit) is not bool for bit in outcomes.values()):
        raise ValueError('Node outcomes')
    return outcomes


def emitted_wires(stream, cases):
    active, wires = {}, {}
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'testStart':
            test = event.get('test', {})
            if isinstance(test, dict):
                active[test.get('id')] = test.get('name')
        elif event.get('type') == 'testDone':
            active.pop(event.get('testID'), None)
        elif event.get('type') == 'print' and isinstance(event.get('message'), str) and event['message'].startswith(WIRE_MARKER):
            value = json.loads(event['message'][len(WIRE_MARKER):])
            if not isinstance(value, dict) or set(value) != {'case', 'wire'}:
                raise ValueError('wire shape')
            name = value['case']
            number = event.get('testID')
            if not isinstance(name, str) or type(number) is not int or name not in cases or name in wires or active.get(number) != name:
                raise ValueError('wire identity')
            if not isinstance(value['wire'], str) or len(value['wire']) > 4096:
                raise ValueError('wire bound')
            wires[name] = value
    if set(wires) != set(cases):
        raise ValueError('incomplete emitted wires')
    return [wires[name] for name in cases]


def run_wire_oracle(root, wires):
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(['node', '--import', 'tsx', '../tool/sync_envelope_server_proof.mjs', '--emitted-wire'],
                                cwd=root / 'server-fixture', input=json.dumps(wires).encode('utf-8'),
                                stdout=output, stderr=subprocess.STDOUT, timeout=60, check=False)
        if output.tell() > 256_000:
            raise ValueError('oracle stream bound')
        output.seek(0)
        return result.returncode, output.read().decode('utf-8', errors='replace')


def main():
    root = Path(__file__).resolve().parent.parent
    head = os.environ.get('ATOMIC_WEB_SOURCE_HEAD', '')
    names = vectors(root)
    cases, node_cases = names + CONTROLS, names + (NODE_CONTROL,)
    report = {
        'version': 1, 'scope': 'pure shared envelope actual locked Server, VM and CI-owned Chrome only',
        'sourceHead': head if re.fullmatch('[0-9a-f]{40}', head) else None,
        'serverHead': SERVER_HEAD, 'flutterVersion': None, 'chromeVersion': None,
        'phase': 'guard', 'outcome': 'failed', 'sourceSha256': {},
        'nodeExitCode': None, 'vmExitCode': None, 'chromeExitCode': None,
        'nodeVmWireExitCode': None, 'nodeChromeWireExitCode': None,
        'nodeCases': dict.fromkeys(node_cases, False),
        'vmCases': dict.fromkeys(cases, False), 'chromeCases': dict.fromkeys(cases, False),
        'nodeVmWireCases': dict.fromkeys(names, False), 'nodeChromeWireCases': dict.fromkeys(names, False),
        'appEditingEnabled': False, 'cloudEnabled': False, 'journalImplemented': False,
    }
    try:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or report['sourceHead'] is None:
            raise ValueError('CI guard')
        for directory, identity in [(root, head), (root / 'server-fixture', SERVER_HEAD)]:
            code, stream = run_private(['git', 'rev-parse', 'HEAD'], directory, 30)
            if code or stream.strip() != identity:
                raise ValueError('source identity')
        for filename in ('lib/api/sync_envelope.dart', 'lib/api/logout_protocol.dart', TEST_FILE,
                         'test/fixtures/sync_envelope_vectors.dart', 'pubspec.lock',
                         'tool/sync_envelope_server_proof.mjs', 'tool/run_sync_envelope_proof.py',
                         'tool/test_sync_envelope_proof.py', '.github/workflows/web-storage-proof.yml',
                         'server-fixture/src/types/noteWire.ts', 'server-fixture/src/types/atomicFile.ts',
                         'server-fixture/src/lib/syncFingerprint.ts', 'server-fixture/package-lock.json'):
            report['sourceSha256'][filename] = hashlib.sha256((root / filename).read_bytes()).hexdigest()
        code, stream = run_private(['flutter', '--version', '--machine'], root, 90)
        if code or json.loads(stream).get('frameworkVersion') != '3.44.8':
            raise ValueError('SDK identity')
        report['flutterVersion'] = '3.44.8'
        chrome = os.environ.get('CHROME_EXECUTABLE', '')
        if not chrome.startswith('/'):
            raise ValueError('Chrome guard')
        code, stream = run_private([chrome, '--version'], root, 30)
        match = re.fullmatch(r'Google Chrome(?: for Testing)? ([0-9]+(?:\.[0-9]+){3})\s*', stream)
        if code or match is None:
            raise ValueError('Chrome identity')
        report['chromeVersion'] = match.group(1)
        report['phase'] = 'actual-server'
        code, stream = run_private(['node', '--import', 'tsx', '../tool/sync_envelope_server_proof.mjs'], root / 'server-fixture', 60)
        report['nodeExitCode'], report['nodeCases'] = code, node_results(stream, node_cases)
        if code or not all(report['nodeCases'].values()):
            raise ValueError('Node cases')
        for target, extra in [('vm', []), ('chrome', ['--platform', 'chrome'])]:
            report['phase'] = target
            code, stream = run_private(['flutter', 'test', '--no-pub', '--reporter', 'json',
                                        '--dart-define=ATOMIC_SYNC_ENVELOPE_WIRE_PROOF=true',
                                        *extra, TEST_FILE], root, 300)
            terminal, results = case_results(stream, cases)
            report[target + 'ExitCode'], report[target + 'Cases'] = code, results
            if code or not terminal or not all(results.values()):
                raise ValueError('Dart cases')
            report['phase'] = 'actual-server-' + target + '-wire'
            code, oracle = run_wire_oracle(root, emitted_wires(stream, names))
            key = 'node' + target.title() + 'Wire'
            report[key + 'ExitCode'], report[key + 'Cases'] = code, node_results(oracle, names)
            if code or not all(report[key + 'Cases'].values()):
                raise ValueError('actual emitted wire cases')
        report['phase'], report['outcome'] = 'complete', 'passed'
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        pass
    (root / 'ci-sync-envelope-proof.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'phase': report['phase'], 'outcome': report['outcome']}))
    return 0 if report['outcome'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
