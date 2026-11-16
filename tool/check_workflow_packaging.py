"""Every Android packaging step in .github/workflows must be opt-in.

A step packages when it builds an APK, app bundle or APK set (flutter build
for any target other than web, desktop or iOS; a `gradle` or `gradlew`
command in its `run` unless every argument is a known non-packaging task or
option such as `test`, `lint` or `--version`, and Gradle assemble, bundle,
install or package tasks anywhere in the step; bundletool build-apks) or uploads a file whose path
names an .apk, .aab or .apks. Each such step must run only when the
repository variable ATOMIC_ANDROID_PACKAGING is 'enabled': its job's `if:`
or its own `if:` must be a guard.

A guard is a strict allow-list, not a substring match: optionally wrapped in
one `${{ }}`, a condition is a conjunction (`&&`) of simple comparisons
(`name.path == 'literal'` or `!=`), one of which is exactly
`vars.ATOMIC_ANDROID_PACKAGING == 'enabled'`. A condition with `||`, `!`, a
function call, parentheses, quoting around the whole expression, a comment
or a nested expression is not a guard. Only the repository variable counts.
A run cannot change `vars`, but any step or action can change `env` for the
steps after it (through $GITHUB_ENV), so an `env.` comparison is never a
guard.

The workflows are read against an explicit allow-list of this repository's
structure, not as general YAML:

- top-level keys at column 0: name, on, permissions, concurrency, jobs;
- job ids at two spaces, and job keys at four: name, if, runs-on,
  timeout-minutes, defaults, env, strategy, environment, steps (steps is
  required);
- steps as a block list, `- key: ...` at six spaces with the step's other
  keys at eight: name, id, if, uses, run, with, env, shell,
  continue-on-error;
- job and step `env:`, step `with:`, `defaults:`, `strategy:` and
  `environment:` as block mappings of plain keys one level deeper.

Values are read as YAML reads them before they are inspected. A plain value
ends at ` #`; a single-quoted value turns `''` into `'`; a double-quoted value
has its backslash escapes decoded (hex, Unicode and one-letter). A quoted value
must close on its own line with only a comment after it, and an unknown escape
is refused. A block scalar is read as YAML reads it: a literal block (`|`)
keeps its lines, a folded block (`>`) joins them with spaces except around
blank and more-indented lines, blank lines before the first content line are
kept as newlines, and `-` or `+` chomping is accepted. A block
with an indentation indicator (`|2`, `>1-`) is refused, and so is a plain
`run` value continued onto another line (a plain `if:` is joined with spaces
as YAML does). Commands, action references and upload paths are checked in
both their decoded and their source form, and a backslash line continuation
in a command is joined first. A local action is any `uses:` whose decoded
reference starts with `.`.

Anything else fails the check (exit 2) instead of being skipped or read as
an empty job: an unknown, duplicated or quoted key, any other indentation,
an inline mapping or flow collection (only a strategy matrix value may be a
flow list), a value continued where one line is expected, an unterminated
or multi-line quoted value, an unknown escape, text after a closing quote,
tabs or other line breaks, a byte order mark, YAML anchors or aliases,
reusable workflow jobs and local actions. Adding a new key or shape needs a
reviewed change to this file.

It checks the workflow files only. A packaging command assembled at run
time or by shell quoting (for example `flutter "build" apk`), inside a
script or helper, inside a Gradle build script that attaches work to an
allowed task, or inside a third-party action is outside what it can detect
or prove.

Usage: python3 tool/check_workflow_packaging.py [WORKFLOW_DIR]
"""
from pathlib import Path
import re
import sys

VAR = 'ATOMIC_ANDROID_PACKAGING'
GUARD_TERM = f"vars.{VAR} == 'enabled'"

FLUTTER_BUILD = re.compile(r'\bflutter(?:\s+-\S+)*\s+build\s+(\S+)', re.I)
NOT_ANDROID_TARGETS = {'web', 'linux', 'windows', 'macos', 'ios', 'ipa',
                       'ios-framework', 'macos-framework'}
OTHER_PACKAGING = re.compile(
    r'\bgradlew?\b[^\n]*\b(assemble|bundle|install|package)\w*'
    r'|bundletool\S*\s+build-apks', re.I)
