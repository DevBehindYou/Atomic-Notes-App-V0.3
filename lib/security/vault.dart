import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:atomic_notes/security/secure_options.dart';
import 'seed_phrase.dart';
import 'vault_crypto.dart';

/// Thrown when a vault already exists for the account, so creating a new one
/// would orphan every note already encrypted under the old key.
class VaultAlreadyExistsError implements Exception {
  const VaultAlreadyExistsError();
  @override
  String toString() => 'A vault already exists for this account';
}

/// Thrown when a phrase cannot be checked because the verifier is unreachable
/// and there is nothing local to test against.
class VaultUnverifiableError implements Exception {
  const VaultUnverifiableError();
  @override
  String toString() => 'Cannot verify the phrase while offline';
}

typedef _VaultOwner = ({String user, int session, int generation});

class _UnlockAttempt {
  _UnlockAttempt(this.owner, this.phrase, this.sample);
  final _VaultOwner owner;
  final String phrase;
  final String? sample;
  late final Future<bool> result;
}

/// End-to-end encryption for note content.
///
/// The key is derived from the recovery phrase and the account id, and nothing
/// else:
///
///   key = Argon2id(phrase, salt = SHA-256("atomic-notes-vault-v1|<user id>"))
///
/// That is a pure function, which is the whole point. The same phrase on any
/// number of devices produces the same key, with no key material to fetch and
/// nothing that can drift out of sync. The server stores only a verifier (a
/// known constant sealed with the key) so a wrong phrase is rejected
/// immediately. The phrase and the key never leave the device.
///
/// This replaces an earlier design where a random key was generated at setup
/// and wrapped by the phrase. That design had a fatal multi-device failure:
/// running setup twice minted a second, unrelated key and overwrote the stored
/// copy of the first, so the same phrase on two devices produced two different
/// keys and each device could read only its own notes.
class Vault {
  Vault._({ApiClient? api, FlutterSecureStorage? storage})
      : _api = api ?? ApiClient.instance,
        _secure = storage ??
            const FlutterSecureStorage(
              aOptions: kSecureAndroidOptions,
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );
  static final Vault instance = Vault._();

  @visibleForTesting
  factory Vault.forTest(
          {required ApiClient api, required FlutterSecureStorage storage}) =>
      Vault._(api: api, storage: storage);

  // The Supabase-era `_table = 'vault'` constant is gone — the server's
  // `vaults` Mongo collection is the equivalent (see db/collections.ts).
  static const int encVersion = 1;

  /// Argon2id parameters. Stored on the row so they can be raised later without
  /// invalidating existing vaults: unlock always uses the values it reads back.
  /// 64 MB is heavy enough to hurt an offline attacker and still finishes in
  /// well under a second on a modern phone.
  static const int kdfMemory = 65536; // KiB
  static const int kdfIterations = 3;
  static const int kdfParallelism = 1;

  final FlutterSecureStorage _secure;

  SecretKey? _key;
  bool _enabled = false;
  String? _boundUser;
  int? _boundSession;
  int _generation = 0;
  Future<void>? _initializing;
  _VaultOwner? _initializingOwner;
  _UnlockAttempt? _unlocking;
  Future<void> _deviceWrites = Future<void>.value();
  final _pendingCacheDeletes = <String, Future<void>>{};
  final _failedCacheDeletes = <String>{};

  final ApiClient _api;
  String? get _uid => _api.currentUserId;
  String _keyStore(String uid) => 'atomic_vault_key_$uid';

  /// The account has a vault configured, or an unreadable cache prevents
  /// safely ruling one out while offline.
  bool get isEnabled => _enabled;

  /// The key is in memory, so vault notes can be read and written.
  bool get isUnlocked => _currentKey != null;

  /// Protected content must stay locked until a usable key is available.
  bool get isLocked => _enabled && _currentKey == null;

  SecretKey? get _currentKey =>
      _boundUser == _uid && _boundSession == _api.sessionRevision ? _key : null;

