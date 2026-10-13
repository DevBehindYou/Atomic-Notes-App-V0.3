// Screenshots contain only the synthetic records below, never account data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/app_theme.dart';
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
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in ['BebasNeue', 'HankenGrotesk', 'JetBrainsMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  for (final scene in ['home', 'text', 'checklist']) {
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
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: RepaintBoundary(key: key, child: child!),
          ),
          home: scene == 'home'
              ? BlocProvider<NotesBloc>.value(
                  value: bloc,
                  child: const HomePage(),
                )
              : NotesCreaterPage(note: scene == 'text' ? featured : checklist),
        ),
      );
      await tester.pumpAndSettle();
      if (scene == 'home') {
        final image = tester.widget<Image>(find.byType(Image));
        await tester.runAsync(
          () => precacheImage(image.image, key.currentContext!),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
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
