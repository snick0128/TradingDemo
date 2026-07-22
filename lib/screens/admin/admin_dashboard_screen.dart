import 'dart:math' show max;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    final width = MediaQuery.of(context).size.width;
    return _DashboardBody(store: store, screenWidth: width);
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final AdminStore store;
  final double screenWidth;
  const _DashboardBody({required this.store, required this.screenWidth});

  bool get _isDesktop => screenWidth >= 1024;
  bool get _isTablet => screenWidth >= 768;

  @override
  Widget build(BuildContext context) {
    final orders = store.masterOrderBook.toList();
    final metrics = _Metrics(orders, store);

    return SingleChildScrollView(
      padding: EdgeInsets.all(_isDesktop ? 20 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────
          _PageHeader(metrics: metrics),
          SizedBox(height: _isDesktop ? 20 : 16),

          // ── KPI grid ───────────────────────────────────────────────
          _KpiGrid(metrics: metrics, columns: _isDesktop ? 4 : _isTablet ? 3 : 2),
          SizedBox(height: _isDesktop ? 20 : 16),

          // ── Charts row ─────────────────────────────────────────────
          if (_isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _VolumeChart(orders: orders)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _ExchangeDistribution(orders: orders)),
              ],
            )
          else ...[
            _VolumeChart(orders: orders),
            const SizedBox(height: 12),
            _ExchangeDistribution(orders: orders),
          ],
          SizedBox(height: _isDesktop ? 20 : 16),

          // ── Bottom panels ──────────────────────────────────────────
          if (_isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TopSymbols(orders: orders)),
                const SizedBox(width: 16),
                Expanded(child: _TopUsers(orders: orders, store: store)),
                const SizedBox(width: 16),
                Expanded(child: _RecentActivity(orders: orders)),
              ],
            )
          else ...[
            _TopSymbols(orders: orders),
            const SizedBox(height: 12),
            _TopUsers(orders: orders, store: store),
            const SizedBox(height: 12),
            _RecentActivity(orders: orders),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _Metrics {
  final List<AdminOrderRecord> orders;
  final AdminStore store;

  const _Metrics(this.orders, this.store);

  bool _exec(AdminOrderRecord o) =>
      o.status == OrderStatus.executed || o.status == OrderStatus.approved;

  List<AdminOrderRecord> get _executed => orders.where(_exec).toList();

  DateTime get _today => DateTime.now();

  List<AdminOrderRecord> get _todayOrders => orders
      .where((o) =>
          o.dateTime.year == _today.year &&
          o.dateTime.month == _today.month &&
          o.dateTime.day == _today.day)
      .toList();

  int get totalUsers => store.totalUsers;
  int get activeSessions => store.activeSessions;
  int get todayTradeCount => _todayOrders.length;
  // Open positions = FIFO-matched count (only unmatched buy legs remain open).
  // Using raw executed order count was wrong — it counted both open AND closed
  // trades, inflating the KPI for every completed trade.
  int get openPositions => store.openPositionCount;
  int get closedTrades => _executed.length;
  int get pendingOrders =>
      orders.where((o) => o.status == OrderStatus.pending).length;

  double get totalVolume => store.totalVolume;
  double get todayVolume =>
      _todayOrders.where(_exec).fold(0.0, (s, o) => s + o.quantity * o.price);
  // Real brokerage from matched trades (0.03% per leg of actual fills)
  double get brokerageEarned => store.revenue;
  // Net admin P&L = brokerage collected − user profits paid (real matched trades)
  double get netRevenue => store.platformPnl;
  double get platformPnl => store.platformPnl;
  double get liveExposure => store.liveExposure;
  double get riskEstimate => store.operatorRiskLossEstimate;

  // Hourly volume for the chart (0-23)
  List<double> get volumeByHour {
    final m = <int, double>{};
    for (final o in _executed) {
      m[o.dateTime.hour] = (m[o.dateTime.hour] ?? 0) + o.quantity * o.price;
    }
    return List.generate(24, (h) => m[h] ?? 0);
  }

  // Exchange distribution
  Map<String, int> get byExchange {
    final m = <String, int>{};
    for (final o in orders) {
      final ex = o.exchange.isEmpty ? 'NSE' : o.exchange;
      m[ex] = (m[ex] ?? 0) + 1;
    }
    return m;
  }

  // Top symbols by volume
  List<MapEntry<String, double>> get topSymbols {
    final m = <String, double>{};
    for (final o in _executed) {
      m[o.symbol] = (m[o.symbol] ?? 0) + o.quantity * o.price;
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(8).toList();
  }

  // Volume sparkline for last 7 hours
  List<double> get recentHourlySparkline {
    final all = volumeByHour;
    final now = DateTime.now().hour;
    final out = <double>[];
    for (int i = 6; i >= 0; i--) {
      final h = (now - i) % 24;
      out.add(all[h]);
    }
    return out;
  }
}

// ── Page header ────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final _Metrics metrics;
  const _PageHeader({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Operations Dashboard',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                now,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        // Live pulse
        _LiveBadge(),
        const SizedBox(width: 12),
        if (metrics.pendingOrders > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertCircle,
                    size: 13, color: AppColors.warning),
                const SizedBox(width: 5),
                Text(
                  '${metrics.pendingOrders} pending',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.success.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success
                    .withOpacity(0.5 + _anim.value * 0.5),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KPI Grid ───────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final _Metrics metrics;
  final int columns;
  const _KpiGrid({required this.metrics, required this.columns});

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards(metrics);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: columns == 4 ? 1.9 : columns == 3 ? 1.7 : 1.6,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }

  List<Widget> _buildCards(_Metrics m) {
    final spark = m.recentHourlySparkline;
    return [
      _KpiCard(
        icon: LucideIcons.trendingUp,
        label: 'Total Volume',
        value: _fmtCurrency(m.totalVolume),
        sub: 'Today: ${_fmtCurrency(m.todayVolume)}',
        color: AppColors.primary,
        sparkData: spark,
      ),
      _KpiCard(
        icon: LucideIcons.activity,
        label: "Today's Trades",
        value: _fmt(m.todayTradeCount),
        sub: '${m.closedTrades} total closed',
        color: const Color(0xFF7B61FF),
        sparkData: spark.map((v) => v * 0.7).toList(),
      ),
      _KpiCard(
        icon: LucideIcons.dollarSign,
        label: 'Brokerage Collected',
        value: _fmtCurrency(m.brokerageEarned),
        sub: 'All users · All time',
        color: AppColors.success,
        sparkData: spark.map((v) => v * 0.0003).toList(),
      ),
      _KpiCard(
        icon: LucideIcons.coins,
        label: 'Admin Net P&L',
        value: _fmtCurrency(m.netRevenue),
        sub: 'Brokerage − User Profits',
        color: const Color(0xFF00BFA5),
        sparkData: spark.map((v) => v * 0.00055).toList(),
      ),
      _KpiCard(
        icon: LucideIcons.users,
        label: 'Total Users',
        value: _fmt(m.totalUsers),
        sub: '${m.activeSessions} active now',
        color: const Color(0xFF1565C0),
        sparkData: null,
      ),
      _KpiCard(
        icon: LucideIcons.zap,
        label: 'Open Positions',
        value: _fmt(m.openPositions),
        sub: '${m.pendingOrders} pending',
        color: AppColors.warning,
        sparkData: null,
      ),
      _KpiCard(
        icon: LucideIcons.layers,
        label: 'Live Exposure',
        value: _fmtCurrency(m.liveExposure),
        sub: 'Risk est: ${_fmtCurrency(m.riskEstimate)}',
        color: AppColors.danger,
        sparkData: null,
      ),
      _KpiCard(
        icon: LucideIcons.checkCircle,
        label: 'Closed Trades',
        value: _fmt(m.closedTrades),
        sub: '${m.orders.length} total orders',
        color: const Color(0xFF00897B),
        sparkData: null,
      ),
    ];
  }

  static String _fmt(int v) => NumberFormat.compact().format(v);
  static String _fmtCurrency(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;
  final List<double>? sparkData;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.sparkData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const Spacer(),
                if (sparkData != null && sparkData!.isNotEmpty)
                  SizedBox(
                    width: 48,
                    height: 24,
                    child: _Sparkline(data: sparkData!, color: color),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              sub,
              style: GoogleFonts.inter(
                  fontSize: 10, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sparkline ──────────────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  const _Sparkline({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    if (data.every((v) => v == 0)) return const SizedBox.shrink();
    final maxV = data.reduce(max);
    final normalized =
        maxV == 0 ? data : data.map((v) => v / maxV * 100).toList();
    final spots = normalized
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Volume Chart ───────────────────────────────────────────────────────────────

class _VolumeChart extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  const _VolumeChart({required this.orders});

  List<double> _hourly() {
    final m = <int, double>{};
    for (final o in orders) {
      if (o.status == OrderStatus.executed ||
          o.status == OrderStatus.approved) {
        m[o.dateTime.hour] =
            (m[o.dateTime.hour] ?? 0) + o.quantity * o.price;
      }
    }
    return List.generate(24, (h) => m[h] ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final hourly = _hourly();
    final maxV = hourly.reduce(max);
    final spots = hourly
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 100000))
        .toList();

    return _Panel(
      title: 'Volume by Hour',
      trailing: Text('₹ in Lakhs',
          style: GoogleFonts.inter(
              fontSize: 10, color: AppColors.textSecondary)),
      child: SizedBox(
        height: 160,
        child: maxV == 0
            ? _EmptyChart()
            : LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.border,
                      strokeWidth: 0.5,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 4,
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${v.toInt()}h',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                '₹${s.y.toStringAsFixed(1)}L\n${s.x.toInt()}:00',
                                GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ))
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.primary.withOpacity(0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.barChart2,
              size: 32, color: AppColors.border),
          const SizedBox(height: 8),
          Text('No trade data yet',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Exchange Distribution ──────────────────────────────────────────────────────

class _ExchangeDistribution extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  const _ExchangeDistribution({required this.orders});

  Map<String, int> get _byExchange {
    final m = <String, int>{};
    for (final o in orders) {
      final ex = o.exchange.isEmpty ? 'NSE' : o.exchange;
      m[ex] = (m[ex] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final dist = _byExchange;
    final total = dist.values.fold(0, (a, b) => a + b);
    final exchColors = {
      'NSE': AppColors.primary,
      'BSE': const Color(0xFF1565C0),
      'MCX': const Color(0xFF6A1B9A),
      'NFO': const Color(0xFF00897B),
      'CDS': const Color(0xFFE65100),
    };

    return _Panel(
      title: 'Exchange Distribution',
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (total == 0)
            _EmptyChart()
          else
            ...dist.entries.map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              final color =
                  exchColors[e.key] ?? AppColors.textSecondary;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(e.key,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                        const Spacer(),
                        Text(
                          '${e.value} (${(pct * 100).toStringAsFixed(1)}%)',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Top Symbols ────────────────────────────────────────────────────────────────

class _TopSymbols extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  const _TopSymbols({required this.orders});

  List<MapEntry<String, double>> get _top {
    final m = <String, double>{};
    for (final o in orders) {
      if (o.status == OrderStatus.executed ||
          o.status == OrderStatus.approved) {
        m[o.symbol] = (m[o.symbol] ?? 0) + o.quantity * o.price;
      }
    }
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .toList();
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    final maxV = top.isEmpty ? 1.0 : top.first.value;

    return _Panel(
      title: 'Top Symbols',
      trailing: Text('by volume',
          style: GoogleFonts.inter(
              fontSize: 10, color: AppColors.textSecondary)),
      child: top.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _EmptyChart(),
            )
          : Column(
              children: top.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final pct = e.value / maxV;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${i + 1}',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(e.key,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    )),
                                const Spacer(),
                                Text(_fmt(e.value),
                                    style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: AppColors.border,
                                valueColor: AlwaysStoppedAnimation(
                                    AppColors.primary
                                        .withOpacity(0.4 + pct * 0.6)),
                                minHeight: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ── Top Users ─────────────────────────────────────────────────────────────────

class _TopUsers extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  final AdminStore store;
  const _TopUsers({required this.orders, required this.store});

  static String _fmt(double v) {
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    // Build volume-by-user from orders
    final volByUser = <String, double>{};
    final labelByUser = <String, String>{};
    for (final o in orders) {
      if (o.status == OrderStatus.executed ||
          o.status == OrderStatus.approved) {
        volByUser[o.userId] =
            (volByUser[o.userId] ?? 0) + o.quantity * o.price;
        if (o.userClientId.isNotEmpty)
          labelByUser[o.userId] = o.userClientId;
      }
    }
    final sorted = volByUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return _Panel(
      title: 'Top Traders',
      trailing: Text('by volume',
          style: GoogleFonts.inter(
              fontSize: 10, color: AppColors.textSecondary)),
      child: top5.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _EmptyChart(),
            )
          : Column(
              children: top5.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final label = labelByUser[e.key] ??
                    e.key.substring(
                        0, e.key.length.clamp(0, 8));
                final initials = label.length >= 2
                    ? label.substring(0, 2).toUpperCase()
                    : label.toUpperCase();
                final avatarColor =
                    _avatarColor(i);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            avatarColor.withOpacity(0.15),
                        child: Text(
                          initials,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: avatarColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis),
                            Text(_fmt(e.value) + ' vol',
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color:
                                        AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Text(
                        '#${i + 1}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: i == 0
                              ? const Color(0xFFFFB300)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Color _avatarColor(int i) {
    const colors = [
      Color(0xFF2962FF),
      Color(0xFF00897B),
      Color(0xFF6A1B9A),
      Color(0xFFE65100),
      Color(0xFF1565C0),
    ];
    return colors[i % colors.length];
  }
}

// ── Recent Activity ────────────────────────────────────────────────────────────

class _RecentActivity extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  const _RecentActivity({required this.orders});

  @override
  Widget build(BuildContext context) {
    final recent = orders.take(10).toList();

    return _Panel(
      title: 'Recent Orders',
      trailing: Text('last 10',
          style: GoogleFonts.inter(
              fontSize: 10, color: AppColors.textSecondary)),
      child: recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _EmptyChart(),
            )
          : Column(
              children: recent.map((o) {
                final isBuy = o.type == OrderType.buy;
                final sideColor =
                    isBuy ? AppColors.success : AppColors.danger;
                Color statusColor;
                switch (o.status) {
                  case OrderStatus.executed:
                  case OrderStatus.approved:
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
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: sideColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isBuy
                              ? LucideIcons.arrowUpRight
                              : LucideIcons.arrowDownLeft,
                          size: 14,
                          color: sideColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${o.symbol} · ${o.quantity}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              o.userClientId.isNotEmpty
                                  ? o.userClientId
                                  : o.userId.substring(
                                      0,
                                      o.userId.length
                                          .clamp(0, 6)),
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color:
                                      AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Text(
                              o.status.name.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('HH:mm').format(o.dateTime),
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ── Panel wrapper ──────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Panel({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
