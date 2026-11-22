import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/feedback/status_strip.dart';
import 'package:atomic_notes/ui/fields/search_field.dart';
import 'package:atomic_notes/ui/headers/selection_bar.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/editor_route.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/note_skeliton.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// The notes screen (screens spec, Home). What it shows lives in
/// [NotesBloc]; this file only draws it. Each part (title row, status strip,
/// chips, cards, new-note button) listens to just the fields it shows, so a
/// tick on one card does not rebuild the header and typing in the search
/// field does not rebuild the chips or the counts.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.now,
    this.headerActions = const [],
    this.back,
  });

  /// Local clock used for the greeting; injectable for date/resume tests.
  final DateTime Function()? now;

  /// The shell's one Back path (Codex R35). Home answers through it instead
  /// of holding a pop handler of its own, so one press is used once.
  final HomeBack? back;

  /// The app-level actions at the right of the header row (sync,
  /// notifications, the Settings avatar). The shell supplies them, so Home
  /// stays free of the profile and notification state. Read once, when the
  /// page is built, like the rest of the header.
  final List<Widget> headerActions;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Lets the signed-in shell offer a system Back to Home before its own
/// two-press exit (screens spec, Home: Back leaves selection, then search).
class HomeBack {
  bool Function()? _handler;

  /// Ends one of Home's transient modes, one per press: the selection first,
  /// then an open search (the platform has already used any press that only
  /// hid the keyboard). Returns false when there was nothing to end.
  bool handle() => _handler?.call() ?? false;
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final ValueNotifier<DateTime> _greetingTime = ValueNotifier(
    _readClock(),
  );
  bool _visible = false;
  bool _foreground = true;

  DateTime _readClock() => (widget.now?.call() ?? DateTime.now()).toLocal();
  final ScrollController _controller = ScrollController();

