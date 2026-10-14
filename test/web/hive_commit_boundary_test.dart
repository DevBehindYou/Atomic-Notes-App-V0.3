@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:atomic_notes/database/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

// Test-only observation/fault injection. No application entrypoint imports this.
// Hooks affect only the generated namespace, and original methods are restored.
const _hooks = r'''
(() => {
  const transaction = IDBDatabase.prototype.transaction;
  const put = IDBObjectStore.prototype.put;
  let prefix = '', events = [], count = 0, abortAt = 0, settlement;
  let finish;
  globalThis.atomicW2Reset = (name, fault) => {
    prefix = name; events = []; count = 0; abortAt = fault;
    settlement = new Promise(resolve => { finish = resolve; });
  };
  IDBDatabase.prototype.transaction = function (...args) {
    const txn = transaction.apply(this, args);
    if (this.name.includes(prefix) && prefix && txn.mode === 'readwrite') {
      txn.addEventListener('complete', () => {
        events.push('complete'); finish('complete');
      });
      txn.addEventListener('abort', () => {
        events.push('abort'); finish('abort');
      });
    }
    return txn;
  };
  IDBObjectStore.prototype.put = function (...args) {
    const request = put.apply(this, args);
    const txn = this.transaction;
    if (txn.db.name.includes(prefix) && prefix) {
      request.addEventListener('success', () => {
        events.push('request');
        if (++count === abortAt) txn.abort();
      });
    }
    return request;
  };
  globalThis.atomicW2MarkFuture = () => { events.push('future'); };
  globalThis.atomicW2MarkFlush = () => { events.push('flush'); };
  globalThis.atomicW2Events = () => JSON.stringify(events);
  globalThis.atomicW2Settlement = () => settlement;
  globalThis.atomicW2Remaining = async name =>
    (await indexedDB.databases()).filter(db => db.name.includes(name)).length;
  globalThis.atomicW2Restore = () => {
    IDBDatabase.prototype.transaction = transaction;
    IDBObjectStore.prototype.put = put;
    prefix = '';
    return IDBDatabase.prototype.transaction === transaction &&
      IDBObjectStore.prototype.put === put && prefix === '';
  };
})();
''';

@JS('atomicW2Reset')
external void _reset(JSString name, JSNumber abortAt);
@JS('atomicW2MarkFuture')
external void _markFuture();
@JS('atomicW2MarkFlush')
external void _markFlush();
@JS('atomicW2Events')
external JSString _events();
@JS('atomicW2Settlement')
external JSPromise<JSString> _settlement();
@JS('atomicW2Remaining')
external JSPromise<JSNumber> _remaining(JSString name);
@JS('atomicW2Restore')
external JSBoolean _restore();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final names = <String>[];
  late String name;
  late Box<dynamic> box;
  setUp(() async {
    name = 'atomic-w2-${Random.secure().nextInt(1 << 30)}-${names.length}';
    names.add(name);
    globalContext.callMethod<JSAny?>('eval'.toJS, _hooks.toJS);
    box = await Hive.openBox<dynamic>(name);
    _reset(name.toJS, 0.toJS);
  });
  tearDown(() async {
    try {
      await Hive.close();
      await Hive.deleteBoxFromDisk(name);
      expect((await _remaining(name.toJS).toDart).toDartInt, 0);
    } finally {
      expect(_restore().toDart, isTrue);
    }
    // Receipt requires owned deletion AND verified native-method restoration.
    // Never include namespace, stored records or errors.
    // ignore: avoid_print
    print('ATOMIC_W2_CLEANUP_OK');
  });

  List<dynamic> observed() => jsonDecode(_events().toDart) as List<dynamic>;
  Note draft(String id) => Note(
    id: id,
    title: 'Public synthetic Ω note',
    kind: NoteKind.todo,
    items: [TodoItem(text: 'Public task', done: true)],
    dirty: true,
    pinned: true,
    serverVersion: 3,
    syncedSig: 'public-synthetic-signature',
    createdAt: DateTime.utc(2026, 10, 14),
    updatedAt: DateTime.utc(2026, 10, 14),
  );

  test('W2 committed Note map survives graceful close and reopen', () async {
    final note = draft('public-note-1');
    await box.put(note.id, note.toMap());
    _markFuture();
    expect((await _settlement().toDart).toDart, 'complete');
    final order = observed();
    expect(order.indexOf('request'), lessThan(order.indexOf('future')));
    expect(order.indexOf('future'), lessThan(order.indexOf('complete')));
    await box.close();
    box = await Hive.openBox<dynamic>(name);
    final reloaded = Note.fromMap(box.get(note.id) as Map);
    expect(reloaded.toMap(), note.toMap());
    expect(reloaded.contentSig, note.contentSig);
  });

  test(
    'W2 request success and flush do not promise a committed write',
    () async {
      final note = draft('public-note-2');
      _reset(name.toJS, 1.toJS);
      await box.put(note.id, note.toMap());
      _markFuture();
      await box.flush();
      _markFlush();
      expect((await _settlement().toDart).toDart, 'abort');
      final order = observed();
      expect(order, ['request', 'future', 'flush', 'abort']);
      // Existing Box memory reports success, but the native transaction aborted.
      expect(box.get(note.id), note.toMap());
      expect(note.dirty, isTrue); // Caller still owns an exportable draft.
      await box.close();
      box = await Hive.openBox<dynamic>(name);
      expect(box.containsKey(note.id), isFalse);
      expect(note.toMap()['title'], 'Public synthetic Ω note');
    },
  );

  test(
    'W2 late putAll abort retains neither synthetic note on reopen',
    () async {
      final a = draft('public-note-a');
      final b = draft('public-note-b');
      _reset(name.toJS, 2.toJS);
      await box.putAll({a.id: a.toMap(), b.id: b.toMap()});
      _markFuture();
      expect((await _settlement().toDart).toDart, 'abort');
      expect(observed(), ['request', 'request', 'future', 'abort']);
      await box.close();
      box = await Hive.openBox<dynamic>(name);
      expect(box.containsKey(a.id), isFalse);
      expect(box.containsKey(b.id), isFalse);
      expect(a.dirty && b.dirty, isTrue);
    },
  );
}
