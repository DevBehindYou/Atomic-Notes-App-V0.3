part of 'notes_repository.dart';

class LogoutBlocked implements Exception {
  const LogoutBlocked(this.message);
  final String message;
}

extension SafeNotesLogout on NotesRepository {
  /// Called only by an explicit logout, after the existing login/device/TOTP/
  /// vault routes. The old plan is never rebound or sent again with new auth.
  Future<void> _recoverSavedLogout(LogoutPlan plan, LogoutPlanStore store,
      void Function() checkCurrent) async {
    checkCurrent();
    for (final envelope in plan.batches) {
      if (envelope.rows.any((row) => !_notes.containsKey(row['id']))) {
        throw const LogoutBlocked(
            'Unlock your vault and retry logout recovery. Your notes remain on this device.');
      }
    }
    final pending = _box.get(NotesRepository._pendingPushKey);
    LogoutEnvelope? pendingEnvelope;
    if (_box.containsKey(NotesRepository._pendingPushKey)) {
      if (pending is! Map || pending['userId'] != plan.userId ||
          pending['logoutAttemptId'] != plan.attemptId || pending['instant'] != true ||
          pending['rows'] is! List || pending['sigs'] is! Map ||
          pending['versions'] is! Map || pending['conflictIds'] is! Map ||
          !plan.batches.any((batch) => batch.requestId == pending['requestId'])) {
        throw const LogoutBlocked('The saved sync needs recovery. Your notes remain on this device.');
      }
      final expected = plan.batches.firstWhere((batch) => batch.requestId == pending['requestId']);
      pendingEnvelope = await LogoutEnvelope.prepare(attemptId: plan.attemptId,
          requestId: expected.requestId,
          rows: (pending['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList());
      checkCurrent();
      if (pendingEnvelope.fingerprint != expected.fingerprint ||
          pendingEnvelope.wireBytes != expected.wireBytes ||
          expected.rows.any((row) =>
              (pending['sigs'] as Map)[row['id']] != plan.snapshots[row['id']]!.contentSig ||
              (pending['versions'] as Map)[row['id']] != plan.snapshots[row['id']]!.updatedAt ||
              (pending['conflictIds'] as Map)[row['id']] != plan.snapshots[row['id']]!.conflictId)) {
        throw const LogoutBlocked('The saved sync changed. Your notes remain on this device.');
      }
    }
    final receipts = await _api.commitLogoutRecovery(LogoutRecoveryQuery(
        previousSessionHash: plan.sessionHash, batches: plan.batches));
    checkCurrent();
    if (receipts.state == LogoutRecoveryState.prepared) {
      throw const FormatException('Recovered logout is not terminal');
    }
    final pendingRequestId = pendingEnvelope?.requestId;
    if (pendingRequestId != null && receipts.batches
        .firstWhere((batch) => batch.requestId == pendingRequestId).charged != pending['logoutCharge']) {
      throw const FormatException('Recovered logout funding changed');
    }
    var conflicted = false;
    for (var index = 0; index < receipts.batches.length; index++) {
      final envelope = plan.batches[index];
      for (final result in receipts.batches[index].results) {
        checkCurrent();
        final local = _notes[result.id]!;
        final snapshot = plan.snapshots[result.id]!;
        if (!result.ok) {
          if (result.error == 'note_conflict') {
            conflicted = true;
            if (local.dirty) {
              final copy = Note(id: snapshot.conflictId, kind: local.kind,
                  title: '${local.title.length > 270 ? local.title.substring(0, 270) : local.title} (conflict copy)',
                  body: local.body, items: local.items.map((item) => item.copy()).toList(), dirty: true);
              final existing = _notes[copy.id];
              if (existing == null) {
                _notes[copy.id] = copy;
              }
              // Memory can contain a copy whose earlier put failed. Retry its
              // write even without a restart; preserve an edited existing copy.
              await _persist(copy.id);
              checkCurrent();
              await _box.flush();
              checkCurrent();
              // An edited copy is never overwritten on replay. Likewise newer
              // original edits remain dirty; only the exact frozen original may
              // be replaced by the pull after its separate copy is durable.
              if ((existing == null || existing.contentSig == copy.contentSig) &&
                  local.contentSig == snapshot.contentSig &&
                  local.updatedAt.toIso8601String() == snapshot.updatedAt) {
                local.dirty = false;
                local.serverVersion = 0;
                await _persist(local.id);
                checkCurrent();
              }
            }
          }
          continue;
        }
        // A retained receipt must not regress a later acknowledged version.
        if (local.serverVersion > result.version!) continue;
        local.serverVersion = result.version!;
        local.syncedSig = snapshot.contentSig;
        local.dirty = local.contentSig != snapshot.contentSig;
        if (!local.dirty) local.updatedAt = DateTime.parse(result.updatedAt!).toUtc();
        final sent = envelope.rows.firstWhere((row) => row['id'] == result.id);
        if (sent['enc_v'] == Vault.encVersion) {
          _encryptedCloudVersions[local.id] = local.serverVersion;
        } else {
          _encryptedCloudVersions.remove(local.id);
        }
        await _persist(local.id);
        checkCurrent();
      }
    }
    await _drainWrites();
    checkCurrent();
    await _box.flush();
    checkCurrent();
    if (conflicted) {
      await _resetCursor();
      checkCurrent();
      await _pull(plan.userId);
      checkCurrent();
      await _drainWrites();
      await _box.flush();
      checkCurrent();
    }
    // The plan remains the crash-replay journal until every local note write is
    // flushed. Only the exact validated pending batch metadata is removed.
    if (pendingEnvelope != null) {
      if (jsonEncode(_box.get(NotesRepository._pendingPushKey)) != jsonEncode(pending)) {
        throw const LogoutBlocked('The saved sync changed. Your notes remain on this device.');
      }
      await _box.delete(NotesRepository._pendingPushKey);
      await _box.flush();
      checkCurrent();
    }
    await store.consumeRecovered(plan, checkCurrent: checkCurrent);
    checkCurrent();
    _notifyLogoutState();
    if (hasPendingLogoutWork) {
      throw const LogoutBlocked(
          'The previous sync was recovered. Remaining edits are safe on this device. Retry logout to sync them in a new attempt.');
    }
  }

  bool get hasPendingLogoutWork =>
      _cacheReady &&
      (_hasSavedLogout ||
          _box.containsKey(NotesRepository._pendingPushKey) ||
          _hasLocalOnlyNotes ||
          _box.values.any((raw) => raw is Map && raw['dirty'] == true) ||
          _notes.values.any(_needsLogoutUpload));

  bool _needsLogoutUpload(Note note) =>
      note.dirty ||
      (!note.deleted && note.serverVersion <= 0) ||
      (note.syncedSig.isNotEmpty && note.contentSig != note.syncedSig);

  void _assertLogoutBackedUp() {
    if (_box.containsKey(NotesRepository._pendingPushKey) ||
        _hasLocalOnlyNotes ||
        _box.values.any((raw) => raw is Map && raw['dirty'] == true) ||
        _notes.values.any(_needsLogoutUpload)) {
      throw const LogoutBlocked(
          'Logout cancelled. Some changes still need to sync. Your notes remain on this device.');
    }
  }

  /// Holds the repository writer fence through upload, completion and local
  /// teardown. The callback must check its supplied identity before each local
  /// auth/key mutation and end the captured session last.
  Future<void> logoutSafely(
      {required Future<void> Function(void Function() checkCurrent) finishLocal,
      void Function(String message)? onProgress}) async {
    if (_loggingOut) {
      throw const LogoutBlocked('Logout is already in progress.');
    }
    _assertCacheOwner();
    if (!_cacheReady ||
        _stopped ||
        _activeNoteMutations > 0 ||
        _lockingVault ||
        _wipingCloud ||
        _userId == null) {
      throw const LogoutBlocked(
          'Logout cannot start yet. Wait for the current operation and retry.');
    }
    final uid = _userId!,
        lifecycle = _lifecycleRevision,
        session = _api.sessionRevision;
    void checkCurrent() {
      if (!_activeFor(uid) ||
          lifecycle != _lifecycleRevision ||
          session != _api.sessionRevision) {
        throw const LogoutBlocked(
            'Session changed. Your notes have been retained.');
      }
    }

    var finished = false;
    var cacheCleared = false;
    _loggingOut = true;
    _hourly?.cancel();
    _hourly = null;
    _afterEdit?.cancel();
    _afterEdit = null;
    _afterReconnect?.cancel();
    _afterReconnect = null;
    _networkRetry?.cancel();
    _networkRetry = null;
    _autoRetry?.cancel();
    _autoRetry = null;
    _notifyLogoutState();
    try {
      onProgress?.call('Checking notes before logout…');
      await _whenIdle();
      await _drainWrites();
      checkCurrent();
      LogoutPlan? plan;
      final store = LogoutPlanStore(_box);
      Future<void> abortSettled(LogoutPlan saved) async {
        if (_box.containsKey(NotesRepository._pendingPushKey)) return;
        try {
          checkCurrent();
          await _api.abortLogoutSync(saved.attemptId);
          checkCurrent();
          await store.consumeAborted(saved);
          checkCurrent();
        } catch (_) {/* Retain the plan unless its abort is confirmed. */}
      }

      Future<void> complete(LogoutPlan saved) async {
        try {
          await _api.completeLogoutSync(saved.attemptId);
          checkCurrent();
        } on ApiException catch (error) {
          if (error.code == 'logout_sync_incomplete') await abortSettled(saved);
          rethrow;
        }
        await store.recordCompletionAcknowledged(saved);
        checkCurrent();
        _assertLogoutBackedUp();
        await store.consumeCompleted(saved);
        checkCurrent();
      }

      if (store.hasPending) {
        final hash = await _api.logoutSessionHash();
        checkCurrent();
        try {
          plan = await store.load(userId: uid, sessionHash: hash);
        } catch (_) {
          checkCurrent();
          final previous = await store.loadForRecovery(userId: uid, currentSessionHash: hash);
          checkCurrent();
          onProgress?.call('Recovering the previous logout sync…');
          await _recoverSavedLogout(previous, store, checkCurrent);
          checkCurrent();
        }
        checkCurrent();
      }
      // Completion replay must precede admission/push: the token may already
      // be revoked by a prior completion whose response was lost.
      if (plan != null &&
          await store.phaseOf(plan) != LogoutPlanPhase.prepared) {
        checkCurrent();
        _assertLogoutBackedUp();
        onProgress?.call('Recovering the logout confirmation…');
        await complete(plan);
      } else if (plan == null && _api.pendingLogoutCompletion != null) {
        // Crash after consuming the completed plan but before clearing auth.
        _assertLogoutBackedUp();
        await _api.completeLogoutSync(_api.pendingLogoutCompletion!);
        checkCurrent();
      } else if (hasPendingLogoutWork) {
        if (!SyncStatusHelper.isSyncOn) {
          throw const LogoutBlocked(
              'Turn on Cloud Sync before logging out. Your unsynced notes remain on this device.');
        }
        final conn = await _checkConnectivity();
        checkCurrent();
        if (conn.contains(ConnectivityResult.none)) {
          throw const LogoutBlocked(
              'You are offline. Reconnect and retry logout; your notes remain on this device.');
        }
        if (plan == null) {
          // Reconcile an already-issued request in its original priced mode.
          if (_box.containsKey(NotesRepository._pendingPushKey)) {
            if (!_hasUnansweredPush(uid)) {
              throw const LogoutBlocked(
                  'The previous sync needs recovery. Your notes remain on this device.');
            }
            onProgress?.call('Recovering the previous sync…');
            await _push(uid, instant: true);
            checkCurrent();
          }
          if (hasPendingLogoutWork) {
            if (!await _api.logoutSyncAvailable()) {
              throw const LogoutBlocked(
                  'Safe logout sync is not available yet. Your notes remain on this device.');
            }
            checkCurrent();
            for (final raw in _box.values) {
              if (raw is Map &&
                  raw['id'] is String &&
                  (raw['dirty'] == true ||
                      (raw['deleted'] != true &&
                          (raw['serverVersion'] is! num ||
                              (raw['serverVersion'] as num) <= 0))) &&
                  !_notes.containsKey(raw['id'])) {
                throw const LogoutBlocked(
                    'Unlock your vault and retry logout. Your protected notes remain on this device.');
              }
            }
            final candidates = _notes.values
                .where(_needsLogoutUpload)
                .map((note) => note.copy())
                .toList();
            final snapshots = <String, LogoutSnapshot>{};
            final rows = <Map<String, dynamic>>[];
            for (final snapshot in candidates) {
              checkCurrent();
              final local = _notes[snapshot.id]!;
              // Cloud wipe leaves clean version-zero rows; conflicts must still
              // preserve their local content as a copy rather than replacing it.
              local.requireResend();
              await _persist(local.id);
              checkCurrent();
              rows.add(await _sealRemote(snapshot, uid));
              checkCurrent();
              snapshots[snapshot.id] = LogoutSnapshot(
                  contentSig: snapshot.contentSig,
                  updatedAt: snapshot.updatedAt.toIso8601String(),
                  conflictId: newId());
            }
            final binding = await _api.logoutSessionHash();
            checkCurrent();
            plan = await LogoutPlan.prepare(
                userId: uid,
                sessionHash: binding,
                rows: rows,
                snapshots: snapshots);
            checkCurrent();
            await store.save(plan);
            checkCurrent();
          }
        }
        if (plan != null) {
          final LogoutAdmission admission;
          try {
            admission = await _api.beginLogoutSync(plan.attemptId,
                plan.batches.map((batch) => batch.toManifest()).toList());
            checkCurrent();
          } on ApiException catch (error) {
            // The abort response may have been lost on the previous attempt.
            // Reconfirm its terminal receipt before consuming local metadata.
            if (error.code == 'logout_attempt_closed') await abortSettled(plan);
            rethrow;
          }
          onProgress?.call(admission.funding == LogoutFunding.emergency
              ? 'Emergency InstaSync for logout — no Energy used…'
              : 'Syncing before logout (${admission.costPerBatch * admission.batches} Energy)…');
          try {
            // A crash may leave batch two unanswered. Reconcile that exact
            // saved request first, then replay earlier receipts idempotently.
            if (_box.containsKey(NotesRepository._pendingPushKey)) {
              final saved = _box.get(NotesRepository._pendingPushKey);
              if (saved is! Map ||
                  saved['logoutAttemptId'] != plan.attemptId ||
                  saved['userId'] != uid ||
                  saved['instant'] != true ||
                  saved['logoutCharge'] != admission.costPerBatch ||
                  saved['rows'] is! List ||
                  !plan.batches
                      .any((batch) => batch.requestId == saved['requestId'])) {
                throw const LogoutBlocked(
                    'The previous sync needs recovery. Your notes remain on this device.');
              }
              final expected = plan.batches
                  .firstWhere((batch) => batch.requestId == saved['requestId']);
              final restored = await LogoutEnvelope.prepare(
                  attemptId: plan.attemptId,
                  requestId: expected.requestId,
                  rows: (saved['rows'] as List)
                      .map((row) => Map<String, dynamic>.from(row as Map))
                      .toList());
              checkCurrent();
              if (restored.fingerprint != expected.fingerprint ||
                  restored.wireBytes != expected.wireBytes ||
                  expected.rows.any((row) =>
                      saved['sigs'] is! Map ||
                      saved['versions'] is! Map ||
                      (saved['sigs'] as Map)[row['id']] !=
                          plan!.snapshots[row['id']]!.contentSig ||
                      (saved['versions'] as Map)[row['id']] !=
                          plan.snapshots[row['id']]!.updatedAt)) {
                throw const LogoutBlocked(
                    'The saved sync changed. Your notes remain on this device.');
              }
              await _push(uid, instant: true);
              checkCurrent();
            }
            for (final envelope in plan.batches) {
              checkCurrent();
              if (_box.containsKey(NotesRepository._pendingPushKey)) {
                final saved = _box.get(NotesRepository._pendingPushKey);
                if (saved is! Map ||
                    saved['requestId'] != envelope.requestId ||
                    saved['logoutAttemptId'] != plan.attemptId) {
                  throw const LogoutBlocked(
                      'The previous sync needs recovery. Your notes remain on this device.');
                }
              } else {
                await _box.put(NotesRepository._pendingPushKey, {
                  'requestId': envelope.requestId,
                  'userId': uid,
                  'instant': true,
                  'rows': envelope.rows,
                  'logoutAttemptId': plan.attemptId,
                  'logoutCharge': admission.costPerBatch,
                  'versions': {
                    for (final row in envelope.rows)
                      row['id']: plan.snapshots[row['id']]!.updatedAt
                  },
                  'sigs': {
                    for (final row in envelope.rows)
                      row['id']: plan.snapshots[row['id']]!.contentSig
                  },
                  'conflictIds': {
                    for (final row in envelope.rows)
                      row['id']: plan.snapshots[row['id']]!.conflictId
                  },
                });
                await _box.flush();
                checkCurrent();
              }
              await _push(uid, instant: true);
              checkCurrent();
            }
            await _drainWrites();
            checkCurrent();
            _assertLogoutBackedUp();
          } catch (error) {
            // Only settled receipts permit abort. Ambiguous requests stay saved
            // and replay with their existing request IDs on the next logout.
            await abortSettled(plan);
            rethrow;
          }
          await store.recordCompletionRequested(plan);
          checkCurrent();
          onProgress?.call('Sync complete. Confirming logout…');
          await complete(plan);
        }
      }
      checkCurrent();
      await _drainWrites();
      checkCurrent();
      _assertLogoutBackedUp();
      onProgress?.call('Logging out…');
      await clearLocal();
      cacheCleared = true;
      checkCurrent();
      await finishLocal(checkCurrent);
      finished = true;
      _stopped = true;
    } on LogoutBlocked {
      rethrow;
    } catch (_) {
      if (cacheCleared) {
        throw const LogoutBlocked(
            'Your notes were synchronized. Retry logout to finish signing out.');
      }
      throw const LogoutBlocked(
          'Logout could not finish. Your notes are retained. Retry logout to recover the same sync.');
    } finally {
      _loggingOut = false;
      if (!finished &&
          !_stopped &&
          uid == _userId &&
          lifecycle == _lifecycleRevision &&
          session == _api.sessionRevision &&
          _automaticSync) {
        _hourly = Timer.periodic(
            const Duration(hours: 1), (_) => unawaited(syncNow()));
        if (!_hasSavedLogout && pendingCount > 0) _scheduleAutoSync();
      }
      _notifyLogoutState();
    }
  }
}