  /// Live text search over the current account's notes (title, body, checklist
  /// items). Runs entirely in memory on the already-decrypted notes, so it never
  /// touches the network and works offline.
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'notes-search');

  /// Whether the search field has taken the title's place.
  final ValueNotifier<bool> _searchOpen = ValueNotifier(false);

  /// Whether the notes have scrolled under the fixed header (title shrinks).
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);

  /// Whether any of the status strip is on screen. The mascot only animates
  /// while it is, so a strip scrolled away costs no frames.
  final ValueNotifier<bool> _stripOnScreen = ValueNotifier(true);

  // Keyboard resizing can move this header between fixed and scrolling layouts.
  // Reparent its existing editor so focus and the platform input connection live on.
  final GlobalKey _headerKey = GlobalKey(debugLabel: 'notes-header');

  /// The strip moves between the two layouts too; keeping its element keeps
  /// the mascot's playback and an open bubble.
  final GlobalKey _stripKey = GlobalKey(debugLabel: 'notes-status-strip');

  late final Widget _body;

  /// Below this height (a phone on its side) the header would leave the grid a strip a
  /// card tall, so it scrolls away with the notes instead of staying put. The
  /// header now includes the 64 dp title row that used to be the shell's app
  /// bar, so the breakpoint rises by that much: the switch happens at the same
  /// screen height as before.
  static const double _shortScreen = 480 + AtomicSpace.x16;
  late final Widget _scrollingBody;

  // Keyboard resizing replaces the grid, but the Home owner must still accept
  // its editor result. Keep the editor's context outside both grid layouts.
  void _editNote(Note note, EditorOrigin? origin) =>
      unawaited(_openEditor(context, note, origin: origin));

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.back?._handler = _handleBack;
    // A screen opened afresh starts with the newest filter, an empty search and nothing selected.
    context.read<NotesBloc>().add(const NotesViewReset());
    _controller.addListener(() {
      final scrolled = _controller.hasClients &&
          _controller.positions.length == 1 &&
          _controller.offset > 0;
      if (scrolled != _scrolled.value) _scrolled.value = scrolled;
    });
    final strip = _StatusSection(
      key: _stripKey,
      time: _greetingTime,
      onScreen: _stripOnScreen,
    );
    Widget header() => _TopBar(
          key: _headerKey,
          actions: widget.headerActions,
          searchController: _searchCtrl,
          searchFocus: _searchFocus,
          searchOpen: _searchOpen,
          scrolled: _scrolled,
          onOpenSearch: _openSearch,
          onCloseSearch: _closeSearch,
        );
    // Built once: the parts below listen to the bloc themselves, so the tree does not have to be
    // rebuilt when the selection starts or ends.
    _body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(),
        Expanded(
          child: _Feed(
            controller: _controller,
            strip: strip,
            pinChips: true,
            onEdit: _editNote,
            onShowAll: _showAll,
          ),
        ),
      ],
    );
    _scrollingBody = NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(child: header()),
      ],
      // No controller of its own: the grid scrolls through the NestedScrollView's.
      body: _Feed(
        strip: strip,
        pinChips: false,
        onEdit: _editNote,
        onShowAll: _showAll,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _visible) {
      _visible = visible;
      // The greeting reads the clock afresh whenever Home is shown again.
      if (visible && _foreground) _greetingTime.value = _readClock();
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.back != widget.back) {
      if (oldWidget.back?._handler == _handleBack) {
        oldWidget.back?._handler = null;
      }
      widget.back?._handler = _handleBack;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _visible) _greetingTime.value = _readClock();
  }

  bool _handleBack() {
    final bloc = context.read<NotesBloc>();
    if (bloc.state.selecting) {
      bloc.add(const NoteSelectionCleared());
      return true;
    }
    if (_searchOpen.value || bloc.state.query.isNotEmpty) {
      _closeSearch();
      return true;
    }
    return false;
  }

  void _openSearch() {
    _searchOpen.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen.value) _searchFocus.requestFocus();
    });
  }

  /// Cancel: clears the query and gives the title its place back.
  void _closeSearch() {
    _searchFocus.unfocus();
    _clearQuery();
    _searchOpen.value = false;
  }

  void _clearQuery() {
    _searchCtrl.clear();
    final bloc = context.read<NotesBloc>();
    if (bloc.state.query.isNotEmpty) bloc.add(const NotesQueryChanged(''));
  }

  /// "Show all notes": back to the All chip with no search. The order stays.
  void _showAll() {
    final bloc = context.read<NotesBloc>();
    if (_searchOpen.value) {
      _closeSearch();
    } else {
      _clearQuery();
    }
    if (bloc.state.tag != null) bloc.add(const NotesTagFilterChanged(null));
    if (bloc.state.type != NoteTypeFilter.all) {
      bloc.add(const NotesTypeFilterChanged(NoteTypeFilter.all));
    }
  }

  bool _stripCheckScheduled = false;

  /// Turns the mascot off while no part of the strip is inside its viewport
  /// and the screen. Scroll notifications can arrive during layout, so the
  /// check runs once after the frame.
  bool _onScroll(Notification notification) {
    if ((notification is ScrollNotification ||
            notification is ScrollMetricsNotification) &&
        !_stripCheckScheduled) {
      _stripCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stripCheckScheduled = false;
        if (mounted) _checkStrip();
      });
    }
    return false;
  }

  void _checkStrip() {
    {
      final box = _stripKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final Object? viewport = RenderAbstractViewport.maybeOf(box);
        var shown = MatrixUtils.transformRect(
                box.getTransformTo(null), Offset.zero & box.size)
            .intersect(Offset.zero & MediaQuery.sizeOf(context));
        if (viewport is RenderBox && viewport.hasSize) {
          shown = shown.intersect(MatrixUtils.transformRect(
              viewport.getTransformTo(null), Offset.zero & viewport.size));
        }
        final onScreen = !shown.isEmpty;
        if (onScreen != _stripOnScreen.value) _stripOnScreen.value = onScreen;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.back?._handler == _handleBack) widget.back?._handler = null;
    _greetingTime.dispose();
    _controller.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchOpen.dispose();
    _scrolled.dispose();
    _stripOnScreen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
          // The canvas follows the selected appearance, and so do the header
          // and the chips painted on it.
          backgroundColor: c.canvas,
          // Home has no app bar above it any more, so it keeps clear of the
          // status bar itself.
          body: SafeArea(
            bottom: false,
            // A tap anywhere that isn't the search field itself drops its
            // focus — otherwise the keyboard and cursor stay put until
            // something else happens to take focus.
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: NotificationListener<Notification>(
                onNotification: _onScroll,
                child: EntranceGroup(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fontSize = AtomicType.bodyMedium.fontSize!;
                      final largeText =
                          MediaQuery.textScalerOf(context).scale(fontSize) >
                              fontSize * 1.6;
                      // A fixed header (title row and search) can crowd out
                      // enlarged note cards. Reuse the scrolling header so
                      // notes remain reachable immediately.
                      return constraints.maxHeight < _shortScreen || largeText
                          ? _scrollingBody
                          : _body;
                    },
                  ),
                ),
              ),
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: selecting ? null : const _NewNoteButton(),
        ),
      ),
    );
  }
}

// ---- header ---------------------------------------------------------------

