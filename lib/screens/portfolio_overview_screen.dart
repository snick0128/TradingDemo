import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart' hide Position;

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class PortfolioOverviewScreen extends StatelessWidget {
  final bool showAppBar;

  const PortfolioOverviewScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final holdings = store.holdings;
    final positions = store.positions;
    final balance = store.balance;

    final body = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NetWorthCard(
              holdings: holdings,
              positions: positions,
              balance: balance,
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SectorAllocationChart(holdings: holdings),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: _MarketCapBreakdownChart()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _SectorAllocationChart(holdings: holdings),
                    const SizedBox(height: 24),
                    _MarketCapBreakdownChart(),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _RiskMetricsCard(),
            const SizedBox(height: 24),
            _BenchmarkComparisonChart(),
            const SizedBox(height: 24),
            _PnlCalendarHeatmap(),
          ],
        ),
      ),
    );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio Overview')),
      body: body,
    );
  }
}

// ─── Net Worth Card ───────────────────────────────────────────────────────────

class _NetWorthCard extends StatelessWidget {
  final List<Holding> holdings;
  final List<Position> positions;
  final double balance;

  const _NetWorthCard({
    required this.holdings,
    required this.positions,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final holdingsValue = holdings.fold(0.0, (s, h) => s + h.currentValue);
    final positionsValue = positions.fold(
      0.0,
      (s, p) => s + (p.quantity * p.currentPrice),
    );
    final netWorth = holdingsValue + positionsValue + balance;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF5A9FE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.wallet, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Total Net Worth',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₹${netWorth.toStringAsFixed(2)}',
            style: AppTheme.tabular(
              const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _netWorthBreakdown(
                  'Holdings',
                  holdingsValue,
                  LucideIcons.briefcase,
                ),
              ),
              Expanded(
                child: _netWorthBreakdown(
                  'Positions',
                  positionsValue,
                  LucideIcons.trendingUp,
                ),
              ),
              Expanded(
                child: _netWorthBreakdown(
                  'Cash',
                  balance,
                  LucideIcons.banknote,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _netWorthBreakdown(String label, double value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '₹${value.toStringAsFixed(0)}',
          style: AppTheme.tabular(
            const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sector Allocation Chart ──────────────────────────────────────────────────

class _SectorAllocationChart extends StatelessWidget {
  final List<Holding> holdings;

  const _SectorAllocationChart({required this.holdings});

  @override
  Widget build(BuildContext context) {
    // Mock sector mapping
    final sectorMap = {
      'RELIANCE': 'Energy',
      'TCS': 'IT',
      'INFY': 'IT',
      'HDFC': 'Finance',
      'ICICI': 'Finance',
      'WIPRO': 'IT',
      'SBIN': 'Finance',
      'BHARTI': 'Telecom',
      'ITC': 'FMCG',
      'HIND': 'Auto',
    };

    final sectorData = <String, double>{};
    for (final h in holdings) {
      final sector = sectorMap[h.symbol] ?? 'Others';
      sectorData[sector] = (sectorData[sector] ?? 0) + h.currentValue;
    }

    final chartData = sectorData.entries
        .map((e) => _ChartData(e.key, e.value))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sector Allocation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: chartData.isEmpty
                ? const Center(
                    child: Text(
                      'No holdings data',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : SfCircularChart(
                    legend: const Legend(
                      isVisible: true,
                      position: LegendPosition.bottom,
                      overflowMode: LegendItemOverflowMode.wrap,
                    ),
                    series: <CircularSeries>[
                      DoughnutSeries<_ChartData, String>(
                        dataSource: chartData,
                        xValueMapper: (_ChartData data, _) => data.label,
                        yValueMapper: (_ChartData data, _) => data.value,
                        innerRadius: '60%',
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: true,
                          labelPosition: ChartDataLabelPosition.outside,
                          textStyle: TextStyle(fontSize: 10),
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

// ─── Market Cap Breakdown Chart ───────────────────────────────────────────────

class _MarketCapBreakdownChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Mock market cap data
    final chartData = [
      _ChartData('Large Cap', 60.0),
      _ChartData('Mid Cap', 25.0),
      _ChartData('Small Cap', 15.0),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Market Cap Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: SfCircularChart(
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.bottom,
              ),
              series: <CircularSeries>[
                DoughnutSeries<_ChartData, String>(
                  dataSource: chartData,
                  xValueMapper: (_ChartData data, _) => data.label,
                  yValueMapper: (_ChartData data, _) => data.value,
                  innerRadius: '60%',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    textStyle: TextStyle(fontSize: 10),
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

// ─── Risk Metrics Card ────────────────────────────────────────────────────────

class _RiskMetricsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Mock data
    const beta = 1.05;
    const sharpe = 1.2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risk Metrics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metricTile(
                  'Beta',
                  beta.toStringAsFixed(2),
                  'Volatility vs market',
                  LucideIcons.activity,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricTile(
                  'Sharpe Ratio',
                  sharpe.toStringAsFixed(2),
                  'Risk-adjusted return',
                  LucideIcons.target,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(
    String label,
    String value,
    String subtitle,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.tabular(
              const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Benchmark Comparison Chart ───────────────────────────────────────────────

class _BenchmarkComparisonChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Mock data: portfolio vs NIFTY 50
    final portfolioData = List.generate(
      30,
      (i) => _TimeSeriesData(
        DateTime.now().subtract(Duration(days: 29 - i)),
        100000 + (i * 500) + (i % 3 == 0 ? 200 : -100),
      ),
    );

    final niftyData = List.generate(
      30,
      (i) => _TimeSeriesData(
        DateTime.now().subtract(Duration(days: 29 - i)),
        100000 + (i * 400) + (i % 2 == 0 ? 150 : -80),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Benchmark Comparison',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Portfolio vs NIFTY 50 (Last 30 days)',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: SfCartesianChart(
              enableAxisAnimation: false,
              primaryXAxis: const DateTimeAxis(
                majorGridLines: MajorGridLines(width: 0),
              ),
              primaryYAxis: const NumericAxis(axisLine: AxisLine(width: 0)),
              legend: const Legend(isVisible: true),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                LineSeries<_TimeSeriesData, DateTime>(
                  name: 'Portfolio',
                  dataSource: portfolioData,
                  xValueMapper: (_TimeSeriesData data, _) => data.date,
                  yValueMapper: (_TimeSeriesData data, _) => data.value,
                  color: AppColors.primary,
                  width: 2,
                  animationDuration: 0,
                ),
                LineSeries<_TimeSeriesData, DateTime>(
                  name: 'NIFTY 50',
                  dataSource: niftyData,
                  xValueMapper: (_TimeSeriesData data, _) => data.date,
                  yValueMapper: (_TimeSeriesData data, _) => data.value,
                  color: AppColors.textSecondary,
                  width: 2,
                  dashArray: const <double>[5, 5],
                  animationDuration: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── P&L Calendar Heatmap ─────────────────────────────────────────────────────

class _PnlCalendarHeatmap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    // Mock daily P&L data
    final dailyPnl = List.generate(
      daysInMonth,
      (i) => (i % 3 == 0 ? 1 : -1) * (100 + (i * 50)),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'P&L Calendar Heatmap',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Daily gain/loss for ${_monthName(now.month)} ${now.year}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(daysInMonth, (i) {
              final day = i + 1;
              final pnl = dailyPnl[i];
              final isPositive = pnl >= 0;
              final color = isPositive ? AppColors.success : AppColors.danger;
              final intensity = (pnl.abs() / 500).clamp(0.2, 1.0);

              return Tooltip(
                message:
                    'Day $day: ${isPositive ? '+' : ''}₹${pnl.toStringAsFixed(0)}',
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(intensity),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: intensity > 0.6 ? Colors.white : color,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}

// ─── Helper Classes ───────────────────────────────────────────────────────────

class _ChartData {
  final String label;
  final double value;

  _ChartData(this.label, this.value);
}

class _TimeSeriesData {
  final DateTime date;
  final double value;

  _TimeSeriesData(this.date, this.value);
}
