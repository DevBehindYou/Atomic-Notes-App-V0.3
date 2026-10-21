import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'mascot_catalog.dart';

class MascotDownloadException implements Exception {
  const MascotDownloadException(this.code,
      {this.retryable = false, this.retryAfter = Duration.zero});
  final String code;
  final bool retryable;
  final Duration retryAfter;
  @override
  String toString() => 'MascotDownloadException($code)';
}

class MascotCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const MascotDownloadException('cancelled');
  }

  Future<T> race<T>(Future<T> work) {
    check();
    return Future.any([
      work,
      whenCancelled.then<T>((_) {
        throw const MascotDownloadException('cancelled');
      })
    ]);
  }
}

/// A dedicated credential-free transport. Callers own staging and promotion.
/// Each call is one attempt: retries must reset the destination file first.
class MascotDownloadClient {
  MascotDownloadClient({
    required this.releaseBase,
    http.Client Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new {
    if (releaseBase.scheme != 'https' ||
        releaseBase.host != 'github.com' ||
        releaseBase.userInfo.isNotEmpty ||
        releaseBase.hasQuery ||
        releaseBase.hasFragment ||
        (releaseBase.hasPort && releaseBase.port != 443) ||
        !RegExp(r'^/DevBehindYou/Atomic-Notes-App-V0\.3/releases/download/mascots-v[0-9]+\.[0-9]+\.[0-9]+/$')
            .hasMatch(releaseBase.path)) {
      throw ArgumentError('A versioned public mascot release is required');
    }
  }

  final Uri releaseBase;
  final http.Client Function() _clientFactory;
  final Duration connectTimeout, idleTimeout;
  static const _deliveryHosts = {
    'github.com',
    'release-assets.githubusercontent.com'
  };

  Future<void> download(
    MascotClip clip, {
    required Future<void> Function(List<int>) write,
    required MascotCancellation cancellation,
    void Function(int received, int total)? onProgress,
  }) async {
    // Only app-pinned instances may influence URLs, limits and expected hashes.
    if (!MascotCatalog.all.any((m) => m.clips.contains(clip)) ||
        clip.bytes > 2 * 1024 * 1024 ||
        clip.bytes <= 0) {
      throw const MascotDownloadException('unknown_clip');
    }
    cancellation.check();
    final client = _clientFactory();
    var finished = false;
    unawaited(cancellation.whenCancelled.then((_) {
      if (!finished) client.close();
    }));
    StreamIterator<List<int>>? iterator;
    try {
      var uri = releaseBase.resolve(clip.originalFilename);
      http.StreamedResponse? response;
      for (var redirects = 0; redirects <= 4; redirects++) {
        cancellation.check();
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers['Accept'] = 'image/gif';
        final currentResponse = await cancellation
            .race(client.send(request).timeout(connectTimeout));
        response = currentResponse;
        if (![301, 302, 303, 307, 308].contains(currentResponse.statusCode)) {
          break;
        }
        final location = currentResponse.headers['location'];
        final next = location == null ? null : uri.resolve(location);
        if (next == null ||
            next.scheme != 'https' ||
            !_deliveryHosts.contains(next.host) ||
            next.userInfo.isNotEmpty ||
            next.hasFragment ||
            (next.hasPort && next.port != 443)) {
          throw const MascotDownloadException('redirect_not_allowed');
        }
        // Do not buffer an arbitrary redirect response body.
        final subscription = currentResponse.stream.listen((_) {});
        await subscription.cancel();
        if (redirects == 4) {
          throw const MascotDownloadException('too_many_redirects');
        }
        uri = next;
      }
      final result = response!;
      if (result.statusCode != 200) {
        final retrySeconds =
            int.tryParse(result.headers['retry-after'] ?? '') ?? 0;
        throw MascotDownloadException('http_${result.statusCode}',
            retryable: result.statusCode == 429 || result.statusCode >= 500,
            retryAfter: Duration(seconds: retrySeconds.clamp(0, 30)));
      }
      final length = result.contentLength;
      if (length != null && length != clip.bytes) {
        throw const MascotDownloadException('size_mismatch');
      }
      final hash = Sha256().toSync().newHashSink();
      var received = 0;
      iterator = StreamIterator(result.stream);
      while (
          await cancellation.race(iterator.moveNext().timeout(idleTimeout))) {
        cancellation.check();
        final chunk = iterator.current;
        if (received + chunk.length > clip.bytes) {
          throw const MascotDownloadException('size_mismatch');
        }
        hash.add(chunk);
        // Await disk writes to bound memory instead of growing an IOSink queue.
        await write(chunk);
        cancellation.check();
        received += chunk.length;
        onProgress?.call(received, clip.bytes);
      }
      hash.close();
      if (received != clip.bytes) {
        throw const MascotDownloadException('size_mismatch');
      }
      final actual = (await hash.hash())
          .bytes
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual != clip.sha256) {
        throw const MascotDownloadException('integrity_mismatch');
      }
      cancellation.check();
    } on TimeoutException {
      throw const MascotDownloadException('timeout', retryable: true);
    } on http.ClientException {
      cancellation.check();
      throw const MascotDownloadException('connection_failed', retryable: true);
    } finally {
      finished = true;
      await iterator?.cancel();
      client.close();
    }
  }
}
