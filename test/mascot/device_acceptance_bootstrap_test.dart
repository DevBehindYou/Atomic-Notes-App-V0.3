import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../tool/device_acceptance/bootstrap.dart';

class Client extends http.BaseClient {
  Client(this.response);
  final http.StreamedResponse response;
  http.BaseRequest? request;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return response;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  final base = Uri.parse('http://127.0.0.1:24139/api');
  test('redirect responses are refused without following them', () async {
    final client = Client(http.StreamedResponse(const Stream.empty(), 302,
        headers: {'location': 'https://example.test/fixture'}));
    await expectLater(
        fetchAcceptanceDescriptor(client, base), throwsStateError);
    expect(client.request!.followRedirects, isFalse);
    expect(client.closed, isTrue);
  });
  test('trickled response has a total deadline and closes its client',
      () async {
    final stream = StreamController<List<int>>();
    final client = Client(http.StreamedResponse(stream.stream, 200));
    final timer = Timer.periodic(
        const Duration(milliseconds: 10), (_) => stream.add([32]));
    try {
      await expectLater(
          fetchAcceptanceDescriptor(client, base,
                  deadline: const Duration(milliseconds: 60))
              .timeout(const Duration(milliseconds: 250)),
          throwsA(isA<TimeoutException>()));
      expect(client.closed, isTrue);
    } finally {
      timer.cancel();
      await stream.close();
    }
  });
  test('valid bounded descriptor is returned and client closed', () async {
    final data = {
      'owner': '12345678-1234-4234-8234-123456789abc',
      'database': 'atomic_test_1234567890abcdef1234'
    };
    final client = Client(http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(data))), 200));
    expect(await fetchAcceptanceDescriptor(client, base), data);
    expect(client.closed, isTrue);
  });
}