# A `gradle` or `gradlew` command in a step's `run` counts unless every one
# of its arguments is on this short non-packaging list: `build`, abbreviated
# task names, variables and options such as -p or --init-script can all
# assemble packages, so anything else is treated as packaging.
GRADLE_COMMAND = re.compile(
    r'(?:^|[\s;&|(`"\'])(?:[\w.~$/-]*/)?gradlew?(?:\.bat)?(?=[\s;&|)`"\']|$)'
    r'(?P<args>[^;&|)\n`]*)', re.I | re.M)
GRADLE_NOT_PACKAGING = {'test', 'lint', 'tasks', 'help', 'dependencies', 'clean',
                        '--version', '-v', '--help', '-h', '--stacktrace', '-s',
                        '--info', '-i', '--quiet', '-q', '--no-daemon', '--offline'}
CONTINUATION = re.compile(r'\\\n[ \t]*')
DOUBLE_ESCAPES = {'0': chr(0), 'a': chr(7), 'b': chr(8), 't': chr(9), chr(9): chr(9),
                  'n': chr(10), 'v': chr(11), 'f': chr(12), 'r': chr(13), 'e': chr(27),
                  ' ': ' ', '"': '"', '/': '/', chr(92): chr(92), 'N': chr(0x85),
                  '_': chr(0xa0), 'L': chr(0x2028), 'P': chr(0x2029)}
HEX_ESCAPES = {'x': 2, 'u': 4, 'U': 8}
PACKAGE_PATH = re.compile(r'\.(apk|aab|apks)\b', re.I)
TERM = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)*"
                  r" (==|!=) ('[^'#]*'|true|false|null|-?[0-9]+)")
ANCHOR = re.compile(r'(^|[:-]\s+)[&*][A-Za-z0-9_]|<<:')
KEY_LINE = re.compile(r'(?P<key>[A-Za-z0-9_-]+):(?: +(?P<value>.*))?')
JOB_ID = re.compile(r'[A-Za-z_][A-Za-z0-9_-]*')
ENV_NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
BLOCK_SCALAR = re.compile(r'[|>][1-9]?[+-]?[1-9]?(\s+#.*)?')
BLOCK_HEADER = re.compile(r'(?P<style>[|>])[+-]?(\s+#.*)?')  # no indentation indicator
FOLDED = re.compile(r'>-?(\s+#.*)?')
FORBIDDEN = {'\t': 'tab', '\r': 'carriage return', '\x85': 'next line',
             '\u2028': 'line separator', '\u2029': 'paragraph separator',
             '\ufeff': 'byte order mark'}

TOP_KEYS = {'name', 'on', 'permissions', 'concurrency', 'jobs'}
JOB_KEYS = {'name', 'if', 'runs-on', 'timeout-minutes', 'defaults', 'env',
            'strategy', 'environment', 'steps'}
STEP_KEYS = {'name', 'id', 'if', 'uses', 'run', 'with', 'env', 'shell',
             'continue-on-error'}


class WorkflowShapeError(Exception):
    pass


class _Line:
    """One source line. [indent] is None for blank and comment-only lines."""

    def __init__(self, number, raw):
        self.number = number
        self.raw = raw
        stripped = raw.strip(' ')
        self.blank = not stripped or stripped.startswith('#')
        self.comment = stripped.startswith('#')
        self.indent = None if self.blank else len(raw) - len(raw.lstrip(' '))
        self.text = stripped


def _fail(where, line, message):
    at = f' (line {line.number})' if line is not None else ''
    raise WorkflowShapeError(f'{where}{at}: {message}')


def _key(line, where):
    """(key, value) of a plain `key:` or `key: value` line, or a shape error."""
    text = line.text
    if text[0] in '"\'':
        _fail(where, line, f'quoted keys are not read: {text}')
    if text[0] in '-?[{&*!|>%@`':
        _fail(where, line, f'expected a plain key: {text}')
    match = KEY_LINE.fullmatch(text)
    if not match:
        _fail(where, line, f'expected a plain `key:` line: {text}')
    value = (match.group('value') or '').strip()
    if value.startswith('#'):
        value = ''
    return match.group('key'), value


