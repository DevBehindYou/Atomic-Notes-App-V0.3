import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final encrypted in [false, true]) {
    test(
        'rich body tags styles images remain one note across Hive and sync ($encrypted)',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('atomic-rich-note-');
      Hive.init(directory.path);
      final box = await Hive.openBox('rich-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>('rich-sync');
      final api = TestApi();
      final vault = TestVault()..unlocked = encrypted;
      final repository = NotesRepository.forTest(
          box: box,
          api: api,
          vault: vault,
          checkConnectivity: () async => [ConnectivityResult.wifi]);
      addTearDown(() async {
        await repository.stop(waitForSync: true);
        repository.dispose();
        await Hive.close();
        final parent = Directory.systemTemp.absolute.path;
        final resolved = directory.absolute.path;
        if (!resolved.startsWith('$parent${Platform.pathSeparator}') ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('atomic-rich-note-')) {
          throw StateError('owned_cleanup_refused');
        }
        await directory.delete(recursive: true);
      });
      await repository.start();
      final original = Note.create()..body = 'Project details';
      final document = NoteDocument.fromNote(original);
      document.setTags(['Release']);
      document
          .replaceStyles(0, [const NoteStyleRun(0, 7, NoteTextStyle.heading)]);
      final task = document.insertChecklistAfter(0);
      document.replaceText(task, 'Ship safely');
      document.setDone(task, true);
      document.insertImageAfter(
          task,
          base64Encode(
              [0xff, 0xd8, 0xff, 0xc0, 0, 8, 8, 0, 1, 0, 1, 1, 0xff, 0xd9]));
      final note = document.toNote(original);
      await repository.save(note);
      expect(repository.visible(filter: NoteFilter.todos).single.id, note.id);
      expect(repository.count, 1);
      final cache = Map<dynamic, dynamic>.from(box.get(note.id) as Map);
      if (encrypted) {
        expect(cache['body'], isEmpty);
        expect(cache['items'], isEmpty);
      }
      final cachedContent = encrypted
          ? await vault.decryptContent(cache['payload'] as String)
          : cache;
      expect(Note.fromMap({...cache, ...cachedContent}).contentSig,
          note.contentSig);
      expect(await repository.syncNow(instant: true), isTrue);
      final row = api.pushes
          .expand((rows) => rows)
          .singleWhere((r) => r['id'] == note.id);
      if (encrypted) {
        expect(row['title'], isEmpty);
        expect(row['body'], isEmpty);
        expect(row['items'], isEmpty);
      }
      final content = encrypted
          ? await vault.decryptContent(row['payload'] as String)
          : row;
      final pulled = Note.fromRemote({...row, ...content, 'version': 1});
      final reopened = NoteDocument.fromNote(pulled);
      expect(reopened.tags, ['Release']);
      expect(reopened.lines.first.styles.single.flags, NoteTextStyle.heading);
      expect(reopened.lines[1].done, isTrue);
      expect(reopened.lines.last.isImage, isTrue);
      expect(pulled.contentSig, note.contentSig);
      expect(pulled.dirty, isFalse);
      // A failed unsupported edit cannot change the current in-memory record.
      final unsupported = note.copy()..body = '{bad';
      await expectLater(repository.save(unsupported), throwsFormatException);
      expect(repository.byId(note.id)!.contentSig, note.contentSig);
    });
  }
}
