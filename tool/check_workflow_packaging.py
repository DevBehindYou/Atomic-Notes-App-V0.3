"""Every Android packaging path in .github/workflows must be opt-in.

A step packages when it builds an APK, app bundle or APK set (flutter build
apk/appbundle, Gradle assemble/bundle tasks, bundletool build-apks) or
uploads a file whose path names an .apk, .aab or .apks. Each such step must
be guarded by `vars.ATOMIC_ANDROID_PACKAGING == 'enabled'`, either on its job
or on the step itself. A step-level guard may test
`env.ATOMIC_ANDROID_PACKAGING == 'enabled'` only when the job defines that
variable from the repository variable, defaulting to 'deferred'.

This is a line-based check of this repository's workflow style (two-space
job keys, six-space step items), not a general YAML parser. A workflow it
cannot split into jobs and steps fails rather than passing.

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
VARS_GUARD = "vars.ATOMIC_ANDROID_PACKAGING == 'enabled'"
ENV_GUARD = "env.ATOMIC_ANDROID_PACKAGING == 'enabled'"
JOB_ENV_DEFINITION = re.compile(
    r"^\s+ATOMIC_ANDROID_PACKAGING:\s*\$\{\{\s*vars\.ATOMIC_ANDROID_PACKAGING\s*==\s*'enabled'"
    r"\s*&&\s*'enabled'\s*\|\|\s*'deferred'\s*\}\}\s*$", re.M)


class WorkflowShapeError(Exception):
    pass


def _if_value(block, indent):
    """The `if:` condition at exactly [indent] spaces, joined across lines."""
    lines = block.split('\n')
    for i, line in enumerate(lines):
        match = re.match(rf'^ {{{indent}}}if:\s*(.*)$', line)
        if not match:
            continue
        value = match.group(1).strip()
        if value in ('>-', '>', '|', '|-'):
            parts = []
            for following in lines[i + 1:]:
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                parts.append(following.strip())
            value = ' '.join(parts)
        return value
    return ''


def _jobs(text):
    match = re.search(r'^jobs:\s*$', text, re.M)
    if not match:
        raise WorkflowShapeError('no jobs: key')
    body = text[match.end():]
    starts = list(re.finditer(r'^  ([A-Za-z0-9_-]+):\s*$', body, re.M))
    if not starts:
        raise WorkflowShapeError('no jobs found')
    for i, start in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(body)
        yield start.group(1), body[start.start():end]


def _steps(job):
    match = re.search(r'^    steps:\s*$', job, re.M)
    if not match:
        return []
    body = job[match.end():]
    starts = list(re.finditer(r'^      - ', body, re.M))
    steps = []
    for i, start in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(body)
        steps.append(body[start.start():end])
    return steps


def violations(workflow_dir):
    found = []
    files = sorted(Path(workflow_dir).glob('*.y*ml'))
    if not files:
        raise WorkflowShapeError(f'no workflows in {workflow_dir}')
    for path in files:
        text = path.read_text(encoding='utf-8').replace('\r\n', '\n')
        for job_name, job in _jobs(text):
            job_guard = VARS_GUARD in _if_value(job, 4)
            env_defined = bool(JOB_ENV_DEFINITION.search(job))
            for step in _steps(job):
                uploads = 'actions/upload-artifact' in step
                packages = bool(PACKAGING_RUN.search(step)) or (
                    uploads and PACKAGE_PATH.search(step))
                if not packages or job_guard:
                    continue
                step_if = _if_value(step.replace('      - ', '        ', 1), 8)
                if VARS_GUARD in step_if or (ENV_GUARD in step_if and env_defined):
                    continue
                name = re.search(r'name:\s*(.+)', step)
                found.append(f'{path.name}: job {job_name}: step '
                             f'{name.group(1).strip() if name else "(unnamed)"}')
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
