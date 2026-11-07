import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// The pre-first-frame initialization steps in main(), in their run order.
/// Labels are fixed names, so a trace never carries account or note data.
enum StartupStep {
  apiInit,
  hiveInit,
  authBox,
  screenSecurity,
  profile,
  syncBox,
  syncStatus,
  quota,
  vault,
  repository,
}

enum StartupOutcome { ok, error }

/// One finished step: how long its future took and whether it completed.
@immutable
class StartupSpan {
  const StartupSpan(this.step, this.elapsed, this.outcome);
  final StartupStep step;
  final Duration elapsed;
  final StartupOutcome outcome;

  @override
  String toString() =>
      '${step.name}=${(elapsed.inMicroseconds / 1000).toStringAsFixed(1)}ms'
      '${outcome == StartupOutcome.ok ? '' : '!'}';
}

/// Opt-in timing of main()'s startup steps, for profile/debug measurement.
///
/// Off unless the build passes `--dart-define=ATOMIC_STARTUP_TRACE=true`, and
/// always off in release builds. When off, [step] only runs the body: no clock,
/// timeline event or output. When on, each step is a `dart:developer` timeline
/// task (visible in DevTools) and [finish] prints one summary line.
///
/// Spans time the Dart futures only. They do not include engine start, the
/// native splash or the first frame, so they are not device startup time.
class StartupTrace {
  StartupTrace({
    required this.enabled,
    Stopwatch Function()? clock,
    void Function(String line)? sink,
  })  : _clock = clock ?? Stopwatch.new,
        _sink = sink ?? debugPrint;

  /// The trace used by main(), configured from the build.
  factory StartupTrace.fromEnvironment() => StartupTrace(
      enabled:
          !kReleaseMode && const bool.fromEnvironment('ATOMIC_STARTUP_TRACE'));

  final bool enabled;
  final Stopwatch Function() _clock;
  final void Function(String line) _sink;
  final List<StartupSpan> _spans = [];
  bool _finished = false;

  List<StartupSpan> get spans => List.unmodifiable(_spans);

  /// Runs [body] as [label], recording its duration and outcome when enabled.
  /// Errors are recorded and rethrown unchanged; their messages are not kept.
  Future<T> step<T>(StartupStep label, Future<T> Function() body) =>
      enabled ? _timed(label, body) : body();

  Future<T> _timed<T>(StartupStep label, Future<T> Function() body) async {
    final task = developer.TimelineTask(filterKey: 'atomic-startup')
      ..start(label.name);
    final watch = _clock()..start();
    var outcome = StartupOutcome.error;
    try {
      final value = await body();
      outcome = StartupOutcome.ok;
      return value;
    } finally {
      watch.stop();
      task.finish(arguments: {'outcome': outcome.name});
      _spans.add(StartupSpan(label, watch.elapsed, outcome));
    }
  }

  /// Prints the summary once. Steps never reached are simply absent.
  void finish() {
    if (!enabled || _finished) return;
    _finished = true;
    _sink('startup-trace: ${_spans.join(' ')}');
  }
}
