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
        'mixed order and discriminator survive Hive and sync sealing ($encrypted)',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('atomic-mixed-note-');
      Hive.init(directory.path);
      final box = await Hive.openBox('mixed-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>('mixed-sync');
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
        final resolved = directory.absolute.path;
        final parent = Directory.systemTemp.absolute.path;
        if (!resolved.startsWith('$parent${Platform.pathSeparator}') ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('atomic-mixed-note-')) {
          throw StateError('owned_cleanup_refused');
        }
        await directory.delete(recursive: true);
      });
      await repository.start();
      final original = Note.create()
        ..body = 'Context\nConclusion'
        ..important = true;
      final document = NoteDocument.fromNote(original);
      document.insertChecklistAfter(0, caretOffset: 2);
      document.replaceText(1, 'Task');
      document.setDone(1, true);
      final note = document.toNote(original);
      await repository.save(note);
      expect(repository.visible(filter: NoteFilter.todos).map((n) => n.id),
          [note.id]);
      final rawCache = Map<dynamic, dynamic>.from(box.get(note.id) as Map);
      final cachedContent = encrypted
          ? await vault.decryptContent(rawCache['payload'] as String)
          : rawCache;
      final cached = Note.fromMap({...rawCache, ...cachedContent});
      expect(cached.body, note.body);
      expect(cached.important, isTrue);
      expect(NoteDocument.isEncoded(cached), isTrue);
      expect(await repository.syncNow(instant: true), isTrue);
      final row = api.pushes
          .expand((rows) => rows)
          .firstWhere((r) => r['id'] == note.id);
      final content = encrypted
          ? await vault.decryptContent(row['payload'] as String)
          : row;
      expect(row['important'], isTrue);
      if (encrypted) {
        expect(row['body'], isEmpty);
        expect(row['items'], isEmpty);
      }
      final pulled = Note.fromRemote({...row, ...content, 'version': 1});
      final restored = NoteDocument.fromNote(pulled);
      expect(pulled.important, isTrue);
      expect(NoteDocument.isEncoded(pulled), isTrue);
      expect(restored.lines.map((line) => line.text),
          ['Context', 'Task', 'Conclusion']);
      expect(restored.lines[1].done, isTrue);
    });
  }
}