/// The Home header row (screens spec, Home 1): the "Notes" title, or the
/// search field in its place, then the search button and the actions the
/// shell passes in. At least 64 high. Below 360 dp, or when the title would
/// not fit beside the actions (large text), the title takes its own line
/// above them instead of truncating. In selection mode the selection bar
/// replaces the row.
class _TopBar extends StatelessWidget {
  const _TopBar({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocus,
    required this.searchOpen,
    required this.scrolled,
    required this.onOpenSearch,
    required this.onCloseSearch,
  });

  final List<Widget> actions;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueNotifier<bool> searchOpen;
  final ValueNotifier<bool> scrolled;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;

  static const String title = 'Notes';

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    // No entrance here: the header is the shell's persistent chrome, and a
    // fade from zero would hide its actions from screen readers.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AtomicSpace.x16),
        child: BlocSelector<NotesBloc, NotesState, bool>(
          selector: (state) => state.selecting,
          builder: (context, selecting) => AnimatedSwitcher(
            duration: AtomicMotion.fade(context, AtomicMotion.standard),
            child: selecting
                ? const _Selection(key: ValueKey('home-selection-bar'))
                : ValueListenableBuilder<bool>(
                    key: const ValueKey('home-title-row'),
                    valueListenable: searchOpen,
                    builder: (context, open, _) => _row(context, open),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, bool open) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    // Measured at the largest size, so scrolling (which shrinks the title)
    // never flips the row into the stacked layout.
    final style = AtomicType.display.copyWith(color: c.textPrimary);
    final search = AtomicIconButton(
      icon: AtomicIcons.search,
      tooltip: 'Search notes',
      onPressed: onOpenSearch,
    );
    final shown = [if (!open) search, ...actions];
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: AtomicSpace.x1),
          shown[i],
        ],
      ],
    );
    final slot = _TitleSlot(
      open: open,
      heading: _Heading(scrolled: scrolled),
      field: SearchField(
        controller: searchController,
        focusNode: searchFocus,
        onChanged: (v) => context.read<NotesBloc>().add(NotesQueryChanged(v)),
        onCancel: onCloseSearch,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each action is a 48 dp target, 4 dp apart; the search button
        // counts even while it is hidden, so opening the search never moves
        // the actions to another line.
        final count = actions.length + 1;
        final actionsWidth =
            count * AtomicSpace.x12 + (count - 1) * AtomicSpace.x1;
        final painter = TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width + AtomicSpace.x2 + actionsWidth <=
            constraints.maxWidth;
        painter.dispose();
        if (actions.isNotEmpty && (width < 360 || !fits)) {
          return Column(
            key: const ValueKey('home-top-bar-stacked'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              slot,
              Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
            ],
          );
        }
        return Row(
          key: const ValueKey('home-top-bar'),
          children: [
            Expanded(child: slot),
            const SizedBox(width: AtomicSpace.x2),
            buttons,
          ],
        );
      },
    );
  }
}

/// The "Notes" heading. It shrinks to `titleLarge` once the notes scroll
/// under the fixed header.
class _Heading extends StatelessWidget {
  const _Heading({required this.scrolled});

