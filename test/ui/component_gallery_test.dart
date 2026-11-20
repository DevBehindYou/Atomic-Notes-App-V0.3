// The debug-only component gallery.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/chips/tag_chip.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/controls/segmented.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/feedback/status_strip.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/fields/code_field.dart';
import 'package:atomic_notes/ui/fields/search_field.dart';
import 'package:atomic_notes/ui/gallery/component_gallery.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:atomic_notes/ui/motion/burst.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/motion/odometer.dart';
import 'package:atomic_notes/ui/motion/orbit_ring.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/rows/checklist_row.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every section, top to bottom. The gallery animates without end (ambient
/// loops, spinners, skeleton pulse), so the tests pump fixed durations and
/// never settle while it is on screen.
const _sections = [
  'Buttons', 'Icon buttons', 'New-note button', 'Chips', 'Selection bar', //
  'Cards', 'Rows', 'Fields', 'Controls', 'Banners and empty state', //
  'Progress', 'Overlays', 'Dialog preview', 'Motion', 'Slide to confirm',
];

/// Every M2-b and M2-c widget the page itself shows. The sheet's widgets
/// appear only once it is open (see the overlay test).
const _components = <Type>[
  // M2-b
  AtomicCard, AtomicCheckbox, AtomicCheckboxMark, AtomicSwitch, //
  AtomicSwitchTrack, Segmented<int>, AtomicTextField, PhraseField, //
  CodeField, SearchField, ChecklistRow, SettingsGroup, SettingsRow, //
  LedgerRow,
  // M2-c
  AtomicBanner, EmptyState, ProgressRing, ProgressBar, Skeleton, //
  StatusStrip, MascotStage, Ambient, Burst, EntranceGroup, Entrance, //
  Stagger, Odometer, OrbitRing, SlideToConfirm, AtomicDialog<bool>,
];

const _frame = Duration(milliseconds: 600);

Widget _app({
  double textScale = 1,
  bool reduced = false,
  bool accessible = false,
  Widget home = const ComponentGallery(),
  Map<String, WidgetBuilder> routes = const {},
  GlobalKey<NavigatorState>? navigator,
}) {
  return MaterialApp(
    theme: AtomicTheme.light,
    routes: routes,
    navigatorKey: navigator,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
        accessibleNavigation: accessible,
      ),
      child: child!,
    ),
    home: home,
  );
}

/// A phone screen of [width] × [height] logical pixels (device pixel ratio
/// 1), so the gallery's margins come from [width] as they do on a device.
void _screen(WidgetTester tester, {double width = 360, double height = 780}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpGallery(
  WidgetTester tester, {
  double width = 360,
  double textScale = 1,
  bool reduced = false,
  bool dark = false,
}) async {
  _screen(tester, width: width);
  await tester.pumpWidget(_app(textScale: textScale, reduced: reduced));
  await tester.pump(_frame);
  if (dark) await _tap(tester, find.byTooltip('Dark theme'));
}

Finder get _list => find
    .descendant(
        of: find.byType(ComponentGallery), matching: find.byType(Scrollable))
    .first;

/// Scrolls [finder] on screen and lays the page out again, so a tap lands
/// where the widget is now. The gallery builds every section up front.
Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Lets the response to an action run for [time], frame by frame, so
/// animations that start when another ends (a snack bar after the one it
/// replaces) get their frames too.
Future<void> _run(WidgetTester tester, [Duration time = _frame]) async {
  const step = Duration(milliseconds: 50);
  await tester.pump();
  for (var t = Duration.zero; t < time; t += step) {
    await tester.pump(time - t < step ? time - t : step);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder,
    {Duration then = _frame}) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await _run(tester, then);
}

/// The odometer's label is a line of its section's merged node.
final _notes128 = RegExp(r'(^|\n)128 notes($|\n)');
final _notes129 = RegExp(r'(^|\n)129 notes($|\n)');

/// Drags from the top of the gallery to its end, calling [onStep] at each
/// stop and failing on the first layout error.
Future<void> _scrollThrough(WidgetTester tester, void Function() onStep) async {
  final position = tester.state<ScrollableState>(_list).position;
  onStep();
  for (var i = 0; i < 200 && position.pixels < position.maxScrollExtent; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: 'at ${position.pixels}');
    onStep();
  }
  expect(position.pixels, position.maxScrollExtent, reason: 'reached the end');
}

