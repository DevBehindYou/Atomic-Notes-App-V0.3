@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:atomic_notes/platform/browser_record_boundary.dart';
import 'package:flutter_test/flutter_test.dart';

// CI test-only interception. No application module imports these hooks.
const _hooks = r'''
(() => {
  const factory = indexedDB, nativeOpen = IDBFactory.prototype.open;
  const ownDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'indexedDB');
  const connections = new Set(), events = [], waiters = [];
  let owned = '', fault = '', keep = false, heldRequest = null;
  let keepCount = 0, deadline = 0, pendingDelete = null;
  const bounded = promise => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('public owned wait bound')), 10000);
    promise.then(value => { clearTimeout(timer); resolve(value); },
      error => { clearTimeout(timer); reject(error); });
  });
  const mark = value => {
    events.push(value);
    for (const waiter of [...waiters]) if (waiter.value === value) {
      waiters.splice(waiters.indexOf(waiter), 1); waiter.resolve(true);
    }
  };
  const wait = value => events.includes(value) ? Promise.resolve(true) :
    bounded(new Promise(resolve => waiters.push({value, resolve})));
  const rawOpen = name => bounded(new Promise((resolve, reject) => {
    const request = nativeOpen.call(factory, name, 1);
    request.onupgradeneeded = () => request.result.createObjectStore('records');
    request.onsuccess = () => {
      connections.add(request.result); resolve(request.result);
    };
    request.onerror = () => reject(new Error('public owned seed open failure'));
  }));
  IDBFactory.prototype.open = function (name, ...args) {
    if (name === owned && fault === 'open-denied')
      throw new DOMException('public synthetic denial', 'SecurityError');
    const request = nativeOpen.call(this, name, ...args);
    if (name === owned) {
      request.addEventListener('upgradeneeded', () => mark('late-upgrade'));
      request.addEventListener('success', () => {
        connections.add(request.result); mark('late-success');
      });
      request.addEventListener('error', () => mark('late-error'));
    }
    return request;
  };
  globalThis.atomicOpenReset = name => { owned = name; };
  globalThis.atomicOpenDeleteQueue = async () => {
    const db = await rawOpen(owned);
    db.onversionchange = () => {}; // Actual native deletion must wait for it.
    pendingDelete = bounded(new Promise((resolve, reject) => {
      const request = factory.deleteDatabase(owned);
      request.onblocked = () => mark('delete-blocked');
      request.onsuccess = () => { mark('delete-complete'); resolve(true); };
      request.onerror = () => reject(new Error('public owned queued delete error'));
    }));
    // Attach a rejection observer immediately; later teardown still awaits it.
    pendingDelete.catch(() => {});
    await wait('delete-blocked');
  };
  globalThis.atomicOpenHoldUpgrade = () => bounded(new Promise((resolve, reject) => {
    const request = nativeOpen.call(factory, owned, 1);
    heldRequest = request; keep = true; keepCount = 0; deadline = performance.now() + 14000;
    request.onupgradeneeded = () => {
      const db = request.result; connections.add(db);
      const store = db.createObjectStore('records');
      const again = () => {
        if (!keep) return;
        if (++keepCount > 500000 || performance.now() > deadline) {
          keep = false; mark('keepalive-bound'); return;
        }
        const read = store.get('public-unused');
        read.onsuccess = again;
        read.onerror = () => { keep = false; mark('keepalive-error'); };
      };
      again(); mark('upgrade-held'); resolve(true);
    };
    request.onsuccess = () => {
      request.result.close(); mark('held-upgrade-complete');
    };
    request.onerror = () => {
      mark('held-upgrade-error'); reject(new Error('public held upgrade error'));
    };
  }));
  globalThis.atomicOpenRelease = () => {
    keep = false;
    for (const db of connections) db.close();
  };
  globalThis.atomicOpenWait = wait;
  globalThis.atomicOpenEvents = () => JSON.stringify(events);
  globalThis.atomicOpenFault = mode => {
    fault = mode;
    if (mode === 'unavailable' || mode === 'getter-denied')
      Object.defineProperty(globalThis, 'indexedDB', { configurable: true, get: () => {
        if (mode === 'getter-denied')
          throw new DOMException('public synthetic getter denial', 'SecurityError');
        return null;
      }});
  };
  globalThis.atomicOpenRestore = () => {
    IDBFactory.prototype.open = nativeOpen;
    if (ownDescriptor) Object.defineProperty(globalThis, 'indexedDB', ownDescriptor);
    else delete globalThis.indexedDB;
    fault = ''; owned = '';
    const restored = Object.getOwnPropertyDescriptor(globalThis, 'indexedDB');
    return IDBFactory.prototype.open === nativeOpen && indexedDB === factory &&
      (ownDescriptor ? restored.get === ownDescriptor.get &&
        restored.value === ownDescriptor.value && restored.configurable === ownDescriptor.configurable :
        restored === undefined);
  };
  const deleteOwned = async name => {
    await bounded(new Promise((resolve, reject) => {
      const request = factory.deleteDatabase(name);
      request.onblocked = () => reject(new Error('public leaked owned connection'));
      request.onerror = () => reject(new Error('public owned cleanup error'));
      request.onsuccess = () => resolve(true);
    }));
    return (await factory.databases()).filter(db => db.name === name).length === 0;
  };
  globalThis.atomicOpenDeleteWithoutClosing = deleteOwned;
  globalThis.atomicOpenCleanup = async name => {
    keep = false;
    for (const db of connections) db.close();
    if (pendingDelete) await pendingDelete;
    return deleteOwned(name);
  };
  globalThis.atomicOpenAbsent = async name =>
    (await factory.databases()).filter(db => db.name === name).length === 0;
})();
''';

