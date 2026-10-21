import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_frame_source.dart';
import 'package:atomic_notes/mascot/mascot_playback_controller.dart';

class BrokenSource implements MascotFrameSource {
  int opens = 0;
  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async {
    opens++;
    throw StateError('bad');
  }
}

void main() {
  test('decode failures try four slots and stop until explicit retry',
      () async {
    final source = BrokenSource();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: source,
        targetPhysicalPixels: 48);
    c.setPlaybackAllowed(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.opens, 4);
    expect(c.state, MascotPlaybackState.failed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.opens, 4);
    c.retry();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.opens, 8);
    await c.close();
  });
  test('hidden player never opens a decoder', () async {
    final source = BrokenSource();
    final c = MascotPlaybackController(
        mascot: MascotCatalog.defaultMascot,
        source: source,
        targetPhysicalPixels: 48);
    c.setPlaybackAllowed(false, visible: false);
    await Future<void>.delayed(Duration.zero);
    expect(source.opens, 0);
    await c.close();
  });
}
