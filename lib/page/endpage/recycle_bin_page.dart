import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/recycle_bin/recycle_bin_cubit.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/utility/component/slide_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Recycle Bin (screens spec, Recycle Bin): notes that were deleted on a
/// device, waiting to be restored or removed for good.
///
/// Deleting a note never destroys it at once. Its content stays here, and its
/// cloud file sits in the Google Drive trash, until it is deleted forever.
class RecycleBinPage extends StatelessWidget {
  /// [source] and [now] are only given by tests; the app uses the real notes
  /// store and the device clock.
  const RecycleBinPage({super.key, this.source, this.now});

  final NotesSource? source;
  final DateTime Function()? now;

  static const String title = 'Recycle Bin';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// When a note was deleted, as the card shows it: "Deleted 9 Nov", with
  /// the year added when it is not the current one. Both dates are read in
  /// local time.
  @visibleForTesting
  static String deletedLabel(DateTime deletedAt, DateTime now) {
    final d = deletedAt.toLocal();
    final day = '${d.day} ${_months[d.month - 1]}';
    return d.year == now.toLocal().year
        ? 'Deleted $day'
        : 'Deleted $day ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RecycleBinCubit>(
      create: (_) =>
          RecycleBinCubit(source: source ?? NotesRepository.instance),
      child: _RecycleBinView(now: now ?? DateTime.now),
    );
  }
}

/// What a card is waiting for while one of its actions runs.
enum _Pending { restore, deleteForever }

class _RecycleBinView extends StatefulWidget {
  const _RecycleBinView({required this.now});

  final DateTime Function() now;

  @override
  State<_RecycleBinView> createState() => _RecycleBinViewState();
}

class _RecycleBinViewState extends State<_RecycleBinView> {
  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  /// Notes with an action in flight. Their buttons ignore taps until it
  /// answers, so a second tap cannot run it twice.
  final Map<String, _Pending> _pending = {};

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

  void _show(UiMessage message) =>
      AtomicSnackBar(text: message.text, millis: message.millis).show(context);

  Future<void> _run(
      Note note, _Pending kind, Future<UiMessage> Function() action) async {
    if (_pending.containsKey(note.id)) return;
    setState(() => _pending[note.id] = kind);
    try {
      final message = await action();
      if (mounted) _show(message);
    } finally {
      if (mounted) setState(() => _pending.remove(note.id));
    }
  }

  void _restore(Note note) {
    final cubit = context.read<RecycleBinCubit>();
    _run(note, _Pending.restore, () => cubit.restore(note));
  }

