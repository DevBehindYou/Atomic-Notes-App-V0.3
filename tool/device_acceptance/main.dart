// Alternate acceptance target only. The production entrypoint never imports it.
import 'dart:convert';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:atomic_notes/main.dart' as production;
import 'package:atomic_notes/security/secure_options.dart';
import 'guard.dart';
import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final base = acceptanceBase(const String.fromEnvironment('API_BASE_URL'),
        enabled: const bool.fromEnvironment('ATOMIC_DEVICE_ACCEPTANCE'),
        release: kReleaseMode);
    const storage = FlutterSecureStorage(aOptions: kSecureAndroidOptions);
    const bindingKey = 'atomic_acceptance_fixture_binding_v1';
    final saved = await storage.read(key: bindingKey);
    if (saved == null) {
      final descriptor = await fetchAcceptanceDescriptor(http.Client(), base);
      final owner = acceptanceOwner(descriptor);
      // These credentials are public constants accepted only by the disposable
      // Server fixture. No Google account or production session is used.
      await storage.write(
          key: 'atomic_api_session_token', value: 'atomic-disposable-client-a');
      await storage.write(key: 'atomic_api_user_id', value: owner);
      await storage.write(
          key: 'atomic_api_user_email',
          value: 'device-acceptance@example.test');
      await storage.write(key: bindingKey, value: jsonEncode(descriptor));
    } else {
      // Do not reseed on restart: offline use and actual logout remain testable.
      acceptanceOwner(jsonDecode(saved));
    }
    _registerFrameMetrics();
    await production.main();
  } catch (_) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Center(
                    child: Text(
                        'Device acceptance server unavailable. Check the USB test connection.'))))));
  }
}

void _registerFrameMetrics() {
  final frames = Queue<List<int>>();
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      if (frames.length == 1200) frames.removeFirst();
      frames.add([
        timing.buildDuration.inMicroseconds,
        timing.rasterDuration.inMicroseconds,
        timing.totalSpan.inMicroseconds
      ]);
    }
  });
  developer.registerExtension('ext.atomicAcceptance.frames',
      (_, parameters) async {
    if (parameters['reset'] == 'true') frames.clear();
    int percentile(int column, double fraction) {
      if (frames.isEmpty) return 0;
      final sorted = frames.map((frame) => frame[column]).toList()..sort();
      return sorted[math.max(0, (sorted.length * fraction).ceil() - 1)];
    }

    return developer.ServiceExtensionResponse.result(jsonEncode({
      'mode': kProfileMode ? 'profile' : 'debug',
      'frames': frames.length,
      'build_p95_us': percentile(0, .95),
      'raster_p95_us': percentile(1, .95),
      'total_p50_us': percentile(2, .5),
      'total_p95_us': percentile(2, .95),
      'total_p99_us': percentile(2, .99),
      'over_16667us_reference':
          frames.where((frame) => frame[2] > 16667).length,
      'note': '60Hz reference only; verify actual device refresh rate',
    }));
  });
}
