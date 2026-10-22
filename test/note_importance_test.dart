import 'package:atomic_notes/api/sync_envelope.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'notes_editor_page_test.dart' show openEditor;

void main() {
  test('legacy unimportant content signature is unchanged', () {
    expect(Note(id: 'legacy', title: 'Keep', body: 'Body').contentSig,
        '25-5a3b62a1-b1b0d0e4');
  });
  test('importance survives note copy and local and remote reconstruction', () {
    final note = Note.fromMap({...Note.create().toMap(), 'important': true});
    expect(note.toMap()['important'], isTrue);
    expect(note.copy().toMap()['important'], isTrue);
    final remote = note.toRemote('synthetic-owner');
    expect(remote['important'], isTrue);
    expect(Note.fromRemote({...remote, 'version': 1}).toMap()['important'],
        isTrue);
    final cleared = note.copy()..important = false;
    expect(cleared.toRemote('synthetic-owner')['important'], isFalse);
    expect(cleared.toMap().containsKey('important'), isFalse);
  });
  test('important palette keeps text and outlines readable', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    expect(contrast(AppColors.importantTitle, AppColors.importantSurface),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.onImportantSurface, AppColors.importantSurface),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.importantOutline, AppColors.importantSurface),
        greaterThanOrEqualTo(3));
  });
  test('wire rejects a nonboolean importance value', () async {
    await expectLater(
        SyncEnvelope.prepare(
            requestId: '00000000-0000-4000-8000-000000000001',
            mode: SyncEnvelopeMode.standard,
            rows: [
              {...Note.create().toRemote('synthetic-owner'), 'important': 'yes'}
            ]),
        throwsFormatException);
  });
  test('optional importance survives projected ordinary and logout wire',
      () async {
    final row = {
      ...Note.create().toRemote('synthetic-owner'),
      'important': true,
      'enc_v': 0,
      'payload': null
    };
    const request = '00000000-0000-4000-8000-000000000001';
    for (final prepared in [
      await SyncEnvelope.prepare(
          requestId: request, mode: SyncEnvelopeMode.standard, rows: [row]),
      await SyncEnvelope.prepareLogout(
          requestId: request,
          attemptId: '00000000-0000-4000-8000-000000000002',
          rows: [row]),
    ]) {
      expect(prepared.rows.single['important'], isTrue);
    }
  });
  testWidgets('editor important toggle saves only with Done', (tester) async {
    final note = Note.create()..title = 'Important';
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Mark important'));
    await tester.pump();
    expect(note.toMap()['important'], isNot(true));
    expect(find.byTooltip('Unmark important'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.toMap()['important'], isTrue);
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Unmark important'));
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(note.toMap()['important'], isTrue);
  });
  testWidgets('important card uses black surface with readable content',
      (tester) async {
    final note = Note.fromMap({
      ...Note.create().toMap(),
      'important': true,
      'title': 'Important',
      'body': 'Keep this readable'
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NotesBulder(
      note: note,
      selected: false,
      selectionMode: false,
      onTap: () {},
      onLongPress: () {},
      onToggleItem: (_) {},
    ))));
    final card = tester.widget<Container>(find
        .descendant(
            of: find.byType(NotesBulder), matching: find.byType(Container))
        .first);
    expect((card.decoration as BoxDecoration).color, const Color(0xff000000));
    expect(find.text('Keep this readable'), findsOneWidget);
  });
}
