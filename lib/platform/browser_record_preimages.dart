part of 'browser_record_boundary.dart';

/// INACTIVE conditional mutation seam, not a journal or production adapter.
extension BrowserRecordPreimages on BrowserOwnerFence {
  /// Each mutation must have an exact predicate; null means actual absence.
  /// Owner and all records are compared in the SAME native write transaction.
  Future<void> compareAndCommit({
    required BrowserOwnerContext expected,
    required Map<String, String?> expectedRecords,
    Map<String, String> puts = const {},
    Map<String, String> inserts = const {},
    Set<String> deletes = const {},
  }) async {
    _boundary._checkOpen();
    expected._validate();
    // Bound caller-controlled collections before copying or allocating lists.
    if (expectedRecords.isEmpty ||
        expectedRecords.length > BrowserRecordBoundary.maxRecords) {
      throw const BrowserRecordException(BrowserRecordFailure.invalidPreimages);
    }
    final predicates = Map<String, String?>.of(expectedRecords);
    final batch = BrowserRecordBoundary._prepareBatch(puts, inserts, deletes);
    if (predicates.isEmpty ||
        predicates.length > BrowserRecordBoundary.maxRecords ||
        predicates.keys.any((key) => key.isEmpty) ||
        batch.keys.any((key) => !predicates.containsKey(key))) {
      throw const BrowserRecordException(BrowserRecordFailure.invalidPreimages);
    }
    if ([
      ...predicates.keys,
      ...batch.keys,
    ].any((key) => key.startsWith(BrowserOwnerFence._reservedPrefix))) {
      throw const BrowserRecordException(BrowserRecordFailure.reservedKey);
    }
    final strings = [
      ...predicates.keys,
      ...predicates.values.whereType<String>(),
    ];
    if (strings.any((value) => value.length > BrowserRecordBoundary.maxBytes)) {
      throw const BrowserRecordException(BrowserRecordFailure.limit);
    }
    var bytes = 0;
    for (final value in strings) {
      bytes += utf8.encode(value).length;
      if (bytes > BrowserRecordBoundary.maxBytes) {
        throw const BrowserRecordException(BrowserRecordFailure.limit);
      }
    }
    await _guarded(expected, 'readwrite', (store, settled) {
      var remaining = predicates.length;
      var failed = false;
      var enqueued = false;
      void fail(BrowserRecordFailure cause) {
        failed = true;
        settled.abortWith(cause);
      }

      void matched() {
        if (failed || enqueued) return;
        remaining--;
        if (remaining == 0) {
          enqueued = true;
          batch.enqueue(store, settled);
        }
      }

      for (final entry in predicates.entries) {
        final count = store.count(entry.key.toJS);
        settled.observe(count);
        count.onsuccess = ((JSAny? _) {
          if (failed || enqueued) return;
          try {
            final rawCount = count.result;
            if (rawCount == null || !rawCount.isA<JSNumber>()) {
              fail(BrowserRecordFailure.invalidRecord);
              return;
            }
            final present = (rawCount as JSNumber).toDartDouble;
            if (present != 0 && present != 1) {
              fail(BrowserRecordFailure.invalidRecord);
              return;
            }
            if (entry.value == null) {
              if (present == 0) {
                matched();
              } else {
                fail(BrowserRecordFailure.preimageMismatch);
              }
            } else if (present == 0) {
              fail(BrowserRecordFailure.preimageMismatch);
            } else {
              final request = store.get(entry.key.toJS);
              settled.observe(request);
              request.onsuccess = ((JSAny? _) {
                if (failed || enqueued) return;
                try {
                  final raw = request.result;
                  if (raw == null || !raw.isA<JSString>()) {
                    fail(BrowserRecordFailure.invalidRecord);
                  } else if ((raw as JSString).toDart != entry.value) {
                    fail(BrowserRecordFailure.preimageMismatch);
                  } else {
                    matched();
                  }
                } catch (_) {
                  fail(BrowserRecordFailure.enqueue);
                }
              }).toJS;
            }
          } catch (_) {
            fail(BrowserRecordFailure.enqueue);
          }
        }).toJS;
      }
    });
  }
}
