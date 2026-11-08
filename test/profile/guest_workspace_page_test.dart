import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/authentication/auth_pages/login_page.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/profile/guest_profile_store.dart';
import 'package:atomic_notes/profile/guest_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

/// Any attempt to open a network connection fails the test.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Guest mode must not use the network');
  }
}

/// In-memory guest notes. Widget tests run on fake time, where real Hive
/// I/O cannot complete; the real store is covered by the adapter test below
/// and by guest_profile_store_test.dart.
class _MemoryNotes implements GuestNotesPort {
  _MemoryNotes([List<Note> notes = const []])
      : _notes = {for (final n in notes) n.id: n.copy()};
  final Map<String, Note> _notes;

  /// Replaces the instant open, to delay or fail it.
  Future<void> Function()? openWith;

  /// Errors the next saves throw, in order.
  List<Object> failures = [];
  int opens = 0;
  int writes = 0;

  @override
  Future<void> open() async {
    opens++;
    await openWith?.call();
  }

  @override
  List<Note> notes() => [for (final n in _notes.values) n.copy()];
  @override
  Future<void> save(Note note) async {
    if (failures.isNotEmpty) throw failures.removeAt(0);
    writes++;
    _notes[note.id] = note.copy();
  }

  @override
  Future<void> remove(String id) async {
    writes++;
    _notes.remove(id);
  }
}

const _googleLabel = 'SIGN IN WITH GOOGLE';

