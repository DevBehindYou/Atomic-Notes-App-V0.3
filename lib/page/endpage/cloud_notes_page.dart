import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cloud Notes (screens spec, Cloud Notes): this device against the cloud,
/// side by side.
///
/// Checking the cloud only COUNTS its note records (Server metadata). It never pulls or merges anything,
/// so looking can never change what is on this device.
class CloudNotesPage extends StatelessWidget {
  /// [source] and [energy] are only given by tests; the app uses the real
  /// notes store and the Server-reported energy prices.
  const CloudNotesPage({super.key, this.source, this.energy});

  final NotesSource? source;

  /// Where the upload batch prices come from (the Server's policy).
  final EnergyStore? energy;

  static const String title = 'Cloud notes';

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CloudNotesCubit>(
      // Count the cloud as soon as the screen opens.
      create: (_) =>
          CloudNotesCubit(source: source ?? NotesRepository.instance)..check(),
      child: _CloudNotesView(energy: energy ?? EnergyService.instance),
    );
  }
}

class _CloudNotesView extends StatefulWidget {
  const _CloudNotesView({required this.energy});

  final EnergyStore energy;

  @override
  State<_CloudNotesView> createState() => _CloudNotesViewState();
}

class _CloudNotesViewState extends State<_CloudNotesView> {
  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  /// Whether the last sync receipt shows its totals. A new sync opens it.
  bool _receiptOpen = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    // The prices follow the Server's policy, which can arrive after the page
    // opens.
    widget.energy.addListener(_onEnergy);
  }

  @override
  void didUpdateWidget(_CloudNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.energy != widget.energy) {
      oldWidget.energy.removeListener(_onEnergy);
      widget.energy.addListener(_onEnergy);
    }
  }

  void _onEnergy() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.energy.removeListener(_onEnergy);
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<void> _sync({required bool uploadAll}) async {
    final cubit = context.read<CloudNotesCubit>();
    setState(() => _receiptOpen = true);
    // Both actions use instant sync. Existing Server pricing applies per charged upload batch.
    final message = await cubit.sync(uploadAll: uploadAll);
    if (message == null || !mounted) return;
    final report = cubit.state.lastReport;
    AtomicSnackBar(
      text: message.text,
      millis: message.millis,
      error: report != null && !report.completed,
    ).show(context);
    await cubit.check();
  }

  /// "Open" when an automatic sync can send now, else how long until it can.
  static String _autoSyncText(DateTime? next) {
    if (next == null) return 'Open';
    final int minutes = (next.difference(DateTime.now()).inSeconds / 60).ceil();
    return minutes <= 1 ? 'In under a minute' : 'In $minutes min';
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }

  /// What the returned count means. Only a successful count is compared; a
  /// failed or retired one is never shown as zero.
  static _Verdict _verdict(CloudNotesState state) {
    final int onDevice = state.onDevice;
    final int waiting = state.waiting;
    if (!SyncStatusHelper.isSyncOn) {
      // Turning sync off removes nothing from Google Drive (copy proposal 1).
      return const _Verdict('Sync off',
          'Cloud sync is off. Your notes stay on this device. Copies already in Google Drive aren’t removed.');
    }
    final int? cloud = state.cloud;
    if (!state.checked) {
      return state.checking
          ? const _Verdict('Checking', 'Counting the notes in your cloud…')
          : const _Verdict('Not checked',
              'The cloud note count has not been checked for this session. Tap Check cloud to check it.');
    }
    if (cloud == null) {
      return const _Verdict(
          'Check failed',
          'The cloud note count could not be checked. Your local notes remain on this device. Try Check cloud again.',
          _Tone.danger);
    }
    if (waiting > 0) {
      return _Verdict(
        '$waiting waiting',
        waiting == 1
            ? '1 change is waiting to upload, including edited notes or deletions. It sends at the next automatic sync, or now with Sync now.'
            : '$waiting changes are waiting to upload, including edited notes or deletions. They send at the next automatic sync, or now with Sync now.',
        _Tone.waiting,
      );
    }
    // The cloud total is the Server's metadata count of note records, not an
    // inventory of readable Google Drive files.
    if (cloud == onDevice) {
      return onDevice == 0
          ? const _Verdict('No notes',
              'This device has no notes, and the cloud metadata count is 0.')
          : const _Verdict(
              'Counts match',
              'This device’s note count matches the cloud metadata count. This check does not compare note contents.',
              _Tone.ok);
    }
    if (cloud < onDevice) {
      return const _Verdict(
          'Fewer in cloud',
          'The cloud metadata count is lower than this device’s note count. This check does not compare note contents. Sync to check for changes.',
          _Tone.attention);
    }
    return const _Verdict(
        'More in cloud',
        'The cloud metadata count is higher than this device’s note count. This check does not compare note contents. Sync to check for changes.',
        _Tone.attention);
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
          child: BlocBuilder<CloudNotesCubit, CloudNotesState>(
            builder: (context, state) {
              final cubit = context.read<CloudNotesCubit>();
              final int onDevice = state.onDevice;
              final int? cloud = state.cloud;
              final bool syncOn = SyncStatusHelper.isSyncOn;
              final bool checking = state.checking;
              final bool working = state.working;
              final bool busy = checking || working;
              final report = state.lastReport;
              final limits = widget.energy.limits;
              final int cost = limits.syncInstantCost;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _titleAway,
                    builder: (context, away, _) => AtomicPageHeader(
                      title: CloudNotesPage.title,
                      showTitle: away,
                      actions: [
                        AtomicIconButton(
                          icon: AtomicIcons.refresh,
                          tooltip: 'Check cloud again',
                          onPressed: busy ? null : cubit.check,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    // The page is short and its actions sit near the end, so
                    // everything is built at once (no lazy list).
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                          margin,
                          0,
                          margin,
                          AtomicSpace.x8 +
                              MediaQuery.paddingOf(context).bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Entrance(
                              index: 0, child: PageTitle(CloudNotesPage.title)),
                          const SizedBox(height: AtomicSpace.x2),
                          Entrance(
                            index: 1,
                            child: _Hero(state: state, busy: busy),
                          ),
                          const SizedBox(height: AtomicSpace.x4),
                          Entrance(
                            index: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Status(verdict: _verdict(state)),
                                const SizedBox(height: AtomicSpace.x2),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AtomicSpace.x1),
                                  child: Text(
                                    'Unchanged means no local edits are waiting; it does not compare cloud contents.',
                                    style: AtomicType.bodySmall
                                        .copyWith(color: c.textSecondary),
                                  ),
                                ),
                                const SizedBox(height: AtomicSpace.x1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AtomicSpace.x1),
                                  child: Text(
                                    'Cloud records is the server’s metadata count of note records. It doesn’t confirm which note files are in Google Drive or that they can be read.',
                                    key: const ValueKey('cloud-notes-metadata'),
                                    style: AtomicType.bodySmall
                                        .copyWith(color: c.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (report != null) ...[
                            const SizedBox(height: AtomicSpace.x8),
                            Entrance(
                              index: 3,
                              child: _SyncReceipt(
                                report: report,
                                open: _receiptOpen,
                                onToggle: () => setState(
                                    () => _receiptOpen = !_receiptOpen),
                              ),
                            ),
                          ],
                          const SizedBox(height: AtomicSpace.x8),
                          Entrance(
                            index: 4,
                            child: _DetailsGroup(
                              label: 'Details',
                              rows: [
                                (
                                  'Last sync',
                                  state.lastSyncedAt == null
                                      ? 'Never'
                                      : _stamp(state.lastSyncedAt!)
                                ),
                                (
                                  'Last check',
                                  state.checkedAt == null
                                      ? '—'
                                      : _stamp(state.checkedAt!)
                                ),
                                ('Cloud sync', syncOn ? 'On' : 'Off'),
                                (
                                  'Automatic sync',
                                  _autoSyncText(state.nextAutoSyncAt)
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AtomicSpace.x8),
                          Entrance(
                            index: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AtomicButton.tonal(
                                  key: const ValueKey('cloud-notes-check'),
                                  label: 'Check cloud',
                                  icon: AtomicIcons.cloud,
                                  size: AtomicButtonSize.large,
                                  expand: true,
                                  busy: checking,
                                  onPressed: working ? null : cubit.check,
                                ),
                                const SizedBox(height: AtomicSpace.x3),
                                AtomicButton.primary(
                                  key: const ValueKey('cloud-notes-sync'),
                                  label:
                                      'Sync now · $cost energy per charged upload batch',
                                  icon: AtomicIcons.refresh,
                                  size: AtomicButtonSize.large,
                                  expand: true,
                                  onPressed: (!syncOn || busy)
                                      ? null
                                      : () => _sync(uploadAll: false),
                                ),
                                if (syncOn &&
                                    cloud != null &&
                                    cloud < onDevice) ...[
                                  const SizedBox(height: AtomicSpace.x3),
                                  AtomicButton.tonal(
                                    key: const ValueKey(
                                        'cloud-notes-upload-all'),
                                    label:
                                        'Upload all · $cost energy per charged upload batch',
                                    icon: AtomicIcons.cloudUpload,
                                    size: AtomicButtonSize.large,
                                    expand: true,
                                    onPressed: busy
                                        ? null
                                        : () => _sync(uploadAll: true),
                                  ),
                                ],
                                const SizedBox(height: AtomicSpace.x6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AtomicSpace.x1),
                                  child: Text(
                                    'Checking the cloud only reads its metadata count of note records. It never changes '
                                    'what is on this device. Sync now sends waiting changes. '
                                    'Upload all marks every live note for upload. Each charged upload batch '
                                    'costs $cost energy and carries up to 50 '
                                    'changes, subject to the size limit. Larger uploads can cost more. '
                                    'With nothing to upload, sync is free. Standard uploads cost '
                                    '${limits.syncStandardCost} energy per charged upload batch, with one '
                                    'standard upload window per account per hour.',
                                    style: AtomicType.bodySmall
                                        .copyWith(color: c.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Tone { neutral, ok, waiting, attention, danger }

class _Verdict {
  final String title;
  final String detail;
  final _Tone tone;
  const _Verdict(this.title, this.detail, [this.tone = _Tone.neutral]);
}

const ValueKey<String> _verdictKey = ValueKey('cloud-notes-verdict');

/// The two ends of the connection on the inverse surface: the counts, the
/// share with no edits waiting, and activity between them.
class _Hero extends StatelessWidget {
  const _Hero({required this.state, required this.busy});

  final CloudNotesState state;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onDevice = state.onDevice;
    final cloud = state.cloud;
    final synced = state.synced;
    final edited = state.waitingNotes;
    final deletions = state.waitingDeletions;
    final dim = c.onInverse.withValues(alpha: 0.72);
    final deletionText =
        '$deletions ${deletions == 1 ? 'deletion' : 'deletions'} waiting';
    final label = [
      '$onDevice on device, '
          '${cloud == null ? 'cloud record count unknown' : '$cloud cloud records'}',
      '$synced unchanged, $edited edited',
      if (deletions > 0) deletionText,
      if (busy) 'Working',
    ].join('. ');
    return Semantics(
      key: const ValueKey('cloud-notes-hero'),
      container: true,
      label: label,
      excludeSemantics: true,
      child: AtomicCard(
        color: c.inverseSurface,
        padding: const EdgeInsets.all(AtomicSpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Endpoint(value: '$onDevice', caption: 'on device'),
                ),
                SizedBox(
                  width: 44,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: AtomicMotion.fade(context, AtomicMotion.quick),
                      child: busy
                          ? const ProgressRing(key: ValueKey('ring'), size: 22)
                          : Icon(AtomicIcons.arrowsExchange,
                              key: const ValueKey('icon'),
                              color: c.accent,
                              size: 24),
                    ),
                  ),
                ),
                Expanded(
                  child: _Endpoint(
                      value: cloud?.toString() ?? '—',
                      caption: 'cloud records',
                      alignEnd: true),
                ),
              ],
            ),
            const SizedBox(height: AtomicSpace.x4),
            ProgressBar(
              value: (synced + edited) == 0 ? 0 : synced / (synced + edited),
            ),
            const SizedBox(height: AtomicSpace.x3),
            // One line, two quantities: each is its own span so each can be
            // checked on its own.
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$synced unchanged'),
                const TextSpan(text: ' · '),
                TextSpan(text: '$edited edited'),
              ]),
              key: const ValueKey('cloud-notes-quantities'),
              style: AtomicType.bodyMedium.copyWith(color: dim),
            ),
            if (deletions > 0) ...[
              const SizedBox(height: AtomicSpace.x1),
              Text(deletionText,
                  style: AtomicType.bodySmall.copyWith(color: dim)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One end of the device-cloud connection: a large numeral over its caption.
class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.value,
    required this.caption,
    this.alignEnd = false,
  });

  final String value;
  final String caption;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Large counts at large text shrink to fit rather than overflow.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(value,
              style: AtomicType.display.copyWith(color: c.onInverse)),
        ),
        Text(caption,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: AtomicType.bodySmall
                .copyWith(color: c.onInverse.withValues(alpha: 0.72))),
      ],
    );
  }
}

/// What the numbers mean: a mismatch is an attention banner and a failed
/// count a danger banner; anything else is a status card with its icon.
/// Screen readers hear a change as it happens.
class _Status extends StatelessWidget {
  const _Status({required this.verdict});

  final _Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget child = switch (verdict.tone) {
      _Tone.attention => AtomicBanner(
          key: _verdictKey,
          tone: BannerTone.attention,
          icon: AtomicIcons.alertTriangle,
          title: verdict.title,
          body: verdict.detail,
        ),
      _Tone.danger => AtomicBanner(
          key: _verdictKey,
          tone: BannerTone.danger,
          icon: AtomicIcons.alertCircle,
          title: verdict.title,
          body: verdict.detail,
        ),
      _ => _StatusCard(verdict: verdict, colors: c),
    };
    return Semantics(
      key: const ValueKey('cloud-notes-status'),
      container: true,
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: AtomicMotion.fade(context, AtomicMotion.quick),
        child: KeyedSubtree(
            key: ValueKey('${verdict.tone}-${verdict.title}'), child: child),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.verdict, required this.colors});

  final _Verdict verdict;
  final AtomicColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final (icon, fill, iconColor) = switch (verdict.tone) {
      _Tone.ok => (AtomicIcons.circleCheck, c.accent, c.onAccent),
      _Tone.waiting => (AtomicIcons.clock, c.info, c.onInfo),
      _ => (
          SyncStatusHelper.isSyncOn ? AtomicIcons.cloud : AtomicIcons.cloudOff,
          c.surfaceInset,
          c.textPrimary
        ),
    };
    return MergeSemantics(
      child: AtomicCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AtomicSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(verdict.title,
                      key: _verdictKey,
                      style: AtomicType.titleMedium
                          .copyWith(color: c.textPrimary)),
                  const SizedBox(height: AtomicSpace.x1),
                  Text(verdict.detail,
                      style: AtomicType.bodyMedium
                          .copyWith(color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled card of label and value lines.
class _DetailsGroup extends StatelessWidget {
  const _DetailsGroup({this.label, required this.rows});

  final String? label;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = this.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(
                left: AtomicSpace.x1, bottom: AtomicSpace.x2),
            child: Semantics(
              header: true,
              child: Text(label,
                  style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
            ),
          ),
        AtomicCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 1,
                      indent: AtomicSpace.x4,
                      color: c.outline),
                _DetailRow(label: rows[i].$1, value: rows[i].$2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A label and its value; the value moves under the label when both do not
/// fit on one line.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AtomicSpace.x3,
              children: [
                Text(label,
                    style:
                        AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
                Text(value,
                    style:
                        AtomicType.titleMedium.copyWith(color: c.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last requested sync, as a collapsible group. Financial totals stay
/// readable here instead of being truncated by a short snackbar.
class _SyncReceipt extends StatelessWidget {
  const _SyncReceipt({
    required this.report,
    required this.open,
    required this.onToggle,
  });

  final SyncAttemptReport report;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final report = this.report;
    final confirmed = report.operations
        .where((entry) => entry.charged != null && entry.refunded != null)
        .toList();
    final known = report.charged != null && report.refunded != null;
    final charged =
        confirmed.fold<int>(0, (sum, entry) => sum + entry.charged!);
    final refunded =
        confirmed.fold<int>(0, (sum, entry) => sum + entry.refunded!);
    final started = report.activity == SyncAttemptActivity.started;
    final title = !started
        ? 'Sync did not start'
        : report.completed
            ? 'Sync completed'
            : 'Sync incomplete';
    final note = AtomicType.bodySmall.copyWith(color: c.textSecondary);

    final details = Padding(
      padding: const EdgeInsets.fromLTRB(
          AtomicSpace.x4, 0, AtomicSpace.x4, AtomicSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!report.completed && report.errorMessage != null) ...[
            Text(report.errorMessage!,
                style: AtomicType.bodyMedium.copyWith(color: c.textPrimary)),
            const SizedBox(height: AtomicSpace.x2),
          ],
          if (started && report.operations.isEmpty)
            Text('No upload was sent. No upload energy was charged.',
                style: note)
          else ...[
            if (!known) Text('Upload energy totals unavailable.', style: note),
            if (report.operations.isNotEmpty)
              Text(
                  known
                      ? '${report.operations.length} upload ${report.operations.length == 1 ? 'batch' : 'batches'}'
                      : '${confirmed.length} of ${report.operations.length} upload batches confirmed',
                  style: note),
            if (confirmed.isNotEmpty) ...[
              if (!known) ...[
                const SizedBox(height: AtomicSpace.x1),
                Text('Confirmed totals only', style: note),
              ],
              const SizedBox(height: AtomicSpace.x2),
              _AmountRow(label: 'Charged', value: '$charged energy'),
              _AmountRow(label: 'Refunded', value: '$refunded energy'),
              _AmountRow(
                  label: known ? 'Net upload cost' : 'Confirmed net',
                  value: '${charged - refunded} energy',
                  strong: true),
              const SizedBox(height: AtomicSpace.x2),
              Text(
                  'These are upload batch totals, not a new debit for each retry.',
                  style: note),
            ],
            if (report.operations.any((entry) => entry.recovered)) ...[
              const SizedBox(height: AtomicSpace.x1),
              Text(
                  'Includes an earlier upload. Its totals may already have been applied.',
                  style: note),
            ],
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AtomicSpace.x1, bottom: AtomicSpace.x2),
          child: Semantics(
            header: true,
            child: Text('Last requested sync',
                style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          ),
        ),
        AtomicCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                expanded: open,
                child: AtomicPressable(
                  key: const ValueKey('cloud-notes-receipt-toggle'),
                  semanticsLabel: '$title. ${open ? 'Hide' : 'Show'} details',
                  excludeSemantics: true,
                  borderRadius: AtomicRadius.largeAll,
                  onTap: onToggle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(title,
                                style: AtomicType.titleMedium
                                    .copyWith(color: c.textPrimary)),
                          ),
                          const SizedBox(width: AtomicSpace.x2),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: AtomicMotion.move(
                                context, AtomicMotion.standard),
                            child: Icon(AtomicIcons.chevronDown,
                                size: 20, color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: AtomicMotion.move(context, AtomicMotion.standard),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child:
                      open ? details : const SizedBox(width: double.infinity),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(
      {required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AtomicSpace.x1),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      (strong ? AtomicType.titleMedium : AtomicType.bodyMedium)
                          .copyWith(
                              color: strong ? c.textPrimary : c.textSecondary)),
            ),
            const SizedBox(width: AtomicSpace.x3),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: AtomicType.titleMedium.copyWith(color: c.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
