import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_download_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Transport extends http.BaseClient {
  _Transport(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }

  @override
  void close() => closed = true;
}

void main() {
  final clip = MascotCatalog.defaultMascot.clips.first;
  late Uint8List original;
  setUpAll(() async {
    original = await File(clip.bundledAssetPath!).readAsBytes();
  });
  MascotDownloadClient client(_Transport transport) => MascotDownloadClient(
        releaseBase: Uri.parse(
            'https://github.com/DevBehindYou/Atomic-Notes-App-V0.3/releases/download/mascots-v1.0.0/'),
        clientFactory: () => transport,
        idleTimeout: const Duration(milliseconds: 100),
      );
  Future<void> discard(List<int> _) async {}

  test(
      'accepts bounded chunked bytes without content length, with no credentials',
      () async {
    final transport = _Transport((_) async => http.StreamedResponse(
        Stream.fromIterable([original.sublist(0, 10), original.sublist(10)]),
        200));
    final chunks = <int>[];
    await client(transport).download(clip,
        write: (part) async => chunks.addAll(part),
        cancellation: MascotCancellation());
    expect(chunks, original);
    expect(transport.closed, isTrue);
    expect(transport.requests.single.followRedirects, isFalse);
    expect(transport.requests.single.headers.keys.map((v) => v.toLowerCase()),
        isNot(contains('authorization')));
    expect(transport.requests.single.headers.keys.map((v) => v.toLowerCase()),
        isNot(contains('cookie')));
  });
  test('rejects a redirect outside the public release host allowlist',
      () async {
    final transport = _Transport((_) async => http.StreamedResponse(
        const Stream.empty(), 302,
        headers: {'location': 'https://example.com/evil.gif'}));
    await expectLater(
        client(transport)
            .download(clip, write: discard, cancellation: MascotCancellation()),
        throwsA(isA<MascotDownloadException>()
            .having((e) => e.code, 'code', 'redirect_not_allowed')));
    expect(transport.requests, hasLength(1));
  });
  test('verified exact length still rejects a changed byte before install',
      () async {
    final changed = Uint8List.fromList(original)..[30] ^= 1;
    final transport = _Transport(
        (_) async => http.StreamedResponse(Stream.value(changed), 200));
    await expectLater(
        client(transport)
            .download(clip, write: discard, cancellation: MascotCancellation()),
        throwsA(isA<MascotDownloadException>()
            .having((e) => e.code, 'code', 'integrity_mismatch')));
  });
  test('oversized body is rejected before an excessive chunk reaches disk',
      () async {
    final transport = _Transport((_) async =>
        http.StreamedResponse(Stream.value(Uint8List(clip.bytes + 1)), 200));
    var written = 0;
    await expectLater(
        client(transport).download(clip, write: (part) async {
          written += part.length;
        }, cancellation: MascotCancellation()),
        throwsA(isA<MascotDownloadException>()
            .having((e) => e.code, 'code', 'size_mismatch')));
    expect(written, 0);
  });
  test('cancel closes a stalled request instead of waiting for its timeout',
      () async {
    final response = Completer<http.StreamedResponse>();
    final transport = _Transport((_) => response.future);
    final cancellation = MascotCancellation();
    final work = client(transport)
        .download(clip, write: discard, cancellation: cancellation);
    cancellation.cancel();
    await expectLater(
        work,
        throwsA(isA<MascotDownloadException>()
            .having((e) => e.code, 'code', 'cancelled')));
    expect(transport.closed, isTrue);
  });
  test('rate limit is retryable and bounded server delay is retained',
      () async {
    final transport = _Transport((_) async => http.StreamedResponse(
        const Stream.empty(), 429,
        headers: {'retry-after': '900'}));
    await expectLater(
        client(transport)
            .download(clip, write: discard, cancellation: MascotCancellation()),
        throwsA(isA<MascotDownloadException>()
            .having((e) => e.retryable, 'retryable', isTrue)
            .having((e) => e.retryAfter, 'retryAfter',
                const Duration(seconds: 30))));
  });
}
