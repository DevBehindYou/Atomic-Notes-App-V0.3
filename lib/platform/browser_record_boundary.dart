/// Inactive browser-only persistence primitive. Not wired to App startup/Hive.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

enum BrowserRecordFailure {
  invalidBatch,
  limit,
  closed,
  openFailed,
  openBlocked,
  openTimedOut,
  invalidSchema,
  request,
  enqueue,
  aborted,
  invalidRecord,
}

/// Safe typed verdict. Never retains DOM messages, keys or record contents.
class BrowserRecordException implements Exception {
  final BrowserRecordFailure code;
  const BrowserRecordException(this.code);

  @override
  String toString() => 'BrowserRecordException(${code.name})';
}

@JS('indexedDB')
external _Factory? get _indexedDB;

extension type _Factory(JSObject _) implements JSObject {
  external _OpenRequest open(JSString name, JSNumber version);
}

extension type _Request(JSObject _) implements JSObject {
  external JSAny? get result;
  external set onsuccess(JSFunction? callback);
  external set onerror(JSFunction? callback);
}

extension type _OpenRequest(JSObject _) implements _Request {
  external _Transaction? get transaction;
  external set onupgradeneeded(JSFunction? callback);
  external set onblocked(JSFunction? callback);
}

extension type _Database(JSObject _) implements JSObject {
  external _Transaction transaction(JSString store, JSString mode);
  external _Store createObjectStore(JSString name);
  external _Names get objectStoreNames;
  external set onversionchange(JSFunction? callback);
  external void close();
}

extension type _Names(JSObject _) implements JSObject {
  external bool contains(JSString name);
}

extension type _Transaction(JSObject _) implements JSObject {
  external _Store objectStore(JSString name);
  external set oncomplete(JSFunction? callback);
  external set onabort(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external void abort();
}

extension type _Store(JSObject _) implements JSObject {
  external _Request put(JSString value, JSString key);
  external _Request add(JSString value, JSString key);
  @JS('delete')
  external _Request remove(JSString key);
  external _Request openCursor();
}

extension type _Cursor(JSObject _) implements JSObject {
  external JSAny get key;
  external JSAny? get value;
  @JS('continue')
  external void advance();
}

/// One fixed store of prepared string records, with native commit settlement.
///
/// Technical bounds are NOT note capacity/economy policy. This is not a complete
/// notes adapter: no owners, sessions, journals, concurrent writers or recovery.
class BrowserRecordBoundary {
  static const maxRecords = 256;
  static const maxBytes = 4 * 1024 * 1024;
  static const _storeName = 'records';
  final _Database _database;
  bool _closed = false;

  BrowserRecordBoundary._(this._database) {
    _database.onversionchange = ((JSAny? _) => close()).toJS;
  }

  static Future<BrowserRecordBoundary> open(String name) async {
    if (name.isEmpty || name.length > 256 || utf8.encode(name).length > 256) {
      throw const BrowserRecordException(BrowserRecordFailure.invalidSchema);
    }
    final completer = Completer<BrowserRecordBoundary>();
    _OpenRequest request;
    try {
      final factory = _indexedDB;
      if (factory == null) {
        throw const BrowserRecordException(BrowserRecordFailure.openFailed);
      }
      request = factory.open(name.toJS, 1.toJS);
    } catch (_) {
      throw const BrowserRecordException(BrowserRecordFailure.openFailed);
    }
    void fail(BrowserRecordFailure code) {
      if (!completer.isCompleted) {
        completer.completeError(BrowserRecordException(code));
      }
    }

    final timer = Timer(const Duration(seconds: 5), () {
      fail(BrowserRecordFailure.openTimedOut);
    });
    void abortUpgrade() {
      try {
        request.transaction?.abort();
      } catch (_) {
        // A finished upgrade cannot be aborted; late success closes below.
      }
    }

    request.onblocked = ((JSAny? _) {
      timer.cancel();
      fail(BrowserRecordFailure.openBlocked);
    }).toJS;
    request.onerror = ((JSAny? _) {
      timer.cancel();
      fail(BrowserRecordFailure.openFailed);
    }).toJS;
    request.onupgradeneeded = ((JSAny? _) {
      // Abort a late upgrade, rather than committing an empty new database.
      if (completer.isCompleted) {
        abortUpgrade();
        return;
      }
      try {
        final database = _Database(request.result as JSObject);
        if (!database.objectStoreNames.contains(_storeName.toJS)) {
          database.createObjectStore(_storeName.toJS);
        }
      } catch (_) {
        timer.cancel();
        fail(BrowserRecordFailure.invalidSchema);
        abortUpgrade();
      }
    }).toJS;
    request.onsuccess = ((JSAny? _) {
      timer.cancel();
      _Database? database;
      try {
        database = _Database(request.result as JSObject);
        if (completer.isCompleted) {
          database.close(); // Late successful open must not leak a connection.
        } else if (!database.objectStoreNames.contains(_storeName.toJS)) {
          database.close();
          fail(BrowserRecordFailure.invalidSchema);
        } else {
          completer.complete(BrowserRecordBoundary._(database));
        }
      } catch (_) {
        try {
          database?.close();
        } catch (_) {
          // Preserve the safe opening failure, never a native error message.
        }
        fail(BrowserRecordFailure.invalidSchema);
      }
    }).toJS;
    return completer.future;
  }

  /// Closes this connection and fences new admissions. It does not cancel a
  /// pending transaction; its native complete/abort event still settles it.
  void close() {
    if (!_closed) {
      _closed = true;
      _database.close();
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const BrowserRecordException(BrowserRecordFailure.closed);
    }
  }

