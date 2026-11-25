import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
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
/// Deleting a note never destroys it at once: its content stays here until it
/// is deleted forever. Both confirmations say what that removal does now (see
/// [BinRemovalStep]), and each confirmed removal covers exactly the notes it
/// showed (see [BinRemoval]).
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

  /// What deleting [note] for good has to do first, when no store judged it.
  /// Read from its sync flag only: the page never infers the note's past in
  /// the cloud. The notes store's own judgement replaces it (see
  /// [BinRemover.stepOf]).
  @visibleForTesting
  static BinRemovalStep removalStep(Note note) => BinRemovalStep.of(note);

  /// The page explanation under the title.
  @visibleForTesting
  static const String explanation =
      'Deleted notes wait here. Restore one to put it back, or delete it for '
      'good to remove it from this device. A note with changes still waiting '
      'to sync is synced first, and stays here if that sync cannot finish. '
      'Deleting here does not promise to remove every copy kept elsewhere.';

  /// The body of the "Delete forever" confirmation for [note]: what this
  /// removal does now, not what happened to the note before. [step] is the
  /// store's judgement, when it gave one.
  @visibleForTesting
  static String deleteForeverBody(Note note, {BinRemovalStep? step}) =>
      switch (step ?? removalStep(note)) {
        // A change waits, but the store says nothing of it can be in the
        // cloud: say only that no sync is needed.
        BinRemovalStep.removeNow when note.dirty =>
          'It is removed from this device now and cannot be brought back from '
              'the Recycle Bin. No sync is needed to remove this note from '
              'this device, so this sends nothing to the cloud.',
        BinRemovalStep.removeNow =>
          'It is removed from this device now and cannot be brought back from '
              'the Recycle Bin. It has no changes waiting to sync, so this '
              'sends nothing to the cloud.',
        BinRemovalStep.syncFirst =>
          'It has changes that have not finished syncing. They sync first, '
              'and only then is the note removed from this device. Without '
              'Cloud Sync, or if the sync fails, it stays in the Recycle Bin.',
      };

  /// What "Empty bin" does to [notes]: how many it removes, and how many of
  /// them need no sync. [stepOf] is the store's judgement, when it gives one.
  @visibleForTesting
  static List<String> emptyBinConsequences(List<Note> notes,
      {BinRemovalStep Function(Note)? stepOf}) {
    final step = stepOf ?? removalStep;
    final count = notes.length;
    final removeNow = notes.where((n) => step(n) == BinRemovalStep.removeNow);
    final now = removeNow.where((n) => !n.dirty).length;
    // A change waits, but the store says nothing of it can be in the cloud.
    final local = removeNow.where((n) => n.dirty).length;
    return [
      count == 1
          ? '1 deleted note is removed from this device for good.'
          : '$count deleted notes are removed from this device for good.',
      if (now == 1)
        '1 has no changes waiting to sync, so nothing is sent for it.',
      if (now > 1)
        '$now have no changes waiting to sync, so nothing is sent for them.',
      if (local == 1)
        'No sync is needed to remove 1 note from this device, so nothing is '
            'sent for it.',
      if (local > 1)
        'No sync is needed to remove $local notes from this device, so '
            'nothing is sent for them.',
    ];
  }

  /// The warning "Empty bin" adds when some notes must sync first, or null
  /// when none must.
  @visibleForTesting
  static String? emptyBinWarning(List<Note> notes,
      {BinRemovalStep Function(Note)? stepOf}) {
    final step = stepOf ?? removalStep;
    final pending =
        notes.where((n) => step(n) == BinRemovalStep.syncFirst).length;
    if (pending == 0) return null;
    return '${pending == 1 ? '1 note has' : '$pending notes have'} changes '
        'that have not finished syncing. They sync first. Without Cloud Sync, '
        'or if the sync fails, nothing is deleted for good.';
  }

  @override
  Widget build(BuildContext context) {
    final store = source ?? NotesRepository.instance;
    return BlocProvider<RecycleBinCubit>(
      create: (_) => RecycleBinCubit(source: store),
      child: _RecycleBinView(source: store, now: now ?? DateTime.now),
    );
  }
}

