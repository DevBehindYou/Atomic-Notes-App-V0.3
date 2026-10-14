@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:atomic_notes/platform/browser_record_boundary.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-only hooks. Every prototype alteration is exact-name scoped and restored.
const _hooks = r'''
(() => {
  const transaction = IDBDatabase.prototype.transaction;
  const put = IDBObjectStore.prototype.put;
  const add = IDBObjectStore.prototype.add;
  const create = IDBDatabase.prototype.createObjectStore;
  let owned = '', events = [], requestCount = 0, enqueueCount = 0;
  let abortAt = 0, throwAt = 0, cancelError = false, failSchema = false;
  globalThis.atomicBoundaryReset = (name, fault, throwing, canceled, schema) => {
    owned = name; events = []; requestCount = 0; enqueueCount = 0;
    abortAt = fault; throwAt = throwing; cancelError = canceled; failSchema = schema;
  };
  IDBDatabase.prototype.transaction = function (...args) {
    const txn = transaction.apply(this, args);
    if (this.name === owned && txn.mode === 'readwrite') {
      events.push('transaction');
      txn.addEventListener('complete', () => events.push('complete'));
      txn.addEventListener('abort', () => events.push('abort'));
    }
    return txn;
  };
  const observe = (request, txn) => {
    request.addEventListener('success', () => {
      events.push('request');
      if (++requestCount === abortAt) txn.abort();
    });
    if (cancelError) request.addEventListener('error', event => {
      events.push('canceled-error'); event.preventDefault();
    });
    return request;
  };
  IDBObjectStore.prototype.put = function (...args) {
    if (this.transaction.db.name !== owned) return put.apply(this, args);
    if (++enqueueCount === throwAt) throw new Error('public synthetic enqueue fault');
    const request = put.apply(this, args);
    return observe(request, this.transaction);
  };
  IDBObjectStore.prototype.add = function (...args) {
    if (this.transaction.db.name !== owned) return add.apply(this, args);
    const request = add.apply(this, args);
    return observe(request, this.transaction);
  };
  IDBDatabase.prototype.createObjectStore = function (...args) {
    if (this.name === owned && failSchema) throw new Error('public schema fault');
    return create.apply(this, args);
  };
  globalThis.atomicBoundaryMark = value => events.push(value);
  globalThis.atomicBoundaryEvents = () => JSON.stringify(events);
  const rawOpen = (name, version = 1, wrong = false) => new Promise((resolve, reject) => {
    const request = indexedDB.open(name, version);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.length)
        create.call(request.result, wrong ? 'wrong' : 'records');
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error('public owned open failure'));
    request.onblocked = () => reject(new Error('public owned open blocked'));
  });
  globalThis.atomicBoundarySeed = async (name, json) => {
    const db = await rawOpen(name);
    try {
      await new Promise((resolve, reject) => {
        const txn = transaction.call(db, 'records', 'readwrite');
        txn.oncomplete = resolve; txn.onabort = () => reject(new Error('public seed abort'));
        const store = txn.objectStore('records');
        for (const [key, value] of JSON.parse(json)) put.call(store, value, key);
      });
    } finally { db.close(); }
  };
  globalThis.atomicBoundaryWrongSchema = async name => {
    const db = await rawOpen(name, 1, true); db.close();
  };
  globalThis.atomicBoundaryUpgrade = async name => {
    const db = await rawOpen(name, 2); db.close();
  };
  globalThis.atomicBoundaryDelete = name => new Promise((resolve, reject) => {
    const request = indexedDB.deleteDatabase(name);
    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(new Error('public owned deletion failure'));
    request.onblocked = () => reject(new Error('public owned deletion blocked'));
  });
  globalThis.atomicBoundaryRemaining = async name =>
    (await indexedDB.databases()).filter(db => db.name === name).length;
  globalThis.atomicBoundaryRestore = () => {
    IDBDatabase.prototype.transaction = transaction;
    IDBObjectStore.prototype.put = put;
    IDBObjectStore.prototype.add = add;
    IDBDatabase.prototype.createObjectStore = create;
    owned = '';
    return IDBDatabase.prototype.transaction === transaction &&
      IDBObjectStore.prototype.put === put && IDBObjectStore.prototype.add === add &&
      IDBDatabase.prototype.createObjectStore === create && owned === '';
  };
})();
''';