  _VaultOwner? _captureOwner() {
    final uid = _uid;
    final session = _api.sessionRevision;
    if (uid != _boundUser || session != _boundSession) {
      _key = null;
      _enabled = false;
      _boundUser = uid;
      _boundSession = session;
      _generation++;
    }
    return uid == null
        ? null
        : (user: uid, session: session, generation: _generation);
  }

  bool _isCurrent(_VaultOwner owner) =>
      owner.user == _uid &&
      owner.session == _api.sessionRevision &&
      owner.generation == _generation;

  // ---- lifecycle --------------------------------------------------------

  /// Work out the vault state for the CURRENT user, and unlock from the device
  /// key store if this device has been unlocked before.
  ///
  /// This must run after every sign-in, not just at process start. It used to be
  /// called only from main(), which runs before the user has a session: on a
  /// second phone the account id was still null at that point, so the vault was
  /// recorded as not configured for the whole session. The unlock screen never
  /// appeared, encrypted notes were silently skipped as unreadable, and new
  /// notes were written in the clear. splash_screen now calls this on every
  /// launch and after every login, which is what makes it correct.
  Future<void> init() {
    final owner = _captureOwner();
    if (owner == null) return Future<void>.value();
    if (_initializingOwner == owner && _initializing != null) {
      return _initializing!;
    }
    // Share only work currently in flight. A later call still refreshes cloud
    // state, including after an earlier response said no vault existed.
    _initializingOwner = owner;
    late final Future<void> pending;
    pending = _initialize(owner).whenComplete(() {
      if (identical(_initializing, pending)) {
        _initializing = null;
        _initializingOwner = null;
      }
    });
    _initializing = pending;
    return pending;
  }

  Future<void> _initialize(_VaultOwner owner) async {
    var cloudUnavailable = false;
    try {
      // Bounded: offline with an expired token, the client tries to refresh
      // before this request and would otherwise retry indefinitely — which,
      // since init() is awaited at startup, hangs the whole app on a blank
      // screen. Failing fast here drops to the cached-key path so the app
      // always opens (local-first).
      final row = await _api.getVault().timeout(const Duration(seconds: 5));
      if (!_isCurrent(owner)) return;
      _enabled = row != null || _key != null;
    } catch (_) {
      if (!_isCurrent(owner)) return;
      cloudUnavailable = true;
      debugPrint('Vault.init: cloud state unavailable; checking device cache');
    }

    if (!_enabled && !cloudUnavailable) return;
    if (_key != null) return;

    try {
      // An explicit lock may already have queued removal of this device key.
      await _deviceWrites;
      if (!_isCurrent(owner) || _key != null) return;
      if (_failedCacheDeletes.contains(owner.user)) {
        _enabled = true;
        return;
      }
      final cached = await _secure.read(key: _keyStore(owner.user));
      if (!_isCurrent(owner) || _key != null) return;
      if (cached != null) {
        final bytes = base64Decode(cached);
        if (bytes.length != 32) {
          throw const FormatException('Invalid cached vault key length');
        }
        _key = SecretKey(bytes);
        _enabled = true;
        debugPrint('Vault: unlocked from device key store');
      }
    } catch (_) {
      if (!_isCurrent(owner) || _key != null) return;
      // A failed read is not an absent vault. Preserve the entry and require
      // unlock, including when the cloud cannot tell us the vault state.
      _enabled = true;
      debugPrint('Vault: device key unavailable; remaining locked');
    }
  }

  // ---- setup ------------------------------------------------------------