  final ValueListenable<bool> scrolled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      builder: (context, scrolled, _) => AnimatedDefaultTextStyle(
        duration: AtomicMotion.move(context, AtomicMotion.standard),
        curve: AtomicMotion.standardCurve,
        style: scrolled ? AtomicType.titleLarge : AtomicType.display,
        child: Semantics(
          header: true,
          child: Text(
            _TopBar.title,
            key: const ValueKey('home-title'),
            maxLines: 1,
            style: TextStyle(color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The title's place in the header: the heading, or the search field with a
/// 200 ms shared-axis swap (a fade only under reduced motion). The slot keeps
/// its element when the header moves between layouts, so the field keeps its
/// focus and input connection.
class _TitleSlot extends StatelessWidget {
  const _TitleSlot({
    required this.open,
    required this.heading,
    required this.field,
  });

  final bool open;
  final Widget heading;
  final Widget field;

  static const Duration swap = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final reduced = AtomicMotion.reduced(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedSwitcher(
      duration: AtomicMotion.fade(context, swap),
      switchInCurve: AtomicMotion.standardCurve,
      switchOutCurve: AtomicMotion.exitCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        if (reduced) return faded;
        // The field enters from the end, the title from the start.
        final incomingField = child.key == const ValueKey('home-search-slot');
        final from = (incomingField ? 0.06 : -0.06) * (rtl ? -1 : 1);
        return SlideTransition(
          position: Tween(begin: Offset(from, 0), end: Offset.zero)
              .animate(animation),
          child: faded,
        );
      },
      child: open
          ? KeyedSubtree(key: const ValueKey('home-search-slot'), child: field)
          : KeyedSubtree(
              key: const ValueKey('home-title-slot'),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: heading,
              ),
            ),
    );
  }
}

/// The selection bar in the header's place: cancel, the count, Select all
/// and Delete (to the Recycle Bin, as before).
class _Selection extends StatelessWidget {
  const _Selection({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<NotesBloc>();
    return BlocSelector<NotesBloc, NotesState, int>(
      selector: (state) => state.selected.length,
      builder: (context, count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AtomicSpace.x2),
        child: SelectionBar(
          count: count,
          onCancel: () => bloc.add(const NoteSelectionCleared()),
          onSelectAll: () => bloc.add(const NoteSelectionAllToggled()),
          onDelete: () => bloc.add(const NotesDeleteSelected()),
        ),
      ),
    );
  }
}

// ---- status strip ------------------------------------------------------------

/// The status strip (components spec, Home status strip): the mascot on its
/// stage, the greeting and the counts. It scrolls away with the notes. In
/// selection mode it stays but dims and ignores taps.
class _StatusSection extends StatelessWidget {
  const _StatusSection({
    super.key,
    required this.time,
    required this.onScreen,
  });

  final ValueListenable<DateTime> time;
  final ValueListenable<bool> onScreen;

  static String greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : (now.hour < 17 ? 'Good afternoon' : 'Good evening');

  /// "3 of 30 notes", or "Note limit reached" at the limit.
  static String quota(NotesState state) => state.isAtLimit
      ? 'Note limit reached'
      : '${state.count} of ${state.limit} notes';

  static QuotaLevel level(NotesState state) => state.isAtLimit
      ? QuotaLevel.limit
      : (state.remaining <= 5 ? QuotaLevel.low : QuotaLevel.normal);

  /// Dirty records can be edits or deletions, not only new notes.
  static String? waiting(int pending) => pending <= 0
      ? null
      : (pending == 1
          ? '1 note change waiting to sync'
          : '$pending note changes waiting to sync');

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final mascot = _Mascot(onScreen: onScreen);
    return Entrance(
      index: 1,
      child: Padding(
        key: const ValueKey('notes-welcome-section'),
        padding: EdgeInsets.fromLTRB(margin, AtomicSpace.x2, margin, 0),
        child: _Inert(
          child: ValueListenableBuilder<DateTime>(
            valueListenable: time,
            builder: (context, now, _) => BlocBuilder<NotesBloc, NotesState>(
              buildWhen: (previous, current) =>
                  previous.count != current.count ||
                  previous.limit != current.limit ||
                  previous.pending != current.pending,
              builder: (context, state) => StatusStrip(
                key: const ValueKey('notes-usage'),
                leading: mascot,
                greeting: greeting(now),
                quota: quota(state),
                quotaLevel: level(state),
                detail: waiting(state.pending),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// In selection mode the strip and the chips stay where they are but dim to
/// 40 % and ignore taps (screens spec, Selection mode).
class _Inert extends StatelessWidget {
  const _Inert({required this.child});

  final Widget child;

  static const double dimmed = 0.4;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NotesBloc, NotesState, bool>(
      selector: (state) => state.selecting,
      builder: (context, selecting) => TweenAnimationBuilder<double>(
        tween: Tween(end: selecting ? dimmed : 1),
        duration: AtomicMotion.fade(context, AtomicMotion.quick),
        curve: AtomicMotion.standardCurve,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: IgnorePointer(
          ignoring: selecting,
          child: ExcludeSemantics(excluding: selecting, child: child),
        ),
      ),
    );
  }
}

/// Touching the character changes animation and shows live sync status.
/// ISS-014: an 84 dp stage with 72 dp art, and 76/64 on screens narrower
/// than 360 dp, so the mascot keeps animating (64 dp is its minimum).
class _Mascot extends StatefulWidget {
  const _Mascot({required this.onScreen});

  final ValueListenable<bool> onScreen;

  static const double art = 72;
  static const double narrowArt = 64;

  static double artFor(double width) => width < 360 ? narrowArt : art;

  /// What DevBehindYou says: whether changes wait, and when automatic sync opens.
  /// "Syncing now" only while a sync is running: offline, changes just wait.
  static String syncMessage(
    DateTime? next,
    int pending, {
    bool syncing = false,
    String? error,
  }) {
    final now = DateTime.now();
    final waiting = pending == 1 ? '1 change' : '$pending changes';
    if (syncing) {
      return pending > 0
          ? 'Syncing $waiting now.'
          : 'Checking for cloud changes…';
    }
    if (error != null) return error;
    if (next == null || !next.isAfter(now)) {
      if (pending == 0) return 'No local changes waiting.';
      return pending == 1
          ? '1 change waiting. It syncs by itself when you are online.'
          : '$waiting waiting. They sync by themselves when you are online.';
    }
    final minutes = (next.difference(now).inSeconds / 60).ceil();
    final when = minutes <= 1 ? 'under a minute' : '$minutes min';
    return pending == 0
        ? 'No local changes waiting. Next sync in $when.'
        : '$waiting waiting. Next sync in $when.';
  }

  @override
  State<_Mascot> createState() => _MascotState();
}

class _MascotState extends State<_Mascot> {
  final OverlayPortalController _bubble = OverlayPortalController();
  final LayerLink _anchor = LayerLink();
  Timer? _autoHide;

  void _onTap() {
    _autoHide?.cancel();
    if (_bubble.isShowing) {
      _bubble.hide();
      return;
    }
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
    final art = _Mascot.artFor(MediaQuery.sizeOf(context).width);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final start = rtl ? Alignment.topRight : Alignment.topLeft;
    return CompositedTransformTarget(
      link: _anchor,
      child: OverlayPortal(
        controller: _bubble,
        overlayChildBuilder: (_) => Positioned(
          width: _ChatBubble.maxWidth,
          child: CompositedTransformFollower(
            link: _anchor,
            showWhenUnlinked: false,
            targetAnchor: rtl ? Alignment.bottomRight : Alignment.bottomLeft,
            followerAnchor: start,
            offset: const Offset(0, AtomicSpace.x1),
            child: Align(
              alignment: start,
              child: BlocSelector<NotesBloc, NotesState, String>(
                selector: (state) => _Mascot.syncMessage(
                  state.nextAutoSyncAt,
                  state.pending,
                  syncing: state.syncing,
                  error: state.syncError,
                ),
                builder: (context, message) => _ChatBubble(text: message),
              ),
            ),
          ),
        ),
        child: MascotStage(
          key: const ValueKey('home-mascot-stage'),
          size: art + MascotStage.padding * 2,
          // The strip scrolled away, or Home covered: no frames.
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.onScreen,
            builder: (context, onScreen, child) =>
                TickerMode(enabled: onScreen, child: child!),
            child: ClipRect(
              key: const ValueKey('mascot-character'),
              child: DevBehindYouMascot(
                size: art,
                interactive: true,
                clipRest: const Duration(seconds: 2),
                onAdvance: _onTap,
                semanticActionLabel: 'show sync status and change animation',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chat-style bubble under the mascot (components spec, Mascot stage and
/// bubble): inverse surface, radius 18 with the corner nearest the mascot at
/// 4, at most 260 wide.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text});

  final String text;

  static const double maxWidth = 260;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AtomicMotion.move(context, AtomicMotion.quick),
      curve: AtomicMotion.standardCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          alignment:
              AlignmentDirectional.topStart.resolve(Directionality.of(context)),
          child: child,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x3, vertical: AtomicSpace.x2 + 1),
          decoration: BoxDecoration(
            color: c.inverseSurface,
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(4),
              topEnd: Radius.circular(18),
              bottomStart: Radius.circular(18),
              bottomEnd: Radius.circular(18),
            ).resolve(Directionality.of(context)),
            boxShadow: light
                ? [
                    BoxShadow(
                      color: c.floatingShadow,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            style: AtomicType.bodySmall.copyWith(color: c.onInverse),
          ),
        ),
      ),
    );
  }
}

// ---- chips --------------------------------------------------------------------

/// All, Notes and To-dos with their counts, one chip per tag in use, and the
/// sort button (screens spec, Home 3). Single-select: a tag shows notes of
/// both kinds. The counts are the bloc's, taken before search and filters,
/// so they stay put while typing.
class _ChipRow extends StatelessWidget {
  const _ChipRow();

  /// Tags by count, highest first, then alphabetically. A selected tag that
  /// no live note carries any more stays, at zero, so it can be left.
  static List<MapEntry<String, int>> tags(NotesState state) {
    final entries = state.tagCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final tag = state.tag;
    if (tag != null && !state.tagCounts.containsKey(tag)) {
      entries.insert(0, MapEntry(tag, 0));
    }
    return entries;
  }

  static const _types = [
    (NoteTypeFilter.all, 'All'),
    (NoteTypeFilter.notes, 'Notes'),
    (NoteTypeFilter.todos, 'To-dos'),
  ];

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final bloc = context.read<NotesBloc>();
    return Entrance(
      index: 2,
      child: _Inert(
        child: BlocBuilder<NotesBloc, NotesState>(
          buildWhen: (previous, current) =>
              previous.type != current.type ||
              previous.tag != current.tag ||
              previous.sort != current.sort ||
              !mapEquals(previous.typeCounts, current.typeCounts) ||
              !mapEquals(previous.tagCounts, current.tagCounts),
          builder: (context, state) {
            final chips = <Widget>[
              for (final (type, label) in _types)
                AtomicFilterChip(
                  label: label,
                  count: state.typeCounts[type] ?? 0,
                  selected: state.tag == null && state.type == type,
                  onSelected: () {
                    if (state.tag != null) {
                      bloc.add(const NotesTagFilterChanged(null));
                    }
                    bloc.add(NotesTypeFilterChanged(type));
                  },
                ),
              for (final entry in tags(state))
                AtomicFilterChip.tag(
                  key: ValueKey('home-tag-${entry.key}'),
                  tag: entry.key,
                  count: entry.value,
                  selected: state.tag == entry.key,
                  onSelected: () {
                    if (state.type != NoteTypeFilter.all) {
                      bloc.add(
                          const NotesTypeFilterChanged(NoteTypeFilter.all));
                    }
                    bloc.add(NotesTagFilterChanged(entry.key));
                  },
                ),
              _SortButton(sort: state.sort),
            ];
            return SingleChildScrollView(
              key: const ValueKey('home-chip-row'),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                  horizontal: margin, vertical: AtomicSpace.x2),
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: AtomicSpace.chipGap),
                    chips[i],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The trailing sort button. A small accent dot shows while Oldest is on.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort});

  final NoteSort sort;

  static const Map<NoteSort, String> labels = {
    NoteSort.newest: 'Newest',
    NoteSort.oldest: 'Oldest',
  };

  @override
  Widget build(BuildContext context) {
    final oldest = sort == NoteSort.oldest;
    return AtomicIconButton(
      icon: AtomicIcons.adjustmentsHorizontal,
      tooltip: 'Sort notes',
      semanticsLabel:
          oldest ? 'Sort notes, oldest first' : 'Sort notes, newest first',
      dot: oldest,
      onPressed: () => _showSortSheet(context),
    );
  }

  static void _showSortSheet(BuildContext context) {
    final bloc = context.read<NotesBloc>();
    unawaited(showAtomicSheet<void>(
      context: context,
      builder: (sheet) {
        final c = sheet.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AtomicSpace.x2),
              child: Semantics(
                header: true,
                child: Text('Sort notes',
                    style:
                        AtomicType.titleMedium.copyWith(color: c.textPrimary)),
              ),
            ),
            for (final entry in labels.entries)
              _SortOption(
                label: entry.value,
                selected: bloc.state.sort == entry.key,
                onTap: () {
                  Navigator.of(sheet).pop();
                  if (bloc.state.sort != entry.key) {
                    bloc.add(NotesSortChanged(entry.key));
                  }
                },
              ),
          ],
        );
      },
    ));
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AtomicPressable(
      onTap: onTap,
      selected: selected,
      semanticsLabel: label,
      excludeSemantics: true,
      borderRadius: AtomicRadius.mediumAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AtomicType.bodyLarge.copyWith(color: c.textPrimary)),
            ),
            if (selected)
              Icon(AtomicIcons.check, size: 24, color: c.textPrimary),
          ],
        ),
      ),
    );
  }
}

// ---- the feed -----------------------------------------------------------------

/// The scrolling part: the status strip, the chips (pinned under the header
/// on a normal screen), the featured card and the grid.
class _Feed extends StatelessWidget {
  const _Feed({
    this.controller,
    required this.strip,
    required this.pinChips,
    required this.onEdit,
    required this.onShowAll,
  });

  /// Null inside the short-screen layout, where the NestedScrollView drives the scrolling.
  final ScrollController? controller;
  final Widget strip;
  final bool pinChips;
  final _EditNote onEdit;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const chips = _ChipRow();
    return Scrollbar(
      radius: const Radius.circular(AtomicSpace.x1),
      thickness: 4,
      controller: controller,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: strip),
          if (pinChips)
            PinnedHeaderSliver(
              child: ColoredBox(color: c.canvas, child: chips),
            )
          else
            const SliverToBoxAdapter(child: chips),
          _NotesSliver(onEdit: onEdit, onShowAll: onShowAll),
        ],
      ),
    );
  }
}

