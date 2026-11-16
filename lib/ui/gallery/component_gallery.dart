import 'dart:async';

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
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
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/headers/selection_bar.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:atomic_notes/ui/motion/burst.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/motion/odometer.dart';
import 'package:atomic_notes/ui/motion/orbit_ring.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/checklist_row.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Every `lib/ui` component in its states, in either theme, for screenshots
/// and device checks. Debug builds only: [debugRoutes] is empty otherwise.
class ComponentGallery extends StatefulWidget {
  const ComponentGallery({super.key});

  static const String route = '/ui-gallery';

  /// The gallery's route in debug builds, and nothing in profile or release.
  static Map<String, WidgetBuilder> get debugRoutes => kDebugMode
      ? {route: (_) => const ComponentGallery()}
      : const <String, WidgetBuilder>{};

  /// How long the slide-to-confirm demo pretends to work.
  static const Duration demoWork = Duration(milliseconds: 1200);

  @override
  State<ComponentGallery> createState() => _ComponentGalleryState();
}

class _ComponentGalleryState extends State<ComponentGallery> {
  bool _dark = false;
  bool _busy = false;
  bool _orbit = false;
  bool _pinned = false;
  int _chip = 0;
  bool _done = false;
  bool _sync = true;
  bool _switch = true;
  bool _check = false;
  int _segment = 0;
  int _bursts = 0;
  int _counter = 128;
  int _entrance = 0;
  int _confirmed = 0;
  Timer? _work;
  Completer<void>? _working;
  final _title = TextEditingController();
  final _search = TextEditingController();
  final _code = TextEditingController();
  final _recovery = TextEditingController();
  final _phrase = TextEditingController();

  @override
  void dispose() {
    _work?.cancel();
    final working = _working;
    if (working != null && !working.isCompleted) working.complete();
    _title.dispose();
    _search.dispose();
    _code.dispose();
    _recovery.dispose();
    _phrase.dispose();
    super.dispose();
  }

  void _noop() {}

  /// Stands in for real work, so the control's "Working" state shows.
  Future<void> _confirmDemo() {
    final working = _working = Completer<void>();
    _work = Timer(ComponentGallery.demoWork, () {
      if (mounted) setState(() => _confirmed++);
      working.complete();
    });
    return working.future;
  }

  Future<void> _showDialog(BuildContext context) => showAtomicDialog<bool>(
        context: context,
        title: 'Delete 3 notes?',
        body: 'They move to the Recycle Bin.',
        icon: AtomicIcons.trash,
        destructive: true,
        actions: const [
          AtomicDialogAction(label: 'Cancel', result: false),
          AtomicDialogAction(
              label: 'Delete',
              result: true,
              variant: AtomicButtonVariant.danger),
        ],
      );

