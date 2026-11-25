// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/utility/web_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// In-app Notification Center (screens spec, Notifications). Reads
/// [NotificationsCubit]; the admin (Atomic-Controller) authors the
/// notifications, users only read/act on them.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.now});

  /// The clock used for relative times; injectable for tests.
  final DateTime Function()? now;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const String title = 'Notifications';

  NotificationsCubit get service => context.read<NotificationsCubit>();

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    service.refresh();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<void> _onAction(AppNotification n) async {
    service.markRead(n.id);
    final url = n.actionUrl ?? '';
    // In-app destinations, then https pages, which open in the browser.
    if (url == '/energypage' || url == '/atomic-energy' || url == '/energy') {
      Navigator.pushNamed(context, '/energypage');
      return;
    }
    if (WebLinks.isWeb(url)) {
      final opened = await WebLinks.open(url);
      if (!mounted || opened) return;
      const AtomicSnackBar(
        text: "Couldn't open the link. Check that a browser is installed.",
        millis: 2500,
        error: true,
      ).show(context);
      return;
    }
    const AtomicSnackBar(
      text: 'Update Atomic Notes to open this.',
      millis: 2000,
    ).show(context);
  }

  static const String markAllLabel = 'Mark all read';

  /// Whether "Mark all read" fits in the header beside the back button. When
  /// it does not (a narrow screen or large text), it moves under the page
  /// title instead of overflowing or truncating.
  bool _markAllFitsHeader(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final painter = TextPainter(
      text: const TextSpan(text: markAllLabel, style: AtomicType.labelLarge),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final button = painter.width + 2 * AtomicSpace.x4;
    painter.dispose();
    // Header padding, the 48 dp back button and room for the collapsed title.
    final room = width - 2 * AtomicSpace.x2 - AtomicSpace.x12 - AtomicSpace.x16;
    return button <= room;
  }

  Widget _markAllButton() => AtomicButton(
        key: const ValueKey('notifications-mark-all-read'),
        label: markAllLabel,
        variant: AtomicButtonVariant.text,
        size: AtomicButtonSize.compact,
        onPressed: service.markAllRead,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inHeader = _markAllFitsHeader(context);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<NotificationsCubit, NotificationsState>(
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _titleAway,
                builder: (context, away, _) => AtomicPageHeader(
                  title: title,
                  showTitle: away,
                  actions: [
                    // Only when something is unread, as before.
                    if (state.unreadCount > 0 && inHeader) _markAllButton(),
                  ],
                ),
              ),
              Expanded(child: _body(context, state, markAllBelow: !inHeader)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NotificationsState state,
      {required bool markAllBelow}) {
    final c = context.colors;
    if (state.loading && state.items.isEmpty) {
      return Center(
        child: ProgressRing(
          semanticsLabel: 'Loading notifications',
          stationary: AtomicMotion.reduced(context),
        ),
      );
    }
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.surface,
      onRefresh: service.refresh,
      child: ListView(
        controller: _scroll,
        // Pull to refresh works on the empty and error states too.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(margin, 0, margin, AtomicSpace.x8),
        children: [
          const PageTitle(title),
          if (markAllBelow && state.unreadCount > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _markAllButton(),
            ),
          const SizedBox(height: AtomicSpace.x4),
          if (state.error != null)
            const Padding(
              padding: EdgeInsets.only(top: AtomicSpace.x8),
              child: EmptyState(
                key: ValueKey('notifications-error'),
                title: 'Could not load notifications',
                body: 'Pull down to retry.',
              ),
            )
          else if (state.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AtomicSpace.x8),
              child: EmptyState(
                key: ValueKey('notifications-empty'),
                title: "You're all caught up",
                body: 'Nothing new right now.',
              ),
            )
          else
            for (final n in state.items) ...[
              _NotificationCard(
                key: ValueKey('notification-${n.id}'),
                notification: n,
                now: widget.now?.call() ?? DateTime.now(),
                onOpen: n.isRead ? null : () => service.markRead(n.id),
                onDismiss: n.dismissible ? () => service.dismiss(n.id) : null,
                onAction: n.hasAction ? () => _onAction(n) : null,
              ),
              const SizedBox(height: AtomicSpace.x3),
            ],
        ],
      ),
    );
  }
}

/// One notification (screens spec, Notifications): an unread accent dot,
/// title, body, relative time and an optional action. A tap on the card marks
/// it read; the dismiss button and the action keep their own taps. A pinned
/// notification (admin-set) shows a pin instead of the dismiss button, and a
/// critical one keeps its alert mark.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    super.key,
    required this.notification,
    required this.now,
    required this.onOpen,
    required this.onDismiss,
    required this.onAction,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = notification;
    final when = relativeTime(n.createdAt, now);
    final unread = !n.isRead;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unread)
          Padding(
            padding: const EdgeInsets.only(top: 7, right: AtomicSpace.x2),
            child: Container(
              key: const ValueKey('notification-unread-dot'),
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: c.accent, shape: BoxShape.circle),
            ),
          ),
        if (n.isCritical)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AtomicSpace.x2),
            child:
                Icon(AtomicIcons.alertTriangle, size: 20, color: c.dangerText),
          ),
        Expanded(
          child: Text(
            n.subject,
            style: AtomicType.titleMedium.copyWith(color: c.textPrimary),
          ),
        ),
        if (onDismiss != null)
          AtomicIconButton(
            icon: AtomicIcons.x,
            tooltip: 'Dismiss',
            onCard: true,
            onPressed: onDismiss,
          )
        else
          Padding(
            padding: const EdgeInsets.all(AtomicSpace.x3),
            child: Tooltip(
              message: 'Pinned',
              child: Icon(AtomicIcons.pin,
                  key: const ValueKey('notification-pinned'),
                  size: 20,
                  color: c.textSecondary,
                  semanticLabel: 'Pinned'),
            ),
          ),
      ],
    );
    final card = AtomicCard(
      color: unread ? c.surfaceRaised : c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: AtomicSpace.x1),
          Text(when,
              style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          const SizedBox(height: AtomicSpace.x2),
          Text(n.description,
              style: AtomicType.bodyMedium.copyWith(color: c.textPrimary)),
          if (onAction != null) ...[
            const SizedBox(height: AtomicSpace.x3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AtomicButton(
                label: n.action!,
                icon: AtomicIcons.arrowRight,
                variant: AtomicButtonVariant.secondary,
                size: AtomicButtonSize.compact,
                onCard: true,
                onPressed: onAction,
              ),
            ),
          ],
        ],
      ),
    );
    final label = [
      if (unread) 'Unread',
      if (n.isCritical) 'Critical',
      n.subject,
      when,
    ].join(', ');
    // The card's own tap marks it read; read cards ignore it. The dismiss and
    // action buttons stay separate nodes for screen readers.
    return AtomicPressable(
      onTap: onOpen,
      semanticsLabel: label,
      button: onOpen != null,
      pressScale: onOpen == null ? 1 : AtomicMotion.pressScale,
      borderRadius: AtomicRadius.largeAll,
      child: card,
    );
  }
}

/// A short relative time: "Just now", "5 min ago", "3 h ago", "Yesterday",
/// "4 days ago", then the date ("2026-09-27"). A time in the future (clock
/// skew) reads as "Just now".
String relativeTime(DateTime at, DateTime now) {
  final local = at.toLocal();
  final diff = now.toLocal().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 2) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  String p(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)}';
}