void main() {
  late _NoNetwork network;

  setUp(() {
    network = _NoNetwork();
  });

  void phone(WidgetTester tester, {double width = 420}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
  }

  // The test font is wider than real fonts; the existing login button row
  // needs a wider test view (unrelated to this change).
  void loginView(WidgetTester tester) => phone(tester, width: 800);

  Future<void> openWorkspace(WidgetTester tester, GuestNotesPort notes) async {
    HttpOverrides.global = network;
    addTearDown(() {
      HttpOverrides.global = null;
      expect(network.attempts, 0, reason: 'no network call in guest mode');
    });
    await tester
        .pumpWidget(MaterialApp(home: GuestWorkspacePage(notes: notes)));
    await tester.pumpAndSettle();
  }

  testWidgets('the Guest entry is off by default; Google start unchanged',
      (tester) async {
    loginView(tester);
    expect(GuestFeature.enabled, isFalse);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    expect(find.text(_googleLabel), findsOneWidget);
    expect(find.byKey(const ValueKey('login-guest')), findsNothing);
  });

  testWidgets('with the gate on, the login page offers Guest entry',
      (tester) async {
    loginView(tester);
    await tester
        .pumpWidget(const MaterialApp(home: LoginPage(guestEntry: true)));
    expect(find.text(_googleLabel), findsOneWidget);
    expect(find.text('Continue without an account'), findsOneWidget);
  });

  testWidgets('status is truthful: local only, not backed up, not synced',
      (tester) async {
    phone(tester);
    await openWorkspace(tester, _MemoryNotes());
    final status =
        tester.widget<Text>(find.byKey(const ValueKey('guest-status'))).data!;
    expect(status, contains('saved on this device only'));
    expect(status, contains('Not backed up and not synced'));
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('create, edit and search offline', (tester) async {
    phone(tester);
    final notes = _MemoryNotes();
    await openWorkspace(tester, notes);
    await tester.tap(find.byKey(const ValueKey('guest-new-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-title')), 'Groceries');
    await tester.enterText(
        find.byKey(const ValueKey('note-body')), 'Milk and eggs');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    expect(notes.notes().single.body, 'Milk and eggs');

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-title')), 'Groceries for Sunday');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries for Sunday'), findsOneWidget);
    expect(notes.notes(), hasLength(1));

    await tester.enterText(find.byKey(const ValueKey('guest-search')), 'eggs');
    await tester.pump();
    expect(find.text('Groceries for Sunday'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('guest-search')), 'bread');
    await tester.pump();
    expect(find.text('Groceries for Sunday'), findsNothing);
  });

  testWidgets('a checklist item can be ticked and stays ticked',
      (tester) async {
    phone(tester);
    final notes = _MemoryNotes([
      Note(
          id: Note.create().id,
          kind: NoteKind.todo,
          title: 'Chores',
          items: [TodoItem(text: 'Sweep')]),
    ]);
    await openWorkspace(tester, notes);
    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(notes.notes().single.items.single.done, isTrue);
  });

  FloatingActionButton newNote(WidgetTester tester) =>
      tester.widget<FloatingActionButton>(
          find.byKey(const ValueKey('guest-new-note')));

  Future<void> writeNote(WidgetTester tester, String title, String body) async {
    await tester.tap(find.byKey(const ValueKey('guest-new-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-title')), title);
    await tester.enterText(find.byKey(const ValueKey('note-body')), body);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets('nothing can be edited while the store is still opening',
      (tester) async {
    phone(tester);
    final opening = Completer<void>();
    final notes = _MemoryNotes()..openWith = (() => opening.future);
    HttpOverrides.global = network;
    addTearDown(() => HttpOverrides.global = null);
    await tester
        .pumpWidget(MaterialApp(home: GuestWorkspacePage(notes: notes)));
    await tester.pump();
    expect(newNote(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('guest-new-note')));
    await tester.pump();
    expect(find.byKey(const ValueKey('note-title')), findsNothing);

    opening.complete();
    await tester.pumpAndSettle();
    expect(newNote(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('guest-status')), findsOneWidget);
  });

  testWidgets('a failed open keeps editing disabled and writes nothing',
      (tester) async {
    phone(tester);
    final notes = _MemoryNotes()
      ..openWith = (() async => throw StateError('cannot open'));
    await openWorkspace(tester, notes);
    expect(find.byKey(const ValueKey('guest-open-failed')), findsOneWidget);
    expect(newNote(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('guest-new-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-title')), findsNothing);
    expect(notes.writes, 0);
  });

  testWidgets('a failed save keeps the draft until a retry stores it once',
      (tester) async {
    phone(tester);
    final notes = _MemoryNotes()..failures = [StateError('disk full')];
    await openWorkspace(tester, notes);
    await writeNote(tester, 'Groceries', 'Milk and eggs');

    expect(notes.notes(), isEmpty);
    expect(find.byKey(const ValueKey('guest-error')), findsOneWidget);
    expect(find.text('Unsaved note: Groceries'), findsOneWidget);
    expect(newNote(tester).onPressed, isNull,
        reason: 'the pending draft is resolved first');

    // The draft is recoverable in full, and saving it can fail again.
    notes.failures = [StateError('still full')];
    await tester.tap(find.byKey(const ValueKey('guest-pending-edit')));
    await tester.pumpAndSettle();
    expect(field(tester, 'note-title'), 'Groceries');
    expect(field(tester, 'note-body'), 'Milk and eggs');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(notes.notes(), isEmpty);
    expect(find.text('Unsaved note: Groceries'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guest-pending-retry')));
    await tester.pumpAndSettle();
    expect(notes.notes().map((n) => (n.title, n.body)),
        [('Groceries', 'Milk and eggs')]);
    expect(find.byKey(const ValueKey('guest-pending')), findsNothing);
    expect(find.byKey(const ValueKey('guest-error')), findsNothing);
    expect(newNote(tester).onPressed, isNotNull);
  });

  testWidgets('a reset during save keeps the draft; retry reopens first',
      (tester) async {
    phone(tester);
    final notes = _MemoryNotes()..failures = [const GuestSessionStale()];
    await openWorkspace(tester, notes);
    await writeNote(tester, 'Plan', 'Call the plumber');

    expect(notes.notes(), isEmpty);
    expect(find.textContaining('was reset'), findsOneWidget);
    expect(find.text('Unsaved note: Plan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guest-pending-retry')));
    await tester.pumpAndSettle();
    expect(notes.opens, 2, reason: 'a stale session is reopened');
    expect(notes.notes().single.body, 'Call the plumber');
  });

  testWidgets('a pending draft is dropped only when discarded', (tester) async {
    phone(tester);
    final notes = _MemoryNotes()..failures = [StateError('disk full')];
    await openWorkspace(tester, notes);
    await writeNote(tester, 'Scratch', 'tmp');
    await tester.tap(find.byKey(const ValueKey('guest-pending-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guest-pending')), findsNothing);
    expect(notes.notes(), isEmpty);
    expect(newNote(tester).onPressed, isNotNull);
  });

  test('the store adapter refuses use before open with a typed error', () {
    final port = GuestStoreNotes(GuestProfileStore());
    expect(port.notes, throwsA(isA<GuestNotesNotOpen>()));
    expect(() => port.save(Note.create()), throwsA(isA<GuestNotesNotOpen>()));
    expect(() => port.remove('x'), throwsA(isA<GuestNotesNotOpen>()));
  });

  test('the real store adapter keeps notes per profile generation', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-guest-ui-');
    Hive.init(directory.path);
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    final store = GuestProfileStore();
    final port = GuestStoreNotes(store);
    await port.open();
    await port.save(Note(id: Note.create().id, title: 'Before'));
    expect(port.notes().map((n) => n.title), ['Before']);

    // A reset must never show earlier notes, and ends the old session.
    await store.reset(await store.open());
    final after = GuestStoreNotes(store);
    await after.open();
    expect(after.notes(), isEmpty);
    await expectLater(port.save(Note(id: Note.create().id, title: 'Late')),
        throwsA(isA<GuestSessionStale>()));

    // Restart: the current generation's notes survive.
    await after.save(Note(id: Note.create().id, title: 'Kept'));
    await store.close();
    await Hive.close();
    Hive.init(directory.path);
    final reopened = GuestStoreNotes(GuestProfileStore());
    await reopened.open();
    expect(reopened.notes().map((n) => n.title), ['Kept']);
  });
}