  // showAtomicSheet already wraps the builder in AtomicSheetBody.
  Future<void> _showSheet(BuildContext context) => showAtomicSheet<void>(
        context: context,
        builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, children: [
          AtomicSheetAction(
              icon: AtomicIcons.pin,
              label: 'Pin',
              onTap: () => Navigator.of(sheet).pop()),
          AtomicSheetAction(
              icon: AtomicIcons.trash,
              label: 'Delete',
              destructive: true,
              onTap: () => Navigator.of(sheet).pop()),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _dark ? AtomicTheme.dark : AtomicTheme.light,
      child: Builder(builder: (context) {
        final c = context.colors;
        return Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            // Built in full, not lazily: keyboard and switch access can
            // only move to controls that exist, and the long stretches
            // without one (status strips, progress, the dialog preview)
            // would otherwise end traversal halfway down the page.
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AtomicSpace.fabClearance),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AtomicPageHeader(
                    title: 'Component gallery',
                    showTitle: true,
                    actions: [
                      AtomicIconButton(
                        icon: _dark ? AtomicIcons.sun : AtomicIcons.moon,
                        tooltip: _dark ? 'Light theme' : 'Dark theme',
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                    ],
                  ),
                  const PageTitle('Components'),
                  _Section('Buttons', [
                    for (final v in AtomicButtonVariant.values)
                      AtomicButton(label: v.name, variant: v, onPressed: _noop),
                    const AtomicButton(label: 'Disabled', onPressed: null),
                    AtomicButton.primary(
                        label: 'Save', busy: _busy, onPressed: _noop),
                    AtomicButton.tonal(
                      label: _busy ? 'Stop busy' : 'Start busy',
                      onPressed: () => setState(() => _busy = !_busy),
                    ),
                    AtomicButton.primary(
                      label: 'Large, full width',
                      size: AtomicButtonSize.large,
                      expand: true,
                      icon: AtomicIcons.check,
                      onPressed: _noop,
                    ),
                    AtomicButton.tonal(
                        label: 'Compact',
                        size: AtomicButtonSize.compact,
                        onPressed: _noop),
                  ]),
                  _Section('Icon buttons', [
                    AtomicIconButton(
                        icon: AtomicIcons.search,
                        tooltip: 'Search',
                        onPressed: _noop),
                    AtomicIconButton(
                      icon: AtomicIcons.pin,
                      toggledIcon: AtomicIcons.pinFilled,
                      tooltip: _pinned ? 'Unpin' : 'Pin',
                      toggled: _pinned,
                      onPressed: () => setState(() => _pinned = !_pinned),
                    ),
                    AtomicIconButton(
                        icon: AtomicIcons.bell,
                        tooltip: 'Notifications',
                        badgeCount: 12,
                        onPressed: _noop),
                    AtomicIconButton(
                        icon: AtomicIcons.cloudUpload,
                        tooltip: 'Sync',
                        dot: true,
                        onPressed: _noop),
                    const AtomicIconButton(
                        icon: AtomicIcons.share,
                        tooltip: 'Share, unavailable',
                        onPressed: null),
                  ]),
                  _Section('New-note button', [
                    AtomicFab(onPressed: _noop),
                    AtomicFab(onPressed: _noop, atLimit: true),
                  ]),
                  _Section('Chips', [
                    for (final (i, label) in ['All', 'Notes', 'To-dos'].indexed)
                      AtomicFilterChip(
                        label: label,
                        count: [12, 9, 4][i],
                        selected: _chip == i,
                        onSelected: () => setState(() => _chip = i),
                      ),
                    AtomicFilterChip.tag(
                      tag: 'a-very-long-legacy-tag-of-forty-units-xx',
                      count: 120,
                      selected: _chip == 3,
                      onSelected: () => setState(() => _chip = 3),
                    ),
                    TagChip(tag: 'work', onRemove: _noop),
                    AddTagChip(onPressed: _noop),
                    for (final tone in StatusTone.values)
                      StatusChip(tone.name, tone: tone),
                  ]),
                  _Section('Selection bar', [
                    SelectionBar(
                      count: 3,
                      onCancel: _noop,
                      onSelectAll: _noop,
                      onDelete: _noop,
                    ),
                  ]),
                  _Section(
                      'Cards',
                      [
                        AtomicCard(
                          child: Text('A note card surface',
                              style: AtomicType.bodyMedium
                                  .copyWith(color: c.textPrimary)),
                        ),
                      ],
                      stacked: true),
                  _Section(
                      'Rows',
                      [
                        SettingsGroup(label: 'Account', children: [
                          SettingsRow(
                              icon: AtomicIcons.user,
                              title: 'Profile',
                              caption: 'Name and picture',
                              onTap: _noop),
                          SettingsRow(
                              icon: AtomicIcons.bell,
                              title: 'Notifications',
                              count: 3,
                              onTap: _noop),
                          SettingsRow(
                              icon: AtomicIcons.palette,
                              title: 'Appearance',
                              value: 'Light',
                              onTap: _noop),
                          SettingsRow.toggle(
                            icon: AtomicIcons.cloud,
                            title: 'Cloud sync',
                            value: _sync,
                            onChanged: (v) => setState(() => _sync = v),
                          ),
                          SettingsRow(
                              icon: AtomicIcons.trash,
                              title: 'Danger zone',
                              danger: true,
                              onTap: _noop),
                        ]),
                        const SettingsGroup(label: 'Unavailable', children: [
                          SettingsRow(
                              icon: AtomicIcons.lock,
                              title: 'Encryption',
                              caption: 'Sign in first',
                              onTap: null),
                          SettingsRow.toggle(
                              icon: AtomicIcons.fingerprint,
                              title: 'App lock',
                              value: false,
                              onChanged: null),
                        ]),
                        ChecklistRow(
                          text: 'Tap to tick this item',
                          done: _done,
                          onToggle: () => setState(() => _done = !_done),
                          onRemove: _noop,
                          removeTooltip: 'Remove item',
                        ),
                        ChecklistRow(
                          text: 'A featured item, done',
                          done: true,
                          tone: CheckboxTone.featured,
                          onToggle: _noop,
                        ),
                        ChecklistRow(
                          text: 'An important item',
                          done: false,
                          tone: CheckboxTone.important,
                          onToggle: _noop,
                        ),
                        const ChecklistRow(
                            text: 'In selection mode',
                            done: false,
                            onToggle: null),
                        const LedgerRow(
                            title: 'Instant sync',
                            amount: '-2',
                            caption: 'Today'),
                        const LedgerRow(
                            title: 'Refund',
                            amount: '+2',
                            caption: 'Today',
                            icon: AtomicIcons.coin,
                            credit: true),
                      ],
                      stacked: true),
                  _Section(
                      'Fields',
                      [
                        AtomicTextField(
                            controller: _title,
                            label: 'Title',
                            hintText: 'Note title'),
                        const AtomicTextField(
                            label: 'With an error',
                            errorText: 'This field is required'),
                        const AtomicTextField(
                            label: 'Not editable',
                            hintText: 'Read only',
                            enabled: false),
                        SearchField(
                            controller: _search, onCancel: _search.clear),
                        CodeField(controller: _code),
                        CodeField(
                            controller: _recovery,
                            recovery: true,
                            errorText: 'That code was already used'),
                        PhraseField(controller: _phrase),
                      ],
                      stacked: true),
                  _Section('Controls', [
                    AtomicSwitch(
                      value: _switch,
                      onChanged: (v) => setState(() => _switch = v),
                      semanticsLabel: 'Example switch',
                    ),
                    const AtomicSwitch(
                        value: true,
                        onChanged: null,
                        semanticsLabel: 'Disabled switch'),
                    for (final tone in CheckboxTone.values)
                      AtomicCheckbox(
                        checked: _check,
                        tone: tone,
                        onChanged: (v) => setState(() => _check = v),
                        semanticsLabel: 'Example ${tone.name} checkbox',
                      ),
                    const AtomicCheckbox(
                        checked: true,
                        onChanged: null,
                        semanticsLabel: 'Disabled checkbox'),
                    Segmented<int>(
                      segments: const [(0, 'Day'), (1, 'Week'), (2, 'Month')],
                      value: _segment,
                      onChanged: (v) => setState(() => _segment = v),
                    ),
                    Segmented<int>(
                      segments: const [(0, 'Newest'), (1, 'Oldest')],
                      value: 0,
                      onChanged: null,
                    ),
                  ]),
                  _Section(
                      'Banners and empty state',
                      [
                        for (final tone in BannerTone.values)
                          AtomicBanner(
                            tone: tone,
                            icon: AtomicIcons.infoCircle,
                            title: 'A ${tone.name} banner',
                            body: 'One short line of explanation.',
                            action: tone == BannerTone.danger
                                ? AtomicButton.text(
                                    label: 'Try again',
                                    size: AtomicButtonSize.compact,
                                    onPressed: _noop)
                                : null,
                          ),
                        EmptyState(
                          title: 'No notes yet',
                          body: 'Your notes appear here.',
                          actionLabel: 'New note',
                          onAction: _noop,
                        ),
                        for (final level in QuotaLevel.values)
                          StatusStrip(
                            leading: MascotStage(
                              size: 56,
                              child: Icon(AtomicIcons.userCircle,
                                  size: MascotStage.artSize(56),
                                  color: c.textPrimary),
                            ),
                            greeting: 'Good evening',
                            quota: level == QuotaLevel.normal
                                ? '12 / 100'
                                : '98 / 100',
                            quotaLevel: level,
                            detail: 'Quota ${level.name}',
                          ),
                      ],
                      stacked: true),
                  _Section('Progress', [
                    const ProgressRing(semanticsLabel: 'Loading'),
                    const ProgressRing(
                        value: 0.6, semanticsLabel: 'Sixty percent'),
                    const SizedBox(
                        width: 160,
                        child: ProgressBar(
                            value: 0.4, semanticsLabel: 'Uploaded')),
                    SizedBox(
                      width: 200,
                      child: AtomicCard(
                        color: c.accent,
                        child: const ProgressBar(
                            value: 0.9,
                            onAccent: true,
                            semanticsLabel: 'Energy',
                            semanticsValue: '27 of 30'),
                      ),
                    ),
                    const Skeleton(width: 120),
                  ]),
                  _Section('Overlays', [
                    AtomicButton.tonal(
                        label: 'Show dialog',
                        onPressed: () => _showDialog(context)),
                    AtomicButton.tonal(
                        label: 'Show sheet',
                        onPressed: () => _showSheet(context)),
                    AtomicButton.tonal(
                      label: 'Show snack bar',
                      onPressed: () => AtomicSnackBar(
                        text: 'Note saved',
                        millis: 2000,
                        action: AtomicSnackBarAction(
                            label: 'Undo', onPressed: _noop),
                      ).show(context),
                    ),
                    AtomicButton.tonal(
                      label: 'Show error snack bar',
                      onPressed: () => const AtomicSnackBar(
                        text: 'Could not sync',
                        millis: 2000,
                        error: true,
                      ).show(context),
                    ),
                  ]),
                  // The live dialog uses the app's theme, not this page's
                  // switch, so this still copy shows it in the page's theme.
                  // It is a picture: no taps, focus or screen reader actions.
                  const _Section(
                      'Dialog preview',
                      [
                        SizedBox(
                          height: 420,
                          child: IgnorePointer(
                            child: ExcludeFocus(
                              child: ExcludeSemantics(
                                child: AtomicDialog<bool>(
                                  title: 'Leave without saving?',
                                  body: 'Your changes to this note are lost.',
                                  icon: AtomicIcons.alertTriangle,
                                  actions: [
                                    AtomicDialogAction(
                                        label: 'Keep editing', result: false),
                                    AtomicDialogAction(
                                        label: 'Leave',
                                        result: true,
                                        variant: AtomicButtonVariant.danger),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      stacked: true),
                  _Section('Motion', [
                    Ambient(
                      period: const Duration(seconds: 3),
                      builder: (context, t, child) =>
                          Opacity(opacity: 0.4 + 0.6 * t, child: child),
                      child: Icon(AtomicIcons.star, color: c.textPrimary),
                    ),
                    OrbitRing(
                      busy: _orbit,
                      child: Icon(AtomicIcons.cloud, color: c.textPrimary),
                    ),
                    AtomicButton.tonal(
                      label: _orbit ? 'Stop orbit' : 'Start orbit',
                      onPressed: () => setState(() => _orbit = !_orbit),
                    ),
                    Burst(
                      trigger: _bursts,
                      child: AtomicButton.tonal(
                          label: 'Burst',
                          onPressed: () => setState(() => _bursts++)),
                    ),
                    AtomicButton.tonal(
                      label: 'Count up',
                      onPressed: () => setState(() => _counter++),
                    ),
                    Odometer(
                      text: '$_counter',
                      style:
                          AtomicType.titleLarge.copyWith(color: c.textPrimary),
                      semanticsLabel: '$_counter notes',
                    ),
                    AtomicButton.tonal(
                      label: 'Replay entrance',
                      onPressed: () => setState(() => _entrance++),
                    ),
                    EntranceGroup(
                      // A new group runs its entrance again.
                      key: ValueKey(_entrance),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < 2; i++)
                          Entrance(
                            index: i,
                            child: Text('Entrance ${i + 1}',
                                style: AtomicType.bodySmall
                                    .copyWith(color: c.textSecondary)),
                          ),
                        for (var i = 0; i < 3; i++)
                          Stagger(
                            index: i,
                            child: Text('Stagger ${i + 1}',
                                style: AtomicType.bodySmall
                                    .copyWith(color: c.textSecondary)),
                          ),
                      ]),
                    ),
                  ]),
                  _Section(
                      'Slide to confirm',
                      [
                        SlideToConfirm(
                            label: 'confirm the demo',
                            onConfirmed: _confirmDemo),
                        Text('Confirmations: $_confirmed',
                            style: AtomicType.bodySmall
                                .copyWith(color: c.textSecondary)),
                      ],
                      stacked: true),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children, {this.stacked = false});

  final String title;
  final List<Widget> children;

  /// Full-width components (rows, fields, cards) stack one per line instead
  /// of wrapping side by side.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, AtomicSpace.sectionGap, margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A heading of its own, so screen readers can jump between
          // sections and the title never merges into the first demo.
          Semantics(
            header: true,
            container: true,
            child: Text(title,
                style: AtomicType.bodySmall
                    .copyWith(color: context.colors.textSecondary)),
          ),
          const SizedBox(height: AtomicSpace.x3),
          if (stacked)
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: AtomicSpace.chipGap),
              child,
            ]
          else
            Wrap(
              spacing: AtomicSpace.chipGap,
              runSpacing: AtomicSpace.chipGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
        ],
      ),
    );
  }
}