/// What deleting a bin note for good has to do first, read from its sync
/// flag alone. It says nothing about the note's past in the cloud: a version
/// number of 0 is no proof that the note never synced (a cloud wipe resets
/// it), and a waiting change is no proof of what the cloud holds.
enum BinRemovalStep {
  /// Nothing about the note waits to sync, so removing it sends nothing: it
  /// is only forgotten on this device.
  removeNow,

  /// The note has a change that has not finished syncing. It syncs first, and
  /// the note is kept when that sync cannot finish.
  syncFirst;

  static BinRemovalStep of(Note note) =>
      note.dirty ? BinRemovalStep.syncFirst : BinRemovalStep.removeNow;
}

/// One confirmed "delete for good", frozen when its confirmation opened:
/// exactly which notes it showed, what it said removing each one does, and
/// whose session it was. Notes are edited in place, so it keeps copies of
/// those facts, never the notes. A note that reaches the bin later is not
/// part of it. With the real notes store, the store froze those facts itself
/// ([BinPurgeConsent]) and checks them again before it removes anything.
final class BinRemoval {
  BinRemoval._(this._facts, this._identity,
      {required this.wholeBin, BinPurgeConsent? consent})
      : _consent = consent;

  final Map<String, (BinRemovalStep, String)> _facts;
  final Object? _identity;
  final BinPurgeConsent? _consent;

  /// Confirmed from "Empty bin" rather than from one note's card.
  final bool wholeBin;

  /// The confirmed notes, in the order they were shown.
  List<String> get ids => List.unmodifiable(_facts.keys);

  int get length => _facts.length;

  /// How many confirmed notes were shown with [step].
  int count(BinRemovalStep step) =>
      _facts.values.where((f) => f.$1 == step).length;

  /// What the confirmation said removing [id] does, or null when [id] is not
  /// part of it.
  BinRemovalStep? stepOf(String id) => _facts[id]?.$1;
}

/// Runs the page's confirmed removals against its notes store: the same
/// store and `deleteForever(ids)` call the cubit uses. With the real notes
/// store the store itself says what each removal needs, syncs when it must
/// and removes only while its confirmation still holds. One removal runs at a
/// time.
class BinRemover {
  BinRemover(this._source);

  final NotesSource _source;

  /// The real notes store, which judges and guards removals itself.
  NotesRepository? get _store {
    final source = _source;
    return source is NotesRepository ? source : null;
  }

  /// What deleting [note] for good has to do first: the store's judgement
  /// when it gives one, else the note's sync flag.
  BinRemovalStep stepOf(Note note) {
    final store = _store;
    if (store == null) return BinRemovalStep.of(note);
    return _step(store.binPurgeConsent([note.id]).factOf(note.id), note);
  }

  static BinRemovalStep _step(BinPurgeFact? fact, Note note) => fact == null
      ? BinRemovalStep.of(note)
      : fact.needsSync
          ? BinRemovalStep.syncFirst
          : BinRemovalStep.removeNow;

  /// A removal is running; another one waits for it to answer.
  bool _removing = false;

  /// The account session and store lifetime, when the store can tell them
  /// apart.
  Object? get _identity {
    final source = _source;
    return source is SyncReportSource
        ? (source as SyncReportSource).syncReportIdentity
        : null;
  }

  /// Freezes what a confirmation is about to show for [notes]. Build it from
  /// the same notes the confirmation's words are built from, at the same
  /// moment.
  BinRemoval confirm(Iterable<Note> notes, {bool wholeBin = false}) {
    final shown = notes.toList();
    final consent = _store?.binPurgeConsent(shown.map((n) => n.id));
    return BinRemoval._(
        Map.unmodifiable({
          for (final n in shown)
            n.id: (
              consent == null
                  ? BinRemovalStep.of(n)
                  : _step(consent.factOf(n.id), n),
              n.title
            ),
        }),
        _identity,
        wholeBin: wholeBin,
        consent: consent);
  }

