"""Every Android packaging step in .github/workflows must be opt-in.

A step packages when it builds an APK, app bundle or APK set (flutter build
apk/appbundle, Gradle assemble/bundle tasks, bundletool build-apks) or
uploads a file whose path names an .apk, .aab or .apks. Each such step must
run only when the repository variable is enabled:

- its job's `if:` is a guard, or
- its own `if:` is a guard, where a step may also test
  `env.ATOMIC_ANDROID_PACKAGING == 'enabled'` when its job sets that
  variable from the repository variable (defaulting to 'deferred'), no step
  overrides it in its own `env:`, and no step in the job writes it to
  $GITHUB_ENV.

A guard is a strict allow-list, not a substring match: optionally wrapped in
one `${{ }}`, a condition is a conjunction (`&&`) of simple comparisons
(`name.path == 'literal'` or `!=`), one of which is exactly
`vars.ATOMIC_ANDROID_PACKAGING == 'enabled'` (or the env form above). A
condition with `||`, `!`, a function call, parentheses, quoting around the
whole expression, a comment or a nested expression is not a guard.

This reads this repository's workflow style (two-space job keys, `steps:`
items at six spaces, step keys at eight) rather than parsing all of YAML.
Anything it cannot read for certain fails the check (exit 2) instead of
being skipped: other step indentation, flow-style collections, tabs, YAML
anchors or aliases, reusable workflow jobs (`uses:` on a job) and local
actions (`uses: ./...`). It checks the workflow files only: what a shell
script or helper does at run time is outside what it can prove.

Usage: python3 tool/check_workflow_packaging.py [WORKFLOW_DIR]
"""
from pathlib import Path
import re
import sys

PACKAGING_RUN = re.compile(
    r'flutter\s+build\s+(apk|appbundle)\b'
    r'|gradlew\S*\s+[^\n]*\b(assemble|bundle)\w*'
    r'|bundletool\S*\s+build-apks', re.I)
PACKAGE_PATH = re.compile(r'\.(apk|aab|apks)\b', re.I)
VAR = 'ATOMIC_ANDROID_PACKAGING'
VARS_TERM = f"vars.{VAR} == 'enabled'"
ENV_TERM = f"env.{VAR} == 'enabled'"
JOB_ENV_VALUE = (f"${{{{ vars.{VAR} == 'enabled' && 'enabled' || "
                 f"'deferred' }}}}")
TERM = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)*"
                  r" (==|!=) ('[^'#]*'|true|false|null|-?[0-9]+)")
ANCHOR = re.compile(r'(^|[:-]\s+)[&*][A-Za-z0-9_]|<<:')
GITHUB_ENV_WRITE = re.compile(r'echo\s+"?([A-Za-z_][A-Za-z0-9_]*)=')


class WorkflowShapeError(Exception):
    pass


def _indent(line):
    return len(line) - len(line.lstrip(' '))


def _meaningful(line):
    stripped = line.strip()
    return stripped and not stripped.startswith('#')


def _condition(lines, i, indent):
    """The `if:` value at lines[i], joined when folded (`>-` or `>`)."""
    value = lines[i].strip()[len('if:'):].strip()
    if value in ('>-', '>'):
        parts = []
        for following in lines[i + 1:]:
            if following.strip() and _indent(following) <= indent:
                break
            parts.append(following.strip())
        return ' '.join(p for p in parts if p)
    if value.startswith(('|', '>')):
        return None  # other block scalars are not read
    return value


def _guard(value, terms):
    """True only when [value] requires one of [terms] (strict allow-list)."""
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
    return any(c in terms for c in conjuncts)


def _check_text(text):
    if '\t' in text:
        raise WorkflowShapeError('tab characters are not read')
    for line in text.split('\n'):
        if _meaningful(line) and ANCHOR.search(line.split(' #')[0]):
            raise WorkflowShapeError(f'YAML anchors/aliases are not read: {line.strip()}')


def _jobs(text):
    lines = text.split('\n')
    start = next((i for i, l in enumerate(lines) if l.rstrip() == 'jobs:'), None)
    if start is None:
        raise WorkflowShapeError('no top-level jobs: key')
    jobs, current = [], None
    for line in lines[start + 1:]:
        if not _meaningful(line):
            if current is not None:
                current[1].append(line)
            continue
        indent = _indent(line)
        if indent == 0:
            break  # the next top-level key
        if indent == 2:
            match = re.fullmatch(r'  ([A-Za-z0-9_-]+):\s*(#.*)?', line.rstrip())
            if not match:
                raise WorkflowShapeError(f'unreadable job line: {line.strip()}')
            current = (match.group(1), [])
            jobs.append(current)
        elif indent < 4 or current is None:
            raise WorkflowShapeError(f'unreadable line under jobs: {line.strip()}')
        else:
            current[1].append(line)
    if not jobs:
        raise WorkflowShapeError('no jobs found')
    return jobs


