import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/recovery/restore_coordinator.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 8, 9);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);

String _id(String letter) =>
    '${letter * 8}-${letter * 4}-4${letter * 3}-8${letter * 3}-${letter * 12}';
final _a = _id('a'), _b = _id('b'), _c = _id('c'), _d = _id('d');
final _e = _id('e'), _f = _id('f');

Note _note(String id, String title) =>
    Note(id: id, title: title, createdAt: _time, updatedAt: _time);

/// Device: A same as archive, B and C differ, D only here.
Map<String, Map<String, Object?>> _device() => {
      _a: _note(_a, 'A').toMap(),
      _b: _note(_b, 'B on device').toMap(),
      _c: _note(_c, 'C on device').toMap(),
      _d: _note(_d, 'D only here').toMap(),
    };

/// Archive: A, B, C, new E, and new sealed F.
List<ArchiveSource> _sources() => [
      ArchiveSource(_note(_a, 'A')),
      ArchiveSource(_note(_b, 'B in archive')),
      ArchiveSource(_note(_c, 'C in archive')),
      ArchiveSource(_note(_e, 'E new')),
      ArchiveSource(Note(id: _f, createdAt: _time, updatedAt: _time),
          sealedPayload: 'sealed-payload'),
    ];

final _choices = {
  _b: ConflictChoice.useArchive,
  _c: ConflictChoice.keepDevice,
};

class _MemoryTarget implements ExportTarget {
  final _bytes = BytesBuilder();
  Uint8List? committed;
  @override
  Future<void> open() async {}
  @override
  Future<void> write(List<int> bytes) async => _bytes.add(bytes);
  @override
  Future<void> commit() async => committed = _bytes.toBytes();
  @override
  Future<void> abort() async {}
}

Future<Uint8List> _archive({ArchiveKey? key}) async {
  final target = _MemoryTarget();
  await ExportWriter(clock: () => _time)
      .write(target, _sources(), key: key, vault: _vault);
  return target.committed!;
}

class _Crash implements Exception {
  const _Crash();
}

/// Durable state survives a crash; [failAt] makes the n-th persistence call
/// throw, simulating the process dying at that boundary.
class _Store implements RestoreStore {
  _Store(this.target);
  final Map<String, Map<String, Object?>> target;
  Map<String, Object?>? marker;
  final staging = <String, Map<String, Map<String, Object?>>>{};
  final backups = <String, Map<String, Map<String, Object?>?>>{};
  int calls = 0;
  int? failAt;
  final writes = <String>[];

  void _boundary(String name) {
    calls++;
    if (failAt != null && calls == failAt) throw const _Crash();
  }

  @override
  Future<Map<String, Object?>?> current(String id) async {
    _boundary('current');
    final value = target[id];
    return value == null ? null : Map.of(value);
  }

  @override
  Future<RestoreMarker?> readMarker() async {
    _boundary('readMarker');
    return marker == null ? null : RestoreMarker.fromJson(marker!);
  }

  @override
  Future<void> writeMarker(RestoreMarker value) async {
    _boundary('writeMarker');
    writes.add('marker:${value.phase.name}');
    marker = jsonDecode(jsonEncode(value.toJson())) as Map<String, Object?>;
  }

  @override
  Future<void> clearMarker() async {
    _boundary('clearMarker');
    writes.add('clearMarker');
    marker = null;
  }

  @override
  Future<void> stage(String op, String id, Map<String, Object?> record) async {
    _boundary('stage');
    writes.add('stage');
    (staging[op] ??= {})[id] = Map.of(record);
  }

  @override
  Future<Map<String, Object?>?> staged(String op, String id) async {
    _boundary('staged');
    return staging[op]?[id];
  }

  @override
  Future<void> discardStaged(String op) async {
    _boundary('discardStaged');
    writes.add('discardStaged');
    staging.remove(op);
  }

  @override
  Future<bool> hasBackup(String op, String id) async {
    _boundary('hasBackup');
    return backups[op]?.containsKey(id) ?? false;
  }

  @override
  Future<void> backup(String op, String id, Map<String, Object?>? prev) async {
    _boundary('backup');
    writes.add('backup');
    (backups[op] ??= {})[id] = prev == null ? null : Map.of(prev);
  }

  @override
  Future<void> put(String id, Map<String, Object?> record) async {
    _boundary('put');
    writes.add('put:$id');
    target[id] = Map.of(record);
  }
}

class _View implements LocalNotesView {
  _View(this.store);
  final _Store store;
  @override
  Note? byId(String id) {
    final value = store.target[id];
    return value == null ? null : Note.fromMap(value);
  }
}

ArchiveKey _key([int seed = 1]) {
  final random = Random(seed);
  return ArchiveKey.forTesting(
      SecretKey(List<int>.generate(32, (_) => random.nextInt(256))),
      List<int>.generate(16, (_) => random.nextInt(256)));
}

String _title(_Store store, String id) => store.target[id]!['title'] as String;

void _expectRestored(_Store store, Map<String, Map<String, Object?>> device) {
  expect(_title(store, _a), 'A');
  expect(store.target[_a], device[_a], reason: 'unchanged note not rewritten');
  expect(_title(store, _b), 'B in archive');
  expect(store.target[_b]!['dirty'], isTrue, reason: 'uploads on next sync');
  expect(store.target[_c], device[_c], reason: 'device version kept');
  expect(store.target[_d], device[_d], reason: 'not in archive: untouched');
  expect(_title(store, _e), 'E new');
  expect(store.target[_f]!['payload'], 'sealed-payload');
  expect(store.target[_f]!['enc_v'], 1);
  final backup = store.backups.values.single;
  expect(backup[_b], device[_b], reason: 'replaced version preserved');
  expect(backup.containsKey(_e) && backup[_e] == null, isTrue);
  expect(store.marker, isNull);
  expect(store.staging, isEmpty);
}

