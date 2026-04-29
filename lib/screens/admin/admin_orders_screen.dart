import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';
import 'admin_ui.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  OrderStatus? _statusFilter;
  String _query = '';
  _OrderSegregation _segregation = _OrderSegregation.stockWise;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final orders = admin.masterOrderBook.where((order) {
      final q = _query.trim().toLowerCase();
      final matchQuery =
          q.isEmpty ||
          order.symbol.toLowerCase().contains(q) ||
          order.userClientId.toLowerCase().contains(q);
      final matchStatus =
          _statusFilter == null || order.status == _statusFilter;
      return matchQuery && matchStatus;
    }).toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Master Order Book',
            subtitle: '${orders.length} order(s) visible after filters.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Filter by user or symbol',
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('All', null),
                    _chip('Pending', OrderStatus.pending),
                    _chip('Approved', OrderStatus.approved),
                    _chip('Rejected', OrderStatus.rejected),
                    _chip('Executed', OrderStatus.executed),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _segregationChip(
                      label: 'Stock-wise',
                      value: _OrderSegregation.stockWise,
                    ),
                    const SizedBox(width: 8),
                    _segregationChip(
                      label: 'User-wise',
                      value: _OrderSegregation.userWise,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: orders.isEmpty
                ? const Center(child: Text('No orders found.'))
                : AdminPanel(
                    child: _buildSegregatedList(context, orders),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, OrderStatus? status) {
    final selected = _statusFilter == status;
    return AdminFilterChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _statusFilter = status),
    );
  }

  Widget _segregationChip({
    required String label,
    required _OrderSegregation value,
  }) {
    final selected = _segregation == value;
    return AdminFilterChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _segregation = value),
    );
  }

  Widget _buildSegregatedList(
    BuildContext context,
    List<AdminOrderRecord> orders,
  ) {
    final Map<String, List<AdminOrderRecord>> grouped = {};

    for (final order in orders) {
      final key = _segregation == _OrderSegregation.stockWise
          ? order.symbol
          : order.userClientId;
      grouped.putIfAbsent(key, () => <AdminOrderRecord>[]).add(order);
    }

    final groupKeys = grouped.keys.toList()..sort();
    final children = <Widget>[];

    for (final key in groupKeys) {
      final groupOrders = grouped[key]!
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      final pendingCount = groupOrders
          .where((o) => o.status == OrderStatus.pending)
          .length;
      final titlePrefix = _segregation == _OrderSegregation.stockWise
          ? 'Stock'
          : 'User';

      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
            color: AppColors.surfaceAlt,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$titlePrefix: $key',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${groupOrders.length} order(s)',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$pendingCount pending',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      for (final order in groupOrders) {
        children.add(_row(context, order));
        children.add(const Divider(height: 1));
      }
    }

    return ListView(
      children: children,
    );
  }

  Widget _row(BuildContext context, AdminOrderRecord order) {
    final isPending = order.status == OrderStatus.pending;
    final sideColor = order.type == OrderType.buy
        ? AppColors.success
        : AppColors.danger;

    Color statusColor;
    switch (order.status) {
      case OrderStatus.approved:
      case OrderStatus.executed:
        statusColor = AppColors.success;
        break;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        statusColor = AppColors.danger;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd MMM HH:mm').format(order.dateTime),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.userClientId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  order.type == OrderType.buy ? 'BUY' : 'SELL',
                  style: TextStyle(
                    color: sideColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(order.symbol, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${order.quantity} @ ₹${order.price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.status.name.toUpperCase(),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isPending) ...[
            const SizedBox(width: 8),
            _actionBtn(
              context,
              'Approve',
              AppColors.success,
              () async {
                await AdminScope.of(context).approveOrder(order.id);
              },
            ),
            const SizedBox(width: 6),
            _actionBtn(
              context,
              'Reject',
              AppColors.danger,
              () async {
                await AdminScope.of(
                  context,
                ).rejectOrder(order.id, reason: 'Rejected by admin');
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context,
    String label,
    Color color,
    Future<void> Function() onTap,
  ) {
    return InkWell(
      onTap: () async {
        try {
          await onTap();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label successful')),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label failed: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

enum _OrderSegregation { stockWise, userWise }
