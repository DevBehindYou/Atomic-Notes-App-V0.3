import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

// UX-04-route: Home opens the editor as one full-screen route that grows from
// the tapped card (or the new-note button) and returns into it.

FakeNotesSource _three() => FakeNotesSource(
      notes: [
        syncedNote('a',
            title: 'Groceries', createdAt: DateTime.utc(2026, 9, 3)),
        syncedNote('b',
            title: 'Ideas',
            body: 'Build a rocket',
            createdAt: DateTime.utc(2026, 9, 2)),
        syncedNote('c', title: 'Trip', createdAt: DateTime.utc(2026, 9, 1)),
      ],
    );

Future<NotesBloc> _home(WidgetTester tester, FakeNotesSource source,
    {bool disableAnimations = false}) async {
  tester.view.physicalSize = const Size(400, 860) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    source.dispose();
  });
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.light,
    // The platform preference still reaches the app, so it can change live.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations:
              disableAnimations || MediaQuery.disableAnimationsOf(context)),
      child: child!,
    ),
    home: BlocProvider<NotesBloc>.value(
      value: bloc,
      child: const HomePage(),
    ),
  ));
  await tester.pumpAndSettle();
  // Let the welcome collapse.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  return bloc;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

final _editor = find.byType(NotesCreaterPage);
final _title = find.byKey(const ValueKey('note-title'));

ModalRoute<Object?> _editorRoute(WidgetTester tester) =>
    // A page route is offstage for its first frame while heroes measure.
    ModalRoute.of(
        tester.element(find.byType(NotesCreaterPage, skipOffstage: false)))!;