  Future<void> commitBatch({
    Map<String, String> puts = const {},
    Map<String, String> inserts = const {},
    Set<String> deletes = const {},
  }) async {
    _checkOpen();
    if (puts.length + inserts.length + deletes.length > maxRecords) {
      throw const BrowserRecordException(BrowserRecordFailure.limit);
    }
    // Copy, validate and encode outside the short-lived native transaction.
    final putCopy = Map<String, String>.of(puts);
    final insertCopy = Map<String, String>.of(inserts);
    final deleteCopy = Set<String>.of(deletes);
    final keys = [...putCopy.keys, ...insertCopy.keys, ...deleteCopy];
    if (keys.isEmpty ||
        keys.toSet().length != keys.length ||
        keys.any((key) => key.isEmpty)) {
      throw const BrowserRecordException(BrowserRecordFailure.invalidBatch);
    }
    if ([
      ...keys,
      ...putCopy.values,
      ...insertCopy.values,
    ].any((value) => value.length > maxBytes)) {
      throw const BrowserRecordException(BrowserRecordFailure.limit);
    }
    var bytes = 0;
    for (final value in [...keys, ...putCopy.values, ...insertCopy.values]) {
      bytes += utf8.encode(value).length;
      if (bytes > maxBytes) {
        throw const BrowserRecordException(BrowserRecordFailure.limit);
      }
    }
    final transaction = _begin('readwrite');
    final settled = _Settlement(transaction);
    try {
      final store = transaction.objectStore(_storeName.toJS);
      for (final entry in putCopy.entries) {
        settled.observe(store.put(entry.value.toJS, entry.key.toJS));
      }
      for (final entry in insertCopy.entries) {
        settled.observe(store.add(entry.value.toJS, entry.key.toJS));
      }
      for (final key in deleteCopy) {
        settled.observe(store.remove(key.toJS));
      }
    } catch (_) {
      settled.abortWith(BrowserRecordFailure.enqueue);
    }
    await settled.future; // Request success can never resolve this future.
  }

  /// Reads paired cursor keys/values in one readonly transaction. A detached
  /// immutable snapshot is returned only after native transaction completion.
  Future<Map<String, String>> readSnapshot() async {
    _checkOpen();
    final transaction = _begin('readonly');
    final settled = _Settlement(transaction);
    final records = <String, String>{};
    var bytes = 0;
    try {
      final request = transaction.objectStore(_storeName.toJS).openCursor();
      settled.observe(request);
      request.onsuccess = ((JSAny? _) {
        try {
          final raw = request.result;
          if (raw == null) return;
          final cursor = _Cursor(raw as JSObject);
          final key = cursor.key;
          final value = cursor.value;
          if (!key.isA<JSString>() || value == null || !value.isA<JSString>()) {
            settled.abortWith(BrowserRecordFailure.invalidRecord);
            return;
          }
          final dartKey = (key as JSString).toDart;
          final dartValue = (value as JSString).toDart;
          if (dartKey.isEmpty) {
            settled.abortWith(BrowserRecordFailure.invalidRecord);
            return;
          }
          if (dartKey.length > maxBytes || dartValue.length > maxBytes) {
            settled.abortWith(BrowserRecordFailure.limit);
            return;
          }
          bytes += utf8.encode(dartKey).length + utf8.encode(dartValue).length;
          if (records.length >= maxRecords || bytes > maxBytes) {
            settled.abortWith(BrowserRecordFailure.limit);
            return;
          }
          records[dartKey] = dartValue;
          cursor.advance();
        } catch (_) {
          settled.abortWith(BrowserRecordFailure.request);
        }
      }).toJS;
    } catch (_) {
      settled.abortWith(BrowserRecordFailure.enqueue);
    }
    await settled.future;
    return Map<String, String>.unmodifiable(records);
  }

  _Transaction _begin(String mode) {
    try {
      return _database.transaction(_storeName.toJS, mode.toJS);
    } catch (_) {
      throw const BrowserRecordException(BrowserRecordFailure.enqueue);
    }
  }
}

/// All listeners are attached before requests enqueue. Failure cause is safe
/// and retained, but terminal abort/complete is the authoritative settlement.
class _Settlement {
  final _Transaction transaction;
  final _completer = Completer<void>();
  BrowserRecordFailure? _cause;

  _Settlement(this.transaction) {
    transaction.oncomplete = ((JSAny? _) {
      if (!_completer.isCompleted) {
        if (_cause == null) {
          _completer.complete();
        } else {
          _completer.completeError(BrowserRecordException(_cause!));
        }
      }
    }).toJS;
    transaction.onabort = ((JSAny? _) {
      if (!_completer.isCompleted) {
        _completer.completeError(
          BrowserRecordException(_cause ?? BrowserRecordFailure.aborted),
        );
      }
    }).toJS;
    transaction.onerror = ((JSAny? _) {
      abortWith(BrowserRecordFailure.request);
    }).toJS;
  }

  Future<void> get future => _completer.future;

  void observe(_Request request) {
    request.onerror = ((JSAny? _) {
      // Explicit abort remains authoritative even if another listener cancels
      // the request error's default abort action. Never permit partial commit.
      abortWith(BrowserRecordFailure.request);
    }).toJS;
  }

  void abortWith(BrowserRecordFailure cause) {
    _cause ??= cause;
    try {
      transaction.abort();
    } catch (_) {
      // If settlement is already queued, still wait for its native event.
    }
  }
}
