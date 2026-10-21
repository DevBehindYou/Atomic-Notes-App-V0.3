import 'dart:convert';
import 'package:http/http.dart' as http;
import 'guard.dart';

/// Takes ownership of the one-shot client, including timeout/error cleanup.
Future<Object?> fetchAcceptanceDescriptor(http.Client client, Uri base,
    {Duration deadline = const Duration(seconds: 8)}) async {
  try {
    return await (() async {
      final request =
          http.Request('GET', base.replace(path: '/__fixture/ready'))
            ..followRedirects = false;
      final response = await client.send(request).timeout(deadline);
      if (response.statusCode != 200) throw StateError('fixture_unavailable');
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(deadline)) {
        if (bytes.length + chunk.length > 4096) {
          throw StateError('fixture_invalid');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      acceptanceOwner(data);
      return data;
    })()
        .timeout(deadline);
  } finally {
    client.close();
  }
}