  /// Turn on encryption for this account.
  ///
  /// Refuses if a vault already exists, checked against the server at call time
  /// rather than trusting cached state. Replacing a vault row is the one
  /// operation that can permanently orphan notes.
  Future<void> createVault(List<String> phrase) async {
    final owner = _captureOwner();
    if (owner == null) throw StateError('Not signed in');
    final uid = owner.user;
    if (_pendingCacheDeletes.containsKey(uid)) {
      throw StateError('Vault device lock is in progress');
    }

    final existing = await _api.getVault();
    _requireCurrent(owner);
    if (existing != null) {
      _enabled = true;
      throw const VaultAlreadyExistsError();
    }

    final key = await _deriveKey(SeedPhrase.canonical(phrase), uid);
    _requireCurrent(owner);
    final verifier = await VaultCrypto.makeVerifier(key);
    _requireCurrent(owner);

    try {
      // Insert, never upsert: the server rejects this with a 409 if a row
      // appeared in the meantime instead of silently replacing the vault —
      // same guarantee as the old insert-never-upsert primary key rejection.
      await _api.createVault(
        verifier: verifier,
        kdfMemory: kdfMemory,
        kdfIterations: kdfIterations,
        kdfParallelism: kdfParallelism,
      );
    } on ApiException catch (e) {
      _requireCurrent(owner);
      if (e.code == 'vault_already_exists') {
        _enabled = true;
        throw const VaultAlreadyExistsError();
      }
      rethrow;
    }

    _requireCurrent(owner);
    _key = key;
    _enabled = true;
    await _cacheKey(owner, key);
    _requireCurrent(owner);
    debugPrint('Vault: created and unlocked');
  }

  // ---- unlock -----------------------------------------------------------

  /// Try to open the vault with [phrase]. Returns true when it is correct.
  ///
  /// [sampleCiphertext] is any note payload this device already holds; it lets
  /// an offline device verify without the server. Throws
  /// [VaultUnverifiableError] when neither the verifier nor a sample is
  /// available, rather than accepting a phrase it could not check.
  Future<bool> unlock(List<String> phrase, {String? sampleCiphertext}) async {
    final owner = _captureOwner();
    if (owner == null || _pendingCacheDeletes.containsKey(owner.user)) {
      return false;
    }
    return _unlockCanonical(
        owner, SeedPhrase.canonical(phrase), sampleCiphertext);
  }

  Future<bool> _unlockCanonical(
      _VaultOwner owner, String phrase, String? sample) async {
    if (!_isCurrent(owner)) return false;
    final active = _unlocking;
    if (active != null) {
      if (active.owner == owner &&
          active.phrase == phrase &&
          active.sample == sample) {
        return active.result;
      }
      // A different phrase/sample must be verified independently, but wait for
      // the current job to release its Argon2 workspace first.
      try {
        await active.result;
      } catch (_) {
        // An earlier attempt's failure does not poison the next attempt.
      }
      return _unlockCanonical(owner, phrase, sample);
    }
    final attempt = _UnlockAttempt(owner, phrase, sample);
    _unlocking = attempt;
    attempt.result = _unlock(owner, phrase, sample).whenComplete(() {
      if (identical(_unlocking, attempt)) _unlocking = null;
    });
    return attempt.result;
  }

  Future<bool> _unlock(
      _VaultOwner owner, String phrase, String? sampleCiphertext) async {
    Map<String, dynamic>? row;
    try {
      row = await _api.getVault();
    } catch (e) {
      debugPrint('Vault.unlock: verifier unreachable ($e)');
    }
    if (!_isCurrent(owner)) return false;

    final key = await _deriveKey(
      phrase,
      owner.user,
      memory: row?['kdfMemory'] as int?,
      iterations: row?['kdfIterations'] as int?,
      parallelism: row?['kdfParallelism'] as int?,
    );
    if (!_isCurrent(owner)) return false;

    final verifier = row?['verifier'] as String?;
    bool ok;
    if (verifier != null) {
      ok = await VaultCrypto.checkVerifier(verifier, key);
    } else if (sampleCiphertext != null) {
      ok = await _opens(sampleCiphertext, key);
    } else {
      throw const VaultUnverifiableError();
    }
    if (!_isCurrent(owner)) return false;

    if (!ok) {
      debugPrint('Vault: unlock rejected, phrase did not verify');
      return false;
    }

    _key = key;
    _enabled = true;
    await _cacheKey(owner, key);
    if (!_isCurrent(owner)) return false;
    debugPrint('Vault: unlocked');
    return true;
  }

