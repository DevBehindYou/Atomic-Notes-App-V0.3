import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/chips/tag_chip.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/headers/selection_bar.dart';
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

  @override
  State<ComponentGallery> createState() => _ComponentGalleryState();
}

class _ComponentGalleryState extends State<ComponentGallery> {
  bool _dark = false;
  bool _busy = false;
  bool _pinned = false;
  int _chip = 0;

  void _noop() {}

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _dark ? AtomicTheme.dark : AtomicTheme.light,
      child: Builder(builder: (context) {
        final c = context.colors;
        return Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AtomicSpace.fabClearance),
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
                    label: 'Tap to toggle busy',
                    busy: _busy,
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
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, AtomicSpace.sectionGap, margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: AtomicType.bodySmall
                  .copyWith(color: context.colors.textSecondary)),
          const SizedBox(height: AtomicSpace.x3),
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
