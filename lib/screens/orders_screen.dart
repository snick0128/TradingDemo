import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
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
        title: const Text(
          'Orders',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1565C0),
          unselectedLabelColor: const Color(0xFF9E9E9E),
          indicatorColor: const Color(0xFF1565C0),
          indicatorWeight: 2,
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

    final pendingCount = allOrders
        .where((o) => o.status == OrderStatus.pending)
        .length;
    final executedCount = allOrders
        .where(
          (o) =>
              o.status == OrderStatus.executed ||
              o.status == OrderStatus.approved,
        )
        .length;

    final filtered = _filter == null
        ? allOrders
        : allOrders.where((o) => o.status == _filter).toList();

    return Column(
      children: [
        // ── Summary strip ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              _summaryItem(
                'Today',
                today.length.toString(),
                const Color(0xFF757575),
              ),
              const SizedBox(width: 24),
              _summaryItem(
                'Pending',
                pendingCount.toString(),
                const Color(0xFF757575),
              ),
              const SizedBox(width: 24),
              _summaryItem(
                'Executed',
                executedCount.toString(),
                const Color(0xFF00C853),
              ),
            ],
          ),
        ),
        // ── Filter chips ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
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
        // ── Orders list ────────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? _emptyOrdersState(context)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    final prev = index > 0 ? filtered[index - 1] : null;
                    final showDateHeader =
                        prev == null ||
                        !_sameDay(prev.dateTime, order.dateTime);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDateHeader) _DateGroupLabel(order.dateTime),
                        _OrderCard(order: order),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _summaryItem(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, OrderStatus? status) {
    final selected = _filter == status;
    return GestureDetector(
      onTap: () => setState(() => _filter = status),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF1565C0) : const Color(0xFFE0E0E0),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF9E9E9E),
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

// ─── Date Group Label ─────────────────────────────────────────────────────────