int _responsiveColumnCount(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  // Keep preview text usable with large accessibility text or narrow windows.
  if (width < 340 || MediaQuery.textScalerOf(context).scale(15) > 24) return 1;
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 550) return 3;
  return 2;
}

/// Opens a note in the editor, growing from [origin] when it is known.
typedef _EditNote = void Function(Note note, EditorOrigin? origin);

/// The navigators already showing an editor opened from Home. A second tap,
/// or a tap on another card while the editor grows, opens nothing more.
final Expando<Object> _editorOpenOn = Expando('home editor');

/// Opens the editor as a full-screen route from [origin] (motion spec,
/// Editor open). One editor per navigator at a time.
Future<void> _openEditor(BuildContext context, Note note,
    {EditorOrigin? origin, bool fromButton = false}) async {
  final navigator = Navigator.of(context);
  if (_editorOpenOn[navigator] != null) return;
  _editorOpenOn[navigator] = note;
  try {
    await _runEditor(context, navigator, note, origin, fromButton);
  } finally {
    _editorOpenOn[navigator] = null;
  }
}

Future<void> _runEditor(BuildContext context, NavigatorState navigator,
    Note note, EditorOrigin? origin, bool fromButton) async {
  final bloc = context.read<NotesBloc>();
  // visible() returns repository objects. Do not let an editor result mutate
  // one before the caller's acceptance and repository persistence checks.
  final draft = note.copy();
  final owned = bloc.supportsOwnedSave;
  // Who may store this draft: the account and session of the editor opening
  // now, not whoever is signed in when Done is pressed.
  final editorContext = owned ? bloc.captureEditorContext() : null;
  // With an acknowledging store the editor owns the save and closes only
  // after this attempt is stored.
  final c = context.colors;
  final saved = await navigator.push<bool>(EditorRoute<bool>(
    // Movement, so instant under reduced motion (ADR-011).
    duration: AtomicMotion.move(context, AtomicMotion.emphasized),
    canvas: c.canvas,
    originColor: fromButton ? c.accent : c.surface,
    // The new-note button is a circle.
    originRadius: fromButton ? null : AtomicRadius.large,
    origin: origin,
    builder: (_) => NotesCreaterPage(
      note: draft,
      onDelete: bloc.state.notes.any((n) => n.id == note.id)
          ? () => bloc.add(NoteDeleted(note.id))
          : null,
      onSave: owned
          ? (snapshot) =>
              _saveFromEditor(context, bloc, editorContext, snapshot)
          : null,
    ),
  ));
  if (owned) return;
  // A store that cannot acknowledge saves keeps the earlier flow.
  if (saved != true || !context.mounted || bloc.isClosed) return;
  if (draft.isEmpty) {
    const MySnackBar(
      text: "Empty note discarded",
      sec: 1200,
    ).showMySnackBar(context);
    return;
  }
  bloc.add(NoteSaved(draft));
}

