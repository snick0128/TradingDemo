import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _latestFirst = true;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          actions: [
            IconButton(
              tooltip: _latestFirst ? 'Sort oldest first' : 'Sort latest first',
              onPressed: () => setState(() => _latestFirst = !_latestFirst),
              icon: Icon(_latestFirst ? LucideIcons.arrowDownWideNarrow : LucideIcons.arrowUpWideNarrow),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
          ),
        ),
        body: TabBarView(
          children: [
            _OrdersList(status: OrderStatus.pending, latestFirst: _latestFirst),
            _OrdersList(status: OrderStatus.approved, latestFirst: _latestFirst),
            _OrdersList(status: OrderStatus.rejected, latestFirst: _latestFirst),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final OrderStatus status;
  final bool latestFirst;

  const _OrdersList({required this.status, required this.latestFirst});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final filteredOrders = store.orders.where((o) => o.status == status).toList()
      ..sort((a, b) => latestFirst ? b.dateTime.compareTo(a.dateTime) : a.dateTime.compareTo(b.dateTime));

    if (filteredOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No ${status.name} orders', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filteredOrders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = filteredOrders[index];
        final color = order.type == OrderType.buy ? AppColors.success : AppColors.danger;

        return CustomCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusBadge(label: order.type.name, color: color),
                          const SizedBox(width: 8),
                          Text(order.symbol, style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(DateFormat('dd MMM, hh:mm a').format(order.dateTime), style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${order.quantity} Qty', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text('at ₹${order.price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
