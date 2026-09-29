// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/energy/energy_cubit.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:atomic_notes/utility/component/energy_bar.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/web_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The dedicated Atomic Energy + Atomic Coins screen. Reads everything through [EnergyCubit] from
/// [EnergyService]; never computes a balance itself.
class EnergyPage extends StatelessWidget {
  /// [store] and [notes] are only given by tests; the app uses the real ones.
  const EnergyPage({super.key, this.store, this.notes});

  final EnergyStore? store;
  final NotesSource? notes;

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

  // ---- actions ----------------------------------------------------------

  Future<void> _convert() async {
    final now = _cubit.state;
    final maxCoins = now.coins;
    if (maxCoins <= 0) {
      const MySnackBar(text: 'No Atomic Coins to convert yet.', sec: 2000)
          .showMySnackBar(context);
      return;
    }
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.paper,
      showDragHandle: true,
      builder: (ctx) => _ConvertSheet(
        maxCoins: maxCoins,
        energy: now.energy,
        energyCap: now.energyCap,
      ),
    );
    if (chosen == null || chosen <= 0) return;
    final err = await _cubit.convertCoins(chosen);
    if (!mounted) return;
    MySnackBar(
      text: err ??
          'Converted $chosen coin${chosen == 1 ? '' : 's'} to '
              '${chosen * EnergyService.coinToEnergy} energy.',
      sec: 2500,
    ).showMySnackBar(context);
  }

  Future<void> _raiseLimit() async {
    final cubit = _cubit;
    final now = cubit.state;
    final tier = now.nextTier;
    if (tier == null) return; // already at the ceiling; the button is hidden
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogBoxLogout(
        text: 'Spend ${tier.costCoins} coins to become ${tier.name} and raise '
            'your note limit from ${now.noteLimit} to ${tier.limit}?',
        action: () async {
          final err = await cubit.upgradeNoteLimit();
          if (!mounted) return;
          MySnackBar(
            text: err ??
                "You're ${tier.name} now — you can keep ${tier.limit} notes.",
            sec: 3000,
          ).showMySnackBar(context);
        },
      ),
    );
  }

  void _needCoins() {
    final now = _cubit.state;
    final tier = now.nextTier;
    if (tier == null) return;
    MySnackBar(
      text: 'Becoming ${tier.name} costs ${tier.costCoins} coins. '
          'You have ${now.coins}.',
      sec: 3000,
    ).showMySnackBar(context);
  }

  /// Coins aren't sold in the App yet. The sheet sends people to the website,
  /// where supporting the project earns Atomic Coins early. The sheet names no
  /// payment platform: the website does.
  void _coinStore() {
    final email = ApiClient.instance.currentUserEmail;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('COIN STORE', color: AppColors.signal),
              const SizedBox(height: AppSpace.sm),
              const HairRule(color: AppColors.ink),
              const SizedBox(height: AppSpace.md),
              const EditorialHeading('Get Atomic Coins\nearly.',
                  style: AppType.headlineLg),
              const SizedBox(height: AppSpace.sm),
              const Text(
                "Coins aren't sold in the app yet. Support Atomic Notes at "
                'the amount you choose, and the developer sends Atomic Coins '
                'to your account as an early-supporter reward.',
                style: AppType.bodyMd,
              ),
              if (email != null && email.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                const MonoLabel('YOUR ACCOUNT EMAIL'),
                const SizedBox(height: AppSpace.xs),
                SelectableText(email,
                    style: AppType.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpace.xs),
                const Text(
                  'Share this exact email with the developer when you '
                  'support, so the coins reach the right account.',
                  style: AppType.bodySm,
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              InkActionButton(
                label: 'Support Atomic Notes',
                signal: true,
                icon: Icons.open_in_new,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final opened = await WebLinks.open(WebLinks.support);
                  if (!mounted) return;
                  if (!opened) {
                    const MySnackBar(
                      text: "Couldn't open the browser. Visit "
                          '${WebLinks.support}',
                      sec: 4000,
                    ).showMySnackBar(context);
                  }
                },
              ),
              const SizedBox(height: AppSpace.sm),
              GhostButton(
                label: 'Not now',
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: "Atomic Energy"),
      body: BlocBuilder<EnergyCubit, EnergyState>(
        builder: (context, state) {
          // Loading state (first load, nothing cached yet).
          if (state.loading && !state.hasLoaded) {
            return const Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.signal),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.signal,
            onRefresh: _cubit.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
              children: [
                _energyHero(state),
                const SizedBox(height: AppSpace.sm),
                _coinsModule(state),
                const SizedBox(height: AppSpace.sm),
                _capacityModule(state),
                const SizedBox(height: AppSpace.md),
                GhostButton(
                  label: 'How Atomic Energy works',
                  icon: Icons.info_outline,
                  onTap: () => Navigator.pushNamed(context, '/energyintro'),
                ),
                const SizedBox(height: AppSpace.lg),
                _activity(state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _energyHero(EnergyState state) {
    return EditorialModule(
      inverted: true,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MonoLabel('ATOMIC ENERGY', color: AppColors.signal),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '${state.energy}',
                      style: AppType.statNumber.copyWith(color: AppColors.paper),
                    ),
                    Text(
                      'of ${state.energyCap} capacity',
                      style: AppType.labelMonoSm
                          .copyWith(color: AppColors.outlineVariant),
                    ),
                  ],
                ),
              ),
              const AtomicIcon('atom', size: 56, set: 'Icons-Without-label-2.5D'),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          EnergyBar(
            fraction: state.wallet.energyFraction,
            height: 12,
            color: EnergyBar.colorFor(state.energy),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '+20 energy every 24h, up to 120. Automatic sync 5 (once an hour), '
            'instant sync 10. Local notes are always free.',
            style: AppType.bodySm.copyWith(color: AppColors.outlineVariant),
          ),
        ],
      ),
    );
  }

  Widget _coinsModule(EnergyState state) {
    final noCoins = state.coins <= 0;
    return EditorialModule(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AtomicIcon.coin(
                  size: 34, set: 'Icons-Without-label-2.5D'),
              const SizedBox(width: AppSpace.sm + 2),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel('ATOMIC COINS'),
                    SizedBox(height: 2),
                    Text('1 coin = 40 energy', style: AppType.bodySm),
                  ],
                ),
              ),
              Text('${state.coins}', style: AppType.statNumber),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          InkActionButton(
            label: 'Get Atomic Coins',
            signal: true,
            icon: Icons.add,
            onTap: _coinStore,
          ),
          const SizedBox(height: AppSpace.sm),
          GhostButton(
            label: noCoins ? 'No coins to convert' : 'Convert coins to energy',
            icon: Icons.bolt,
            onTap: noCoins ? null : _convert,
          ),
        ],
      ),
    );
  }

  /// The asset name for a tier's particle icon: the tier names are already exactly the
  /// SVG file names (`assets/Atomic Icons/*/tachyon.svg` etc.), lowercased.
  static String _tierIcon(String tierName) => tierName.toLowerCase();

  /// How many notes the account can hold, and the way to raise it with coins.
  Widget _capacityModule(EnergyState state) {
    final l = state.limits;
    final int used = state.notesUsed;
    final int limit = state.noteLimit;
    final NoteLimitTier? next = state.nextTier;
    final bool atCeiling = next == null;
    final currentTier = l.tierFor(limit);
    return EditorialModule(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AtomicIcon(_tierIcon(currentTier?.name ?? 'tachyon'),
                  size: 34, set: 'Icons-Without-label-2.5D'),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel(currentTier?.name ?? 'Note capacity'),
                    const SizedBox(height: 2),
                    Text('$used of $limit notes used', style: AppType.bodySm),
                  ],
                ),
              ),
              Text('$limit', style: AppType.statNumber),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              for (final tier in l.noteLimitTiers)
                Expanded(
                  child: Container(
                    key: ValueKey('capacity-${tier.limit}'),
                    margin: EdgeInsets.only(
                        right: tier == l.noteLimitTiers.last ? 0 : 4),
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tier.limit <= limit ? AppColors.ink : Colors.transparent,
                      borderRadius: AppRadius.sm,
                      border: Border.all(
                          color: tier.limit <= limit
                              ? AppColors.ink
                              : AppColors.outlineVariant,
                          width: AppStroke.rule),
                    ),
                    child: Text(
                      '${tier.limit}',
                      style: AppType.labelMonoSm.copyWith(
                          color: tier.limit <= limit
                              ? AppColors.paper
                              : AppColors.slateData),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final tier in l.noteLimitTiers)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: tier == l.noteLimitTiers.last ? 0 : 4),
                    // A FittedBox, not MonoLabel directly: "Antimatter" and
                    // "Strangelet" are wider than a fifth of the row, and
                    // wrapping mid-word ("ANTIMATTE" / "R") reads worse than
                    // shrinking to fit one line.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tier.name.toUpperCase(),
                        maxLines: 1,
                        style: AppType.labelMonoSm.copyWith(
                          color: tier.limit <= limit
                              ? AppColors.ink
                              : AppColors.slateData,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            atCeiling
                ? 'This is the most notes an account can hold.'
                : 'Become ${next.name} for ${next.costCoins} coins to hold '
                    '${next.limit} notes.',
            style: AppType.bodySm,
          ),
          if (next != null) ...[
            const SizedBox(height: AppSpace.md),
            InkActionButton(
              label: 'Become ${next.name}  ·  ${next.costCoins} coins',
              icon: Icons.add,
              onTap: state.canAffordNoteLimit ? _raiseLimit : _needCoins,
            ),
          ],
        ],
      ),
    );
  }

  Widget _activity(EnergyState state) {
    final all = state.history;
    final shown = all.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'ACTIVITY',
          trailing: GestureDetector(
            onTap: () {
              setState(() => _shown = _pageSize);
              _cubit.refresh();
            },
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.refresh, size: 18, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (state.error != null)
          _note('Could not load activity. Pull down to retry.')
        else if (all.isEmpty)
          _note('No transactions yet. Daily energy and conversions will '
              'show up here.')
        else ...[
          ...shown.map(_historyRow),
          if (all.length > _shown) ...[
            const SizedBox(height: AppSpace.xs),
            GhostButton(
              label: 'Load more',
              icon: Icons.expand_more,
              onTap: () => setState(() => _shown += _pageSize),
            ),
          ],
        ],
      ],
    );
  }

  Widget _note(String text) => EditorialModule(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text(text, style: AppType.bodySm),
      );

  Widget _historyRow(EnergyTx tx) {
    final iconName = switch (tx.kind) {
      EnergyTxKind.purchase => 'atomic-coin',
      EnergyTxKind.convert => 'atomic-coin',
      _ => 'atom',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: AppRadius.std,
        border: Border.all(color: AppColors.outlineVariant, width: AppStroke.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AtomicIcon(iconName, size: 24),
          const SizedBox(width: AppSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Prefer the specific note ("Instant sync", "Standard sync",
                  // "Daily energy grant", "Welcome gift…") over the generic kind
                  // label, so the user sees exactly where energy/coins went.
                  (tx.note != null && tx.note!.isNotEmpty)
                      ? tx.note!
                      : tx.kind.label,
                  style: AppType.bodyMedium15,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                MonoLabel(_stamp(tx.createdAt), small: true),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (tx.energyDelta != 0) _delta(tx.energyDelta, 'ENERGY'),
              if (tx.coinsDelta != 0) _delta(tx.coinsDelta, 'COINS'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _delta(int value, String unit) {
    final positive = value > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${positive ? '+' : ''}$value',
            style: AppType.bodyMedium15.copyWith(
              color: positive ? AppColors.signal : AppColors.slateData,
            ),
          ),
          const SizedBox(width: 4),
          MonoLabel(unit, small: true, color: AppColors.slateData),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }
}

/// Bottom sheet to pick how many coins to convert. Local state only; the
/// service performs the (server-authoritative) conversion after it returns.
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
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('CONVERT COINS', color: AppColors.signal),
          const SizedBox(height: AppSpace.sm),
          const HairRule(color: AppColors.ink),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stepBtn(Icons.remove, () {
                if (_amount > 1) setState(() => _amount--);
              }),
              Column(
                children: [
                  Text('$_amount', style: AppType.statNumber),
                  const MonoLabel('COINS', small: true),
                ],
              ),
              _stepBtn(Icons.add, () {
                if (_amount < widget.maxCoins) setState(() => _amount++);
              }),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('= $_gain energy', style: AppType.headlineMd),
          const SizedBox(height: AppSpace.xs),
          if (_overflows)
            Text(
              'That would overflow your ${widget.energyCap} cap. Use some '
              'energy first or convert fewer coins.',
              style: AppType.bodySm.copyWith(color: AppColors.error),
            )
          else
            Text('You have ${widget.maxCoins} coins.', style: AppType.bodySm),
          const SizedBox(height: AppSpace.lg),
          InkActionButton(
            label: 'Convert',
            signal: true,
            icon: Icons.bolt,
            onTap: _overflows ? null : () => Navigator.of(context).pop(_amount),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          borderRadius: AppRadius.std,
          border: Border.all(color: AppColors.ink, width: AppStroke.hairline),
        ),
        child: Icon(icon, color: AppColors.ink),
      ),
    );
  }
}
