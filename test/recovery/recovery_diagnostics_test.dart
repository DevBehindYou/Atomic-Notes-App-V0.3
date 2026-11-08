import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/recovery/record_integrity.dart';
import 'package:atomic_notes/recovery/recovery_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _codes(RecoveryFacts f) =>
    [for (final i in RecoveryDiagnostics.diagnose(f)) i.code];

void main() {
  test('a healthy device has nothing to report', () {
    expect(RecoveryDiagnostics.diagnose(const RecoveryFacts()), isEmpty);
  });

  test('each state gets its own message and a safe next step', () {
    final cases = <RecoveryFacts, (String, RecoveryAction)>{
      const RecoveryFacts(vaultLocked: true): (
        'vault_locked',
        RecoveryAction.unlockVault
      ),
      const RecoveryFacts(cacheOwnerMatches: false): (
        'wrong_owner',
        RecoveryAction.signInAgain
      ),
      const RecoveryFacts(pendingWrites: 2): (
        'pending_writes',
        RecoveryAction.retrySync
      ),
      const RecoveryFacts(providerAvailable: false): (
        'provider_unavailable',
        RecoveryAction.tryLater
      ),
      const RecoveryFacts(online: false): ('offline', RecoveryAction.tryLater),
      const RecoveryFacts(archiveError: 'truncated'): (
        'archive_damaged',
        RecoveryAction.chooseAnotherBackup
      ),
      const RecoveryFacts(archiveError: 'authentication_failed'): (
        'archive_password',
        RecoveryAction.chooseAnotherBackup
      ),
      const RecoveryFacts(archiveError: 'unsupported_kdf'): (
        'archive_unsupported',
        RecoveryAction.chooseAnotherBackup
      ),
      const RecoveryFacts(integrity: {IntegrityProblem.malformedFields: 3}): (
        'damaged_records',
        RecoveryAction.none
      ),
    };
    for (final MapEntry(key: facts, value: (code, action)) in cases.entries) {
      final issue = RecoveryDiagnostics.diagnose(facts).single;
      expect([issue.code, issue.action], [code, action]);
      expect(issue.message, isNotEmpty);
    }
  });

  test('messages match the actual state, not a generic error', () {
    expect(
        RecoveryDiagnostics.diagnose(const RecoveryFacts(pendingWrites: 1))
            .single
            .message,
        contains('1 change is saved on this device but not yet synced'));
    // Offline: pending changes wait instead of offering a sync that cannot run.
    final offline = RecoveryDiagnostics.diagnose(
        const RecoveryFacts(pendingWrites: 4, online: false));
    expect([for (final i in offline) i.code], ['pending_writes', 'offline']);
    expect(offline.first.action, RecoveryAction.tryLater);
    expect(offline.first.message, contains('when you are back online'));
    // Order: ownership, then lock, then pending work, then provider.
    expect(
        _codes(const RecoveryFacts(
            cacheOwnerMatches: false,
            vaultLocked: true,
            pendingWrites: 1,
            providerAvailable: false)),
        [
          'wrong_owner',
          'vault_locked',
          'pending_writes',
          'provider_unavailable'
        ]);
  });

  test('the report holds codes and counts, never content, tokens or keys', () {
    const canaries = [
      'Secret note title about my health',
      'person@example.com',
      'ya29.a0AfH6SMBxxxxxxxxxxxxxxxxxxxxxxxx',
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig',
      'k3yMaterialBase64AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      // Short, code-shaped values that pattern redaction would let through.
      'diabetes',
      'short-secret',
      'abc',
    ];
    for (final canary in canaries) {
      for (final app in [
        DiagnosticApp(version: canary),
        DiagnosticApp(version: '2.0.1+$canary'),
      ]) {
        final report = RecoveryDiagnostics.redactedReport(
            RecoveryFacts(
                archiveError: canary,
                integrity: const {IntegrityProblem.idMismatch: 1}),
            app: app);
        expect(report, isNot(contains(canary)), reason: canary);
        final json = jsonDecode(report) as Map<String, Object?>;
        expect(json['archiveError'], 'other', reason: canary);
        expect((json['app'] as Map)['version'], 'invalid', reason: canary);
      }
      for (final issue in RecoveryDiagnostics.diagnose(
          RecoveryFacts(archiveError: canary))) {
        expect(issue.message, isNot(contains(canary)), reason: canary);
      }
    }
  });

  test('the report keeps known codes, counts and typed app facts', () {
    final report = RecoveryDiagnostics.redactedReport(
        const RecoveryFacts(
            pendingWrites: 2,
            archiveError: 'truncated',
            integrity: {IntegrityProblem.idMismatch: 1},
            quarantinedCopies: 1),
        app: const DiagnosticApp(
            version: '2.03.9+2051',
            flavor: DiagnosticFlavor.staging,
            platform: DiagnosticPlatform.android));
    final json = jsonDecode(report) as Map<String, Object?>;
    expect(json['issues'],
        ['pending_writes', 'archive_damaged', 'damaged_records']);
    expect(json['archiveError'], 'truncated');
    expect(json['integrity'], {'idMismatch': 1});
    expect(json['quarantinedCopies'], 1);
    expect(json['app'],
        {'version': '2.03.9+2051', 'flavor': 'staging', 'platform': 'android'});
    expect(
        jsonDecode(
            RecoveryDiagnostics.redactedReport(const RecoveryFacts()))['app'],
        {'version': null, 'flavor': null, 'platform': null});
    // Every archive code the format can raise is known by name.
    for (final code in RecoveryDiagnostics.archiveErrorCodes) {
      expect(
          jsonDecode(RecoveryDiagnostics.redactedReport(
              RecoveryFacts(archiveError: code)))['archiveError'],
          code);
    }
  });

  test('damaged records claim neither a note count nor unconfirmed copies', () {
    String message(RecoveryFacts f) =>
        RecoveryDiagnostics.diagnose(f).single.message;
    const findings = {
      IntegrityProblem.malformedFields: 3,
      IntegrityProblem.idMismatch: 2
    };
    final plain = message(const RecoveryFacts(integrity: findings));
    expect(plain, 'Some stored records could not be read.');
    expect(plain, isNot(matches(RegExp(r'\d'))));
    expect(
        message(const RecoveryFacts(integrity: findings, quarantinedCopies: 2)),
        'Some stored records could not be read. 2 copies are kept aside.');
  });

  group('status panel', () {
    Future<void> show(WidgetTester tester, RecoveryFacts facts,
        Future<void> Function(RecoveryAction) onAction) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      RecoveryStatusPanel(facts: facts, onAction: onAction)))));
    }

    testWidgets('retry runs once while in flight', (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await show(tester, const RecoveryFacts(pendingWrites: 3), (action) {
        calls++;
        expect(action, RecoveryAction.retrySync);
        return gate.future;
      });
      final retry =
          find.byKey(const ValueKey('recovery-action-pending_writes'));
      await tester.tap(retry);
      await tester.pump();
      expect(find.text('Working…'), findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      expect(calls, 1, reason: 'no double submit');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sync now'), findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('a failed step can be tried again', (tester) async {
      var calls = 0;
      await show(tester, const RecoveryFacts(vaultLocked: true), (_) async {
        calls++;
        throw StateError('unlock failed');
      });
      await tester
          .tap(find.byKey(const ValueKey('recovery-action-vault_locked')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('recovery-failed-vault_locked')),
          findsOneWidget);
      // A step can fail part way, so the panel never claims nothing changed.
      expect(find.textContaining('Nothing was changed'), findsNothing);
      expect(
          find.text(
              'That did not finish. Your notes on this device are kept; you can try again.'),
          findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('recovery-action-vault_locked')));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });

    testWidgets(
        'accessible: labelled 48dp actions and announced issues, also offline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await show(
          tester,
          const RecoveryFacts(
              vaultLocked: true,
              pendingWrites: 1,
              online: false,
              archiveError: 'malformed'),
          (_) async {});
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.text('Unlock encrypted notes'), findsOneWidget);
      expect(find.text('Choose another backup'), findsOneWidget);
      expect(find.text('Sync now'), findsNothing,
          reason: 'offline: no sync offered');
      expect(
          find.byKey(const ValueKey('recovery-issue-offline')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('large text does not overflow', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: RecoveryStatusPanel(
                          facts: const RecoveryFacts(
                              cacheOwnerMatches: false,
                              vaultLocked: true,
                              pendingWrites: 9),
                          onAction: (_) async {}))))));
      expect(tester.takeException(), isNull);
    });
  });
}
