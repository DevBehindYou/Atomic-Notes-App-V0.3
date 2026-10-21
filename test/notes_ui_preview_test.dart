// Screenshots contain only the synthetic records below, never account data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/utility/component/cloud_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['BebasNeue', 'HankenGrotesk', 'JetBrainsMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf')))
          .load();
    }
  });

  for (final scene in [
    'home',
    'text',
    'checklist',
    'home-collapsed',
    'cloud-busy',
  ]) {
    testWidgets('preview_$scene', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final featured = Note(
        id: 'synthetic-pinned',
        title: 'Morning pages: slow start',
        body:
            'Woke before the alarm. Tea first, phone later.\nThree things to protect today.',
        pinned: true,
        updatedAt: DateTime(2026, 10, 12, 7, 10),
      );
      final checklist = Note(
        id: 'synthetic-checklist',
        title: 'Grocery run',
        kind: NoteKind.todo,
        items: [
          TodoItem(text: 'Lemons', done: true),
          TodoItem(text: 'Sourdough', done: true),
          TodoItem(text: 'Basil'),
        ],
        updatedAt: DateTime(2026, 10, 11),
      );
      final source = FakeNotesSource(
        notes: [
          featured,
          checklist,
          Note(
            id: 'synthetic-call',
            title: 'Q4 planning call',
            body: 'Ship offline search first. Sync conflicts after.',
          ),
          Note(
            id: 'synthetic-book',
            title: 'Book notes: chapter 4',
            body: 'Attention is a budget. Spend it on purpose.',
          ),
          Note(
            id: 'synthetic-weekend',
            title: 'Weekend, gently',
            body: 'Family, walking, reading.',
          ),
        ],
      );
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
      final homeScene = scene.startsWith('home') || scene == 'cloud-busy';
      Widget notesHome() => BlocProvider<NotesBloc>.value(
            value: bloc,
            child: HomePage(now: () => DateTime(2026, 10, 14, 20)),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: RepaintBoundary(key: key, child: child!),
          ),
          home: homeScene
              ? (scene == 'cloud-busy'
                  ? Scaffold(
                      backgroundColor: AppColors.paper,
                      appBar: AppBar(
                        backgroundColor: AppColors.paper,
                        title: const Text('Atomic Notes'),
                        actions: [
                          CloudButton(
                            ico: 'assets/sync.svg',
                            action: () {},
                            onLongPress: () {},
                            clr: 0,
                            isLoading: true,
                          ),
                          const SizedBox(width: AppSpace.md),
                        ],
                      ),
                      body: notesHome(),
                    )
                  : notesHome())
              : NotesCreaterPage(note: scene == 'text' ? featured : checklist),
        ),
      );
      await tester.pumpAndSettle();
      if (homeScene) {
        final artwork = find.descendant(
          of: find.byKey(const ValueKey('mascot-character')),
          matching: find.byType(RawImage),
        );
        // Native codec work must run outside the test's fake async clock.
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          if (artwork
              .evaluate()
              .any((element) => (element.widget as RawImage).image != null)) {
            break;
          }
        }
        expect(tester.widget<RawImage>(artwork).image, isNotNull);
      }
      if (scene == 'home-collapsed') {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('notes-welcome-section')))
              .height,
          0,
        );
      }
      if (scene == 'cloud-busy') {
        expect(find.byKey(const ValueKey('cloud-sync-ring')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('cloud-button-surface'))),
          const Size(48, 44),
        );
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['ATOMIC_UI_CAPTURE'] == 'true') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('ci-notes-ui-previews');
            await directory.create();
            await File(
              '${directory.path}/$scene.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
