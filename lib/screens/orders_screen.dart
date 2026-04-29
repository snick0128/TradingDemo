import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_drawer.dart';
import '../widgets/shared_widgets.dart';
import 'basket_orders_screen.dart';
import 'gtt_orders_screen.dart';
import 'market_watch_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Order Book'),
            Tab(text: 'Trade Book'),
            Tab(text: 'Open'),
            Tab(text: 'GTT'),
            Tab(text: 'Basket'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OrderBookTab(),
          _TradeBookTab(),
          _OpenOrdersTab(),
          GttOrdersScreen(),
          BasketOrdersScreen(),
        ],
      ),
    );
  }
}

// ─── Order Book Tab (all orders with cancel/modify) ───────────────────────────

class _OrderBookTab extends StatefulWidget {
  const _OrderBookTab();

  @override
  State<_OrderBookTab> createState() => _OrderBookTabState();
}

class _OrderBookTabState extends State<_OrderBookTab> {
  OrderStatus? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final allOrders = store.orders.toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final today = allOrders.where((o) {
      final now = DateTime.now();
      return o.dateTime.year == now.year &&
          o.dateTime.month == now.month &&
          o.dateTime.day == now.day;
    }).toList();

    final pendingCount =
        allOrders.where((o) => o.status == OrderStatus.pending).length;
    final executedCount = allOrders
        .where((o) =>
            o.status == OrderStatus.executed ||
            o.status == OrderStatus.approved)
        .length;

    final filtered = _filter == null
        ? allOrders
        : allOrders.where((o) => o.status == _filter).toList();

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceElevated,
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                'Today: ${today.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Pending: $pendingCount',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
              Text(
                'Executed: $executedCount',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', null),
                const SizedBox(width: 8),
                _filterChip('Pending', OrderStatus.pending),
                const SizedBox(width: 8),
                _filterChip('Executed', OrderStatus.executed),
                const SizedBox(width: 8),
                _filterChip('Rejected', OrderStatus.rejected),
                const SizedBox(width: 8),
                _filterChip('Cancelled', OrderStatus.cancelled),
              ],
            ),
          ),
        ),
        // Orders list
        Expanded(
          child: filtered.isEmpty
              ? _emptyOrdersState(context)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _OrderCard(order: filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, OrderStatus? status) {
    final selected = _filter == status;
    Color chipColor;
    if (status == OrderStatus.pending) {
      chipColor = AppColors.warning;
    } else if (status == OrderStatus.executed ||
        status == OrderStatus.approved) {
      chipColor = AppColors.success;
    } else if (status == OrderStatus.rejected ||
        status == OrderStatus.cancelled) {
      chipColor = AppColors.danger;
    } else {
      chipColor = AppColors.primary;
    }

    return GestureDetector(
      onTap: () => setState(() => _filter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withValues(alpha: 0.15)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? chipColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? chipColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _emptyOrdersState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.inbox, size: 56, color: AppColors.border),
          const SizedBox(height: 16),
          const Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Place your first trade to see orders here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
            ),
            child: const Text('Start Trading'),
          ),
        ],
      ),
    );
  }
}

// ─── Order Card ───────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Order order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final isPending = order.status == OrderStatus.pending;

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
      case OrderStatus.partiallyExecuted:
      case OrderStatus.pending:
        statusColor = AppColors.warning;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.softShadow,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Left color bar
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: sideColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppColors.cardRadius),
                bottomLeft: Radius.circular(AppColors.cardRadius),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          order.symbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: order.variety.name,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      StatusBadge(
                        label: order.status.name,
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.product.name.toUpperCase()} • ${order.quantity} qty @ ₹${order.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  DateFormat('HH:mm').format(order.dateTime),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () =>
                        TradingScope.of(context).cancelOrder(order.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trade Book Tab (executed orders only) ────────────────────────────────────

class _TradeBookTab extends StatelessWidget {
  const _TradeBookTab();

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final executed =
        store.orders
            .where(
              (o) =>
                  o.status == OrderStatus.approved ||
                  o.status == OrderStatus.executed,
            )
            .toList()
          ..sort(
            (a, b) => (b.executedAt ?? b.dateTime).compareTo(
              a.executedAt ?? a.dateTime,
            ),
          );

    if (executed.isEmpty) {
      return _emptyState('No executed trades');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 900
            ? MediaQuery.of(context).size.width
            : 900,
        child: Column(
          children: [
            _TradeBookHeader(),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: executed.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _TradeBookRow(order: executed[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TradeBookHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: AppColors.surfaceAlt.withValues(alpha: 0.2),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Execution Time', style: _hStyle)),
          Expanded(flex: 1, child: Text('Type', style: _hStyle)),
          Expanded(flex: 3, child: Text('Instrument', style: _hStyle)),
          Expanded(flex: 2, child: Text('Quantity', style: _hStyle)),
          Expanded(
            flex: 2,
            child: Text(
              'Avg. Price',
              style: _hStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: AppColors.textSecondary,
  );
}

class _TradeBookRow extends StatelessWidget {
  final Order order;
  const _TradeBookRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final typeColor = isBuy ? AppColors.success : AppColors.danger;
    final execTime = order.executedAt ?? order.dateTime;
    final avgPrice = order.executedPrice ?? order.price;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd MMM HH:mm:ss').format(execTime),
              style: AppTheme.tabular(
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  order.type.name.toUpperCase(),
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.symbol,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'NSE',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${order.executedQuantity ?? order.quantity}',
              style: AppTheme.tabular(const TextStyle(fontSize: 13)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${avgPrice.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: AppTheme.tabular(
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Open Orders Tab (pending only) ──────────────────────────────────────────

class _OpenOrdersTab extends StatelessWidget {
  const _OpenOrdersTab();

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final pending =
        store.orders.where((o) => o.status == OrderStatus.pending).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (pending.isEmpty) {
      return _emptyState('No open orders');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _PendingOrderCard(order: pending[index]),
    );
  }
}

class _PendingOrderCard extends StatelessWidget {
  final Order order;
  const _PendingOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final color = isBuy ? AppColors.success : AppColors.danger;

    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        order.symbol,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      label: order.variety.name,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    StatusBadge(label: 'PENDING', color: AppColors.warning),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.product.name.toUpperCase()} • ${order.quantity} qty @ ₹${order.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm').format(order.dateTime),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16, color: AppColors.danger),
            onPressed: () => TradingScope.of(context).cancelOrder(order.id),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _emptyState(String message) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(LucideIcons.inbox, size: 48, color: AppColors.border),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}