def _entries(lines, indent, where, allowed=None, key_pattern=None):
    """A block mapping at exactly [indent]: [(key, value, line, body)].

    [lines] are everything under the parent key. Every meaningful line is
    either an entry at [indent] or belongs to the body of the entry above
    it, so wrong indentation can never be skipped.
    """
    entries, seen = [], set()
    for line in lines:
        if line.blank:
            if entries:
                entries[-1][3].append(line)
            continue
        if line.indent == indent:
            key, value = _key(line, where)
            if allowed is not None and key not in allowed:
                _fail(where, line, f'key `{key}` is not on the allow-list')
            if key_pattern is not None and not key_pattern.fullmatch(key):
                _fail(where, line, f'unsupported key name `{key}`')
            if key in seen:
                _fail(where, line, f'duplicate key `{key}`')
            seen.add(key)
            entries.append((key, value, line, []))
        elif line.indent > indent and entries:
            entries[-1][3].append(line)
        else:
            _fail(where, line, f'expected a key at {indent} spaces: {line.text}')
    return entries


def _meaningful(body):
    return [line for line in body if not line.blank]


def _double_quoted(value, where, line):
    """(decoded text, rest of the line) for a double-quoted [value]."""
    out, i = [], 1
    while i < len(value):
        char = value[i]
        if char == '"':
            return ''.join(out), value[i + 1:]
        if char == chr(92):
            if i + 1 >= len(value):
                break  # an escaped line break: the value continues
            code = value[i + 1]
            if code in DOUBLE_ESCAPES:
                out.append(DOUBLE_ESCAPES[code])
                i += 2
                continue
            width = HEX_ESCAPES.get(code)
            digits = value[i + 2:i + 2 + width] if width else ''
            if not width or len(digits) != width or not re.fullmatch('[0-9A-Fa-f]+', digits):
                _fail(where, line, f'unknown escape in a quoted value: {value[i:i + 2]}')
            point = int(digits, 16)
            if point > 0x10FFFF:
                _fail(where, line, f'escape out of range in a quoted value: {value[i:i + 2 + width]}')
            out.append(chr(point))
            i += 2 + width
            continue
        out.append(char)
        i += 1
    _fail(where, line, 'a quoted value must close on its own line')


def _single_quoted(value, where, line):
    """(decoded text, rest of the line) for a single-quoted [value]."""
    out, i = [], 1
    while i < len(value):
        if value[i] == "'":
            if value[i + 1:i + 2] == "'":
                out.append("'")
                i += 2
                continue
            return ''.join(out), value[i + 1:]
        out.append(value[i])
        i += 1
    _fail(where, line, 'a quoted value must close on its own line')


def _scalar(value, where, line):
    """[value] as YAML reads a one-line scalar: quotes and escapes decoded,
    a plain value's trailing comment removed. Anything else is refused."""
    if value[:1] in ('"', "'"):
        decode = _double_quoted if value[0] == '"' else _single_quoted
        text, rest = decode(value, where, line)
        rest = rest.strip()
        if rest and not rest.startswith('#'):
            _fail(where, line, f'text after a quoted value is not read: {rest}')
        return text
    cut = value.find(' #')
    return value if cut < 0 else value[:cut].rstrip()


def _fold(lines):
    """Folds block-scalar [lines] as YAML does for `>`: a break between two
    ordinary lines becomes a space, each blank line a newline, and breaks
    next to a more-indented line are kept."""
    out, previous, blank = [], None, 0
    for text in lines:
        if not text:
            blank += 1
            continue
        kind = 'more' if text[0] == ' ' else 'ordinary'
        if previous is None:
            out.append('\n' * blank)
        elif previous == 'ordinary' and kind == 'ordinary':
            out.append(' ' if blank == 0 else '\n' * blank)
        else:
            out.append('\n' * (blank + 1))
        out.append(text)
        previous, blank = kind, 0
    return ''.join(out)


