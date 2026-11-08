import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Single-file container for an [ArchiveManifest] and its entries (C12).
///
/// Layout (integers big-endian):
///
///     header  : 'ATNA' | version u8 = 1 | mode u8
///               mode 1 adds: kdf u8 = 1 (Argon2id) | memory u32 |
///               iterations u32 | parallelism u8 | salt (16 bytes)
///     frames  : length u32 | payload, repeated
///               frame 0 = manifest JSON, frames 1..n = entries in manifest
///               order, last frame = trailer JSON {"entries": n}
///
/// Mode 0 stores payloads as they are; each entry is still checked against
/// its manifest SHA-256, and the trailer detects truncation. Mode 1 seals each
/// payload with AES-256-GCM under a key derived from an export password with
/// the vault's own Argon2id parameters. The associated data binds every frame
/// to the header, its index and whether it is the trailer, so frames cannot
/// be reordered, dropped, moved between archives or cut off undetected.
abstract final class ArchiveContainer {
  static const magic = [0x41, 0x54, 0x4e, 0x41]; // ATNA
  static const version = 1;
  static const modePlain = 0;
  static const modePassword = 1;
  static const _kdfArgon2id = 1;
  static const saltLength = 16;
  static const _sealOverhead = VaultCrypto.nonceLength + VaultCrypto.macLength;
  static const _maxTrailerBytes = 1024;

  /// Name stem of the temporary file next to the target. Never a backup.
  static const partialSuffix = '.partial';

  /// The only key-derivation profile an archive may use: the vault's own
  /// Argon2id parameters. The header is read before anything is
  /// authenticated, so any other profile is refused before derivation rather
  /// than letting an archive choose how much memory and time it costs.
  static bool supportedKdf(int memory, int iterations, int parallelism) =>
      memory == Vault.kdfMemory &&
      iterations == Vault.kdfIterations &&
      parallelism == Vault.kdfParallelism;
}

/// The export password's key and the context needed to derive it again.
/// The context (KDF parameters and salt) is stored in the archive header;
/// the password and key never are.
class ArchiveKey {
  ArchiveKey._(
      this.key, this.salt, this.memory, this.iterations, this.parallelism);

  final SecretKey key;
  final Uint8List salt;
  final int memory;
  final int iterations;
  final int parallelism;

  /// Derives a fresh key with a random salt and the vault's Argon2id
  /// parameters (65,536 KiB, 3 iterations, parallelism 1).
  static Future<ArchiveKey> create(String password, {Random? random}) {
    final source = random ?? Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(
        ArchiveContainer.saltLength, (_) => source.nextInt(256)));
    return derive(password, salt,
        memory: Vault.kdfMemory,
        iterations: Vault.kdfIterations,
        parallelism: Vault.kdfParallelism);
  }

  /// Derives the key for an archive whose header gave [salt] and parameters.
  static Future<ArchiveKey> derive(String password, List<int> salt,
      {required int memory,
      required int iterations,
      required int parallelism}) async {
    if (!ArchiveContainer.supportedKdf(memory, iterations, parallelism)) {
      throw const ArchiveFormatException(
          'unsupported_kdf', 'The archive key settings are not supported');
    }
    if (password.isEmpty) {
      throw const ArchiveFormatException(
          'key_required', 'Enter the export password');
    }
    final key = await VaultCrypto.deriveKey(password, salt,
        memory: memory, iterations: iterations, parallelism: parallelism);
    return ArchiveKey._(
        key, Uint8List.fromList(salt), memory, iterations, parallelism);
  }

  /// A key whose derivation is skipped, for tests of the container only.
  static ArchiveKey forTesting(SecretKey key, List<int> salt) => ArchiveKey._(
      key,
      Uint8List.fromList(salt),
      Vault.kdfMemory,
      Vault.kdfIterations,
      Vault.kdfParallelism);
}

/// One note to export, as the device holds it: readable, or a sealed row's
/// vault [sealedPayload] with empty readable fields.
class ArchiveSource {
  const ArchiveSource(this.note, {this.sealedPayload});
  final Note note;
  final String? sealedPayload;
}

/// Where an export is written. A write goes to a temporary location and only
/// [commit] makes it the target; [abort] leaves the target as it was.
abstract class ExportTarget {
  Future<void> open();
  Future<void> write(List<int> bytes);
  Future<void> commit();
  Future<void> abort();
}

