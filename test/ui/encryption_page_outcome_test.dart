// The encryption page's setup outcome (R47): what the page says once setup
// has run. The description covers only notes that were sealed, notes the
// notes step left waiting or could not convert stay shown after the toast,
// nothing promises when they will be sent, and an outcome is shown only for
// the account it belongs to while that account's vault is on. Fakes stand
// in for the vault, the notes step and the signed-in account. Every phrase
// is synthetic, built from the public word list.

import 'package:atomic_notes/page/endpage/encryption_page.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/wordlist.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<String> _phrase = [
  for (var i = 0; i < SeedPhrase.wordCount; i++) kWordList[i * 23 + 5],
];

class _Fakes {
  bool unlocked = false;
  bool enabled = false;
  String? account = 'account-a';
  int waiting = 0;
  Object? createError;
  Object? migrateError;
  final List<String> calls = [];

  Future<void> create(List<String> phrase) async {
    calls.add('createVault');
    final error = createError;
    if (error is VaultAlreadyExistsError) enabled = true;
    if (error != null) throw error;
    unlocked = true;
    enabled = true;
  }

  Future<int> migrate() async {
    calls.add('migrateToVault');
    final error = migrateError;
    if (error != null) throw error;
    return waiting;
  }

  Future<void> lock() async {
    calls.add('lockVault');
    unlocked = false;
  }
}

final Finder _generate = find.byKey(const ValueKey('encryption-generate'));
final Finder _wrote = find.byKey(const ValueKey('encryption-wrote'));
final Finder _turnOn = find.byKey(const ValueKey('encryption-turn-on'));
final Finder _error = find.byKey(const ValueKey('encryption-error'));
final Finder _pending = find.byKey(const ValueKey('encryption-pending'));
Finder _field(int i) => find.descendant(
    of: find.byKey(ValueKey('encryption-word-$i')),
    matching: find.byType(TextField));

/// Wording the page must never use: a claim about every note or a promise
/// about when waiting notes are sent.
const List<String> _overclaims = [
  'only ever holds',
  'Every note',
  'next sync',
  'will be encrypted',
];