def _job(name, lines):
    """Splits a job into its own `if:`, `env:` entries and steps."""
    job_if, env, steps, i = None, {}, None, 0
    while i < len(lines):
        line = lines[i]
        if not _meaningful(line) or _indent(line) != 4:
            i += 1
            continue
        key = line.strip()
        if re.match(r'-|[\[{]', key) or ': [' in key or ': {' in key:
            raise WorkflowShapeError(f'job {name}: flow or list syntax: {key}')
        if key.startswith('uses:'):
            raise WorkflowShapeError(f'job {name}: reusable workflow jobs are not read')
        if key.startswith('if:'):
            job_if = _condition(lines, i, 4)
        elif key.split('#')[0].strip() == 'env:':
            for entry in lines[i + 1:]:
                if not _meaningful(entry):
                    continue
                if _indent(entry) <= 4:
                    break
                match = re.fullmatch(r'      ([A-Za-z0-9_]+):\s*(.*)', entry.rstrip())
                if not match:
                    raise WorkflowShapeError(f'job {name}: unreadable env entry')
                env[match.group(1)] = match.group(2).strip()
        elif key.startswith('steps:'):
            if key.split('#')[0].strip() != 'steps:':
                raise WorkflowShapeError(f'job {name}: steps must be a block list')
            steps = _steps(name, lines[i + 1:])
        i += 1
    return job_if, env, steps or []


def _steps(name, lines):
    steps = []
    for line in lines:
        if not _meaningful(line):
            if steps:
                steps[-1].append(line)
            continue
        indent = _indent(line)
        if indent <= 4:
            if indent == 4 and line.strip().startswith('-'):
                raise WorkflowShapeError(
                    f'job {name}: steps list items must be indented six spaces')
            break
        if indent == 6:
            if not line.startswith('      - '):
                raise WorkflowShapeError(f'job {name}: unreadable step line: {line.strip()}')
            first = line[8:]
            if first.startswith(('{', '[', '-')):
                raise WorkflowShapeError(f'job {name}: flow-style step')
            steps.append(['        ' + first])
        elif not steps:
            raise WorkflowShapeError(f'job {name}: unreadable steps block')
        elif indent == 7:
            raise WorkflowShapeError(f'job {name}: step keys must be indented eight spaces')
        else:
            steps[-1].append(line)
    return steps


def _step_key(step, key):
    """Line index of a direct step key (eight spaces), or None."""
    for i, line in enumerate(step):
        if _indent(line) == 8 and re.match(rf'{key}:(\s|$)', line.strip()):
            return i
    return None


def violations(workflow_dir):
    found = []
    files = sorted(Path(workflow_dir).glob('*.y*ml'))
    if not files:
        raise WorkflowShapeError(f'no workflows in {workflow_dir}')
    for path in files:
        text = path.read_text(encoding='utf-8').replace('\r\n', '\n')
        _check_text(text)
        for job_name, job_lines in _jobs(text):
            job_if, env, steps = _job(job_name, job_lines)
            job_guard = _guard(job_if, {VARS_TERM})
            writes_var = any(
                VAR in line and 'GITHUB_ENV' in line
                for step in steps for line in step) or any(
                m.group(1) == VAR for step in steps for line in step
                for m in GITHUB_ENV_WRITE.finditer(line))
            env_derived = env.get(VAR) == JOB_ENV_VALUE and not writes_var
            for step in steps:
                text_of_step = '\n'.join(step)
                uses = _step_key(step, 'uses')
                if uses is not None and step[uses].strip()[5:].strip().startswith('./'):
                    raise WorkflowShapeError(
                        f'{path.name}: job {job_name}: local actions are not read')
                uploads = 'actions/upload-artifact' in text_of_step
                packages = bool(PACKAGING_RUN.search(text_of_step)) or (
                    uploads and PACKAGE_PATH.search(text_of_step))
                if not packages or job_guard:
                    continue
                step_env = _step_key(step, 'env')
                overrides = step_env is not None and any(
                    re.match(rf'\s*{VAR}\s*:', line)
                    for line in step[step_env + 1:]
                    if _indent(line) > 8)
                if_line = _step_key(step, 'if')
                step_if = _condition(step, if_line, 8) if if_line is not None else None
                terms = {VARS_TERM} | ({ENV_TERM} if env_derived and not overrides else set())
                if _guard(step_if, terms):
                    continue
                name_line = _step_key(step, 'name')
                name = step[name_line].strip()[5:].strip() if name_line is not None else '(unnamed)'
                found.append(f'{path.name}: job {job_name}: step {name}')
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