/// Stores one accepted editor snapshot for [editorContext] and reports the
/// outcome of exactly this attempt. Nothing is saved for a notes screen or
/// bloc that has gone, or for an editor opened when nobody could write.
Future<NoteSaveResult> _saveFromEditor(BuildContext context, NotesBloc bloc,
    NoteEditorContext? editorContext, Note snapshot) async {
  if (!context.mounted || bloc.isClosed) return const NoteSaveRejected();
  if (editorContext == null) {
    return const NoteSaveRetired(NoteSaveRetirement.contextChanged);
  }
  if (snapshot.isEmpty) {
    const MySnackBar(
      text: "Empty note discarded",
      sec: 1200,
    ).showMySnackBar(context);
    return const NoteSaveSkipped();
  }
  final ack = NoteSaveAck();
  bloc.add(NoteSaved(snapshot, ack: ack, context: editorContext));
  return ack.result;
}

void _newNote(BuildContext context, NoteKind kind) {
  final navigator = Navigator.of(context);
  // Notes and to-dos draw on the same allowance.
  final state = context.read<NotesBloc>().state;
  if (state.isAtLimit) {
    MySnackBar(
      text: "You've reached ${state.limit} notes — delete one to make room",
      sec: 3000,
    ).showMySnackBar(context);
    return;
  }
  // The editor grows from the button that asked for it.
  _openEditor(context, Note.create(kind: kind),
      origin: () => editorOriginRect(context, navigator), fromButton: true);
}

