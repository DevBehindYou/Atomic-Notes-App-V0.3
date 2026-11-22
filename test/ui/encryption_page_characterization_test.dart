// Characterises the encryption page through its default wiring: the real
// Vault and notes repository singletons, with nobody signed in. It uses only
// the page's public constructor and its visible copy, so the same file runs
// against the page before and after the redesign (UX-06-encryption).
//
// Signed out, the vault is neither enabled nor unlocked, so the page offers
// setup. `Vault.createVault` has no account to create a vault for and
// throws before any key is derived or anything is sent, so a correctly
// confirmed phrase takes the could-not-turn-on path. The phrase is the one
// the page generates; it is read from the screen and never printed.

import 'package:atomic_notes/page/endpage/encryption_page.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/wordlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _failed = 'Could not turn on encryption. Check your connection.';
const String _incomplete = 'Enter all ${SeedPhrase.wordCount} words.';
const String _mismatch = 'That does not match the phrase. Check the order.';

final Set<String> _words = kWordList.toSet();

/// A label, whatever case the page renders it in.
Finder _label(String text) => find.byWidgetPredicate(
    (w) => w is Text && w.data?.toLowerCase() == text.toLowerCase());

Future<void> _pump(WidgetTester tester) async {
  // Tall enough that the lazily built list holds every control.
  tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    initialRoute: '/encryption',
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => settings.name == '/encryption'
            ? const EncryptionPage()
            : Scaffold(body: Text('route ${settings.name}'))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(_label(text));
  await tester.pumpAndSettle();
  await tester.tap(_label(text));
  await tester.pumpAndSettle();
}

/// The phrase as shown, in screen order.
List<String> _shown(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null && _words.contains(t.data)) t.data!,
    ];

Future<void> _type(WidgetTester tester, List<String> words) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(SeedPhrase.wordCount));
  for (var i = 0; i < words.length; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(fields.at(i), words[i]);
  }
  await tester.pump();
}

void main() {
  testWidgets('signed out, setup is offered', (tester) async {
    await _pump(tester);
    expect(_label('End-to-end encryption'), findsOneWidget);
    expect(_label('Read this first'), findsOneWidget);
    expect(_label('Generate recovery phrase'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('generating shows six list words and the next actions',
      (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Generate recovery phrase');
    final phrase = _shown(tester);
    expect(phrase, hasLength(SeedPhrase.wordCount));
    expect(_label('Copy phrase'), findsOneWidget);
    expect(_label('I wrote it down'), findsOneWidget);
  });

  testWidgets('confirming checks every word and the order', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Generate recovery phrase');
    final phrase = _shown(tester);
    await _tapText(tester, 'I wrote it down');
    expect(find.byType(TextField), findsNWidgets(SeedPhrase.wordCount));

    await _type(tester, phrase.take(3).toList());
    await _tapText(tester, 'Turn on encryption');
    expect(find.text(_incomplete), findsOneWidget);

    await _type(tester, phrase.reversed.toList());
    await _tapText(tester, 'Turn on encryption');
    expect(find.text(_mismatch), findsOneWidget);
    expect(find.text(_incomplete), findsNothing);
  });

  testWidgets('Back returns to the same phrase', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Generate recovery phrase');
    final phrase = _shown(tester);
    await _tapText(tester, 'I wrote it down');
    await _tapText(tester, 'Back');
    expect(find.byType(TextField), findsNothing);
    expect(_shown(tester), phrase);
  });

  testWidgets('signed out, a confirmed phrase cannot turn encryption on',
      (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Generate recovery phrase');
    final phrase = _shown(tester);
    await _tapText(tester, 'I wrote it down');
    await _type(tester, phrase);
    await _tapText(tester, 'Turn on encryption');
    expect(find.text(_failed), findsOneWidget);
    expect(find.byType(EncryptionPage), findsOneWidget);
    // Still confirming, with the words kept for a retry.
    expect(find.byType(TextField), findsNWidgets(SeedPhrase.wordCount));
    expect(find.text(phrase.first), findsOneWidget);

    await _tapText(tester, 'Turn on encryption');
    expect(find.text(_failed), findsOneWidget);
    // The phrase is never shown back in the message.
    for (final word in phrase) {
      expect(find.textContaining('$word '), findsNothing);
    }
  });

  testWidgets('copying puts the phrase on the clipboard, then clears it',
      (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
      } else if (call.method == 'Clipboard.getData') {
        return {'text': clip};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(tester);
    await _tapText(tester, 'Generate recovery phrase');
    final phrase = _shown(tester);
    await _tapText(tester, 'Copy phrase');
    expect(clip, phrase.join(' '));
    expect(find.textContaining('clears from the clipboard in 60s'),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(clip, '');
  });
}
