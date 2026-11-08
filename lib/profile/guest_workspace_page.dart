import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/profile/guest_profile_store.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:flutter/material.dart';

/// Guest mode stays off until its gate is accepted (C17). Default builds
/// keep the Google-only start.
abstract final class GuestFeature {
  static const enabled = bool.fromEnvironment('ATOMIC_GUEST_PREVIEW');
}

/// What the Guest workspace needs: local notes only. No session, network,
/// Drive, vault or wallet is reachable through it.
abstract class GuestNotesPort {
  Future<void> open();
  List<Note> notes();
  Future<void> save(Note note);
  Future<void> remove(String id);
}

/// The guest store was used before [GuestNotesPort.open] succeeded.
class GuestNotesNotOpen implements Exception {
  const GuestNotesNotOpen();
  @override
  String toString() => 'Guest notes are not open yet';
}

/// [GuestNotesPort] over the isolated [GuestProfileStore].
class GuestStoreNotes implements GuestNotesPort {
  GuestStoreNotes(this.store);
  final GuestProfileStore store;
  GuestSession? _session;

  GuestSession get _open => _session ?? (throw const GuestNotesNotOpen());

  @override
  Future<void> open() async => _session = await store.open();
  @override
  List<Note> notes() => store.notes(_open);
  @override
  Future<void> save(Note note) => store.put(_open, note);
  @override
  Future<void> remove(String id) => store.remove(_open, id);
}

/// A local-only workspace: create, edit, check off, search and delete notes
/// kept on this device for a Guest. It states plainly that nothing is backed
/// up or synced, and never offers sync.
class GuestWorkspacePage extends StatefulWidget {
  const GuestWorkspacePage({required this.notes, super.key});
  final GuestNotesPort notes;

  @override
  State<GuestWorkspacePage> createState() => _GuestWorkspacePageState();
}

class _GuestWorkspacePageState extends State<GuestWorkspacePage> {
  final _search = TextEditingController();
  late Future<void> _opened = _open();
  bool _ready = false;
  String? _error;

  /// A note whose save failed. It is kept, and new edits and leaving the
  /// page wait, until a save succeeds or the user discards it.
  Note? _pending;

  /// A write is in flight; leaving now could lose its note.
  bool _saving = false;

  /// The session ended (reset or replaced). Nothing is read from it again;
  /// the next write reopens the current workspace first.
  bool _stale = false;

  Future<void> _open() async {
    _ready = false;
    await widget.notes.open();
    _stale = false;
    if (mounted) setState(() => _ready = true);
  }

  bool get _canEdit => _ready && !_stale && !_saving && _pending == null;
  bool get _canLeave => _pending == null && !_saving;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _markStale() {
    if (_stale) return;
    _stale = true;
    // Found while building: refresh the controls after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  List<Note> _visible() {
    if (_stale) return const [];
    final List<Note> all;
    try {
      all = widget.notes.notes();
    } on GuestSessionStale {
      _markStale();
      return const [];
    }
    final query = _search.text.trim().toLowerCase();
    final notes = all.where((n) => !n.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (query.isEmpty) return notes;
    return [
      for (final note in notes)
        if (note.title.toLowerCase().contains(query) ||
            NoteProjection.fromNote(note).matches(query))
          note
    ];
  }

  Future<void> _edit(Note note, {required bool existing}) async {
    final draft = note.copy();
    var deleted = false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotesCreaterPage(
          note: draft, onDelete: existing ? () => deleted = true : null),
    );
    if (!mounted) return;
    if (deleted) {
      await _write(() => widget.notes.remove(note.id));
    } else if (saved == true && !draft.isEmpty) {
      draft.touch();
      await _persist(draft);
    }
  }

  /// Saves [draft]. On any failure the draft stays as [_pending].
  Future<void> _persist(Note draft) async {
    setState(() => _pending = draft);
    final saved = await _write(() => widget.notes.save(draft));
    if (saved && mounted) setState(() => _pending = null);
  }

