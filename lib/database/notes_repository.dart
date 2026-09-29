import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_policy.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:hive_ce/hive_ce.dart';

/// Single source of truth for notes, and the sync engine.
///
/// Replaces the old model where seven screens each built their own
/// `NotesDataBase` with its own in-memory copy, and where the entire notebook
/// was pushed as one base64 blob. That blob was last-write-wins across *every*
/// note at once: a second device syncing didn't merge with the first, it
/// replaced everything the first had written. That is why notes never appeared
/// on a second phone.
///
/// Now: one row per note, last-write-wins per note on a server-set
/// `updated_at`, tombstones for deletes. MIGRATION NOTE: this used to also
/// carry a Realtime subscription (a change on one device landing on others
/// without a manual sync) — the new backend has no realtime/push layer yet
/// (see the server's README). Automatic sync runs at launch, when the app comes
/// back to the foreground, when the network returns, a few seconds after a local
/// change (or as soon as the Server's hourly window opens), and hourly.
class NotesRepository extends ChangeNotifier with WidgetsBindingObserver implements NotesSource {
  NotesRepository._() {
    // The note limit comes from the Server's wallet; the notes screens show it, so they must hear when it moves.
    NoteQuota.changes.addListener(notifyListeners);
  }
  static final NotesRepository instance = NotesRepository._();

  static const String boxName = 'notesBox';

  /// Reserved Hive key tagging which account this local cache belongs to. Stored
  /// as a plain String, so the `is Map` guards in the loaders skip right over
  /// it. It is what lets a device keep one user's offline notes while refusing
  /// to show them to a different user who signs in later.
  static const String _ownerKey = '__cache_owner__';

  late Box _box;
  final ApiClient _api = ApiClient.instance;
  String? get _userId => _api.currentUserId;

  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  /// Periodic background ("hourly") standard sync, for a device left open.
  Timer? _hourly;

  /// Pending automatic sync after a local change. Edits in quick succession
  /// reset it, so a burst of edits is one sync.
  Timer? _afterEdit;
  static const Duration _editSettle = Duration(seconds: 8);

  /// Android reports a network as connected before it can carry traffic, so a
  /// reconnect waits this long before syncing.
  Timer? _afterReconnect;
  static const Duration _reconnectSettle = Duration(seconds: 3);

  /// Retry of an automatic sync that lost the network (see [networkRetryDelay]).
  Timer? _networkRetry;
  int _networkRetries = 0;

  bool _syncing = false;
  bool get isSyncing => _syncing;

  @override
  String? lastError;
  @override
  DateTime? lastSyncedAt;
  int? _syncCursor;
  static const _pendingPushKey = '__pending_sync_operation';

  /// Reserved Hive key holding the last pull cursor of [_ownerKey]'s account, so
  /// a restart continues where the last pull ended instead of refetching every
  /// note from Google Drive.
  static const String _cursorKey = '__sync_cursor__';

  /// A push carries at most this many notes (the most an account can hold, so
  /// one upload of everything is one request) and roughly this many bytes, which
  /// keeps a request under the Server's size limit. A sync sends up to
  /// [_maxPushBatches] of them.
  static const int _maxPushRows = 50;
  static const int _maxPushBytes = 2500000;
  static const int _maxPushBatches = 5;

  /// While set and in the future, the Server has said an automatic (standard)
  /// sync is not open yet. Instant sync is never blocked.
  DateTime? _standardBlockedUntil;
  Timer? _autoRetry;

