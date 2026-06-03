import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/trade_ledger.dart';
import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

// ── Analytics data model ───────────────────────────────────────────────────────
// All metrics derived from real FIFO-matched trades via LedgerSummary.
// No synthetic multipliers or hashcode-based P&L.

class _Analytics {
  final List<AdminOrderRecord> orders;
  late final LedgerSummary _ledger;

  _Analytics(this.orders) {
    _ledger = LedgerSummary(orders);
  }

  bool _exec(AdminOrderRecord o) =>
      o.status == OrderStatus.executed || o.status == OrderStatus.approved;

  // Volume = sum of all executed order notionals
  double get volume =>
      orders.where(_exec).fold(0.0, (s, o) => s + o.quantity * o.price);

  // Real brokerage: 0.03% per leg of actual fill prices
  double get brokerageEarned => _ledger.brokerageRevenue;

  // Profits paid to winning users from matched closed trades
  double get userProfitPaid => _ledger.userProfitsPaid;

  // Net admin P&L = brokerage collected − user profits paid (real, no fake charges)
  double get netAdminPnl => _ledger.netAdminPnl;

  int get totalOrders => orders.length;
  int get executedOrders => orders.where(_exec).length;
  int get closedTrades => _ledger.closed.length;
  int get activeUsers => orders.map((o) => o.userId).toSet().length;
  double get exposure => volume;

  // Win rate over matched CLOSED trades only
  double get winRatio => _ledger.winRate;

  // Real P&L per symbol (from matched closed trades)
  Map<String, double> get pnlBySymbol => _ledger.pnlBySymbol;

  // Real P&L per user clientId (from matched closed trades)
  Map<String, double> get pnlByUser {
    final m = <String, double>{};
    for (final t in _ledger.closed) {
      final id = t.userClientId.isNotEmpty ? t.userClientId : t.userId;
      m[id] = (m[id] ?? 0) + t.netPnl;
    }
    return m;
  }

  // P&L grouped by exchange (from matched closed trades)
  Map<String, double> get pnlByExchange {
    final m = <String, double>{};
    for (final t in _ledger.closed) {
      final ex = t.exchange.isEmpty ? _exchFromSymbol(t.symbol) : t.exchange;
      m[ex] = (m[ex] ?? 0) + t.netPnl;
    }
    return m;
  }

  Map<int, double> get volByHour => _ledger.volumeByHour;

  // Daily admin P&L from real matched trades
  Map<DateTime, double> get dailyAdminPnl => _ledger.dailyAdminPnl;

  // Cumulative equity curve from real daily admin P&L
  List<FlSpot> get equityCurve {
    final curve = _ledger.equityCurve;
    if (curve.isEmpty) return [const FlSpot(0, 0)];
    return [
      for (int i = 0; i < curve.length; i++)
        FlSpot(i.toDouble(), curve[i].cumulative),
    ];
  }

