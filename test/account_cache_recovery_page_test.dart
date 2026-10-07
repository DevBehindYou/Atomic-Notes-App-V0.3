import 'dart:async';
import 'package:atomic_notes/page/account_cache_recovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
      WidgetTester tester, Future<void> Function() signOut) async {
    await tester.pumpWidget(MaterialApp(
      home: AccountCacheRecoveryPage(signOut: signOut),
      routes: {
        '/loginpage': (_) => const Scaffold(body: Text('Synthetic login'))
      },
    ));
  }

  testWidgets(
      'recovery explains preservation without notes or account identifiers',
      (tester) async {
    await show(tester, () async {});
    expect(
        find.textContaining('notes are preserved and hidden'), findsOneWidget);
    expect(find.textContaining('Do not uninstall'), findsOneWidget);
    final state = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await state.maybePop(), isTrue); // PopScope consumes Back.
    await tester.pumpAndSettle();
    expect(find.byType(AccountCacheRecoveryPage), findsOneWidget);
  });

  testWidgets(
      'sign-in action waits, blocks repeated taps, then clears the route stack',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await show(tester, () {
      calls++;
      return gate.future;
    });
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Returning to sign-in…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic login'), findsOneWidget);
    expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
  });

  testWidgets('failed sign-out can retry without displaying raw errors',
      (tester) async {
    var calls = 0;
    await show(tester, () async {
      if (++calls == 1) throw StateError('Synthetic private error');
    });
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('stored notes are unchanged'), findsOneWidget);
    expect(find.textContaining('Synthetic private error'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Synthetic login'), findsOneWidget);
  });

  testWidgets('narrow screen and enlarged text remain scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: AccountCacheRecoveryPage(signOut: () async {}),
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(FilledButton));
    expect(tester.takeException(), isNull);
  });
}
