@TestOn('browser')
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:atomic_notes/platform/browser_record_boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/database/note.dart';

// Test-only hooks. Every prototype alteration is exact-name scoped and restored.
const _hooks = r'''
(() => {
  const transaction = IDBDatabase.prototype.transaction;
  const put = IDBObjectStore.prototype.put;
  const add = IDBObjectStore.prototype.add;
  const create = IDBDatabase.prototype.createObjectStore;
  const objectStore = IDBTransaction.prototype.objectStore;
  const count = IDBObjectStore.prototype.count, get = IDBObjectStore.prototype.get;
  let predicateFault = '', predicateAt = 0, predicateCount = 0;
  globalThis.atomicPreimagePredicateFault = (kind, at) => { predicateFault=kind; predicateAt=at; predicateCount=0; };
  let failSnapshot = false;
  let owned = '', events = [], requestCount = 0, enqueueCount = 0;
  let abortAt = 0, throwAt = 0, cancelError = false, failSchema = false;
  globalThis.atomicPreimageReset = (name, fault, throwing, canceled, schema) => {
    predicateFault=''; predicateAt=0; predicateCount=0;
    owned = name; events = []; requestCount = 0; enqueueCount = 0; failSnapshot = false;
    abortAt = fault; throwAt = throwing; cancelError = canceled; failSchema = schema;
  };
  globalThis.atomicPreimageFailSnapshot = value => { failSnapshot = value; };
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

  IDBObjectStore.prototype.count = function (...args) {
    if (this.transaction.db.name !== owned) return count.apply(this, args);
    const selected = ++predicateCount === predicateAt;
    if (selected && predicateFault === 'throw') throw new Error('public count fault');
    const request = selected && predicateFault === 'error'
      ? add.call(this, 'public', 'error-sentinel') : count.apply(this, args);
    if (selected && predicateFault === 'error') request.addEventListener('error', event => event.preventDefault());
    if (selected && predicateFault === 'wrong') request.addEventListener('success', () => Object.defineProperty(request, 'result', {get: () => 2}));
    if (selected && predicateFault === 'abort') request.addEventListener('success', () => this.transaction.abort());
    return request;
  };
  IDBObjectStore.prototype.get = function (...args) {
    if (this.transaction.db.name === owned && args[0] !== '@atomic/context/v1' && predicateFault === 'getThrow')
      throw new Error('public get fault');
    return get.apply(this, args);
  };
  globalThis.atomicPreimageMark = value => events.push(value);
  globalThis.atomicPreimageEvents = () => JSON.stringify(events);
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
  globalThis.atomicPreimageSeed = async (name, json) => {
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
  globalThis.atomicPreimageWrongSchema = async name => {
    const db = await rawOpen(name, 1, true); db.close();
  };
  globalThis.atomicPreimageUpgrade = async name => {
    const db = await rawOpen(name, 2); db.close();
  };
  globalThis.atomicPreimageDelete = name => new Promise((resolve, reject) => {
    const request = indexedDB.deleteDatabase(name);
    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(new Error('public owned deletion failure'));
    request.onblocked = () => reject(new Error('public owned deletion blocked'));
  });
  globalThis.atomicPreimageRemaining = async name =>
    (await indexedDB.databases()).filter(db => db.name === name).length;
  globalThis.atomicPreimageRestore = () => {
    IDBDatabase.prototype.transaction = transaction;
    IDBObjectStore.prototype.put = put;
    IDBObjectStore.prototype.add = add;
    IDBDatabase.prototype.createObjectStore = create;
    IDBTransaction.prototype.objectStore = objectStore;
    IDBObjectStore.prototype.count=count; IDBObjectStore.prototype.get=get;
    predicateFault=''; predicateCount=0; predicateAt=0;
    failSnapshot = false;
    owned = '';
    return IDBDatabase.prototype.transaction === transaction &&
      IDBObjectStore.prototype.put === put && IDBObjectStore.prototype.add === add &&
      IDBDatabase.prototype.createObjectStore === create &&
      IDBTransaction.prototype.objectStore === objectStore && IDBObjectStore.prototype.count === count && IDBObjectStore.prototype.get === get && predicateFault === '' && !failSnapshot && owned === '';
  };
})();
''';

