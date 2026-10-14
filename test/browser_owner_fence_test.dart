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
  const objectStore = IDBTransaction.prototype.objectStore;
  let failSnapshot = false;
  let owned = '', events = [], requestCount = 0, enqueueCount = 0;
  let abortAt = 0, throwAt = 0, cancelError = false, failSchema = false;
  globalThis.atomicFenceReset = (name, fault, throwing, canceled, schema) => {
    owned = name; events = []; requestCount = 0; enqueueCount = 0; failSnapshot = false;
    abortAt = fault; throwAt = throwing; cancelError = canceled; failSchema = schema;
  };
  globalThis.atomicFenceFailSnapshot = value => { failSnapshot = value; };
  IDBTransaction.prototype.objectStore = function (...args) {
    if (this.db.name === owned && this.mode === 'readonly' && failSnapshot)
      throw new Error('public snapshot enqueue fault');
    return objectStore.apply(this, args);
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
  globalThis.atomicFenceMark = value => events.push(value);
  globalThis.atomicFenceEvents = () => JSON.stringify(events);
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
  globalThis.atomicFenceSeed = async (name, json) => {
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
  globalThis.atomicFenceWrongSchema = async name => {
    const db = await rawOpen(name, 1, true); db.close();
  };
  globalThis.atomicFenceUpgrade = async name => {
    const db = await rawOpen(name, 2); db.close();
  };
  globalThis.atomicFenceDelete = name => new Promise((resolve, reject) => {
    const request = indexedDB.deleteDatabase(name);
    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(new Error('public owned deletion failure'));
    request.onblocked = () => reject(new Error('public owned deletion blocked'));
  });
  globalThis.atomicFenceRemaining = async name =>
    (await indexedDB.databases()).filter(db => db.name === name).length;
  globalThis.atomicFenceRestore = () => {
    IDBDatabase.prototype.transaction = transaction;
    IDBObjectStore.prototype.put = put;
    IDBObjectStore.prototype.add = add;
    IDBDatabase.prototype.createObjectStore = create;
    IDBTransaction.prototype.objectStore = objectStore;
    failSnapshot = false;
    owned = '';
    return IDBDatabase.prototype.transaction === transaction &&
      IDBObjectStore.prototype.put === put && IDBObjectStore.prototype.add === add &&
      IDBDatabase.prototype.createObjectStore === create &&
      IDBTransaction.prototype.objectStore === objectStore && !failSnapshot && owned === '';
  };
})();
''';

@JS('atomicFenceFailSnapshot')
external void _failSnapshot(JSBoolean value);
@JS('atomicFenceReset')
external void _reset(
  JSString name,
  JSNumber abortAt,
  JSNumber throwAt,
  JSBoolean cancelError,
  JSBoolean failSchema,
);
@JS('atomicFenceEvents')
external JSString _events();
@JS('atomicFenceSeed')
external JSPromise<JSAny?> _seed(JSString name, JSString pairs);
@JS('atomicFenceDelete')
external JSPromise<JSBoolean> _delete(JSString name);
@JS('atomicFenceRemaining')
external JSPromise<JSNumber> _remaining(JSString name);
@JS('atomicFenceRestore')
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
    name = 'atomic-fence-${Random.secure().nextInt(1 << 30)}-${index++}';
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
    print('ATOMIC_FENCE_CLEANUP_OK');
  });

  const a1 = BrowserOwnerContext(owner: 'public-owner-a', epoch: 1);
  const a2 = BrowserOwnerContext(owner: 'public-owner-a', epoch: 2);
  const b1 = BrowserOwnerContext(owner: 'public-owner-b', epoch: 1);
  Future<BrowserOwnerFence> fence() async => BrowserOwnerFence(await open());

  test(
    'F1 empty bootstrap and guarded commit survive reopen without internal row',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      await guard.commitBatch(
        expected: a1,
        puts: {'note': 'public Ω draft', 'journal': 'public prepared'},
      );
      for (final connection in connections) {
        connection.close();
      }
      final snapshot = await (await fence()).readSnapshot(a1);
      expect(snapshot, {
        'note': 'public Ω draft',
        'journal': 'public prepared',
      });
      expect(() => snapshot['note'] = 'changed', throwsUnsupportedError);
    },
  );

  test(
    'F2 missing context refuses writes and reads and retains existing rows',
    () async {
      final boundary = await open();
      await boundary.commitBatch(puts: {'note': 'retained public draft'});
      final guard = BrowserOwnerFence(boundary);
      await expectLater(
        guard.commitBatch(expected: a1, puts: {'note': 'lost'}),
        throwsA(failure(BrowserRecordFailure.missingContext)),
      );
      await expectLater(
        guard.readSnapshot(a1),
        throwsA(failure(BrowserRecordFailure.missingContext)),
      );
      await expectLater(
        guard.bootstrap(a1),
        throwsA(failure(BrowserRecordFailure.bootstrapRefused)),
      );
      expect(await boundary.readSnapshot(), {'note': 'retained public draft'});
    },
  );

  test(
    'F3 malformed context refuses all access without modifying exact rows',
    () async {
      final boundary = await open();
      final guard = BrowserOwnerFence(boundary);
      for (final value in [
        'invalid-json',
        '{"schema":1,"schema":1,"owner":"public-owner-a","epoch":1}',
        '{"schema":1,"owner":"public-owner-a","owner":"public-owner-a","epoch":1}',
        '{"schema":1.0,"owner":"public-owner-a","epoch":1}',
        '{ "schema":1,"owner":"public-owner-a","epoch":1}',
        '{"owner":"public-owner-a","schema":1,"epoch":1}',
        '{}',
        '{"schema":2,"owner":"public-owner-a","epoch":1}',
        '{"schema":1,"owner":"public-owner-a","epoch":0}',
        '{"schema":1,"owner":"public-owner-a","epoch":1,"extra":true}',
      ]) {
        final records = {
          BrowserOwnerFence.contextKey: value,
          'note': 'retained public',
        };
        await boundary.commitBatch(puts: records);
        await expectLater(
          guard.commitBatch(expected: a1, deletes: {'note'}),
          throwsA(failure(BrowserRecordFailure.malformedContext)),
        );
        await expectLater(
          guard.readSnapshot(a1),
          throwsA(failure(BrowserRecordFailure.malformedContext)),
        );
        await expectLater(
          guard.bootstrap(a1),
          throwsA(failure(BrowserRecordFailure.bootstrapRefused)),
        );
        expect(await boundary.readSnapshot(), records);
      }
      await seed([
        [BrowserOwnerFence.contextKey, 7],
      ]);
      await expectLater(
        guard.readSnapshot(a1),
        throwsA(failure(BrowserRecordFailure.malformedContext)),
      );
    },
  );

  test(
    'F4 duplicate bootstrap and concurrent two-owner bootstrap preserve first owner',
    () async {
      final first = await fence(), second = await fence();
      final accepted = first.bootstrap(a1);
      final refused = expectLater(
        second.bootstrap(b1),
        throwsA(failure(BrowserRecordFailure.bootstrapRefused)),
      );
      await accepted;
      await refused;
      await expectLater(
        first.bootstrap(a1),
        throwsA(failure(BrowserRecordFailure.bootstrapRefused)),
      );
      expect(await first.readSnapshot(a1), isEmpty);
      await expectLater(
        second.readSnapshot(b1),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
    },
  );

  test(
    'F5 stale owner and epoch cannot overwrite insert delete or disclose rows',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      await guard.commitBatch(
        expected: a1,
        puts: {'note': 'retained', 'journal': 'sealed'},
      );
      for (final stale in [b1, a2]) {
        await expectLater(
          guard.commitBatch(
            expected: stale,
            puts: {'note': 'lost'},
            inserts: {'extra': 'new'},
            deletes: {'journal'},
          ),
          throwsA(failure(BrowserRecordFailure.contextMismatch)),
        );
        await expectLater(
          guard.readSnapshot(stale),
          throwsA(failure(BrowserRecordFailure.contextMismatch)),
        );
        expect(await guard.readSnapshot(a1), {
          'note': 'retained',
          'journal': 'sealed',
        });
      }
    },
  );

  test(
    'F6 reserved namespace and invalid contexts admit no transaction or mutation',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      await guard.commitBatch(expected: a1, puts: {'note': 'retained'});
      reset();
      for (final operation in [0, 1, 2]) {
        await expectLater(
          guard.commitBatch(
            expected: a1,
            puts: operation == 0
                ? {'@atomic/other': 'bad', 'note': 'lost'}
                : {},
            inserts: operation == 1
                ? {BrowserOwnerFence.contextKey: 'bad'}
                : {},
            deletes: operation == 2 ? {BrowserOwnerFence.contextKey} : {},
          ),
          throwsA(failure(BrowserRecordFailure.reservedKey)),
        );
      }
      for (final invalid in [
        const BrowserOwnerContext(owner: '', epoch: 1),
        const BrowserOwnerContext(owner: 'a', epoch: 0),
        const BrowserOwnerContext(owner: 'a', epoch: 9007199254740992),
        BrowserOwnerContext(owner: 'Ω' * 65, epoch: 1),
      ]) {
        await expectLater(
          guard.commitBatch(expected: invalid, puts: {'note': 'lost'}),
          throwsA(failure(BrowserRecordFailure.invalidContext)),
        );
        await expectLater(
          guard.bootstrap(invalid),
          throwsA(failure(BrowserRecordFailure.invalidContext)),
        );
      }
      expect(observed(), isEmpty);
      expect(await guard.readSnapshot(a1), {'note': 'retained'});
    },
  );

  test(
    'F7 same-owner epoch transition preserves note journal and dirty state',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      await guard.commitBatch(
        expected: a1,
        puts: {'note': '{"dirty":true}', 'journal': 'old prepared request'},
      );
      await guard.transition(expected: a1, next: a2);
      await expectLater(
        guard.commitBatch(
          expected: a1,
          puts: {'note': '{"dirty":false}'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
      expect(await guard.readSnapshot(a2), {
        'note': '{"dirty":true}',
        'journal': 'old prepared request',
      });
    },
  );

  test(
    'F8 cross-owner nonincrement and overflow transitions retain owner and rows',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      await guard.commitBatch(expected: a1, puts: {'note': 'retained'});
      for (final next in [
        b1,
        a1,
        const BrowserOwnerContext(owner: 'public-owner-a', epoch: 3),
      ]) {
        await expectLater(
          guard.transition(expected: a1, next: next),
          throwsA(failure(BrowserRecordFailure.transitionRefused)),
        );
      }
      const last = BrowserOwnerContext(
        owner: 'public-owner-a',
        epoch: BrowserOwnerContext.maxEpoch,
      );
      await expectLater(
        guard.transition(expected: last, next: last),
        throwsA(failure(BrowserRecordFailure.transitionRefused)),
      );
      expect(await guard.readSnapshot(a1), {'note': 'retained'});
    },
  );

  test(
    'F9 transition before second-connection stale write rejects whole batch',
    () async {
      final first = await fence(), second = await fence();
      await first.bootstrap(a1);
      await first.commitBatch(
        expected: a1,
        puts: {'note': 'retained', 'journal': 'retained sealed'},
      );
      final transition = first.transition(expected: a1, next: a2);
      final refused = expectLater(
        second.commitBatch(
          expected: a1,
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
      await transition;
      await refused;
      expect(await second.readSnapshot(a2), {
        'note': 'retained',
        'journal': 'retained sealed',
      });
    },
  );

  test(
    'F10 write before second-connection transition commits then preserves new rows',
    () async {
      final first = await fence(), second = await fence();
      await first.bootstrap(a1);
      final write = first.commitBatch(
        expected: a1,
        puts: {'note': 'new public', 'journal': 'new sealed'},
      );
      final transition = second.transition(expected: a1, next: a2);
      await write;
      await transition;
      expect(await first.readSnapshot(a2), {
        'note': 'new public',
        'journal': 'new sealed',
      });
    },
  );

  test(
    'F11 concurrent same-epoch transitions have exactly one winner',
    () async {
      final first = await fence(), second = await fence();
      await first.bootstrap(a1);
      final accepted = first.transition(expected: a1, next: a2);
      final refused = expectLater(
        second.transition(expected: a1, next: a2),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
      await accepted;
      await refused;
      await second.commitBatch(expected: a2, puts: {'note': 'winner retained'});
      expect(await first.readSnapshot(a2), {'note': 'winner retained'});
    },
  );

  test(
    'F12 late abort rolls back bootstrap transition and guarded batch completely',
    () async {
      final guard = await fence();
      reset(abortAt: 1);
      await expectLater(
        guard.bootstrap(a1),
        throwsA(failure(BrowserRecordFailure.aborted)),
      );
      expect(await connections.last.readSnapshot(), isEmpty);
      reset();
      await guard.bootstrap(a1);
      await guard.commitBatch(
        expected: a1,
        puts: {'note': 'retained', 'journal': 'retained sealed'},
      );
      reset(abortAt: 1);
      await expectLater(
        guard.transition(expected: a1, next: a2),
        throwsA(failure(BrowserRecordFailure.aborted)),
      );
      expect(await guard.readSnapshot(a1), {
        'note': 'retained',
        'journal': 'retained sealed',
      });
      reset(abortAt: 2);
      await expectLater(
        guard.commitBatch(
          expected: a1,
          puts: {'note': 'lost', 'journal': 'lost sealed'},
        ),
        throwsA(failure(BrowserRecordFailure.aborted)),
      );
      reset();
      expect(await (await fence()).readSnapshot(a1), {
        'note': 'retained',
        'journal': 'retained sealed',
      });
    },
  );

  test(
    'F13 guarded snapshot allows 256 domain rows and refuses 257 without truncation',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      final records = {for (var i = 0; i < 256; i++) 'row-$i': 'public'};
      await guard.commitBatch(expected: a1, puts: records);
      expect(await guard.readSnapshot(a1), records);
      await guard.commitBatch(expected: a1, puts: {'row-256': 'public'});
      await expectLater(
        guard.readSnapshot(a1),
        throwsA(failure(BrowserRecordFailure.limit)),
      );
    },
  );

  test('F14 closed connection refuses every guarded admission', () async {
    final boundary = await open();
    final guard = BrowserOwnerFence(boundary);
    await guard.bootstrap(a1);
    boundary.close();
    await expectLater(
      guard.bootstrap(a1),
      throwsA(failure(BrowserRecordFailure.closed)),
    );
    await expectLater(
      guard.transition(expected: a1, next: a2),
      throwsA(failure(BrowserRecordFailure.closed)),
    );
    await expectLater(
      guard.commitBatch(expected: a1, puts: {'note': 'lost'}),
      throwsA(failure(BrowserRecordFailure.closed)),
    );
    await expectLater(
      guard.readSnapshot(a1),
      throwsA(failure(BrowserRecordFailure.closed)),
    );
  });
  test(
    'F15 synchronous snapshot enqueue failure returns safe error and retains rows',
    () async {
      final boundary = await open();
      final guard = BrowserOwnerFence(boundary);
      await guard.bootstrap(a1);
      await guard.commitBatch(expected: a1, puts: {'note': 'retained public'});
      _failSnapshot(true.toJS);
      await expectLater(
        boundary.readSnapshot(),
        throwsA(failure(BrowserRecordFailure.enqueue)),
      );
      await expectLater(
        guard.readSnapshot(a1),
        throwsA(failure(BrowserRecordFailure.enqueue)),
      );
      _failSnapshot(false.toJS);
      expect(await guard.readSnapshot(a1), {'note': 'retained public'});
    },
  );
}
