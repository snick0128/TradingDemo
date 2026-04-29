import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_drawer.dart';

class HoldingsScreen extends StatelessWidget {
  final bool showAppBar;

  const HoldingsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final holdings = store.holdings;

    final body = SingleChildScrollView(
      child: Column(
        children: [
          _SummaryStrip(holdings: holdings),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _HoldingsTable(holdings: holdings),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: _AllocationSection(holdings: holdings),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _HoldingsTable(holdings: holdings),
                    const SizedBox(height: 24),
                    _AllocationSection(holdings: holdings),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _AnalyticsSection(holdings: holdings),
          ),
        ],
      ),
    );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Holdings')),
      body: body,
    );
  }
}

// ─── Summary Strip ────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final List<Holding> holdings;

  const _SummaryStrip({required this.holdings});

  @override
  Widget build(BuildContext context) {
    final totalInv = holdings.fold(0.0, (s, h) => s + h.investedValue);
    final totalCur = holdings.fold(0.0, (s, h) => s + h.currentValue);
    final totalPnl = totalCur - totalInv;
    final totalDiv = holdings.fold(
      0.0,
      (s, h) => s + (h.dividendReceived ?? 0),
    );
    final isPos = totalPnl >= 0;
    final pnlPct = totalInv == 0 ? 0.0 : (totalPnl / totalInv) * 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Theme.of(context).colorScheme.surface,
      child: Wrap(
        spacing: 48,
        runSpacing: 16,
        children: [
          _stat(
            'Total investment',
            '₹${totalInv.toStringAsFixed(2)}',
            AppColors.textPrimary,
          ),
          _stat(
            'Current value',
            '₹${totalCur.toStringAsFixed(2)}',
            AppColors.textPrimary,
          ),
          _stat(
            'Total P&L',
            '${isPos ? '+' : ''}₹${totalPnl.abs().toStringAsFixed(2)}',
            isPos ? AppColors.success : AppColors.danger,
            sub: '${isPos ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
          ),
          if (totalDiv > 0)
            _stat(
              'Dividends received',
              '₹${totalDiv.toStringAsFixed(2)}',
              AppColors.primary,
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, {String? sub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTheme.tabular(
                TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (sub != null) ...[
              const SizedBox(width: 8),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─── Holdings Table ───────────────────────────────────────────────────────────

class _HoldingsTable extends StatelessWidget {
  final List<Holding> holdings;

  const _HoldingsTable({required this.holdings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Holdings (${holdings.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (holdings.isEmpty)
          _emptyState()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: holdings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _HoldingCard(holding: holdings[index]),
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Column(
        children: [
          Icon(LucideIcons.briefcase, size: 48, color: AppColors.border),
          SizedBox(height: 16),
          Text(
            "You don't have any holdings yet",
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Holding Card ─────────────────────────────────────────────────────────────

class _HoldingCard extends StatelessWidget {
  final Holding holding;

  const _HoldingCard({required this.holding});

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final isPos = h.pnl >= 0;
    final pnlColor = isPos ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: symbol + name + sell button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      h.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _openSellDrawer(context, h),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Sell'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Middle row: Qty + Avg
          Text(
            'Qty: ${h.quantity}  •  Avg: ₹${h.avgPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // Bottom row: LTP + P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LTP: ₹${h.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '(${isPos ? '+' : ''}${h.pnlPercentage.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: pnlColor,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'P&L: ${isPos ? '+' : ''}₹${h.pnl.abs().toStringAsFixed(2)}',
                    style: AppTheme.tabular(
                      TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: pnlColor,
                      ),
                    ),
                  ),
                  Text(
                    '(${isPos ? '+' : ''}${h.pnlPercentage.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: pnlColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSellDrawer(BuildContext context, Holding h) {
    final store = TradingScope.of(context);
    // Look up the stock from the watchlist; fall back to a synthetic Stock from holding data
    Stock stock;
    try {
      stock = store.stockBySymbol(h.symbol);
    } catch (_) {
      stock = Stock(
        symbol: h.symbol,
        name: h.name,
        currentPrice: h.currentPrice,
        changePercentage: h.pnlPercentage,
        sector: '',
      );
    }

    Scaffold.of(context).openEndDrawer();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Sell',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: OrderFormDrawer(stock: stock, initialSide: OrderType.sell),
      ),
    );
  }
}

// ─── Allocation Section ───────────────────────────────────────────────────────

class _AllocationSection extends StatelessWidget {
  final List<Holding> holdings;

  const _AllocationSection({required this.holdings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Allocation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Container(
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: holdings.isEmpty
              ? const Center(
                  child: Text(
                    'No data',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : SfCircularChart(
                  legend: const Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                  ),
                  series: <CircularSeries>[
                    DoughnutSeries<Holding, String>(
                      dataSource: holdings.toList(),
                      xValueMapper: (Holding h, _) => h.symbol,
                      yValueMapper: (Holding h, _) => h.currentValue,
                      innerRadius: '65%',
                      dataLabelSettings: const DataLabelSettings(
                        isVisible: false,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Analytics Section ────────────────────────────────────────────────────────

class _AnalyticsSection extends StatelessWidget {
  final List<Holding> holdings;

  const _AnalyticsSection({required this.holdings});

  /// Simplified XIRR approximation: total return / years held (weighted by investment)
  double _computeXirr() {
    if (holdings.isEmpty) return 0;
    final now = DateTime.now();
    double weightedReturn = 0;
    double totalInvested = 0;

    for (final h in holdings) {
      final years = now.difference(h.purchaseDate).inDays / 365.0;
      if (years <= 0) continue;
      final invested = h.investedValue;
      final annualReturn =
          h.totalReturn / (invested == 0 ? 1 : invested) / years;
      weightedReturn += annualReturn * invested;
      totalInvested += invested;
    }

    return totalInvested == 0 ? 0 : (weightedReturn / totalInvested) * 100;
  }

  /// CAGR: (currentValue / investedValue)^(1/years) - 1
  double _computeCagr() {
    if (holdings.isEmpty) return 0;
    final now = DateTime.now();
    double totalInvested = 0;
    double totalCurrent = 0;
    double totalYears = 0;
    int count = 0;

    for (final h in holdings) {
      final years = now.difference(h.purchaseDate).inDays / 365.0;
      if (years <= 0) continue;
      totalInvested += h.investedValue;
      totalCurrent += h.currentValue;
      totalYears += years;
      count++;
    }

    if (totalInvested == 0 || count == 0) return 0;
    final avgYears = totalYears / count;
    if (avgYears <= 0) return 0;

    return (pow(totalCurrent / totalInvested, 1 / avgYears) - 1) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final xirr = _computeXirr();
    final cagr = _computeCagr();
    final xirrPos = xirr >= 0;
    final cagrPos = cagr >= 0;

    final totalDiv = holdings.fold(
      0.0,
      (s, h) => s + (h.dividendReceived ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Portfolio Analytics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _AnalyticsCard(
              icon: LucideIcons.trendingUp,
              label: 'XIRR',
              value: '${xirrPos ? '+' : ''}${xirr.toStringAsFixed(2)}%',
              valueColor: xirrPos ? AppColors.success : AppColors.danger,
              subtitle: 'Annualised return (approx.)',
            ),
            _AnalyticsCard(
              icon: LucideIcons.barChart2,
              label: 'CAGR',
              value: '${cagrPos ? '+' : ''}${cagr.toStringAsFixed(2)}%',
              valueColor: cagrPos ? AppColors.success : AppColors.danger,
              subtitle: 'Compound annual growth rate',
            ),
            _AnalyticsCard(
              icon: LucideIcons.dollarSign,
              label: 'Total Dividends',
              value: '₹${totalDiv.toStringAsFixed(2)}',
              valueColor: AppColors.primary,
              subtitle: 'Across all holdings',
            ),
          ],
        ),
        if (holdings.any((h) => (h.dividendReceived ?? 0) > 0)) ...[
          const SizedBox(height: 24),
          _DividendTable(
            holdings: holdings
                .where((h) => (h.dividendReceived ?? 0) > 0)
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String subtitle;

  const _AnalyticsCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
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
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTheme.tabular(
              TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: valueColor,
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

class _DividendTable extends StatelessWidget {
  final List<Holding> holdings;

  const _DividendTable({required this.holdings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dividend Tracking',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              // Header
              Container(
                color: AppColors.surfaceAlt.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Symbol',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Qty',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Dividend received',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...holdings.map(
                (h) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              h.symbol,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${h.quantity}',
                              style: AppTheme.tabular(
                                const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '₹${h.dividendReceived!.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: AppTheme.tabular(
                                const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
