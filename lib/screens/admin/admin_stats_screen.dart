import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

/// Live trading terminal dashboard for admins.
///
/// ⚠️ NO StreamBuilders here — all data comes from AdminStore which already
/// holds the Firestore subscriptions. Adding more streams here was causing
/// Firestore SDK internal assertion failures (WatchChangeAggregator overload).
class AdminStatsScreen extends StatelessWidget {
  const AdminStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    return _AdminDashboard(store: store);
  }
}

// ── Main layout ───────────────────────────────────────────────────────────────

class _AdminDashboard extends StatelessWidget {
  final AdminStore store;
  const _AdminDashboard({required this.store});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: KPIs + Live Feed + Anomaly Detection
        SizedBox(
          width: 340,
          child: Column(
            children: [
              _KpiStrip(store: store),
              const Divider(height: 1),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Live Feed'),
                          Tab(text: '⚠ Anomalies'),
                        ],
                        labelStyle: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _LiveTradeFeed(store: store),
                            _AnomalyPanel(store: store),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: Order table
        Expanded(child: _OrderTable(store: store)),
      ],
    );
  }
}

// ── KPI Strip — reads from AdminStore, no extra streams ──────────────────────

class _KpiStrip extends StatelessWidget {
  final AdminStore store;
  const _KpiStrip({required this.store});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOrders = store.masterOrderBook.where((o) {
      return o.dateTime.year == today.year &&
          o.dateTime.month == today.month &&
          o.dateTime.day == today.day;
    }).toList();

    final volume = todayOrders.fold<double>(
        0, (s, o) => s + (o.quantity * o.price));

