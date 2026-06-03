import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class LiveMonitorScreen extends StatefulWidget {
  const LiveMonitorScreen({super.key});
  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  String _query = '';
  _RiskFilter _riskFilter = _RiskFilter.all;

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    final allOrders = store.masterOrderBook.toList();

    // Live = executed/approved open positions + in-flight pending orders
    final live = allOrders.where((o) {
      return o.status == OrderStatus.executed ||
          o.status == OrderStatus.approved ||
          o.status == OrderStatus.pending ||
          o.status == OrderStatus.partiallyExecuted;
    }).toList()
      ..sort((a, b) => (b.quantity * b.price).compareTo(a.quantity * a.price));

    // Compute summaries
    final totalExposure =
        live.fold<double>(0, (s, o) => s + o.quantity * o.price);
    final totalPositions = live.length;
    final uniqueUsers = live.map((o) => o.userId).toSet().length;

    // Group by user for risk analysis
    final byUser = <String, List<AdminOrderRecord>>{};
    for (final o in live) {
      byUser.putIfAbsent(o.userId, () => []).add(o);
    }

    // Per-user exposure
    final userExposure = {
      for (final e in byUser.entries)
        e.key: e.value.fold<double>(0, (s, o) => s + o.quantity * o.price)
    };
    final maxUserExposure =
        userExposure.isEmpty ? 1.0 : userExposure.values.reduce((a, b) => a > b ? a : b);

    // Risk level per order
    _RiskLevel _risk(AdminOrderRecord o) {
      final pct = o.quantity * o.price / (maxUserExposure.clamp(1, double.infinity));
      if (pct > 0.5) return _RiskLevel.high;
      if (pct > 0.15) return _RiskLevel.medium;
      return _RiskLevel.low;
    }

    // Filter
    var filtered = live.where((o) {
      final q = _query.trim().toUpperCase();
      final matchQ = q.isEmpty ||
          o.symbol.toUpperCase().contains(q) ||
          o.userClientId.toUpperCase().contains(q);
      final matchR = _riskFilter == _RiskFilter.all ||
          (_riskFilter == _RiskFilter.high && _risk(o) == _RiskLevel.high) ||
          (_riskFilter == _RiskFilter.medium && _risk(o) == _RiskLevel.medium) ||
          (_riskFilter == _RiskFilter.low && _risk(o) == _RiskLevel.low);
      return matchQ && matchR;
    }).toList();

    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Summary bar ──────────────────────────────────────────────
          _SummaryBar(
            totalPositions: totalPositions,
            uniqueUsers: uniqueUsers,
            totalExposure: totalExposure,
          ),

          // ── Filters ──────────────────────────────────────────────────
          _FilterBar(
            query: _query,
            riskFilter: _riskFilter,
            onQueryChanged: (v) => setState(() => _query = v),
            onRiskFilterChanged: (r) => setState(() => _riskFilter = r),
          ),

          // ── Content ──────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(isFiltered: _query.isNotEmpty || _riskFilter != _RiskFilter.all)
                : isWide
                    ? _DesktopTable(orders: filtered, riskOf: _risk, store: store)
                    : _MobileCardList(orders: filtered, riskOf: _risk),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int totalPositions;
  final int uniqueUsers;
  final double totalExposure;
  const _SummaryBar({
    required this.totalPositions,
    required this.uniqueUsers,
    required this.totalExposure,
  });

  static String _fmtV(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _SummaryChip(
            icon: LucideIcons.radio,
            label: 'Open',
            value: '$totalPositions',
            color: AppColors.success,
          ),
          const SizedBox(width: 16),
          _SummaryChip(
            icon: LucideIcons.users,
            label: 'Users',
            value: '$uniqueUsers',
            color: AppColors.primary,
          ),
          const SizedBox(width: 16),
          _SummaryChip(
            icon: LucideIcons.trendingUp,
            label: 'Exposure',
            value: _fmtV(totalExposure),
            color: AppColors.warning,
          ),
          const Spacer(),
          // Live pulse
          _LivePulse(),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                )),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 9,
                    color: Colors.white54,
                    letterSpacing: 0.3)),
          ],
        ),
      ],
    );
  }
}

