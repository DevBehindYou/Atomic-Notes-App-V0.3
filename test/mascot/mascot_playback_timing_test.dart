import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_frame_source.dart';
import 'package:atomic_notes/mascot/mascot_playback_controller.dart';

class Clock implements MascotScheduler {
  @override
  Duration now = Duration.zero;
  final List<Job> jobs = [];
  @override
  MascotScheduledTask schedule(Duration d, void Function() f) {
    final j = Job(now + d, f);
    jobs.add(j);
    return j;
  }

  void elapse(Duration d) {
    now += d;
    for (final j in List<Job>.of(jobs)) {
      if (!j.canceled && j.at <= now) {
        j.canceled = true;
        j.f();
      }
    }
  }

  int get active => jobs.where((j) => !j.canceled).length;
}

class Job implements MascotScheduledTask {
  Job(this.at, this.f);
  final Duration at;
  final void Function() f;
  bool canceled = false;
  @override
  void cancel() {
    canceled = true;
  }
}

class Source implements MascotFrameSource {
  final List<Session> sessions = [];
  final List<String> ids = [];
  Completer<OwnedMascotFrame>? delayed;
  Duration duration = const Duration(milliseconds: 50);
  int closeFailures = 0;
  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async {
    ids.add(clip.id);
    final s = Session(this);
    sessions.add(s);
    return s;
  }
}

class Session implements MascotFrameSession {
  Session(this.source);
  final Source source;
  int reads = 0, closes = 0;
  @override
  int get frameCount => 2;
  final List<OwnedMascotFrame> frames = [];
  @override
  Future<OwnedMascotFrame> nextFrame() async {
    reads++;
    if (source.delayed != null) {
      return source.delayed!.future;
    }
    final p = ui.PictureRecorder();
    ui.Canvas(p);
    final pic = p.endRecording();
    final image = await pic.toImage(1, 1);
    pic.dispose();
    final f = OwnedMascotFrame(image, source.duration);
    frames.add(f);
    return f;
  }

  @override
  Future<void> close() async {
    closes++;
    if (source.closeFailures > 0) {
      source.closeFailures--;
      throw StateError('lease_cleanup');
    }
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual variable frame deadlines and one cycle, no embedded loop',
      () async {
    final s = Source();
    final clock = Clock();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: s,
        targetPhysicalPixels: 48,
        scheduler: clock);
    c.setPlaybackAllowed(true);
    await settle();
    expect(s.sessions.single.reads, 1);
    clock.elapse(const Duration(milliseconds: 49));
    await settle();
    expect(s.sessions.single.reads, 1);
    clock.elapse(const Duration(milliseconds: 1));
    await settle();
    expect(s.sessions.single.reads, 2);
    clock.elapse(const Duration(milliseconds: 50));
    await settle();
    expect(s.sessions.length, 2);
    expect(s.sessions.first.closes, 1);
    await c.close();
    expect(s.sessions.expand((s) => s.frames).every((f) => f.isDisposed), true);
  });
  test('tap coalesces to a single latest pending advance', () async {
    final s = Source();
    final clock = Clock();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: s,
        targetPhysicalPixels: 48,
        scheduler: clock);
    c.setPlaybackAllowed(true);
    await settle();
    c.advanceFromUser();
    await settle();
    for (var i = 0; i < 100; i++) {
      c.advanceFromUser();
    }
    await settle();
    expect(s.sessions.length, 2);
    clock.elapse(const Duration(milliseconds: 250));
    await settle();
    expect(s.sessions.length, 3);
    expect(s.ids[1], isNot(s.ids[2]));
    await c.close();
  });
  test(
      'hidden delayed frame is disposed without publication and no further decode',
      () async {
    final s = Source();
    final delayed = Completer<OwnedMascotFrame>();
    s.delayed = delayed;
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: s,
        targetPhysicalPixels: 48);
    c.setPlaybackAllowed(true);
    await settle();
    c.setPlaybackAllowed(false, visible: false);
    final p = ui.PictureRecorder();
    ui.Canvas(p);
    final pic = p.endRecording();
    final f = OwnedMascotFrame(
        await pic.toImage(1, 1), const Duration(milliseconds: 40));
    pic.dispose();
    delayed.complete(f);
    await settle();
    expect(f.isDisposed, true);
    expect(c.frame, isNull);
    expect(s.sessions.single.reads, 1);
    expect(s.sessions.single.closes, 1);
    await c.close();
  });
  test('still closes after first frame and zero duration never schedules',
      () async {
    final s = Source();
    final clock = Clock();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: s,
        targetPhysicalPixels: 48,
        scheduler: clock);
    c.setPlaybackAllowed(false);
    await settle();
    expect(s.sessions.single.reads, 1);
    expect(s.sessions.single.closes, 1);
    expect(clock.active, 0);
    expect(c.state, MascotPlaybackState.still);
    s.duration = Duration.zero;
    c.setPlaybackAllowed(true);
    await settle();
    expect(clock.active, 0);
    await c.close();
  });
  test('first still-frame tap always chooses another variation', () async {
    for (var seed = 0; seed < 20; seed++) {
      final source = Source();
      final c = MascotPlaybackController(
          mascot: MascotCatalog.defaultMascot,
          source: source,
          targetPhysicalPixels: 48,
          random: Random(seed));
      c.setPlaybackAllowed(false);
      await settle();
      c.advanceFromUser();
      await settle();
      expect(source.ids[1], isNot(source.ids[0]), reason: 'seed $seed');
      await c.close();
    }
  });
  test(
      'cleanup rejection reports failure and explicit retry keeps queue usable',
      () async {
    final source = Source()..closeFailures = 1;
    final clock = Clock();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: source,
        targetPhysicalPixels: 48,
        scheduler: clock);
    c.setPlaybackAllowed(true);
    await settle();
    clock.elapse(const Duration(milliseconds: 50));
    await settle();
    clock.elapse(const Duration(milliseconds: 50));
    await settle();
    expect(c.state, MascotPlaybackState.failed);
    expect(c.errorCode, 'mascot_cleanup_failed');

    expect(source.sessions.length, 1);
    c.retry();
    await settle();
    expect(c.state, MascotPlaybackState.frame);
    expect(source.sessions.length, 2);
    expect(source.sessions.first.closes, 2);
    await c.close();
    expect(source.sessions.last.closes, 1);
    expect(source.sessions.expand((s) => s.frames).every((f) => f.isDisposed),
        true);
  });
  test('dispose contains transient cleanup rejection and finishes cleanup',
      () async {
    final source = Source()..closeFailures = 1;
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: source,
        targetPhysicalPixels: 48);
    c.setPlaybackAllowed(true);
    await settle();
    c.dispose();
    await settle();
    expect(source.sessions.single.closes, 2);
    expect(source.sessions.single.frames.every((f) => f.isDisposed), true);
  });
  test(
      'repeated cleanup failure is bounded and owned session remains retryable',
      () async {
    final source = Source()..closeFailures = 3;
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: source,
        targetPhysicalPixels: 48);
    c.setPlaybackAllowed(true);
    await settle();
    await c.close();
    expect(source.sessions.single.closes, 2);
    expect(c.errorCode, 'mascot_cleanup_failed');
    await c.close();
    expect(source.sessions.single.closes, 4);
    expect(source.sessions.single.frames.every((f) => f.isDisposed), true);
  });
}
