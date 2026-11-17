import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/energy/energy_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/motion/odometer.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:atomic_notes/utility/web_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The dedicated Atomic Energy + Atomic Coins screen (screens spec, Energy).
/// Reads everything through [EnergyCubit] from [EnergyService]; never
/// computes a balance itself. Costs, tiers and limits come from the Server's
/// policy in the state, never from constants here.
class EnergyPage extends StatelessWidget {
  /// [store] and [notes] are only given by tests; the app uses the real ones.
  const EnergyPage({super.key, this.store, this.notes});

  final EnergyStore? store;
  final NotesSource? notes;

  static const String title = 'Atomic Energy';

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EnergyCubit>(
      // Read fresh balances as soon as the screen opens; it draws the cached ones meanwhile.
      create: (_) => EnergyCubit(
        store: store ?? EnergyService.instance,
        notes: notes ?? NotesRepository.instance,
      )..refresh(),
      child: const _EnergyView(),
    );
  }
}

class _EnergyView extends StatefulWidget {
  const _EnergyView();

  @override
  State<_EnergyView> createState() => _EnergyViewState();
}

class _EnergyViewState extends State<_EnergyView> {
  EnergyCubit get _cubit => context.read<EnergyCubit>();

  /// How many activity rows are visible; "Load more" adds another page.
  static const int _pageSize = 7;
  int _shown = _pageSize;

  /// Whether the coin credit batches are open.
  bool _batchesOpen = false;

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

  void _say(String text, int millis) =>
      AtomicSnackBar(text: text, millis: millis).show(context);

  // ---- actions ----------------------------------------------------------

  Future<void> _convert() async {
    final now = _cubit.state;
    final maxCoins = now.coins;
    if (maxCoins <= 0) {
      _say('No Atomic Coins to convert yet.', 2000);
      return;
    }
    final chosen = await showAtomicSheet<int>(
      context: context,
      builder: (ctx) => _ConvertSheet(
        maxCoins: maxCoins,
        energy: now.energy,
        energyCap: now.energyCap,
      ),
    );
    if (chosen == null || chosen <= 0 || !mounted) return;
    final err = await _cubit.convertCoins(chosen);
    if (!mounted) return;
    _say(
      err ??
          'Converted $chosen coin${chosen == 1 ? '' : 's'} to '
              '${chosen * EnergyService.coinToEnergy} energy.',
      2500,
    );
  }

  Future<void> _retryConversion() async {
    final error = await _cubit.retryPendingConversion();
    if (mounted) {
      _say(error ?? 'Conversion confirmed. Balance refreshed.', 3000);
    }
  }