/// The featured card, the masonry grid, or an empty state.
class _NotesSliver extends StatelessWidget {
  const _NotesSliver({required this.onEdit, required this.onShowAll});

  final _EditNote onEdit;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      // Not the sync spinner, the notices or the counts: the cards show none of them.
      buildWhen: (previous, current) =>
          previous.signature != current.signature ||
          !setEquals(previous.selected, current.selected) ||
          previous.type != current.type ||
          previous.tag != current.tag ||
          previous.sort != current.sort ||
          previous.query != current.query,
      builder: (context, state) {
        final width = MediaQuery.sizeOf(context).width;
        final margin = AtomicSpace.screenMargin(width);
        final bottom =
            AtomicSpace.fabClearance + MediaQuery.paddingOf(context).bottom;
        final notes = state.notes;
        if (notes.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Center(
                child: _Empty(narrowed: state.narrowed, onShowAll: onShowAll),
              ),
            ),
          );
        }
        final bloc = context.read<NotesBloc>();
        final featured = notes.first.pinned ? notes.first : null;
        final remaining = featured == null ? notes : notes.skip(1).toList();
        final offset = featured == null ? 0 : 1;
        Widget card(Note note, int index, {bool featured = false}) => Stagger(
              index: index,
              child: _CardOrigin(
                noteId: note.id,
                builder: (origin) => NotesBulder(
                  key: ValueKey(note.id),
                  note: note,
                  projection: bloc.projectionFor(note),
                  featured: featured,
                  selected: state.selected.contains(note.id),
                  selectionMode: state.selecting,
                  onTap: () => state.selecting
                      ? bloc.add(NoteSelectionToggled(note.id))
                      : onEdit(note, origin()),
                  onLongPress: () => bloc.add(NoteSelectionToggled(note.id)),
                  onToggleItem: (i) => bloc.add(NoteItemToggled(note, i)),
                ),
              ),
            );
        return SliverMainAxisGroup(
          slivers: [
            if (featured != null)
              SliverPadding(
                key: const ValueKey('home-featured'),
                padding: EdgeInsets.fromLTRB(margin, AtomicSpace.x2, margin, 0),
                sliver: SliverToBoxAdapter(
                  child: card(featured, 0, featured: true),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  margin, AtomicSpace.gridGap, margin, bottom),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: _responsiveColumnCount(context),
                // The card keeps 4 dp of its own below it; together they
                // make the 12 dp grid gap.
                mainAxisSpacing: AtomicSpace.gridGap - AtomicSpace.x1,
                crossAxisSpacing: AtomicSpace.gridGap,
                childCount: remaining.length,
                itemBuilder: (context, index) =>
                    card(remaining[index], index + offset),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Marks a card as the place its editor grows from and returns to. The
/// origin stays valid only while this element still shows the same note: a
/// card scrolled away, filtered out, deleted or rebuilt for another note
/// gives null, and the editor fades instead.
class _CardOrigin extends StatelessWidget {
  const _CardOrigin({required this.noteId, required this.builder});

  final String noteId;
  final Widget Function(EditorOrigin Function() origin) builder;

  @override
  Widget build(BuildContext context) => builder(() {
        final navigator = Navigator.of(context);
        return () {
          if (!context.mounted) return null;
          final shown = context.widget;
          if (shown is! _CardOrigin || shown.noteId != noteId) return null;
          return editorOriginRect(context, navigator);
        };
      });
}

/// No notes at all, or nothing that matches the chips and the search.
class _Empty extends StatelessWidget {
  const _Empty({required this.narrowed, required this.onShowAll});

  final bool narrowed;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (narrowed) {
      return EmptyState(
        key: const ValueKey('home-empty-no-match'),
        title: 'No notes match',
        body: 'Try another filter or search.',
        actionLabel: 'Show all notes',
        onAction: onShowAll,
      );
    }
    return const EmptyState(
      key: ValueKey('home-empty-first-note'),
      // A still second mascot: only the strip's animates.
      art: MascotStage(
        size: 96,
        child: DevBehindYouMascot(size: 84, secondary: true),
      ),
      title: 'Write your first note',
      body: 'Tap + to start. You can switch to a checklist in the editor.',
    );
  }
}

// ---- new note -----------------------------------------------------------------

/// The new-note button (components spec, Floating action button). At the
/// limit it stays and says why when tapped; the strip reads "Note limit
/// reached".
class _NewNoteButton extends StatelessWidget {
  const _NewNoteButton();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NotesBloc, NotesState, bool>(
      selector: (state) => state.isAtLimit,
      builder: (context, atLimit) => AtomicFab(
        key: const ValueKey('home-new-note'),
        atLimit: atLimit,
        onPressed: () => _newNote(context, NoteKind.text),
      ),
    );
  }
}

/// Kept so existing imports of the skeleton keep resolving.
const Widget kNotesSkeleton = Skeliton();
