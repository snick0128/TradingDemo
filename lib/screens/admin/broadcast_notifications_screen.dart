import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../config/backend_config.dart';
import '../../data/services/backend_api_service.dart';
import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class BroadcastNotificationsScreen extends StatefulWidget {
  const BroadcastNotificationsScreen({super.key});
  @override
  State<BroadcastNotificationsScreen> createState() =>
      _BroadcastNotificationsScreenState();
}

class _BroadcastNotificationsScreenState
    extends State<BroadcastNotificationsScreen> {
  final _titleController   = TextEditingController();
  final _messageController = TextEditingController();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  String _type    = 'Info';
  bool   _sending = false;
  String? _lastError;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title   = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Title and message are required.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }

    setState(() { _sending = true; _lastError = null; });

    // ── 1. Write to in-app AdminStore (local notification history) ───────────
    final admin = AdminScope.of(context);
    admin.broadcastNotification(
      title: title,
      message: message,
      type: _mapType(_type),
    );

    // ── 2. Send in-app notification to all users via backend ──────────────────
    try {
      await _api.broadcastNotification(
        title: title,
        message: message,
        data: {'type': _type.toLowerCase()},
      );

      _titleController.clear();
      _messageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notification sent to all users.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      final err = e.toString().replaceFirst('BackendException: ', '');
      setState(() => _lastError = err);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Delivery failed: $err'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = AdminScope.of(context).broadcasts;

    return AdminPage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeader(
              title: 'Broadcast Notifications',
              subtitle: 'Send FCM push notification to all users instantly.',
            ),
            const SizedBox(height: 20),

            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compose Push Notification',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sends an in-app notification to every user. Appears in their notification center immediately.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Notification Type'),
                    items: const [
                      DropdownMenuItem(value: 'Info',        child: Text('ℹ️  Info')),
                      DropdownMenuItem(value: 'Warning',     child: Text('⚠️  Warning')),
                      DropdownMenuItem(value: 'Alert',       child: Text('🚨  Alert')),
                      DropdownMenuItem(value: 'Maintenance', child: Text('🔧  Maintenance')),
                    ],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Market Closure Notice',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      hintText: 'Write your broadcast message here...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, size: 14, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastError!,
                              style: const TextStyle(fontSize: 12, color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(LucideIcons.send, size: 16),
                      label: Text(_sending ? 'Sending…' : 'Send to All Users'),
                    ),
                  ),
                ],
              ),
            ),

            if (sent.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Sent History', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: sent.take(10).toList().asMap().entries.map((e) {
                    final n = e.value;
                    return Column(
                      children: [
                        if (e.key > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(LucideIcons.bellRing, color: AppColors.primary, size: 20),
                          title: Text(n.title,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(
                            '${_labelForType(n.relatedAlertType)} • ${n.timestamp.toString().substring(0, 16)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: StatusBadge(label: 'Sent', color: AppColors.success),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  AlertType _mapType(String type) {
    switch (type) {
      case 'Warning':     return AlertType.marginWarning;
      case 'Alert':       return AlertType.news;
      case 'Maintenance': return AlertType.autoSquareOffWarning;
      default:            return AlertType.news;
    }
  }

  String _labelForType(AlertType? type) {
    if (type == AlertType.marginWarning)       return 'Warning';
    if (type == AlertType.autoSquareOffWarning) return 'Maintenance';
    return 'Info';
  }
}