void main() {
  testWidgets('a double tap on a card opens exactly one editor',
      (tester) async {
    final source = _three();
    await _home(tester, source);
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.tap(find.byKey(const ValueKey('b')), warnIfMissed: false);
    await _settle(tester);
    expect(_editor, findsOneWidget);
    await _back(tester);
    expect(_editor, findsNothing);
    // Nothing left behind: a fresh tap opens one editor again.
    await tester.tap(find.byKey(const ValueKey('c')));
    await _settle(tester);
    expect(_editor, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two taps on different cards in one frame open one editor',
      (tester) async {
    final source = _three();
    await _home(tester, source);
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.tap(find.byKey(const ValueKey('c')), warnIfMissed: false);
    await _settle(tester);
    expect(_editor, findsOneWidget);
    expect(find.descendant(of: _editor, matching: find.text('Ideas')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two card activations in one frame without a pointer (keyboard or '
      'accessibility) open one editor', (tester) async {
    final source = _three();
    await _home(tester, source);
    // No pointer for the navigator to cancel: the call site itself must hold.
    void activate(String id) =>
        tester.widget<NotesBulder>(find.byKey(ValueKey(id))).onTap();
    activate('b');
    activate('c');
    await _settle(tester);
    expect(find.byType(NotesCreaterPage, skipOffstage: false), findsOneWidget);
    expect(find.descendant(of: _editor, matching: find.text('Ideas')),
        findsOneWidget);
    await _back(tester);
    expect(find.byType(NotesCreaterPage, skipOffstage: false), findsNothing);
    // Released on close: the next action opens again.
    activate('c');
    await _settle(tester);
    expect(find.descendant(of: _editor, matching: find.text('Trip')),
        findsOneWidget);
    await _back(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on another card while the editor grows opens nothing',
      (tester) async {
    final source = _three();
    await _home(tester, source);
    final other = tester.getCenter(find.byKey(const ValueKey('c')));
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(other);
    await _settle(tester);
    expect(find.byType(NotesCreaterPage, skipOffstage: false), findsOneWidget);
    expect(find.descendant(of: _editor, matching: find.text('Ideas')),
        findsOneWidget);
    await _back(tester);
    expect(_editor, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a double tap on the new-note button opens one editor',
      (tester) async {
    final source = _three();
    await _home(tester, source);
    final fab = find.byKey(const ValueKey('home-new-note'));
    await tester.tap(fab);
    await tester.tap(fab, warnIfMissed: false);
    await _settle(tester);
    expect(_editor, findsOneWidget);
    await _back(tester);
    expect(_editor, findsNothing);
    expect(source.saveCalls, 0, reason: 'An empty new note is not stored.');
  });

  group('result delivery', () {
    testWidgets('Done stores the edited draft once and returns to Home',
        (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      await tester.enterText(_title, 'Ideas, revised');
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(source.saveCalls, 1);
      expect(source.byId('b')!.title, 'Ideas, revised');
      expect(bloc.state.notes.firstWhere((n) => n.id == 'b').title,
          'Ideas, revised');
    });

    testWidgets('Back on an unchanged draft closes without saving',
        (tester) async {
      final source = _three();
      await _home(tester, source);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      await _back(tester);
      expect(_editor, findsNothing);
      expect(source.saveCalls, 0);
      expect(find.byKey(const ValueKey('b')), findsOneWidget);
    });

    testWidgets(
        'Back on a changed draft asks; Keep editing stays, Discard '
        'closes without saving', (tester) async {
      final source = _three();
      await _home(tester, source);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      await tester.enterText(_title, 'Not kept');
      await _back(tester);
      expect(find.text('Save your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _settle(tester);
      expect(_editor, findsOneWidget);
      expect(tester.widget<TextField>(_title).controller!.text, 'Not kept');
      await _back(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(source.saveCalls, 0);
      expect(source.byId('b')!.title, 'Ideas');
    });

    testWidgets('Back on a changed draft, then Save, stores it',
        (tester) async {
      final source = _three();
      await _home(tester, source);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      await tester.enterText(_title, 'Kept');
      await _back(tester);
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(source.saveCalls, 1);
      expect(source.byId('b')!.title, 'Kept');
    });
  });

  testWidgets('the search query, field and its focus survive the editor',
      (tester) async {
    final source = _three();
    final bloc = await _home(tester, source);
    await tester.tap(find.byTooltip('Search notes'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'rocket');
    await _settle(tester);
    final search = tester.state<EditableTextState>(find.byType(EditableText));
    expect(search.widget.focusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('b')));
    await _settle(tester);
    expect(_editor, findsOneWidget);
    expect(search.widget.focusNode.hasFocus, isFalse,
        reason: 'The editor takes focus from the search field.');
    await _back(tester);
    expect(_editor, findsNothing);
    expect(bloc.state.query, 'rocket');
    expect(search.mounted, isTrue);
    expect(search.widget.controller.text, 'rocket');
    expect(search.widget.focusNode.hasFocus, isTrue,
        reason: 'Focus (and so the keyboard) returns to the search field.');
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
  });

  group('transition', () {
    testWidgets('the editor is a full-screen page route of 350 ms',
        (tester) async {
      await _home(tester, _three());
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      final route = _editorRoute(tester);
      expect(route, isA<PageRoute<Object?>>());
      expect(route.opaque, isTrue);
      expect(route.transitionDuration, const Duration(milliseconds: 350));
      expect(
          route.reverseTransitionDuration, const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation!.status, AnimationStatus.forward);
      await tester.pump(const Duration(milliseconds: 260));
      expect(route.animation!.status, AnimationStatus.completed);
      await _settle(tester);
    });

    testWidgets('open grows from the tapped card; content fades in late',
        (tester) async {
      await _home(tester, _three());
      final card = tester.getRect(find.byKey(const ValueKey('b')));
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final clip = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      final early = clip.clipper!.getClip(clip.size);
      expect(early.outerRect.width, lessThan(card.width + 4));
      expect(early.outerRect.center.dx, closeTo(card.center.dx, 4));
      final content = tester
          .widget<Opacity>(find.byKey(const ValueKey('editor-route-content')));
      expect(content.opacity, 0, reason: 'Content waits for the last 60%.');
      await _settle(tester);
      final settled = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      expect(settled.clipper!.getClip(settled.size).outerRect,
          Offset.zero & settled.size);
      expect(
          tester
              .widget<Opacity>(
                  find.byKey(const ValueKey('editor-route-content')))
              .opacity,
          1);
    });

    testWidgets('close returns into the card when it is still there',
        (tester) async {
      await _home(tester, _three());
      final card = tester.getRect(find.byKey(const ValueKey('b')));
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 349));
      final clip = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      final late = clip.clipper!.getClip(clip.size).outerRect;
      expect(late.width, lessThan(card.width + 8));
      expect(late.center.dx, closeTo(card.center.dx, 8));
      await _settle(tester);
      expect(_editor, findsNothing);
    });

    testWidgets('close fades out when the card has gone', (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      // The note is deleted behind the editor (another device, say).
      bloc.add(const NoteDeleted('b'));
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final clip = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      expect(
          clip.clipper!.getClip(clip.size).outerRect, Offset.zero & clip.size,
          reason: 'No card to return to: a plain fade.');
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the new-note button is the origin of a new note',
        (tester) async {
      await _home(tester, _three());
      final fab = find.byKey(const ValueKey('home-new-note'));
      final origin = tester.getRect(fab);
      await tester.tap(fab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final clip = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      final early = clip.clipper!.getClip(clip.size);
      expect(early.outerRect.center.dx, closeTo(origin.center.dx, 6));
      expect(early.outerRect.center.dy, closeTo(origin.center.dy, 6));
      await _settle(tester);
    });
  });

  testWidgets('reduced motion: the route opens and closes without waiting',
      (tester) async {
    final source = _three();
    await _home(tester, source, disableAnimations: true);
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();
    expect(_editor, findsOneWidget);
    final route = _editorRoute(tester);
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.binding.handlePopRoute();
    // One frame runs the editor's close, the next removes the route.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(_editor, findsNothing);
    expect(source.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  group('reduced motion changing while the editor is shown (R41)', () {
    void setReduced(WidgetTester tester, bool on) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: on);
    }

    void clearOnTearDown(WidgetTester tester) => addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    Rect clipRect(WidgetTester tester) {
      final clip = tester.renderObject<RenderClipRRect>(
          find.byKey(const ValueKey('editor-route-clip')));
      return clip.clipper!.getClip(clip.size).outerRect;
    }

    double contentOpacity(WidgetTester tester) => tester
        .widget<Opacity>(find.byKey(const ValueKey('editor-route-content')))
        .opacity;

    testWidgets(
        'review: enabling reduced motion while editor is open also '
        'disables the exit transform', (tester) async {
      await _home(tester, _three());
      clearOnTearDown(tester);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      final route = _editorRoute(tester);
      setReduced(tester, true);
      await tester.pump();
      expect(MediaQuery.disableAnimationsOf(tester.element(_editor)), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(route.animation!.status, AnimationStatus.dismissed,
          reason: 'the platform preference changed before closing the editor');
      await tester.pump();
      expect(_editor, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'turned on while the editor grows: the open finishes at once and '
        'Done still stores the draft once', (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      clearOnTearDown(tester);
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final route = _editorRoute(tester);
      expect(route.animation!.status, AnimationStatus.forward);
      expect(route.animation!.value, lessThan(1));
      setReduced(tester, true);
      await tester.pump();
      expect(route.animation!.status, AnimationStatus.completed,
          reason: 'A running entrance ends when reduced motion turns on.');
      await tester.pump();
      expect(clipRect(tester), Offset.zero & tester.view.physicalSize / 3);
      expect(contentOpacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
      // The editor works as usual.
      await tester.enterText(_title, 'Ideas, revised');
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_editor, findsNothing);
      expect(source.saveCalls, 1);
      expect(source.byId('b')!.title, 'Ideas, revised');
      expect(bloc.state.notes.firstWhere((n) => n.id == 'b').title,
          'Ideas, revised');
      expect(tester.takeException(), isNull);
    });

    testWidgets('turned on while the editor closes: the close finishes at once',
        (tester) async {
      final source = _three();
      await _home(tester, source);
      clearOnTearDown(tester);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      final route = _editorRoute(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation!.status, AnimationStatus.reverse);
      expect(route.animation!.value, greaterThan(0));
      setReduced(tester, true);
      await tester.pump();
      expect(route.animation!.status, AnimationStatus.dismissed,
          reason: 'A running exit ends when reduced motion turns on.');
      await tester.pump();
      expect(_editor, findsNothing);
      expect(source.saveCalls, 0);
      expect(find.byKey(const ValueKey('b')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'turned on while Done closes the editor: the draft is stored once',
        (tester) async {
      final source = _three();
      await _home(tester, source);
      clearOnTearDown(tester);
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      final route = _editorRoute(tester);
      await tester.enterText(_title, 'Kept');
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation!.status, AnimationStatus.reverse);
      setReduced(tester, true);
      await tester.pump();
      expect(route.animation!.status, AnimationStatus.dismissed);
      await tester.pump();
      expect(_editor, findsNothing);
      expect(source.saveCalls, 1);
      expect(source.byId('b')!.title, 'Kept');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'turned on while the editor closes: search text and focus come back',
        (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      clearOnTearDown(tester);
      await tester.tap(find.byTooltip('Search notes'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      final search = tester.state<EditableTextState>(find.byType(EditableText));
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      expect(search.widget.focusNode.hasFocus, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      setReduced(tester, true);
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(bloc.state.query, 'rocket');
      expect(search.mounted, isTrue);
      expect(search.widget.controller.text, 'rocket');
      expect(search.widget.focusNode.hasFocus, isTrue,
          reason: 'Focus (and so the keyboard) returns to the search field.');
    });

    testWidgets(
        'turned on while the editor is fully open: Back is instant and the '
        'search field gets its focus back', (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      clearOnTearDown(tester);
      await tester.tap(find.byTooltip('Search notes'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      final search = tester.state<EditableTextState>(find.byType(EditableText));
      await tester.tap(find.byKey(const ValueKey('b')));
      await _settle(tester);
      final route = _editorRoute(tester);
      setReduced(tester, true);
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(route.animation!.status, AnimationStatus.dismissed);
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(source.saveCalls, 0);
      expect(bloc.state.query, 'rocket');
      expect(search.mounted, isTrue,
          reason: 'The field keeps its element across the preference change.');
      expect(search.widget.focusNode.hasFocus, isTrue,
          reason: 'Focus (and so the keyboard) returns to the search field.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('turned off while the editor is open: the close moves again',
        (tester) async {
      await _home(tester, _three());
      clearOnTearDown(tester);
      setReduced(tester, true);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      final route = _editorRoute(tester);
      expect(route.animation!.status, AnimationStatus.completed,
          reason: 'Opened under reduced motion: no entrance.');
      await _settle(tester);
      setReduced(tester, false);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation!.status, AnimationStatus.reverse,
          reason: 'The close uses the preference as it is now.');
      await _settle(tester);
      expect(_editor, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a later open uses the preference as it is then',
        (tester) async {
      await _home(tester, _three());
      clearOnTearDown(tester);
      setReduced(tester, true);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      expect(_editorRoute(tester).animation!.status, AnimationStatus.completed);
      await _back(tester);
      expect(_editor, findsNothing);
      setReduced(tester, false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('c')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final route = _editorRoute(tester);
      expect(route.animation!.status, AnimationStatus.forward);
      expect(route.transitionDuration, const Duration(milliseconds: 350));
      await _settle(tester);
      await _back(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
