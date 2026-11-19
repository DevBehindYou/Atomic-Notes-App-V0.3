// Review R23 on the editor (UX-04-editor):
// - the delete action says what the caller's delete does: the signed-in notes
//   move a note to the Recycle Bin, the guest workspace removes it for good;
// - a phone in landscape with the keyboard up keeps the title, the draft and
//   Done reachable, and the header's actions move into the toolbar.

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/profile/guest_workspace_page.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestMemory implements GuestNotesPort {
  final entries = [
    Note(id: 'guest-probe', title: 'Synthetic note', body: 'Sample'),
  ];
  int removals = 0;

  @override
  Future<void> open() async {}
  @override
  List<Note> notes() => List.of(entries);
  @override
  Future<void> save(Note note) async => entries.add(note);
  @override
  Future<void> remove(String id) async {
    removals++;
    entries.removeWhere((n) => n.id == id);
  }
}

Future<void> _openGuestNote(WidgetTester tester, _GuestMemory notes) async {
  await tester.pumpWidget(MaterialApp(home: GuestWorkspacePage(notes: notes)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('guest-note-guest-probe')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester, NotesCreaterPage page,
    {Size size = const Size(390, 844), double keyboard = 0}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => page,
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
  group('delete says what it does', () {
    testWidgets('a guest note is deleted permanently, never "Recycle Bin"',
        (tester) async {
      final notes = _GuestMemory();
      await _openGuestNote(tester, notes);

      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.textContaining('Recycle Bin'), findsNothing);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this note permanently?'), findsOneWidget);
      expect(find.textContaining('cannot be restored'), findsOneWidget);
      expect(find.textContaining('Recycle Bin'), findsNothing);

      await tester.tap(find.text('Delete permanently').last);
      await tester.pumpAndSettle();
      expect(notes.removals, 1);
      expect(notes.notes(), isEmpty);
      expect(
          find.byKey(const ValueKey('guest-note-guest-probe')), findsNothing);
    });

    testWidgets('cancelling a guest delete writes nothing', (tester) async {
      final notes = _GuestMemory();
      await _openGuestNote(tester, notes);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(notes.removals, 0);
      expect(notes.notes(), hasLength(1));
      // The editor is still open on the note.
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    testWidgets(
        'a signed-in note moves to the Recycle Bin, and Cancel keeps it',
        (tester) async {
      var deletes = 0;
      await _openEditor(
          tester,
          NotesCreaterPage(
              note: Note(id: 'signed-in', title: 'Saved', body: 'Body'),
              onDelete: () => deletes++));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Move to Recycle Bin'), findsOneWidget);
      expect(find.text('Delete permanently'), findsNothing);

      await tester.tap(find.text('Move to Recycle Bin'));
      await tester.pumpAndSettle();
      expect(find.text('Move note to Recycle Bin?'), findsOneWidget);
      expect(find.textContaining('can be restored from the Recycle Bin'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletes, 0);

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Recycle Bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Recycle Bin').last);
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });
  });

  group('landscape with the keyboard up', () {
    for (final inset in [210.0, 222.0, 230.0]) {
      testWidgets(
          'inset $inset: no overflow; title, Done and actions reachable',
          (tester) async {
        await _openEditor(tester, NotesCreaterPage(note: Note.create()),
            size: const Size(640, 360), keyboard: inset);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('note-title')).hitTestable(),
            findsOneWidget);
        final done = find.text('Done');
        expect(done.hitTestable(), findsOneWidget);
        expect(tester.getRect(done).bottom, lessThanOrEqualTo(360 - inset));
        // The header's actions live in the toolbar now.
        expect(find.byTooltip('Back to notes'), findsOneWidget);
        for (final tooltip in ['Pin note', 'More actions']) {
          await tester.ensureVisible(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
          expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget,
              reason: tooltip);
        }
      });
    }

    testWidgets('the edited draft is kept and saved in the tight layout',
        (tester) async {
      final note = Note.create();
      await _openEditor(tester, NotesCreaterPage(note: note),
          size: const Size(640, 360), keyboard: 222);

      await tester.enterText(find.byKey(const ValueKey('note-title')), 'Trip');
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Pin note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pin note'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Nothing is written until Done.
      expect(note.title, isEmpty);
      expect(note.pinned, isFalse);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(note.title, 'Trip');
      expect(note.pinned, isTrue);
    });

    testWidgets('a portrait phone keeps the header', (tester) async {
      await _openEditor(tester, NotesCreaterPage(note: Note.create()),
          size: const Size(390, 844), keyboard: 300);
      expect(tester.takeException(), isNull);
      // Header row present: Back sits above the title, not in the toolbar.
      final back = tester.getRect(find.byTooltip('Back to notes'));
      final title = tester.getRect(find.byKey(const ValueKey('note-title')));
      expect(back.bottom, lessThanOrEqualTo(title.top));
    });
  });
}