@JS('atomicOpenReset')
external void _reset(JSString name);
@JS('atomicOpenDeleteQueue')
external JSPromise<JSAny?> _deleteQueue();
@JS('atomicOpenHoldUpgrade')
external JSPromise<JSAny?> _holdUpgrade();
@JS('atomicOpenRelease')
external void _release();
@JS('atomicOpenWait')
external JSPromise<JSBoolean> _wait(JSString event);
@JS('atomicOpenEvents')
external JSString _events();
@JS('atomicOpenFault')
external void _fault(JSString mode);
@JS('atomicOpenRestore')
external JSBoolean _restore();
@JS('atomicOpenCleanup')
external JSPromise<JSBoolean> _cleanup(JSString name);
@JS('atomicOpenAbsent')
external JSPromise<JSBoolean> _absent(JSString name);
@JS('atomicOpenDeleteWithoutClosing')
external JSPromise<JSBoolean> _deleteWithoutClosing(JSString name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String name;
  var index = 0;
  final boundaries = <BrowserRecordBoundary>[];
  Matcher failure(BrowserRecordFailure code) => isA<BrowserRecordException>()
      .having((error) => error.code, 'safe typed failure', code)
      .having(
        (error) => error.toString(),
        'no native message',
        'BrowserRecordException(${code.name})',
      );
  List<dynamic> observed() => jsonDecode(_events().toDart) as List<dynamic>;
  Future<void> recover() async {
    expect(_restore().toDart, isTrue);
    final boundary = await BrowserRecordBoundary.open(name);
    boundaries.add(boundary);
    await boundary.commitBatch(puts: {'public': 'recovered'});
    expect(await boundary.readSnapshot(), {'public': 'recovered'});
  }

  void stage(String value) {
    // Fixed public fixture stages only; never native messages or record data.
    // ignore: avoid_print
    print('ATOMIC_OPEN_STAGE_$value');
  }

  setUp(() {
    name = 'atomic-open-${Random.secure().nextInt(1 << 30)}-${index++}';
    boundaries.clear();
    globalContext.callMethod<JSAny?>('eval'.toJS, _hooks.toJS);
    _reset(name.toJS);
  });
  tearDown(() async {
    try {
      _release();
      for (final boundary in boundaries) {
        boundary.close();
      }
    } finally {
      expect(_restore().toDart, isTrue);
    }
    expect((await _cleanup(name.toJS).toDart).toDart, isTrue);
    // Receipt follows owned absence and native factory/descriptor restoration.
    // ignore: avoid_print
    print('ATOMIC_OPEN_CLEANUP_OK');
  });

  test(
    'O1 native delete queue times out and aborts late schema upgrade',
    () async {
      await _deleteQueue().toDart;
      final clock = Stopwatch()..start();
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openTimedOut)),
      );
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(4900));
      expect(observed(), ['delete-blocked']);
      _release();
      await _wait('late-error'.toJS).toDart;
      expect(observed(), [
        'delete-blocked',
        'delete-complete',
        'late-upgrade',
        'late-error',
      ]);
      expect((await _absent(name.toJS).toDart).toDart, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  test(
    'O2 native upgrade queue times out and closes late successful connection',
    () async {
      stage('holding');
      await _holdUpgrade().toDart;
      stage('waiting_timeout');
      final clock = Stopwatch()..start();
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openTimedOut)),
      );
      stage('elapsed');
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(4900));
      stage('still_held');
      expect(observed(), ['upgrade-held']);
      _release();
      stage('waiting_late_success');
      await _wait('late-success'.toJS).toDart;
      stage('late_event_order');
      expect(observed(), [
        'upgrade-held',
        'held-upgrade-complete',
        'late-success',
      ]);
      // This deletion must not be rescued by teardown closing observer handles:
      // a leaked late successful boundary connection would produce onblocked.
      stage('unblocked_delete');
      expect((await _deleteWithoutClosing(name.toJS).toDart).toDart, isTrue);
      stage('complete');
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  test(
    'O3 synthetic unavailable IndexedDB returns safe failure and recovers',
    () async {
      _fault('unavailable'.toJS);
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openFailed)),
      );
      expect(observed(), isEmpty);
      await recover();
    },
  );
  test(
    'O4 synthetic denied IndexedDB getter returns safe failure and recovers',
    () async {
      _fault('getter-denied'.toJS);
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openFailed)),
      );
      expect(observed(), isEmpty);
      await recover();
    },
  );
  test(
    'O5 synthetic denied owned factory open returns safe failure and recovers',
    () async {
      _fault('open-denied'.toJS);
      await expectLater(
        BrowserRecordBoundary.open(name),
        throwsA(failure(BrowserRecordFailure.openFailed)),
      );
      expect(observed(), isEmpty);
      await recover();
    },
  );
}