def _block_scalar(value, body, indent, where, line):
    """The text of a literal (`|`) or folded (`>`) block scalar whose key is
    at [indent], as YAML reads it. Blank lines before the first content line
    are kept as newlines. Trailing newlines are dropped (chomping does not
    change a command). An indentation indicator, or a content line at an
    indentation YAML would not accept, is refused."""
    header = BLOCK_HEADER.fullmatch(value)
    if not header:
        _fail(where, line, f'block scalar indentation indicators are not read: {value}')
    lines, content, ended, leading = [], None, False, 0
    for item in body:
        if not item.raw.strip(' '):
            if content is None:
                leading += 1  # kept once the content starts, as YAML does
            elif not ended:
                lines.append('')
            continue
        width = len(item.raw) - len(item.raw.lstrip(' '))
        if content is None and not ended and width > indent:
            content = width
            lines.extend([''] * leading)
        if not ended and content is not None and width >= content:
            lines.append(item.raw[content:])  # a `#` line here is content
            continue
        if item.comment:
            ended = True  # a less-indented comment ends the block
            continue
        _fail(where, item, 'a block scalar line at an unexpected indentation is not read')
    while lines and not lines[-1]:
        lines.pop()
    return '\n'.join(lines) if header.group('style') == '|' else _fold(lines)


def _single(key, value, line, body, where):
    """A one-line scalar value, decoded: no flow collection, block or continuation."""
    if not value:
        _fail(where, line, f'`{key}` needs a one-line value')
    if value[0] in '[{|>&*!':
        _fail(where, line, f'`{key}`: flow, block or tagged values are not read')
    if _meaningful(body):
        _fail(where, _meaningful(body)[0], f'`{key}` value continues onto another line')
    return _scalar(value, where, line)


def _block(key, value, line, where):
    if value:
        _fail(where, line, f'`{key}` must be a block (inline values are not read)')


def _mapping(key, value, line, body, indent, where, allowed=None,
             key_pattern=None, flow_lists=False):
    """A block mapping of one-line scalars (or simple flow lists)."""
    _block(key, value, line, where)
    entries = _entries(body, indent, f'{where} {key}', allowed, key_pattern)
    if not entries:
        _fail(where, line, f'`{key}` is empty')
    values = {}
    for sub, sub_value, sub_line, sub_body in entries:
        if (flow_lists and sub_value.startswith('[') and sub_value.endswith(']')
                and not re.search(r'[\[\]{}]', sub_value[1:-1])
                and not _meaningful(sub_body)):
            values[sub] = sub_value
            continue
        values[sub] = _single(sub, sub_value, sub_line, sub_body, f'{where} {key}')
    return values


def _condition(value, body, indent):
    """The `if:` expression at [indent], or None when it cannot be read.

    A folded block (`>` or `>-`) and a plain value continued on deeper lines
    both join their lines with spaces, as YAML does, so a continuation such
    as `|| true` is part of what the guard check sees. A comment line ends a
    plain value; inside a folded block, a deeper `#` line is part of the
    text. A line that would continue the value after it has ended is not
    read.
    """
    folded = bool(FOLDED.fullmatch(value))
    if not folded and BLOCK_SCALAR.fullmatch(value):
        return None  # literal and other block scalars are not read
    parts, ended = ([] if folded else [value]), False
    for line in body:
        if line.comment:
            deeper = len(line.raw) - len(line.raw.lstrip(' ')) > indent
            if folded and deeper and not ended:
                parts.append(line.text)
            else:
                ended = True
        elif not line.blank:
            if ended:
                return None
            parts.append(line.text)
    return ' '.join(parts)


def _guard(value):
    """True only when [value] requires the repository opt-in."""
    if value is None:
        return False
    value = value.strip()
    if value.startswith('${{') and value.endswith('}}'):
        value = value[3:-2].strip()
    if any(token in value for token in ('${{', '}}', '||', '#', '(', ')', '"')):
        return False
    conjuncts = [c.strip() for c in value.split('&&')]
    if not all(TERM.fullmatch(c) for c in conjuncts):
        return False
    return GUARD_TERM in conjuncts


