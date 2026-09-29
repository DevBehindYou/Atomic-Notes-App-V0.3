import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/note_skeliton.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// The notes screen. What it shows lives in [NotesBloc]; this file only draws it. Each part
/// (title row, filter chips, search box, grid, add menu) listens to just the fields it shows,
/// so a tick on one card does not rebuild the header and typing in the search box does not
/// rebuild the add menu.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _controller = ScrollController();

  /// Live text search over the current account's notes (title, body, checklist
  /// items). Runs entirely in memory on the already-decrypted notes, so it never
  /// touches the network and works offline.
  final TextEditingController _searchCtrl = TextEditingController();

  late final Widget _body;

  /// Below this height (a phone on its side) the header would leave the grid a strip a
  /// card tall, so it scrolls away with the notes instead of staying put.
  static const double _shortScreen = 480;
  late final Widget _scrollingBody;

  @override
  void initState() {
    super.initState();
    // A screen opened afresh starts with the newest filter, an empty search and nothing selected.
    context.read<NotesBloc>().add(const NotesViewReset());
    // Built once: the parts below listen to the bloc themselves, so the tree does not have to be
    // rebuilt when the selection starts or ends.
    _body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(searchController: _searchCtrl),
        Expanded(child: _NotesGrid(controller: _controller)),
      ],
    );
    _scrollingBody = NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(child: _Header(searchController: _searchCtrl)),
      ],
      // No controller of its own: the grid scrolls through the NestedScrollView's.
      body: const _NotesGrid(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NotesBloc, NotesState>(
      listenWhen: (previous, current) =>
          previous.notice != current.notice &&
          current.notice != null &&
          !current.notice!.fromSync,
      listener: (context, state) => MySnackBar(
        text: state.notice!.text,
        sec: state.notice!.millis,
      ).showMySnackBar(context),
      child: BlocSelector<NotesBloc, NotesState, bool>(
        selector: (state) => state.selecting,
        builder: (context, selecting) => Scaffold(
          backgroundColor: AppColors.paper,
          // A tap anywhere that isn't the search field itself drops its focus —
          // otherwise the keyboard and cursor stay put until something else
          // happens to take focus.
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxHeight < _shortScreen ? _scrollingBody : _body,
            ),
          ),
          floatingActionButton: selecting ? null : const _AddMenu(),
        ),
      ),
    );
  }
}

// ---- header ---------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.md, AppSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TitleRow(),
          const SizedBox(height: AppSpace.sm),
          const HairRule(color: AppColors.ink),
          _FilterAndSearch(searchController: searchController),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      buildWhen: (previous, current) =>
          previous.selected.length != current.selected.length ||
          previous.count != current.count ||
          previous.limit != current.limit ||
          previous.pending != current.pending,
      builder: (context, state) {
        final bloc = context.read<NotesBloc>();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: EditorialHeading(
                state.selecting ? '${state.selected.length} selected' : 'Notes',
                style: AppType.headlineLg,
                maxLines: 1,
              ),
            ),
            if (state.selecting) ...[
              GestureDetector(
                onTap: () => bloc.add(const NoteSelectionAllToggled()),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: MonoLabel('ALL'),
                ),
              ),
              GestureDetector(
                onTap: () => bloc.add(const NoteSelectionCleared()),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: MonoLabel('CANCEL'),
                ),
              ),
              GestureDetector(
                onTap: () => bloc.add(const NotesDeleteSelected()),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm + 2, vertical: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    borderRadius: AppRadius.std,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      MonoLabel('DELETE', color: Colors.white),
                    ],
                  ),
                ),
              ),
            ] else
              // Usage is shown always, not just when it's a problem, so
              // running out is never a surprise.
              MonoLabel(
                '${state.usageLabel}'
                '${state.pending > 0 ? " · ${state.pending} UNSYNCED" : ""}',
                color: state.isAtLimit
                    ? AppColors.error
                    : (state.remaining <= 5 ? AppColors.signal : null),
              ),
          ],
        );
      },
    );
  }
}

