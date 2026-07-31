import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class NotificationsCenterScreen extends StatelessWidget {
  final bool showAppBar;
  const NotificationsCenterScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final notifications = store.notifications;
    final unread = store.unreadNotificationCount;

    final body = notifications.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.bellOff, size: 48, color: AppColors.border),
                SizedBox(height: 16),
                Text(
                  'No notifications',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Alerts and order updates will appear here.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        : Container(
            color: const Color(0xFFFAFAFA),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final n = notifications[index];
                return _NotificationCard(
                  notification: n,
                  onTap: () => store.markNotificationRead(n.id),
                );
              },
            ),
          );

    final actions = <Widget>[
      if (unread > 0)
        TextButton(
          onPressed: () => store.markAllNotificationsRead(),
          child: const Text('Mark all read'),
        ),
      if (notifications.isNotEmpty)
        IconButton(
          onPressed: () => store.clearNotifications(),
          icon: const Icon(LucideIcons.trash2, size: 18, color: AppColors.danger),
          tooltip: 'Clear all',
        ),
    ];

    if (!showAppBar) {
      return Scaffold(
        body: Column(
          children: [
            if (notifications.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Notifications'),
        actions: actions,
      ),
      body: body,
    );
  }
}

// ─── Notification category → icon + color ────────────────────────────────────
//
// [AppNotification.relatedAlertType] is the authoritative signal when set by
// the code that created the notification; server-pushed notifications
// (main.dart's Firestore listener) always tag it generically as
// [AlertType.news] though, so those fall through to a title-text heuristic —
// this also covers categories (order status, market hours, IPO, security)
// that don't have a dedicated AlertType at all.

class _NotifVisual {
  final IconData icon;
  final Color color;
  const _NotifVisual(this.icon, this.color);
}

_NotifVisual _visualFor(AppNotification n) {
  switch (n.relatedAlertType) {
    case AlertType.orderExecution:
      return const _NotifVisual(Icons.check_circle, AppColors.success);
    case AlertType.orderRejection:
      return const _NotifVisual(Icons.error, AppColors.danger);
    case AlertType.priceAbove:
    case AlertType.priceBelow:
    case AlertType.percentageMove:
    case AlertType.volumeSpike:
    case AlertType.pnlTarget:
      return const _NotifVisual(LucideIcons.zap, AppColors.warning);
    case AlertType.slTriggered:
    case AlertType.marginWarning:
    case AlertType.autoSquareOffWarning:
      return const _NotifVisual(Icons.warning_amber_rounded, AppColors.danger);
    case AlertType.news:
    case null:
      break;
  }

  final title = n.title.toLowerCase();
  if (title.contains('reject')) return const _NotifVisual(Icons.error, AppColors.danger);
  if (title.contains('execut')) return const _NotifVisual(Icons.check_circle, AppColors.success);
  if (title.contains('square-off') || title.contains('square off')) {
    return const _NotifVisual(Icons.warning_amber_rounded, AppColors.danger);
  }
  if (title.contains('market open') || title.contains('market close')) {
    return const _NotifVisual(LucideIcons.trendingUp, AppColors.primary);
  }
  if (title.contains('ipo')) return const _NotifVisual(LucideIcons.gift, Color(0xFF7B1FA2));
  if (title.contains('security') || title.contains('login')) {
    return const _NotifVisual(LucideIcons.shield, Color(0xFF546E7A));
  }
  if (title.contains('deposit') || title.contains('withdraw') || title.contains('fund')) {
    return const _NotifVisual(LucideIcons.wallet, AppColors.primary);
  }
  if (title.contains('alert')) return const _NotifVisual(LucideIcons.zap, AppColors.warning);
  return const _NotifVisual(LucideIcons.bell, AppColors.textSecondary);
}

String _relativeTimestamp(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(that).inDays;

  if (diffDays == 0) return DateFormat('h:mm a').format(t);
  if (diffDays == 1) return 'Yesterday';
  return DateFormat('dd MMM').format(t);
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    final visual = _visualFor(notification);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: visual.color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(visual.icon, size: 18, color: visual.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0D0D0D)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF757575)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _relativeTimestamp(notification.timestamp),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
            if (isUnread)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