    final activeStocks = todayOrders.map((o) => o.symbol).toSet().length;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Dashboard',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Kpi('Users', '${store.totalUsers}', AppColors.primary),
              const SizedBox(width: 8),
              _Kpi('Trades Today', '${todayOrders.length}', AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Kpi('Volume', '₹${_fmt(volume)}', AppColors.accent),
              const SizedBox(width: 8),
              _Kpi('Active Stocks', '$activeStocks', AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Live Trade Feed — reads from AdminStore.masterOrderBook ──────────────────

class _LiveTradeFeed extends StatelessWidget {
  final AdminStore store;
  const _LiveTradeFeed({required this.store});

  @override
  Widget build(BuildContext context) {
    final orders = store.masterOrderBook;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('Live Trades',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const Center(
                  child: Text('No trades yet.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: orders.length,
                  itemBuilder: (context, i) {
                    final o = orders[i];
                    return _FeedRow(order: o);
                  },
                ),
        ),
      ],
    );
  }
}

class _FeedRow extends StatelessWidget {
  final AdminOrderRecord order;
  const _FeedRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final color = isBuy ? AppColors.success : AppColors.danger;
    final time = DateFormat('HH:mm:ss').format(order.dateTime);
    final userId = order.userId.length > 6
        ? order.userId.substring(0, 6)
        : order.userId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Text(time,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(isBuy ? 'BUY' : 'SELL',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(order.symbol,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Text('${order.quantity} × ',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          Text('₹${order.price.toStringAsFixed(0)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('($userId…)',
              style: const TextStyle(
                  fontSize: 9, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Order Table — reads from AdminStore.masterOrderBook ──────────────────────

class _OrderTable extends StatefulWidget {
  final AdminStore store;
  const _OrderTable({required this.store});

  @override
  State<_OrderTable> createState() => _OrderTableState();
}

class _OrderTableState extends State<_OrderTable> {
  String _filterType = 'ALL';
  String _filterStock = '';

  @override
  Widget build(BuildContext context) {
    var orders = widget.store.masterOrderBook.toList();

    if (_filterType != 'ALL') {
      orders = orders
          .where((o) =>
              (_filterType == 'BUY') == (o.type == OrderType.buy))
          .toList();
    }
    if (_filterStock.isNotEmpty) {
      orders = orders
          .where((o) => o.symbol.contains(_filterStock))
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text('Order Book',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              for (final t in ['ALL', 'BUY', 'SELL'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(t, style: const TextStyle(fontSize: 11)),
                    selected: _filterType == t,
                    onSelected: (_) => setState(() => _filterType = t),
                    selectedColor: t == 'BUY'
                        ? AppColors.success.withValues(alpha: 0.2)
                        : t == 'SELL'
                            ? AppColors.danger.withValues(alpha: 0.2)
                            : AppColors.primary.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 0),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                height: 30,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Stock…',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) =>
                      setState(() => _filterStock = v.toUpperCase()),
                ),
              ),
            ],
          ),
        ),

        // Table header
        _TableHeader(),

        // Table rows — from store, no StreamBuilder
        Expanded(
          child: orders.isEmpty
              ? const Center(
                  child: Text('No orders.',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, i) => _OrderRow(order: orders[i]),
                ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surfaceAlt,
      child: const Row(
        children: [
          _TH('Time', flex: 2),
          _TH('User', flex: 2),
          _TH('Stock', flex: 2),
          _TH('Type', flex: 1),
          _TH('Qty', flex: 1, right: true),
          _TH('Price', flex: 2, right: true),
          _TH('Total', flex: 2, right: true),
          _TH('Status', flex: 2),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool right;
  const _TH(this.label, {this.flex = 1, this.right = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final AdminOrderRecord order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final typeColor = isBuy ? AppColors.success : AppColors.danger;
    final statusStr = _statusLabel(order.status);
    final isExecuted = order.status == OrderStatus.executed ||
        order.status == OrderStatus.approved;
    final time = DateFormat('HH:mm:ss').format(order.dateTime);
    final userId = order.userId.length > 6
        ? order.userId.substring(0, 6)
        : order.userId;
    final total = order.quantity * order.price;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(time,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Text('$userId…',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Text(order.symbol,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                isBuy ? 'BUY' : 'SELL',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: typeColor),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('${order.quantity}',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(fontSize: 11)),
          ),
          Expanded(
            flex: 2,
            child: Text('₹${order.price.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text('₹${total.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isExecuted
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                statusStr,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isExecuted
                        ? AppColors.success
                        : AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
        return 'EXECUTED';
      case OrderStatus.approved:
        return 'APPROVED';
      case OrderStatus.rejected:
        return 'REJECTED';
      case OrderStatus.cancelled:
        return 'CANCELLED';
      case OrderStatus.partiallyExecuted:
        return 'PARTIAL';
      case OrderStatus.pending:
        return 'PENDING';
    }
  }
}

// ── Anomaly Detection Panel — reads from AdminStore.masterOrderBook ───────────

class _AnomalyPanel extends StatelessWidget {
  final AdminStore store;
  const _AnomalyPanel({required this.store});

  @override
  Widget build(BuildContext context) {
    final orders = store.masterOrderBook;
    final now = DateTime.now();
    final oneMinAgo = now.subtract(const Duration(minutes: 1));

    final userCounts = <String, int>{};
    final userVolumes = <String, double>{};
    for (final o in orders) {
      if (o.dateTime.isBefore(oneMinAgo)) continue;
      userCounts[o.userId] = (userCounts[o.userId] ?? 0) + 1;
      userVolumes[o.userId] =
          (userVolumes[o.userId] ?? 0) + (o.quantity * o.price);
    }

    final anomalies = <_Anomaly>[];
    for (final e in userCounts.entries) {
      if (e.value > 10) {
        anomalies.add(_Anomaly(
            userId: e.key,
            message: '${e.value} trades in 1 min',
            severity: 'HIGH'));
      } else if (e.value > 5) {
        anomalies.add(_Anomaly(
            userId: e.key,
            message: '${e.value} trades in 1 min',
            severity: 'MEDIUM'));
      }
    }
    for (final e in userVolumes.entries) {
      if (e.value > 1000000) {
        anomalies.add(_Anomaly(
            userId: e.key,
            message:
                'Volume ₹${(e.value / 100000).toStringAsFixed(1)}L in 1 min',
            severity: 'HIGH'));
      }
    }

    if (anomalies.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 32),
            SizedBox(height: 8),
            Text('No anomalies detected',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: anomalies.length,
      itemBuilder: (context, i) {
        final a = anomalies[i];
        final isHigh = a.severity == 'HIGH';
        final color = isHigh ? AppColors.danger : AppColors.warning;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                isHigh ? Icons.warning_rounded : Icons.info_outline,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a.userId.substring(0, a.userId.length.clamp(0, 6))}…',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Text(a.message,
                        style: TextStyle(fontSize: 10, color: color)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(a.severity,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Anomaly {
  final String userId;
  final String message;
  final String severity;
  const _Anomaly(
      {required this.userId, required this.message, required this.severity});
}
