// UX-08-gated: Guest, recovery, import preview and the browser preview gate
// read the redesign tokens, in both themes, while every gate stays as it was.
// Nothing here enables a gated feature: each page is driven directly.
import 'dart:io';
import 'dart:typed_data';

import 'package:atomic_notes/authentication/auth_pages/login_page.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/platform/browser_preview_gate.dart';
import 'package:atomic_notes/profile/guest_workspace_page.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_preview_view.dart';
import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/recovery/recovery_page.dart';
import 'package:atomic_notes/recovery/restore_coordinator.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../notes_editor_page_test.dart' as editor show field;

final _time = DateTime.utc(2026, 11, 8, 9);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);
String _id(String c) => '${c * 8}-${c * 4}-4${c * 3}-8${c * 3}-${c * 12}';
Note _note(String c, String title) =>
    Note(id: _id(c), title: title, createdAt: _time, updatedAt: _time);

/// The fixed legacy colours these pages used to set. None may reach a
/// page-owned text in either theme.
const _legacy = <Color>[
  AppColors.ink,
  AppColors.onSurface,
  AppColors.onSurfaceVariant,
  AppColors.slateData,
  AppColors.error,
  AppColors.paper,
];

const _themes = {'light': AtomicColors.light, 'dark': AtomicColors.dark};

Widget _app(AtomicColors c, Widget home) =>
    MaterialApp(theme: AtomicTheme.build(c), home: home);

