import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cloud Notes: this device against the cloud, side by side.
///
/// Checking the cloud only COUNTS its notes. It never pulls or merges anything,
/// so looking can never change what is on this device.
class CloudNotesPage extends StatelessWidget {
  /// [source] is only given by tests; the app uses the real notes store.
  const CloudNotesPage({super.key, this.source});

  final NotesSource? source;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CloudNotesCubit>(
      // Count the cloud as soon as the screen opens.
      create: (_) =>
          CloudNotesCubit(source: source ?? NotesRepository.instance)..check(),
      child: const _CloudNotesView(),
    );
  }
}

class _CloudNotesView extends StatefulWidget {
  const _CloudNotesView();

  @override
  State<_CloudNotesView> createState() => _CloudNotesViewState();
}

class _CloudNotesViewState extends State<_CloudNotesView> {
  Future<void> _sync({required bool uploadAll}) async {
    final cubit = context.read<CloudNotesCubit>();
    // Both buttons on this page are instant sync: they send now and cost 10 energy when there is something to send.
    final message = await cubit.sync(uploadAll: uploadAll);
    if (message == null || !mounted) return;
    MySnackBar(text: message.text, sec: message.millis).showMySnackBar(context);
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

  _Verdict _verdict(CloudNotesState state) {
    final int onDevice = state.onDevice;
    final int waiting = state.waiting;
    if (!SyncStatusHelper.isSyncOn) {
      return const _Verdict('Sync off',
          'Cloud Sync is turned off, so notes stay on this device only.',
          AppColors.outline);
    }
    final int? cloud = state.cloud;
    if (!state.checked) {
      return const _Verdict(
          'Checking', 'Counting the notes in your cloud…', AppColors.outline);
    }
    if (cloud == null) {
      return const _Verdict('Offline',
          'The cloud could not be reached. Notes on this device are safe and sync when the connection is back.',
          AppColors.error);
    }
    if (waiting > 0) {
      return _Verdict(
        '$waiting waiting',
        waiting == 1
            ? '1 edited note is waiting to upload. It sends at the next automatic sync, or now with Sync now.'
            : '$waiting edited notes are waiting to upload. They send at the next automatic sync, or now with Sync now.',
        AppColors.signal,
      );
    }
    if (cloud == onDevice) {
      return const _Verdict('In sync',
          'This device and the cloud hold the same number of notes.',
          AppColors.signal);
    }
    if (cloud < onDevice) {
      return const _Verdict(
          'Cloud behind',
          'The cloud has fewer notes than this device, for example after '
              'wiping the cloud. Upload all to fill it again.',
          AppColors.error);
    }
    return const _Verdict('Cloud ahead',
        'The cloud has more notes than this device. Sync to download them.',
        AppColors.signal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: 'Cloud Notes'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
        child: BlocBuilder<CloudNotesCubit, CloudNotesState>(
          builder: (context, state) {
            final cubit = context.read<CloudNotesCubit>();
            final int onDevice = state.onDevice;
            final int waiting = state.waiting;
            final int synced = state.synced;
            final _Verdict verdict = _verdict(state);
            final bool syncOn = SyncStatusHelper.isSyncOn;
            final int? cloud = state.cloud;
            final String cloudText = cloud?.toString() ?? '—';
            final bool checking = state.checking;
            final bool working = state.working;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  'DEVICE VS CLOUD',
                  trailing: DataChip(
                    verdict.title,
                    active: true,
                    activeColor: verdict.color,
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                // The two ends of the connection, as one inverted module.
                EditorialModule(
                  inverted: true,
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _Endpoint(
                                caption: 'On device', value: '$onDevice'),
                          ),
                          SizedBox(
                            width: 44,
                            child: Center(
                              child: (checking || working)
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                AppColors.paper),
                                      ),
                                    )
                                  : const Icon(Icons.sync_alt,
                                      color: AppColors.signal, size: 22),
                            ),
                          ),
                          Expanded(
                            child: _Endpoint(
                                caption: 'In cloud',
                                value: cloudText,
                                alignEnd: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                      _SyncBar(synced: synced, waiting: waiting),
                      const SizedBox(height: AppSpace.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          MonoLabel('Synced $synced',
                              small: true, color: AppColors.outlineVariant),
                          MonoLabel('Waiting $waiting',
                              small: true, color: AppColors.outlineVariant),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),

                // What the numbers mean.
                EditorialModule(
                  accent: verdict.color == AppColors.signal,
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MonoLabel('Status', small: true, color: verdict.color),
                      const SizedBox(height: AppSpace.xs),
                      Text(verdict.detail, style: AppType.bodyMd),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),

                // The ledger.
                EditorialModule(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    children: [
                      _LedgerRow(
                          label: 'Last sync',
                          value: state.lastSyncedAt == null
                              ? 'Never'
                              : _stamp(state.lastSyncedAt!)),
                      const SizedBox(height: AppSpace.sm),
                      const HairRule(),
                      const SizedBox(height: AppSpace.sm),
                      _LedgerRow(
                          label: 'Last check',
                          value: state.checkedAt == null ? '—' : _stamp(state.checkedAt!)),
                      const SizedBox(height: AppSpace.sm),
                      const HairRule(),
                      const SizedBox(height: AppSpace.sm),
                      _LedgerRow(
                          label: 'Cloud Sync', value: syncOn ? 'On' : 'Off'),
                      const SizedBox(height: AppSpace.sm),
                      const HairRule(),
                      const SizedBox(height: AppSpace.sm),
                      _LedgerRow(
                          label: 'Automatic sync',
                          value: _autoSyncText(state.nextAutoSyncAt)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

                InkActionButton(
                  label: 'Check cloud',
                  icon: Icons.cloud_sync_outlined,
                  signal: true,
                  loading: checking,
                  onTap: (working || checking) ? null : cubit.check,
                ),
                const SizedBox(height: AppSpace.sm + 2),
                GhostButton(
                  label: 'Sync now  ·  ${EnergyService.syncInstantCost} energy',
                  icon: Icons.sync,
                  onTap: (!syncOn || working || checking)
                      ? null
                      : () => _sync(uploadAll: false),
                ),
                if (syncOn && cloud != null && cloud < onDevice) ...[
                  const SizedBox(height: AppSpace.sm + 2),
                  GhostButton(
                    label: 'Upload all  ·  ${EnergyService.syncInstantCost} energy',
                    icon: Icons.cloud_upload_outlined,
                    onTap: (working || checking)
                        ? null
                        : () => _sync(uploadAll: true),
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                const HairRule(),
                const SizedBox(height: AppSpace.md),
                const Text(
                  'Checking the cloud only counts its notes. It never changes '
                  'what is on this device. Sync now and Upload all send only '
                  'the notes you edited and cost ${EnergyService.syncInstantCost} '
                  'energy; with nothing to send they are free. Automatic sync '
                  'runs once an hour and costs ${EnergyService.syncStandardCost}.',
                  style: AppType.bodySm,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Verdict {
  final String title;
  final String detail;
  final Color color;
  const _Verdict(this.title, this.detail, this.color);
}

/// One end of the device-cloud connection: a big numeral over a mono caption.
class _Endpoint extends StatelessWidget {
  final String caption;
  final String value;
  final bool alignEnd;

  const _Endpoint({
    required this.caption,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppType.displayLg.copyWith(color: AppColors.paper),
        ),
        const SizedBox(height: AppSpace.xs),
        MonoLabel(caption, small: true, color: AppColors.outlineVariant),
      ],
    );
  }
}

/// How much of what is on the device has reached the cloud.
class _SyncBar extends StatelessWidget {
  final int synced;
  final int waiting;

  const _SyncBar({required this.synced, required this.waiting});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.sm,
      child: SizedBox(
        height: 10,
        child: (synced + waiting) == 0
            ? const ColoredBox(color: AppColors.onSurfaceVariant)
            : Row(
                children: [
                  if (synced > 0)
                    Expanded(
                      flex: synced,
                      child: const ColoredBox(color: AppColors.signal),
                    ),
                  if (waiting > 0)
                    Expanded(
                      flex: waiting,
                      child: const ColoredBox(color: AppColors.outline),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final String label;
  final String value;

  const _LedgerRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: MonoLabel(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppType.bodyMedium15,
          ),
        ),
      ],
    );
  }
}
