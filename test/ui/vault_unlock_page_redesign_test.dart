// The vault unlock page on lib/ui components (screens spec, Vault unlock),
// over a fake phrase check, a fake notes reload and a fake sign-in identity.
// The unlock logic is the one on main: the same checks before the vault is
// asked, the same messages, the same routes. Added here: a result that
// arrives after the sign-in changed, or after a newer attempt, is ignored.
//
// Every phrase is synthetic, built from the public word list.

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:atomic_notes/page/endpage/vault_unlock_page.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/wordlist.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<String> _phrase = [
  for (var i = 0; i < SeedPhrase.wordCount; i++) kWordList[i * 11 + 5],
];
final List<String> _otherPhrase = [
  for (var i = 0; i < SeedPhrase.wordCount; i++) kWordList[i * 13 + 400],
];

/// The phrase check, reload and sign-in the page is given.
class _Fakes {
  final List<List<String>> unlocks = [];
  final List<Completer<bool>> answers = [];
  int reloads = 0;
  Completer<void>? reloadGate;
  Object session = ('fixture-user-a', 1);

  Future<bool> unlock(List<String> phrase) {
    unlocks.add(List.of(phrase));
    final answer = Completer<bool>();
    answers.add(answer);
    return answer.future;
  }

  Future<void> reload() async {
    reloads++;
    await reloadGate?.future;
  }
}

final List<RouteSettings> _pushed = [];

Finder _word(int i) => find.byKey(ValueKey('vault-word-$i'));
Finder _field(int i) =>
    find.descendant(of: _word(i), matching: find.byType(TextField));
final Finder _unlock = find.byKey(const ValueKey('vault-unlock'));
final Finder _skip = find.byKey(const ValueKey('vault-skip'));
final Finder _error = find.byKey(const ValueKey('vault-error'));

Future<void> _pump(
  WidgetTester tester,
  _Fakes fakes, {
  bool fromStartup = false,
  ThemeData? theme,
  double width = 412,
  double height = 2400,
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
    initialRoute: '/vaultunlock',
    onGenerateRoute: (settings) {
      if (settings.name == '/') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('settings page')));
      }
      if (settings.name == '/vaultunlock') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => VaultUnlockPage(
                  fromStartup: fromStartup,
                  unlock: fakes.unlock,
                  reloadAfterUnlock: fakes.reload,
                  sessionIdentity: () => fakes.session,
                ));
      }
      _pushed.add(settings);
      return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route ${settings.name}')));
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

Future<void> _type(WidgetTester tester, List<String> words) async {
  for (var i = 0; i < words.length; i++) {
    await _reveal(tester, _field(i));
    await tester.enterText(_field(i), words[i]);
  }
  await tester.pump();
}