class _LivePulse extends StatefulWidget {
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(0.5 + _ctrl.value * 0.5),
            ),
          ),
          const SizedBox(width: 5),
          Text('LIVE MONITOR',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
                letterSpacing: 1,
              )),
        ],
      ),
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String query;
  final _RiskFilter riskFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_RiskFilter> onRiskFilterChanged;
  const _FilterBar({
    required this.query,
    required this.riskFilter,
    required this.onQueryChanged,
    required this.onRiskFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // Search
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search symbol or user…',
                  hintStyle: GoogleFonts.inter(fontSize: 12),
                  prefixIcon: const Icon(LucideIcons.search, size: 14),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () => onQueryChanged(''),
                          padding: EdgeInsets.zero,
                        )
                      : null,
                ),
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Risk filters
          ..._RiskFilter.values.map((r) {
            final label = r == _RiskFilter.all
                ? 'All'
                : r == _RiskFilter.high
                    ? 'High Risk'
                    : r == _RiskFilter.medium
                        ? 'Medium'
                        : 'Low Risk';
            final color = r == _RiskFilter.high
                ? AppColors.danger
                : r == _RiskFilter.medium
                    ? AppColors.warning
                    : AppColors.success;
            final selected = riskFilter == r;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => onRiskFilterChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? (r == _RiskFilter.all
                            ? AppColors.primary
                            : color)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: r == _RiskFilter.all
                            ? (selected ? AppColors.primary : AppColors.border)
                            : (selected ? color : AppColors.border)),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Desktop table ──────────────────────────────────────────────────────────────

class _DesktopTable extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  final _RiskLevel Function(AdminOrderRecord) riskOf;
  final AdminStore store;
  const _DesktopTable({
    required this.orders,
    required this.riskOf,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: const Color(0xFFF5F5F5),
          child: Row(
            children: const [
              _TH('User', 2),
              _TH('Symbol', 2),
              _TH('Side', 1),
              _TH('Qty', 1, right: true),
              _TH('Entry Price', 2, right: true),
              _TH('Exposure', 2, right: true),
              _TH('Time', 2),
              _TH('Risk', 1),
              _TH('Exchange', 1),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (_, i) => _DesktopRow(
              order: orders[i],
              risk: riskOf(orders[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool right;
  const _TH(this.label, this.flex, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DesktopRow extends StatelessWidget {
  final AdminOrderRecord order;
  final _RiskLevel risk;
  const _DesktopRow({required this.order, required this.risk});

  static String _fmtV(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final riskColor = risk == _RiskLevel.high
        ? AppColors.danger
        : risk == _RiskLevel.medium
            ? AppColors.warning
            : AppColors.success;
    final exposure = order.quantity * order.price;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
          left: BorderSide(color: riskColor, width: 2),
        ),
        color: risk == _RiskLevel.high
            ? AppColors.danger.withOpacity(0.02)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              order.userClientId.isNotEmpty
                  ? order.userClientId
                  : order.userId.substring(0, order.userId.length.clamp(0, 8)),
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.symbol,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
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
                isBuy ? 'BUY' : 'SELL',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 9,
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
              style: GoogleFonts.jetBrainsMono(fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.price > 0 ? '₹${order.price.toStringAsFixed(2)}' : '—',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtV(exposure),
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd/MM HH:mm').format(order.dateTime),
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                risk == _RiskLevel.high
                    ? 'HIGH'
                    : risk == _RiskLevel.medium
                        ? 'MED'
                        : 'LOW',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: riskColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              order.exchange.isEmpty ? 'NSE' : order.exchange,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile card list ───────────────────────────────────────────────────────────

class _MobileCardList extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  final _RiskLevel Function(AdminOrderRecord) riskOf;
  const _MobileCardList(
      {required this.orders, required this.riskOf});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (_, i) =>
          _MobileCard(order: orders[i], risk: riskOf(orders[i])),
    );
  }
}

class _MobileCard extends StatelessWidget {
  final AdminOrderRecord order;
  final _RiskLevel risk;
  const _MobileCard({required this.order, required this.risk});

  static String _fmtV(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final riskColor = risk == _RiskLevel.high
        ? AppColors.danger
        : risk == _RiskLevel.medium
            ? AppColors.warning
            : AppColors.success;
    final exposure = order.quantity * order.price;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: riskColor.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: riskColor.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: sideColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(isBuy ? 'BUY' : 'SELL',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: sideColor,
                      )),
                ),
                const SizedBox(width: 8),
                Text(order.symbol,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    )),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${risk.name.toUpperCase()} RISK',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${order.quantity} × ₹${order.price.toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text('Exposure: ${_fmtV(exposure)}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          )),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      order.userClientId.isNotEmpty
                          ? order.userClientId
                          : order.userId.substring(
                              0, order.userId.length.clamp(0, 8)),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd MMM · HH:mm').format(order.dateTime),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoPill(order.exchange.isEmpty ? 'NSE' : order.exchange),
                const SizedBox(width: 6),
                _InfoPill(order.product.isEmpty ? 'MIS' : order.product),
                const SizedBox(width: 6),
                _InfoPill(order.variety.isEmpty ? 'MARKET' : order.variety),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  const _InfoPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          )),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isFiltered;
  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? LucideIcons.searchX : LucideIcons.radio,
            size: 48,
            color: AppColors.border,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered
                ? 'No positions match your filter.'
                : 'No open positions right now.',
            style: GoogleFonts.inter(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          if (!isFiltered) ...[
            const SizedBox(height: 8),
            Text(
              'Open positions will appear here in real time.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Enums ──────────────────────────────────────────────────────────────────────

enum _RiskLevel { low, medium, high }

enum _RiskFilter { all, low, medium, high }
