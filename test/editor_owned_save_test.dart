// S1 / review R10–R11: while its own save is pending the editor accepts no
// edits from any input, and the save's completion closes only the editor's
// own route. The first case in each group is the reviewer fixture
// (review-evidence/2026-11-12-packet-3/reviewer_s1_edges_test.dart).

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