  List<MapEntry<String, double>> get topLosers => (pnlBySymbol.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value)))
      .take(5)
      .toList();

  List<MapEntry<String, double>> get topWinners => (pnlBySymbol.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(5)
      .toList();

  String get topLosingSegment {
    final m = pnlByExchange;
    if (m.isEmpty) return 'N/A';
    return m.entries.reduce((a, b) => a.value < b.value ? a : b).key;
  }

  String get topProfitSegment {
    final m = pnlByExchange;
    if (m.isEmpty) return 'N/A';
    return m.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  List<_AlertData> get alerts {
    final out = <_AlertData>[];
    for (final e in pnlBySymbol.entries) {
      if (e.value < -20000) {
        out.add(_AlertData('LOSS', '${e.key}: loss ₹${_f(e.value.abs())}', true));
      }
    }
    for (final e in pnlByUser.entries) {
      if (e.value > 50000) {
        out.add(_AlertData('USER', '${e.key} profitable: ₹${_f(e.value)}', false));
      }
    }
    if (exposure > 10000000) {
      out.add(_AlertData('EXPOSURE', 'Exposure ₹${_f(exposure)} above threshold', true));
    }
    if (netAdminPnl < -100000) {
      out.add(_AlertData('P&L', 'Net admin P&L is negative: ₹${_f(netAdminPnl.abs())}', true));
    }
    return out;
  }

  static String _exchFromSymbol(String sym) {
    const mcx = {'GOLD', 'SILVER', 'CRUDE', 'CRUDEOIL', 'NATURALGAS',
        'COPPER', 'ZINC', 'LEAD', 'NICKEL', 'ALUMINIUM'};
    final u = sym.toUpperCase();
    if (mcx.any(u.startsWith)) return 'MCX';
    if (u.startsWith('NIFTY') || u.startsWith('BANKNIFTY') || u.startsWith('SENSEX')) {
      return 'NSE F&O';
    }
    return 'NSE';
  }

  // Kept for filter-bar exchange matching
  static String _exchange(String sym) => _exchFromSymbol(sym);

  static String _f(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _AlertData {
  final String tag, message;
  final bool isHigh;
  const _AlertData(this.tag, this.message, this.isHigh);
}

// ── Main Screen ────────────────────────────────────────────────────────────────

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen>
    with TickerProviderStateMixin {
  int _days = 7; // filter: 7/30/90/-1(all)
  String _exchange = 'ALL';
  late final TabController _chartTab;
  late final TabController _breakdownTab;

  @override
  void initState() {
    super.initState();
    _chartTab = TabController(length: 3, vsync: this);
    _breakdownTab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _chartTab.dispose();
    _breakdownTab.dispose();
    super.dispose();
  }

  _Analytics _buildAnalytics(List<AdminOrderRecord> allOrders) {
    final now = DateTime.now();
    final cutoff = _days > 0 ? now.subtract(Duration(days: _days)) : null;

    var orders = allOrders.where((o) {
      if (cutoff != null && o.dateTime.isBefore(cutoff)) return false;
      if (_exchange != 'ALL') {
        return _Analytics._exchange(o.symbol) == _exchange;
      }
      return true;
    }).toList();

    return _Analytics(orders);
  }

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    final an = _buildAnalytics(store.masterOrderBook.toList());
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _FilterBar(
            days: _days,
            exchange: _exchange,
            onDays: (v) => setState(() => _days = v),
            onExchange: (v) => setState(() => _exchange = v),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Summary Cards ──────────────────────────────────────────
                  _SectionTitle('Business Overview', LucideIcons.barChart2),
                  const SizedBox(height: 8),
                  _SummaryGrid(an: an, isWide: isWide),
                  const SizedBox(height: 20),

                  // ── P&L Breakdown ──────────────────────────────────────────
                  _SectionTitle('P&L Breakdown', LucideIcons.dollarSign),
                  const SizedBox(height: 8),
                  _PnlBreakdownCard(an: an),
                  const SizedBox(height: 20),

                  // ── Charts ─────────────────────────────────────────────────
                  _SectionTitle('Charts', LucideIcons.trendingUp),
                  const SizedBox(height: 8),
                  _ChartSection(an: an, tabController: _chartTab),
                  const SizedBox(height: 20),

                  // ── Breakdown ──────────────────────────────────────────────
                  _SectionTitle('Segmented Analytics', LucideIcons.layers),
                  const SizedBox(height: 8),
                  _BreakdownSection(an: an, tabController: _breakdownTab),
                  const SizedBox(height: 20),

                  // ── Risk + Alerts ──────────────────────────────────────────
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _RiskCard(an: an, store: store)),
                        const SizedBox(width: 16),
                        Expanded(child: _AlertsCard(an: an)),
                      ],
                    )
                  else ...[
                    _SectionTitle('Risk Analytics', LucideIcons.shieldAlert),
                    const SizedBox(height: 8),
                    _RiskCard(an: an, store: store),
                    const SizedBox(height: 20),
                    _SectionTitle('Alerts', LucideIcons.bell),
                    const SizedBox(height: 8),
                    _AlertsCard(an: an),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Bar ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final int days;
  final String exchange;
  final ValueChanged<int> onDays;
  final ValueChanged<String> onExchange;

  const _FilterBar({
    required this.days,
    required this.exchange,
    required this.onDays,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Analytics',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          for (final (label, value) in [
            ('7D', 7),
            ('30D', 30),
            ('90D', 90),
            ('All', -1),
          ])
            _Chip(
              label: label,
              selected: days == value,
              onTap: () => onDays(value),
            ),
          const SizedBox(width: 8),
          for (final ex in ['ALL', 'NSE', 'NSE F&O', 'MCX'])
            _Chip(
              label: ex,
              selected: exchange == ex,
              onTap: () => onExchange(ex),
              isExchange: true,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isExchange;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isExchange = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isExchange ? AppColors.accent : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Summary Cards Grid ─────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final _Analytics an;
  final bool isWide;

  const _SummaryGrid({required this.an, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _CardData('Total Orders',    '${an.totalOrders}',    LucideIcons.clipboardList,  AppColors.primary,              null),
      _CardData('Executed',        '${an.executedOrders}', LucideIcons.checkCircle,    AppColors.success,              null),
      _CardData('Closed Trades',   '${an.closedTrades}',   LucideIcons.checkCircle2,   const Color(0xFF00897B),        null),
      _CardData('Active Users',    '${an.activeUsers}',    LucideIcons.users,          const Color(0xFF7B1FA2),        null),
      _CardData('Win Rate',        '${(an.winRatio * 100).toStringAsFixed(1)}%', LucideIcons.target, AppColors.success, null),
      _CardData('Total Volume',    _f(an.volume),          LucideIcons.trendingUp,     AppColors.primary,              null),
      _CardData(
        'Net Admin P&L',
        '${an.netAdminPnl >= 0 ? '+' : '-'}₹${_f(an.netAdminPnl.abs())}',
        an.netAdminPnl >= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
        an.netAdminPnl >= 0 ? AppColors.success : AppColors.danger,
        an.netAdminPnl,
      ),
      _CardData('Brokerage',       '₹${_f(an.brokerageEarned)}', LucideIcons.coins,  const Color(0xFF00838F),        null),
      _CardData('Exposure',        '₹${_f(an.exposure)}',  LucideIcons.zap,            AppColors.warning,              null),
      _CardData('User Profits Paid','-₹${_f(an.userProfitPaid)}', LucideIcons.arrowDownLeft, AppColors.danger,        null),
      _CardData('Top Losing Seg.', an.topLosingSegment,    LucideIcons.xCircle,        AppColors.danger,               null),
      _CardData('Top Profit Seg.', an.topProfitSegment,    LucideIcons.award,          AppColors.success,              null),
    ];

    final cols = isWide ? 4 : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisExtent: 96,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => _SummaryCard(data: cards[i]),
    );
  }

  static String _f(double v) => _Analytics._f(v.abs());
}

class _CardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final double? rawValue;
  const _CardData(this.label, this.value, this.icon, this.color, this.rawValue);
}

class _SummaryCard extends StatelessWidget {
  final _CardData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(data.icon, size: 14, color: data.color),
              ),
              const Spacer(),
              if (data.rawValue != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (data.rawValue! >= 0 ? AppColors.success : AppColors.danger).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    data.rawValue! >= 0 ? '↑' : '↓',
                    style: TextStyle(
                      fontSize: 10,
                      color: data.rawValue! >= 0 ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: data.rawValue != null
                  ? (data.rawValue! >= 0 ? AppColors.success : AppColors.danger)
                  : AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            data.label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── P&L Breakdown ──────────────────────────────────────────────────────────────

class _PnlBreakdownCard extends StatelessWidget {
  final _Analytics an;
  const _PnlBreakdownCard({required this.an});

  @override
  Widget build(BuildContext context) {
    // Only real, computable lines — no synthetic slippage or spread estimates.
    final rows = [
      ('+', 'Brokerage Collected (0.03%/leg)', an.brokerageEarned, AppColors.success),
      ('-', 'User Profits Paid Out',            an.userProfitPaid,   AppColors.danger),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: r.$4.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        r.$1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: r.$4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '₹${_Analytics._f(r.$3)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: r.$4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.border,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Net Admin P&L',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${an.netAdminPnl >= 0 ? '+' : '-'}₹${_Analytics._f(an.netAdminPnl.abs())}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: an.netAdminPnl >= 0 ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charts Section ─────────────────────────────────────────────────────────────

class _ChartSection extends StatelessWidget {
  final _Analytics an;
  final TabController tabController;

  const _ChartSection({required this.an, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TabBar(
            controller: tabController,
            tabs: const [
              Tab(text: 'Equity Curve'),
              Tab(text: 'P&L Trend'),
              Tab(text: 'Top Symbols'),
            ],
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 280,
            child: TabBarView(
              controller: tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                  child: _EquityCurveChart(spots: an.equityCurve),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                  child: _PnlTrendChart(dailyPnl: an.dailyAdminPnl),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                  child: _TopSymbolsChart(
                    losers: an.topLosers,
                    winners: an.topWinners,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquityCurveChart extends StatelessWidget {
  final List<FlSpot> spots;
  const _EquityCurveChart({required this.spots});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty || (spots.length == 1 && spots.first.y == 0)) {
      return const Center(
        child: Text(
          'No executed orders yet.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final maxY = spots.map((s) => s.y).reduce(max);
    final minY = spots.map((s) => s.y).reduce(min);
    final isPositive = spots.last.y >= 0;
    final lineColor = isPositive ? AppColors.success : AppColors.danger;

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: lineColor,
            barWidth: 2,
            dotData: FlDotData(show: spots.length <= 7),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withOpacity(0.08),
            ),
          ),
        ],
        minY: minY - (maxY - minY).abs() * 0.1,
        maxY: maxY + (maxY - minY).abs() * 0.1,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, _) => Text(
                '₹${_Analytics._f(v)}',
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Text(
                'D${v.toInt() + 1}',
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
              interval: max(1, (spots.length / 5).floorToDouble()),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: max(1, (maxY - minY) / 4),
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '₹${_Analytics._f(s.y)}',
                      TextStyle(
                        color: s.y >= 0 ? AppColors.success : AppColors.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _PnlTrendChart extends StatelessWidget {
  final Map<DateTime, double> dailyPnl;
  const _PnlTrendChart({required this.dailyPnl});

  @override
  Widget build(BuildContext context) {
    if (dailyPnl.isEmpty) {
      return const Center(
        child: Text(
          'No data for selected range.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final sorted = dailyPnl.keys.toList()..sort();
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < sorted.length; i++) {
      final v = dailyPnl[sorted[i]]!;
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: v,
            color: v >= 0 ? AppColors.success : AppColors.danger,
            width: max(4, min(18, 280 / sorted.length)).toDouble(),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
      ));
    }

    final maxAbs = dailyPnl.values.map((v) => v.abs()).fold(0.0, max);
    final fmt = DateFormat('d/M');

    return BarChart(
      BarChartData(
        barGroups: groups,
        maxY: maxAbs * 1.2,
        minY: -maxAbs * 1.2,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                '₹${_Analytics._f(v)}',
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= sorted.length) return const SizedBox.shrink();
                if (sorted.length > 10 && idx % 3 != 0) return const SizedBox.shrink();
                return Text(
                  fmt.format(sorted[idx]),
                  style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '₹${_Analytics._f(rod.toY)}',
              TextStyle(
                color: rod.toY >= 0 ? AppColors.success : AppColors.danger,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopSymbolsChart extends StatelessWidget {
  final List<MapEntry<String, double>> losers;
  final List<MapEntry<String, double>> winners;

  const _TopSymbolsChart({required this.losers, required this.winners});

  @override
  Widget build(BuildContext context) {
    if (losers.isEmpty && winners.isEmpty) {
      return const Center(
        child: Text(
          'No symbol data.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final all = <MapEntry<String, double>>[...winners, ...losers];
    final unique = <String, double>{};
    for (final e in all) { unique[e.key] = e.value; }

    final sorted = unique.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();

    return SingleChildScrollView(
      child: Column(
        children: top.map((e) {
          final isPos = e.value >= 0;
          final maxAbs = top.map((e) => e.value.abs()).fold(0.01, max);
          final ratio = e.value.abs() / maxAbs;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    e.key.length > 8 ? '${e.key.substring(0, 8)}…' : e.key,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(
                        isPos ? AppColors.success : AppColors.danger,
                      ),
                      minHeight: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 60,
                  child: Text(
                    '₹${_Analytics._f(e.value.abs())}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isPos ? AppColors.success : AppColors.danger,
                    ),
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

// ── Breakdown Section ──────────────────────────────────────────────────────────

class _BreakdownSection extends StatelessWidget {
  final _Analytics an;
  final TabController tabController;

  const _BreakdownSection({required this.an, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: tabController,
            tabs: const [
              Tab(text: 'By Exchange'),
              Tab(text: 'By Symbol'),
              Tab(text: 'By User'),
            ],
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: tabController,
              children: [
                _BreakdownTable(
                  data: an.pnlByExchange,
                  labelHeader: 'Exchange',
                ),
                _BreakdownTable(
                  data: Map.fromEntries(
                    (an.pnlBySymbol.entries.toList()
                          ..sort((a, b) => b.value.abs().compareTo(a.value.abs())))
                        .take(20),
                  ),
                  labelHeader: 'Symbol',
                ),
                _BreakdownTable(
                  data: Map.fromEntries(
                    (an.pnlByUser.entries.toList()
                          ..sort((a, b) => b.value.abs().compareTo(a.value.abs())))
                        .take(20),
                  ),
                  labelHeader: 'User',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownTable extends StatelessWidget {
  final Map<String, double> data;
  final String labelHeader;

  const _BreakdownTable({required this.data, required this.labelHeader});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  labelHeader,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Expanded(
                flex: 2,
                child: Text(
                  'P&L',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Expanded(
                flex: 2,
                child: Text(
                  'Direction',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              final isPos = e.value >= 0;
              final maxAbs = entries.map((x) => x.value.abs()).fold(0.01, max);
              final ratio = e.value.abs() / maxAbs;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${isPos ? '+' : '-'}₹${_Analytics._f(e.value.abs())}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isPos ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation(
                              isPos ? AppColors.success : AppColors.danger,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Risk Analytics ─────────────────────────────────────────────────────────────

class _RiskCard extends StatelessWidget {
  final _Analytics an;
  final AdminStore store;

  const _RiskCard({required this.an, required this.store});

  @override
  Widget build(BuildContext context) {
    // Max drawdown estimate: max peak-to-trough from equity curve
    final spots = an.equityCurve;
    double maxDrawdown = 0;
    double peak = double.negativeInfinity;
    for (final s in spots) {
      if (s.y > peak) peak = s.y;
      final dd = peak - s.y;
      if (dd > maxDrawdown) maxDrawdown = dd;
    }

    final highRiskUsers = store.highestRiskOrders
        .map((o) => o.userId)
        .toSet()
        .take(5)
        .toList();

    final unhedgedExposure = an.exposure * 0.7; // estimate

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.shieldAlert, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Risk Analytics',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _riskRow('Open Exposure', '₹${_Analytics._f(an.exposure)}', AppColors.warning),
          _riskRow('Unhedged Positions', '₹${_Analytics._f(unhedgedExposure)}', AppColors.warning),
          _riskRow('Max Drawdown', '₹${_Analytics._f(maxDrawdown)}', AppColors.danger),
          _riskRow('Operator Risk Est.', '₹${_Analytics._f(store.operatorRiskLossEstimate)}', AppColors.danger),
          const SizedBox(height: 10),
          Text(
            'High Risk Users',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (highRiskUsers.isEmpty)
            const Text(
              'None detected',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: highRiskUsers.map((uid) {
                final short = uid.length > 6 ? '${uid.substring(0, 6)}…' : uid;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Text(
                    short,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _riskRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alerts Widget ──────────────────────────────────────────────────────────────

class _AlertsCard extends StatelessWidget {
  final _Analytics an;
  const _AlertsCard({required this.an});

  @override
  Widget build(BuildContext context) {
    final alerts = an.alerts;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.bell, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Smart Alerts',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              if (alerts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${alerts.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (alerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'All clear — no alerts triggered.',
                    style: TextStyle(fontSize: 12, color: AppColors.success),
                  ),
                ],
              ),
            )
          else
            ...alerts.map((a) {
              final color = a.isHigh ? AppColors.danger : AppColors.warning;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      a.isHigh ? Icons.warning_rounded : Icons.info_outline,
                      color: color,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              a.tag,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            a.message,
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ],
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

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
