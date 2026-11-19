// The editor on lib/ui components (UX-04-editor): the layout checks every
// redesigned screen passes, in both themes and both directions, the "…" menu
// and the control targets. Save behaviour is covered by the S1 tests and
// notes_editor_page_test.dart; this file only checks presentation.

import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Note _full() => Note(
      id: 'redesign',
      title: 'Weekend plan with a title long enough to wrap twice',
      body: jsonEncode({
        'v': 2,
        'tags': ['travel', 'home', 'a-long-tag-name'],
        'blocks': [
          {
            'text': 'Pack the bags, water the plants and call the neighbours.',
            'checklist': false,
            'done': false,
            'styles': [],
          },
          {'text': 'Passport', 'checklist': true, 'done': false, 'styles': []},
          {'text': 'Tickets', 'checklist': true, 'done': true, 'styles': []},
        ],
      }),
      items: [TodoItem(text: NoteDocument.richFormatMarker)],
    );

Future<void> _open(
  WidgetTester tester,
  Note note, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  double scale = 1,
  double keyboard = 0,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => NotesCreaterPage(note: note),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, theme) in [
    ('light', AtomicTheme.light),
    ('dark', AtomicTheme.dark),
  ]) {
    for (final direction in TextDirection.values) {
      for (final keyboard in [0.0, 280.0]) {
        testWidgets(
            'fits 320 dp at 2.0 text ($name, ${direction.name}, '
            '${keyboard == 0 ? 'no keyboard' : 'keyboard open'})',
            (tester) async {
          await _open(tester, _full(),
              theme: theme,
              size: const Size(320, 640),
              scale: 2,
              keyboard: keyboard,
              direction: direction);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byTooltip('More actions'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Copy note'), findsOneWidget);
        });
      }
    }
  }

  testWidgets('the dark theme paints the editor with dark roles',
      (tester) async {
    await _open(tester, _full(), theme: AtomicTheme.dark);

    final scaffolds = tester
        .widgetList<Scaffold>(find.byType(Scaffold))
        .where((s) => s.backgroundColor != null)
        .map((s) => s.backgroundColor)
        .toList();
    expect(scaffolds, isNotEmpty);
    expect(scaffolds, contains(AtomicColors.dark.canvas));
    expect(scaffolds, isNot(contains(AtomicColors.light.canvas)));
  });

  testWidgets('a new note offers Copy and Discard in the menu', (tester) async {
    await _open(tester, Note.create());

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Copy note'), findsOneWidget);
    expect(find.text('Discard note'), findsOneWidget);
    expect(find.text('Move to Recycle Bin'), findsNothing);
  });

  testWidgets('header and toolbar targets are at least 48 dp', (tester) async {
    // Fewer than three tags, so Add tag is offered.
    await _open(tester, Note.create());

    for (final tooltip in [
      'Back to notes',
      'More actions',
      'Pin note',
      'Add tag',
    ]) {
      final target = find.byTooltip(tooltip);
      expect(target, findsWidgets, reason: tooltip);
      final size = tester.getSize(target.first);
      expect(size.shortestSide, greaterThanOrEqualTo(48), reason: tooltip);
    }
  });
}
