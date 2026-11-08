# CI artifact secret scan (C46, App part)

`Flutter verification` (`.github/workflows/flutter-ci.yml`) now scans what each
job is about to upload, and refuses the uploads if any of it holds a secret.
The Server repository has the matching check in its own CI (Server PR #97).

## What already existed

These were verified, not changed:

- `flutter pub get --enforce-lockfile` and a pinned Flutter 3.44.8.
- `tool/record_flutter_verification.py`, which records the source head, the
  `pubspec.lock` SHA-256 and the debug APK SHA-256 and size.
- Placeholder, non-production configuration from `cred.example.dart`.
- Sanitized, bounded proof files from each fixture.

## Added

`tool/scan_ci_artifacts.py` and its tests in
`tool/test_scan_ci_artifacts.py`. The CI runs those tests too.

### What it scans for

- the exact values of environment variables whose names end in `KEY`,
  `SECRET`, `TOKEN`, `PASSWORD` or `CANARY`;
- credentialed URIs;
- credential shapes: PEM private keys, Google access and refresh tokens,
  client secrets and API keys, and JWTs.

### How it reports

- **Positive control.** A random per-run canary (`ATOMIC_CI_CANARY`) must be
  detected in a synthetic sample before the result is trusted.
- **Report contents.** The report, `ci-artifact-scan-proof.json`, names the
  file and the kind of each finding. It never includes the value or where it
  appeared.
- **Not scanned.** Binary images and packages (PNG previews, the APK) are
  skipped and counted.
- **Oversized files.** A file over 8 MiB is reported as a finding.

### Workflow order

In each job, every artifact upload now runs at the end, after the scan step,
and only when the scan succeeded. Before this change, uploads were interleaved
with the steps that produced them.

- **APK recorder.** The verification recorder reads the APK upload's outcome,
  so it now runs after that upload.
- **Second scan.** The recorder's proof is scanned again on its own before it
  is uploaded.

### What a failure means

The scan fails only when an upload would be unsafe: a finding, or a canary
that was not detected. Failed tests still fail their own steps.

## Not in scope

- No signed release and no deployment.
- Codex's reserved `device-acceptance.yml` and `staging-android.yml` are not
  changed.
- Web repository CI is blocked with the rest of the W lane.