/// Writes to `<file>.partial-<random>`, flushes, then renames over [file].
///
/// The rename replaces [file] in one step on every platform Dart supports
/// (Windows included, via MoveFileEx with replace), so the previous export is
/// never deleted first. If the rename fails, [file] still holds the previous
/// export and [abort] removes only the temporary file.
class FileExportTarget implements ExportTarget {
  FileExportTarget(this.file, {Random? random, this.replace = _rename})
      : _temp = File('${file.path}${ArchiveContainer.partialSuffix}-'
            '${(random ?? Random.secure()).nextInt(1 << 32).toRadixString(16)}');

  final File file;
  final File _temp;
  RandomAccessFile? _handle;

  /// Moves the finished temporary file over the target. Injectable so tests
  /// can make the final step fail.
  final Future<void> Function(File temporary, File target) replace;

  static Future<void> _rename(File temporary, File target) =>
      temporary.rename(target.path);

  File get temporaryFile => _temp;

  @override
  Future<void> open() async {
    _handle = await _temp.open(mode: FileMode.writeOnly);
  }

  @override
  Future<void> write(List<int> bytes) async {
    await _handle!.writeFrom(bytes);
  }

  @override
  Future<void> commit() async {
    final handle = _handle!;
    _handle = null;
    await handle.flush();
    await handle.close();
    await replace(_temp, file);
  }

  @override
  Future<void> abort() async {
    final handle = _handle;
    _handle = null;
    try {
      await handle?.close();
    } catch (_) {}
    try {
      if (await _temp.exists()) await _temp.delete();
    } catch (_) {}
  }
}

/// Cooperative cancellation, checked between entries.
class ExportCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'Export cancelled';
}

/// The export did not finish. The previous export (if any) is untouched and
/// nothing partial is left that could be mistaken for a backup.
class ExportFailed implements Exception {
  const ExportFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExportResult {
  const ExportResult(this.manifest, this.bytesWritten);
  final ArchiveManifest manifest;
  final int bytesWritten;
}

class ExportWriter {
  ExportWriter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  /// Writes [sources] as one archive to [target].
  ///
  /// The sources are copied first, so later edits cannot change the export.
  /// Each entry is encoded twice (once for the manifest, once to write) and
  /// only one entry is held in memory at a time; the second encoding must
  /// match the manifest or the export fails.
  Future<ExportResult> write(
    ExportTarget target,
    List<ArchiveSource> sources, {
    ArchiveKey? key,
    ArchiveVault? vault,
    ExportCancel? cancel,
  }) async {
    final snapshot = [
      for (final source in sources)
        ArchiveSource(Note.fromMap(source.note.toMap()),
            sealedPayload: source.sealedPayload)
    ];
    final entries = [
      for (final source in snapshot)
        ArchiveNoteCodec.encode(source.note,
                sealedPayload: source.sealedPayload)
            .$2
    ];
    final manifest = ArchiveManifest(
        createdAt: _clock().toUtc(), entries: entries, vault: vault);
    // Validate exactly as a reader will before writing anything.
    ArchiveManifest.parse(manifest.encode());

    final header = _header(key);
    final headerHash = await Sha256().hash(header);
    var written = 0;
    var index = 0;
    Future<void> frame(List<int> payload, {bool trailer = false}) async {
      final body = key == null
          ? payload
          : await _seal(payload, key, headerHash.bytes, index, trailer);
      final length = ByteData(4)..setUint32(0, body.length);
      await target.write(length.buffer.asUint8List());
      await target.write(body);
      written += 4 + body.length;
      index++;
    }

    try {
      await target.open();
      await target.write(header);
      written += header.length;
      await frame(manifest.encode());
      for (var i = 0; i < snapshot.length; i++) {
        if (cancel?.isCancelled ?? false) throw const ExportCancelled();
        final (bytes, entry) = ArchiveNoteCodec.encode(snapshot[i].note,
            sealedPayload: snapshot[i].sealedPayload);
        if (entry.sha256 != entries[i].sha256) {
          throw const ExportFailed('A note changed during export. Try again.');
        }
        await frame(bytes);
      }
      if (cancel?.isCancelled ?? false) throw const ExportCancelled();
      await frame(utf8.encode(jsonEncode({'entries': snapshot.length})),
          trailer: true);
      await target.commit();
      return ExportResult(manifest, written);
    } on ExportCancelled {
      await target.abort();
      rethrow;
    } on ExportFailed {
      await target.abort();
      rethrow;
    } catch (_) {
      await target.abort();
      throw const ExportFailed(
          'The export could not be written. Your notes are unchanged.');
    }
  }

