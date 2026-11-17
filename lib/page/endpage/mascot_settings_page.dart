import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_cubit.dart';
import 'package:atomic_notes/mascot/mascot_frame_source.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_bloc/flutter_bloc.dart';

typedef MascotArtworkBuilder = Widget Function(
    BuildContext context, MascotDefinition mascot, bool animate);

/// Mascot settings (screens spec, Mascot settings): the chosen mascot on a
/// large stage, the switch that animates it, and the seven bundled mascots
/// to choose from.
///
/// The choice and the switch are stored by [MascotCubit] on this device, as
/// before. Only the large mascot animates (one ambient loop, ADR-011); the
/// cards show still artwork. `MascotView` keeps every playback rule: it stops
/// under reduced motion, while another route covers this one, in the
/// background and when it leaves the tree.
class MascotSettingsPage extends StatefulWidget {
  /// [artworkBuilder] and [frameSource] are only given by tests: the first
  /// replaces the artwork with a stand-in, the second feeds the real
  /// `MascotView` synthetic frames instead of decoding the bundled clips.
  const MascotSettingsPage(
      {super.key,
      required this.preferences,
      required this.resolver,
      this.artworkBuilder,
      this.frameSource});

  final MascotCubit preferences;
  final MascotAssetResolver resolver;
  final MascotArtworkBuilder? artworkBuilder;
  final MascotFrameSource? frameSource;

  static const String title = 'Mascot';
  static const String touchHint =
      'Touch your mascot to change its animation. Your choice stays on this device.';
  static const String includedText =
      'All 7 mascots are included and work offline. Each has four animations.';
  static const String readOnlyText =
      'These settings were saved by a newer app. Update the app to change them.';
  static const String animateCaption =
      'Randomly play the four animations of your favorite.';
  static const String reducedCaption =
      'System reduced motion is on. Mascots stay still.';

  /// The hero stage, and each card's stage (components spec, Mascot stage).
  static const double heroStage = 160;
  static const double cardStage = 88;

  @override
  State<MascotSettingsPage> createState() => _MascotSettingsPageState();
}

class _MascotSettingsPageState extends State<MascotSettingsPage> {
  final ScrollController _scroll = ScrollController();

