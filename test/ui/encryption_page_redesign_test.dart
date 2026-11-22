// The encryption page on lib/ui components (screens spec, Encryption and
// vault), over a fake vault state, a fake vault creation, a fake note
// migration and a fake device lock. The setup and lock logic is the one on
// main: the same checks before the vault is asked, the same calls in the
// same order, the same routes. Every phrase is synthetic, built from the
// public word list.

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:atomic_notes/page/endpage/encryption_page.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/wordlist.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final List<String> _phrase = [
  for (var i = 0; i < SeedPhrase.wordCount; i++) kWordList[i * 17 + 9],
];

/// The vault state and the calls the page makes, in order.
class _Fakes {
  bool unlocked = false;
  bool enabled = false;
  final List<String> calls = [];
  final List<List<String>> created = [];

  /// When set, the next vault creation waits for it.
  Completer<void>? createGate;
  Object? createError;
  Completer<int>? migrateGate;
  Object? migrateError;
  int waiting = 0;
  Completer<void>? lockGate;
  Object? lockError;

  /// Whether a failed lock still leaves the vault open.
  bool lockFailureKeepsKey = true;

  List<String> generate() {
    calls.add('generate');
    return List.of(_phrase);
  }

  Future<void> create(List<String> phrase) async {
    calls.add('createVault');
    created.add(List.of(phrase));
    await createGate?.future;
    final error = createError;
    if (error is VaultAlreadyExistsError) enabled = true;
    if (error != null) throw error;
    unlocked = true;
    enabled = true;
  }

  Future<int> migrate() async {
    calls.add('migrateToVault');
    final gate = migrateGate;
    final n = gate != null ? await gate.future : waiting;
    final error = migrateError;
    if (error != null) throw error;
    return n;
  }

  Future<void> lock() async {
    calls.add('lockVault');
    await lockGate?.future;
    final error = lockError;
    if (error != null) {
      if (!lockFailureKeepsKey) unlocked = false;
      throw error;
    }
    unlocked = false;
  }
}

final List<RouteSettings> _pushed = [];

final Finder _generate = find.byKey(const ValueKey('encryption-generate'));
final Finder _copy = find.byKey(const ValueKey('encryption-copy'));
final Finder _wrote = find.byKey(const ValueKey('encryption-wrote'));
final Finder _turnOn = find.byKey(const ValueKey('encryption-turn-on'));
final Finder _back = find.byKey(const ValueKey('encryption-back'));
final Finder _lock = find.byKey(const ValueKey('encryption-lock'));
final Finder _unlock = find.byKey(const ValueKey('encryption-unlock'));
final Finder _error = find.byKey(const ValueKey('encryption-error'));
final Finder _busy = find.byKey(const ValueKey('encryption-busy'));
Finder _word(int i) => find.byKey(ValueKey('encryption-word-$i'));
Finder _field(int i) =>
    find.descendant(of: _word(i), matching: find.byType(TextField));
Finder _pill(int i) => find.byKey(ValueKey('encryption-phrase-$i'));

Future<void> _pump(
  WidgetTester tester,
  _Fakes fakes, {
  ThemeData? theme,
  double width = 412,
  double height = 2600,
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    initialRoute: '/encryptionpage',
    onGenerateRoute: (settings) {
      if (settings.name == '/') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('settings page')));
      }
      if (settings.name == '/encryptionpage') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => EncryptionPage(
                  isUnlocked: () => fakes.unlocked,
                  isEnabled: () => fakes.enabled,
                  generatePhrase: fakes.generate,
                  createVault: fakes.create,
                  migrateToVault: fakes.migrate,
                  lockVault: fakes.lock,
                ));
      }
      _pushed.add(settings);
      return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
                body: Column(children: [
                  Text('route ${settings.name}'),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('leave route')),
                ]),
              ));
    },
  ));
  await tester.pumpAndSettle();
}

