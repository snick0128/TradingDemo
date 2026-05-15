import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class AdminStatsScreen extends StatelessWidget {
  const AdminStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    return _Dashboard(store: store);
  }
}

// ── Layout root ────────────────────────────────────────────────────────────────

class _Dashboard extends StatelessWidget {
  final AdminStore store;
  const _Dashboard({required this.store});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return isWide
        ? _WideLayout(store: store)
        : _NarrowLayout(store: store);
  }
}

// ── Wide layout (≥900px): KPIs top, sidebar + table below ─────────────────────

class _WideLayout extends StatelessWidget {
  final AdminStore store;
  const _WideLayout({required this.store});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KpiGrid(store: store),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    Expanded(child: _SidePanel(store: store)),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _OrderTable(store: store)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Narrow layout (mobile): stack vertically ───────────────────────────────────

class _NarrowLayout extends StatefulWidget {
  final AdminStore store;
  const _NarrowLayout({required this.store});

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<_NarrowLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KpiGrid(store: widget.store),
        TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Live Feed'), Tab(text: 'Order Book')],
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _SidePanel(store: widget.store),
              _OrderTable(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }
}

// ── KPI Grid ───────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final AdminStore store;
  const _KpiGrid({required this.store});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOrders = store.masterOrderBook.where((o) =>
        o.dateTime.year == today.year &&
        o.dateTime.month == today.month &&
        o.dateTime.day == today.day).toList();

    final todayVolume = todayOrders.fold<double>(0, (s, o) => s + o.quantity * o.price);
    final activeSymbols = todayOrders.map((o) => o.symbol).toSet().length;
    final executedToday = todayOrders.where((o) =>
        o.status == OrderStatus.executed || o.status == OrderStatus.approved).length;

    final kpis = [
      _KpiData('Total Users', '${store.totalUsers}', LucideIcons.users, AppColors.primary),
      _KpiData('Trades Today', '${todayOrders.length}', LucideIcons.activity, AppColors.success),
      _KpiData('Volume Today', _fmt(todayVolume), LucideIcons.trendingUp, const Color(0xFF7B1FA2)),
      _KpiData('Live Exposure', _fmt(store.liveExposure), LucideIcons.zap, AppColors.warning),
      _KpiData('Executed', '$executedToday', LucideIcons.checkCircle, AppColors.success),
      _KpiData('Active Symbols', '$activeSymbols', LucideIcons.barChart2, AppColors.accent),
      _KpiData('Revenue', '₹${_fmt(store.revenue)}', LucideIcons.dollarSign, const Color(0xFF00838F)),
      _KpiData('Risk Est.', '₹${_fmt(store.operatorRiskLossEstimate)}', LucideIcons.shieldAlert, AppColors.danger),
    ];

