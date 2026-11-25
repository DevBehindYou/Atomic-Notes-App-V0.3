import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/state/danger_zone/danger_zone_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirms removal from either cloud storage or this device.
class DangerZonePage extends StatelessWidget {
  const DangerZonePage({super.key, this.source});

  final NotesSource? source;

  @override
  Widget build(BuildContext context) {
    final store = source ?? NotesRepository.instance;
    return BlocProvider(
      key: ObjectKey(store),
      create: (_) => DangerZoneCubit(source: store),
      child: _DangerZoneView(source: store),
    );
  }
}

enum _WipeScope {
  cloud(
    label: 'Remove cloud notes',
    title: 'Remove cloud notes?',
    icon: AtomicIcons.cloudOff,
    removes: 'This account’s cloud-note records and its existing app-managed '
        'note files, which move to Google Drive trash.',
    keeps: 'Notes on this device and other devices, and your account.',
    body: 'This removes this account’s cloud-note records and moves its '
        'existing app-managed note files to Google Drive trash. Notes on this '
        'device and other devices are kept. A device can upload its notes '
        'again later.',
    caution: 'This doesn’t delete your account or all account history. You '
        'can’t undo this cloud-removal action inside Atomic Notes. Google '
        'Drive manages files in its trash.',
    success: 'Cloud-note records removed. Device notes were kept.',
    unconfirmed: 'Cloud removal wasn’t confirmed. Some files may already have '
        'moved to Drive trash. Device notes were kept. Check your connection '
        'and retry the same action.',
  ),
  local(
    label: 'Remove local notes',
    title: 'Remove notes from this device?',
    icon: AtomicIcons.deviceMobile,
    removes: 'Notes stored in this app on this device, including its local '
        'Recycle Bin.',
    keeps: 'Your account, settings and existing cloud copies. Available cloud '
        'notes can download again after a successful sync.',
    body: 'This removes notes stored in this app on this device, including '
        'its local Recycle Bin. Your account, settings and existing cloud '
        'copies are kept. Available cloud notes can download again after a '
        'successful sync.',
    caution: 'Notes or changes that have no other copy cannot be recovered '
        'after removal.',
    success: 'Local notes removed. Existing cloud copies, your account and '
        'settings were kept.',
    unconfirmed: 'Local removal wasn’t confirmed. Check your notes and local '
        'Recycle Bin before trying again.',
  );

  const _WipeScope({
    required this.label,
    required this.title,
    required this.icon,
    required this.removes,
    required this.keeps,
    required this.body,
    required this.caution,
    required this.success,
    required this.unconfirmed,
  });

  final String label;
  final String title;
  final IconData icon;
  final String removes;
  final String keeps;
  final String body;
  final String caution;
  final String success;
  final String unconfirmed;
}

class _DangerZoneView extends StatefulWidget {
  const _DangerZoneView({required this.source});

  final NotesSource source;

  @override
  State<_DangerZoneView> createState() => _DangerZoneViewState();
}

class _DangerZoneViewState extends State<_DangerZoneView> {
  static const _title = 'Danger Zone';
  final _scroll = ScrollController();
  final _titleAway = ValueNotifier(false);
  bool _confirming = false;

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

  void _show(String text, {bool error = false}) =>
      AtomicSnackBar(text: text, millis: 4000, error: error).show(context);

