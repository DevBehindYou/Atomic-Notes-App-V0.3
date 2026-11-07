import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/recovery/recovery_page.dart';
import 'package:atomic_notes/recovery/restore_coordinator.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 8, 9);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);
String _id(String c) => '${c * 8}-${c * 4}-4${c * 3}-8${c * 3}-${c * 12}';
Note _note(String c, String title) =>
    Note(id: _id(c), title: title, createdAt: _time, updatedAt: _time);

ArchiveKey _key() {
  final random = Random(3);
  return ArchiveKey.forTesting(
      SecretKey(List<int>.generate(32, (_) => random.nextInt(256))),
      List<int>.generate(16, (_) => random.nextInt(256)));
}

class _Target implements ExportTarget {
  _Target({this.failOnWrite = false, this.gate});
  final bool failOnWrite;
  final Completer<void>? gate;
  final _bytes = BytesBuilder();
  Uint8List? committed;
  bool aborted = false;
  @override
  Future<void> open() async {}
  @override
  Future<void> write(List<int> bytes) async {
    if (failOnWrite) throw const FileSystemExceptionLike();
    await gate?.future;
    _bytes.add(bytes);
  }

  @override
  Future<void> commit() async => committed = _bytes.toBytes();
  @override
  Future<void> abort() async => aborted = true;
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike();
}

class _Store implements RestoreStore {
  _Store(this.target);
  final Map<String, Map<String, Object?>> target;
  Map<String, Object?>? marker;
  final staging = <String, Map<String, Map<String, Object?>>>{};
  final backups = <String, Map<String, Map<String, Object?>?>>{};
  @override
  Future<Map<String, Object?>?> current(String id) async => target[id];
  @override
  Future<RestoreMarker?> readMarker() async =>
      marker == null ? null : RestoreMarker.fromJson(marker!);
  @override
  Future<void> writeMarker(RestoreMarker m) async => marker = m.toJson();
  @override
  Future<void> clearMarker() async => marker = null;
  @override
  Future<void> stage(String op, String id, Map<String, Object?> r) async =>
      (staging[op] ??= {})[id] = r;
  @override
  Future<Map<String, Object?>?> staged(String op, String id) async =>
      staging[op]?[id];
  @override
  Future<void> discardStaged(String op) async => staging.remove(op);
  @override
  Future<bool> hasBackup(String op, String id) async =>
      backups[op]?.containsKey(id) ?? false;
  @override
  Future<void> backup(String op, String id, Map<String, Object?>? p) async =>
      (backups[op] ??= {})[id] = p;
  @override
  Future<void> put(String id, Map<String, Object?> r) async => target[id] = r;
}

class _Ports implements RecoveryPorts, LocalNotesView {
  _Ports({this.target});
  final store = _Store({
    _id('a'): _note('a', 'Device A').toMap(),
    _id('b'): _note('b', 'Device B').toMap(),
  });
  ExportTarget Function()? target;
  final targets = <_Target>[];
  ArchiveByteSource Function()? archive;
  BackupRecord? last;
  int recorded = 0;

  @override
  int get savedLocally => store.target.length;
  @override
  String? get cloudStatus => null;
  @override
  BackupRecord? get lastBackup => last;
  @override
  Future<void> recordBackup(BackupRecord record) async {
    recorded++;
    last = record;
  }

  @override
  Future<List<ArchiveSource>> snapshot() async => [
        for (final value in store.target.values)
          ArchiveSource(Note.fromMap(value))
      ];
  @override
  ArchiveVault? get vault => _vault;
  @override
  ExportTarget newExportTarget() {
    final made = target?.call() ?? _Target();
    if (made is _Target) targets.add(made);
    return made;
  }

  @override
  Future<ArchiveByteSource Function()?> pickArchive() async => archive;
  @override
  LocalNotesView get local => this;
  @override
  RestoreStore get restoreStore => store;
  @override
  Note? byId(String id) {
    final value = store.target[id];
    return value == null ? null : Note.fromMap(value);
  }
}

Future<Uint8List> _archive(List<Note> notes, {ArchiveKey? key}) async {
  final target = _Target();
  await ExportWriter(clock: () => _time).write(
      target, [for (final n in notes) ArchiveSource(n)],
      key: key, vault: _vault);
  return target.committed!;
}

