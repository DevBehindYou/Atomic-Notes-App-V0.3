// The Recycle Bin page reads the repository's in-memory notes only, so it can be
// shown without Hive or the network. A fresh repository holds no notes.

import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an empty bin says so and offers nothing destructive',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: RecycleBinPage()));

    expect(find.text('Recycle Bin is empty'), findsOneWidget);
    // No "…" menu (Empty bin) and no card buttons.
    expect(find.byTooltip('More options'), findsNothing);
    expect(find.text('Delete forever'), findsNothing);
  });
}
