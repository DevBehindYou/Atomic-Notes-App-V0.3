import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'mascot_catalog.dart';
import 'mascot_frame_source.dart';
import 'mascot_sequence.dart';

enum MascotPlaybackState { loading, frame, still, failed, disposed }

abstract interface class MascotScheduledTask {
  void cancel();
}

abstract interface class MascotScheduler {
  Duration get now;
  MascotScheduledTask schedule(Duration delay, void Function() callback);
}

class TimerMascotScheduler implements MascotScheduler {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  Duration get now => _watch.elapsed;
  @override
  MascotScheduledTask schedule(Duration delay, void Function() callback) =>
      _TimerTask(Timer(delay, callback));
}

class _TimerTask implements MascotScheduledTask {
  _TimerTask(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}

/// Owns one session and one published image. All decoder operations serialize.
/// The view supplies a release callback that retires painted images post-frame.
class MascotPlaybackController extends ChangeNotifier {
  MascotPlaybackController(
      {required MascotDefinition mascot,
      required this.source,
      required this.targetPhysicalPixels,
      MascotScheduler? scheduler,
      Random? random,
      void Function(OwnedMascotFrame)? releaseFrame})
      : _mascot = mascot,
        scheduler = scheduler ?? TimerMascotScheduler(),
        _random = random ?? Random(),
        _release = releaseFrame ?? ((f) => f.dispose()) {
    _sequence = MascotSequence(_random, mascot.clips.map((c) => c.slot));
  }
  final MascotFrameSource source;
  final MascotScheduler scheduler;
  final Random _random;
  final void Function(OwnedMascotFrame) _release;
  int targetPhysicalPixels;
  MascotDefinition _mascot;
  late MascotSequence _sequence;
  MascotPlaybackState state = MascotPlaybackState.loading;
  OwnedMascotFrame? frame;
  String? clipId;
  String? errorCode;
  int generation = 0;
  bool _allowed = false, _visible = false, _closed = false;
  MascotFrameSession? _session;
  MascotClip? _clip;
  int _frames = 0;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  MascotScheduledTask? _timer, _tapTimer;
  Duration? _lastTap;
  bool _restartQueued = false, _restartFromUser = false;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _replace(OwnedMascotFrame? next) {
    final old = frame;
    frame = next;
    if (old != null) _release(old);
  }

  void _enqueue(Future<void> Function() work) {
    _tail = _tail.then((_) async {
      try {
        await work();
      } catch (error) {
        errorCode = error is _MascotCleanupFailure
            ? 'mascot_cleanup_failed'
            : 'mascot_playback_failed';
        _timer?.cancel();
        _tapTimer?.cancel();
        if (!_closed) {
          _replace(null);
          state = MascotPlaybackState.failed;
          _notify();
        }
      }
    });
  }

  bool _current(int gen) => !_closed && generation == gen && _visible;
  Future<void> _closeSession() async {
    final session = _session;
    if (session == null) return;
    try {
      await session.close();
      if (identical(_session, session)) _session = null;
    } catch (_) {
      // Keep ownership so explicit retry/final close can retry cleanup.
      throw const _MascotCleanupFailure();
    }
  }

  void setMascot(MascotDefinition mascot) {
    if (_closed || _mascot.id == mascot.id) return;
    _mascot = mascot;
    _sequence = MascotSequence(_random, mascot.clips.map((c) => c.slot));
    _replace(null);
    _clip = null;
    _lastTap = null;
    _restart();
  }

  void setTargetPhysicalPixels(int pixels) {
    if (targetPhysicalPixels == pixels) return;
    targetPhysicalPixels = pixels;
    _restart();
  }

  void setPlaybackAllowed(bool allowed, {bool visible = true}) {
    if (_closed || (_allowed == allowed && _visible == visible)) return;
    _allowed = allowed;
    _visible = visible;
    _restart();
  }

