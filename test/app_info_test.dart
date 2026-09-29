// The version the App shows and sends with the notification feed must be the one it is built as.

import 'dart:io';

import 'package:atomic_notes/utility/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppInfoText matches the version in pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = line.substring('version:'.length).trim();
    expect('${AppInfoText.version}+${AppInfoText.buildNumber}', version);
  });
}
