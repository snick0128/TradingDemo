import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

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
                Text('No notifications',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 16)),
                SizedBox(height: 8),
                Text('Alerts and order updates will appear here.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return _NotificationCard(
                notification: n,
                onTap: () => store.markNotificationRead(n.id),
              );
            },
          );

    if (!showAppBar) {
      return Scaffold(
        body: Column(
          children: [
            if (notifications.isNotEmpty) _buildActionBar(context, store, unread),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
            'Notifications${unread > 0 ? ' ($unread unread)' : ''}'),
        actions: [
          if (notifications.isNotEmpty) ...[
            TextButton(
              onPressed: () => store.markAllNotificationsRead(),
              child: const Text('Mark all read'),
            ),
            TextButton(
              onPressed: () => store.clearNotifications(),
              child: const Text('Clear all',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ],
      ),
      body: body,
    );
  }

  Widget _buildActionBar(
      BuildContext context, store, int unread) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (unread > 0)
            TextButton(
              onPressed: () => store.markAllNotificationsRead(),
              child: const Text('Mark all read'),
            ),
          TextButton(
            onPressed: () => store.clearNotifications(),
            child: const Text('Clear all',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard(
      {required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM, hh:mm a');
    final isUnread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.primary.withOpacity(0.05)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread
                ? AppColors.primary.withOpacity(0.2)
                : AppColors.border,
          ),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread dot
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isUnread ? AppColors.primary : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: isUnread
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmt.format(notification.timestamp),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
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
