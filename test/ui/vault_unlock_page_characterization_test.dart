// Characterises the vault unlock page through its default wiring: the real
// Vault and notes repository singletons, with nobody signed in. It uses only
// the page's public constructor and its visible copy, so the same file runs
// against the page before and after the redesign (UX-06-vault).
//
// Signed out, `Vault.unlock` has no account to derive a key for and answers
// false without deriving anything, so a well-formed phrase takes the
// incorrect-phrase path. Every phrase here is synthetic, built from the
// public word list.

import 'package:atomic_notes/page/endpage/vault_unlock_page.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/wordlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _wrong =
    'That phrase did not open the vault. Check the words and their order.';
final List<String> _synthetic = [
  for (var i = 0; i < SeedPhrase.wordCount; i++) kWordList[i * 7 + 3],
];

final List<String> _pushed = [];

/// A label, whatever case the page renders it in.
Finder _label(String text) => find.byWidgetPredicate(
    (w) => w is Text && w.data?.toLowerCase() == text.toLowerCase());

Future<void> _pump(WidgetTester tester, {bool fromStartup = false}) async {
  // Tall enough that the lazily built list holds every control.
  tester.view.physicalSize = const Size(412 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    initialRoute: '/vault',
    onGenerateRoute: (settings) {
      if (settings.name == '/') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('settings page')));
      }
      if (settings.name == '/vault') {
        return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => VaultUnlockPage(fromStartup: fromStartup));
      }
      _pushed.add(settings.name!);
      return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route ${settings.name}')));
    },
  ));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, List<String> words) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(SeedPhrase.wordCount));
  for (var i = 0; i < words.length; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(fields.at(i), words[i]);
  }
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(_label(text));
  await tester.pumpAndSettle();
  await tester.tap(_label(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(_pushed.clear);

  testWidgets('six word fields and the unlock action', (tester) async {
    await _pump(tester);
    expect(find.byType(TextField), findsNWidgets(SeedPhrase.wordCount));
    expect(_label('Unlock vault'), findsOneWidget);
    expect(_label('Cancel'), findsOneWidget);
  });

  testWidgets('an incomplete phrase asks for every word', (tester) async {
    await _pump(tester);
    await _type(tester, _synthetic.take(3).toList());
    await _tapText(tester, 'Unlock vault');
    expect(
        find.text('Enter all ${SeedPhrase.wordCount} words.'), findsOneWidget);
  });

  testWidgets('a word outside the list is named', (tester) async {
    await _pump(tester);
    await _type(tester, [..._synthetic.take(5), 'qqzx']);
    await _tapText(tester, 'Unlock vault');
    expect(find.text('Not from the word list: qqzx. Check the spelling.'),
        findsOneWidget);
  });

  testWidgets('an incorrect phrase stays locked, and retrying works',
      (tester) async {
    await _pump(tester);
    await _type(tester, _synthetic);
    await _tapText(tester, 'Unlock vault');
    expect(find.text(_wrong), findsOneWidget);
    expect(find.byType(VaultUnlockPage), findsOneWidget);
    expect(_pushed, isEmpty);

    // The words stay for correcting, and the next try runs again.
    expect(find.text(_synthetic.first), findsOneWidget);
    await _tapText(tester, 'Unlock vault');
    expect(find.text(_wrong), findsOneWidget);
    expect(_pushed, isEmpty);
    // The phrase is never shown back in the message.
    for (final word in _synthetic) {
      expect(find.textContaining('$word,'), findsNothing);
    }
  });

  testWidgets('Cancel from Settings goes back', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Cancel');
    expect(find.text('settings page'), findsOneWidget);
    expect(find.byType(VaultUnlockPage), findsNothing);
    expect(_pushed, isEmpty);
  });

  testWidgets('Skip at launch continues to the notes', (tester) async {
    await _pump(tester, fromStartup: true);
    expect(_label('Skip for now'), findsOneWidget);
    await _tapText(tester, 'Skip for now');
    expect(_pushed, ['/mainpage']);
  });

  testWidgets('system back from Settings leaves the page', (tester) async {
    await _pump(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });
}
