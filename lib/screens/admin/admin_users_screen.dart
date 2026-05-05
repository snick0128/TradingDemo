import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import 'admin_ui.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  bool? _isActiveFilter;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = admin.users.where((user) {
      final q = _query.toLowerCase();
      final matchQuery =
          q.isEmpty ||
          user.name.toLowerCase().contains(q) ||
          user.email.toLowerCase().contains(q) ||
          user.clientId.toLowerCase().contains(q);
      final matchStatus =
          _isActiveFilter == null || user.isActive == _isActiveFilter;
      return matchQuery && matchStatus;
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'User Management',
            subtitle: '${users.length} user(s) across the platform.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, email, client ID',
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _filterChip('All', null),
                    _filterChip('Active', true),
                    _filterChip('Disabled', false),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('No users found.'))
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _userRow(context, users[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool? value) {
    final selected = _isActiveFilter == value;
    return AdminFilterChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _isActiveFilter = value),
    );
  }

  Widget _userRow(BuildContext context, User user) {
    final admin = AdminScope.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text(
          user.name.isEmpty ? 'U' : user.name[0].toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${user.email}\n${user.clientId} • Bal ₹${NumberFormat('#,##,##0').format(user.balance)} • Margin ₹${NumberFormat('#,##,##0').format(user.marginLimit)}',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: user.isActive,
            onChanged: (enabled) {
              if (enabled) {
                admin.enableUser(user.id);
              } else {
                admin.disableUser(user.id);
              }
            },
            activeColor: AppColors.success,
          ),
          IconButton(
            onPressed: () => _openUserActions(context, user),
            icon: const Icon(LucideIcons.moreVertical, size: 18),
          ),
        ],
      ),
    );
  }

  void _openUserActions(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.wallet),
              title: const Text('Adjust Balance'),
              onTap: () {
                Navigator.pop(ctx);
                _showAmountDialog(
                  context,
                  user,
                  title: 'Adjust Balance',
                  onSubmit: (amount) =>
                      AdminScope.of(context).adjustUserBalance(user.id, amount),
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.gauge),
              title: const Text('Adjust Margin Limit'),
              onTap: () {
                Navigator.pop(ctx);
                _showAmountDialog(
                  context,
                  user,
                  title: 'Adjust Margin Limit',
                  onSubmit: (amount) =>
                      AdminScope.of(context).adjustUserMargin(user.id, amount),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAmountDialog(
    BuildContext context,
    User user, {
    required String title,
    required void Function(double amount) onSubmit,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title • ${user.clientId}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (+ add / - deduct)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(controller.text.trim()) ?? 0;
              if (amount == 0) return;
              try {
                onSubmit(amount);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Adjustment of ₹$amount applied successfully.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to apply adjustment: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