def _packages(text, command):
    """Whether a step packages. [text] is the step's source plus every
    decoded value; [command] is its decoded `run` (empty when none)."""
    text = CONTINUATION.sub(' ', text)
    command = CONTINUATION.sub(' ', command)
    for match in FLUTTER_BUILD.finditer(text):
        if match.group(1).lower() not in NOT_ANDROID_TARGETS:
            return True
    if OTHER_PACKAGING.search(text):
        return True
    for match in GRADLE_COMMAND.finditer(command):
        args = match.group('args').split()
        if not args or any(a.lower() not in GRADLE_NOT_PACKAGING for a in args):
            return True
    return 'actions/upload-artifact' in text and bool(PACKAGE_PATH.search(text))


def _check_text(text, where):
    for char, name in FORBIDDEN.items():
        if char in text:
            raise WorkflowShapeError(f'{where}: {name} characters are not read')
    control = re.search(r'[\x00-\x08\x0b-\x1f\x7f]', text)
    if control:
        raise WorkflowShapeError(f'{where}: control characters are not read')
    for number, line in enumerate(text.split('\n'), 1):
        stripped = line.strip()
        if stripped and not stripped.startswith('#') and ANCHOR.search(line.split(' #')[0]):
            raise WorkflowShapeError(
                f'{where} (line {number}): YAML anchors/aliases are not read: {stripped}')


def _steps(key, value, line, body, where):
    """The steps block list: each step's lines, re-based to eight spaces."""
    _block(key, value, line, where)
    items = []
    for item in body:
        if item.blank:
            if items:
                items[-1].append(item)
            continue
        if item.indent == 6:
            if not item.raw.startswith('      - '):
                _fail(where, item, f'expected a step `- key: ...` at six spaces: {item.text}')
            rest = item.raw[8:]
            if not rest or rest[0] == ' ':
                _fail(where, item, 'a step must start with a key right after `- `')
            items.append([_Line(item.number, '        ' + rest)])
        elif item.indent > 6 and items:
            items[-1].append(item)
        else:
            _fail(where, item, f'expected a step at six spaces: {item.text}')
    if not items:
        _fail(where, line, 'the steps block has no steps')
    steps = []
    for index, lines in enumerate(items, 1):
        here = f'{where} step {index}'
        step = {'if': None, 'name': None, 'uses': None, 'run': '', 'values': [],
                'text': '\n'.join(l.raw for l in lines)}
        for sub, sub_value, sub_line, sub_body in _entries(lines, 8, here, STEP_KEYS):
            if sub == 'if':
                if not sub_value:
                    _fail(here, sub_line, '`if` needs a value')
                step['if'] = _condition(sub_value, sub_body, 8)
            elif sub == 'run':
                if not sub_value or sub_value[0] in '[{&*!':
                    _fail(here, sub_line, '`run` must be a scalar or a block scalar')
                if sub_value[0] in ('"', "'"):
                    if _meaningful(sub_body):
                        _fail(here, sub_line, 'a quoted `run` must close on its own line')
                    step['run'] = _scalar(sub_value, here, sub_line)
                elif BLOCK_SCALAR.fullmatch(sub_value):
                    step['run'] = _block_scalar(sub_value, sub_body, 8, here, sub_line)
                else:
                    if _meaningful(sub_body):
                        _fail(here, _meaningful(sub_body)[0],
                              'a plain `run` continued onto another line is not read; '
                              'use a block scalar')
                    step['run'] = _scalar(sub_value, here, sub_line)
            elif sub == 'with':
                _block(sub, sub_value, sub_line, here)
                entries = _entries(sub_body, 10, f'{here} with')
                if not entries:
                    _fail(here, sub_line, '`with` is empty')
                for w_key, w_value, w_line, w_body in entries:
                    if BLOCK_SCALAR.fullmatch(w_value):
                        step['values'].append(
                            _block_scalar(w_value, w_body, 10, f'{here} with', w_line))
                        continue
                    step['values'].append(_single(w_key, w_value, w_line, w_body, f'{here} with'))
            elif sub == 'env':
                step['values'] += _mapping(sub, sub_value, sub_line, sub_body, 10, here,
                                           None, ENV_NAME).values()
            else:
                step[sub] = _single(sub, sub_value, sub_line, sub_body, here)
                if sub == 'uses' and step[sub].strip().startswith('.'):
                    _fail(here, sub_line, 'local actions are not read')
        steps.append(step)
    return steps