void _view(WidgetTester tester, {double width = 420, double height = 900}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// 320 dp wide with text at 200%.
void _narrowLargeText(WidgetTester tester) {
  _view(tester, width: 320, height: 640);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

TextStyle _style(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).style!;

void _expectToken(WidgetTester tester, String key, Color token) {
  final style = _style(tester, key);
  expect(style.color, token, reason: key);
  expect(_legacy, isNot(contains(style.color)), reason: key);
  expect(style.fontFamily, AtomicFonts.sans, reason: key);
}

/// Every text painted under [scope] uses no legacy colour.
void _expectNoLegacy(WidgetTester tester, Finder scope) {
  final painted = find.descendant(of: scope, matching: find.byType(RichText));
  expect(painted, findsWidgets);
  for (final element in painted.evaluate()) {
    final text = (element.widget as RichText).text;
    text.visitChildren((span) {
      final color = span.style?.color;
      expect(_legacy, isNot(contains(color)),
          reason: '"${span.toPlainText()}" uses a legacy colour');
      return true;
    });
  }
}

// ---------------------------------------------------------------- Guest ---

class _GuestNotes implements GuestNotesPort {
  final _notes = <String, Note>{};
  List<Object> failures = [];
  int writes = 0;

  @override
  Future<void> open() async {}
  @override
  List<Note> notes() => [for (final n in _notes.values) n.copy()];
  @override
  Future<void> save(Note note) async {
    if (failures.isNotEmpty) throw failures.removeAt(0);
    writes++;
    _notes[note.id] = note.copy();
  }

  @override
  Future<void> remove(String id) async => _notes.remove(id);
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Guest mode must not use the network');
}

Future<void> _openGuest(
    WidgetTester tester, AtomicColors c, GuestNotesPort notes) async {
  HttpOverrides.global = _NoNetwork();
  addTearDown(() => HttpOverrides.global = null);
  await tester.pumpWidget(_app(c, GuestWorkspacePage(notes: notes)));
  await tester.pumpAndSettle();
}

Future<void> _writeGuestNote(
    WidgetTester tester, String title, String body) async {
  await tester.tap(find.byKey(const ValueKey('guest-new-note')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('note-title')), title);
  await tester.enterText(editor.field('note-body'), body);
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

// ------------------------------------------------------------- Recovery ---

class _Target implements ExportTarget {
  final _bytes = BytesBuilder();
  Uint8List? committed;
  @override
  Future<void> open() async {}
  @override
  Future<void> write(List<int> bytes) async => _bytes.add(bytes);
  @override
  Future<void> commit() async => committed = _bytes.toBytes();
  @override
  Future<void> abort() async {}
}

class _Store implements RestoreStore {
  _Store(this.target);
  final Map<String, Map<String, Object?>> target;
  Map<String, Object?>? marker;
  final staging = <String, Map<String, Map<String, Object?>>>{};
  final backups = <String, Map<String, Map<String, Object?>?>>{};
  @override
  Future<Map<String, Object?>?> current(String id) async => target[id];
  @override
  Future<RestoreMarker?> readMarker() async =>
      marker == null ? null : RestoreMarker.fromJson(marker!);
  @override
  Future<void> writeMarker(RestoreMarker m) async => marker = m.toJson();
  @override
  Future<void> clearMarker() async => marker = null;
  @override
  Future<void> stage(String op, String id, Map<String, Object?> r) async =>
      (staging[op] ??= {})[id] = r;
  @override
  Future<Map<String, Object?>?> staged(String op, String id) async =>
      staging[op]?[id];
  @override
  Future<void> discardStaged(String op) async => staging.remove(op);
  @override
  Future<bool> hasBackup(String op, String id) async =>
      backups[op]?.containsKey(id) ?? false;
  @override
  Future<void> backup(String op, String id, Map<String, Object?>? p) async =>
      (backups[op] ??= {})[id] = p;
  @override
  Future<void> put(String id, Map<String, Object?> r) async => target[id] = r;
}

class _Ports implements RecoveryPorts, LocalNotesView {
  final store = _Store({_id('a'): _note('a', 'Device A').toMap()});

  /// The bytes the chosen archive yields on every read. Replacing them after
  /// review stands for the file changing on disk.
  Uint8List? archiveBytes;

  @override
  int get savedLocally => store.target.length;
  @override
  String? get cloudStatus => null;
  @override
  BackupRecord? get lastBackup => null;
  @override
  Future<void> recordBackup(BackupRecord record) async {}
  @override
  Future<List<ArchiveSource>> snapshot() async => [
        for (final value in store.target.values)
          ArchiveSource(Note.fromMap(value)),
      ];
  @override
  ArchiveVault? get vault => _vault;
  @override
  ExportTarget newExportTarget() => _Target();
  @override
  Future<ArchiveByteSource Function()?> pickArchive() async =>
      archiveBytes == null
          ? null
          : () => ArchiveByteSource.bytes(archiveBytes!);
  @override
  LocalNotesView get local => this;
  @override
  RestoreStore get restoreStore => store;
  @override
  Note? byId(String id) {
    final value = store.target[id];
    return value == null ? null : Note.fromMap(value);
  }
}

Future<Uint8List> _archive(List<Note> notes) async {
  final target = _Target();
  await ExportWriter(clock: () => _time)
      .write(target, [for (final n in notes) ArchiveSource(n)], vault: _vault);
  return target.committed!;
}

Future<void> _openRecovery(WidgetTester tester, AtomicColors c, _Ports ports,
    {bool? enabled}) async {
  await tester.pumpWidget(_app(
      c,
      enabled == null
          ? RecoveryPage(ports: ports)
          : RecoveryPage(ports: ports, enabled: enabled)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

// ----------------------------------------------------------------- Lib ---

/// A source file with line endings normalised.
String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Dart files under lib/ whose source constructs [widget].
List<String> _constructors(String widget) {
  final pattern = RegExp('\\b${RegExp.escape(widget)}\\(');
  return [
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      if (pattern.hasMatch(_source(file.path))) file.path.replaceAll('\\', '/'),
  ]..sort();
}

void main() {
  group('gates and default reachability stay as on base', () {
    test('every gated feature is off in default builds', () {
      expect(GuestFeature.enabled, isFalse);
      expect(RecoveryFeature.enabled, isFalse);
      expect(const LoginPage().guestEntry, isFalse);
      expect(RecoveryPage(ports: _Ports()).enabled, isFalse);
    });

    test('each gated page is built only where it was on base', () {
      expect(_constructors('GuestWorkspacePage'), [
        'lib/authentication/auth_pages/login_page.dart',
        'lib/profile/guest_workspace_page.dart',
      ]);
      expect(_source('lib/authentication/auth_pages/login_page.dart'),
          contains('if (widget.guestEntry)'));
      expect(
          _constructors('RecoveryPage'), ['lib/recovery/recovery_page.dart']);
      expect(_constructors('ImportPreviewView'), [
        'lib/recovery/import_preview_view.dart',
        'lib/recovery/recovery_page.dart',
      ]);
      expect(_constructors('BrowserPreviewGate'),
          ['lib/main.dart', 'lib/platform/browser_preview_gate.dart']);
      expect(
          _source('lib/main.dart'),
          contains('  if (kIsWeb) {\n    runApp(const BrowserPreviewGate());\n'
              '    return;\n  }'));
    });

    testWidgets('the default login page offers no Guest entry', (tester) async {
      _view(tester, width: 800);
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      expect(find.byKey(const ValueKey('login-guest')), findsNothing);
      expect(find.text('Continue without an account'), findsNothing);
    });

    testWidgets('the default recovery page offers nothing', (tester) async {
      _view(tester);
      await _openRecovery(tester, AtomicColors.light, _Ports());
      expect(
          find.byKey(const ValueKey('recovery-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('recovery-export')), findsNothing);
      expect(find.byKey(const ValueKey('recovery-open')), findsNothing);
      expect(find.byKey(const ValueKey('recovery-password')), findsNothing);
    });

    testWidgets('the browser gate still opens nothing', (tester) async {
      _view(tester);
      await tester.pumpWidget(const BrowserPreviewGate());
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.routes, isEmpty);
      expect(app.onGenerateRoute, isNull);
      expect(app.onUnknownRoute, isNull);
      expect(find.text('WEBAPP IN DEVELOPMENT'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ButtonStyleButton), findsNothing);
    });
  });

  for (final MapEntry(key: name, value: c) in _themes.entries) {
    group('$name theme', () {
      testWidgets('Guest text reads the theme tokens', (tester) async {
        _view(tester);
        final notes = _GuestNotes()..failures = [StateError('disk full')];
        await _openGuest(tester, c, notes);
        _expectToken(tester, 'guest-status', c.textPrimary);
        await _writeGuestNote(tester, 'Groceries', 'Milk');
        _expectToken(tester, 'guest-error', c.dangerText);
        final pending = tester.widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('guest-pending')),
            matching: find.text('Unsaved note: Groceries')));
        expect(pending.style!.color, c.textPrimary);
        _expectNoLegacy(tester, find.byType(ListView));
      });

      testWidgets('Guest keeps a draft until a save succeeds', (tester) async {
        _view(tester);
        final notes = _GuestNotes()..failures = [StateError('disk full')];
        await _openGuest(tester, c, notes);
        await _writeGuestNote(tester, 'Plan', 'Call the plumber');
        expect(notes.notes(), isEmpty);
        expect(find.text('Unsaved note: Plan'), findsOneWidget);
        expect(
            tester
                .widget<FloatingActionButton>(
                    find.byKey(const ValueKey('guest-new-note')))
                .onPressed,
            isNull,
            reason: 'the pending draft is resolved first');

        // Back cannot drop it silently.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guest-leave-keep')));
        await tester.pumpAndSettle();
        expect(find.byType(GuestWorkspacePage), findsOneWidget);
        expect(find.text('Unsaved note: Plan'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('guest-pending-retry')));
        await tester.pumpAndSettle();
        expect(notes.notes().map((n) => (n.title, n.body)),
            [('Plan', 'Call the plumber')]);
        expect(notes.writes, 1);
        expect(find.byKey(const ValueKey('guest-pending')), findsNothing);
        expect(find.byKey(const ValueKey('guest-error')), findsNothing);
      });

      testWidgets('recovery text reads the theme tokens', (tester) async {
        _view(tester, height: 1400);
        await _openRecovery(tester, c, _Ports(), enabled: false);
        _expectToken(tester, 'recovery-unavailable', c.textPrimary);

        final ports = _Ports()..archiveBytes = Uint8List.fromList([1, 2, 3, 4]);
        await _openRecovery(tester, c, ports, enabled: true);
        for (final key in [
          'recovery-local',
          'recovery-cloud',
          'recovery-backup'
        ]) {
          _expectToken(tester, key, c.textPrimary);
        }
        await tester.tap(find.byKey(const ValueKey('recovery-open')));
        await _settle(tester);
        _expectToken(tester, 'recovery-message', c.dangerText);
        _expectNoLegacy(tester, find.byType(ListView));
      });

      testWidgets('an approved archive restores; a changed one is refused',
          (tester) async {
        _view(tester, height: 1400);
        final ports = _Ports();
        final approved = await tester.runAsync(
            () => _archive([_note('a', 'Device A'), _note('e', 'New E')]));
        final changed = await tester.runAsync(
            () => _archive([_note('a', 'Device A'), _note('f', 'Other F')]));
        final restore = find.byKey(const ValueKey('import-preview-restore'));
        await _openRecovery(tester, c, ports, enabled: true);

        // Changed after review: refused, nothing written.
        ports.archiveBytes = approved;
        await tester.tap(find.byKey(const ValueKey('recovery-open')));
        await _settle(tester);
        expect(find.text('2 notes'), findsOneWidget);
        _expectToken(tester, 'import-preview-comparison', c.textPrimary);
        ports.archiveBytes = changed;
        await tester.ensureVisible(restore);
        await tester.tap(restore);
        await _settle(tester);
        expect(_text(tester, 'recovery-message'),
            'This archive changed after it was reviewed. Review it again.');
        _expectToken(tester, 'recovery-message', c.dangerText);
        expect(ports.store.target.keys, [_id('a')]);
        expect(ports.store.marker, isNull);

        // Reviewed and unchanged: restored.
        ports.archiveBytes = approved;
        await tester.tap(find.byKey(const ValueKey('recovery-open')));
        await _settle(tester);
        await tester.ensureVisible(restore);
        await tester.tap(restore);
        await _settle(tester);
        expect(_text(tester, 'recovery-message'),
            'Restored 1 notes. 0 kept as they were on this device.');
        _expectToken(tester, 'recovery-message', c.textPrimary);
        expect(ports.store.target[_id('e')]!['title'], 'New E');
        expect(ports.store.marker, isNull);
      });

      testWidgets('import preview text reads the theme tokens', (tester) async {
        _view(tester);
        final preview = await tester.runAsync(() async =>
            ImportValidator.inspect(
                ArchiveByteSource.bytes(await _archive([_note('e', 'New E')])),
                local: _Ports()));
        await tester.pumpWidget(_app(
            c,
            Scaffold(
                body: SingleChildScrollView(
                    child: ImportPreviewView(preview: preview!)))));
        final total = tester.widget<Text>(find.text('1 note'));
        expect(total.style!.color, c.textPrimary);
        expect(total.style!.fontSize, AtomicType.titleLarge.fontSize);
        _expectToken(tester, 'import-preview-comparison', c.textPrimary);
        _expectNoLegacy(tester, find.byType(ImportPreviewView));

        await tester.pumpWidget(_app(
            c,
            Scaffold(
                body: ImportPreviewView(preview: ImportPreview.locked()))));
        final locked = tester.widget<Text>(find.textContaining('protected'));
        expect(locked.style!.color, c.textPrimary);
        expect(
            find.byKey(const ValueKey('import-preview-restore')), findsNothing);
      });

      testWidgets('the browser gate follows the platform theme',
          (tester) async {
        _view(tester);
        tester.platformDispatcher.platformBrightnessTestValue = c.brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(const BrowserPreviewGate());
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, c.canvas);
        final heading = tester.widget<Text>(find.text('WEBAPP IN DEVELOPMENT'));
        expect(heading.style!.color, c.textPrimary);
        expect(heading.style!.fontFamily, AtomicFonts.sans);
        expect(
            tester.widget<Text>(find.text('ATOMIC NOTES / WEB')).style!.color,
            c.textSecondary);
        _expectNoLegacy(tester, find.byType(Scaffold));
      });
    });
  }

  group('320 dp at 200% text', () {
    testWidgets('Guest, with a pending draft', (tester) async {
      // The note is written at phone size (the editor is outside this row),
      // then the page is shown narrow with large text.
      _view(tester);
      final notes = _GuestNotes()..failures = [StateError('disk full')];
      await _openGuest(tester, AtomicColors.dark, notes);
      await _writeGuestNote(tester, 'A long unsaved title', 'Body');
      _narrowLargeText(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final pending = find.byKey(const ValueKey('guest-pending'));
      await tester.scrollUntilVisible(pending, 80,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(pending, findsOneWidget);
      expect(find.byKey(const ValueKey('guest-pending-discard')).hitTestable(),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recovery, enabled and gated', (tester) async {
      _narrowLargeText(tester);
      await _openRecovery(tester, AtomicColors.dark, _Ports(), enabled: true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _openRecovery(tester, AtomicColors.dark, _Ports());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('import preview', (tester) async {
      _narrowLargeText(tester);
      final preview = await tester.runAsync(() async => ImportValidator.inspect(
          ArchiveByteSource.bytes(
              await _archive([_note('a', 'Device A'), _note('e', 'New E')])),
          local: _Ports()));
      await tester.pumpWidget(_app(
          AtomicColors.light,
          Scaffold(
              body: SingleChildScrollView(
                  child: ImportPreviewView(preview: preview!)))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('browser gate', (tester) async {
      _narrowLargeText(tester);
      await tester.pumpWidget(const BrowserPreviewGate());
      expect(tester.takeException(), isNull);
    });
  });
}