  Future<bool> _write(Future<void> Function() write) async {
    setState(() => _saving = true);
    try {
      if (_stale) {
        final reopened = _open();
        setState(() {
          _opened = reopened;
        });
        await reopened;
      }
      await write();
      if (mounted) setState(() => _error = null);
      return true;
    } on GuestSessionStale {
      _stale = true;
      if (mounted) {
        setState(() => _error = 'This guest workspace was reset. Your note '
            'was not saved; retry to save it in the current workspace.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your note could not be saved on this device. '
            'It is kept here; retry or discard it.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return false;
  }

  Future<void> _editPending(Note pending) async {
    final draft = pending.copy();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotesCreaterPage(note: draft),
    );
    if (!mounted || saved != true) return;
    draft.touch();
    await _persist(draft);
  }

  void _discardPending() => setState(() {
        _pending = null;
        _error = null;
      });

  /// Leaving while a note is unsaved asks first; it never drops the note
  /// silently.
  Future<void> _confirmLeave() async {
    if (_saving) return; // The write finishes or fails into [_pending].
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved note'),
        content: const Text(
            'This note is not saved on this device. Keep it to retry, or discard it and leave.'),
        actions: [
          TextButton(
              key: const ValueKey('guest-leave-keep'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep note')),
          TextButton(
              key: const ValueKey('guest-leave-discard'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and leave')),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    _discardPending();
    Navigator.pop(context);
  }

  Widget _pendingPanel(Note pending) => Card(
        key: const ValueKey('guest-pending'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Unsaved note: '
                  '${pending.title.isEmpty ? 'Untitled' : pending.title}',
                  style: AppType.bodyMd),
              Wrap(spacing: AppSpace.sm, children: [
                TextButton(
                    key: const ValueKey('guest-pending-retry'),
                    onPressed: _saving ? null : () => _persist(pending),
                    child: const Text('Retry save')),
                TextButton(
                    key: const ValueKey('guest-pending-edit'),
                    onPressed: _saving ? null : () => _editPending(pending),
                    child: const Text('Edit')),
                TextButton(
                    key: const ValueKey('guest-pending-discard'),
                    onPressed: _saving ? null : _discardPending,
                    child: const Text('Discard')),
              ]),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _canLeave,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          appBar: MyAppBar(
              text: 'Guest notes', onBack: () => Navigator.maybePop(context)),
          floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('guest-new-note'),
            onPressed:
                _canEdit ? () => _edit(Note.create(), existing: false) : null,
            icon: const Icon(Icons.add),
            label: const Text('New note'),
          ),
          body: FutureBuilder<void>(
            future: _opened,
            builder: (context, snapshot) {
              final failed = snapshot.hasError;
              final opening =
                  !failed && snapshot.connectionState != ConnectionState.done;
              final notes = failed || opening ? const <Note>[] : _visible();
              return ListView(
                padding: const EdgeInsets.all(AppSpace.md),
                children: [
                  Semantics(
                    container: true,
                    child: const Text(
                        'Guest · saved on this device only. Not backed up and not synced. Sign in with Google to keep notes in your Drive.',
                        key: ValueKey('guest-status'),
                        style: AppType.bodyMd),
                  ),
                  if (failed)
                    const Text(
                        'Guest notes on this device could not be opened. Nothing was changed.',
                        key: ValueKey('guest-open-failed'),
                        style: AppType.bodyMd),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(_error!,
                          key: const ValueKey('guest-error'),
                          style:
                              AppType.bodyMd.copyWith(color: AppColors.error)),
                    ),
                  // Shown whatever the store's state, so the note stays
                  // reachable even when reopening fails.
                  if (_pending != null) _pendingPanel(_pending!),
                  if (opening)
                    const Padding(
                      padding: EdgeInsets.all(AppSpace.md),
                      child: Center(
                          child: CircularProgressIndicator(
                              semanticsLabel: 'Opening guest notes')),
                    ),
                  if (!failed && !opening) ...[
                    if (_stale && _pending == null)
                      const Text(
                          'This guest workspace was reset. Reopen it to continue.',
                          key: ValueKey('guest-stale'),
                          style: AppType.bodyMd),
                    if (_stale && _pending == null)
                      TextButton(
                          key: const ValueKey('guest-reopen'),
                          onPressed: () => setState(() {
                                _opened = _open();
                              }),
                          child: const Text('Reopen')),
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      key: const ValueKey('guest-search'),
                      controller: _search,
                      enabled: !_stale,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Search guest notes',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    if (notes.isEmpty && !_stale)
                      const Text('No notes yet', style: AppType.bodyMd),
                    for (final note in notes)
                      ListTile(
                        key: ValueKey('guest-note-${note.id}'),
                        minVerticalPadding: AppSpace.sm,
                        title:
                            Text(note.title.isEmpty ? 'Untitled' : note.title),
                        subtitle: Text(note.preview,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        enabled: _canEdit,
                        onTap: () => _edit(note, existing: true),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      );
}