    final cols = MediaQuery.of(context).size.width >= 900 ? 8 : 4;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: 68,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: kpis.length,
        itemBuilder: (_, i) => _KpiCard(data: kpis[i]),
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _KpiData {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiData(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: data.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: data.color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(data.icon, size: 13, color: data.color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: data.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                data.label,
                style: TextStyle(
                  fontSize: 9,
                  color: data.color.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Side panel: Live Feed + Anomaly tabs ───────────────────────────────────────

class _SidePanel extends StatefulWidget {
  final AdminStore store;
  const _SidePanel({required this.store});

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Live Feed'), Tab(text: '⚠ Anomalies')],
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _LiveFeed(store: widget.store),
              _AnomalyPanel(store: widget.store),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Live Feed ──────────────────────────────────────────────────────────────────

class _LiveFeed extends StatelessWidget {
  final AdminStore store;
  const _LiveFeed({required this.store});

  @override
  Widget build(BuildContext context) {
    final orders = store.masterOrderBook;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Real-time trades',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${orders.length} total',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: orders.isEmpty
              ? const Center(
                  child: Text(
                    'No trades yet.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _FeedTile(order: orders[i]),
                ),
        ),
      ],
    );
  }
}

class _FeedTile extends StatelessWidget {
  final AdminOrderRecord order;
  const _FeedTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final time = DateFormat('HH:mm:ss').format(order.dateTime);
    final total = order.quantity * order.price;
    final uid = order.userClientId.isNotEmpty
        ? order.userClientId
        : order.userId.substring(0, order.userId.length.clamp(0, 6));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.4)),
        ),
      ),
      child: Row(
        children: [
          // Side badge
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: sideColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isBuy ? 'BUY' : 'SELL',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: sideColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Symbol + user
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.symbol,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  uid,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Amount + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_fmt(total)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Anomaly Panel ──────────────────────────────────────────────────────────────

class _AnomalyPanel extends StatelessWidget {
  final AdminStore store;
  const _AnomalyPanel({required this.store});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 1));
    final recentOrders = store.masterOrderBook.where((o) => o.dateTime.isAfter(cutoff)).toList();

    final userCounts = <String, int>{};
    final userVolumes = <String, double>{};
    for (final o in recentOrders) {
      userCounts[o.userId] = (userCounts[o.userId] ?? 0) + 1;
      userVolumes[o.userId] = (userVolumes[o.userId] ?? 0) + o.quantity * o.price;
    }

    final anomalies = <_Anomaly>[];
    for (final e in userCounts.entries) {
      if (e.value > 10) {
        anomalies.add(_Anomaly(e.key, '${e.value} trades in 1 min', true));
      } else if (e.value > 5) {
        anomalies.add(_Anomaly(e.key, '${e.value} trades in 1 min', false));
      }
    }
    for (final e in userVolumes.entries) {
      if (e.value > 1000000) {
        anomalies.add(_Anomaly(
          e.key,
          'Volume ₹${(e.value / 100000).toStringAsFixed(1)}L in 1 min',
          true,
        ));
      }
    }
    // Check for high-value single orders
    for (final o in recentOrders) {
      if (o.quantity * o.price > 5000000) {
        anomalies.add(_Anomaly(o.userId, 'Large order: ${o.symbol} ₹${(o.quantity * o.price / 100000).toStringAsFixed(1)}L', true));
      }
    }

    if (anomalies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 24),
            ),
            const SizedBox(height: 10),
            const Text(
              'No anomalies',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'All trading activity looks normal.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: anomalies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final a = anomalies[i];
        final color = a.isHigh ? AppColors.danger : AppColors.warning;
        final short = a.userId.substring(0, a.userId.length.clamp(0, 7));
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(
                a.isHigh ? Icons.warning_rounded : Icons.info_outline,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$short…',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      a.message,
                      style: TextStyle(fontSize: 10, color: color),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  a.isHigh ? 'HIGH' : 'MED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Anomaly {
  final String userId, message;
  final bool isHigh;
  const _Anomaly(this.userId, this.message, this.isHigh);
}

// ── Order Table ────────────────────────────────────────────────────────────────

class _OrderTable extends StatefulWidget {
  final AdminStore store;
  const _OrderTable({required this.store});

  @override
  State<_OrderTable> createState() => _OrderTableState();
}

class _OrderTableState extends State<_OrderTable> {
  String _typeFilter = 'ALL';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    var orders = widget.store.masterOrderBook.toList();
    if (_typeFilter != 'ALL') {
      orders = orders.where((o) => (_typeFilter == 'BUY') == (o.type == OrderType.buy)).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toUpperCase();
      orders = orders.where((o) => o.symbol.contains(q) || o.userClientId.contains(q)).toList();
    }

    final isWide = MediaQuery.of(context).size.width >= 900;

    return Column(
      children: [
        // ── Filter bar ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(
                'Order Book',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${orders.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              // Type filter chips
              for (final t in ['ALL', 'BUY', 'SELL'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _typeFilter = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _typeFilter == t
                            ? (t == 'BUY'
                                ? AppColors.success
                                : t == 'SELL'
                                    ? AppColors.danger
                                    : AppColors.primary)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _typeFilter == t
                              ? Colors.transparent
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _typeFilter == t
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              SizedBox(
                width: isWide ? 140 : 90,
                height: 28,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.toUpperCase()),
                  decoration: const InputDecoration(
                    hintText: 'Symbol / User…',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    prefixIcon: Icon(LucideIcons.search, size: 13),
                    prefixIconConstraints: BoxConstraints(minWidth: 28),
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        // ── Table header ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
              _th('Time', 2),
              if (isWide) _th('User', 2),
              _th('Symbol', 2),
              _th('Side', 1),
              _th('Qty', 1, right: true),
              if (isWide) _th('Price', 2, right: true),
              _th('Total', 2, right: true),
              if (isWide) _th('P&L', 2, right: true),
              _th('Status', 2),
            ],
          ),
        ),

        // ── Rows ─────────────────────────────────────────────────────────────
        Expanded(
          child: orders.isEmpty
              ? const Center(
                  child: Text(
                    'No orders.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _OrderRow(order: orders[i], isWide: isWide),
                ),
        ),
      ],
    );
  }

  Widget _th(String label, int flex, {bool right = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final AdminOrderRecord order;
  final bool isWide;
  const _OrderRow({required this.order, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final total = order.quantity * order.price;
    final isExec = order.status == OrderStatus.executed || order.status == OrderStatus.approved;
    final time = DateFormat('HH:mm:ss').format(order.dateTime);

    // Simulated P&L (same formula used throughout app)
    final h = order.id.hashCode.abs();
    final movement = (h % 200 - 100) / 1000.0;
    final pnl = order.quantity * order.price * movement;

    final statusColor = _statusColor(order.status);
    final statusLabel = _statusLabel(order.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.4)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              time,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (isWide)
            Expanded(
              flex: 2,
              child: Text(
                order.userClientId.isNotEmpty
                    ? order.userClientId
                    : '${order.userId.substring(0, order.userId.length.clamp(0, 6))}…',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            flex: 2,
            child: Text(
              order.symbol,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: sideColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                isBuy ? 'B' : 'S',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: sideColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${order.quantity}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(fontSize: 10),
            ),
          ),
          if (isWide)
            Expanded(
              flex: 2,
              child: Text(
                '₹${order.price.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(fontSize: 10),
              ),
            ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${_fmt(total)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isWide)
            Expanded(
              flex: 2,
              child: isExec
                  ? Text(
                      '${pnl >= 0 ? '+' : ''}₹${_fmt(pnl.abs())}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: pnl >= 0 ? AppColors.success : AppColors.danger,
                      ),
                    )
                  : const Text(
                      '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
            ),
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
      case OrderStatus.approved:
        return AppColors.success;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return AppColors.danger;
      case OrderStatus.partiallyExecuted:
        return AppColors.warning;
      case OrderStatus.pending:
        return AppColors.warning;
    }
  }

  static String _statusLabel(OrderStatus s) {
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

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
