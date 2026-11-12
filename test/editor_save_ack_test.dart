// S1 save acknowledgement. The editor closes only after its own attempt is
// stored on this device; a failed or rejected attempt keeps the draft.
// The "unchanged" group keeps the characterization of main 9c2c23d that S1
// preserves; the two cases S1 replaced (Done closing before the save, and a
// failed save losing the draft silently) are in commit 2f22f19.

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

/// A store whose local save can be held open or made to fail.
class _AckSource extends FakeNotesSource {
  _AckSource()
      : super(notes: [Note(id: 'n1', title: 'Original', body: 'Body')]);

  Completer<void>? gate;
  Object? failure;
  int attempts = 0;
  final submitted = <Note>[];

  @override
  Future<void> save(Note note) async {
    attempts++;
    submitted.add(note);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return super.save(note);
  }
}

class _Home {
  final source = _AckSource();

  /// Errors the bloc rethrows from its handlers.
  final blocErrors = <Object>[];
  late final NotesBloc bloc;

  Future<void> open(WidgetTester tester) async {
    // The bloc's event subscription is created here, so errors its handlers
    // rethrow arrive in this zone instead of failing the test.
    runZonedGuarded(() {
      bloc = NotesBloc(
        source: source,
        isSyncEnabled: () => true,
        isOnline: () async => true,
      );
    }, (error, _) => blocErrors.add(error));
    tester.view.physicalSize = const Size(1290, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!bloc.isClosed) await bloc.close();
      source.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<NotesBloc>.value(value: bloc, child: const HomePage()),
    ));
    await tester.pumpAndSettle();
    // Let the welcome collapse.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  Future<void> editTitle(WidgetTester tester, String title) async {
    await tester.tap(find.text('ORIGINAL'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('note-title')), title);
    await tester.pump();
  }
}

void main() {
  group('S1: the editor waits for its own save', () {
    testWidgets(
        'Done stays open, locked, until the save is stored; then '
        'closes once', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.gate = Completer<void>();
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.text('Saving…'), warnIfMissed: false);
      await tester.tap(find.byTooltip('Back to notes'), warnIfMissed: false);
      await tester.pump();
      expect(home.source.attempts, 1, reason: 'no duplicate save');
      expect(find.byType(NotesCreaterPage), findsOneWidget,
          reason: 'Back waits for the save');
      expect(home.source.byId('n1')!.title, 'Original');
      home.source.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.byId('n1')!.title, 'Edited');
      expect(home.source.attempts, 1);
      expect(home.blocErrors, isEmpty);
    });

    testWidgets(
        'a failed save keeps the draft; Edit returns to it and a '
        'later Done saves it', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure = Exception('synthetic local write failure');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Not saved'), findsOneWidget);
      expect(
          find.text('This note could not be saved. Your draft is still here.'),
          findsOneWidget);
      expect(home.source.byId('n1')!.title, 'Original');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('note-title')))
              .controller!
              .text,
          'Edited');
      home.source.failure = null;
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.byId('n1')!.title, 'Edited');
      expect(home.source.attempts, 2);
      expect(home.blocErrors, isEmpty, reason: 'reported, not rethrown');
    });

    testWidgets('Retry saves the same draft again', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure = Exception('synthetic local write failure');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      home.source.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.byId('n1')!.title, 'Edited');
      expect(home.source.attempts, 2);
    });

    testWidgets('Discard after a failure leaves without saving',
        (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure = Exception('synthetic local write failure');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.byId('n1')!.title, 'Original');
      expect(home.source.attempts, 1);
    });

    testWidgets(
        'a session change refused by the store says so; the draft '
        'stays', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure =
          StateError('Notes are changing session. Please retry.');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
          find.text('Notes are changing session. Please retry. '
              'Your draft is still here.'),
          findsOneWidget);
      expect(home.source.byId('n1')!.title, 'Original');
    });

    testWidgets('every attempt saves its own copy of the draft',
        (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure = Exception('synthetic local write failure');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      home.source.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(home.source.submitted, hasLength(2));
      expect(identical(home.source.submitted[0], home.source.submitted[1]),
          isFalse);
      expect(home.source.byId('n1'), same(home.source.submitted[1]));
    });
  });

  group('unchanged from main 9c2c23d', () {
    testWidgets('Done twice saves once', (tester) async {
      final home = _Home();
      await home.open(tester);
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.tap(find.text('Done'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(home.source.attempts, 1);
      expect(home.source.byId('n1')!.title, 'Edited');
    });

    testWidgets('an empty new note is discarded with a message, never saved',
        (tester) async {
      final home = _Home();
      await home.open(tester);
      await tester.tap(find.text('NEW NOTE'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(find.text('Empty note discarded'), findsOneWidget);
      expect(home.source.attempts, 0);
    });

    testWidgets('Back without changes closes without saving', (tester) async {
      final home = _Home();
      await home.open(tester);
      await tester.tap(find.text('ORIGINAL'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.attempts, 0);
    });
  });
}