void main() {
  test('restores new and chosen notes, keeps the rest, preserves replaced',
      () async {
    final device = _device();
    final store = _Store(_device());
    final bytes = await _archive();
    final result = await RestoreCoordinator(store, random: Random(1)).restore(
        () => ArchiveByteSource.bytes(bytes),
        local: _View(store),
        choices: _choices);
    expect(result.written, [_e, _f, _b]);
    expect(result.kept, [_c]);
    _expectRestored(store, device);
    expect(store.writes.where((w) => w.startsWith('put:')),
        ['put:$_e', 'put:$_f', 'put:$_b']);
  });

  group('preflight refuses without writing', () {
    test('a conflict without a choice is never merged or guessed', () async {
      final store = _Store(_device());
      final bytes = await _archive();
      await expectLater(
          RestoreCoordinator(store).restore(
              () => ArchiveByteSource.bytes(bytes),
              local: _View(store),
              choices: {_b: ConflictChoice.useArchive}),
          throwsA(isA<RestoreRefused>()));
      expect(store.writes, isEmpty);
    });

    test('an archive with issues is refused', () async {
      final store = _Store(_device());
      final target = _MemoryTarget();
      await ExportWriter(clock: () => _time)
          .write(target, [ArchiveSource(_note(_e, 'T' * 301))], vault: _vault);
      await expectLater(
          RestoreCoordinator(store).restore(
              () => ArchiveByteSource.bytes(target.committed!),
              local: _View(store)),
          throwsA(isA<RestoreRefused>()));
      expect(store.writes, isEmpty);
    });

    test('a wrong export password is refused', () async {
      final store = _Store(_device());
      final bytes = await _archive(key: _key());
      await expectLater(
          RestoreCoordinator(store).restore(
              () => ArchiveByteSource.bytes(bytes),
              local: _View(store),
              choices: _choices,
              key: _key(2)),
          throwsA(isA<ArchiveFormatException>()));
      expect(store.writes, isEmpty);
    });

    test('an unfinished restore must be resumed first', () async {
      final store = _Store(_device())
        ..marker = const RestoreMarker(
            operationId: 'op', phase: RestorePhase.staging, ids: []).toJson();
      final bytes = await _archive();
      await expectLater(
          RestoreCoordinator(store).restore(
              () => ArchiveByteSource.bytes(bytes),
              local: _View(store),
              choices: _choices),
          throwsA(isA<RestoreRefused>()));
      expect(store.writes, isEmpty);
    });

    test('an encrypted archive restores with its key', () async {
      final device = _device();
      final store = _Store(_device());
      final key = _key();
      final bytes = await _archive(key: key);
      await RestoreCoordinator(store).restore(
          () => ArchiveByteSource.bytes(bytes),
          local: _View(store),
          choices: _choices,
          key: key);
      _expectRestored(store, device);
    });
  });

  group('a crash at any persistence boundary', () {
    test('leaves the old target or a restore that resume finishes', () async {
      final bytes = await _archive();
      final probe = _Store(_device());
      await RestoreCoordinator(probe).restore(
          () => ArchiveByteSource.bytes(bytes),
          local: _View(probe),
          choices: _choices);
      final boundaries = probe.calls;
      expect(boundaries, greaterThan(15));

      for (var k = 1; k <= boundaries; k++) {
        final device = _device();
        final store = _Store(_device())..failAt = k;
        await expectLater(
            RestoreCoordinator(store).restore(
                () => ArchiveByteSource.bytes(bytes),
                local: _View(store),
                choices: _choices),
            throwsA(isA<_Crash>()),
            reason: 'boundary $k');
        final committed = store.writes.contains('marker:committing');
        if (!committed) {
          for (final id in device.keys) {
            expect(store.target[id], device[id],
                reason: 'boundary $k: target untouched before commit');
          }
          expect(store.target.keys.toSet(), device.keys.toSet());
        }
        // Restart: a new coordinator over the same durable state.
        store.failAt = null;
        await RestoreCoordinator(store).resume();
        if (committed) {
          _expectRestored(store, device);
        } else {
          expect(store.target, device, reason: 'boundary $k: undone');
          expect(store.marker, isNull);
          expect(store.staging, isEmpty);
        }
      }
    });

    test('a crash during resume is itself resumable', () async {
      final bytes = await _archive();
      Future<void> run(_Store store) => RestoreCoordinator(store).restore(
          () => ArchiveByteSource.bytes(bytes),
          local: _View(store),
          choices: _choices);
      // The first boundary at which a crash leaves a note already written.
      var crashAt = 0;
      for (var k = 1; crashAt == 0 && k < 200; k++) {
        final attempt = _Store(_device())..failAt = k;
        try {
          await run(attempt);
        } on _Crash {
          if (attempt.writes.contains('put:$_e')) crashAt = k;
        }
      }
      expect(crashAt, greaterThan(0));

      final device = _device();
      final crashed = _Store(_device())..failAt = crashAt;
      await expectLater(run(crashed), throwsA(isA<_Crash>()));
      // Each resume crashes one boundary later than the last, then succeeds.
      var resumeCrashes = 0;
      for (var j = 1; crashed.marker != null && j < 50; j++) {
        crashed
          ..calls = 0
          ..failAt = j;
        try {
          await RestoreCoordinator(crashed).resume();
        } on _Crash {
          resumeCrashes++;
        }
      }
      expect(resumeCrashes, greaterThan(3));
      _expectRestored(crashed, device);
    });
  });
}
