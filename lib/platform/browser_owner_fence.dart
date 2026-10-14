part of 'browser_record_boundary.dart';

/// Local consistency token only. An owner hint is not an authenticated identity.
class BrowserOwnerContext {
  final String owner;
  final int epoch;
  const BrowserOwnerContext({required this.owner, required this.epoch});
  static const maxEpoch = 9007199254740991;

  void _validate() {
    if (owner.isEmpty ||
        owner.length > 128 ||
        utf8.encode(owner).length > 128 ||
        epoch < 1 ||
        epoch > maxEpoch) {
      throw const BrowserRecordException(BrowserRecordFailure.invalidContext);
    }
  }

  String _encode() => jsonEncode({'schema': 1, 'owner': owner, 'epoch': epoch});
  bool _matches(BrowserOwnerContext other) =>
      owner == other.owner && epoch == other.epoch;

  static BrowserOwnerContext _decode(JSAny? raw) {
    if (raw == null) {
      throw const BrowserRecordException(BrowserRecordFailure.missingContext);
    }
    try {
      if (!raw.isA<JSString>()) throw const FormatException();
      final text = (raw as JSString).toDart;
      if (text.length > 1024) throw const FormatException();
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic> ||
          value.length != 3 ||
          value['schema'] is! int ||
          value['schema'] != 1 ||
          value['owner'] is! String ||
          value['epoch'] is! int) {
        throw const FormatException();
      }
      final context = BrowserOwnerContext(
        owner: value['owner'] as String,
        epoch: value['epoch'] as int,
      );
      context._validate();
      return context;
    } catch (_) {
      throw const BrowserRecordException(BrowserRecordFailure.malformedContext);
    }
  }
}

/// INACTIVE facade. Guards local consistency in one native transaction.
/// Generic boundary/raw same-origin access can bypass it: not authentication,
/// a production adapter, account-switch orchestration or cross-tab leadership.
class BrowserOwnerFence {
  static const contextKey = '@atomic/context/v1';
  static const _reservedPrefix = '@atomic/';
  final BrowserRecordBoundary _boundary;
  const BrowserOwnerFence(this._boundary);

  /// Only an entirely empty store can receive an initial owner. Existing rows
  /// without a context are retained and refused, never assigned or cleared.
  Future<void> bootstrap(BrowserOwnerContext context) async {
    _boundary._checkOpen();
    context._validate();
    final encoded = context._encode();
    final transaction = _boundary._begin('readwrite');
    final settled = _Settlement(transaction);
    try {
      final store = transaction.objectStore(
        BrowserRecordBoundary._storeName.toJS,
      );
      final request = store.openCursor();
      settled.observe(request);
      request.onsuccess = ((JSAny? _) {
        try {
          if (request.result != null) {
            settled.abortWith(BrowserRecordFailure.bootstrapRefused);
          } else {
            settled.observe(store.add(encoded.toJS, contextKey.toJS));
          }
        } catch (_) {
          settled.abortWith(BrowserRecordFailure.enqueue);
        }
      }).toJS;
    } catch (_) {
      settled.abortWith(BrowserRecordFailure.enqueue);
    }
    await settled.future;
  }

  /// Advance the same owner's epoch exactly once. No data row is touched.
  /// Cross-owner transitions are refused until a dedicated-account DB design.
  Future<void> transition({
    required BrowserOwnerContext expected,
    required BrowserOwnerContext next,
  }) async {
    _boundary._checkOpen();
    expected._validate();
    next._validate();
    if (expected.owner != next.owner ||
        expected.epoch == BrowserOwnerContext.maxEpoch ||
        next.epoch != expected.epoch + 1) {
      throw const BrowserRecordException(
        BrowserRecordFailure.transitionRefused,
      );
    }
    final encoded = next._encode();
    await _guarded(expected, 'readwrite', (store, settled) {
      settled.observe(store.put(encoded.toJS, contextKey.toJS));
    });
  }

  Future<void> commitBatch({
    required BrowserOwnerContext expected,
    Map<String, String> puts = const {},
    Map<String, String> inserts = const {},
    Set<String> deletes = const {},
  }) async {
    _boundary._checkOpen();
    expected._validate();
    final batch = BrowserRecordBoundary._prepareBatch(puts, inserts, deletes);
    if (batch.keys.any((key) => key.startsWith(_reservedPrefix))) {
      throw const BrowserRecordException(BrowserRecordFailure.reservedKey);
    }
    await _guarded(expected, 'readwrite', batch.enqueue);
  }

  /// Verify the context before collecting rows in the same readonly snapshot.
  /// Internal context is excluded from the existing 256-domain-row/4MiB bounds.
  Future<Map<String, String>> readSnapshot(BrowserOwnerContext expected) async {
    _boundary._checkOpen();
    expected._validate();
    final records = <String, String>{};
    await _guarded(expected, 'readonly', (store, settled) {
      BrowserRecordBoundary._collectRecords(
        store,
        settled,
        records,
        omitContext: true,
      );
    });
    return Map<String, String>.unmodifiable(records);
  }

  Future<void> _guarded(
    BrowserOwnerContext expected,
    String mode,
    void Function(_Store, _Settlement) enqueue,
  ) async {
    final transaction = _boundary._begin(mode);
    final settled = _Settlement(transaction);
    try {
      final store = transaction.objectStore(
        BrowserRecordBoundary._storeName.toJS,
      );
      final request = store.get(contextKey.toJS);
      settled.observe(request);
      request.onsuccess = ((JSAny? _) {
        try {
          final current = BrowserOwnerContext._decode(request.result);
          if (!current._matches(expected)) {
            settled.abortWith(BrowserRecordFailure.contextMismatch);
            return;
          }
          // No await, crypto or network: admission remains in this transaction.
          enqueue(store, settled);
        } on BrowserRecordException catch (error) {
          settled.abortWith(error.code);
        } catch (_) {
          settled.abortWith(BrowserRecordFailure.enqueue);
        }
      }).toJS;
    } catch (_) {
      settled.abortWith(BrowserRecordFailure.enqueue);
    }
    await settled.future;
  }
}
