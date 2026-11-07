# Startup sequence harness (C02)

`main()` now runs its pre-first-frame work through
`runStartupSequence(StartupServices, StartupTrace)` in
`lib/utility/startup_sequence.dart`. The steps, their order, the 8-second API
bound and the local-first fallback are the same as before. The function was
moved out of `main()` unchanged, so tests can inject services. `main()` still
shows `StartupFailedApp` on any other failure.

## Deterministic gates (`test/startup_sequence_test.dart`)

- Every step runs once, in the fixed order. The trace spans match
  `StartupStep.values`.
- Each step starts only after the previous one finishes. Every step is held
  open in turn to check this.
- A failing API init is tolerated, and the remaining steps still run.
- A hung API init falls back at exactly `apiInitTimeout` (8 s, fake time). It
  is still waiting at 8 s − 1 ms.
- A failure in any later step stops startup and is rethrown, and no later step
  runs. There are nine cases, one per step.
- A returning-user start through the real `ApiClient` and `Vault` makes **one**
  `GET /api/vault`. The splash's first check then adds none. A second serial
  request would fail this gate.

## Synthetic report (`tool/startup_benchmark.dart`)

```text
flutter test --no-pub tool/startup_benchmark.dart
STARTUP_BENCHMARK_OUT=<path> flutter test --no-pub tool/startup_benchmark.dart
```

The tool prints one `startup-benchmark:` JSON line. If `STARTUP_BENCHMARK_OUT`
is set, it also writes the line to that file. It covers four scenarios:
healthy, noVault, offline and apiHangs. For each scenario it reports:

- the call order;
- the outcome of each step;
- the vault request count before the first frame, and through the splash;
- the fake elapsed milliseconds.

Local steps use a fixed 5 ms synthetic delay. The report is labelled
`synthetic: true`. It is **not** a device measurement and must not be reported
as one.

Last local run, Windows, Flutter 3.44.8:

| Scenario | Vault requests before first frame / through splash | Fake elapsed |
| --- | --- | --- |
| healthy | 1 / 1 | 40 ms |
| noVault | 1 / 2 | 40 ms |
| offline | 1 / 2 | 40 ms |
| apiHangs | 1 / 1 | 8,040 ms |

The noVault and offline scenarios refresh at the splash by design (PR #122).

## Verification

```text
flutter test --no-pub test/startup_sequence_test.dart        # 14 passed
flutter test --no-pub tool/startup_benchmark.dart            # 4 passed
flutter analyze --no-pub --fatal-warnings --fatal-infos      # no issues
flutter test --no-pub                                        # 1121 passed, 33 skipped
```
