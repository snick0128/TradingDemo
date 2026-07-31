import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/instrument_logo.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';

class HoldingsScreen extends StatefulWidget {
  final bool showAppBar;

  const HoldingsScreen({super.key, this.showAppBar = true});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  TradingStore? _store;
  List<Holding> _holdings = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.positionsVersion.removeListener(_onHoldingsChanged);
      _store = store;
      store.positionsVersion.addListener(_onHoldingsChanged);
      _holdings = store.holdings;
    }
  }

  void _onHoldingsChanged() {
    if (mounted) setState(() => _holdings = _store!.holdings);
  }

  @override
  void dispose() {
    _store?.positionsVersion.removeListener(_onHoldingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use .of() for structural store state (backendError, knownStocks connectivity)
    // so the shimmer clears on first data load. Price ticks never call
    // notifyListeners(), so this doesn't add per-tick rebuilds.
    final store = TradingScope.of(context);
    final holdings = _holdings;

    // Shimmer while market data hasn't arrived yet
    if (store.knownStocks.isEmpty && !store.backendError) {
      final shimmerBody = ShimmerWrapper(
        child: Column(
          children: [
            // Summary strip skeleton
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.surface,
              child: Row(
                children: const [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ShimmerRect(width: 70, height: 11), SizedBox(height: 6), ShimmerRect(width: 110, height: 18),
                  ])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    ShimmerRect(width: 60, height: 11), SizedBox(height: 6), ShimmerRect(width: 90, height: 18),
                  ])),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: 8,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                itemBuilder: (_, __) => const ShimmerHoldingTile(),
              ),
            ),
          ],
        ),
      );
      if (!showAppBar) return shimmerBody;
      return Scaffold(
        appBar: AppBar(title: const Text('Holdings')),
        body: shimmerBody,
      );
    }

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
    final isPos = totalPnl >= 0;
    final pnlPct = totalInv == 0 ? 0.0 : (totalPnl / totalInv) * 100;
    final arrow = isPos ? '▲' : '▼';
    final pnlColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          // Top 2-col grid
          Row(
            children: [
              Expanded(
                child: _statCell(
                  'Total investment',
                  '₹${totalInv.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _statCell(
                  'Current value',
                  '₹${totalCur.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          const SizedBox(height: 12),
          // Full-width P&L row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total P&L',
                style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
              ),
              Row(
                children: [
                  Text(
                    '$arrow ₹${totalPnl.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: pnlColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPos
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$arrow ${pnlPct.abs().toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pnlColor,
                      ),
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

  Widget _statCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D0D0D),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
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

  Color _avatarColor(String symbol) {
    const colors = [
      Color(0xFF1565C0),
      Color(0xFF00695C),
      Color(0xFF6A1B9A),
      Color(0xFFAD1457),
      Color(0xFF558B2F),
      Color(0xFFE65100),
    ];
    return colors[symbol.codeUnitAt(0) % colors.length];
  }

  String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final isPos = h.pnl >= 0;
    final pnlColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final pnlBg = isPos ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final avatarColor = _avatarColor(h.symbol);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + symbol/name + Sell button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InstrumentLogo(
                  symbol: h.symbol,
                  size: 34,
                  fallbackBuilder: (_) => Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      h.symbol.isNotEmpty ? h.symbol[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.symbol,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D0D0D),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        h.name,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF757575),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _openSellDrawer(context, h),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD50000)),
                    ),
                    child: const Text(
                      'Sell',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFD50000),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Qty · avg → ltp
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Text(
                  '${h.quantity} qty',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF757575)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('·',
                      style: TextStyle(color: Color(0xFF9E9E9E))),
                ),
                Text(
                  'Avg ₹${h.avgPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF757575)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward,
                      size: 11, color: Color(0xFF9E9E9E)),
                ),
                Text(
                  'LTP ₹${h.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0D0D0D),
                  ),
                ),
              ],
            ),
          ),
          // Bottom band: Invested | Current | P&L
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              children: [
                _statMini('Invested', '₹${_compact(h.investedValue)}'),
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFFE0E0E0),
                ),
                _statMini('Current', '₹${_compact(h.currentValue)}'),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: pnlBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isPos ? '+' : ''}₹${h.pnl.abs().toStringAsFixed(2)}'
                    '  (${isPos ? '+' : ''}${h.pnlPercentage.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: pnlColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statMini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF9E9E9E))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D0D0D))),
      ],
    );
  }

  void _openSellDrawer(BuildContext context, Holding h) {
    final store = TradingScope.of(context);
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

    OrderFormSheet.show(context, stock: stock, initialSide: OrderType.sell);
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

    final totalDiv = holdings.fold(
      0.0,
      (s, h) => s + (h.dividendReceived ?? 0),
    );

    // Guard: values beyond ±999% are meaningless (insufficient data)
    final xirrValid = xirr.abs() <= 999;
    final cagrValid = cagr.abs() <= 999;

    final xirrPos = xirr >= 0;
    final cagrPos = cagr >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Portfolio analytics',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0D0D0D),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Values are approximate',
              child: const Icon(
                Icons.info_outline,
                size: 14,
                color: Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Use Wrap instead of GridView so cards size to their content
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _AnalyticsCard(
                    icon: LucideIcons.trendingUp,
                    label: 'XIRR',
                    value: xirrValid
                        ? '${xirrPos ? '+' : ''}${xirr.toStringAsFixed(2)}%'
                        : 'N/A',
                    valueColor: !xirrValid
                        ? const Color(0xFF9E9E9E)
                        : (xirrPos
                              ? const Color(0xFF00C853)
                              : const Color(0xFFD50000)),
                    insufficientData: !xirrValid,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _AnalyticsCard(
                    icon: LucideIcons.barChart2,
                    label: 'CAGR',
                    value: cagrValid
                        ? '${cagrPos ? '+' : ''}${cagr.toStringAsFixed(2)}%'
                        : 'N/A',
                    valueColor: !cagrValid
                        ? const Color(0xFF9E9E9E)
                        : (cagrPos
                              ? const Color(0xFF00C853)
                              : const Color(0xFFD50000)),
                    insufficientData: !cagrValid,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _AnalyticsCard(
                    icon: LucideIcons.dollarSign,
                    label: 'Total Dividends',
                    value: '₹${totalDiv.toStringAsFixed(2)}',
                    valueColor: totalDiv == 0
                        ? const Color(0xFF757575)
                        : const Color(0xFF1565C0),
                  ),
                ),
              ],
            );
          },
        ),
        if (holdings.any((h) => (h.dividendReceived ?? 0) > 0)) ...[
          const SizedBox(height: 24),
          _DividendTable(
            holdings: holdings
                .where((h) => (h.dividendReceived ?? 0) > 0)
                .toList(),
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final bool insufficientData;

  const _AnalyticsCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    this.insufficientData = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF757575)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (insufficientData)
            const Text(
              'Insufficient data for this period',
              style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
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
                color: AppColors.surfaceAlt.withOpacity(0.3),
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