/// The filter chips and the search box, hidden while notes are being selected.
class _FilterAndSearch extends StatelessWidget {
  const _FilterAndSearch({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NotesBloc, NotesState, bool>(
      selector: (state) => state.selecting,
      builder: (context, selecting) {
        if (selecting) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          // Some bigger-screen devices default to a larger system font scale
          // than the phones this row was built against; left unclamped, that
          // grows the filter chips and the search field's hint/icon past the
          // row's intended proportions and pushes into the mascot's fixed
          // column. Capped here so the row's own layout stays predictable
          // regardless of the device's text-size setting.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler:
                  MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Filter / sort row.
                      const SizedBox(height: 28, child: _FilterChips()),
                      const SizedBox(height: AppSpace.sm),
                      _SearchField(controller: searchController),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                const _Mascot(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Atomi", the app's mascot. A tap opens a small chat bubble saying how sync
/// stands; it closes by itself after a few seconds or on a second tap.
class _Mascot extends StatefulWidget {
  const _Mascot();

  /// What Atomi says: whether changes are waiting, and when automatic sync next opens.
  /// "Syncing now" only while a sync is running: offline, changes just wait.
  static String syncMessage(DateTime? next, int pending, {bool syncing = false}) {
    final now = DateTime.now();
    final waiting = pending == 1 ? '1 change' : '$pending changes';
    if (pending > 0 && syncing) return 'Syncing $waiting now.';
    if (next == null || !next.isAfter(now)) {
      if (pending == 0) return 'All notes synced.';
      return pending == 1
          ? '1 change waiting. It syncs by itself when you are online.'
          : '$waiting waiting. They sync by themselves when you are online.';
    }
    final minutes = (next.difference(now).inSeconds / 60).ceil();
    final when = minutes <= 1 ? 'under a minute' : '$minutes min';
    return pending == 0
        ? 'All synced. Next sync in $when.'
        : '$waiting waiting. Next sync in $when.';
  }

  @override
  State<_Mascot> createState() => _MascotState();
}

class _MascotState extends State<_Mascot> {
  final OverlayPortalController _bubble = OverlayPortalController();
  final LayerLink _anchor = LayerLink();
  Timer? _autoHide;
  String _message = '';

  void _onTap() {
    _autoHide?.cancel();
    if (_bubble.isShowing) {
      _bubble.hide();
      return;
    }
    final state = context.read<NotesBloc>().state;
    setState(() => _message =
        _Mascot.syncMessage(state.nextAutoSyncAt, state.pending, syncing: state.syncing));
    _bubble.show();
    _autoHide = Timer(const Duration(seconds: 3), () {
      if (mounted && _bubble.isShowing) _bubble.hide();
    });
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _anchor,
      child: OverlayPortal(
        controller: _bubble,
        overlayChildBuilder: (_) => Positioned(
          width: 240,
          child: CompositedTransformFollower(
            link: _anchor,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topRight,
              child: _ChatBubble(text: _message),
            ),
          ),
        ),
        // Hard-clipped: fixed regardless of device text scale or the GIF's own
        // frame size, so it can never paint past its box onto the search field.
        child: GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: const ClipRect(
            child: SizedBox(
              width: 72,
              height: 72,
              child: Image(
                image: AssetImage(
                    'assets/Atomic Icons/dotgrid-blink-transparent.gif'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chat-style bubble, its sharp corner pointing up at the mascot.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: const BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(3),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Text(text, style: AppType.bodySm.copyWith(color: AppColors.paper)),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NotesBloc, NotesState, NoteFilter>(
      selector: (state) => state.filter,
      builder: (context, current) => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: NoteFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.xs + 2),
        itemBuilder: (context, i) {
          final f = NoteFilter.values[i];
          return GestureDetector(
            onTap: () => context.read<NotesBloc>().add(NotesFilterChanged(f)),
            behavior: HitTestBehavior.opaque,
            child: DataChip(f.label, active: current == f),
          );
        },
      ),
    );
  }
}

/// Live search field under the filter chips.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  static const _border = OutlineInputBorder(
    borderRadius: AppRadius.std,
    borderSide: BorderSide(color: AppColors.outlineVariant, width: AppStroke.rule),
  );

  static const _focusedBorder = OutlineInputBorder(
    borderRadius: AppRadius.std,
    borderSide: BorderSide(color: AppColors.signal, width: AppStroke.offset),
  );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (v) => context.read<NotesBloc>().add(NotesQueryChanged(v)),
      cursorColor: AppColors.signal,
      style: AppType.bodyMd,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceLowest,
        hintText: 'Search notes',
        prefixIcon:
            const Icon(Icons.search, size: 18, color: AppColors.slateData),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        suffixIcon: BlocSelector<NotesBloc, NotesState, bool>(
          selector: (state) => state.query.isNotEmpty,
          builder: (context, hasQuery) => hasQuery
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    context.read<NotesBloc>().add(const NotesQueryChanged(''));
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(Icons.close,
                      size: 16, color: AppColors.slateData),
                )
              : const SizedBox.shrink(),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: AppSpace.sm),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _focusedBorder,
      ),
    );
  }
}

// ---- the grid ---------------------------------------------------------------

int _responsiveColumnCount(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 550) return 3;
  return 2;
}

Future<void> _openEditor(BuildContext context, Note note) async {
  final bloc = context.read<NotesBloc>();
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NotesCreaterPage(note: note),
  );
  if (saved != true) return; // An abandoned new note was never stored.
  if (note.isEmpty) {
    if (!context.mounted) return;
    const MySnackBar(text: "Empty note discarded", sec: 1200)
        .showMySnackBar(context);
    return;
  }
  bloc.add(NoteSaved(note));
}