@JS('atomicBoundaryReset')
external void _reset(
  JSString name,
  JSNumber abortAt,
  JSNumber throwAt,
  JSBoolean cancelError,
  JSBoolean failSchema,
);
@JS('atomicBoundaryMark')
external void _mark(JSString value);
@JS('atomicBoundaryEvents')
external JSString _events();
@JS('atomicBoundarySeed')
external JSPromise<JSAny?> _seed(JSString name, JSString pairs);
@JS('atomicBoundaryWrongSchema')
external JSPromise<JSAny?> _wrongSchema(JSString name);
@JS('atomicBoundaryUpgrade')
external JSPromise<JSAny?> _upgrade(JSString name);
@JS('atomicBoundaryDelete')
external JSPromise<JSBoolean> _delete(JSString name);
@JS('atomicBoundaryRemaining')
external JSPromise<JSNumber> _remaining(JSString name);
@JS('atomicBoundaryRestore')
external JSBoolean _restore();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String name;
  final connections = <BrowserRecordBoundary>[];
  var index = 0;
  void reset({
    int abortAt = 0,
    int throwAt = 0,
    bool cancelError = false,
    bool failSchema = false,
  }) => _reset(
    name.toJS,
    abortAt.toJS,
    throwAt.toJS,
    cancelError.toJS,
    failSchema.toJS,
  );
  Future<BrowserRecordBoundary> open() async {
    final boundary = await BrowserRecordBoundary.open(name);
    connections.add(boundary);
    return boundary;
  }

  List<dynamic> observed() => jsonDecode(_events().toDart) as List<dynamic>;
  Matcher failure(BrowserRecordFailure code) => isA<BrowserRecordException>()
      .having((error) => error.code, 'safe code', code);
  Future<void> seed(List<List<Object?>> pairs) async {
    await _seed(name.toJS, jsonEncode(pairs).toJS).toDart;
  }

  setUp(() {
    name = 'atomic-boundary-${Random.secure().nextInt(1 << 30)}-${index++}';
    connections.clear();
    globalContext.callMethod<JSAny?>('eval'.toJS, _hooks.toJS);
    reset();
  });
  tearDown(() async {
    try {
      for (final boundary in connections) {
        boundary.close();
      }
      expect((await _delete(name.toJS).toDart).toDart, isTrue);
      expect((await _remaining(name.toJS).toDart).toDartInt, 0);
    } finally {
      expect(_restore().toDart, isTrue);
    }
    // Exact receipt requires owned deletion and checked native restoration.
    // ignore: avoid_print
    print('ATOMIC_BOUNDARY_CLEANUP_OK');
  });

  test(
    'B1 commit acknowledgment follows native complete and survives reopen',
    () async {
      final boundary = await open();
      final draft = <String, String>{
        'note': 'public Ω checklist',
        'journal': 'pending-v3',
      };
      final expected = Map<String, String>.of(draft);
      final commit = boundary.commitBatch(puts: draft);
      draft['note'] = 'public caller subsequent edit';
      await commit;
      _mark('ack'.toJS);
      expect(observed(), [
        'transaction',
        'request',
        'request',
        'complete',
        'ack',
      ]);
      final snapshot = await boundary.readSnapshot();
      expect(snapshot, expected);
      expect(
        () => snapshot['note'] = 'public mutation',
        throwsUnsupportedError,
      );
      boundary.close();
      expect(await (await open()).readSnapshot(), expected);
    },
  );

  test(
    'B2 late abort rejects acknowledgment and preserves sentinel and draft',
    () async {
      final boundary = await open();
      await boundary.commitBatch(
        puts: {'note': 'public sentinel', 'journal': 'old'},
      );
      final draft = {'note': 'public offline edit', 'journal': 'new'};
      final savedDraft = Map<String, String>.of(draft);
      reset(abortAt: 2);
      await expectLater(
        boundary.commitBatch(puts: draft),
        throwsA(failure(BrowserRecordFailure.aborted)),
      );
      expect(observed(), ['transaction', 'request', 'request', 'abort']);
      expect(draft, savedDraft);
      boundary.close();
      expect(await (await open()).readSnapshot(), {
        'note': 'public sentinel',
        'journal': 'old',
      });
    },
  );

  test(
    'B3 canceled request error still aborts whole duplicate insert batch',
    () async {
      final boundary = await open();
      await boundary.commitBatch(
        puts: {'sentinel': 'public old', 'existing': 'public exists'},
      );
      reset(cancelError: true);
      await expectLater(
        boundary.commitBatch(
          puts: {'sentinel': 'public changed'},
          inserts: {'existing': 'public duplicate', 'new': 'public new'},
        ),
        throwsA(failure(BrowserRecordFailure.request)),
      );
      expect(observed(), contains('canceled-error'));
      expect(observed().last, 'abort');
      boundary.close();
      expect(await (await open()).readSnapshot(), {
        'sentinel': 'public old',
        'existing': 'public exists',
      });
    },
  );

  test('B4 synchronous enqueue failure aborts earlier writes', () async {
    final boundary = await open();
    await boundary.commitBatch(puts: {'sentinel': 'public old'});
    reset(throwAt: 2);
    await expectLater(
      boundary.commitBatch(
        puts: {'sentinel': 'public changed', 'new': 'public new'},
      ),
      throwsA(failure(BrowserRecordFailure.enqueue)),
    );
    expect(observed().last, 'abort');
    boundary.close();
    expect(await (await open()).readSnapshot(), {'sentinel': 'public old'});
  });

  test('B5 committed deletion preserves unrelated record', () async {
    final boundary = await open();
    await boundary.commitBatch(
      puts: {
        'note': 'public old',
        'journal': 'public old',
        'keep': 'public kept',
      },
    );
    reset();
    await boundary.commitBatch(deletes: {'note', 'journal'});
    _mark('ack'.toJS);
    expect(observed(), ['transaction', 'complete', 'ack']);
    boundary.close();
    expect(await (await open()).readSnapshot(), {'keep': 'public kept'});
  });

  test('B6 invalid and oversized batches admit no native transaction', () async {
    final boundary = await open();
    await boundary.commitBatch(puts: {'sentinel': 'public old'});
    reset();
    await expectLater(
      boundary.commitBatch(),
      throwsA(failure(BrowserRecordFailure.invalidBatch)),
    );
    await expectLater(
      boundary.commitBatch(puts: {'same': 'public'}, deletes: {'same'}),
      throwsA(failure(BrowserRecordFailure.invalidBatch)),
    );
    await expectLater(
      boundary.commitBatch(puts: {'': 'public'}),
      throwsA(failure(BrowserRecordFailure.invalidBatch)),
    );
    await expectLater(
      boundary.commitBatch(
        puts: {for (var i = 0; i < 257; i++) '$i': 'public'},
      ),
      throwsA(failure(BrowserRecordFailure.limit)),
    );
    // Two-byte characters pass a code-unit-only check but exceed the UTF-8 cap.
    final unicode = List<String>.filled(
      BrowserRecordBoundary.maxBytes ~/ 2,
      'é',
    ).join();
    await expectLater(
      boundary.commitBatch(puts: {'key': unicode}),
      throwsA(failure(BrowserRecordFailure.limit)),
    );
    expect(observed(), isEmpty);
    expect(await boundary.readSnapshot(), {'sentinel': 'public old'});
  });

  test('B7 malformed native record rejects whole snapshot safely', () async {
    final boundary = await open();
    await boundary.commitBatch(puts: {'valid': 'public value'});
    await seed([
      ['malformed', 7],
    ]);
    await expectLater(
      boundary.readSnapshot(),
      throwsA(failure(BrowserRecordFailure.invalidRecord)),
    );
    final error = const BrowserRecordException(
      BrowserRecordFailure.invalidRecord,
    );
    expect(error.toString(), 'BrowserRecordException(invalidRecord)');
  });

  test(
    'B8 snapshot limits reject row 257 and aggregate UTF8 without truncation',
    () async {
      final boundary = await open();
      await seed([
        for (var i = 0; i < 257; i++) ['$i', 'public'],
      ]);
      await expectLater(
        boundary.readSnapshot(),
        throwsA(failure(BrowserRecordFailure.limit)),
      );
      // Delete in individually valid bounded batches before the next owned seed.
      await boundary.commitBatch(deletes: {for (var i = 0; i < 256; i++) '$i'});
      await boundary.commitBatch(deletes: {'256'});
      final unicode = List<String>.filled(
        BrowserRecordBoundary.maxBytes ~/ 4,
        'é',
      ).join();
      await seed([
        ['first', unicode],
        ['second', unicode],
      ]);
      await expectLater(
        boundary.readSnapshot(),
        throwsA(failure(BrowserRecordFailure.limit)),
      );
    },
  );

  test(
    'B9 readonly snapshot remains coherent during second connection write',
    () async {
      final reader = await open();
      final writer = await open();
      await writer.commitBatch(puts: {'note': 'public old', 'journal': 'old'});
      final snapshot = reader.readSnapshot();
      final write = writer.commitBatch(
        puts: {'note': 'public new', 'journal': 'new'},
      );
      expect(await snapshot, {'note': 'public old', 'journal': 'old'});
      await write;
      expect(await reader.readSnapshot(), {
        'note': 'public new',
        'journal': 'new',
      });
    },
  );

  test(
    'B10 close fences admissions while pending native commit settles',
    () async {
      final boundary = await open();
      final pending = boundary.commitBatch(
        puts: {'note': 'public pending', 'journal': 'pending'},
      );
      boundary.close();
      await expectLater(
        boundary.commitBatch(puts: {'other': 'public'}),
        throwsA(failure(BrowserRecordFailure.closed)),
      );
      await expectLater(
        boundary.readSnapshot(),
        throwsA(failure(BrowserRecordFailure.closed)),
      );
      await pending;
      expect(await (await open()).readSnapshot(), {
        'note': 'public pending',
        'journal': 'pending',
      });
    },
  );

  test(
    'B11 version change closes connection and rejects lower version reopen',
    () async {
      final boundary = await open();
      await boundary.commitBatch(puts: {'note': 'public'});
      await _upgrade(name.toJS).toDart;
      await expectLater(
        boundary.readSnapshot(),
        throwsA(failure(BrowserRecordFailure.closed)),
      );
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openFailed)),
      );
    },
  );

  test('B12 missing store schema is refused without repair', () async {
    await _wrongSchema(name.toJS).toDart;
    await expectLater(
      BrowserRecordBoundary.open(name),
      throwsA(failure(BrowserRecordFailure.invalidSchema)),
    );
    await expectLater(
      BrowserRecordBoundary.open(''),
      throwsA(failure(BrowserRecordFailure.invalidSchema)),
    );
  });

  test(
    'B13 upgrade callback throw returns safe error and aborts schema change',
    () async {
      reset(failSchema: true);
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.invalidSchema)),
      );
      // Reopen proves recovery; owned teardown deletion proves no leaked connection.
      reset();
      final boundary = await open();
      expect(await boundary.readSnapshot(), isEmpty);
      await boundary.commitBatch(puts: {'note': 'public recovered'});
      expect(await boundary.readSnapshot(), {'note': 'public recovered'});
    },
  );
}
