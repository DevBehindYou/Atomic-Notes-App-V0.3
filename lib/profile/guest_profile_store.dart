import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:hive_ce/hive_ce.dart';

/// Thrown when guest metadata on this device cannot be read. The raw record
/// and the guest's notes are kept; nothing is recreated without [recover].
class GuestProfileCorrupt implements Exception {
  const GuestProfileCorrupt();
  @override
  String toString() => 'The guest profile on this device could not be read';
}

/// A write from a session whose profile was reset, removed or replaced.
class GuestSessionStale implements Exception {
  const GuestSessionStale();
  @override
  String toString() => 'This guest session has ended';
}

/// An open guest profile: its id and the generation it was opened at. Every
/// read and write checks both, so a session from before a reset, or for
/// another profile, cannot reach the current notes.
class GuestSession {
  const GuestSession._(this.profileId, this.generation);
  final String profileId;
  final int generation;
}

/// Local-only notes for a Guest, kept apart from any signed-in account (C16).
///
/// The registry box `guestProfiles` holds one metadata record; each profile
/// generation's notes live in their own box, `guest_notes_<id>_g<generation>`,
/// so a reset moves to a new empty box and can never expose earlier notes. The signed-in cache
/// (`notesBox`) is never opened, read or written here, and an existing
/// account is never converted. Nothing here needs a session, network, Drive,
/// vault or wallet.
///
/// Not yet reachable from any screen: Guest entry (C17) stays disabled until
/// its gate is accepted.
class GuestProfileStore {
  GuestProfileStore({String Function()? newProfileId})
      : _newProfileId = newProfileId ?? newId;

  static const registryBox = 'guestProfiles';
  static const _recordKey = 'profile';
  static const _version = 1;
  static final _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  final String Function() _newProfileId;
  Future<GuestSession>? _opening;
  Box<dynamic>? _registry;
  final Map<String, Box<dynamic>> _notes = {};

  static String notesBoxName(String profileId, int generation) =>
      'guest_notes_${profileId.replaceAll('-', '')}_g$generation';

  /// Opens the device's guest profile, creating it on first use. Concurrent
  /// calls share one open.
  Future<GuestSession> open() => _opening ??= _open().whenComplete(() {
        _opening = null;
      });

  Future<GuestSession> _open() async {
    final registry = _registry ??= await Hive.openBox<dynamic>(registryBox);
    final raw = registry.get(_recordKey);
    if (raw == null) {
      final id = _newProfileId().toLowerCase();
      if (!_uuid.hasMatch(id)) throw StateError('Invalid guest profile id');
      await registry.put(_recordKey, _record(id, 1));
      return _session(id, 1);
    }
    final (id, generation) = _parse(raw);
    return _session(id, generation);
  }

  Future<GuestSession> _session(String id, int generation) async {
    final name = notesBoxName(id, generation);
    _notes[name] ??= await Hive.openBox<dynamic>(name);
    // A reset interrupted after its fence may have left the previous
    // generation's box behind; it is no longer reachable, so remove it.
    if (generation > 1) {
      final previous = notesBoxName(id, generation - 1);
      if (!_notes.containsKey(previous) && await Hive.boxExists(previous)) {
        await Hive.deleteBoxFromDisk(previous);
      }
    }
    return GuestSession._(id, generation);
  }

  static Map<String, Object> _record(String id, int generation) =>
      {'v': _version, 'id': id, 'generation': generation};

  static (String, int) _parse(Object? raw) {
    if (raw is! Map ||
        raw['v'] != _version ||
        raw['id'] is! String ||
        !_uuid.hasMatch(raw['id'] as String) ||
        raw['generation'] is! int ||
        (raw['generation'] as int) < 1 ||
        raw.length != 3) {
      throw const GuestProfileCorrupt();
    }
    return (raw['id'] as String, raw['generation'] as int);
  }

  /// Replaces unreadable metadata with a new profile. The unreadable record
  /// is moved aside, not deleted, and no notes box is removed.
  Future<GuestSession> recover() async {
    final registry = _registry ??= await Hive.openBox<dynamic>(registryBox);
    final raw = registry.get(_recordKey);
    try {
      _parse(raw);
      return open();
    } on GuestProfileCorrupt {
      await registry.put(
          'unreadable:${DateTime.now().toUtc().microsecondsSinceEpoch}', raw);
      await registry.delete(_recordKey);
      return open();
    }
  }

  Box<dynamic> _current(GuestSession session) {
    final raw = _registry?.get(_recordKey);
    final (id, generation) = _parse(raw);
    final box = _notes[notesBoxName(session.profileId, session.generation)];
    if (id != session.profileId ||
        generation != session.generation ||
        box == null ||
        !box.isOpen) {
      throw const GuestSessionStale();
    }
    return box;
  }

  List<Note> notes(GuestSession session) => [
        for (final value in _current(session).values)
          if (value is Map) Note.fromMap(value)
      ];

  Future<void> put(GuestSession session, Note note) async =>
      _current(session).put(note.id, note.toMap());

  Future<void> remove(GuestSession session, String id) async =>
      _current(session).delete(id);

  /// Ends every session of this profile and starts its next generation with
  /// no notes. Returns the new session.
  Future<GuestSession> reset(GuestSession session) async {
    final box = _current(session);
    final next = session.generation + 1;
    // Fence first: once the generation moves, old sessions are refused and
    // the new generation uses a new, empty box, even if the old box's
    // removal below is interrupted (the next open removes it).
    await _registry!.put(_recordKey, _record(session.profileId, next));
    _notes.remove(notesBoxName(session.profileId, session.generation));
    await box.deleteFromDisk();
    return _session(session.profileId, next);
  }

  Future<void> close() async {
    for (final box in _notes.values) {
      await box.close();
    }
    _notes.clear();
    await _registry?.close();
    _registry = null;
  }
}