void _newNote(BuildContext context, NoteKind kind) {
  // Notes and to-dos draw on the same allowance.
  final state = context.read<NotesBloc>().state;
  if (state.isAtLimit) {
    MySnackBar(
      text: "You've reached ${state.limit} notes — delete one to make room",
      sec: 3000,
    ).showMySnackBar(context);
    return;
  }
  _openEditor(context, Note.create(kind: kind));
}

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({this.controller});

  /// Null inside the short-screen layout, where the NestedScrollView drives the scrolling.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      // Not the sync spinner, the notices or the counts: the cards show none of them.
      buildWhen: (previous, current) =>
          previous.signature != current.signature ||
          !setEquals(previous.selected, current.selected) ||
          previous.filter != current.filter ||
          previous.query != current.query,
      builder: (context, state) {
        final notes = state.notes;
        if (notes.isEmpty) return _EmptyState(narrowed: state.narrowed);
        final bloc = context.read<NotesBloc>();
        return Scrollbar(
          radius: AppRadius.smRadius,
          thickness: 4,
          controller: controller,
          child: MasonryGridView.count(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.md, AppSpace.sm, AppSpace.md, 110),
            crossAxisCount: _responsiveColumnCount(context),
            mainAxisSpacing: AppSpace.sm,
            crossAxisSpacing: AppSpace.sm,
            controller: controller,
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return NotesBulder(
                key: ValueKey(note.id),
                note: note,
                selected: state.selected.contains(note.id),
                selectionMode: state.selecting,
                onTap: () => state.selecting
                    ? bloc.add(NoteSelectionToggled(note.id))
                    : _openEditor(context, note),
                onLongPress: () => bloc.add(NoteSelectionToggled(note.id)),
                onToggleItem: (i) => bloc.add(NoteItemToggled(note, i)),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.narrowed});

  final bool narrowed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MonoLabel(narrowed ? 'FILTER / NO MATCH' : 'INDEX / EMPTY'),
            const SizedBox(height: AppSpace.sm),
            EditorialHeading(
              narrowed ? 'Nothing here\nyet.' : 'Nothing written\nyet.',
              style: AppType.headlineLg,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              narrowed
                  ? 'No notes match this filter. Try another one.'
                  : 'Tap New note to start writing, or Checklist for '
                      'something you can tick off.',
              style: AppType.bodyMd.copyWith(color: AppColors.slateData),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- add menu -----------------------------------------------------------------

/// Two-way add: a plain note or a checklist. Both dim at the cap.
class _AddMenu extends StatelessWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      buildWhen: (previous, current) =>
          previous.isAtLimit != current.isAtLimit ||
          previous.limit != current.limit,
      builder: (context, state) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (state.isAtLimit)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm + 2, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.std,
                border: Border.all(color: AppColors.error, width: AppStroke.rule),
              ),
              child: MonoLabel('${state.limit} NOTE LIMIT REACHED',
                  color: AppColors.onErrorContainer),
            ),
          GestureDetector(
            onTap: () => _newNote(context, NoteKind.todo),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: AppRadius.std,
                border:
                    Border.all(color: AppColors.ink, width: AppStroke.hairline),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist_rounded, size: 16, color: AppColors.ink),
                  SizedBox(width: AppSpace.sm),
                  MonoLabel('CHECKLIST', color: AppColors.ink),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          GestureDetector(
            onTap: () => _newNote(context, NoteKind.text),
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: AppRadius.std,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(AppStroke.offset, AppStroke.offset),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md + 2, vertical: AppSpace.md - 2),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: AppRadius.std,
                  border: Border.all(
                      color: AppColors.ink, width: AppStroke.hairline),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: AppColors.paper),
                    SizedBox(width: AppSpace.sm),
                    MonoLabel('NEW NOTE', color: AppColors.paper),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept so existing imports of the skeleton keep resolving.
const Widget kNotesSkeleton = Skeliton();