class _DateGroupLabel extends StatelessWidget {
  final DateTime date;
  const _DateGroupLabel(this.date);

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('dd MMM yyyy').format(date).toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF9E9E9E),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Order Card ───────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Order order;
  const _OrderCard({required this.order});

  Future<void> _cancelOrder(BuildContext context, String orderId) async {
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope != null) {
      try {
        await appScope.tradingService.cancelOrder(orderId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order cancelled')));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cancellation failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    TradingScope.of(context).cancelOrder(orderId);
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final isPending = order.status == OrderStatus.pending;
    final isExecuted = order.status == OrderStatus.executed ||
        order.status == OrderStatus.approved;

    Color statusBg, statusFg;
    String statusLabel;
    switch (order.status) {
      case OrderStatus.approved:
      case OrderStatus.executed:
        statusBg = const Color(0xFFE8F5E9);
        statusFg = const Color(0xFF2E7D32);
        statusLabel = 'Executed';
        break;
      case OrderStatus.rejected:
        statusBg = const Color(0xFFFFEBEE);
        statusFg = const Color(0xFFC62828);
        statusLabel = 'Rejected';
        break;
      case OrderStatus.cancelled:
        statusBg = const Color(0xFFF5F5F5);
        statusFg = const Color(0xFF616161);
        statusLabel = 'Cancelled';
        break;
      case OrderStatus.partiallyExecuted:
        statusBg = const Color(0xFFFFF8E1);
        statusFg = const Color(0xFFF57F17);
        statusLabel = 'Partial';
        break;
      case OrderStatus.pending:
        statusBg = const Color(0xFFFFF8E1);
        statusFg = const Color(0xFFF57F17);
        statusLabel = 'Pending';
    }

    final pnl = order.pnl;
    final hasPnl = pnl != null && pnl != 0;
    final pnlPositive = (pnl ?? 0) >= 0;

    return IntrinsicHeight(
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: sideColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Symbol + cancel/time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              order.symbol,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0D0D0D),
                              ),
                            ),
                            if (order.isAutoSquareOff) ...[
                              const SizedBox(width: 6),
                              _chip(
                                'Auto SQ-OFF',
                                const Color(0xFFFFF3E0),
                                const Color(0xFFE65100),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            if (isPending)
                              GestureDetector(
                                onTap: () => _cancelOrder(context, order.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFD50000),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFD50000),
                                    ),
                                  ),
                                ),
                              ),
                            if (isPending) const SizedBox(width: 8),
                            Text(
                              DateFormat('HH:mm').format(order.dateTime),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF757575),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Row 2: Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(
                          order.product.name.toUpperCase(),
                          const Color(0xFFE3F2FD),
                          const Color(0xFF1565C0),
                        ),
                        _chip(
                          order.variety.name.toUpperCase(),
                          const Color(0xFFF3E5F5),
                          const Color(0xFF6A1B9A),
                        ),
                        if (order.exchange?.isNotEmpty == true)
                          _chip(
                            order.exchange!,
                            const Color(0xFFE8F5E9),
                            const Color(0xFF2E7D32),
                          ),
                        _chip(statusLabel, statusBg, statusFg),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Row 3: Side + qty + price(s)
                    Row(
                      children: [
                        Text(
                          isBuy ? 'Buy' : 'Sell',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: sideColor,
                          ),
                        ),
                        Text(
                          ' · ${order.executedQuantity ?? order.quantity} qty',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                        if (isExecuted) ...[
                          Text(
                            '  ·  ₹${order.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward,
                            size: 11,
                            color: Color(0xFF9E9E9E),
                          ),
                          Text(
                            ' ₹${(order.executedPrice ?? order.price).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0D0D0D),
                            ),
                          ),
                        ] else
                          Text(
                            '  ·  ₹${order.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                            ),
                          ),
                      ],
                    ),
                    // Row 4: Margin / leverage / P&L (only when data is present)
                    if (order.marginUsed != null ||
                        order.leverageApplied != null ||
                        (hasPnl && isExecuted) ||
                        order.chargesApplied != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          if (order.marginUsed != null &&
                              order.marginUsed! > 0)
                            _metaItem(
                              'Margin',
                              '₹${order.marginUsed!.toStringAsFixed(0)}',
                              const Color(0xFF757575),
                            ),
                          if (order.leverageApplied != null &&
                              order.leverageApplied! > 1)
                            _metaItem(
                              'Leverage',
                              '${order.leverageApplied!.toStringAsFixed(0)}x',
                              const Color(0xFF757575),
                            ),
                          if (order.chargesApplied != null &&
                              order.chargesApplied! > 0)
                            _metaItem(
                              'Charges',
                              '₹${order.chargesApplied!.toStringAsFixed(2)}',
                              const Color(0xFF757575),
                            ),
                          if (hasPnl && isExecuted)
                            _metaItem(
                              'P&L',
                              '${pnlPositive ? '+' : ''}₹${pnl!.toStringAsFixed(2)}',
                              pnlPositive
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: text,
        ),
      ),
    );
  }

  Widget _metaItem(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ─── Trade Book Tab (executed orders — card rows) ─────────────────────────────

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

    if (executed.isEmpty) return _emptyState('No executed trades');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: executed.length,
      itemBuilder: (context, index) {
        final order = executed[index];
        final prev = index > 0 ? executed[index - 1] : null;
        final showDateHeader =
            prev == null ||
            !_sameDay(
              prev.executedAt ?? prev.dateTime,
              order.executedAt ?? order.dateTime,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateHeader)
              _DateGroupLabel(order.executedAt ?? order.dateTime),
            _TradeCard(order: order),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _TradeCard extends StatelessWidget {
  final Order order;
  const _TradeCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final sideBg = isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final execTime = order.executedAt ?? order.dateTime;
    final avgPrice = order.executedPrice ?? order.price;
    final pnl = order.pnl;
    final hasPnl = pnl != null && pnl != 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('HH:mm:ss').format(execTime),
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
              if (order.isAutoSquareOff)
                const Text(
                  'Auto SQ',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // BUY/SELL chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sideBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isBuy ? 'BUY' : 'SELL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: sideColor,
              ),
            ),
          ),
          if (order.exchange?.isNotEmpty == true) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                order.exchange!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
            ),
          ],
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.symbol,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D0D0D),
                    ),
                  ),
                  if (order.product != ProductType.mis) ...[
                    const SizedBox(width: 4),
                    Text(
                      order.product.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '${order.executedQuantity ?? order.quantity} qty · ₹${avgPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
              if (hasPnl)
                Text(
                  '${(pnl! >= 0) ? '+' : ''}₹${pnl.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pnl >= 0
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
            ],
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

  Future<void> _cancelOrder(BuildContext context, String orderId) async {
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope != null) {
      try {
        await appScope.tradingService.cancelOrder(orderId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order cancelled')));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cancellation failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    TradingScope.of(context).cancelOrder(orderId);
  }

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
            onPressed: () => _cancelOrder(context, order.id),
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