  Future<bool> _opens(String payload, SecretKey key) async {
    try {
      await VaultCrypto.open(payload, key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SecretKey> _deriveKey(
    String canonicalPhrase,
    String uid, {
    int? memory,
    int? iterations,
    int? parallelism,
  }) async {
    final salt = await VaultCrypto.saltForUser(uid);
    return VaultCrypto.deriveKey(
      canonicalPhrase,
      salt,
      memory: memory ?? kdfMemory,
      iterations: iterations ?? kdfIterations,
      parallelism: parallelism ?? kdfParallelism,
    );
  }

  // ---- content ----------------------------------------------------------

  Future<String> encryptContent(Map<String, dynamic> content) {
    final key = _currentKey;
    if (key == null) throw StateError('Vault is locked');
    return VaultCrypto.sealJson(content, key);
  }

  Future<Map<String, dynamic>> decryptContent(String payload) {
    final key = _currentKey;
    if (key == null) throw StateError('Vault is locked');
    return VaultCrypto.openJson(payload, key);
  }

  // ---- device / session -------------------------------------------------

  /// Forget the key on this device only. The account stays encrypted and the
  /// phrase is needed to open it here again.
  Future<void> lockThisDevice() async {
    final uid = _uid;
    _generation++;
    _key = null;
    if (uid != null) await _deleteCachedKey(uid);
    debugPrint('Vault: locked on this device');
  }

  /// Drop the decryption key from RAM only, without deleting the device key
  /// store. Used by the session guard on any sign-out (including a session that
  /// simply expired): decrypted vault content is immediately unreadable, yet the
  /// same user signing back in on this device can still auto-unlock. A different
  /// user gets nothing — [init] rebinds per account and only reads that
  /// account's key store entry.
  void lockMemory() {
    _generation++;
    _key = null;
  }

  /// Wipe key material for this device. Call on logout BEFORE signOut, while
  /// the user id is still readable.
  Future<void> clearLocal() async {
    final uid = _uid;
    _generation++;
    _key = null;
    _enabled = false;
    _boundUser = null;
    _boundSession = null;
    if (uid != null) await _deleteCachedKey(uid);
  }

  void _requireCurrent(_VaultOwner owner) {
    if (!_isCurrent(owner)) {
      throw StateError('Vault operation is no longer current');
    }
  }

  Future<void> _cacheKey(_VaultOwner owner, SecretKey key) {
    final pending = _deviceWrites.then((_) async {
      if (!_isCurrent(owner)) return;
      final bytes = await key.extractBytes();
      if (!_isCurrent(owner)) return;
      await _secure.write(
          key: _keyStore(owner.user), value: base64Encode(bytes));
      if (_isCurrent(owner)) _failedCacheDeletes.remove(owner.user);
    });
    _deviceWrites = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> _deleteCachedKey(String uid) {
    // A platform write already underway cannot be cancelled. Deleting after
    // it settles makes explicit device lock/clear win, even if that write fails.
    late final Future<void> pending;
    pending = _deviceWrites.then((_) async {
      try {
        await _secure.delete(key: _keyStore(uid));
        _failedCacheDeletes.remove(uid);
      } catch (_) {
        // The old entry may still exist. Require a verified phrase before
        // trusting this account's cache again in this process.
        _failedCacheDeletes.add(uid);
        rethrow;
      } finally {
        if (identical(_pendingCacheDeletes[uid], pending)) {
          _pendingCacheDeletes.remove(uid);
        }
      }
    });
    _pendingCacheDeletes[uid] = pending;
    _deviceWrites = pending.catchError((Object _) {});
    return pending;
  }
}