  Future<void> _confirm(_WipeScope scope) async {
    if (_confirming) return;
    _confirming = true;
    final source = widget.source;
    final reports =
        source is SyncReportSource ? source as SyncReportSource : null;
    final identity = reports?.syncReportIdentity;
    bool current() =>
        mounted &&
        identical(source, widget.source) &&
        reports?.syncReportIdentity == identity;
    final cubit = context.read<DangerZoneCubit>();
    final pending = cubit.state.unsynced;
    final local = scope == _WipeScope.local;
    try {
      await showAtomicDialog<void>(
        context: context,
        title: scope.title,
        body: scope.body,
        icon: scope.icon,
        destructive: true,
        barrierDismissible: false,
        actions: const [],
        content: _WipeConfirmation(
          scope: scope,
          pending: local ? pending : 0,
          onConfirmed: () async {
            if (!current()) {
              if (mounted) {
                _show('The notes session changed. Open the removal again.',
                    error: true);
              }
              return;
            }
            if (local && source.pendingCount != pending) {
              _show('Pending note changes changed. Review the removal again.',
                  error: true);
              return;
            }
            WipeOutcome? outcome;
            try {
              outcome = await (local ? cubit.wipeLocal() : cubit.wipeCloud());
            } catch (_) {
              // An exception can arrive after part of the removal has run.
            }
            if (!current()) return;
            if (outcome?.ok == true) {
              _show(scope.success);
            } else {
              final message = outcome?.message;
              final knownCloudRefusal = !local &&
                  (message == 'Not signed in.' ||
                      message ==
                          'Finish the pending logout before wiping cloud notes.');
              _show(knownCloudRefusal ? message! : scope.unconfirmed,
                  error: true);
            }
          },
        ),
      );
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _titleAway,
              builder: (context, away, _) =>
                  AtomicPageHeader(title: _title, showTitle: away),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.only(
                  bottom: AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  const PageTitle(_title),
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(margin, AtomicSpace.x4, margin, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AtomicBanner(
                          tone: BannerTone.danger,
                          icon: AtomicIcons.alertTriangle,
                          title: 'Two actions. No undo.',
                          body:
                              'Cloud removal and device removal affect different '
                              'copies of your notes. Review the consequences '
                              'before you confirm.',
                        ),
                        for (final scope in _WipeScope.values) ...[
                          const SizedBox(height: AtomicSpace.x3),
                          _WipeCard(
                              scope: scope, onPressed: () => _confirm(scope)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WipeCard extends StatelessWidget {
  const _WipeCard({required this.scope, required this.onPressed});

  final _WipeScope scope;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AtomicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.danger,
                  borderRadius: AtomicRadius.mediumAll,
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(scope.icon, color: c.onDanger, size: 22),
                ),
              ),
              const SizedBox(width: AtomicSpace.x3),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    scope == _WipeScope.cloud
                        ? 'Wipe cloud notes'
                        : 'Wipe local notes',
                    style:
                        AtomicType.titleMedium.copyWith(color: c.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          for (final (label, text) in [
            ('Removes', scope.removes),
            ('Keeps', scope.keeps),
          ]) ...[
            const SizedBox(height: AtomicSpace.x3),
            Text(label,
                style: AtomicType.labelLarge.copyWith(color: c.textPrimary)),
            const SizedBox(height: AtomicSpace.x1),
            Text(text,
                style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
          ],
          const SizedBox(height: AtomicSpace.x4),
          AtomicButton.danger(
              label: scope.label, expand: true, onPressed: onPressed),
        ],
      ),
    );
  }
}

class _WipeConfirmation extends StatefulWidget {
  const _WipeConfirmation({
    required this.scope,
    required this.pending,
    required this.onConfirmed,
  });

  final _WipeScope scope;
  final int pending;
  final Future<void> Function() onConfirmed;

  @override
  State<_WipeConfirmation> createState() => _WipeConfirmationState();
}

class _WipeConfirmationState extends State<_WipeConfirmation> {
  bool _reviewed = false;
  bool _locked = false;

  bool get _canSubmit =>
      mounted && !_locked && ModalRoute.of(context)?.isCurrent == true;

  void _review() {
    if (_canSubmit && !_reviewed) setState(() => _reviewed = true);
  }

  Future<void> _confirm() async {
    // Both input paths can reach this before the next frame.
    if (!_canSubmit) return;
    setState(() => _locked = true);
    await widget.onConfirmed();
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  void _cancel() {
    if (!_canSubmit) return;
    _locked = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scope = widget.scope;
    final pending = widget.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scope.caution,
            style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
        if (pending > 0) ...[
          const SizedBox(height: AtomicSpace.x3),
          Text(
            pending == 1
                ? '1 note change hasn’t finished syncing. Removing local notes '
                    'can lose unsynced content and discard pending deletions. '
                    'Sync first if you want to keep those changes.'
                : '$pending note changes haven’t finished syncing. Removing '
                    'local notes can lose unsynced content and discard pending '
                    'deletions. Sync first if you want to keep those changes.',
            style: AtomicType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ],
        const SizedBox(height: AtomicSpace.x4),
        Text('Slide to ${scope.label.toLowerCase()}',
            style: AtomicType.labelLarge.copyWith(color: c.textPrimary)),
        const SizedBox(height: AtomicSpace.x2),
        IgnorePointer(
          ignoring: _locked,
          child: SlideToConfirm(
            label: scope.label.toLowerCase(),
            target: scope,
            allowAlternativeActivation: false,
            onConfirmed: _confirm,
          ),
        ),
        if (_locked) ...[
          const SizedBox(height: AtomicSpace.x2),
          Semantics(
            liveRegion: true,
            child: Text('Removing notes…',
                style: AtomicType.bodyMedium.copyWith(color: c.textPrimary)),
          ),
        ],
        const SizedBox(height: AtomicSpace.x2),
        AtomicButton.text(
          label: 'Review removal',
          onPressed: _locked ? null : _review,
        ),
        if (_reviewed)
          AtomicButton.danger(
            label: scope.label,
            busy: _locked,
            onPressed: _locked ? null : _confirm,
          ),
        AtomicButton.text(
          label: 'Cancel',
          onPressed: _locked ? null : _cancel,
        ),
      ],
    );
  }
}