/// The page's own list, not a text field's inner scrollable.
Finder get _list => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// Scrolls the lazily built page until [finder] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(_list).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 120, scrollable: _list);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder,
    {bool settle = true}) async {
  await _reveal(tester, finder);
  await tester.tap(finder, warnIfMissed: false);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _toVerify(WidgetTester tester) async {
  await _tap(tester, _generate);
  await _tap(tester, _wrote);
}

Future<void> _type(WidgetTester tester, List<String> words) async {
  for (var i = 0; i < words.length; i++) {
    await _reveal(tester, _field(i));
    await tester.enterText(_field(i), words[i]);
  }
  // Done typing: the keyboard closes, so the focused field stops pulling
  // the list back to itself.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

bool _hasTap(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData().hasAction(SemanticsAction.tap);

/// Lets a snackbar run its course so no timer is left.
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

String? _clip;

void _mockClipboard(WidgetTester tester) {
  _clip = null;
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      _clip = (call.arguments as Map)['text'] as String?;
    } else if (call.method == 'Clipboard.getData') {
      return {'text': _clip};
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  setUp(_pushed.clear);

  group('off', () {
    testWidgets('a hero card, the warning banner and Generate', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      expect(find.text(EncryptionPage.offTitle), findsOneWidget);
      expect(find.text(EncryptionPage.offBody), findsOneWidget);
      final chip = tester.widget<StatusChip>(find.ancestor(
          of: find.text(EncryptionPage.chipOff),
          matching: find.byType(StatusChip)));
      expect(chip.tone, StatusTone.neutral);
      final warning = tester.widget<AtomicBanner>(
          find.byKey(const ValueKey('encryption-warning')));
      expect(warning.tone, BannerTone.attention);
      expect(warning.title, EncryptionPage.warningTitle);
      expect(warning.body, EncryptionPage.warningBody);
      final generate = tester.widget<AtomicButton>(_generate);
      expect(generate.variant, AtomicButtonVariant.primary);
      expect(generate.label, EncryptionPage.generateLabel);
      expect(fakes.calls, isEmpty);
      // The editorial labels are gone.
      expect(find.text('ENCRYPTION'), findsNothing);
      expect(find.text('OFF'), findsNothing);
    });
  });

  group('setup', () {
    testWidgets('Generate shows step 1 with the phrase in order',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _tap(tester, _generate);
      expect(fakes.calls, ['generate']);
      expect(find.text(EncryptionPage.step1), findsOneWidget);
      expect(find.text(EncryptionPage.showTitle), findsOneWidget);
      expect(find.text(EncryptionPage.showBody), findsOneWidget);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        expect(find.descendant(of: _pill(i), matching: find.text(_phrase[i])),
            findsOneWidget);
        expect(find.descendant(of: _pill(i), matching: find.text('${i + 1}')),
            findsOneWidget);
      }
      expect(tester.widget<AtomicButton>(_copy).variant,
          AtomicButtonVariant.tonal);
      expect(tester.widget<AtomicButton>(_wrote).variant,
          AtomicButtonVariant.primary);
      expect(find.text('STEP 1 OF 2 / WRITE IT DOWN'), findsNothing);
    });

    testWidgets('two pills per row, row by row', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _tap(tester, _generate);
      for (var i = 0; i < SeedPhrase.wordCount; i += 2) {
        final left = tester.getRect(_pill(i));
        final right = tester.getRect(_pill(i + 1));
        expect(left.top, right.top);
        expect(left.right, lessThan(right.left));
        if (i > 0) {
          expect(left.top, greaterThan(tester.getRect(_pill(i - 2)).bottom));
        }
      }
      final word = tester.widget<Text>(
          find.descendant(of: _pill(0), matching: find.text(_phrase[0])));
      expect(word.style!.fontFamily, AtomicType.mono.fontFamily);
    });

    testWidgets('Copy puts the phrase on the clipboard and clears it in 60 s',
        (tester) async {
      _mockClipboard(tester);
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _tap(tester, _generate);
      await _tap(tester, _copy);
      expect(_clip, _phrase.join(' '));
      expect(find.text(EncryptionPage.copiedMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(_clip, _phrase.join(' '));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_clip, '');
    });

    testWidgets('Copy never clears something copied since', (tester) async {
      _mockClipboard(tester);
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _tap(tester, _generate);
      await _tap(tester, _copy);
      _clip = 'something else';
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(_clip, 'something else');
    });

    testWidgets('I wrote it down moves to step 2, and Back returns',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _toVerify(tester);
      expect(find.text(EncryptionPage.step2), findsOneWidget);
      expect(find.text(EncryptionPage.verifyTitle), findsOneWidget);
      expect(find.text(EncryptionPage.verifyBody), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(SeedPhrase.wordCount));
      expect(
          tester.widget<AtomicButton>(_back).variant, AtomicButtonVariant.text);

      await _tap(tester, _back);
      expect(find.text(EncryptionPage.step1), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        expect(find.text(_phrase[i]), findsOneWidget);
      }
      // One phrase for the whole setup.
      expect(fakes.calls, ['generate']);
    });

    testWidgets('missing words and the wrong order never reach the vault',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _tap(tester, _turnOn);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.incompleteMessage);

      await _type(tester, _phrase.take(5).toList());
      await _tap(tester, _turnOn);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.incompleteMessage);

      await _type(tester, _phrase.reversed.toList());
      await _tap(tester, _turnOn);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.mismatchMessage);
      expect(fakes.calls, ['generate']);
    });
  });

  group('turning on', () {
    testWidgets('creates the vault, then migrates, then shows On',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn);
      expect(fakes.calls, ['generate', 'createVault', 'migrateToVault']);
      expect(fakes.created.single, _phrase);
      expect(find.text(EncryptionPage.onMessage), findsOneWidget);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(find.text(EncryptionPage.onBody), findsOneWidget);
      expect(find.text(EncryptionPage.chipOn), findsOneWidget);
      expect(_error, findsNothing);
      // The phrase is gone from the screen.
      for (final word in _phrase) {
        expect(find.text(word), findsNothing);
      }
      await _drainSnack(tester);
    });

    for (final (n, copy) in [
      (
        1,
        'Encryption is on. 1 note is still plain in the cloud and will be '
            'encrypted at the next sync.'
      ),
      (
        3,
        'Encryption is on. 3 notes are still plain in the cloud and will be '
            'encrypted at the next sync.'
      ),
    ]) {
      testWidgets('says how many notes still wait ($n)', (tester) async {
        final fakes = _Fakes()..waiting = n;
        await _pump(tester, fakes);
        await _toVerify(tester);
        await _type(tester, _phrase);
        await _tap(tester, _turnOn);
        expect(EncryptionPage.waitingMessage(n), copy);
        expect(find.text(copy), findsOneWidget);
        expect(find.text(EncryptionPage.onMessage), findsNothing);
        await _drainSnack(tester);
      });
    }

    testWidgets('while it runs the button is busy and taps are ignored',
        (tester) async {
      final handle = tester.ensureSemantics();
      final fakes = _Fakes()..createGate = Completer<void>();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn, settle: false);
      expect(tester.widget<AtomicButton>(_turnOn).busy, isTrue);
      expect(_hasTap(tester, _turnOn), isFalse);
      expect(tester.widget<AtomicButton>(_back).onPressed, isNull);
      expect(find.text(EncryptionPage.turningOn), findsOneWidget);
      final live = tester.widget<Semantics>(
          find.ancestor(of: _busy, matching: find.byType(Semantics)).first);
      expect(live.properties.liveRegion, isTrue);

      await _tap(tester, _turnOn, settle: false);
      expect(fakes.calls, ['generate', 'createVault']);

      fakes.createGate!.complete();
      await tester.pumpAndSettle();
      expect(fakes.calls, ['generate', 'createVault', 'migrateToVault']);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(_busy, findsNothing);
      await _drainSnack(tester);
      handle.dispose();
    });

    testWidgets('the migration step also keeps the button busy',
        (tester) async {
      final fakes = _Fakes()..migrateGate = Completer<int>();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn, settle: false);
      expect(fakes.calls.last, 'migrateToVault');
      // The vault is on underneath, but the page waits for the notes step.
      expect(find.text(EncryptionPage.turningOn), findsOneWidget);
      fakes.migrateGate!.complete(0);
      await tester.pumpAndSettle();
      expect(find.text(EncryptionPage.onMessage), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('a failure says so, keeps the words, and a retry works',
        (tester) async {
      final fakes = _Fakes()
        ..createError = StateError('detail ${_phrase.join(' ')}');
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn);
      expect(fakes.calls, ['generate', 'createVault']);
      final banner = tester.widget<AtomicBanner>(_error);
      expect(banner.tone, BannerTone.danger);
      expect(banner.title, EncryptionPage.failedMessage);
      expect(find.text(EncryptionPage.step2), findsOneWidget);
      expect(tester.widget<TextField>(_field(0)).controller!.text, _phrase[0]);
      expect(tester.widget<AtomicButton>(_turnOn).busy, isFalse);

      fakes.createError = null;
      await _tap(tester, _turnOn);
      expect(fakes.calls,
          ['generate', 'createVault', 'createVault', 'migrateToVault']);
      expect(fakes.created, [_phrase, _phrase]);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(_error, findsNothing);
      await _drainSnack(tester);
    });

    testWidgets('an account with a vault already shows Locked and says why',
        (tester) async {
      final fakes = _Fakes()..createError = const VaultAlreadyExistsError();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn);
      expect(fakes.calls, ['generate', 'createVault']);
      expect(find.text(EncryptionPage.lockedTitle), findsOneWidget);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.existsMessage);
      expect(find.text(EncryptionPage.onTitle), findsNothing);
    });

    testWidgets('a failed notes step after the vault is made says it is on',
        (tester) async {
      final fakes = _Fakes()..migrateError = StateError('offline');
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn);
      expect(fakes.calls, ['generate', 'createVault', 'migrateToVault']);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(tester.widget<AtomicBanner>(_error).title,
          EncryptionPage.partialMessage);
      expect(find.text(EncryptionPage.failedMessage), findsNothing);
      expect(find.text(EncryptionPage.onMessage), findsNothing);

      // Locking from here shows the lock running, not the setup step.
      fakes.lockGate = Completer<void>();
      await _tap(tester, _lock, settle: false);
      expect(find.text(EncryptionPage.locking), findsOneWidget);
      expect(find.text(EncryptionPage.turningOn), findsNothing);
      expect(_turnOn, findsNothing);
      fakes.lockGate!.complete();
      await tester.pumpAndSettle();
      expect(_pushed.single.name, '/vaultunlock');
    });

    testWidgets('leaving mid-setup finishes the same calls quietly',
        (tester) async {
      final fakes = _Fakes()..createGate = Completer<void>();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn, settle: false);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);

      fakes.createGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fakes.calls, ['generate', 'createVault', 'migrateToVault']);
      expect(find.text(EncryptionPage.onMessage), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(_pushed, isEmpty);
    });

    testWidgets('leaving after a failure started shows nothing',
        (tester) async {
      final fakes = _Fakes()
        ..createGate = Completer<void>()
        ..createError = StateError('offline');
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _type(tester, _phrase);
      await _tap(tester, _turnOn, settle: false);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      fakes.createGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fakes.calls, ['generate', 'createVault']);
      expect(find.text(EncryptionPage.failedMessage), findsNothing);
    });
  });

  group('on', () {
    testWidgets('a hero card, the device explanation and a tonal Lock',
        (tester) async {
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true;
      await _pump(tester, fakes);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(find.text(EncryptionPage.onBody), findsOneWidget);
      expect(find.text(EncryptionPage.lockBody), findsOneWidget);
      final chip = tester.widget<StatusChip>(find.ancestor(
          of: find.text(EncryptionPage.chipOn),
          matching: find.byType(StatusChip)));
      expect(chip.tone, StatusTone.accent);
      final lock = tester.widget<AtomicButton>(_lock);
      expect(lock.variant, AtomicButtonVariant.tonal);
      expect(lock.label, EncryptionPage.lockLabel);
      expect(_generate, findsNothing);
      expect(find.text('Your notes are encrypted'), findsNothing);
    });

    testWidgets('Lock forgets the key and clears the stack to the unlock page',
        (tester) async {
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true;
      await _pump(tester, fakes);
      await _tap(tester, _lock);
      expect(fakes.calls, ['lockVault']);
      expect(_pushed.single.name, '/vaultunlock');
      expect(_pushed.single.arguments, true);
      expect(find.byType(EncryptionPage), findsNothing);
      expect(find.text('settings page'), findsNothing);
    });

    testWidgets('while locking the button is busy and taps are ignored',
        (tester) async {
      final handle = tester.ensureSemantics();
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true
        ..lockGate = Completer<void>();
      await _pump(tester, fakes);
      await _tap(tester, _lock, settle: false);
      expect(tester.widget<AtomicButton>(_lock).busy, isTrue);
      expect(_hasTap(tester, _lock), isFalse);
      expect(find.text(EncryptionPage.locking), findsOneWidget);
      await _tap(tester, _lock, settle: false);
      expect(fakes.calls, ['lockVault']);
      fakes.lockGate!.complete();
      await tester.pumpAndSettle();
      expect(_pushed.single.name, '/vaultunlock');
      handle.dispose();
    });

    testWidgets('a failed lock with the key kept says so, and a retry works',
        (tester) async {
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true
        ..lockError = StateError('busy');
      await _pump(tester, fakes);
      await _tap(tester, _lock);
      expect(find.text(EncryptionPage.lockFailedMessage), findsOneWidget);
      expect(find.byType(EncryptionPage), findsOneWidget);
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(tester.widget<AtomicButton>(_lock).busy, isFalse);
      expect(_pushed, isEmpty);
      await _drainSnack(tester);

      fakes.lockError = null;
      await _tap(tester, _lock);
      expect(fakes.calls, ['lockVault', 'lockVault']);
      expect(_pushed.single.name, '/vaultunlock');
    });

    testWidgets('a failed lock that still forgot the key goes on to unlock',
        (tester) async {
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true
        ..lockError = StateError('late')
        ..lockFailureKeepsKey = false;
      await _pump(tester, fakes);
      await _tap(tester, _lock);
      expect(_pushed.single.name, '/vaultunlock');
      expect(_pushed.single.arguments, true);
      expect(find.text(EncryptionPage.lockFailedMessage), findsNothing);
    });

    testWidgets('leaving mid-lock does not navigate afterwards',
        (tester) async {
      final fakes = _Fakes()
        ..unlocked = true
        ..enabled = true
        ..lockGate = Completer<void>();
      await _pump(tester, fakes);
      await _tap(tester, _lock, settle: false);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      fakes.lockGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fakes.calls, ['lockVault']);
      expect(_pushed, isEmpty);
      expect(find.text('settings page'), findsOneWidget);
    });

    for (final keepsKey in [true, false]) {
      testWidgets(
          'leaving mid-lock, a failed lock shows and opens nothing '
          '(${keepsKey ? 'key kept' : 'key gone'})', (tester) async {
        final fakes = _Fakes()
          ..unlocked = true
          ..enabled = true
          ..lockGate = Completer<void>()
          ..lockError = StateError('busy')
          ..lockFailureKeepsKey = keepsKey;
        await _pump(tester, fakes);
        await _tap(tester, _lock, settle: false);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        fakes.lockGate!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(fakes.calls, ['lockVault']);
        expect(_pushed, isEmpty);
        expect(find.text(EncryptionPage.lockFailedMessage), findsNothing);
        expect(find.text('settings page'), findsOneWidget);
      });
    }
  });

  group('locked here', () {
    testWidgets('a Locked hero and Unlock vault', (tester) async {
      final fakes = _Fakes()..enabled = true;
      await _pump(tester, fakes);
      expect(find.text(EncryptionPage.lockedTitle), findsOneWidget);
      expect(find.text(EncryptionPage.lockedBody), findsOneWidget);
      final chip = tester.widget<StatusChip>(find.ancestor(
          of: find.text(EncryptionPage.chipLocked),
          matching: find.byType(StatusChip)));
      expect(chip.tone, StatusTone.inverse);
      expect(tester.widget<AtomicButton>(_unlock).variant,
          AtomicButtonVariant.primary);
      expect(_generate, findsNothing);
      expect(_lock, findsNothing);
    });

    testWidgets('Unlock vault opens the unlock page; the result shows after',
        (tester) async {
      final fakes = _Fakes()..enabled = true;
      await _pump(tester, fakes);
      await _tap(tester, _unlock);
      expect(_pushed.single.name, '/vaultunlock');
      expect(_pushed.single.arguments, isNull);
      // The unlock page opened the vault.
      fakes.unlocked = true;
      await tester.tap(find.text('leave route'));
      await tester.pumpAndSettle();
      expect(find.text(EncryptionPage.onTitle), findsOneWidget);
      expect(find.text(EncryptionPage.lockedTitle), findsNothing);
      expect(fakes.calls, isEmpty);
    });
  });

  group('credentials', () {
    testWidgets('the phrase never reaches the log or a message',
        (tester) async {
      final logged = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logged.add(message);
      };
      _mockClipboard(tester);
      final fakes = _Fakes()
        ..createError = StateError('detail ${_phrase.join(' ')}');
      try {
        await _pump(tester, fakes);
        await _tap(tester, _generate);
        await _tap(tester, _copy);
        await _tap(tester, _wrote);
        await _type(tester, _phrase);
        await _tap(tester, _turnOn);
        fakes
          ..createError = null
          ..migrateError = StateError(_phrase.join(' '));
        await _tap(tester, _turnOn);
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
      } finally {
        // Restored inside the test body, before the binding checks it.
        debugPrint = original;
      }
      for (final word in _phrase) {
        expect(logged.where((l) => l.contains(word)), isEmpty);
        // No message repeats a word.
        expect(
            find.byWidgetPredicate((w) =>
                w is Text &&
                (w.data ?? '').contains(' ') &&
                (w.data ?? '').split(' ').contains(word)),
            findsNothing);
      }
    });

    testWidgets('the confirm fields keep the entry rules of the old page',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _toVerify(tester);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        await _reveal(tester, _field(i));
        final field = tester.widget<TextField>(_field(i));
        expect(field.autocorrect, isFalse);
        expect(field.enableSuggestions, isFalse);
        expect(
            field.textInputAction,
            i == SeedPhrase.wordCount - 1
                ? TextInputAction.done
                : TextInputAction.next);
      }
    });
  });

  group('look', () {
    testWidgets('canvas, pill fields in mono and 48 dp targets',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      expect(
          tester
              .widget<Scaffold>(find.ancestor(
                  of: find.text(EncryptionPage.offTitle),
                  matching: find.byType(Scaffold)))
              .backgroundColor,
          AtomicColors.light.canvas);
      expect(tester.getSize(_generate).height, greaterThanOrEqualTo(48));
      await _tap(tester, _generate);
      expect(tester.getSize(_copy).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_wrote).height, greaterThanOrEqualTo(48));
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        expect(tester.getSize(_pill(i)).height, greaterThanOrEqualTo(48));
      }
      await _tap(tester, _wrote);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        await _reveal(tester, _field(i));
        final field = tester.widget<TextField>(_field(i));
        final border = field.decoration!.enabledBorder! as OutlineInputBorder;
        expect(border.borderRadius, AtomicRadius.pill);
        expect(field.style!.fontFamily, AtomicType.mono.fontFamily);
        expect(find.descendant(of: _word(i), matching: find.text('${i + 1}')),
            findsOneWidget);
        expect(tester.getSize(_field(i)).height, greaterThanOrEqualTo(48));
      }
      expect(tester.getSize(_turnOn).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_back).height, greaterThanOrEqualTo(48));
    });

    testWidgets('the dark theme uses the dark tokens', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, theme: AtomicTheme.dark);
      expect(
          tester
              .widget<Scaffold>(find.ancestor(
                  of: find.text(EncryptionPage.offTitle),
                  matching: find.byType(Scaffold)))
              .backgroundColor,
          AtomicColors.dark.canvas);
      final title = tester.widget<Text>(find.text(EncryptionPage.offTitle));
      expect(title.style!.color, AtomicColors.dark.textPrimary);
    });

    testWidgets('an error is a danger banner announced as it appears',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _toVerify(tester);
      await _tap(tester, _turnOn);
      final live = tester.widget<Semantics>(
          find.ancestor(of: _error, matching: find.byType(Semantics)).first);
      expect(live.properties.liveRegion, isTrue);
    });

    testWidgets('words, fields and titles are named for screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      final fakes = _Fakes();
      await _pump(tester, fakes);
      expect(tester.getSemantics(find.text(EncryptionPage.offTitle)),
          matchesSemantics(label: EncryptionPage.offTitle, isHeader: true));
      await _tap(tester, _generate);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        final data = tester.getSemantics(_pill(i)).getSemanticsData();
        expect(data.label, EncryptionPage.wordLabel(i));
        expect(data.value, _phrase[i]);
      }
      expect(tester.getSemantics(find.text(EncryptionPage.showTitle)),
          matchesSemantics(label: EncryptionPage.showTitle, isHeader: true));
      await _tap(tester, _wrote);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        await _reveal(tester, _field(i));
        final data = tester.getSemantics(_field(i)).getSemanticsData();
        expect(data.label, contains(EncryptionPage.wordLabel(i)));
        expect(data.flagsCollection.isTextField, isTrue);
      }
      handle.dispose();
    });

    testWidgets('motion follows reduced motion', (tester) async {
      for (final reduced in [false, true]) {
        final fakes = _Fakes();
        await _pump(tester, fakes, disableAnimations: reduced);
        final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
        expect(size.duration, reduced ? Duration.zero : AtomicMotion.standard);
        final fade =
            tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
        expect(fade.duration, AtomicMotion.quick);
      }
    });

    testWidgets('with large text the phrase stacks in one column',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, width: 320, height: 640, textScale: 2);
      await _tap(tester, _generate);
      await _reveal(tester, _pill(1));
      await _reveal(tester, _pill(0));
      expect(tester.getRect(_pill(0)).left, tester.getRect(_pill(1)).left);
      expect(tester.getRect(_pill(1)).top,
          greaterThan(tester.getRect(_pill(0)).bottom));
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final state in [
        'off',
        'step 1',
        'step 2',
        'busy',
        'error',
        'on',
        'locking',
        'locked',
      ]) {
        testWidgets('fits 320 dp at 2.0 text ($name, $state)', (tester) async {
          final fakes = _Fakes();
          if (state == 'on' || state == 'locking') {
            fakes
              ..unlocked = true
              ..enabled = true
              ..lockGate = Completer<void>();
          }
          if (state == 'locked') fakes.enabled = true;
          if (state == 'busy') fakes.createGate = Completer<void>();
          await _pump(tester, fakes,
              theme: theme, width: 320, height: 640, textScale: 2);
          expect(tester.takeException(), isNull);
          final targets = <Finder>[];
          switch (state) {
            case 'off':
              targets.add(_generate);
            case 'step 1':
              await _tap(tester, _generate);
              targets.addAll(
                  [_copy, _wrote, for (var i = 0; i < 6; i++) _pill(i)]);
            case 'step 2':
              await _toVerify(tester);
              targets.addAll([_turnOn, _back, _field(0), _field(5)]);
            case 'busy':
              await _toVerify(tester);
              await _type(tester, _phrase);
              await _tap(tester, _turnOn, settle: false);
              targets.addAll([_turnOn, _busy, _back]);
            case 'error':
              await _toVerify(tester);
              await _tap(tester, _turnOn);
              targets.addAll([_error, _turnOn]);
            case 'on':
              targets.add(_lock);
            case 'locking':
              await _tap(tester, _lock, settle: false);
              targets.addAll([_lock, _busy]);
            case 'locked':
              targets.add(_unlock);
          }
          for (final f in targets) {
            await _reveal(tester, f);
            final rect = tester.getRect(f);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          }
          expect(tester.takeException(), isNull);
          if (state == 'busy') {
            fakes.createGate!.complete();
            await tester.pumpAndSettle();
            await _drainSnack(tester);
          }
          if (state == 'locking') {
            fakes.lockGate!.complete();
            await tester.pumpAndSettle();
          }
        });
      }
    }
  });
}