Future<void> _pump(WidgetTester tester, _Fakes fakes) async {
  tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.light,
    home: EncryptionPage(
      isUnlocked: () => fakes.unlocked,
      isEnabled: () => fakes.enabled,
      generatePhrase: () => List.of(_phrase),
      createVault: fakes.create,
      migrateToVault: fakes.migrate,
      lockVault: fakes.lock,
      currentAccount: () => fakes.account,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Rebuilds the page, as any later frame would (here: a new window size),
/// so it shows what is true now.
Future<void> _rebuild(WidgetTester tester) async {
  final size = tester.view.physicalSize;
  tester.view.physicalSize = Size(size.width, size.height + 3);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _turnOnEncryption(WidgetTester tester) async {
  await _tap(tester, _generate);
  await _tap(tester, _wrote);
  for (var i = 0; i < _phrase.length; i++) {
    await tester.ensureVisible(_field(i));
    await tester.enterText(_field(i), _phrase[i]);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, _turnOn);
}

/// Lets the toast run its course.
Future<void> _afterToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsNothing);
}

void _expectNoOverclaim() {
  for (final phrase in _overclaims) {
    expect(find.textContaining(phrase), findsNothing, reason: phrase);
  }
}

void main() {
  group('copy', () {
    test('no message claims every note or promises the next sync', () {
      final copies = [
        EncryptionPage.onBody,
        EncryptionPage.onMessage,
        EncryptionPage.partialMessage,
        EncryptionPage.pendingBody,
        for (final n in [1, 2, 3]) ...[
          EncryptionPage.waitingMessage(n),
          EncryptionPage.pendingTitle(n),
        ],
      ];
      for (final copy in copies) {
        for (final phrase in _overclaims) {
          expect(copy.contains(phrase), isFalse, reason: '$phrase in $copy');
        }
      }
      expect(EncryptionPage.onBody, contains('An encrypted note'));
      expect(EncryptionPage.pendingTitle(1), 'Setup left 1 note waiting');
      expect(EncryptionPage.pendingTitle(2), 'Setup left 2 notes waiting');
      expect(EncryptionPage.waitingMessage(1),
          'Encryption is on. 1 note has not been sent encrypted yet.');
    });
  });

  group('pending', () {
    testWidgets('notes left waiting stay shown after the toast',
        (tester) async {
      final fakes = _Fakes()..waiting = 2;
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(fakes.calls, ['createVault', 'migrateToVault']);
      // The toast and the lasting status, together.
      expect(find.text(EncryptionPage.waitingMessage(2)), findsOneWidget);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      _expectNoOverclaim();
      expect(_pending, findsOneWidget, reason: 'pending with the toast');
      final banner = tester.widget<AtomicBanner>(_pending);
      expect(banner.tone, BannerTone.attention);
      expect(banner.title, EncryptionPage.pendingTitle(2));
      expect(banner.body, EncryptionPage.pendingBody);
      expect(find.text(EncryptionPage.onMessage), findsNothing);

      await _afterToast(tester);
      expect(find.text(EncryptionPage.waitingMessage(2)), findsNothing);
      expect(_pending, findsOneWidget, reason: 'pending after the toast');
      expect(tester.widget<AtomicBanner>(_pending).title,
          EncryptionPage.pendingTitle(2));
      _expectNoOverclaim();

      await _rebuild(tester);
      expect(_pending, findsOneWidget, reason: 'pending after a rebuild');
      expect(tester.widget<AtomicBanner>(_pending).title,
          EncryptionPage.pendingTitle(2));
      expect(_error, findsNothing);
    });

    testWidgets('one note left waiting is counted as one', (tester) async {
      final fakes = _Fakes()..waiting = 1;
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      await _afterToast(tester);
      expect(find.text(EncryptionPage.pendingTitle(1)), findsOneWidget);
    });
  });

  group('failed', () {
    testWidgets('a failed notes step stays shown and claims no waiting count',
        (tester) async {
      final fakes = _Fakes()..migrateError = StateError('offline');
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(fakes.calls, ['createVault', 'migrateToVault']);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      final banner = tester.widget<AtomicBanner>(_error);
      expect(banner.tone, BannerTone.danger);
      expect(banner.title, EncryptionPage.partialMessage);
      expect(find.text(EncryptionPage.failedMessage), findsNothing);
      expect(_pending, findsNothing, reason: 'no waiting count on a failure');
      _expectNoOverclaim();

      await _afterToast(tester);
      await _rebuild(tester);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.partialMessage);
      expect(find.text(EncryptionPage.onMessage), findsNothing);
    });

    testWidgets('a create failure is not shown as encryption on',
        (tester) async {
      final fakes = _Fakes()..createError = StateError('offline');
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(fakes.calls, ['createVault']);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.failedMessage);
      expect(find.text(EncryptionPage.partialMessage), findsNothing);
      expect(find.text(EncryptionPage.onTitle), findsNothing);
      expect(_pending, findsNothing);
    });
  });

  group('completed', () {
    testWidgets('every note sent: the toast, then no lasting status',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(find.text(EncryptionPage.onMessage), findsOneWidget);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(find.text(EncryptionPage.onBody), findsOneWidget);
      expect(_pending, findsNothing);
      expect(_error, findsNothing);
      _expectNoOverclaim();
      await _afterToast(tester);
      await _rebuild(tester);
      expect(_pending, findsNothing);
      expect(_error, findsNothing);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
    });
  });

  group('locked', () {
    testWidgets('locked here, the notes left waiting are still shown',
        (tester) async {
      final fakes = _Fakes()..waiting = 2;
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      await _afterToast(tester);
      // The key is forgotten on this device; the account's vault stays on.
      fakes.unlocked = false;
      await _rebuild(tester);
      expect(find.text(EncryptionPage.lockedTitle), findsOneWidget);
      expect(find.text(EncryptionPage.onTitle), findsNothing);
      expect(find.text(EncryptionPage.onBody), findsNothing);
      expect(_pending, findsOneWidget, reason: 'pending while locked here');
      expect(tester.widget<AtomicBanner>(_pending).title,
          EncryptionPage.pendingTitle(2));
      _expectNoOverclaim();
    });

    testWidgets('locked here after a failed notes step, the failure stays',
        (tester) async {
      final fakes = _Fakes()..migrateError = StateError('offline');
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      fakes.unlocked = false;
      await _rebuild(tester);
      expect(find.text(EncryptionPage.lockedTitle), findsOneWidget);
      expect(_error, findsOneWidget, reason: 'failure while locked here');
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.partialMessage);
    });

    testWidgets('an account that already has a vault shows Locked only',
        (tester) async {
      final fakes = _Fakes()..createError = const VaultAlreadyExistsError();
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(fakes.calls, ['createVault']);
      expect(find.text(EncryptionPage.lockedTitle), findsOneWidget);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.existsMessage);
      expect(_pending, findsNothing);
      expect(find.text(EncryptionPage.onTitle), findsNothing);
      expect(find.text(EncryptionPage.partialMessage), findsNothing);
      _expectNoOverclaim();
    });
  });

  group('current account', () {
    testWidgets('notes left waiting are shown only for their own account',
        (tester) async {
      final fakes = _Fakes()..waiting = 2;
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      await _afterToast(tester);
      expect(_pending, findsOneWidget);

      // Another account, with its own vault open here.
      fakes.account = 'account-b';
      await _rebuild(tester);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(_pending, findsNothing, reason: 'pending of another account');

      fakes.account = 'account-a';
      await _rebuild(tester);
      expect(_pending, findsOneWidget, reason: 'pending of this account');
    });

    testWidgets('a failed notes step is shown only for its own account',
        (tester) async {
      final fakes = _Fakes()..migrateError = StateError('offline');
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      expect(_error, findsOneWidget);
      fakes.account = 'account-b';
      await _rebuild(tester);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(find.text(EncryptionPage.partialMessage), findsNothing,
          reason: 'failure of another account');
    });

    testWidgets('no outcome once the account has no vault on', (tester) async {
      final fakes = _Fakes()..waiting = 2;
      await _pump(tester, fakes);
      await _turnOnEncryption(tester);
      await _afterToast(tester);
      fakes
        ..unlocked = false
        ..enabled = false;
      await _rebuild(tester);
      expect(find.text(EncryptionPage.offTitle), findsOneWidget);
      expect(_pending, findsNothing);
      expect(find.text(EncryptionPage.pendingTitle(2)), findsNothing);
    });
  });
}
