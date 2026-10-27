import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/fake_notes_source.dart';

Note _fixture() {
  final original = Note(
    id: 'existing-rich-note',
    title: 'Original',
    body: 'Context\n- [x] Finished\n- [ ] Pending',
    items: [TodoItem(text: NoteDocument.formatMarker)],
    pinned: true,
    important: true,
    createdAt: DateTime.utc(2026, 10, 27, 12, 0, 0, 862, 722),
    serverVersion: 53,
    syncedSig: 'original-cloud-signature',
  );
  final document = NoteDocument.fromNote(original)
    ..setTags(['synthetic'])
    ..replaceStyles(0, [const NoteStyleRun(0, 7, 3)])
    ..insertImageAfter(
        2, base64Encode(image.encodeJpg(image.Image(width: 2, height: 2))));
  return document.toNote(original);
}

class _Harness {
  _Harness() : source = FakeNotesSource(notes: [_fixture()]);

  final FakeNotesSource source;
  late final NotesBloc bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  final visible = ValueNotifier(true);
  final homeKey = GlobalKey();

  Future<void> open(WidgetTester tester, {bool short = false}) async {
    tester.view.physicalSize = const Size(1290, 2700);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = FakeViewPadding(bottom: short ? 1500 : 0);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!bloc.isClosed) await bloc.close();
      source.dispose();
      visible.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<NotesBloc>.value(
        value: bloc,
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, __) =>
              show ? HomePage(key: homeKey) : const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Let the welcome collapse so a short viewport's card is tappable too.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  Future<void> editWithLayoutChange(WidgetTester tester,
      {bool initiallyShort = false}) async {
    final card =
        tester.element(find.byKey(const ValueKey('existing-rich-note')));
    await tester.tap(find.text('ORIGINAL'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-title')), 'Saved title');
    expect(source.saveCalls, 0);
    tester.view.viewInsets = FakeViewPadding(bottom: initiallyShort ? 0 : 1500);
    await tester.pumpAndSettle();
    expect(card.mounted, isFalse,
        reason: 'The keyboard replaces the originating grid layout.');
    expect(homeKey.currentContext!.mounted, isTrue);
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-title')))
            .controller!
            .text,
        'Saved title');
    tester.view.viewInsets = FakeViewPadding(bottom: initiallyShort ? 1500 : 0);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final initiallyShort in [false, true]) {
    testWidgets(
        'accepted editor save survives ${initiallyShort ? 'short-full-short' : 'full-short-full'} IME layout',
        (tester) async {
      final harness = _Harness();
      await harness.open(tester, short: initiallyShort);
      final original = harness.source.byId('existing-rich-note')!;
      final before = original.toMap();
      await harness.editWithLayoutChange(tester,
          initiallyShort: initiallyShort);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(harness.source.saveCalls, 1);
      final saved = harness.source.byId(original.id)!;
      expect(saved.title, 'Saved title');
      expect(saved.dirty, isTrue);
      final preserved = saved.toMap()
        ..remove('title')
        ..remove('dirty')
        ..remove('updatedAt');
      final expected = Map<String, dynamic>.from(before)
        ..remove('title')
        ..remove('dirty')
        ..remove('updatedAt');
      expect(preserved, expected,
          reason:
              'Rich body, image, tasks, tags, styles, flags, identity and creation time survive title-only saving.');
      expect(original.toMap(), before,
          reason: 'Only the accepted draft replaces the repository object.');
      expect(tester.takeException(), isNull);
      // The short-origin case otherwise triggers a headless Flutter semantics
      // geometry assertion when reparenting the cached header under a dialog.
      // Keep semantics enabled for the matching full-origin save regression.
    }, semanticsEnabled: !initiallyShort);
  }

  testWidgets('cancel after IME layout changes never saves the draft',
      (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    final before = harness.source.byId('existing-rich-note')!.toMap();
    await harness.editWithLayoutChange(tester);
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(harness.source.saveCalls, 0);
    expect(harness.source.byId('existing-rich-note')!.toMap(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the actual Home owner still rejects the editor result',
      (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    final before = harness.source.byId('existing-rich-note')!.toMap();
    await harness.editWithLayoutChange(tester);
    final owner = harness.homeKey.currentContext!;
    harness.visible.value = false;
    await tester.pumpAndSettle();
    expect(owner.mounted, isFalse);
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(harness.source.saveCalls, 0);
    expect(harness.source.byId('existing-rich-note')!.toMap(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed notes bloc still rejects the accepted editor result',
      (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    final before = harness.source.byId('existing-rich-note')!.toMap();
    await harness.editWithLayoutChange(tester);
    await tester.runAsync(harness.bloc.close);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(harness.source.saveCalls, 0);
    expect(harness.source.byId('existing-rich-note')!.toMap(), before);
    expect(tester.takeException(), isNull);
  });
}
