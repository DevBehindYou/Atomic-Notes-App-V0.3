import 'dart:io';
import 'package:http/io_client.dart';

// The base implementation constructs dart:io's real client. Calling it directly
// avoids Flutter's test-only global HTTP substitute without changing that global.
class _FixtureHttp extends HttpOverrides {}

IOClient serverFixtureTransport() => IOClient(
    _FixtureHttp().createHttpClient(null)..findProxy = (_) => 'DIRECT');
