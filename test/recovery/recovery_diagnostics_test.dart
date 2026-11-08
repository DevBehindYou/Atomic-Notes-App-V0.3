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
    ];
    final report = RecoveryDiagnostics.redactedReport(
        const RecoveryFacts(
            pendingWrites: 2,
            archiveError: 'truncated',
            integrity: {IntegrityProblem.idMismatch: 1}),
        app: {
          'version': '2.03.9+2051',
          'build': 'staging',
          'lastError': canaries[0],
          'account': canaries[1],
          'token': canaries[2],
          'session': canaries[3],
          'vaultKey': canaries[4],
          'Free text key': 'x',
        });
    for (final canary in canaries) {
      expect(report, isNot(contains(canary)), reason: canary);
    }
    final json = jsonDecode(report) as Map<String, Object?>;
    expect(json['issues'],
        ['pending_writes', 'archive_damaged', 'damaged_records']);
    expect(json['integrity'], {'idMismatch': 1});
    final app = json['app'] as Map<String, Object?>;
    expect([app['version'], app['build'], app['lastError'], app['token']],
        ['2.03.9+2051', 'staging', 'redacted', 'redacted']);
    expect(app.containsKey('Free text key'), isFalse);
    expect(app['redacted'], 'x', reason: 'unsafe keys are renamed');
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