  void _restart({bool user = false}) {
    if (_closed) return;
    ++generation;
    _timer?.cancel();
    _tapTimer?.cancel();
    _tapTimer = null;
    state = MascotPlaybackState.loading;
    errorCode = null;
    _restartFromUser = user;
    if (!_restartQueued) {
      _restartQueued = true;
      _enqueue(() async {
        _restartQueued = false;
        final gen = generation;
        final fromUser = _restartFromUser;
        await _closeSession();
        if (!_current(gen)) return;
        await _start(gen, poster: !_allowed, user: fromUser);
      });
    }
    _notify();
  }

  Future<void> _start(int gen,
      {required bool poster, bool user = false}) async {
    // Initial static artwork participates in adjacency avoidance too.
    if (poster && !user && _clip == null) {
      _sequence = MascotSequence(_random, _mascot.clips.map((c) => c.slot),
          previousSlot: _mascot.clips.first.slot);
    }
    int? slot = poster && !user && _clip == null
        ? _mascot.clips.first.slot
        : _sequence.next();
    while (_current(gen) && slot != null) {
      final clip = _mascot.clips.firstWhere((c) => c.slot == slot);
      _clip = clip;
      clipId = clip.id;
      try {
        final session = await source.open(clip, targetPhysicalPixels);
        _session = session;
        if (!_current(gen)) {
          await _closeSession();
          return;
        }
        _frames = 0;
        await _decode(gen, poster: poster);
        return;
      } catch (error) {
        if (error is _MascotCleanupFailure) rethrow;
        await _closeSession();
        if (!_current(gen)) return;
        _sequence.excludeFailed(clip.slot);
        slot = _sequence.next();
      }
    }
    if (_current(gen)) {
      _replace(null);
      state = MascotPlaybackState.failed;
      _notify();
    }
  }

  Future<void> _decode(int gen, {bool poster = false}) async {
    final session = _session!;
    final next = await session.nextFrame();
    if (!_current(gen)) {
      next.dispose();
      await _closeSession();
      return;
    }
    _frames++;
    _replace(next);
    state = poster ? MascotPlaybackState.still : MascotPlaybackState.frame;
    _notify();
    if (poster) {
      await _closeSession();
      return;
    }
    if (!_current(gen)) {
      await _closeSession();
      return;
    }
    // A zero duration is indefinite, never a zero-delay busy loop.
    if (next.duration <= Duration.zero) {
      await _closeSession();
      return;
    }
    _timer = scheduler.schedule(
        next.duration,
        () => _enqueue(() async {
              if (!_current(gen) || !_allowed) return;
              if (_frames >= session.frameCount) {
                await _closeSession();
                await _start(gen, poster: false);
              } else {
                try {
                  await _decode(gen);
                } catch (error) {
                  if (error is _MascotCleanupFailure) rethrow;
                  await _closeSession();
                  if (!_current(gen)) return;
                  _sequence.excludeFailed(_clip!.slot);
                  await _start(gen, poster: false);
                }
              }
            }));
  }

  void advanceFromUser() {
    if (_closed || !_visible) return;
    final last = _lastTap;
    if (last != null &&
        scheduler.now - last < const Duration(milliseconds: 250)) {
      _tapTimer ??= scheduler.schedule(
          const Duration(milliseconds: 250) - (scheduler.now - last), () {
        _tapTimer = null;
        _lastTap = scheduler.now;
        _restart(user: true);
      });
      return;
    }
    _lastTap = scheduler.now;
    _restart(user: true);
  }

  void retry() {
    if (_closed) return;
    _sequence.reset();
    _clip = null;
    _restart();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    generation++;
    _timer?.cancel();
    _tapTimer?.cancel();
    _replace(null);
    state = MascotPlaybackState.disposed;
    return _closing = _tail.then((_) async {
      // One bounded retry handles transient lease cleanup during disposal.
      for (var attempt = 0; attempt < 2 && _session != null; attempt++) {
        try {
          await _closeSession();
        } catch (_) {
          errorCode = 'mascot_cleanup_failed';
        }
      }
    }).whenComplete(() {
      _closing = null;
    });
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

class _MascotCleanupFailure implements Exception {
  const _MascotCleanupFailure();
}
