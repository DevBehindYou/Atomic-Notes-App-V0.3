// S1 characterization: how an editor save is acknowledged on main 9c2c23d,
// before the save-acknowledgement slice. Each case pins today's behaviour.
// Cases marked "S1 changes this" are the defects the slice fixes; they are
// expected to be rewritten, not kept, when it lands.

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

  @override
  Future<void> save(Note note) async {
    attempts++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return super.save(note);
  }
}

class _Home {
  final source = _AckSource();

  /// Errors the bloc rethrows from its handlers, which today reach no UI.
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
  group('today (main 9c2c23d)', () {
    testWidgets(
        'Done closes the editor before the local save finishes '
        '(S1 changes this)', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.gate = Completer<void>();
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing,
          reason: 'the route closes on Done, not on a saved result');
      expect(home.source.attempts, 1);
      expect(home.source.byId('n1')!.title, 'Original',
          reason: 'the save is still waiting');
      home.source.gate!.complete();
      await tester.pumpAndSettle();
      expect(home.source.byId('n1')!.title, 'Edited');
      expect(home.blocErrors, isEmpty);
    });

    testWidgets(
        'a failing local save closes the editor, loses the draft and '
        'tells nobody (S1 changes this)', (tester) async {
      final home = _Home();
      await home.open(tester);
      home.source.failure = StateError('synthetic local write failure');
      await home.editTitle(tester, 'Edited');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(home.source.attempts, 1);
      expect(home.source.byId('n1')!.title, 'Original');
      expect(find.text('Edited'), findsNothing, reason: 'the draft is gone');
      expect(find.byType(SnackBar), findsNothing, reason: 'no feedback');
      expect(home.blocErrors, [isA<StateError>()],
          reason: 'the error only reaches the bloc zone');
    });

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
