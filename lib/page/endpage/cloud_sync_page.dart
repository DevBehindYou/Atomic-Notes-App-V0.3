import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/material.dart';

/// Cloud sync (screens spec, Cloud sync): the switch that turns cloud sync
/// on or off, the way to Cloud Notes, and when a change takes effect.
///
/// The choice is stored by [SyncStatusHelper]; the sync button reads it at
/// the moment it is tapped, so no restart is needed.
class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  static const String title = 'Cloud sync';

  /// What the switch means, from the cloud copy proposal (sections 1 and 2).
  static const String onCaption = 'Your notes are saved on your device. With '
      'cloud sync on, Atomic Notes uses its server to sync them with your '
      'Google Drive.';
  static const String offCaption = 'Cloud sync is off. Your notes stay on '
      "this device. Copies already in Google Drive aren't removed.";

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  late bool _on = SyncStatusHelper.isSyncOn;

  /// True while the new choice is being stored; taps wait for it.
  bool _saving = false;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<void> _set(bool value) async {
    if (_saving || value == _on) return;
    setState(() {
      _on = value;
      _saving = true;
    });
    try {
      await SyncStatusHelper.setSyncStatus(value);
    } catch (_) {
      // Show what is stored, not what was asked for.
      if (!mounted) return;
      setState(() {
        _on = SyncStatusHelper.isSyncOn;
        _saving = false;
      });
      const AtomicSnackBar(
        text: "Couldn't change cloud sync. Try again.",
        millis: 3000,
        error: true,
      ).show(context);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    AtomicSnackBar(
      text: value ? 'Cloud sync on' : 'Cloud sync off',
      millis: 2000,
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: EntranceGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _titleAway,
                builder: (context, away, _) => AtomicPageHeader(
                    title: CloudSyncPage.title, showTitle: away),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margin, 0, margin,
                      AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const Entrance(
                        index: 0, child: PageTitle(CloudSyncPage.title)),
                    const SizedBox(height: AtomicSpace.x2),
                    Entrance(
                      index: 1,
                      child: _SyncHero(
                        on: _on,
                        onChanged: _saving ? null : _set,
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    Entrance(
                      index: 2,
                      child: SettingsGroup(children: [
                        SettingsRow(
                          key: const ValueKey('cloud-sync-cloud-notes'),
                          icon: AtomicIcons.arrowsExchange,
                          title: 'Cloud notes',
                          caption: 'Compare this device with the cloud',
                          onTap: () =>
                              Navigator.pushNamed(context, '/cloudnotes'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    const Entrance(
                      index: 3,
                      child: AtomicBanner(
                        tone: BannerTone.info,
                        icon: AtomicIcons.infoCircle,
                        title: 'Changes take effect immediately',
                        body: 'No restart needed. The sync button reads this '
                            'setting each time you tap it.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero card: the whole card is the one switch, so screen readers hear
/// one toggle, not a card and a switch.
class _SyncHero extends StatelessWidget {
  const _SyncHero({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onChanged = this.onChanged;
    final caption = on ? CloudSyncPage.onCaption : CloudSyncPage.offCaption;
    return AtomicPressable(
      key: const ValueKey('cloud-sync-switch'),
      button: false,
      toggled: on,
      semanticsLabel: '${CloudSyncPage.title}. $caption',
      excludeSemantics: true,
      haptic: AtomicHaptic.selection,
      borderRadius: AtomicRadius.largeAll,
      onTap: onChanged == null ? null : () => onChanged(!on),
      child: AtomicCard(
        padding: const EdgeInsets.all(AtomicSpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(on ? AtomicIcons.cloudCheck : AtomicIcons.cloudOff,
                    size: 28, color: c.textPrimary),
                const SizedBox(width: AtomicSpace.x3),
                Expanded(
                  child: Text(
                    CloudSyncPage.title,
                    style: AtomicType.titleLarge.copyWith(color: c.textPrimary),
                  ),
                ),
                const SizedBox(width: AtomicSpace.x3),
                AtomicSwitchTrack(value: on, enabled: onChanged != null),
              ],
            ),
            const SizedBox(height: AtomicSpace.x3),
            AnimatedSwitcher(
              duration: AtomicMotion.fade(context, AtomicMotion.quick),
              child: Text(
                caption,
                key: ValueKey(on),
                style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
