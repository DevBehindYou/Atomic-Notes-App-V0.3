// S1 / review R10–R11: while its own save is pending the editor accepts no
// edits from any input, and the save's completion closes only the editor's
// own route. Review R14: a draft whose context was retired leaves the screen
// at once, even while its close waits under another route. Review R16: the
// same holds when that context's seal fails, through the real repository.
// The first case in each group is the reviewer fixture
// (review-evidence/2026-11-12-packet-3/reviewer_s1_edges_test.dart).

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

final _title = find.byKey(const ValueKey('note-title'));

/// Opens the editor over a button, with [onSave] owning the save, and
/// records the editor route's results.
Future<List<bool?>> _open(
    WidgetTester tester, Future<NoteSaveResult> Function(Note) onSave,
    {GlobalKey<NavigatorState>? nav,
    Note? note,
    bool useRootNavigator = true}) async {
  tester.view.physicalSize = const Size(1290, 2700);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final results = <bool?>[];
  await tester.pumpWidget(MaterialApp(
    navigatorKey: nav,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => results.add(await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              useRootNavigator: useRootNavigator,
              builder: (_) => NotesCreaterPage(
                  note: note ??
                      Note(id: 'draft', title: 'Submitted title', body: 'Body'),
                  onSave: onSave))),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

TextField _field(WidgetTester tester) => tester.widget<TextField>(_title);

/// A test vault whose held seal can be made to fail once it has run.
class _SealFailingVault extends TestVault {
  Object? failureAfterSeal;

  @override
  Future<String> encryptContent(Map<String, dynamic> content) async {
    final sealed = await super.encryptContent(content);
    final error = failureAfterSeal;
    if (error != null) throw error;
    return sealed;
  }
}

void main() {
  group('review R10: no edits while the save is pending', () {
    testWidgets(
        'reviewer fixture: Tab cannot reach the title, IME edits '
        'nothing', (tester) async {
      final gate = Completer<NoteSaveResult>();
      Note? sent;
      await _open(tester, (snapshot) {
        sent = snapshot;
        return gate.future;
      });
      await tester.tap(find.text('Done'));
      await tester.pump();
      var focused = false;
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (_field(tester).focusNode!.hasFocus) {
          focused = true;
          break;
        }
      }
      expect(focused, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(_field(tester).readOnly, isTrue);
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      expect(sent!.title, 'Submitted title');
      expect(find.byType(NotesCreaterPage), findsNothing);
    });

    testWidgets(
        'a focused field loses focus at Done and gets it back after '
        'Edit', (tester) async {
      final gate = Completer<NoteSaveResult>();
      await _open(tester, (_) => gate.future);
      await tester.tap(_title);
      await tester.pump();
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(_field(tester).focusNode!.hasFocus, isFalse);
      expect(find.text('Saving…'), findsOneWidget);
      gate.complete(NoteSaveFailed(Exception('synthetic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(_field(tester).readOnly, isFalse);
      expect(_field(tester).focusNode!.hasFocus, isTrue,
          reason: 'editing resumes where it was');
      tester.testTextInput.enterText('Edited after failure');
      await tester.pump();
      expect(_field(tester).controller!.text, 'Edited after failure');
    });

    testWidgets('screen-reader actions are disabled while saving',
        (tester) async {
      final handle = tester.ensureSemantics();
      final gate = Completer<NoteSaveResult>();
      await _open(tester, (_) => gate.future);
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(tester.getSemantics(find.byTooltip('Pin note')),
          isSemantics(isEnabled: false, hasEnabledState: true, isButton: true));
      expect(tester.getSemantics(find.byTooltip('Mark important')),
          isSemantics(isEnabled: false, hasEnabledState: true, isButton: true));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
          reason: 'Done is disabled and reads "Saving…"');
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('review R11: completion closes only the editor route', () {
    testWidgets(
        'reviewer fixture: a covering dialog stays; the editor '
        'closes once it is on top again', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results = await _open(tester, (_) => gate.future, nav: nav);
      await tester.tap(find.text('Done'));
      await tester.pump();
      unawaited(showDialog<bool>(
          context: nav.currentContext!,
          builder: (_) =>
              const AlertDialog(title: Text('Independent overlay'))));
      await tester.pumpAndSettle();
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      expect(find.text('Independent overlay'), findsOneWidget);
      expect(find.byType(NotesCreaterPage), findsOneWidget,
          reason: 'waits under the overlay');
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, [true], reason: 'its own result, exactly once');
    });

    testWidgets('a page pushed on top: the editor waits for it',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results = await _open(tester, (_) => gate.future, nav: nav);
      await tester.tap(find.text('Done'));
      await tester.pump();
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')))));
      await tester.pumpAndSettle();
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, [true]);
    });

    testWidgets('a nested navigator: only the editor route closes',
        (tester) async {
      final nested = GlobalKey<NavigatorState>();
      final root = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      tester.view.physicalSize = const Size(1290, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: root,
        home: Scaffold(
          body: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => NotesCreaterPage(
                        note: Note(id: 'draft', title: 'T', body: 'B'),
                        onSave: (_) => gate.future)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pump();
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(find.text('Open'), findsOneWidget,
          reason: 'the nested home route stays');
      expect(root.currentState!.canPop(), isFalse);
    });

    testWidgets('an editor route removed while saving completes nothing',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      await _open(tester, (_) => gate.future, nav: nav);
      await tester.tap(find.text('Done'));
      await tester.pump();
      final editorRoute =
          ModalRoute.of(tester.element(find.byType(NotesCreaterPage)))!;
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')))));
      await tester.pumpAndSettle();
      nav.currentState!.removeRoute(editorRoute);
      await tester.pumpAndSettle();
      gate.complete(const NoteSaveSucceeded());
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('review R14: a retired draft leaves the screen at once', () {
    const retired = NoteSaveRetired(NoteSaveRetirement.contextChanged);
    Note privateNote() => Note(
        id: 'old', title: 'Former account draft title', body: 'Former account draft body');

    /// Nothing of the draft in the widget tree or the semantics tree.
    void expectRedacted(WidgetTester tester) {
      expect(find.text('Former account draft title'), findsNothing);
      expect(find.textContaining('Former account'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(NotesCreaterPage), matching: find.byType(EditableText)),
          findsNothing);
      expect(
          find.semantics.byPredicate((node) {
            final data = node.getSemanticsData();
            return '${data.label} ${data.value} ${data.hint} ${data.tooltip}'
                .contains('Former account');
          }),
          findsNothing);
    }

    testWidgets(
        'reviewer fixture: under a covering dialog the draft is hidden at '
        'once, and the editor closes once after it', (tester) async {
      final handle = tester.ensureSemantics();
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results =
          await _open(tester, (_) => gate.future, nav: nav, note: privateNote());
      await tester.tap(find.text('Done'));
      await tester.pump();
      unawaited(showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(title: Text('New account overlay'))));
      await tester.pumpAndSettle();
      gate.complete(retired);
      await tester.pump(); // the result arrives and schedules a frame
      await tester.pump(); // the next frame already hides the draft
      expectRedacted(tester);
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      await tester.pumpAndSettle();
      expectRedacted(tester);
      expect(find.text('New account overlay'), findsOneWidget,
          reason: 'the covering route stays');
      expect(find.byType(NotesCreaterPage), findsOneWidget,
          reason: 'the close waits under the cover');
      expect(find.text('Retry'), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(results, isEmpty);
      await nav.currentState!.maybePop(); // Back closes the cover
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, [false], reason: 'its own result, exactly once');
      await nav.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(find.text('Open'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('uncovered, it is hidden in the first frame and closes once',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results =
          await _open(tester, (_) => gate.future, nav: nav, note: privateNote());
      await tester.tap(find.text('Done'));
      await tester.pump();
      gate.complete(retired);
      await tester.pump(); // the result arrives and schedules a frame
      await tester.pump(); // the next frame already hides the draft
      expectRedacted(tester);
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, [false]);
    });

    testWidgets('a nested navigator: hidden at once, only the editor closes',
        (tester) async {
      final nested = GlobalKey<NavigatorState>();
      final root = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      tester.view.physicalSize = const Size(1290, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final results = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        navigatorKey: root,
        home: Scaffold(
          body: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => TextButton(
                onPressed: () async => results.add(await showDialog<bool>(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => NotesCreaterPage(
                        note: privateNote(), onSave: (_) => gate.future))),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pump();
      unawaited(showDialog<void>(
          context: nested.currentContext!,
          useRootNavigator: false,
          builder: (_) => const AlertDialog(title: Text('Nested cover'))));
      await tester.pumpAndSettle();
      gate.complete(retired);
      await tester.pump(); // the result arrives and schedules a frame
      await tester.pump(); // the next frame already hides the draft
      expectRedacted(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nested cover'), findsOneWidget);
      nested.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(find.text('Open'), findsOneWidget,
          reason: 'the nested home route stays');
      expect(results, [false]);
      expect(root.currentState!.canPop(), isFalse);
    });

    testWidgets('an editor route removed while retired completes nothing',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results =
          await _open(tester, (_) => gate.future, nav: nav, note: privateNote());
      await tester.tap(find.text('Done'));
      await tester.pump();
      final editorRoute =
          ModalRoute.of(tester.element(find.byType(NotesCreaterPage)))!;
      unawaited(showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Another page'))));
      await tester.pumpAndSettle();
      gate.complete(retired);
      await tester.pump(); // the result arrives and schedules a frame
      await tester.pump(); // the next frame already hides the draft
      expectRedacted(tester);
      nav.currentState!.removeRoute(editorRoute);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Another page'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, isNot(contains(false)),
          reason: 'a removed route has nothing left to complete');
    });

    testWidgets('an editor route replaced while retired completes nothing',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<NoteSaveResult>();
      final results =
          await _open(tester, (_) => gate.future, nav: nav, note: privateNote());
      await tester.tap(find.text('Done'));
      await tester.pump();
      final editorRoute =
          ModalRoute.of(tester.element(find.byType(NotesCreaterPage)))!;
      unawaited(showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Cover'))));
      await tester.pumpAndSettle();
      gate.complete(retired);
      await tester.pump(); // the result arrives and schedules a frame
      await tester.pump(); // the next frame already hides the draft
      expectRedacted(tester);
      nav.currentState!.replace(
          oldRoute: editorRoute,
          newRoute: MaterialPageRoute<bool>(
              builder: (_) => const Scaffold(body: Text('Replacement'))));
      await tester.pumpAndSettle();
      nav.currentState!.pop(); // the cover
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Replacement'), findsOneWidget,
          reason: 'the completion never pops another route');
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(results, isNot(contains(false)));
    });
  });

  group('review R16: a failed seal for a changed context, end to end', () {
    // The real repository and NotesBloc on in-memory Hive boxes, so the
    // editor sees the outcome the repository actually returns. In-memory
    // boxes keep every future in the widget test's fake-async zone.
    late TestApi api;
    late _SealFailingVault vault;
    late NotesRepository repository;
    late NotesBloc bloc;

    /// Waits for [future] by pumping frames (bounded), as fake async needs.
    Future<void> drive(WidgetTester tester, Future<void> future) async {
      var done = false;
      unawaited(future.whenComplete(() => done = true));
      for (var i = 0; i < 100 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done, isTrue);
    }

    Future<void> openStore(WidgetTester tester) async {
      final box = await Hive.openBox('r16-editor-notes', bytes: Uint8List(0));
      SyncStatusHelper.syncBox =
          await Hive.openBox<bool>('r16-editor-sync', bytes: Uint8List(0));
      api = TestApi();
      vault = _SealFailingVault()..unlocked = true;
      repository = NotesRepository.forTest(
          box: box,
          api: api,
          vault: vault,
          checkConnectivity: () async => [ConnectivityResult.wifi]);
      await repository.start();
      bloc = NotesBloc(
          source: repository,
          isSyncEnabled: () => false,
          isOnline: () async => true);
    }

    Future<void> closeStore(WidgetTester tester) async {
      final gate = vault.sealGate;
      if (gate != null && !gate.isCompleted) gate.complete();
      await tester.runAsync(bloc.close); // completes only on the real event loop
      await drive(tester, repository.stop(waitForSync: true));
      repository.dispose();
      await drive(tester, Hive.close());
    }

    /// The editor's save goes through the bloc with a context captured now.
    Future<NoteSaveResult> Function(Note) ownedSave() {
      final context = bloc.captureEditorContext()!;
      return (note) {
        final ack = NoteSaveAck();
        bloc.add(NoteSaved(note, ack: ack, context: context));
        return ack.result;
      };
    }

    Future<void> waitForSeal(WidgetTester tester) async {
      for (var i = 0; i < 20 && !vault.sealEntered!.isCompleted; i++) {
        await tester.pump();
      }
      expect(vault.sealEntered!.isCompleted, isTrue);
    }

    Note privateNote() => Note(
        id: 'old', title: 'Former account draft title', body: 'Former account draft body');

    testWidgets(
        'a session change and a failed seal hide the draft under a cover; '
        'the editor closes once after it', (tester) async {
      final handle = tester.ensureSemantics();
      await openStore(tester);
      try {
        vault
          ..sealGate = Completer<void>()
          ..sealEntered = Completer<void>();
        final nav = GlobalKey<NavigatorState>();
        final results =
            await _open(tester, ownedSave(), nav: nav, note: privateNote());
        await tester.tap(find.text('Done'));
        await waitForSeal(tester);
        unawaited(showDialog<void>(
            context: nav.currentContext!,
            builder: (_) => const AlertDialog(title: Text('New account overlay'))));
        await tester.pumpAndSettle();
        api.user = 'user-b';
        api.sessionRevision++;
        vault.failureAfterSeal = StateError('synthetic seal failure');
        vault.sealGate!.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        expect(find.textContaining('Former account'), findsNothing);
        expect(
            find.semantics.byPredicate((node) {
              final data = node.getSemanticsData();
              return '${data.label} ${data.value} ${data.hint} ${data.tooltip}'
                  .contains('Former account');
            }),
            findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('New account overlay'), findsOneWidget);
        expect(find.byType(NotesCreaterPage), findsOneWidget);
        expect(results, isEmpty);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(NotesCreaterPage), findsNothing);
        expect(results, [false], reason: 'its own result, exactly once');
      } finally {
        await closeStore(tester);
        handle.dispose();
      }
    });

    testWidgets('the same context and a failed seal keep the draft and offer Retry',
        (tester) async {
      await openStore(tester);
      try {
        vault
          ..sealGate = Completer<void>()
          ..sealEntered = Completer<void>();
        final results = await _open(tester, ownedSave(), note: privateNote());
        await tester.tap(find.text('Done'));
        await waitForSeal(tester);
        vault.failureAfterSeal = StateError('synthetic seal failure');
        vault.sealGate!.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Former account draft title'), findsOneWidget,
            reason: 'a genuine failure keeps the draft');
        expect(find.byType(NotesCreaterPage), findsOneWidget);
        expect(results, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  });
}