Future<void> _open(WidgetTester tester, _Ports ports,
    {bool enabled = true}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: RecoveryPage(
          ports: ports,
          enabled: enabled,
          deriveKey: (_) async => _key(),
          openKey: (_, __) async => _key())));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  testWidgets('behind its feature gate the page offers nothing',
      (tester) async {
    expect(RecoveryFeature.enabled, isFalse, reason: 'off in default builds');
    await _open(tester, _Ports(), enabled: false);
    expect(find.byKey(const ValueKey('recovery-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-export')), findsNothing);
    expect(find.byKey(const ValueKey('recovery-open')), findsNothing);
  });

  testWidgets('saved locally, cloud and backup are separate facts',
      (tester) async {
    await _open(tester, _Ports());
    expect(_text(tester, 'recovery-local'), '2 notes saved on this device');
    expect(_text(tester, 'recovery-cloud'), 'Cloud sync status unknown');
    expect(
        _text(tester, 'recovery-backup'), 'No backup made on this device yet');
  });

  testWidgets('a finished backup is recorded, with progress', (tester) async {
    final ports = _Ports();
    await _open(tester, ports);
    await tester.enterText(
        find.byKey(const ValueKey('recovery-password')), 'pw');
    await tester.tap(find.byKey(const ValueKey('recovery-export')));
    await _settle(tester);
    expect(ports.recorded, 1);
    expect(ports.last!.notes, 2);
    expect(ports.last!.encrypted, isTrue);
    expect(_text(tester, 'recovery-message'), 'Backup saved: 2 notes.');
    expect(
        _text(tester, 'recovery-backup'), startsWith('Last backup: 2 notes'));
    expect(ports.targets.single.committed, isNotNull);
  });

  testWidgets('a failed backup never marks a backup as made', (tester) async {
    final ports = _Ports(target: () => _Target(failOnWrite: true));
    await _open(tester, ports);
    await tester.tap(find.byKey(const ValueKey('recovery-export')));
    await _settle(tester);
    expect(ports.recorded, 0);
    expect(ports.targets.single.aborted, isTrue);
    expect(_text(tester, 'recovery-message'),
        'The export could not be written. Your notes are unchanged.');
    expect(
        _text(tester, 'recovery-backup'), 'No backup made on this device yet');
  });

  testWidgets('a cancelled backup never marks a backup as made',
      (tester) async {
    final gate = Completer<void>();
    final ports = _Ports(target: () => _Target(gate: gate));
    await _open(tester, ports);
    await tester.tap(find.byKey(const ValueKey('recovery-export')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('recovery-progress')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recovery-cancel')));
    gate.complete();
    await _settle(tester);
    expect(ports.recorded, 0);
    expect(ports.targets.single.committed, isNull);
    expect(_text(tester, 'recovery-message'), contains('Backup cancelled'));
  });

  testWidgets('restore needs every conflict chosen, then reports the result',
      (tester) async {
    final ports = _Ports();
    final bytes = await tester.runAsync(() => _archive(
        [_note('a', 'Device A'), _note('b', 'Backup B'), _note('e', 'New E')]));
    ports.archive = () => ArchiveByteSource.bytes(bytes!);
    await _open(tester, ports);
    await tester.tap(find.byKey(const ValueKey('recovery-open')));
    await _settle(tester);
    final restore = find.byKey(const ValueKey('import-preview-restore'));
    await tester.ensureVisible(restore);
    expect(tester.widget<FilledButton>(restore).onPressed, isNull,
        reason: 'the differing note has no choice yet');
    expect(find.textContaining('Device B'), findsNothing,
        reason: 'the preview shows no note content');
    final choice = find.byKey(ValueKey('recovery-choice-${_id('b')}'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await _settle(tester);
    expect(_text(tester, 'recovery-message'),
        'Restored 2 notes. 0 kept as they were on this device.');
    expect(ports.store.target[_id('b')]!['title'], 'Backup B');
    expect(ports.store.target[_id('e')]!['title'], 'New E');
    expect(ports.store.backups.values.single[_id('b')]!['title'], 'Device B');
  });

  testWidgets('a protected backup stays locked until its password is given',
      (tester) async {
    final ports = _Ports();
    final bytes = await tester
        .runAsync(() => _archive([_note('e', 'New E')], key: _key()));
    ports.archive = () => ArchiveByteSource.bytes(bytes!);
    await _open(tester, ports);
    await tester.tap(find.byKey(const ValueKey('recovery-open')));
    await _settle(tester);
    expect(find.textContaining('export password'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('recovery-password')), 'pw');
    final unlock = find.byKey(const ValueKey('recovery-unlock'));
    await tester.ensureVisible(unlock);
    await tester.tap(unlock);
    await _settle(tester);
    expect(find.text('1 note'), findsOneWidget);
  });
}