  static const UiMessage _changed = UiMessage(
      'The Recycle Bin changed before this could finish. Nothing was deleted '
      'for good. Check it and try again.',
      4000);

  /// Whether [removal] no longer matches what its confirmation showed. Each
  /// confirmed note must still be in the bin, unchanged, in the same session.
  /// The one change allowed is the one the confirmation announced: a change
  /// that had to sync first has synced.
  bool _drifted(BinRemoval removal) {
    final store = _store, consent = removal._consent;
    if (store != null || consent != null) {
      return store == null ||
          consent == null ||
          !consent.allows(store.binPurgeConsent(removal.ids));
    }
    if (removal._identity != _identity) return true;
    for (final MapEntry(key: id, value: (step, title))
        in removal._facts.entries) {
      final note = _source.byId(id);
      if (note == null || !note.deleted || note.title != title) return true;
      final now = BinRemovalStep.of(note);
      if (now != step && step != BinRemovalStep.syncFirst) return true;
    }
    return false;
  }

  bool _waitsToSync(BinRemoval removal) =>
      removal._facts.keys.any((id) => _source.byId(id)?.dirty ?? false);

  /// Deletes for good exactly the notes [removal] confirmed, and only while
  /// they are as it showed them. The real store gets the confirmation itself
  /// and guards every wait inside its call. With any other store a change
  /// that must sync first syncs here, before the store is asked, and the
  /// check right before the store's call has no wait in between.
  Future<UiMessage> remove(BinRemoval removal) async {
    if (_removing) {
      return const UiMessage(
          'Another removal is still running. Try again when it finishes.',
          3000);
    }
    _removing = true;
    try {
      if (removal.length == 0 || _drifted(removal)) return _changed;
      final store = _store, consent = removal._consent;
      if (store != null && consent != null) {
        // The store syncs first when it must and checks the confirmation
        // again after every wait, so a note restored or replaced meanwhile is
        // never removed under it.
        // The store returns how many it removed for good, so the message
        // says that, not what is left in memory.
        final removed =
            await store.deleteForever(removal.ids, consent: consent);
        if (removed == removal.length) return _done(removal);
        if (removed > 0) return _interrupted(removal, removed);
        // Nothing was removed: a change still waiting to sync says why;
        // otherwise the store could not show the bin is as confirmed.
        if (!_drifted(removal) &&
            store.binPurgeConsent(removal.ids).needsSync) {
          return UiMessage(_notSentYet(), 3000);
        }
        return _changed;
      }
      if (_waitsToSync(removal)) {
        final synced = await _source.syncNow();
        if (_drifted(removal)) return _changed;
        // Like the store, judge the confirmed notes, not the whole sync: other
        // changes may still wait (an automatic sync sends one batch an hour)
        // once these have gone.
        if (_waitsToSync(removal)) {
          return synced ? _changed : UiMessage(_notSentYet(), 3000);
        }
      }
      final removed = await _source.deleteForever(removal.ids);
      return _outcome(removal, removed);
    } catch (_) {
      return _unfinished(removal);
    } finally {
      _removing = false;
    }
  }

  /// What happened, read from the store afterwards rather than assumed.
  UiMessage _outcome(BinRemoval removal, int removed) {
    final left = removal.ids.where((id) => _source.byId(id) != null).length;
    if (removed == 0 && left == removal.length) {
      return UiMessage(_notSentYet(), 3000);
    }
    if (left == removal.length) return _unfinished(removal);
    if (left > 0) {
      final gone = removal.length - left;
      return UiMessage(
          'Deleted $gone of ${removal.length} notes for good. '
          '${left == 1 ? 'One is' : '$left are'} still in the Recycle Bin.',
          4000);
    }
    return _done(removal);
  }