  Future<void> _deleteForever(Note note) async {
    final cubit = context.read<RecycleBinCubit>();
    final name = note.title.trim();
    final confirmed = await showAtomicDialog<bool>(
      context: context,
      // Destructive: only the buttons close it, as before.
      barrierDismissible: false,
      icon: AtomicIcons.trash,
      destructive: true,
      title: name.isEmpty
          ? 'Delete this note for good?'
          : 'Delete "$name" for good?',
      body: 'It is removed from this device. Its cloud copy stays in your '
          'Google Drive trash until Drive empties it.',
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: 'Delete forever',
          result: true,
          variant: AtomicButtonVariant.danger,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await _run(note, _Pending.deleteForever, () => cubit.deleteForever(note));
  }

  Future<void> _openMenu() async {
    final choice = await showAtomicSheet<bool>(
      context: context,
      builder: (sheet) => AtomicSheetAction(
        key: const ValueKey('recycle-bin-empty'),
        icon: AtomicIcons.trashX,
        label: 'Empty bin',
        destructive: true,
        onTap: () => Navigator.pop(sheet, true),
      ),
    );
    if (choice != true || !mounted) return;
    // The bin may have changed while the menu was open.
    final count = context.read<RecycleBinCubit>().state.notes.length;
    if (count > 0) _emptyBin(count);
  }

  void _emptyBin(int count) {
    final cubit = context.read<RecycleBinCubit>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SlideConfirmDialog(
        title: 'Empty the Recycle Bin',
        slideLabel: 'empty bin',
        consequences: [
          count == 1
              ? '1 deleted note is removed from this device for good.'
              : '$count deleted notes are removed from this device for good.',
          'Their cloud copies stay in your Google Drive trash until Drive '
              'empties it.',
        ],
        onConfirmed: () async {
          final message = await cubit.emptyBin();
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (mounted) _show(message);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: EntranceGroup(
          child: BlocBuilder<RecycleBinCubit, RecycleBinState>(
            builder: (context, state) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _titleAway,
                  builder: (context, away, _) => AtomicPageHeader(
                    title: RecycleBinPage.title,
                    showTitle: away,
                    actions: [
                      // Nothing destructive is offered for an empty bin.
                      if (state.notes.isNotEmpty)
                        AtomicIconButton(
                          key: const ValueKey('recycle-bin-menu'),
                          icon: AtomicIcons.dots,
                          tooltip: 'More options',
                          onPressed: _openMenu,
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body(context, state.notes)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<Note> notes) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final now = widget.now();
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(margin, 0, margin,
          AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
      children: [
        const Entrance(index: 0, child: PageTitle(RecycleBinPage.title)),
        Entrance(
          index: 1,
          child: Text(
            'Deleted notes wait here. Restore one to put it back, or delete '
            'it for good. Their cloud copies sit in your Google Drive trash '
            'meanwhile.',
            style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: AtomicSpace.x6),
        if (notes.isEmpty)
          const Entrance(
            index: 2,
            child: Padding(
              padding: EdgeInsets.only(top: AtomicSpace.x8),
              child: EmptyState(
                key: ValueKey('recycle-bin-empty-state'),
                title: 'Recycle Bin is empty',
                body: 'Notes you delete wait here first.',
              ),
            ),
          )
        else
          for (final (i, note) in notes.indexed)
            Stagger(
              key: ValueKey('bin-${note.id}'),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AtomicSpace.x3),
                child: _BinCard(
                  note: note,
                  deleted: RecycleBinPage.deletedLabel(note.updatedAt, now),
                  pending: _pending[note.id],
                  onRestore: () => _restore(note),
                  onDeleteForever: () => _deleteForever(note),
                ),
              ),
            ),
      ],
    );
  }
}

/// One deleted note: what it was, when it was deleted, and the two things
/// that can happen to it.
class _BinCard extends StatelessWidget {
  const _BinCard({
    required this.note,
    required this.deleted,
    required this.pending,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final Note note;
  final String deleted;
  final _Pending? pending;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    final preview = note.preview.trim();
    final meta = note.kind == NoteKind.todo ? 'Checklist · $deleted' : deleted;
    return AtomicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AtomicType.titleMedium.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AtomicSpace.x1),
          Text(
            meta,
            style: AtomicType.bodySmall.copyWith(color: c.textSecondary),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: AtomicSpace.x2),
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
            ),
          ],
          const SizedBox(height: AtomicSpace.x3),
          // The buttons share a line while they fit and stack otherwise
          // (narrow screens, large text).
          Wrap(
            spacing: AtomicSpace.x2,
            runSpacing: AtomicSpace.x2,
            children: [
              AtomicButton.tonal(
                label: 'Restore',
                icon: AtomicIcons.restore,
                size: AtomicButtonSize.compact,
                onCard: true,
                busy: pending == _Pending.restore,
                // Disabled while the other action runs.
                onPressed: pending == _Pending.deleteForever ? null : onRestore,
              ),
              AtomicButton.danger(
                label: 'Delete forever',
                size: AtomicButtonSize.compact,
                onCard: true,
                busy: pending == _Pending.deleteForever,
                onPressed: pending == _Pending.restore ? null : onDeleteForever,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
