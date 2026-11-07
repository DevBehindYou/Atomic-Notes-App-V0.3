# Startup phase trace (C01)

`lib/utility/startup_trace.dart` times each pre-first-frame step in `main()`.
The steps are API init, Hive init, the auth/sync boxes, screen security,
profile, sync status, quota, vault and repository. Tracing is opt-in:

```text
flutter run --profile --dart-define=ATOMIC_STARTUP_TRACE=true
```

## Behavior

- **Off by default**, and always off in release builds (`!kReleaseMode`). When
  off, `step()` returns the body's own future. There is no clock, timeline event
  or output, and the order is unchanged. A test asserts that the returned future
  is the same object as the body's.
- **When on**, each step becomes a `dart:developer` `TimelineTask` with filter
  key `atomic-startup`, visible in DevTools. `finish()` prints one line, for
  example `startup-trace: apiInit=1.5ms hiveInit=12.0ms vault=0.3ms!`. A `!`
  marks a step that threw. The error itself is rethrown unchanged.
- **Privacy:** the labels are a fixed enum (`StartupStep`). Error messages are
  never recorded, and no account, token or note data enters a span.
- **Scope of the timing:** spans cover the Dart futures only. They do not cover
  engine start, the OS splash, the first frame or Home readiness. They are not
  device startup time and must not be reported as such.

## Overhead

On the host VM (Windows, `flutter test`), an enabled empty step costs about
48 µs, measured over 2,000 runs by the informational test. For 10 steps that is
under 1 ms. This is not a device figure. When tracing is off there is no added
work beyond one boolean check and the call itself.

## Verification

```text
flutter test --no-pub test/startup_trace_test.dart test/startup_vault_network_test.dart test/splash_startup_test.dart
flutter analyze --no-pub --fatal-warnings --fatal-infos
```

## Device use (QA scope, not executed here)

Use a profile build with the dart-define. Collect the `startup-trace:` line over
the same five or more cold launches as the startup-vault acceptance row. Report
the timings separately from `am start -W` and from Home readiness. Keep the
phone's existing lock, two-factor and vault settings (Codex review Q2).
