# Automatic sync activity — R19

Repository syncs already publish start/end notifications, but NotesBloc previously
kept its busy flag only for a manually requested sync. An automatic sync could
therefore leave the mascot and sync control showing idle.

NotesSource now exposes the repository's existing isSyncing getter. NotesBloc
reads it when created and on source/view updates. A separate manual-operation
flag keeps the busy indicator active during the button's connectivity check.
Manual requests also check the source directly to avoid starting another sync
while an automatic sync is running. No sync scheduling or billing code changes.

## Reproduction and proof

Base: main 415e13d5e7a9d979396342733a3618c6dbe90a23.
Test-only commit: 06646c0c32aba45ea06960b467b1e3fb0a4f6626.

Run with Flutter 3.44.8:

```text
flutter test --no-pub --reporter expanded test/notes_bloc_test.dart test/home_page_test.dart --plain-name R19
```

Before the fix, three regressions fail: initial busy state, automatic start/end
propagation, and the mascot's existing syncing message. The fourth case is a
passing control for retaining busy state during a manual connectivity check.
After the fix all four pass. The source-update test additionally checks preserved
search/selection, suppressed duplicate state, refusal of a second manual sync,
and absence of a manufactured billing notice for automatic activity.

## Boundaries and rollback

These tests use a fake NotesSource and a Flutter widget harness. They do not prove
native lifecycle scheduling, live Google Drive traffic, authenticated device
behavior, or two-device reconciliation. Automatic failure feedback, count-based
Cloud Notes verdicts and R8 billing-message accuracy remain separate work. R19 is
partially addressed, not closed.

The change adds no service, dependency, schema, migration or deployment step.
Rollback is to revert the production fix and its regression tests together; no
stored data needs conversion. Full local analysis/tests and CI analysis/tests/
debug APK results are recorded in the PR and aggregate verification report.
