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
  @override
  Future<void> open() async {}
  @override
  List<Note> notes() => [for (final n in _notes.values) n.copy()];
  @override
  Future<void> save(Note note) async => _notes[note.id] = note.copy();
  @override
  Future<void> remove(String id) async => _notes.remove(id);
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