def _job(job_id, body, where):
    where = f'{where}: job {job_id}'
    job_if, steps = None, None
    for key, value, line, sub_body in _entries(body, 4, where, None, None):
        if key == 'uses':
            _fail(where, line, 'reusable workflow jobs are not read')
        if key not in JOB_KEYS:
            _fail(where, line, f'key `{key}` is not on the allow-list')
        if key == 'if':
            if not value:
                _fail(where, line, '`if` needs a value')
            job_if = _condition(value, sub_body, 4)
        elif key == 'steps':
            steps = _steps(key, value, line, sub_body, where)
        elif key == 'env':
            _mapping(key, value, line, sub_body, 6, where, None, ENV_NAME)
        elif key == 'defaults':
            _block(key, value, line, where)
            run = _entries(sub_body, 6, f'{where} defaults', {'run'})
            if not run:
                _fail(where, line, '`defaults` is empty')
            _, run_value, run_line, run_body = run[0]
            _mapping('run', run_value, run_line, run_body, 8, f'{where} defaults',
                     {'shell', 'working-directory'})
        elif key == 'strategy':
            _block(key, value, line, where)
            entries = _entries(sub_body, 6, f'{where} strategy',
                               {'fail-fast', 'max-parallel', 'matrix'})
            if not entries:
                _fail(where, line, '`strategy` is empty')
            for sub, sub_value, sub_line, sub_sub in entries:
                if sub == 'matrix':
                    _mapping(sub, sub_value, sub_line, sub_sub, 8, f'{where} strategy',
                             None, JOB_ID, flow_lists=True)
                else:
                    _single(sub, sub_value, sub_line, sub_sub, f'{where} strategy')
        elif key == 'environment' and not value:
            _mapping(key, value, line, sub_body, 6, where, {'name', 'url'})
        else:
            _single(key, value, line, sub_body, where)
    if steps is None:
        raise WorkflowShapeError(f'{where}: no steps block')
    return job_if, steps


def _jobs(text, where):
    lines = [_Line(number, raw) for number, raw in enumerate(text.split('\n'), 1)]
    jobs = None
    for key, value, line, body in _entries(lines, 0, where, TOP_KEYS):
        if key == 'jobs':
            _block(key, value, line, where)
            jobs = _entries(body, 2, f'{where}: jobs', None, JOB_ID)
            for job_id, job_value, job_line, _ in jobs:
                _block(job_id, job_value, job_line, f'{where}: jobs')
    if jobs is None:
        raise WorkflowShapeError(f'{where}: no top-level jobs: key')
    if not jobs:
        raise WorkflowShapeError(f'{where}: no jobs found')
    return [(job_id, body) for job_id, _, _, body in jobs]


def violations(workflow_dir):
    found = []
    files = sorted(Path(workflow_dir).glob('*.y*ml'))
    if not files:
        raise WorkflowShapeError(f'no workflows in {workflow_dir}')
    for path in files:
        try:
            text = path.read_bytes().decode('utf-8').replace('\r\n', '\n')
        except UnicodeDecodeError as error:
            raise WorkflowShapeError(f'{path.name}: not UTF-8: {error}') from error
        _check_text(text, path.name)
        for job_id, body in _jobs(text, path.name):
            job_if, steps = _job(job_id, body, path.name)
            if _guard(job_if):
                continue
            for step in steps:
                decoded = [step['run'], step['uses'] or '', step['name'] or ''] + step['values']
                text = '\n'.join([step['text']] + decoded)
                if not _packages(text, step['run']) or _guard(step['if']):
                    continue
                found.append(f"{path.name}: job {job_id}: step {step['name'] or '(unnamed)'}")
    return found


def main(argv):
    directory = argv[1] if len(argv) > 1 else '.github/workflows'
    try:
        problems = violations(directory)
    except (OSError, WorkflowShapeError) as error:
        print(f'check_workflow_packaging: cannot check workflows: {error}')
        return 2
    for problem in problems:
        print(f'UNGUARDED ANDROID PACKAGING: {problem}')
    print(f'check_workflow_packaging: {len(problems)} unguarded packaging step(s)')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