  static Uint8List _header(ArchiveKey? key) {
    final out = BytesBuilder()
      ..add(ArchiveContainer.magic)
      ..addByte(ArchiveContainer.version)
      ..addByte(key == null
          ? ArchiveContainer.modePlain
          : ArchiveContainer.modePassword);
    if (key != null) {
      final params = ByteData(9)
        ..setUint32(0, key.memory)
        ..setUint32(4, key.iterations)
        ..setUint8(8, key.parallelism);
      out
        ..addByte(ArchiveContainer._kdfArgon2id)
        ..add(params.buffer.asUint8List())
        ..add(key.salt);
    }
    return out.toBytes();
  }
}

Uint8List _aad(List<int> headerHash, int index, bool trailer) {
  final tail = ByteData(5)
    ..setUint32(0, index)
    ..setUint8(4, trailer ? 1 : 0);
  return Uint8List.fromList([...headerHash, ...tail.buffer.asUint8List()]);
}

Future<Uint8List> _seal(List<int> payload, ArchiveKey key, List<int> headerHash,
    int index, bool trailer) async {
  final box = await VaultCrypto.aes.encrypt(payload,
      secretKey: key.key,
      nonce: VaultCrypto.aes.newNonce(),
      aad: _aad(headerHash, index, trailer));
  return Uint8List.fromList(
      [...box.nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// Reads frames one at a time, so memory stays bounded by the largest
/// allowed frame. Sources are a [RandomAccessFile] or bytes in memory.
abstract class ArchiveByteSource {
  Future<Uint8List> read(int count);

  factory ArchiveByteSource.bytes(List<int> bytes) = _MemorySource;
  factory ArchiveByteSource.file(RandomAccessFile file) = _FileSource;
}

class _MemorySource implements ArchiveByteSource {
  _MemorySource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);
  final Uint8List _bytes;
  int _offset = 0;
  @override
  Future<Uint8List> read(int count) async {
    final end = min(_offset + count, _bytes.length);
    final out = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return out;
  }
}

class _FileSource implements ArchiveByteSource {
  _FileSource(this._file);
  final RandomAccessFile _file;
  @override
  Future<Uint8List> read(int count) => _file.read(count);
}

/// What an archive header says about how to open it.
class ArchiveHeader {
  const ArchiveHeader._(this.encrypted, this.salt, this.memory, this.iterations,
      this.parallelism, this._bytes);
  final bool encrypted;
  final Uint8List? salt;
  final int memory;
  final int iterations;
  final int parallelism;
  final Uint8List _bytes;
}

/// Verifies and yields an archive's contents in order: the header, the
/// manifest, each entry (checked against the manifest), then the trailer.
/// Nothing is returned for an entry until its frame has been authenticated
/// and its size and checksum match.
class ArchiveReader {
  ArchiveReader(this._source);
  final ArchiveByteSource _source;

  ArchiveHeader? _header;
  List<int>? _headerHash;
  Uint8List? _manifestBytes;

  /// SHA-256 of the header bytes, once [readHeader] has run.
  List<int>? get headerDigest => _headerHash;

  /// The authenticated manifest frame exactly as stored, once
  /// [readManifest] has run. Every entry is later checked against the
  /// checksums it lists.
  Uint8List? get manifestBytes => _manifestBytes;
  ArchiveKey? _key;
  int _index = 0;

  Future<Uint8List> _exactly(int count, String what) async {
    final bytes = await _source.read(count);
    if (bytes.length != count) {
      throw ArchiveFormatException(
          'truncated', 'The archive ends early ($what)');
    }
    return bytes;
  }

  Future<ArchiveHeader> readHeader() async {
    final fixed = await _exactly(6, 'header');
    if (!_same(fixed.sublist(0, 4), ArchiveContainer.magic)) {
      throw const ArchiveFormatException(
          'malformed', 'This is not an Atomic Notes archive');
    }
    if (fixed[4] != ArchiveContainer.version) {
      throw const ArchiveFormatException('unsupported_version',
          'This archive needs a newer version of Atomic Notes');
    }
    final header = switch (fixed[5]) {
      ArchiveContainer.modePlain =>
        ArchiveHeader._(false, null, 0, 0, 0, Uint8List.fromList(fixed)),
      ArchiveContainer.modePassword => await _passwordHeader(fixed),
      _ => throw const ArchiveFormatException('unsupported_version',
          'This archive needs a newer version of Atomic Notes'),
    };
    _header = header;
    _headerHash = (await Sha256().hash(header._bytes)).bytes;
    return header;
  }

  Future<ArchiveHeader> _passwordHeader(Uint8List fixed) async {
    final rest = await _exactly(10 + ArchiveContainer.saltLength, 'header');
    if (rest[0] != ArchiveContainer._kdfArgon2id) {
      throw const ArchiveFormatException('unsupported_version',
          'This archive needs a newer version of Atomic Notes');
    }
    final view = ByteData.sublistView(rest);
    final memory = view.getUint32(1);
    final iterations = view.getUint32(5);
    final parallelism = view.getUint8(9);
    // Checked here, before any key is derived: the header is not yet
    // authenticated, so it must not choose the derivation cost.
    if (!ArchiveContainer.supportedKdf(memory, iterations, parallelism)) {
      throw const ArchiveFormatException(
          'unsupported_kdf', 'The archive key settings are not supported');
    }
    return ArchiveHeader._(true, Uint8List.fromList(rest.sublist(10)), memory,
        iterations, parallelism, Uint8List.fromList([...fixed, ...rest]));
  }

  /// Supplies the key for an encrypted archive, derived from its header.
  void useKey(ArchiveKey key) => _key = key;

  Future<Uint8List> _frame(int maxBytes, {bool trailer = false}) async {
    final header = _header!;
    final lengthBytes = await _exactly(4, 'frame length');
    final length = ByteData.sublistView(lengthBytes).getUint32(0);
    final limit =
        maxBytes + (header.encrypted ? ArchiveContainer._sealOverhead : 0);
    if (length > limit ||
        (header.encrypted && length < ArchiveContainer._sealOverhead)) {
      throw const ArchiveFormatException(
          'limit_exceeded', 'An archive frame is too large');
    }
    final body = await _exactly(length, 'frame');
    final index = _index++;
    if (!header.encrypted) return body;
    final key = _key;
    if (key == null) {
      throw const ArchiveFormatException(
          'key_required', 'Enter the export password');
    }
    try {
      final clear = await VaultCrypto.aes.decrypt(
          SecretBox(
              body.sublist(
                  VaultCrypto.nonceLength, body.length - VaultCrypto.macLength),
              nonce: body.sublist(0, VaultCrypto.nonceLength),
              mac: Mac(body.sublist(body.length - VaultCrypto.macLength))),
          secretKey: key.key,
          aad: _aad(_headerHash!, index, trailer));
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      // A wrong password and a damaged or reordered frame look the same.
      throw const ArchiveFormatException('authentication_failed',
          'The password is wrong or the archive is damaged');
    }
  }

  Future<ArchiveManifest> readManifest() async {
    final bytes = await _frame(ArchiveLimits.maxManifestBytes);
    final manifest = ArchiveManifest.parse(bytes);
    _manifestBytes = bytes;
    return manifest;
  }

  Future<ArchivedNote> readEntry(ArchiveEntry entry) async =>
      ArchiveNoteCodec.decode(await _frame(ArchiveLimits.maxEntryBytes), entry);

  /// Confirms the archive is complete and nothing follows the trailer.
  Future<void> readTrailer(ArchiveManifest manifest) async {
    final body = await _frame(ArchiveContainer._maxTrailerBytes, trailer: true);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      throw const ArchiveFormatException(
          'truncated', 'The archive is incomplete');
    }
    if (json is! Map ||
        json.length != 1 ||
        json['entries'] != manifest.entries.length) {
      throw const ArchiveFormatException(
          'truncated', 'The archive is incomplete');
    }
    if ((await _source.read(1)).isNotEmpty) {
      throw const ArchiveFormatException(
          'malformed', 'The archive has data after its end');
    }
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Hex SHA-256 of a whole file, for callers recording what was written.
Future<String> archiveFileSha256(File file) async {
  final digest = await const DartSha256().hash(await file.readAsBytes());
  return [for (final b in digest.bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
}
