import 'dart:async';

import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stopwatch that reports a fixed duration, so summaries are deterministic.
class _FixedWatch implements Stopwatch {
  _FixedWatch(this._elapsed);
  final Duration _elapsed;
  @override
  Duration get elapsed => _elapsed;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('default build has tracing off', () {
    expect(StartupTrace.fromEnvironment().enabled, isFalse);
  });

  test('disabled trace only runs the body: no clock, spans or output',
      () async {
    var clocks = 0;
    final lines = <String>[];
    final trace = StartupTrace(
        enabled: false,
        clock: () {
          clocks++;
          return Stopwatch();
        },
        sink: lines.add);
    final body = Future<int>.value(7);
    final returned = trace.step(StartupStep.apiInit, () => body);
    expect(identical(returned, body), isTrue,
        reason: 'the step future is the body future itself');
    expect(await returned, 7);
    await expectLater(
        trace.step(
            StartupStep.vault, () => Future<void>.error(StateError('x'))),
        throwsStateError);
    trace.finish();
    expect(clocks, 0);
    expect(trace.spans, isEmpty);
    expect(lines, isEmpty);
  });

  for (final enabled in [false, true]) {
    test('body starts synchronously, in call order (enabled: $enabled)',
        () async {
      final trace = StartupTrace(enabled: enabled, sink: (_) {});
      final started = <StartupStep>[];
      final first = Completer<void>();
      final a = trace.step(StartupStep.hiveInit, () {
        started.add(StartupStep.hiveInit);
        return first.future;
      });
      expect(started, [StartupStep.hiveInit]);
      first.complete();
      await a;
      await trace.step(StartupStep.authBox, () async {
        started.add(StartupStep.authBox);
      });
      expect(started, [StartupStep.hiveInit, StartupStep.authBox]);
    });
  }

  test('enabled trace records each step in order with its outcome', () async {
    final lines = <String>[];
    final durations = [
      const Duration(microseconds: 1500),
      const Duration(milliseconds: 12),
      const Duration(microseconds: 250),
    ];
    var next = 0;
    final trace = StartupTrace(
        enabled: true,
        clock: () => _FixedWatch(durations[next++]),
        sink: lines.add);
    expect(await trace.step(StartupStep.apiInit, () async => 'token-free'),
        'token-free');
    await trace.step(StartupStep.hiveInit, () async {});
    await expectLater(
        trace.step(StartupStep.vault,
            () async => throw StateError('private note title')),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'private note title')));
    trace.finish();
    trace.finish();

    expect(trace.spans.map((s) => s.step),
        [StartupStep.apiInit, StartupStep.hiveInit, StartupStep.vault]);
    expect(trace.spans.map((s) => s.outcome), [
      StartupOutcome.ok,
      StartupOutcome.ok,
      StartupOutcome.error,
    ]);
    expect(
        lines, ['startup-trace: apiInit=1.5ms hiveInit=12.0ms vault=0.3ms!']);
    expect(lines.single, isNot(contains('private')),
        reason: 'error messages are never recorded');
  });

  test('a body that throws synchronously still closes its span', () async {
    final trace = StartupTrace(enabled: true, sink: (_) {});
    await expectLater(
        trace.step<void>(StartupStep.quota, () => throw ArgumentError('x')),
        throwsArgumentError);
    expect(trace.spans.single.outcome, StartupOutcome.error);
  });

  test('summary labels are only the fixed step names', () async {
    final lines = <String>[];
    final trace = StartupTrace(enabled: true, sink: lines.add);
    for (final step in StartupStep.values) {
      await trace.step(step, () async {});
    }
    trace.finish();
    final labels = lines.single
        .substring('startup-trace: '.length)
        .split(' ')
        .map((part) => part.split('=').first)
        .toList();
    expect(labels, StartupStep.values.map((s) => s.name).toList());
  });

  test('measures enabled per-step overhead (informational)', () async {
    final trace = StartupTrace(enabled: true, sink: (_) {});
    const runs = 2000;
    final watch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      await trace.step(StartupStep.syncBox, () async {});
    }
    watch.stop();
    final perStep = watch.elapsedMicroseconds / runs;
    // Host-VM figure only; recorded in the task doc, not a device number.
    // ignore: avoid_print
    print('startup-trace overhead: ${perStep.toStringAsFixed(2)} us/step');
    expect(trace.spans, hasLength(runs));
    expect(perStep, lessThan(1000), reason: 'well under 1 ms per step');
  });
}