  /// A confirmed removal that stopped after removing [removed] of its notes
  /// for good. The remaining attempts have no confirmed outcome.
  UiMessage _interrupted(BinRemoval removal, int removed) {
    final kept = removal.length - removed;
    return UiMessage(
        'Deleted $removed of ${removal.length} notes for good, then the '
        'removal was interrupted. ${kept == 1 ? 'One deletion was' : '$kept deletions were'} '
        'not confirmed. Check the Recycle Bin.',
        4000);
  }

  /// Every confirmed note was removed for good.
  UiMessage _done(BinRemoval removal) {
    if (!removal.wholeBin) return const UiMessage('Deleted for good', 3000);
    if (_source.binNotes.isEmpty) {
      return const UiMessage('Recycle Bin emptied', 3000);
    }
    return UiMessage(
        '${removal.length == 1 ? '1 note' : '${removal.length} notes'} '
        'deleted for good. Notes deleted after you confirmed are still in the '
        'Recycle Bin.',
        4000);
  }

  /// A removal that stopped part way, said only as far as the store confirms
  /// it.
  UiMessage _unfinished(BinRemoval removal) {
    final all = removal.ids.every((id) => _source.byId(id)?.deleted ?? false);
    if (!all) {
      return const UiMessage(
          "Couldn't confirm the removal. Check the Recycle Bin before trying "
          'again.',
          4000);
    }
    return UiMessage(
        removal.length == 1
            ? "Couldn't finish removing this note. It remains in the Recycle "
                'Bin.'
            : "Couldn't finish removing these notes. They remain in the "
                'Recycle Bin.',
        4000);
  }

  /// Why a delete could not go through: a change must reach the cloud first,
  /// or the note would come back. The same words as the cubit's.
  String _notSentYet() {
    final next = _source.nextAutoSyncAt;
    if (next == null) {
      return 'Could not delete yet. Turn on Cloud Sync and sync first.';
    }
    final int minutes =
        (next.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 60);
    return 'This deletion has not reached the cloud yet. It sends in $minutes '
        'min, or use Sync now in Cloud Notes.';
  }
}

/// What a card is waiting for while one of its actions runs.
enum _Pending { restore, deleteForever }

class _RecycleBinView extends StatefulWidget {
  const _RecycleBinView({required this.source, required this.now});

  /// The store the cubit reads; confirmed removals run against it too.
  final NotesSource source;
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

  /// Runs confirmed removals, one at a time.
  late final BinRemover _remover = BinRemover(widget.source);

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
    final name = note.title.trim();
    // The words and the confirmed removal come from the same note, now.
    final removal = _remover.confirm([note]);
    final body =
        RecycleBinPage.deleteForeverBody(note, step: removal.stepOf(note.id));
    final confirmed = await showAtomicDialog<bool>(
      context: context,
      // Destructive: only the buttons close it, as before.
      barrierDismissible: false,
      icon: AtomicIcons.trash,
      destructive: true,
      title: name.isEmpty
          ? 'Delete this note for good?'
          : 'Delete "$name" for good?',
      body: body,
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
    await _run(note, _Pending.deleteForever, () => _remover.remove(removal));
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
    final notes = context.read<RecycleBinCubit>().state.notes;
    if (notes.isNotEmpty) _emptyBin(notes);
  }

  void _emptyBin(List<Note> notes) {
    // Frozen with the words: a note deleted while the slide is open is not
    // part of it.
    final removal = _remover.confirm(notes, wholeBin: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SlideConfirmDialog(
        title: 'Empty the Recycle Bin',
        slideLabel: 'empty bin',
        consequences: RecycleBinPage.emptyBinConsequences(notes,
            stepOf: (n) => removal.stepOf(n.id) ?? BinRemovalStep.of(n)),
        warning: RecycleBinPage.emptyBinWarning(notes,
            stepOf: (n) => removal.stepOf(n.id) ?? BinRemovalStep.of(n)),
        onConfirmed: () async {
          final message = await _remover.remove(removal);
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
            RecycleBinPage.explanation,
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