SemanticsNode _node(WidgetTester tester, Pattern label) =>
    tester.getSemantics(find.bySemanticsLabel(label));

Future<SemanticsNode> _shown(WidgetTester tester, Pattern label) async {
  await _show(tester, find.bySemanticsLabel(label));
  return _node(tester, label);
}

/// What holds keyboard focus, named by the gallery component around it.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? name;
  context.visitAncestorElements((element) {
    name = switch (element.widget) {
      AtomicButton(:final label) => 'button $label',
      AtomicIconButton(:final tooltip) => 'icon $tooltip',
      AtomicSwitch(:final semanticsLabel) => 'switch $semanticsLabel',
      AtomicCheckbox(:final semanticsLabel) => 'checkbox $semanticsLabel',
      SettingsRow(:final title) => 'settings $title',
      ChecklistRow(:final text) => 'checklist $text',
      AtomicTextField(:final label) => 'field $label',
      SearchField() => 'search',
      Segmented() => 'segmented',
      AtomicFilterChip() => 'filter chip',
      TagChip() || AddTagChip() => 'tag chip',
      AtomicFab() => 'fab',
      SlideToConfirm() => 'slide',
      _ => null,
    };
    return name == null;
  });
  return name ?? 'unnamed ${context.widget.runtimeType}';
}