Future<void> _tapUnlock(WidgetTester tester) async {
  await _reveal(tester, _unlock);
  await tester.tap(_unlock, warnIfMissed: false);
  // Past the button's spinner fade and any old message fading out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Answers the latest check. While a gated reload keeps the spinner turning
/// the page cannot settle, so [settle] false only lets time pass.
Future<void> _answer(WidgetTester tester, _Fakes fakes, bool ok,
    {bool settle = true}) async {
  fakes.answers.last.complete(ok);
  await _flush(tester, settle: settle);
}

Future<void> _flush(WidgetTester tester, {bool settle = true}) async {
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

bool _hasTap(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData().hasAction(SemanticsAction.tap);

String _fieldText(WidgetTester tester, int i) =>
    tester.widget<TextField>(_field(i)).controller!.text;

void main() {
  setUp(_pushed.clear);

  group('unlock', () {
    testWidgets('a correct phrase from Settings reloads and goes back',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      expect(fakes.unlocks.single, _phrase);
      expect(fakes.reloads, 0);

      await _answer(tester, fakes, true);
      expect(fakes.reloads, 1);
      expect(find.text('settings page'), findsOneWidget);
      expect(find.byType(VaultUnlockPage), findsNothing);
      expect(_pushed, isEmpty);
    });

    testWidgets('a correct phrase at launch continues through the splash',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, fromStartup: true);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true);
      expect(fakes.reloads, 1);
      expect(_pushed.map((s) => s.name), ['/splashpage']);
      expect(find.byType(VaultUnlockPage), findsNothing);
    });

    testWidgets('the notes reload finishes before the page leaves',
        (tester) async {
      final fakes = _Fakes()..reloadGate = Completer<void>();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true, settle: false);
      expect(fakes.reloads, 1);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
      expect(_hasTap(tester, _unlock), isFalse);

      fakes.reloadGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
    });

    testWidgets('an incorrect phrase stays locked, then a retry opens it',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _otherPhrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, false);

      expect(find.text(VaultUnlockPage.wrongMessage), findsOneWidget);
      expect(fakes.reloads, 0);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
      // The words stay for correcting, and the button is ready again.
      expect(_fieldText(tester, 0), _otherPhrase.first);
      expect(_hasTap(tester, _unlock), isTrue);

      await _type(tester, _phrase);
      await _tapUnlock(tester);
      // A new try clears the old message.
      expect(find.text(VaultUnlockPage.wrongMessage), findsNothing);
      expect(fakes.unlocks, [_otherPhrase, _phrase]);
      await _answer(tester, fakes, true);
      expect(fakes.reloads, 1);
      expect(find.text('settings page'), findsOneWidget);
    });

    testWidgets('missing and unknown words are caught before the vault',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase.take(4).toList());
      await _tapUnlock(tester);
      expect(find.text(VaultUnlockPage.incompleteMessage), findsOneWidget);

      await _type(tester, [..._phrase.take(5), 'qqzx']);
      await _tapUnlock(tester);
      expect(
          find.text(VaultUnlockPage.unknownMessage(['qqzx'])), findsOneWidget);
      expect(fakes.unlocks, isEmpty);
    });

    testWidgets('offline and unexpected failures show plain copy',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      fakes.answers.last.completeError(const VaultUnverifiableError());
      await tester.pumpAndSettle();
      expect(find.text(VaultUnlockPage.offlineMessage), findsOneWidget);

      await _tapUnlock(tester);
      fakes.answers.last
          .completeError(StateError('raw detail ${_phrase.join(' ')}'));
      await tester.pumpAndSettle();
      expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
      expect(find.textContaining('raw detail'), findsNothing);
      expect(_hasTap(tester, _unlock), isTrue);
      expect(fakes.reloads, 0);
    });

    testWidgets('a reload failure stays on the page with plain copy',
        (tester) async {
      final fakes = _Fakes()..reloadGate = Completer<void>();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true, settle: false);
      fakes.reloadGate!.completeError(StateError('reload detail'));
      await tester.pumpAndSettle();
      expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
      expect(find.textContaining('reload detail'), findsNothing);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
    });

    testWidgets('while unlocking it is guarded, and the fields stay editable',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, fromStartup: true);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      expect(fakes.unlocks, hasLength(1));
      expect(
          find.descendant(
              of: _unlock, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(_hasTap(tester, _unlock), isFalse);
      expect(_hasTap(tester, _skip), isFalse);

      await tester.tap(_unlock, warnIfMissed: false);
      await tester.pump();
      await tester.tap(_skip, warnIfMissed: false);
      await tester.pump();
      // Submitting from the keyboard does not start a second check either.
      await tester.showKeyboard(_field(SeedPhrase.wordCount - 1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fakes.unlocks, hasLength(1));
      expect(_pushed, isEmpty);
      // The keyboard is kept: the fields are not disabled.
      expect(tester.widget<TextField>(_field(0)).enabled, isNot(false));

      await _answer(tester, fakes, false);
      expect(_hasTap(tester, _unlock), isTrue);
      expect(_hasTap(tester, _skip), isTrue);
    });
  });

  group('cancel and leaving', () {
    testWidgets('Cancel from Settings goes back without asking the vault',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      expect(find.text(VaultUnlockPage.cancelLabel), findsOneWidget);
      await tester.ensureVisible(_skip);
      await tester.tap(_skip);
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
      expect(fakes.unlocks, isEmpty);
    });

    testWidgets('Skip at launch goes to the notes', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, fromStartup: true);
      expect(find.text(VaultUnlockPage.skipLabel), findsOneWidget);
      // Nothing is behind the page at launch, so no back button.
      expect(find.byTooltip('Back'), findsNothing);
      await tester.ensureVisible(_skip);
      await tester.tap(_skip);
      await tester.pumpAndSettle();
      expect(_pushed.map((s) => s.name), ['/mainpage']);
      expect(fakes.unlocks, isEmpty);
    });

    testWidgets('the header back leaves from Settings', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
    });

    testWidgets('leaving during the check ignores its late result',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);

      await _answer(tester, fakes, true);
      expect(tester.takeException(), isNull);
      expect(fakes.reloads, 0);
      expect(_pushed, isEmpty);
      expect(find.text('settings page'), findsOneWidget);
    });

    testWidgets('leaving during the reload does not navigate again',
        (tester) async {
      final fakes = _Fakes()..reloadGate = Completer<void>();
      await _pump(tester, fakes, fromStartup: true);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true, settle: false);
      expect(fakes.reloads, 1);
      // At launch the page is the only route; replace it as Skip would.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushReplacementNamed('/elsewhere');
      await tester.pumpAndSettle();

      fakes.reloadGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_pushed.map((s) => s.name), ['/elsewhere']);
    });
  });

  group('stale results', () {
    testWidgets('a result for an earlier sign-in never unlocks this one',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, fromStartup: true);
      await _type(tester, _phrase);
      await _tapUnlock(tester);

      // Another account signs in while the old check is still running.
      fakes.session = ('fixture-user-b', 2);
      await _answer(tester, fakes, true);

      expect(fakes.reloads, 0);
      expect(_pushed, isEmpty);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
      expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
      // The phrase typed for the other sign-in is dropped.
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        expect(_fieldText(tester, i), isEmpty);
      }
      expect(_hasTap(tester, _unlock), isTrue);

      // The new sign-in can unlock with its own phrase.
      await _type(tester, _otherPhrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true);
      expect(fakes.reloads, 1);
      expect(_pushed.map((s) => s.name), ['/splashpage']);
    });

    testWidgets('the same user with a new session is a different sign-in',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      fakes.session = ('fixture-user-a', 2);
      await _answer(tester, fakes, true);
      expect(fakes.reloads, 0);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
    });

    testWidgets('a sign-in change during the reload does not continue',
        (tester) async {
      final fakes = _Fakes()..reloadGate = Completer<void>();
      await _pump(tester, fakes, fromStartup: true);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, true, settle: false);
      fakes.session = ('fixture-user-b', 2);
      fakes.reloadGate!.complete();
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(find.byType(VaultUnlockPage), findsOneWidget);
      expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
    });

    for (final error in <Object>[
      const VaultUnverifiableError(),
      StateError('fixture failure'),
    ]) {
      testWidgets(
          'a failure for an earlier sign-in drops the phrase '
          '(${error.runtimeType})', (tester) async {
        final fakes = _Fakes();
        await _pump(tester, fakes);
        await _type(tester, _phrase);
        await _tapUnlock(tester);
        fakes.session = ('fixture-user-b', 2);
        fakes.answers.last.completeError(error);
        await tester.pumpAndSettle();
        expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
        expect(find.text(VaultUnlockPage.offlineMessage), findsNothing);
        for (var i = 0; i < SeedPhrase.wordCount; i++) {
          expect(_fieldText(tester, i), isEmpty);
        }
      });
    }

    testWidgets('a wrong answer for an earlier sign-in is not shown as wrong',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      fakes.session = ('fixture-user-b', 2);
      await _answer(tester, fakes, false);
      expect(find.text(VaultUnlockPage.wrongMessage), findsNothing);
      expect(find.text(VaultUnlockPage.failedMessage), findsOneWidget);
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
      final fakes = _Fakes()..reloadGate = Completer<void>();
      try {
        // Wrong, then failed, then correct with a failing reload.
        await _pump(tester, fakes);
        await _type(tester, _otherPhrase);
        await _tapUnlock(tester);
        await _answer(tester, fakes, false);
        await _tapUnlock(tester);
        fakes.answers.last
            .completeError(StateError('detail ${_otherPhrase.join(' ')}'));
        await tester.pumpAndSettle();
        await _type(tester, _phrase);
        await _tapUnlock(tester);
        await _answer(tester, fakes, true, settle: false);
        fakes.reloadGate!.completeError(StateError(_phrase.join(' ')));
        await tester.pumpAndSettle();
      } finally {
        // Restored inside the test body, before the binding checks it.
        debugPrint = original;
      }

      for (final word in [..._phrase, ..._otherPhrase]) {
        expect(logged.where((l) => l.contains(word)), isEmpty);
        // Only the fields hold the words; no message repeats them.
        expect(
            find.byWidgetPredicate(
                (w) => w is Text && (w.data ?? '').split(' ').contains(word)),
            findsNothing);
      }
    });
  });

  group('keyboard', () {
    testWidgets('the fields keep the entry rules of the old page',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        final field = tester.widget<TextField>(_field(i));
        expect(field.autocorrect, isFalse);
        expect(field.enableSuggestions, isFalse);
        expect(field.textCapitalization, TextCapitalization.none);
        expect(
            field.textInputAction,
            i == SeedPhrase.wordCount - 1
                ? TextInputAction.done
                : TextInputAction.next);
      }
      await tester.enterText(_field(0), 'ab1c-d');
      await tester.pump();
      expect(_fieldText(tester, 0), 'abcd');
    });

    testWidgets('Next moves to the following word', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await tester.showKeyboard(_field(0));
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      final focused = tester.widget<TextField>(_field(1)).focusNode!;
      expect(focused.hasFocus, isTrue);
    });

    testWidgets('Done on the last word unlocks', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await tester.showKeyboard(_field(SeedPhrase.wordCount - 1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fakes.unlocks.single, _phrase);
      await _answer(tester, fakes, false);
    });

    testWidgets('a pasted phrase fills every field', (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await tester.enterText(_field(0), _phrase.join(' '));
      await tester.pump();
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        expect(_fieldText(tester, i), _phrase[i]);
      }
    });
  });

  group('look', () {
    testWidgets('the title, six numbered pills and the actions',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes, fromStartup: true);
      const c = AtomicColors.light;
      expect(
          tester
              .widget<Scaffold>(find.ancestor(
                  of: find.text(VaultUnlockPage.title),
                  matching: find.byType(Scaffold)))
              .backgroundColor,
          c.canvas);
      final title = tester.widget<Text>(find.text(VaultUnlockPage.title));
      expect(title.style!.fontSize, AtomicType.headlineLarge.fontSize);
      expect(find.text(VaultUnlockPage.explanation), findsOneWidget);
      expect(find.text(VaultUnlockPage.footnote), findsOneWidget);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        final field = tester.widget<TextField>(_field(i));
        final border = field.decoration!.enabledBorder! as OutlineInputBorder;
        expect(border.borderRadius, AtomicRadius.pill);
        expect(field.style!.fontFamily, AtomicType.mono.fontFamily);
        expect(find.descendant(of: _word(i), matching: find.text('${i + 1}')),
            findsOneWidget);
      }
      expect(find.text(VaultUnlockPage.unlockLabel), findsOneWidget);
      expect(tester.getSize(_unlock).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_skip).height, greaterThanOrEqualTo(48));
      // The editorial labels are gone.
      expect(find.text('VAULT LOCKED'), findsNothing);
    });

    testWidgets('an error is a danger banner announced as it appears',
        (tester) async {
      final fakes = _Fakes();
      await _pump(tester, fakes);
      await _type(tester, _phrase);
      await _tapUnlock(tester);
      await _answer(tester, fakes, false);
      final banner = tester.widget<AtomicBanner>(_error);
      expect(banner.tone, BannerTone.danger);
      expect(banner.title, VaultUnlockPage.wrongMessage);
      final live = tester.widget<Semantics>(
          find.ancestor(of: _error, matching: find.byType(Semantics)).first);
      expect(live.properties.liveRegion, isTrue);
    });

    testWidgets('each word field is named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final fakes = _Fakes();
      await _pump(tester, fakes);
      for (var i = 0; i < SeedPhrase.wordCount; i++) {
        final data = tester.getSemantics(_field(i)).getSemanticsData();
        expect(data.label, contains(VaultUnlockPage.wordLabel(i)));
        expect(data.flagsCollection.isTextField, isTrue);
      }
      // The last one is the large title; the header's copy is hidden.
      expect(tester.getSemantics(find.text(VaultUnlockPage.title).last),
          matchesSemantics(label: VaultUnlockPage.title, isHeader: true));
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

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final fromStartup in [false, true]) {
        for (final state in ['idle', 'busy', 'error']) {
          testWidgets(
              'fits 320 dp at 2.0 text ($name, '
              '${fromStartup ? 'launch' : 'settings'}, $state)',
              (tester) async {
            final fakes = _Fakes();
            await _pump(tester, fakes,
                fromStartup: fromStartup,
                theme: theme,
                width: 320,
                height: 640,
                textScale: 2);
            expect(tester.takeException(), isNull);
            if (state != 'idle') {
              await _type(tester, _phrase);
              await _tapUnlock(tester);
              if (state == 'error') {
                await _answer(tester, fakes, false);
                await _reveal(tester, _error);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                final rect = tester.getRect(_error);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(320));
              } else {
                await tester.pump(const Duration(milliseconds: 300));
              }
            }
            for (final f in [_unlock, _skip, _field(0)]) {
              await _reveal(tester, f);
              final rect = tester.getRect(f);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(320));
            }
            expect(tester.takeException(), isNull);
            if (state == 'busy') await _answer(tester, fakes, false);
          });
        }
      }
    }
  });
}