@JS('atomicPreimagePredicateFault')
external void _predicateFault(JSString kind, JSNumber at);
@JS('atomicPreimageReset')
external void _reset(
  JSString name,
  JSNumber abortAt,
  JSNumber throwAt,
  JSBoolean cancelError,
  JSBoolean failSchema,
);
@JS('atomicPreimageEvents')
external JSString _events();
@JS('atomicPreimageSeed')
external JSPromise<JSAny?> _seed(JSString name, JSString pairs);
@JS('atomicPreimageDelete')
external JSPromise<JSBoolean> _delete(JSString name);
@JS('atomicPreimageRemaining')
external JSPromise<JSNumber> _remaining(JSString name);
@JS('atomicPreimageRestore')
external JSBoolean _restore();

/// A hostile oversized map proves admission refuses before reading/copying keys.
class _OversizedPredicates extends MapBase<String, String?> {
  @override
  int get length => BrowserRecordBoundary.maxRecords + 1;
  @override
  bool get isEmpty => false;
  @override
  Iterable<String> get keys =>
      throw StateError('must never copy oversized map');
  @override
  String? operator [](Object? key) => throw StateError('must never read');
  @override
  void operator []=(String key, String? value) => throw StateError('read only');
  @override
  void clear() => throw StateError('read only');
  @override
  String? remove(Object? key) => throw StateError('read only');
}

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
    name = 'atomic-preimage-${Random.secure().nextInt(1 << 30)}-${index++}';
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
    print('ATOMIC_PREIMAGE_CLEANUP_OK');
  });

  const a1 = BrowserOwnerContext(owner: 'public-owner-a', epoch: 1);
  const b1 = BrowserOwnerContext(owner: 'public-owner-b', epoch: 1);
  Future<BrowserOwnerFence> fence() async => BrowserOwnerFence(await open());

  Future<BrowserOwnerFence> ready() async {
    final guard = await fence();
    await guard.bootstrap(a1);
    await guard.commitBatch(
      expected: a1,
      puts: {'note': 'old', 'journal': 'request-old'},
    );
    return guard;
  }

  void fault(String kind, int at) => _predicateFault(kind.toJS, at.toJS);
  test(
    'P1 actual Note and exact journal settle atomically and survive reopen',
    () async {
      final guard = await fence();
      await guard.bootstrap(a1);
      final note = Note(
        id: '00000000-0000-4000-8000-000000000001',
        title: 'Ω draft',
        body: 'public synthetic',
        dirty: true,
      );
      final raw = jsonEncode(note.toMap());
      const journal =
          '{"requestId":"00000000-0000-4000-8000-000000000002","rows":[{"payload":"public synthetic sealed"}]}';
      await guard.commitBatch(
        expected: a1,
        puts: {note.id: raw, 'journal': journal},
      );
      final accepted = note.copy();
      accepted.serverVersion = 3;
      accepted.syncedSig = note.contentSig;
      accepted.dirty = false;
      await guard.compareAndCommit(
        expected: a1,
        expectedRecords: {note.id: raw, 'journal': journal},
        puts: {note.id: jsonEncode(accepted.toMap())},
        deletes: {'journal'},
      );
      for (final connection in connections) {
        connection.close();
      }
      final rows = await (await fence()).readSnapshot(a1);
      expect(rows.containsKey('journal'), isFalse);
      final restored = Note.fromMap(
        jsonDecode(rows[note.id]!) as Map<String, dynamic>,
      );
      expect(restored.contentSig, note.contentSig);
      expect(restored.dirty, isFalse);
      expect(restored.serverVersion, 3);
      expect(restored.syncedSig, note.contentSig);
    },
  );
  test(
    'P2 changed note aborts all journal deletion and note mutations',
    () async {
      final guard = await ready();
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'stale', 'journal': 'request-old'},
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P3 replaced journal aborts settlement without clearing dirty work',
    () async {
      final guard = await ready();
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old', 'journal': 'request-stale'},
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P4 absence admits insert but native NULL is present and never overwritten',
    () async {
      final guard = await ready();
      await guard.compareAndCommit(
        expected: a1,
        expectedRecords: {'new': null},
        inserts: {'new': 'public'},
      );
      await seed([
        ['native-null', null],
      ]);
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'native-null': null},
          puts: {'native-null': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'native-null': 'text'},
          puts: {'native-null': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.invalidRecord)),
      );
      await expectLater(
        guard.readSnapshot(a1),
        throwsA(failure(BrowserRecordFailure.invalidRecord)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'native-null': null},
          puts: {'native-null': 'still lost'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
    },
  );
  test(
    'P5 missing string record and invalid native count fail safely',
    () async {
      final guard = await ready();
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'missing': 'old'},
          puts: {'missing': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      fault('wrong', 1);
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'new': null},
          puts: {'new': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.invalidRecord)),
      );
      reset();
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P6 missing malformed and foreign contexts retain exact records',
    () async {
      final boundary = await open();
      final guard = BrowserOwnerFence(boundary);
      await boundary.commitBatch(puts: {'note': 'old'});
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old'},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.missingContext)),
      );
      await boundary.commitBatch(puts: {BrowserOwnerFence.contextKey: 'bad'});
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old'},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.malformedContext)),
      );
      expect(await boundary.readSnapshot(), {
        'note': 'old',
        BrowserOwnerFence.contextKey: 'bad',
      });
      await boundary.commitBatch(deletes: {BrowserOwnerFence.contextKey});
      await boundary.commitBatch(deletes: {'note'});
      await guard.bootstrap(a1);
      await expectLater(
        guard.compareAndCommit(
          expected: b1,
          expectedRecords: {'new': null},
          puts: {'new': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
      expect(await guard.readSnapshot(a1), isEmpty);
    },
  );
  test(
    'P7 invalid predicates namespaces and UTF8 limits admit no transaction',
    () async {
      final guard = await ready();
      reset();
      for (final predicates in <Map<String, String?>>[
        {},
        {'dependency': 'x'},
        {'': 'x'},
        {for (var i = 0; i < 257; i++) 'key-$i': null},
      ]) {
        await expectLater(
          guard.compareAndCommit(
            expected: a1,
            expectedRecords: predicates,
            puts: {'note': 'lost'},
          ),
          throwsA(failure(BrowserRecordFailure.invalidPreimages)),
        );
      }
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'@atomic/other': null},
          puts: {'@atomic/other': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.reservedKey)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {
            'note': 'Ω' * (BrowserRecordBoundary.maxBytes ~/ 2 + 1),
          },
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.limit)),
      );
      expect(observed(), isEmpty);
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P8 dependency preimages are checked without mutating dependency records',
    () async {
      final guard = await ready();
      await guard.compareAndCommit(
        expected: a1,
        expectedRecords: {'note': 'old', 'journal': 'request-old'},
        puts: {'note': 'new'},
      );
      expect(await guard.readSnapshot(a1), {
        'note': 'new',
        'journal': 'request-old',
      });
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'new', 'journal': 'wrong'},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      expect(await guard.readSnapshot(a1), {
        'note': 'new',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P9 second connection edit before settlement preserves newer note and journal',
    () async {
      final first = await ready(), second = await fence();
      final edit = second.commitBatch(
        expected: a1,
        puts: {'note': 'new dirty revision'},
      );
      final rejected = expectLater(
        first.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old', 'journal': 'request-old'},
          puts: {'note': 'clean old'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      await edit;
      await rejected;
      expect(await first.readSnapshot(a1), {
        'note': 'new dirty revision',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P10 second connection pending replacement cannot be deleted by stale receipt',
    () async {
      final first = await ready(), second = await fence();
      final replacement = second.commitBatch(
        expected: a1,
        puts: {'journal': 'request-new'},
      );
      final rejected = expectLater(
        first.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old', 'journal': 'request-old'},
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
      await replacement;
      await rejected;
      expect(await first.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-new',
      });
    },
  );
  test(
    'P11 settlement before second connection edit leaves newest edit intact',
    () async {
      final first = await ready(), second = await fence();
      final settlement = first.compareAndCommit(
        expected: a1,
        expectedRecords: {'note': 'old', 'journal': 'request-old'},
        puts: {'note': 'accepted'},
        deletes: {'journal'},
      );
      final edit = second.commitBatch(
        expected: a1,
        puts: {'note': 'new dirty'},
      );
      await settlement;
      await edit;
      expect(await first.readSnapshot(a1), {'note': 'new dirty'});
    },
  );
  test(
    'P12 canceled count request error explicitly aborts all mutation admission',
    () async {
      final guard = await ready();
      await guard.commitBatch(
        expected: a1,
        puts: {'error-sentinel': 'retained'},
      );
      fault('error', 1);
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old', 'journal': 'request-old'},
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.request)),
      );
      reset();
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
        'error-sentinel': 'retained',
      });
    },
  );
  test(
    'P13 synchronous count or value enqueue throw aborts whole comparison',
    () async {
      final guard = await ready();
      for (final kind in ['throw', 'getThrow']) {
        fault(kind, 2);
        await expectLater(
          guard.compareAndCommit(
            expected: a1,
            expectedRecords: {'note': 'old', 'journal': 'request-old'},
            puts: {'note': 'lost'},
            deletes: {'journal'},
          ),
          throwsA(failure(BrowserRecordFailure.enqueue)),
        );
        reset();
        expect(await guard.readSnapshot(a1), {
          'note': 'old',
          'journal': 'request-old',
        });
      }
    },
  );
  test(
    'P14 abort on final comparison cannot acknowledge or apply writes',
    () async {
      final guard = await ready();
      fault('abort', 2);
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'first': null, 'second': null},
          puts: {'first': 'lost', 'second': 'lost'},
        ),
        throwsA(isA<BrowserRecordException>()),
      );
      reset();
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P15 late write abort and partial enqueue failure preserve all old records',
    () async {
      final guard = await ready();
      for (final late in [true, false]) {
        reset(abortAt: late ? 2 : 0, throwAt: late ? 0 : 2);
        await expectLater(
          guard.compareAndCommit(
            expected: a1,
            expectedRecords: {'note': 'old', 'journal': 'request-old'},
            puts: {'note': 'lost', 'journal': 'lost'},
          ),
          throwsA(
            failure(
              late
                  ? BrowserRecordFailure.aborted
                  : BrowserRecordFailure.enqueue,
            ),
          ),
        );
        reset();
        expect(await (await fence()).readSnapshot(a1), {
          'note': 'old',
          'journal': 'request-old',
        });
      }
    },
  );
  test(
    'P16 closed connection fences conditional admissions and prepared inputs detach',
    () async {
      final guard = await ready();
      final predicates = {'note': 'old', 'journal': 'request-old'};
      final puts = {'note': 'new'};
      final settled = guard.compareAndCommit(
        expected: a1,
        expectedRecords: predicates,
        puts: puts,
      );
      predicates['note'] = 'wrong';
      puts['note'] = 'wrong';
      await settled;
      expect(await guard.readSnapshot(a1), {
        'note': 'new',
        'journal': 'request-old',
      });
      connections.last.close();
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'new'},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.closed)),
      );
    },
  );

  test(
    'P17 oversized map refuses before copy and invalid context admits no transaction',
    () async {
      final guard = await ready();
      reset();
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: _OversizedPredicates(),
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.invalidPreimages)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: const BrowserOwnerContext(owner: '', epoch: 1),
          expectedRecords: {'note': 'old'},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.invalidContext)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'x' * (BrowserRecordBoundary.maxBytes + 1)},
          puts: {'note': 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.limit)),
      );
      expect(observed(), isEmpty);
      expect(await guard.readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test(
    'P18 stale epoch after concurrent transition preserves note and journal',
    () async {
      final first = await ready(), second = await fence();
      const next = BrowserOwnerContext(owner: 'public-owner-a', epoch: 2);
      final transition = second.transition(expected: a1, next: next);
      final rejected = expectLater(
        first.compareAndCommit(
          expected: a1,
          expectedRecords: {'note': 'old', 'journal': 'request-old'},
          puts: {'note': 'lost'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.contextMismatch)),
      );
      await transition;
      await rejected;
      expect(await first.readSnapshot(next), {
        'note': 'old',
        'journal': 'request-old',
      });
    },
  );
  test('P19 native object is never coerced into a string preimage', () async {
    final guard = await ready();
    await seed([
      [
        'object',
        {'public': 'synthetic'},
      ],
      ['number', 7],
    ]);
    for (final key in ['object', 'number']) {
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {key: '[object Object]'},
          puts: {key: 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.invalidRecord)),
      );
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {key: null},
          puts: {key: 'lost'},
        ),
        throwsA(failure(BrowserRecordFailure.preimageMismatch)),
      );
    }
  });
  test(
    'P20 canceled mutation error aborts earlier writes and journal deletion',
    () async {
      final guard = await ready();
      await guard.commitBatch(expected: a1, puts: {'duplicate': 'retained'});
      reset(cancelError: true);
      await expectLater(
        guard.compareAndCommit(
          expected: a1,
          expectedRecords: {
            'note': 'old',
            'journal': 'request-old',
            'duplicate': 'retained',
          },
          puts: {'note': 'lost'},
          inserts: {'duplicate': 'collision'},
          deletes: {'journal'},
        ),
        throwsA(failure(BrowserRecordFailure.request)),
      );
      expect(observed(), contains('canceled-error'));
      reset();
      expect(await (await fence()).readSnapshot(a1), {
        'note': 'old',
        'journal': 'request-old',
        'duplicate': 'retained',
      });
    },
  );
}