  /// Whether the large title has scrolled away, so the header shows it.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  /// Whether any of the hero card is on screen. Once it has scrolled away
  /// the large mascot pauses (through [TickerMode], which `MascotView`
  /// follows) even while the list still keeps it built.
  final ValueNotifier<bool> _heroShown = ValueNotifier(true);
  final GlobalKey _heroKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    _titleAway.value = _scroll.hasClients && _scroll.offset > AtomicSpace.x10;
    final box = _heroKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scroll.hasClients) {
      // Not built: the list has already dropped it, so nothing plays.
      return;
    }
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    _heroShown.value = _scroll.offset < top + box.size.height;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleAway.dispose();
    _heroShown.dispose();
    super.dispose();
  }

  Widget _art(BuildContext context, MascotDefinition mascot, bool animate) {
    final builder = widget.artworkBuilder;
    if (builder != null) return builder(context, mascot, animate);
    final stage =
        animate ? MascotSettingsPage.heroStage : MascotSettingsPage.cardStage;
    return MascotView(
        mascot: mascot,
        resolver: widget.resolver,
        frameSource: widget.frameSource,
        // The tappable mascot draws a 2 dp focus border around its art.
        size: MascotStage.artSize(stage) - (animate ? 4 : 0),
        interactive: animate,
        animationsEnabled:
            animate && widget.preferences.state.desired.animationsEnabled,
        routeVisible: ModalRoute.of(context)?.isCurrent ?? true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final preferences = widget.preferences;
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
                    title: MascotSettingsPage.title, showTitle: away),
              ),
              Expanded(
                child: BlocBuilder<MascotCubit, MascotState>(
                  bloc: preferences,
                  builder: (context, state) {
                    final favorite =
                        MascotCatalog.findById(state.desired.selectedId) ??
                            MascotCatalog.defaultMascot;
                    final readOnly =
                        state.saveState == MascotSaveState.readOnly;
                    final reduced = MediaQuery.disableAnimationsOf(context);
                    return ListView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                          margin,
                          0,
                          margin,
                          AtomicSpace.x8 +
                              MediaQuery.paddingOf(context).bottom),
                      children: [
                        const Entrance(
                            index: 0,
                            child: PageTitle(MascotSettingsPage.title)),
                        const SizedBox(height: AtomicSpace.x2),
                        Entrance(
                          index: 1,
                          child: _Hero(
                            key: _heroKey,
                            favorite: favorite,
                            art: ValueListenableBuilder<bool>(
                              valueListenable: _heroShown,
                              builder: (context, shown, art) =>
                                  TickerMode(enabled: shown, child: art!),
                              child: _art(context, favorite, true),
                            ),
                            saveState: state.saveState,
                          ),
                        ),
                        if (readOnly) ...[
                          const SizedBox(height: AtomicSpace.x4),
                          const Entrance(
                            index: 2,
                            child: AtomicBanner(
                              key: ValueKey('mascot-read-only'),
                              tone: BannerTone.info,
                              icon: AtomicIcons.infoCircle,
                              title: MascotSettingsPage.readOnlyText,
                            ),
                          ),
                        ],
                        if (state.saveState == MascotSaveState.error) ...[
                          const SizedBox(height: AtomicSpace.x4),
                          Entrance(
                            index: 2,
                            child: AtomicBanner(
                              key: const ValueKey('mascot-save-error'),
                              tone: BannerTone.attention,
                              icon: AtomicIcons.alertTriangle,
                              title: 'Your choice could not be saved yet.',
                              action: AtomicButton.tonal(
                                key: const ValueKey('mascot-retry-save'),
                                label: 'Retry save',
                                size: AtomicButtonSize.compact,
                                onCard: true,
                                onPressed: preferences.retrySave,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AtomicSpace.x6),
                        Entrance(
                          index: 3,
                          child: SettingsGroup(children: [
                            SettingsRow.toggle(
                              key: const ValueKey('mascot-animate'),
                              icon: AtomicIcons.userCircle,
                              title: 'Animate mascot',
                              caption: reduced
                                  ? MascotSettingsPage.reducedCaption
                                  : MascotSettingsPage.animateCaption,
                              value: state.desired.animationsEnabled,
                              onChanged: readOnly
                                  ? null
                                  : preferences.setAnimationsEnabled,
                            ),
                          ]),
                        ),
                        const SizedBox(height: AtomicSpace.x6),
                        Entrance(
                          index: 4,
                          child: _MascotGrid(
                            favoriteId: favorite.id,
                            art: (mascot) => _art(context, mascot, false),
                            onSelect: readOnly
                                ? null
                                : (mascot) =>
                                    preferences.selectMascot(mascot.id),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen mascot on the large stage, its name, what touching it does,
/// and whether the choice is stored yet.
class _Hero extends StatelessWidget {
  const _Hero(
      {super.key,
      required this.favorite,
      required this.art,
      required this.saveState});

  final MascotDefinition favorite;
  final Widget art;
  final MascotSaveState saveState;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saved = switch (saveState) {
      MascotSaveState.pending => ('Saving your choice…', AtomicIcons.clock),
      MascotSaveState.saved => ('Saved on this device', AtomicIcons.check),
      _ => null,
    };
    return AtomicCard(
      padding: const EdgeInsets.all(AtomicSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Its own node, so screen readers hear the mascot button without
          // the texts below it.
          Center(
              child: Semantics(container: true, child: _HeroStage(art: art))),
          const SizedBox(height: AtomicSpace.x4),
          MergeSemantics(
            child: Column(
              children: [
                Text('Your mascot',
                    textAlign: TextAlign.center,
                    style:
                        AtomicType.bodySmall.copyWith(color: c.textSecondary)),
                Text(favorite.displayName,
                    key: const ValueKey('mascot-hero-name'),
                    textAlign: TextAlign.center,
                    style: AtomicType.headlineMedium
                        .copyWith(color: c.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: AtomicSpace.x3),
          Text(MascotSettingsPage.touchHint,
              textAlign: TextAlign.center,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
          const SizedBox(height: AtomicSpace.x2),
          Text(MascotSettingsPage.includedText,
              textAlign: TextAlign.center,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
          if (saved != null) ...[
            const SizedBox(height: AtomicSpace.x3),
            Center(
              child: StatusChip(saved.$1,
                  key: const ValueKey('mascot-save-status'), icon: saved.$2),
            ),
          ],
        ],
      ),
    );
  }
}

/// The large stage. The art is clipped to the disc, so its square light
/// ground never shows past the edge on the dark canvas; the clip would also
/// hide the mascot's own square focus border, so a ring around the disc
/// shows keyboard focus instead.
class _HeroStage extends StatefulWidget {
  const _HeroStage({required this.art});

  final Widget art;

  @override
  State<_HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<_HeroStage> {
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        final ring = focused &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional;
        if (ring != _ring) setState(() => _ring = ring);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: _ring ? c.focus : const Color(0x00000000), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: MascotStage(
            size: MascotSettingsPage.heroStage,
            child: ClipOval(child: widget.art),
          ),
        ),
      ),
    );
  }
}

/// The seven bundled mascots in catalog order, two to a row while a card
/// keeps room for its stage and name at the current text size, else one.
class _MascotGrid extends StatelessWidget {
  const _MascotGrid(
      {required this.favoriteId, required this.art, required this.onSelect});

  final String favoriteId;
  final Widget Function(MascotDefinition mascot) art;
  final ValueChanged<MascotDefinition>? onSelect;

  static const double _gap = AtomicSpace.x3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    const mascots = MascotCatalog.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AtomicSpace.x1, bottom: AtomicSpace.x2),
          child: Text('Choose your mascot',
              style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final minCard = MascotSettingsPage.cardStage +
              AtomicSpace.x4 * 2 +
              (scale - 1).clamp(0, 4) * 120;
          final columns = constraints.maxWidth >= minCard * 2 + _gap ? 2 : 1;
          final rows = <Widget>[];
          for (var i = 0; i < mascots.length; i += columns) {
            final cells = <Widget>[];
            for (var j = 0; j < columns; j++) {
              if (j > 0) cells.add(const SizedBox(width: _gap));
              final index = i + j;
              cells.add(Expanded(
                child: index < mascots.length
                    ? Stagger(
                        index: index,
                        child: _MascotCard(
                          mascot: mascots[index],
                          selected: mascots[index].id == favoriteId,
                          art: art(mascots[index]),
                          onSelect: onSelect,
                        ),
                      )
                    : const SizedBox.shrink(),
              ));
            }
            if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
            rows.add(IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ));
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
        }),
      ],
    );
  }
}

/// One radio card: the whole card picks the mascot. The chosen one shows a
/// "Selected" accent chip and is marked selected for screen readers.
class _MascotCard extends StatelessWidget {
  const _MascotCard(
      {required this.mascot,
      required this.selected,
      required this.art,
      required this.onSelect});

  final MascotDefinition mascot;
  final bool selected;
  final Widget art;
  final ValueChanged<MascotDefinition>? onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onSelect = this.onSelect;
    return AtomicPressable(
      key: ValueKey('choose-${mascot.id}'),
      selected: selected,
      semanticsLabel:
          selected ? mascot.displayName : 'Use ${mascot.displayName}',
      excludeSemantics: true,
      haptic: AtomicHaptic.selection,
      borderRadius: AtomicRadius.largeAll,
      onTap: onSelect == null ? null : () => onSelect(mascot),
      child: SizedBox.expand(
        child: AtomicCard(
          color: selected ? c.surfaceRaised : null,
          padding: const EdgeInsets.all(AtomicSpace.x4),
          child: Column(
            children: [
              MascotStage(
                size: MascotSettingsPage.cardStage,
                child: ClipOval(child: art),
              ),
              const SizedBox(height: AtomicSpace.x3),
              Text(mascot.displayName,
                  textAlign: TextAlign.center,
                  style: AtomicType.titleMedium.copyWith(color: c.textPrimary)),
              const SizedBox(height: AtomicSpace.x2),
              const Spacer(),
              selected
                  ? const StatusChip('Selected',
                      tone: StatusTone.accent, icon: AtomicIcons.check)
                  : const StatusChip('Use'),
            ],
          ),
        ),
      ),
    );
  }
}
