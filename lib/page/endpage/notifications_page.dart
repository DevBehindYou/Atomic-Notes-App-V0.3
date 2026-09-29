// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/web_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// In-app Notification Center. Reads [NotificationsCubit]; the admin
/// (Atomic-Controller) authors the notifications, users only read/act on them.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  NotificationsCubit get service => context.read<NotificationsCubit>();

  @override
  void initState() {
    super.initState();
    service.refresh();
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
      const MySnackBar(
        text: "Couldn't open the link. Check that a browser is installed.",
        sec: 2500,
      ).showMySnackBar(context);
      return;
    }
    const MySnackBar(
      text: 'Update Atomic Notes to open this.',
      sec: 2000,
    ).showMySnackBar(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: "Notifications"),
      body: BlocBuilder<NotificationsCubit, NotificationsState>(
        builder: (context, state) {
          if (state.loading && state.items.isEmpty) {
            return const Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.signal),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.signal,
            onRefresh: service.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
              children: [
                SectionHeader(
                  'INBOX',
                  trailing: state.unreadCount == 0
                      ? null
                      : GestureDetector(
                          onTap: service.markAllRead,
                          behavior: HitTestBehavior.opaque,
                          child: const MonoLabel('MARK ALL READ',
                              color: AppColors.signal, small: true),
                        ),
                ),
                const SizedBox(height: AppSpace.md),
                if (state.error != null)
                  _note('Could not load notifications. Pull down to retry.')
                else if (state.items.isEmpty)
                  _note("You're all caught up. Nothing new right now.")
                else
                  ...state.items.map(_card),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _note(String text) => EditorialModule(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text(text, style: AppType.bodySm),
      );

  Widget _card(AppNotification n) {
    final accent = _priorityColor(n.priority);
    // A tap on the card marks it read; the ✕ and the action button keep their own taps.
    return GestureDetector(
      key: ValueKey('notification-${n.id}'),
      onTap: n.isRead ? null : () => service.markRead(n.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: n.isRead ? AppColors.surfaceLowest : AppColors.surface,
          borderRadius: AppRadius.std,
          border: Border.all(
            color: n.isCritical ? AppColors.error : AppColors.outlineVariant,
            width: n.isCritical ? AppStroke.hairline : AppStroke.rule,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _leading(n, accent),
                const SizedBox(width: AppSpace.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!n.isRead) ...[
                            Container(
                              height: 8,
                              width: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.signal,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                          ],
                          Expanded(
                            child: Text(
                              n.subject,
                              style: AppType.headlineSm,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      MonoLabel(_stamp(n.createdAt), small: true),
                    ],
                  ),
                ),
                // Pinned notifications (admin-set) can't be dismissed: show a
                // pin marker instead of the ✕.
                if (n.dismissible)
                  GestureDetector(
                    onTap: () => service.dismiss(n.id),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: AppSpace.sm),
                      child:
                          Icon(Icons.close, size: 18, color: AppColors.slateData),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpace.sm),
                    child: Icon(Icons.push_pin_outlined,
                        size: 16, color: AppColors.slateData),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(n.description, style: AppType.bodyMd),
            if (n.hasAction) ...[
              const SizedBox(height: AppSpace.md),
              GhostButton(
                label: n.action!,
                icon: Icons.arrow_forward,
                expand: false,
                onTap: () => _onAction(n),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leading(AppNotification n, Color accent) {
    Widget box(Widget child) => Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: AppRadius.std,
            border: Border.all(color: accent, width: AppStroke.rule),
          ),
          child: child,
        );
    if (n.type == 'atomic_energy') {
      return box(const AtomicIcon('atom', size: 22));
    }
    return box(Icon(_iconFor(n.type), size: 20, color: accent));
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'server_down':
      case 'maintenance':
        return Icons.cloud_off;
      case 'server_restored':
        return Icons.cloud_done;
      case 'new_update':
      case 'update_required':
        return Icons.system_update_alt;
      case 'bug_report':
        return Icons.bug_report;
      case 'bug_fixed':
        return Icons.check_circle_outline;
      case 'new_feature':
      case 'upcoming_feature':
        return Icons.rocket_launch;
      case 'security':
        return Icons.shield_outlined;
      case 'account':
        return Icons.person_outline;
      case 'general':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  static Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical':
        return AppColors.error;
      case 'high':
        return AppColors.signal;
      case 'low':
        return AppColors.slateData;
      default:
        return AppColors.ink;
    }
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }
}