  /// When the next automatic sync can send changes, or null when it is open now.
  @override
  DateTime? get nextAutoSyncAt {
    final until = _standardBlockedUntil;
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  /// Tail of the serialized Hive write queue (see [_persist]). Never fails.
  Future<void> _writeChain = Future<void>.value();

  /// In-memory index, id -> note.
  final Map<String, Note> _notes = {};

  // ---- lifecycle --------------------------------------------------------

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
    await _loadFromDisk();

    // Push anything that was written while offline as soon as we're back.
    _connectivity = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _networkRetries = 0;
        _afterReconnect?.cancel();
        _afterReconnect = Timer(_reconnectSettle, () => unawaited(syncNow()));
      }
    });
    // Timers do not run while Android keeps the app in the background.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _networkRetries = 0;
    unawaited(syncNow());
  }

  /// Sends local changes without a manual sync: a few seconds after the edits
  /// settle when automatic sync is open, else just after the window opens.
  void _scheduleAutoSync() {
    if (_userId == null || !SyncStatusHelper.isSyncOn) return;
    final blockedUntil = nextAutoSyncAt;
    final wait = blockedUntil == null
        ? _editSettle
        : blockedUntil.difference(DateTime.now()) + const Duration(seconds: 5);
    _afterEdit?.cancel();
    _afterEdit = Timer(wait, () => unawaited(syncNow()));
  }

  Future<void> _loadFromDisk() async {
    _notes.clear();
    _syncCursor = null;
    // A cache written by a different account — a previous user whose session
    // expired without an explicit logout — must never surface for this one.
    // (Explicit logout already wipes the box; this covers the expiry path.)
    final owner = _box.get(_ownerKey);
    final uid = _userId;
    if (owner is String && uid != null && owner != uid) {
      await _drainWrites();
      await _box.clear();
      return;
    }
    if (uid != null) _restoreCursor(uid);
    for (final raw in _box.values) {
      if (raw is Map && raw['id'] is String) {
        final opened = await _open(raw);
        if (opened == null) continue; // encrypted + locked: load after unlock
        final n = Note.fromMap(opened);
        _notes[n.id] = n;
      }
    }
  }

  // ---- encryption boundary ---------------------------------------------
  // When the vault is unlocked, note content (title/body/items) is sealed into
  // `payload` and the plaintext fields are emptied before anything is written
  // to Hive or Supabase, and re-opened on the way back. When encryption is off
  // these are pass-throughs, so plaintext behaviour is unchanged.

  Future<Map<String, dynamic>> _sealLocal(Note n) => _seal(n.toMap());
  Future<Map<String, dynamic>> _sealRemote(Note n, String uid) =>
      _seal(n.toRemote(uid));

  Future<Map<String, dynamic>> _seal(Map<String, dynamic> m) async {
    // T2T: the vault is off or locked on this device, so the note is stored in
    // the clear and stays readable to any signed-in device.
    if (!Vault.instance.isUnlocked) {
      m['enc_v'] = 0;
      m['payload'] = null;
      return m;
    }
    m['payload'] = await Vault.instance.encryptContent({
      'title': m['title'] ?? '',
      'body': m['body'] ?? '',
      'items': m['items'] ?? const <dynamic>[],
    });
    m['enc_v'] = Vault.encVersion;
    m['title'] = '';
    m['body'] = '';
    m['items'] = const <dynamic>[];
    return m;
  }

  /// Inverse of [_seal]. Returns a plaintext map ready for Note.fromMap/
  /// fromRemote, or null if the row is encrypted but the vault is locked or the
  /// content can't be decrypted (caller skips it and retries after unlock).
  Future<Map<String, dynamic>?> _open(Map<dynamic, dynamic> m) async {
    final out = m.map((k, v) => MapEntry(k.toString(), v));
    final encV = out['enc_v'] is int ? out['enc_v'] as int : 0;
    final payload = out['payload'];
    if (encV < 1 || payload is! String) return out;
    if (!Vault.instance.isUnlocked) return null;
    try {
      final content = await Vault.instance.decryptContent(payload);
      out['title'] = content['title'] ?? '';
      out['body'] = content['body'] ?? '';
      out['items'] = content['items'] ?? const <dynamic>[];
      return out;
    } catch (e) {
      debugPrint('NotesRepository: could not decrypt note ${out['id']}: $e');
      return null;
    }
  }

  /// Called after sign-in, and on startup when a session already exists.
  ///
  /// Returns as soon as the (cheap, local) subscription is registered — the
  /// actual network sync runs in the background. Nothing in the UI should
  /// ever wait for this.
  Future<void> start() async {
    final uid = _userId;
    if (uid == null) return;
    // Isolation on the hot path (logout/expiry then a different user signs in
    // without an app restart): if the disk cache belongs to another account,
    // drop it before this user's notes load in. Same user keeps their cache.
    final owner = _box.get(_ownerKey);
    if (owner is String && owner != uid) {
      _notes.clear();
      _syncCursor = null;
      lastSyncedAt = null;
      await _drainWrites();
      await _box.clear();
      notifyListeners();
    }
    _restoreCursor(uid);
    await _box.put(_ownerKey, uid);
    // MIGRATION NOTE: `_listenRealtime()` used to be called here — removed,
    // the new backend has no realtime endpoint (see class doc comment above).
    // Initial sync: fetches existing cloud notes (a free pull when there's
    // nothing pending) and sends anything edited since the last one.
    unawaited(syncNow());
    _hourly?.cancel();
    _hourly = Timer.periodic(
        const Duration(hours: 1), (_) => unawaited(syncNow()));
  }

  Future<void> stop() async {
    _hourly?.cancel();
    _hourly = null;
    _afterEdit?.cancel();
    _afterEdit = null;
    _afterReconnect?.cancel();
    _afterReconnect = null;
    _networkRetry?.cancel();
    _networkRetry = null;
    _networkRetries = 0;
    _autoRetry?.cancel();
    _autoRetry = null;
    _standardBlockedUntil = null;
  }

  /// Drop the in-memory notes without touching the on-disk cache. Used by the
  /// session guard on sign-out so the UI can't show the previous user's notes,
  /// while a same-user re-login can still reuse the local cache.
  void clearMemory() {
    _notes.clear();
    _syncCursor = null;
    lastSyncedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_connectivity?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _hourly?.cancel();
    _afterEdit?.cancel();
    _afterReconnect?.cancel();
    _networkRetry?.cancel();
    _autoRetry?.cancel();
    super.dispose();
  }

  // ---- reads ------------------------------------------------------------

  /// Live notes, tombstones excluded, pinned first.
  @override
  List<Note> visible({NoteFilter filter = NoteFilter.newest}) {
    final list = _notes.values.where((n) => !n.deleted).toList();

    switch (filter) {
      case NoteFilter.todos:
        list.retainWhere((n) => n.kind == NoteKind.todo);
      case NoteFilter.notes:
        list.retainWhere((n) => n.kind == NoteKind.text);
      case NoteFilter.newest:
      case NoteFilter.oldest:
        break;
    }

    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return filter == NoteFilter.oldest
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  @override
  int get count => _notes.values.where((n) => !n.deleted).length;
  @override
  int get pendingCount => _notes.values.where((n) => n.dirty).length;

  @override
  Note? byId(String id) => _notes[id];

  // ---- quota ------------------------------------------------------------

  /// Notes and to-dos share one allowance — a checklist is a note.
  @override
  int get limit => NoteQuota.limit;

  int get remaining => (limit - count).clamp(0, limit);

  bool get isAtLimit => count >= limit;

  /// Tombstones don't count, so deleting frees a slot immediately.
  String get usageLabel => '$count / $limit';

  // ---- writes -----------------------------------------------------------

  @override
  Future<void> save(Note note) async {
    note.touch();
    // Saved without a real change (or edited back to what the cloud holds): nothing to upload.
    note.settleDirty();
    _notes[note.id] = note;
    await _persist(note.id);
    notifyListeners();
    if (note.dirty) _scheduleAutoSync();
  }

  /// Soft delete, so the removal can reach other devices.
  @override
  Future<void> deleteNotes(Iterable<String> ids) async {
    for (final id in ids) {
      final n = _notes[id];
      if (n == null) continue;
      n.deleted = true;
      n.touch();
      if (n.serverVersion == 0) {
        // Never uploaded, so the cloud has nothing to delete: pushing this
        // would send a tombstone for a row it never had. settleDirty() would
        // not clear it either — it only matches a save back to already-synced
        // content, which a fresh delete never is.
        n.dirty = false;
      } else {
        n.settleDirty();
      }
      await _persist(n.id);
    }
    notifyListeners();
    if (_notes.values.any((n) => n.dirty)) _scheduleAutoSync();
  }

  /// Wipes the local cache only — used on logout. Does not touch the server.
  Future<void> clearLocal() async {
    _notes.clear();
    _syncCursor = null;
    // Let an in-flight write finish first: it would otherwise land after the
    // clear and leave this account's note on disk for the next one.
    await _drainWrites();
    await _box.clear();
    lastSyncedAt = null;
    notifyListeners();
  }

  // ---- persistence ------------------------------------------------------

  /// Writes note [id] to Hive, one write at a time. Each write reads the note
  /// when it runs and sealing is asynchronous, so unqueued writers could finish
  /// out of order and let an older snapshot (for example an acknowledgment that
  /// clears `dirty`) overwrite a newer local edit. Every change to a note is
  /// followed by a call here, so the last write on disk reflects the last
  /// change. A write for another account, or for a note no longer in memory,
  /// is dropped rather than put into the wrong cache.
  Future<void> _persist(String id) {
    final uid = _userId;
    final write = _writeChain.then((_) async {
      final note = _notes[id];
      if (note == null || _userId != uid) return;
      await _box.put(id, await _sealLocal(note));
    });
    _writeChain = write.catchError((_) {});
    return write;
  }

  Future<void> _drainWrites() => _writeChain;

  /// Loads the pull cursor saved for [uid], if this cache belongs to that account.
  void _restoreCursor(String uid) {
    final cursor = _box.get(_cursorKey);
    _syncCursor = _box.get(_ownerKey) == uid && cursor is int ? cursor : null;
  }

  Future<void> _resetCursor() async {
    _syncCursor = null;
    await _box.delete(_cursorKey);
  }

  // ---- sync -------------------------------------------------------------

  /// How long a sync may take before we give up. A device can report a live
  /// connection and still have no route out (captive portals, hotel wifi), so
  /// a connectivity check alone isn't enough — without a deadline the request
  /// just sits there.


  /// Push local changes, then pull remote ones. Safe to call often.
  ///
  /// Cloud sync is energy-gated, and only notes that were edited are sent.
  /// [instant] sync (the manual buttons) costs 10 every time and is always open. An
  /// automatic (standard) sync costs 5 and the Server allows one per hour; while
  /// it is closed nothing is sent and the changes wait ([nextAutoSyncAt] says when).
  /// A sync with nothing to upload (receive-only) is free. If the balance can't
  /// cover the upload, the notes stay safely on the device (still dirty) and
  /// nothing is pushed — so at zero energy local notes keep working but don't
  /// reach the cloud until energy is topped up.
  @override
  Future<bool> syncNow({bool instant = false}) async {
    if (_syncing) return true;
    final uid = _userId;
    if (uid == null) return false;
    if (!SyncStatusHelper.isSyncOn) return false;

    // Don't sit on a dead socket when we already know there's no network.
    final conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) {
      lastError = 'Offline — changes are saved on this device';
      return false;
    }

    if (_syncing || _userId != uid) return false;
    // Acquire locally before the first await that starts a sync operation.
    _syncing = true;
    lastError = null;
    notifyListeners();
    try {
      // A push carries at most 20 notes: keep sending until nothing is waiting,
      // so a completed sync means every queued change reached the server.
      var drained = false;
      for (var batch = 0; batch < _maxPushBatches && !drained; batch++) {
        // The Server has closed automatic sync for now: leave the changes waiting, but still
        // collect a push that was sent and never answered.
        if (!mayPushNow(instant: instant, nextAutoSyncAt: nextAutoSyncAt,
            hasUnansweredPush: _hasUnansweredPush(uid))) {
          break;
        }
        drained = !await _push(uid, instant: instant);
      }
      await _pull(uid);
      unawaited(EnergyService.instance.refresh());
      _networkRetries = 0;
      if (!drained) {
        if (!instant && nextAutoSyncAt != null) {
          // Not a failure: the changes send at the next automatic sync, or now with instant sync.
          return false;
        }
        lastError = '$pendingCount changes are still waiting to sync. Sync again to send the rest.';
        return false;
      }
      return true;
    } on TimeoutException {
      debugPrint('NotesRepository: sync timed out');
      _retryAfterNetworkFailure();
      lastError = 'Sync is taking longer than expected. Your changes are saved; retry to recover the same operation.';
      return false;
    } catch (e) {
      debugPrint('NotesRepository: sync failed: ${e.runtimeType}: $e');
      if (isNetworkFailure(e)) {
        _retryAfterNetworkFailure();
        lastError = 'Connection lost. Your changes are saved on this device and finish syncing when you are back online.';
        return false;
      }
      final text = e.toString();
      lastError = text.contains('note_limit_reached')
          ? 'Note limit reached — delete a note or add capacity in Atomic Energy'
          : text.contains('insufficient_energy')
              ? 'Not enough Atomic Energy for this sync. Your notes stay on this device.'
              : text;
      return false;
    } finally {
      _syncing = false;
      final done = _syncDone;
      _syncDone = null;
      done?.complete();
      notifyListeners();
    }
  }

  /// Completes when the running sync ends. Lets a caller that must not race a
  /// sync (unlock, migration) wait for it instead of skipping it.
  Completer<void>? _syncDone;

  Future<void> _whenIdle() async {
    while (_syncing) {
      await (_syncDone ??= Completer<void>()).future;
    }
  }

  /// A push this account sent whose answer never arrived (app killed, connection lost).
  bool _hasUnansweredPush(String uid) {
    final saved = _box.get(_pendingPushKey);
    return saved is Map && saved['userId'] == uid;
  }

  /// Tries again a little later after the network dropped mid-sync, a few times, so a
  /// push the Server already took is collected without waiting for the next edit or resume.
  void _retryAfterNetworkFailure() {
    final delay = networkRetryDelay(_networkRetries);
    if (delay == null) return;
    _networkRetries++;
    _networkRetry?.cancel();
    _networkRetry = Timer(delay, () => unawaited(syncNow()));
  }

  /// Remembers that automatic sync is closed for [seconds] (or the usual hour) and
  /// tries once more just after it opens, so an hourly timer that fires a moment
  /// early does not cost a whole extra hour.
  void _startCooldown(int? seconds) {
    final wait = Duration(
        seconds: (seconds ?? EnergyService.instance.limits.syncStandardIntervalSeconds).clamp(1, 7200));
    _standardBlockedUntil = DateTime.now().add(wait);
    _autoRetry?.cancel();
    _autoRetry = Timer(wait + const Duration(seconds: 5), () {
      _standardBlockedUntil = null;
      unawaited(syncNow());
    });
    notifyListeners();
  }

  /// Sends one batch. Returns true when more changes are still waiting.
  Future<bool> _push(String uid, {required bool instant}) async {
    if (_userId != uid) return false;
    Map<String, dynamic>? pending = _hasUnansweredPush(uid)
        ? Map<String, dynamic>.from(_box.get(_pendingPushKey) as Map) : null;
    if (pending == null) {
      // A note edited back to what the cloud holds needs no upload.
      var settled = false;
      for (final n in _notes.values) {
        if (n.settleDirty()) {
          settled = true;
          unawaited(_persist(n.id));
        }
      }
      final candidates = _notes.values.where((n) => n.dirty).take(_maxPushRows).map((n) => n.copy()).toList();
      if (candidates.isEmpty) {
        if (settled) notifyListeners();
        return false;
      }
      final sealed = await Future.wait(candidates.map((n) => _sealRemote(n, uid)));
      if (_userId != uid) return false;
      // Keep one request under the Server's size limit; the rest goes in the next batch.
      var bytes = 0;
      var take = 0;
      for (final row in sealed) {
        final size = jsonEncode(row).length;
        if (take > 0 && bytes + size > _maxPushBytes) break;
        bytes += size;
        take++;
      }
      final dirty = candidates.sublist(0, take);
      final rows = sealed.sublist(0, take);
      pending = {
        'requestId': newId(), 'userId': uid, 'instant': instant, 'rows': rows,
        'versions': {for (final n in dirty) n.id: n.updatedAt.toIso8601String()},
        // What the cloud will hold once this lands, so a later edit can be compared with it.
        'sigs': {for (final n in dirty) n.id: n.contentSig},
        'conflictIds': {for (final n in dirty) n.id: newId()},
      };
      await _box.put(_pendingPushKey, pending);
    }
    final rows = (pending['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    final List<Map<String, dynamic>> results;
    try {
      results = await _api.pushNotes(rows, requestId: pending['requestId'] as String, instant: pending['instant'] == true);
    } on ApiException catch (e) {
      if (e.code == 'sync_cooldown') {
        // Refused before anything was recorded or charged. Forget this request so the next
        // try can be made in either mode, and wait for the window the Server named.
        if (_userId == uid) await _box.delete(_pendingPushKey);
        _startCooldown(e.retryAfterSeconds);
        return true;
      }
      // Validation happens before the operation is charged/recorded. Retry corrected data.
      if (e.statusCode == 400 || ['note_limit_reached', 'insufficient_energy', 'note_id_conflict'].contains(e.code)) {
        if (_userId == uid) await _box.delete(_pendingPushKey);
      }
      rethrow;
    }
    if (_userId != uid) return false;
    final versions = pending['versions'] as Map;
    var conflicted = false;
    var failed = false;
    final writtenSeqs = <int>[];
    for (final result in results) {
      final id = result['id'] as String;
      final local = _notes[id];
      if (local == null) continue;
      if (result['ok'] != true) {
        failed = true;
        if (result['error'] == 'note_conflict') conflicted = true;
        if (result['error'] == 'note_conflict' && local.dirty) {
          final copy = Note(id: (pending['conflictIds'] as Map)[id] as String, kind: local.kind, title: '${local.title.length > 270 ? local.title.substring(0, 270) : local.title} (conflict copy)',
            body: local.body, items: local.items.map((i) => i.copy()).toList(), dirty: true);
          _notes[copy.id] = copy;
          await _persist(copy.id);
          // The other version is fetched again below and replaces this one.
          local.dirty = false;
          local.serverVersion = 0;
          await _persist(id);
        }
        continue;
      }
      local.serverVersion = (result['version'] as num).toInt();
      final sent = (pending['sigs'] as Map?)?[id];
      if (sent is String) local.syncedSig = sent;
      final seq = (result['seq'] as num?)?.toInt();
      if (seq != null) writtenSeqs.add(seq);
      if (local.updatedAt.toIso8601String() == versions[id]) {
        local.dirty = false;
        local.updatedAt = DateTime.parse(result['updated_at'] as String).toUtc();
      }
      if (_userId != uid) return false;
      await _persist(id);
    }
    if (_userId != uid) return false;
    await _box.delete(_pendingPushKey);
    await _skipOwnPushedRows(writtenSeqs);
    // The Server takes a standard sync once per hour, so the next one is not open yet. A replayed
    // instant request does not close it, whatever started this attempt.
    if (closesAutomaticSync(sentInstant: pending['instant'] == true, results: results)) {
      _standardBlockedUntil = DateTime.now().add(
          Duration(seconds: EnergyService.instance.limits.syncStandardIntervalSeconds));
    }
    if (failed) {
      // The pull cursor is already past the version that conflicted, so start over.
      if (conflicted) await _resetCursor();
      notifyListeners();
      await _pull(uid);
      throw ApiException(
          conflicted
              ? 'Some notes changed on another device. Your edits are saved as separate copies.'
              : 'Some notes could not be uploaded. They stay on this device and will retry.',
          409);
    }
    return _notes.values.any((n) => n.dirty);
  }

  /// The rows this push just wrote would come back in the next pull, and each would be read from Drive
  /// again. When their sequences are exactly the next ones after the cursor, no other device wrote in
  /// between, so the cursor moves past them. Anything else leaves the cursor alone and the pull as it was.
  Future<void> _skipOwnPushedRows(List<int> seqs) async {
    final cursor = _syncCursor;
    if (cursor == null || seqs.isEmpty) return;
    seqs.sort();
    var expected = cursor + 1;
    for (final seq in seqs) {
      if (seq != expected) return;
      expected++;
    }
    _syncCursor = seqs.last;
    await _box.put(_cursorKey, _syncCursor);
  }

  Future<void> _pull(String uid) async {
    var more = true;
    while (more && _userId == uid) {
      final response = await _api.pullNotes(after: _syncCursor, encOnly: !Vault.instance.isUnlocked);
      if (_userId != uid) return;
      await _mergeAll(List<Map<String, dynamic>>.from(response['rows'] as List), uid);
      if (_userId != uid) return;
      _syncCursor = (response['nextCursor'] as num).toInt();
      await _box.put(_cursorKey, _syncCursor);
      more = response['hasMore'] == true;
      lastSyncedAt = DateTime.parse(response['cursor'] as String).toUtc();
    }
  }

  /// Last-write-wins per note, on the server's `updated_at`.
  ///
  /// [forUid] is the account the rows were fetched for. If the session has since
  /// changed (logout or expiry completed while this fetch/stream event was in
  /// flight), the rows are dropped rather than merged — otherwise a late fetch
  /// would repopulate the UI with the previous user's notes after sign-out.
  Future<void> _mergeAll(List<Map<String, dynamic>> rows, String forUid) async {
    if (_userId != forUid) return;
    var changed = false;
    for (final row in rows) {
      if (_userId != forUid) return; // session ended mid-merge
      // Read before the row is opened: is the cloud copy plain while the vault is unlocked?
      final plainInCloud = rowNeedsSealing(row, vaultUnlocked: Vault.instance.isUnlocked);
      final opened = await _open(row);
      if (opened == null) continue; // encrypted + locked: retry after unlock
      final remote = Note.fromRemote(opened);
      final local = _notes[remote.id];

      if (local == null) {
        if (plainInCloud) remote.requireResend();
        _notes[remote.id] = remote;
        await _persist(remote.id);
        changed = true;
        continue;
      }

      // Never let a pull clobber an edit that hasn't been pushed yet.
      if (local.dirty) continue;

      if (remote.serverVersion > local.serverVersion) {
        if (plainInCloud) remote.requireResend();
        _notes[remote.id] = remote;
        await _persist(remote.id);
        changed = true;
      } else if (plainInCloud && remote.serverVersion == local.serverVersion) {
        // This device already has that version, but the cloud still holds it as plain text.
        local.requireResend();
        await _persist(local.id);
        changed = true;
      }
    }
    if (changed && _userId == forUid) notifyListeners();
  }

  /// Re-seal every note this device holds and push them.
  ///
  /// Runs after the vault is created and after every unlock, so notes written
  /// while the vault was off or locked (T2T) are converted to vault notes. It
  /// is idempotent: re-sealing an already-sealed note just rewrites it, so an
  /// interrupted run is safe to repeat.
  ///
  /// Waits for a sync that is already running first: it may still be pulling notes
  /// this method has not seen yet, and skipping it (as a busy [syncNow] does) would
  /// leave those notes plain in the cloud. Returns how many notes are still waiting
  /// to be sent sealed (0 when the migration finished; more when the Server refused
  /// for now, for example without enough energy).
  Future<int> migrateToVault() async {
    if (!Vault.instance.isUnlocked) return 0;
    await _whenIdle();
    if (_notes.isEmpty) return 0;
    debugPrint('NotesRepository: migrating ${_notes.length} notes into the vault');
    for (final n in _notes.values.toList()) {
      n.requireResend();
      await _persist(n.id);
    }
    notifyListeners();
    await syncNow();
    final waiting = pendingCount;
    debugPrint('NotesRepository: vault migration ${waiting == 0 ? 'complete' : 'left $waiting notes waiting'}');
    return waiting;
  }

  /// After unlocking on a device that was holding notes it could not read,
  /// re-read the local cache, pull everything, and fold any plaintext notes
  /// into the vault.
  Future<void> reloadAfterUnlock() async {
    // A sync that started before the unlock may still be merging rows. Let it finish, so the
    // reload below sees every row it stored and its late rows are not merged into a cache that
    // is being rebuilt.
    await _whenIdle();
    await _loadFromDisk();
    // A locked pull skipped encrypted rows but still advanced the cursor.
    await _resetCursor();
    lastSyncedAt = null;
    notifyListeners();
    await syncNow();
    await migrateToVault();
  }

  /// Any sealed payload this device already holds, so an offline device can
  /// check a recovery phrase without reaching the server.
  String? get sampleCiphertext {
    for (final raw in _box.values) {
      if (raw is Map && raw['id'] is String) {
        final v = raw['enc_v'];
        final p = raw['payload'];
        if (v is int && v >= 1 && p is String && p.isNotEmpty) return p;
      }
    }
    return null;
  }

  // ---- recycle bin ------------------------------------------------------

  /// Deleted notes this device still holds, most recently deleted first.
  ///
  /// A deleted note is a tombstone that keeps its content, so it can be put
  /// back. Its cloud file sits in the Google Drive trash meanwhile.
  @override
  List<Note> get binNotes {
    final list = _notes.values.where((n) => n.deleted).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Puts a deleted note back. False when it is not in the bin or the note
  /// limit leaves no room for it.
  @override
  Future<bool> restoreNote(String id) async {
    final n = _notes[id];
    if (n == null || !n.deleted || isAtLimit) return false;
    n.deleted = false;
    n.touch();
    // Restored before its deletion was sent: the cloud still has it, so there is nothing to send.
    n.settleDirty();
    await _persist(id);
    notifyListeners();
    if (n.dirty) _scheduleAutoSync();
    return true;
  }

  /// Removes deleted notes from this device for good. A deletion that has not
  /// reached the cloud yet is synced first: forgetting it locally would let the
  /// note come back from the cloud on the next pull. Returns how many were
  /// removed; 0 means nothing was, for example because that sync failed.
  @override
  Future<int> deleteForever(Iterable<String> ids) async {
    final targets = ids.where((id) => _notes[id]?.deleted == true).toList();
    if (targets.isEmpty) return 0;
    bool unsent() => targets.any((id) {
          final n = _notes[id];
          return n != null && n.dirty && n.serverVersion > 0;
        });
    if (unsent()) {
      if (!SyncStatusHelper.isSyncOn) return 0;
      await syncNow();
      if (unsent()) return 0;
    }
    var removed = 0;
    for (final id in targets) {
      if (_notes.remove(id) != null) removed++;
    }
    // Let an in-flight write finish, then drop the stored copies.
    await _drainWrites();
    for (final id in targets) {
      await _box.delete(id);
    }
    notifyListeners();
    return removed;
  }

  // ---- maintenance ------------------------------------------------------

  /// Number of live notes in the cloud, or null when the cloud cannot be reached.
  ///
  /// Reads a count only: nothing is pulled or merged, so checking the cloud can
  /// never change the notes on this device. It counts rows, not readable notes:
  /// an encrypted row still counts while this device is locked, which is what
  /// makes the on-device and in-cloud numbers comparable.
  @override
  Future<int?> cloudCount() async {
    if (_userId == null) return null;
    try {
      return await _api.remoteNoteCount();
    } catch (e) {
      debugPrint('NotesRepository.cloudCount failed: $e');
      return null;
    }
  }

  /// Empties the CLOUD copy of this account's notes and leaves this device alone.
  ///
  /// The Server removes the Drive files and the note rows without leaving
  /// tombstones, so no pull can tell any device to delete its notes. Every note
  /// here is then at "version 0" in the cloud (it is not there), so an edit or
  /// [markAllForUpload] writes it again as a new cloud note.
  ///
  /// Deliberately leaves the vault row alone: it holds the phrase verifier, and
  /// dropping it would strand notes still encrypted on other devices.
  @override
  Future<WipeOutcome> wipeRemote() async {
    if (_userId == null) return const WipeOutcome(false, 'Not signed in.');
    try {
      await _api.wipeRemoteNotes();
    } catch (e) {
      lastError = e.toString();
      debugPrint('NotesRepository.wipeRemote failed: $e');
      return const WipeOutcome(false,
          'Could not wipe the cloud. Check your connection and try again; nothing on this device was changed.');
    }
    for (final id in _notes.keys.toList()) {
      _notes[id]?.serverVersion = 0;
      _notes[id]?.syncedSig = '';
      await _persist(id);
    }
    // A saved push refers to cloud versions that no longer exist.
    await _box.delete(_pendingPushKey);
    lastSyncedAt = null;
    notifyListeners();
    return const WipeOutcome(true,
        'Cloud notes wiped. The notes on this device are untouched.');
  }

  /// Removes every note from THIS DEVICE only. The cloud copy is not touched, so
  /// the notes download again on the next sync. Notes that were never uploaded
  /// are gone for good: [pendingCount] says how many before the caller asks.
  @override
  Future<int> wipeLocalNotes() async {
    final removed = _notes.length;
    _notes.clear();
    _syncCursor = null;
    lastSyncedAt = null;
    // Let an in-flight write finish first, or it lands after the clear.
    await _drainWrites();
    await _box.clear();
    final uid = _userId;
    // Keep the cache tagged with this account so the next load still recognises it.
    if (uid != null) await _box.put(_ownerKey, uid);
    notifyListeners();
    return removed;
  }

  /// Marks every live note as waiting to upload, so the next sync writes all of
  /// them to the cloud. Used to refill a cloud that was wiped.
  @override
  Future<int> markAllForUpload() async {
    var marked = 0;
    for (final n in _notes.values.toList()) {
      if (n.deleted) continue;
      n.dirty = true;
      // Forced: send it even if this device believes the cloud already has it.
      n.syncedSig = '';
      marked++;
      await _persist(n.id);
    }
    notifyListeners();
    return marked;
  }
}
