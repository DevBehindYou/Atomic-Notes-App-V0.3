import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/flutter_gif_frame_source.dart';

class Lease implements MascotAssetLease {
  Lease(this.bytes);
  @override
  final Uint8List bytes;
  int closes = 0;
  int failures = 0;
  @override
  Future<void> close() async {
    closes++;
    if (failures > 0) {
      failures--;
      throw StateError('cleanup');
    }
  }
}

class Resolver implements MascotAssetResolver {
  Resolver(this.lease);
  final Lease lease;
  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async => lease;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real GIF honors encoded cycle durations and closes byte lease once',
      () async {
    final clip = MascotCatalog.defaultMascot.clips.first;
    final lease = Lease(await File(clip.sourcePath).readAsBytes());
    final session = await FlutterGifFrameSource(Resolver(lease)).open(clip, 48);
    expect(session.frameCount, clip.frameCount);
    final frame = await session.nextFrame();
    // This native engine ignores requested animated GIF decode sizing.
    expect(frame.image.width, clip.width);
    expect(frame.duration.inMilliseconds, anyOf(40, 50));
    var cycleDuration = frame.duration;
    frame.dispose();
    for (var i = 1; i < session.frameCount; i++) {
      final next = await session.nextFrame();
      cycleDuration += next.duration;
      next.dispose();
    }
    expect(cycleDuration, clip.encodedCycleDuration);
    await session.close();
    await session.close();
    expect(lease.closes, 1);
    await expectLater(session.nextFrame(), throwsStateError);
  });
  test('close waits for outstanding frame retrieval', () async {
    final clip = MascotCatalog.defaultMascot.clips.first;
    final lease = Lease(await File(clip.sourcePath).readAsBytes());
    final session = await FlutterGifFrameSource(Resolver(lease)).open(clip, 48);
    final pending = session.nextFrame();
    final closing = session.close();
    final frame = await pending;
    frame.dispose();
    await closing;
    expect(lease.closes, 1);
  });
  test('failed byte-lease cleanup is retryable without disposing codec twice',
      () async {
    final clip = MascotCatalog.defaultMascot.clips.first;
    final lease = Lease(await File(clip.sourcePath).readAsBytes())
      ..failures = 1;
    final session = await FlutterGifFrameSource(Resolver(lease)).open(clip, 48);
    final frame = await session.nextFrame();
    frame.dispose();
    await expectLater(session.close(), throwsStateError);
    await session.close();
    await session.close();
    expect(lease.closes, 2);
  });
}