Color _canvas(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

double _opacityAbove(WidgetTester tester, String text) => tester
    .widget<FadeTransition>(find
        .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

/// The gallery's indeterminate "Loading" ring, found even while its route
/// is covered (offstage).
final _loading = find.byWidgetPredicate(
    (w) => w is ProgressRing && w.semanticsLabel == 'Loading',
    skipOffstage: false);

/// The positions of whatever animates inside the ring: empty for a still
/// (determinate) ring.
List<double> _ringFrames(WidgetTester tester) => tester
    .widgetList<AnimatedBuilder>(find.descendant(
        of: _loading,
        matching: find.byType(AnimatedBuilder),
        skipOffstage: false))
    .map((w) => w.animation)
    .whereType<Animation<double>>()
    .map((a) => a.value)
    .toList();

/// The tickers that are running anywhere inside the simulated ring, read
/// from each ticker-providing state's diagnostics. A still ring must have
/// none: painting a still arc over a running animation is not stopping it.
int _activeRingTickers(WidgetTester tester) {
  final ring = find.byWidgetPredicate(
      (w) => '${w.runtimeType}' == '_SimulatedLoading',
      skipOffstage: false);
  final states = tester.stateList(find.descendant(
      of: ring,
      matching: find.byWidgetPredicate((w) => w is StatefulWidget),
      skipOffstage: false));
  var active = 0;
  for (final state in states) {
    for (final property in state.toDiagnosticsNode().getProperties()) {
      final Iterable<Ticker> tickers = switch (property.value) {
        Ticker ticker when property.name == 'ticker' => [ticker],
        Set<Ticker> set when property.name == 'tickers' => set,
        _ => const <Ticker>[],
      };
      active += tickers.where((t) => t.isActive).length;
    }
  }
  return active;
}

/// The ring measures where it is after a layout, then rebuilds.
Future<void> _remeasure(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _showRing(WidgetTester tester) async {
  await tester.ensureVisible(_loading);
  await _remeasure(tester);
}

Future<void> _expectSpinning(WidgetTester tester, String reason) async {
  expect(tester.widget<ProgressRing>(_loading).value, isNull, reason: reason);
  final before = _ringFrames(tester);
  expect(before, isNotEmpty, reason: reason);
  expect(_activeRingTickers(tester), greaterThan(0), reason: reason);
  await tester.pump(const Duration(milliseconds: 420));
  expect(_ringFrames(tester), isNot(before), reason: '$reason: it moves');
}

Future<void> _expectStill(WidgetTester tester, String reason) async {
  for (var i = 0; i < 2; i++) {
    expect(tester.widget<ProgressRing>(_loading).value, 0.25, reason: reason);
    expect(_ringFrames(tester), isEmpty, reason: reason);
    expect(_activeRingTickers(tester), 0, reason: '$reason: its ticker stops');
    await tester.pump(const Duration(milliseconds: 420));
  }
}

CustomPainter? _burstPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(of: find.byType(Burst), matching: find.byType(CustomPaint))
        .first)
    .foregroundPainter;

void main() {
  setUp(() {
    AmbientBudget.reset();
    // A tap that would miss its widget fails the test instead of warning.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('debug only', () {
    test('the route exists in debug builds only', () {
      expect(ComponentGallery.debugRoutes.keys,
          kDebugMode ? [ComponentGallery.route] : isEmpty);
    });

    // Tests run in debug mode, so the guard itself is checked in source:
    // profile and release builds see an empty map, and the app reaches the
    // gallery only through it.
    test('the app registers the gallery only through the guarded routes', () {
      final gallery =
          File('lib/ui/gallery/component_gallery.dart').readAsStringSync();
      expect(gallery,
          matches(RegExp(r'get debugRoutes\s*=>\s*kDebugMode\s*\?\s*\{')));
      expect(gallery, contains(': const <String, WidgetBuilder>{};'));

      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('...ComponentGallery.debugRoutes,'));
      expect(RegExp(r'ComponentGallery\b').allMatches(main), hasLength(1));

      final others = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path
              .replaceAll(r'\', '/')
              .endsWith('lib/ui/gallery/component_gallery.dart'))
          .where((f) => !f.path.replaceAll(r'\', '/').endsWith('lib/main.dart'))
          .where((f) => f.readAsStringSync().contains('ComponentGallery'))
          .map((f) => f.path);
      expect(others, isEmpty);
    });
  });

  testWidgets('switches between the light and dark themes', (tester) async {
    await _pumpGallery(tester);
    expect(find.text('Components'), findsOneWidget);
    expect(_canvas(tester), AtomicColors.light.canvas);
    await _tap(tester, find.byTooltip('Dark theme'));
    expect(_canvas(tester), AtomicColors.dark.canvas);
    await _tap(tester, find.byTooltip('Light theme'));
    expect(_canvas(tester), AtomicColors.light.canvas);
    expect(tester.takeException(), isNull);
  });

  for (final (width, textScale) in [(360.0, 1.0), (360.0, 2.0), (320.0, 2.0)]) {
    for (final dark in [false, true]) {
      testWidgets(
          'every section is present and fits $width dp at text '
          '$textScale (${dark ? 'dark' : 'light'})', (tester) async {
        await _pumpGallery(tester,
            width: width, textScale: textScale, dark: dark);
        final seen = <String>{};
        await _scrollThrough(tester, () {
          for (final section in _sections) {
            if (find.text(section).evaluate().isNotEmpty) seen.add(section);
          }
        });
        expect(seen, unorderedEquals(_sections));
        expect(_canvas(tester),
            dark ? AtomicColors.dark.canvas : AtomicColors.light.canvas);
      });
    }
  }

  testWidgets('shows every M2-b and M2-c component', (tester) async {
    await _pumpGallery(tester);
    final seen = <Type>{};
    await _scrollThrough(tester, () {
      seen.addAll(tester.allWidgets.map((w) => w.runtimeType));
    });
    expect(_components.where((type) => !seen.contains(type)), isEmpty);
  });

  testWidgets(
      'the overlay demos open and close the dialog, sheet and snack '
      'bars', (tester) async {
    await _pumpGallery(tester);
    final title = find.text('Delete 3 notes?');
    final dialog =
        find.ancestor(of: title, matching: find.byType(AtomicDialog<bool>));

    await _tap(tester, find.text('Show dialog'));
    expect(title, findsOneWidget);
    await tester
        .tap(find.descendant(of: dialog, matching: find.text('Cancel')));
    await _run(tester);
    expect(title, findsNothing);

    // Back closes the dialog only, never the page under it.
    await _tap(tester, find.text('Show dialog'));
    expect(title, findsOneWidget);
    await tester.binding.handlePopRoute();
    await _run(tester);
    expect(title, findsNothing);
    expect(find.byType(ComponentGallery), findsOneWidget);

    await _tap(tester, find.text('Show sheet'));
    expect(find.byType(AtomicSheetBody), findsOneWidget,
        reason: 'one handle, not a sheet inside a sheet');
    expect(find.byType(AtomicSheetAction), findsNWidgets(2));
    await tester.tap(find.descendant(
        of: find.byType(AtomicSheetBody), matching: find.text('Pin')));
    await _run(tester);
    expect(find.byType(AtomicSheetBody), findsNothing);

    await _tap(tester, find.text('Show snack bar'));
    expect(find.text('Note saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    // A new message replaces the one showing, then times out.
    await _tap(tester, find.text('Show error snack bar'));
    expect(find.text('Note saved'), findsNothing);
    expect(find.text('Could not sync'), findsOneWidget);
    await _run(tester, const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the interactive demos change state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpGallery(tester);

    expect(await _shown(tester, 'Save'), isSemantics(isEnabled: true));
    await _tap(tester, find.text('Start busy'));
    expect(_node(tester, 'Save'),
        isSemantics(hasEnabledState: true, isEnabled: false));
    expect(
        find.descendant(
            of: find.widgetWithText(AtomicButton, 'Save'),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    // A busy button ignores taps, so the demo is ended from elsewhere.
    await _tap(tester, find.text('Stop busy'));
    expect(_node(tester, 'Save'), isSemantics(isEnabled: true));

    const tick = 'Complete Tap to tick this item';
    expect(await _shown(tester, tick), isSemantics(isChecked: false));
    await _tap(tester, find.text('Tap to tick this item'));
    expect(_node(tester, tick), isSemantics(isChecked: true));

    expect(await _shown(tester, 'Cloud sync'), isSemantics(isToggled: true));
    await _tap(tester, find.text('Cloud sync'));
    expect(_node(tester, 'Cloud sync'), isSemantics(isToggled: false));

    expect(
        await _shown(tester, 'Example switch'), isSemantics(isToggled: true));
    await _tap(tester, find.bySemanticsLabel('Example switch'));
    expect(_node(tester, 'Example switch'), isSemantics(isToggled: false));

    const box = 'Example standard checkbox';
    expect(await _shown(tester, box), isSemantics(isChecked: false));
    await _tap(tester, find.bySemanticsLabel(box));
    expect(_node(tester, box), isSemantics(isChecked: true));

    expect(await _shown(tester, 'Week'), isSemantics(isSelected: false));
    await _tap(tester, find.text('Week'));
    expect(_node(tester, 'Week'), isSemantics(isSelected: true));
    expect(_node(tester, 'Day'), isSemantics(isSelected: false));

    await _show(tester, find.text('Count up'));
    expect(find.semantics.byLabel(_notes128), findsOne);
    await _tap(tester, find.text('Count up'),
        then: const Duration(milliseconds: 900));
    expect(find.semantics.byLabel(_notes129), findsOne);
    expect(find.semantics.byLabel(_notes128), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets(
      'slide to confirm: a short slide does nothing, a full one '
      'works, then resets', (tester) async {
    await _pumpGallery(tester);
    final thumb = find.byKey(SlideToConfirm.thumbKey);
    await _show(tester, find.text('Confirmations: 0'));

    await tester.drag(thumb, const Offset(60, 0));
    await _run(tester);
    expect(find.text('Slide to confirm the demo'), findsOneWidget);
    expect(find.text('Confirmations: 0'), findsOneWidget);

    await tester.tap(thumb);
    await tester.pump();
    expect(find.text('Tap again to confirm'), findsOneWidget);
    await tester.pump(SlideToConfirm.armedFor + _frame);
    expect(find.text('Slide to confirm the demo'), findsOneWidget,
        reason: 'disarmed after the timeout');

    await tester.drag(thumb, const Offset(500, 0));
    await tester.pump();
    expect(find.text('Working…'), findsOneWidget);
    await tester.pump(ComponentGallery.demoWork);
    await tester.pump(_frame);
    expect(find.text('Confirmations: 1'), findsOneWidget);
    expect(find.text('Slide to confirm the demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers hear every demo, with its state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpGallery(tester);
    final cases = <String, Matcher>{
      'Dark theme': isSemantics(isButton: true, hasTapAction: true),
      'Disabled':
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      'Share, unavailable':
          isSemantics(hasEnabledState: true, isEnabled: false),
      'Profile. Name and picture':
          isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      'Encryption. Sign in first':
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      'App lock': isSemantics(
          hasToggledState: true, hasEnabledState: true, isEnabled: false),
      'Complete In selection mode': isSemantics(
          hasCheckedState: true, hasEnabledState: true, isEnabled: false),
      'Disabled switch': isSemantics(
          hasToggledState: true, hasEnabledState: true, isEnabled: false),
      'Example important checkbox': isSemantics(
          hasCheckedState: true, isEnabled: true, hasTapAction: true),
      'Disabled checkbox': isSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: false),
      'Day': isSemantics(isSelected: true, isEnabled: true),
      'Newest': isSemantics(
          isSelected: true, hasEnabledState: true, isEnabled: false),
      'Show dialog': isSemantics(isButton: true, hasTapAction: true),
      'Start orbit': isSemantics(isButton: true, hasTapAction: true),
    };
    for (final MapEntry(key: label, value: matcher) in cases.entries) {
      expect(await _shown(tester, label), matcher, reason: label);
    }
    // These two share a node with the text around them; the label must
    // still be there, read once, not digit by digit.
    await _show(tester, find.text('Count up'));
    expect(find.semantics.byLabel(_notes128), findsOne);
    await _show(tester, find.text('Confirmations: 0'));
    final slide = find.semantics.byLabel(RegExp('Slide to confirm the demo'));
    expect(slide, findsOne);
    expect(slide.evaluate().single, isSemantics(hasTapAction: true));
    // The dialog preview is a picture: on screen, but silent.
    await _show(tester, find.text('Leave without saving?'));
    expect(find.bySemanticsLabel('Leave without saving?'), findsNothing);
    expect(find.bySemanticsLabel('Keep editing'), findsNothing);
    handle.dispose();
  });

  testWidgets(
      'keyboard focus reaches every enabled demo and skips the '
      'disabled ones', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic);
    await _pumpGallery(tester);
    final reached = <String>[];
    for (var i = 0; i < 200; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final name = _focused();
      if (name == null) continue;
      if (reached.isNotEmpty && name == reached.first) break; // wrapped
      reached.add(name);
      if (name == 'checkbox Example standard checkbox') {
        // The focused control works from the keyboard too.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(_frame);
      }
    }
    expect(reached.first, 'icon Back');
    expect(
        reached,
        containsAllInOrder([
          'icon Dark theme',
          'button primary',
          'button Start busy',
          'icon Pin',
          'fab',
          'filter chip',
          'tag chip',
          'icon Cancel selection',
          'settings Profile',
          'settings Cloud sync',
          'checklist Tap to tick this item',
          'field Title',
          'search',
          'field 6-digit code',
          'field Recovery phrase',
          'switch Example switch',
          'checkbox Example standard checkbox',
          'segmented',
          'button Try again',
          'button New note',
          'button Show dialog',
          'button Show error snack bar',
          'button Start orbit',
          'button Burst',
          'button Count up',
          'button Replay entrance',
        ]));
    expect(
        reached,
        isNot(anyOf([
          contains('button Disabled'),
          contains('icon Share, unavailable'),
          contains('settings Encryption'),
          contains('settings App lock'),
          contains('checklist In selection mode'),
          contains('field Not editable'),
          contains('switch Disabled switch'),
          contains('checkbox Disabled checkbox'),
          contains('button Keep editing'),
          contains('button Leave'),
        ])));
    expect(reached.where((name) => name.startsWith('unnamed')), isEmpty);
    final handle = tester.ensureSemantics();
    expect(await _shown(tester, 'Example standard checkbox'),
        isSemantics(isChecked: true));
    handle.dispose();
  });

  testWidgets(
      'reduced motion stops loops and finishes transitions at once, '
      'even mid-flight', (tester) async {
    await _pumpGallery(tester);
    await _show(tester, find.text('Replay entrance'));
    expect(AmbientBudget.active, 1, reason: 'the ambient demo loops');

    await _tap(tester, find.text('Replay entrance'),
        then: const Duration(milliseconds: 50));
    await tester.tap(find.text('Burst'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacityAbove(tester, 'Entrance 1'), lessThan(1));
    expect(_opacityAbove(tester, 'Stagger 1'), lessThan(1));
    expect(_burstPainter(tester), isNotNull);

    // Reduced motion turns on while all of that is running.
    await tester.pumpWidget(_app(reduced: true));
    await tester.pump();
    expect(AmbientBudget.active, 0);
    expect(_opacityAbove(tester, 'Entrance 1'), 1);
    expect(_opacityAbove(tester, 'Stagger 1'), 1);
    expect(_burstPainter(tester), isNull);

    // A new burst never starts.
    await tester.tap(find.text('Burst'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_burstPainter(tester), isNull);

    // And off again: the loop resumes.
    await tester.pumpWidget(_app());
    await tester.pump(_frame);
    expect(AmbientBudget.active, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving it mid-work leaves no loop, ticker or timer behind',
      (tester) async {
    await _pumpGallery(tester);
    await _tap(tester, find.text('Start busy'));
    await _tap(tester, find.text('Show snack bar'));
    await _tap(tester, find.text('Start orbit'));
    await _tap(tester, find.text('Burst'),
        then: const Duration(milliseconds: 100));
    await _show(tester, find.text('Confirmations: 0'));
    await tester.drag(
        find.byKey(SlideToConfirm.thumbKey), const Offset(500, 0));
    await tester.pump();
    expect(find.text('Working…'), findsOneWidget);
    expect(AmbientBudget.active, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(AmbientBudget.active, 0);
    expect(tester.binding.transientCallbackCount, 0);
    // The test binding also fails this test if any timer (snack bar, demo
    // work) is still pending now that the tree is gone.
  });

  testWidgets('opens and closes repeatedly from a named route', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app(
      routes: ComponentGallery.debugRoutes,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AtomicButton.primary(
              label: 'Open gallery',
              onPressed: () =>
                  Navigator.pushNamed(context, ComponentGallery.route),
            ),
          ),
        ),
      ),
    ));
    for (var round = 0; round < 3; round++) {
      await tester.tap(find.text('Open gallery'));
      await _run(tester, const Duration(seconds: 1));
      expect(find.text('Components'), findsOneWidget, reason: 'round $round');

      await _show(tester, find.text('Replay entrance'));
      expect(AmbientBudget.active, 1);
      // The preview's buttons are a picture: tapping one leaves the page be.
      await _show(tester, find.text('Leave'));
      await tester.tap(find.text('Leave'), warnIfMissed: false);
      await _run(tester);
      expect(find.byType(ComponentGallery), findsOneWidget);

      if (round == 1) {
        // Leave with a dialog open: the first back closes only the dialog.
        await _tap(tester, find.text('Show dialog'));
        await tester.binding.handlePopRoute();
        await _run(tester);
        expect(find.text('Delete 3 notes?'), findsNothing);
        expect(find.byType(ComponentGallery), findsOneWidget);
      }
      if (round == 2) {
        // Leave while the slide is armed (its disarm timer pending).
        await _tap(tester, find.byKey(SlideToConfirm.thumbKey),
            then: Duration.zero);
        expect(find.text('Tap again to confirm'), findsOneWidget);
      }
      if (round.isEven) {
        await tester.binding.handlePopRoute();
        await _run(tester, const Duration(seconds: 1));
      } else {
        await _tap(tester, find.byTooltip('Back'),
            then: const Duration(seconds: 1));
      }
      expect(find.byType(ComponentGallery), findsNothing,
          reason: 'round $round');
      expect(AmbientBudget.active, 0);
      expect(tester.binding.transientCallbackCount, 0);
    }
    expect(tester.takeException(), isNull);
  });

  // Review R26: nothing loads in the gallery, so its indeterminate ring is
  // still unless someone could watch it move.
  group('the simulated loading ring', () {
    for (final flag in ['disableAnimations', 'accessibleNavigation']) {
      testWidgets('is still under $flag, and reads as Loading', (tester) async {
        final handle = tester.ensureSemantics();
        _screen(tester);
        await tester.pumpWidget(_app(
          reduced: flag == 'disableAnimations',
          accessible: flag == 'accessibleNavigation',
        ));
        await tester.pump(_frame);
        await _showRing(tester);
        await _expectStill(tester, flag);
        // The still arc is not a percentage.
        final node = tester.getSemantics(find.bySemanticsLabel('Loading'));
        expect(node.value, isEmpty, reason: flag);
        handle.dispose();
      });
    }

    testWidgets('spins on screen, with the same label, and stops off screen',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGallery(tester);
      await _remeasure(tester);
      await _expectStill(tester, 'built below the fold');

      await _showRing(tester);
      await _expectSpinning(tester, 'scrolled into view');
      expect(
          tester.getSemantics(find.bySemanticsLabel('Loading')).value, isEmpty);

      tester.state<ScrollableState>(_list).position.jumpTo(0);
      await _remeasure(tester);
      await _expectStill(tester, 'scrolled back out of view');

      await _showRing(tester);
      await _expectSpinning(tester, 'scrolled into view again');
      handle.dispose();
    });

    testWidgets('stops and restarts as reduced motion changes while open',
        (tester) async {
      await _pumpGallery(tester);
      await _showRing(tester);
      await _expectSpinning(tester, 'normal motion');

      for (final (reduced, accessible) in [(true, false), (false, true)]) {
        final flag = reduced ? 'disableAnimations' : 'accessibleNavigation';
        await tester.pumpWidget(_app(reduced: reduced, accessible: accessible));
        await _remeasure(tester);
        await _expectStill(tester, '$flag turned on');

        await tester.pumpWidget(_app());
        await _remeasure(tester);
        await _expectSpinning(tester, '$flag turned off');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('stops while the app is in the background', (tester) async {
      await _pumpGallery(tester);
      await _showRing(tester);
      await _expectSpinning(tester, 'foreground');

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await _remeasure(tester);
      await _expectStill(tester, 'paused');

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await _remeasure(tester);
      await _expectSpinning(tester, 'resumed');
    });

    testWidgets('stops while another page covers the gallery', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      _screen(tester);
      await tester.pumpWidget(_app(navigator: navigator));
      await tester.pump(_frame);
      await _showRing(tester);
      await _expectSpinning(tester, 'gallery showing');

      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering page')))));
      await _run(tester, const Duration(seconds: 1));
      expect(find.text('Covering page'), findsOneWidget);
      await _expectStill(tester, 'covered');

      navigator.currentState!.pop();
      await _run(tester, const Duration(seconds: 1));
      await _remeasure(tester);
      await _expectSpinning(tester, 'uncovered');
    });

    // Review R36: a dialog route is not opaque, so TickerMode stays on for
    // the gallery below even while a fullscreen dialog hides all of it.
    testWidgets('stops under a fullscreen dialog and resumes when it closes',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      _screen(tester);
      await tester.pumpWidget(_app(navigator: navigator));
      await tester.pump(_frame);
      await _showRing(tester);
      await _expectSpinning(tester, 'gallery showing');

      unawaited(showDialog<void>(
        context: tester.element(find.byType(ComponentGallery)),
        builder: (_) => const Dialog.fullscreen(
          child: ColoredBox(
            color: Colors.white,
            child: Center(child: Text('Covering dialog')),
          ),
        ),
      ));
      await _run(tester, const Duration(seconds: 1));
      expect(find.text('Covering dialog'), findsOneWidget);
      expect(
          tester
              .getRect(find.byType(Dialog))
              .contains(tester.getRect(_loading).center),
          isTrue,
          reason: 'the dialog hides the ring');
      expect(TickerMode.valuesOf(tester.element(_loading)).enabled, isTrue,
          reason: 'the route below is not muted');
      await _expectStill(tester, 'under a fullscreen dialog');

      // Nothing else changed: closing the dialog alone restarts it.
      navigator.currentState!.pop();
      await _run(tester, const Duration(seconds: 1));
      expect(find.text('Covering dialog'), findsNothing);
      await _remeasure(tester);
      await _expectSpinning(tester, 'dialog closed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the gallery ends the ring and its observers',
        (tester) async {
      _screen(tester);
      await tester.pumpWidget(_app(
        routes: ComponentGallery.debugRoutes,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: AtomicButton.primary(
                label: 'Open gallery',
                onPressed: () =>
                    Navigator.pushNamed(context, ComponentGallery.route),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open gallery'));
      await _run(tester, const Duration(seconds: 1));
      await _showRing(tester);
      await _expectSpinning(tester, 'open');
      final ring = tester.state(find.ancestor(
          of: _loading,
          matching: find.byWidgetPredicate(
              (w) => '${w.runtimeType}' == '_SimulatedLoading')));

      await tester.binding.handlePopRoute();
      await _run(tester, const Duration(seconds: 1));
      expect(find.byType(ComponentGallery), findsNothing);
      expect(_loading, findsNothing);
      expect(ring.mounted, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      // Already removed: the ring no longer hears lifecycle changes.
      expect(tester.binding.removeObserver(ring as WidgetsBindingObserver),
          isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
