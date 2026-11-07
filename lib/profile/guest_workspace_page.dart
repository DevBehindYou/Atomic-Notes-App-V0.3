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

/// [GuestNotesPort] over the isolated [GuestProfileStore].
class GuestStoreNotes implements GuestNotesPort {
  GuestStoreNotes(this.store);
  final GuestProfileStore store;
  GuestSession? _session;

  @override
  Future<void> open() async => _session = await store.open();
  @override
  List<Note> notes() => store.notes(_session!);
  @override
  Future<void> save(Note note) => store.put(_session!, note);
  @override
  Future<void> remove(String id) => store.remove(_session!, id);
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
  late final Future<void> _opened = widget.notes.open();
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Note> _visible() {
    final query = _search.text.trim().toLowerCase();
    final notes = widget.notes.notes().where((n) => !n.deleted).toList()
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
    try {
      if (deleted) {
        await widget.notes.remove(note.id);
      } else if (saved == true && !draft.isEmpty) {
        draft.touch();
        await widget.notes.save(draft);
      }
      setState(() => _error = null);
    } on GuestSessionStale {
      setState(() =>
          _error = 'This guest workspace was reset. Reopen it to continue.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const MyAppBar(text: 'Guest notes'),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('guest-new-note'),
          onPressed: () => _edit(Note.create(), existing: false),
          icon: const Icon(Icons.add),
          label: const Text('New note'),
        ),
        body: FutureBuilder<void>(
          future: _opened,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(AppSpace.md),
                child: Text(
                    'Guest notes on this device could not be opened. Nothing was changed.',
                    key: ValueKey('guest-open-failed'),
                    style: AppType.bodyMd),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: CircularProgressIndicator(
                      semanticsLabel: 'Opening guest notes'));
            }
            final notes = _visible();
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
                if (_error != null)
                  Text(_error!,
                      key: const ValueKey('guest-error'),
                      style: AppType.bodyMd.copyWith(color: AppColors.error)),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  key: const ValueKey('guest-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Search guest notes',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpace.sm),
                if (notes.isEmpty)
                  const Text('No notes yet', style: AppType.bodyMd),
                for (final note in notes)
                  ListTile(
                    key: ValueKey('guest-note-${note.id}'),
                    minVerticalPadding: AppSpace.sm,
                    title: Text(note.title.isEmpty ? 'Untitled' : note.title),
                    subtitle: Text(note.preview,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _edit(note, existing: true),
                  ),
              ],
            );
          },
        ),
      );
}