  Future<void> _raiseLimit() async {
    final cubit = _cubit;
    final now = cubit.state;
    final tier = now.nextTier;
    if (tier == null) return; // already at the ceiling; the button is hidden
    final confirmed = await showAtomicDialog<bool>(
      context: context,
      // Spending coins: only the buttons close it, as before.
      barrierDismissible: false,
      icon: AtomicIcons.coin,
      title: 'Become ${tier.name}?',
      body: 'Spend ${tier.costCoins} coins to become ${tier.name} and raise '
          'your note limit from ${now.noteLimit} to ${tier.limit}?',
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: 'Confirm',
          result: true,
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    final err = await cubit.upgradeNoteLimit();
    if (!mounted) return;
    _say(err ?? "You're ${tier.name} now — you can keep ${tier.limit} notes.",
        3000);
  }

  void _needCoins() {
    final now = _cubit.state;
    final tier = now.nextTier;
    if (tier == null) return;
    _say(
      'Becoming ${tier.name} costs ${tier.costCoins} coins. '
      'You have ${now.coins}.',
      3000,
    );
  }

  Future<void> _loadMoreBatches() async {
    final message = await _cubit.loadMoreCoinBatches();
    if (message != null && mounted) _say(message, 3000);
  }

  /// Coins aren't sold in the App yet. The sheet sends people to the website,
  /// where supporting the project earns Atomic Coins early. The sheet names no
  /// payment platform: the website does.
  void _coinStore() {
    final email = ApiClient.instance.currentUserEmail;
    showAtomicSheet<void>(
      context: context,
      builder: (ctx) => _CoinStoreSheet(
        email: email,
        onSupport: () async {
          Navigator.of(ctx).pop();
          final opened = await WebLinks.open(WebLinks.support);
          if (!mounted) return;
          if (!opened) {
            _say("Couldn't open the browser. Visit ${WebLinks.support}", 4000);
          }
        },
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                builder: (context, away, _) =>
                    AtomicPageHeader(title: EnergyPage.title, showTitle: away),
              ),
              Expanded(
                child: BlocBuilder<EnergyCubit, EnergyState>(
                  builder: (context, state) {
                    // Loading state (first load, nothing cached yet).
                    if (state.loading && !state.hasLoaded) {
                      return const Center(
                        child: ProgressRing(
                          key: ValueKey('energy-loading'),
                          semanticsLabel: 'Loading Atomic Energy',
                        ),
                      );
                    }
                    return RefreshIndicator(
                      color: c.accent,
                      onRefresh: _cubit.refresh,
                      child: _list(context, state),
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

  Widget _list(BuildContext context, EnergyState state) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final details = state.wallet.coinDetails;
    var block = 1;
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(margin, 0, margin,
          AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
      children: [
        const Entrance(index: 0, child: PageTitle(EnergyPage.title)),
        const SizedBox(height: AtomicSpace.x4),
        Entrance(index: block++, child: _EnergyHero(state: state)),
        const SizedBox(height: AtomicSpace.x3),
        Entrance(index: block++, child: _coinsCard(state)),
        const SizedBox(height: AtomicSpace.sectionGap),
        Entrance(index: block++, child: _capacity(state)),
        if (details != null) ...[
          const SizedBox(height: AtomicSpace.sectionGap),
          Entrance(index: block++, child: _coinExpiry(details)),
        ],
        const SizedBox(height: AtomicSpace.sectionGap),
        ..._activity(state, block++),
        const SizedBox(height: AtomicSpace.sectionGap),
        Entrance(
          index: block++,
          child: SettingsGroup(children: [
            SettingsRow(
              key: const ValueKey('energy-how-it-works'),
              icon: AtomicIcons.helpCircle,
              title: 'How Atomic Energy works',
              onTap: () => Navigator.pushNamed(context, '/energyintro'),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _coinsCard(EnergyState state) {
    final c = context.colors;
    final coins = state.coins;
    final noCoins = coins <= 0;
    return AtomicCard(
      key: const ValueKey('energy-coins'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ExcludeSemantics(
                child:
                    AtomicIcon.coin(size: 40, set: 'Icons-Without-label-2.5D'),
              ),
              const SizedBox(width: AtomicSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$coins coin${coins == 1 ? '' : 's'}',
                      style: AtomicType.numeric(AtomicType.headlineMedium)
                          .copyWith(color: c.textPrimary),
                    ),
                    Text(
                      '1 coin = ${EnergyService.coinToEnergy} energy',
                      style:
                          AtomicType.bodySmall.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AtomicSpace.x4),
          // The buttons share a line while they fit and stack otherwise.
          Wrap(
            spacing: AtomicSpace.x2,
            runSpacing: AtomicSpace.x2,
            children: [
              AtomicButton.secondary(
                key: const ValueKey('energy-get-coins'),
                label: 'Get coins',
                icon: AtomicIcons.plus,
                onPressed: _coinStore,
              ),
              AtomicButton.tonal(
                key: const ValueKey('energy-convert'),
                label: noCoins ? 'No coins to convert' : 'Convert',
                icon: AtomicIcons.bolt,
                onCard: true,
                onPressed: noCoins ? null : _convert,
              ),
            ],
          ),
          const SizedBox(height: AtomicSpace.x2),
          AtomicButton.text(
            key: const ValueKey('energy-retry-conversion'),
            label: 'Retry unconfirmed conversion',
            icon: AtomicIcons.refresh,
            onPressed: _retryConversion,
          ),
        ],
      ),
    );
  }

  /// How many notes the account can hold, the tiers, and the way to raise it
  /// with coins.
  Widget _capacity(EnergyState state) {
    final c = context.colors;
    final l = state.limits;
    final used = state.notesUsed;
    final limit = state.noteLimit;
    final next = state.nextTier;
    final currentTier = l.tierFor(limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(currentTier?.name ?? 'Note capacity'),
        Text(
          '$used of $limit notes used',
          style: AtomicType.numeric(AtomicType.bodyMedium)
              .copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AtomicSpace.x3),
        _TierRow(tiers: l.noteLimitTiers, limit: limit, next: next),
        const SizedBox(height: AtomicSpace.x3),
        Text(
          next == null
              ? 'This is the most notes an account can hold.'
              : 'Become ${next.name} for ${next.costCoins} coins to hold '
                  '${next.limit} notes.',
          style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
        ),
        if (next != null) ...[
          const SizedBox(height: AtomicSpace.x3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AtomicButton.primary(
              key: const ValueKey('energy-raise-limit'),
              label: 'Become ${next.name} · ${next.costCoins} coins',
              icon: AtomicIcons.plus,
              onPressed: state.canAffordNoteLimit ? _raiseLimit : _needCoins,
            ),
          ),
        ],
      ],
    );
  }

  Widget _coinExpiry(CoinDetails details) {
    final c = context.colors;
    final secondary = AtomicType.bodySmall.copyWith(color: c.textSecondary);
    final primary = AtomicType.bodyMedium.copyWith(color: c.textPrimary);
    return Column(
      key: const ValueKey('energy-coin-expiry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Coin expiry'),
        AtomicCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AtomicSpace.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'New coins expire six calendar months after credit. '
                        'Coins expiring soonest are used first. Existing '
                        'coins from before the policy do not expire. Energy '
                        'and capacity already obtained are unchanged.',
                        style: secondary),
                    const SizedBox(height: AtomicSpace.x3),
                    Text('${details.nonExpiring} coins never expire.',
                        style: primary),
                    if (details.nextExpiryAt != null)
                      Text(
                          '${details.nextExpiryCoins} coins next expire '
                          '${_stamp(details.nextExpiryAt!)} (local time).',
                          style: primary),
                    const SizedBox(height: AtomicSpace.x2),
                    Text(
                        'Last checked ${_stamp(details.serverTime)}. Refresh '
                        'for the current balance; the Server confirms '
                        'spending.',
                        style: secondary),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.outline),
              AtomicPressable(
                key: const ValueKey('energy-credit-batches'),
                button: true,
                semanticsLabel: 'Credit batches',
                excludeSemantics: true,
                borderRadius: BorderRadius.zero,
                onTap: () => setState(() => _batchesOpen = !_batchesOpen),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: SettingsRow.minHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Credit batches',
                              style: AtomicType.titleMedium
                                  .copyWith(color: c.textPrimary)),
                        ),
                        const SizedBox(width: AtomicSpace.x3),
                        AnimatedRotation(
                          turns: _batchesOpen ? 0.5 : 0,
                          duration:
                              AtomicMotion.move(context, AtomicMotion.standard),
                          curve: AtomicMotion.standardCurve,
                          child: Icon(AtomicIcons.chevronDown,
                              size: 20, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: AtomicMotion.move(context, AtomicMotion.standard),
                curve: AtomicMotion.emphasizedCurve,
                alignment: AlignmentDirectional.topStart,
                child: !_batchesOpen
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final batch in details.rows)
                            LedgerRow(
                              key: ValueKey('energy-batch-${batch.id}'),
                              icon: AtomicIcons.coin,
                              title: '${batch.remaining} of ${batch.amount} '
                                  'coins remaining',
                              caption: 'Credited ${_stamp(batch.creditedAt)}\n'
                                  '${batch.expiresAt == null ? 'Never expires' : 'Expiry ${_stamp(batch.expiresAt!)}'}'
                                  ' · local time',
                              amount: '+${batch.amount}',
                              credit: true,
                            ),
                          if (details.nextCursor != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(AtomicSpace.x2,
                                  0, AtomicSpace.x2, AtomicSpace.x2),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: AtomicButton.text(
                                  key: const ValueKey(
                                      'energy-load-more-batches'),
                                  label: 'Load more batches',
                                  onPressed: _loadMoreBatches,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _activity(EnergyState state, int block) {
    final c = context.colors;
    final all = state.history;
    final shown = all.take(_shown).toList();
    Widget note(String text) => AtomicCard(
          key: const ValueKey('energy-activity-note'),
          child: Text(text,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
        );
    return [
      Entrance(
        index: block,
        child: Row(
          children: [
            const Expanded(child: _SectionLabel('Activity', bottom: 0)),
            AtomicIconButton(
              key: const ValueKey('energy-activity-refresh'),
              icon: AtomicIcons.refresh,
              tooltip: 'Refresh activity',
              onPressed: () {
                setState(() => _shown = _pageSize);
                _cubit.refresh();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: AtomicSpace.x2),
      if (state.error != null)
        Entrance(
            index: block,
            child: note('Could not load activity. Pull down to retry.'))
      else if (all.isEmpty)
        Entrance(
            index: block,
            child: note('No transactions yet. Daily energy and conversions '
                'will show up here.'))
      else ...[
        AtomicCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tx) in shown.indexed) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 1,
                      indent: AtomicSpace.x4 + 32 + AtomicSpace.x3,
                      color: c.outline),
                Stagger(
                  key: ValueKey('energy-tx-${tx.id}'),
                  index: i,
                  child: _ActivityRow(tx: tx, stamp: _stamp(tx.createdAt)),
                ),
              ],
            ],
          ),
        ),
        if (all.length > _shown) ...[
          const SizedBox(height: AtomicSpace.x2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AtomicButton.text(
              key: const ValueKey('energy-load-more'),
              label: 'Load more',
              icon: AtomicIcons.chevronDown,
              onPressed: () => setState(() => _shown += _pageSize),
            ),
          ),
        ],
      ],
    ];
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }
}

/// A section's small label, read as a header.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.bottom = AtomicSpace.x2});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsetsDirectional.only(start: AtomicSpace.x1, bottom: bottom),
      child: Semantics(
        header: true,
        child: Text(text,
            style: AtomicType.titleMedium
                .copyWith(color: context.colors.textPrimary)),
      ),
    );
  }
}

/// The energy hero (components spec, Hero stat card) on the accent fill:
/// the balance rolls like an odometer and the bar grows to it.
class _EnergyHero extends StatelessWidget {
  const _EnergyHero({required this.state});

  final EnergyState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final energy = state.energy;
    final cap = state.energyCap;
    final l = state.limits;
    final on = c.onAccent;
    return AtomicCard(
      key: const ValueKey('energy-hero'),
      color: c.accent,
      padding: const EdgeInsets.all(AtomicSpace.heroPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: 'Atomic energy, $energy of $cap',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Atomic energy',
                            style: AtomicType.titleMedium.copyWith(color: on)),
                      ),
                      const SizedBox(width: AtomicSpace.x3),
                      const AtomicIcon('atom',
                          size: 40, set: 'Icons-Without-label-2.5D'),
                    ],
                  ),
                  const SizedBox(height: AtomicSpace.x2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: AtomicSpace.x2,
                    children: [
                      Odometer(
                        key: const ValueKey('energy-balance'),
                        text: '$energy',
                        style: AtomicType.display.copyWith(color: on),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AtomicSpace.x1),
                        child: Text('of $cap',
                            style: AtomicType.numeric(AtomicType.bodyLarge)
                                .copyWith(color: on)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AtomicSpace.x4),
          // Its own node, so the level is read on its own.
          Semantics(
            container: true,
            child: ProgressBar(
              key: const ValueKey('energy-bar'),
              value: state.wallet.energyFraction,
              onAccent: true,
              semanticsLabel: 'Energy level',
              semanticsValue: '$energy of $cap',
            ),
          ),
          const SizedBox(height: AtomicSpace.x4),
          Text(
            '+20 energy every 24h, up to $cap. Each automatic upload batch '
            'costs ${l.syncStandardCost} energy; the hourly window is shared '
            'across your account. Each instant upload batch costs '
            '${l.syncInstantCost}. Large syncs can use multiple batches. '
            'Receive-only sync is free. Local notes are always free.',
            style: AtomicType.bodySmall.copyWith(color: on),
          ),
        ],
      ),
    );
  }
}

/// The note-limit tiers as a horizontal row of cards: the current one on the
/// inverse fill, labelled "Current"; later ones show their cost, the next one
/// with an accent edge.
class _TierRow extends StatelessWidget {
  const _TierRow(
      {required this.tiers, required this.limit, required this.next});

  final List<NoteLimitTier> tiers;
  final int limit;
  final NoteLimitTier? next;

  /// The asset name for a tier's particle icon: the tier names are already
  /// exactly the SVG file names (`assets/Atomic Icons/*/tachyon.svg` etc.),
  /// lowercased.
  static String _icon(String tierName) => tierName.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Wider with larger text, so names wrap less; never wider than most of
    // the screen, so the next card always peeks in.
    final screen = MediaQuery.sizeOf(context).width;
    final width = MediaQuery.textScalerOf(context)
        .scale(132)
        .clamp(132.0, screen * 0.7)
        .toDouble();
    return SingleChildScrollView(
      key: const ValueKey('energy-tiers'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, tier) in tiers.indexed) ...[
              if (i > 0) const SizedBox(width: AtomicSpace.x2),
              Stagger(
                index: i,
                child: _tierCard(c, tier, width),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tierCard(AtomicColors c, NoteLimitTier tier, double width) {
    final current = tier.limit == limit;
    final owned = tier.limit < limit;
    final isNext = tier == next;
    final fg = current ? c.onInverse : c.textPrimary;
    final fg2 = current ? c.onInverse : c.textSecondary;
    final status = current
        ? 'Current'
        : owned
            ? null
            : '${tier.costCoins} coins';
    return Semantics(
      container: true,
      label: [tier.name, '${tier.limit} notes', status]
          .whereType<String>()
          .join('. '),
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('capacity-${tier.limit}'),
          width: width,
          padding: const EdgeInsets.all(AtomicSpace.x3),
          decoration: BoxDecoration(
            color: current ? c.inverseSurface : c.surface,
            borderRadius: AtomicRadius.mediumAll,
            border: Border.all(
              color: isNext
                  ? c.accentText
                  : (current ? c.inverseSurface : c.outline),
              width: isNext ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AtomicIcon(_icon(tier.name),
                  size: 32, set: 'Icons-Without-label-2.5D'),
              const SizedBox(height: AtomicSpace.x2),
              Text(tier.name,
                  style: AtomicType.titleMedium.copyWith(color: fg)),
              Text('${tier.limit} notes',
                  style: AtomicType.numeric(AtomicType.bodySmall)
                      .copyWith(color: fg2)),
              if (status != null) ...[
                const SizedBox(height: AtomicSpace.x2),
                if (current)
                  DecoratedBox(
                    decoration: BoxDecoration(
                        color: c.accent, borderRadius: AtomicRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AtomicSpace.x2, vertical: 2),
                      child: Text(status,
                          style: AtomicType.labelMedium
                              .copyWith(color: c.onAccent)),
                    ),
                  )
                else
                  Text(status,
                      style: AtomicType.numeric(AtomicType.labelLarge).copyWith(
                          color: isNext ? c.accentText : c.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One activity row: a 32 icon tile, what happened, when, and the deltas.
/// Credits read in the accent text colour, spending in the secondary one.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.tx, required this.stamp});

  final EnergyTx tx;
  final String stamp;

  static String _signed(int value) => value > 0 ? '+$value' : '−${value.abs()}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final coinKind =
        tx.kind == EnergyTxKind.purchase || tx.kind == EnergyTxKind.convert;
    // Prefer the specific note ("Instant sync", "Standard sync", "Daily
    // energy grant", "Welcome gift…") over the generic kind label, so the
    // user sees exactly where energy/coins went.
    final description =
        (tx.note != null && tx.note!.isNotEmpty) ? tx.note! : tx.kind.label;
    final deltas = [
      if (tx.energyDelta != 0)
        (text: '${_signed(tx.energyDelta)} energy', credit: tx.energyDelta > 0),
      if (tx.coinsDelta != 0)
        (text: '${_signed(tx.coinsDelta)} coins', credit: tx.coinsDelta > 0),
    ];
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: c.surfaceInset, shape: BoxShape.circle),
                  child: Icon(coinKind ? AtomicIcons.coin : AtomicIcons.bolt,
                      size: 18, color: c.textPrimary),
                ),
                const SizedBox(width: AtomicSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AtomicType.bodyLarge
                              .copyWith(color: c.textPrimary)),
                      Text(stamp,
                          style: AtomicType.numeric(AtomicType.bodySmall)
                              .copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
                if (deltas.isNotEmpty) ...[
                  const SizedBox(width: AtomicSpace.x3),
                  // At most 40 % of the row, wrapping inside it, so a long
                  // amount at large text never pushes the row past its edge.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in deltas)
                          Text(d.text,
                              textAlign: TextAlign.end,
                              style: AtomicType.numeric(AtomicType.titleMedium)
                                  .copyWith(
                                      color: d.credit
                                          ? c.accentText
                                          : c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coin store sheet: coins aren't sold in the App, so it points to the
/// website and shows the account email to quote when supporting.
class _CoinStoreSheet extends StatelessWidget {
  const _CoinStoreSheet({
    required this.email,
    required this.onSupport,
    required this.onDismiss,
  });

  final String? email;
  final VoidCallback onSupport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final email = this.email;
    return Column(
      key: const ValueKey('energy-coin-store'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Coin store',
            style: AtomicType.labelLarge.copyWith(color: c.accentText)),
        const SizedBox(height: AtomicSpace.x2),
        Semantics(
          header: true,
          child: Text('Get Atomic Coins early.',
              style: AtomicType.headlineMedium.copyWith(color: c.textPrimary)),
        ),
        const SizedBox(height: AtomicSpace.x2),
        Text(
          "Coins aren't sold in the app yet. Support Atomic Notes at the "
          'amount you choose, and the developer sends Atomic Coins to your '
          'account as an early-supporter reward.',
          style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
        ),
        if (email != null && email.isNotEmpty) ...[
          const SizedBox(height: AtomicSpace.x4),
          Text('Your account email',
              style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          const SizedBox(height: AtomicSpace.x1),
          SelectableText(email,
              style: AtomicType.titleMedium.copyWith(color: c.textPrimary)),
          const SizedBox(height: AtomicSpace.x1),
          Text(
            'Share this exact email with the developer when you support, so '
            'the coins reach the right account.',
            style: AtomicType.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('energy-support'),
          label: 'Support Atomic Notes',
          icon: AtomicIcons.externalLink,
          expand: true,
          onPressed: onSupport,
        ),
        const SizedBox(height: AtomicSpace.x2),
        AtomicButton.text(
          key: const ValueKey('energy-support-dismiss'),
          label: 'Not now',
          expand: true,
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

/// Bottom sheet to pick how many coins to convert, with a large stepper.
/// Local state only; the service performs the (server-authoritative)
/// conversion after it returns.
class _ConvertSheet extends StatefulWidget {
  final int maxCoins;
  final int energy;
  final int energyCap;
  const _ConvertSheet({
    required this.maxCoins,
    required this.energy,
    required this.energyCap,
  });

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  int _amount = 1;

  int get _gain => _amount * EnergyService.coinToEnergy;
  bool get _overflows => widget.energy + _gain > widget.energyCap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: const ValueKey('energy-convert-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Convert coins',
              style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
        ),
        const SizedBox(height: AtomicSpace.x6),
        Row(
          children: [
            AtomicIconButton(
              key: const ValueKey('energy-convert-less'),
              // The Atomic icon font has no minus glyph yet.
              icon: Icons.remove,
              tooltip: 'Fewer coins',
              onCard: true,
              onPressed: _amount > 1 ? () => setState(() => _amount--) : null,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: '$_amount coin${_amount == 1 ? '' : 's'}',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Text('$_amount',
                          key: const ValueKey('energy-convert-amount'),
                          textAlign: TextAlign.center,
                          style: AtomicType.numeric(AtomicType.display)
                              .copyWith(color: c.textPrimary)),
                      Text('coins',
                          textAlign: TextAlign.center,
                          style: AtomicType.bodySmall
                              .copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            AtomicIconButton(
              key: const ValueKey('energy-convert-more'),
              icon: AtomicIcons.plus,
              tooltip: 'More coins',
              onCard: true,
              onPressed: _amount < widget.maxCoins
                  ? () => setState(() => _amount++)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AtomicSpace.x6),
        Text('= $_gain energy',
            textAlign: TextAlign.center,
            style: AtomicType.numeric(AtomicType.headlineMedium)
                .copyWith(color: c.textPrimary)),
        const SizedBox(height: AtomicSpace.x1),
        if (_overflows)
          Text(
            'That would overflow your ${widget.energyCap} cap. Use some '
            'energy first or convert fewer coins.',
            textAlign: TextAlign.center,
            style: AtomicType.bodySmall.copyWith(color: c.dangerText),
          )
        else
          Text('You have ${widget.maxCoins} coins.',
              textAlign: TextAlign.center,
              style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('energy-convert-confirm'),
          label: 'Convert',
          icon: AtomicIcons.bolt,
          size: AtomicButtonSize.large,
          expand: true,
          onPressed:
              _overflows ? null : () => Navigator.of(context).pop(_amount),
        ),
      ],
    );
  }
}
