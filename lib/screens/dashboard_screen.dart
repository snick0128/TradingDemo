import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedSymbol = '';
  String _query = '';
  int _selectedRange = 2;
  ChartType _chartType = ChartType.candles;
  bool _showSma20 = true;
  bool _showSma50 = false;
  bool _showVolume = true;
  late final TransformationController _chartTransformController;
  int _mobileVisibleCandles = 34;

  @override
  void initState() {
    super.initState();
    _chartTransformController = TransformationController();
  }

  @override
  void dispose() {
    _chartTransformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final allStocks = store.watchlist;
    final filteredStocks = _filteredStocks(allStocks);
    final isMobile = MediaQuery.of(context).size.width < 760;

    if (allStocks.isEmpty) {
      return const Scaffold(body: Center(child: Text('No symbols available.')));
    }

    final selectedStock = _resolveSelectedStock(
      fallback: allStocks.first,
      all: allStocks,
      filtered: filteredStocks,
    );

    return Scaffold(
      appBar: _buildAppBar(context, store),
      bottomNavigationBar: isMobile ? _buildMobileCtaBar(context, selectedStock) : null,
      body: Container(
        color: AppColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 1150;
            final isTablet = constraints.maxWidth >= 760;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildKpiStrip(context, isTablet),
                  const SizedBox(height: 16),
                  _buildPortfolioSummary(context, store),
                  const SizedBox(height: 16),
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            children: [
                              _buildChartCard(context, selectedStock),
                              const SizedBox(height: 16),
                              _buildDepthAndTape(context, selectedStock, horizontal: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 360,
                          child: _buildWatchlistPanel(context, filteredStocks, selectedStock),
                        ),
                      ],
                    )
                  else ...[
                    _buildChartCard(context, selectedStock, showInlineActions: !isMobile),
                    const SizedBox(height: 16),
                    _buildWatchlistPanel(context, filteredStocks, selectedStock),
                    const SizedBox(height: 16),
                    _buildDepthAndTape(context, selectedStock, horizontal: false),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, TradingStore store) {
    final compact = MediaQuery.of(context).size.width < 760;

    return AppBar(
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
            ),
            child: const Icon(LucideIcons.candlestickChart, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Box Trading Pro',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Live Market Mode',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!compact) ...[
          _smallChip(icon: LucideIcons.activity, label: 'NSE Open', color: AppColors.success),
          const SizedBox(width: 10),
        ],
        IconButton(
          onPressed: () => _openSearchSheet(context),
          icon: const Icon(LucideIcons.search),
        ),
        if (!compact) IconButton(onPressed: () {}, icon: const Icon(LucideIcons.settings2)),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildKpiStrip(BuildContext context, bool isTablet) {
    final store = TradingScope.of(context);
    final pnl = store.totalPnl;
    final pnlPct = store.totalInvestment == 0 ? 0 : (pnl / store.totalInvestment) * 100;
    
    final kpis = [
      _kpiCard(context, 'NIFTY 50', '22,814.65', '+192.15 (0.84%)', AppColors.success, isTablet),
      _kpiCard(context, 'SENSEX', '75,091.11', '+440.23 (0.59%)', AppColors.success, isTablet),
      _kpiCard(context, 'Portfolio P&L', '₹${pnl.abs().toStringAsFixed(0)}', 
               '${pnl >= 0 ? '+' : '-'}${pnlPct.abs().toStringAsFixed(2)}%', 
               pnl >= 0 ? AppColors.success : AppColors.danger, isTablet),
      _kpiCard(context, 'Margin Available', '₹${store.balance.toStringAsFixed(0)}', 
               'Blocked: ₹${store.usedMargin.toStringAsFixed(0)}', 
               AppColors.primary, isTablet),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kpis,
    );
  }

  Widget _kpiCard(BuildContext context, String label, String value, String subValue, Color color, bool isTablet) {
    return SizedBox(
      width: isTablet ? 250 : double.infinity,
      child: CustomCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                Icon(LucideIcons.trendingUp, size: 14, color: color.withValues(alpha: 0.6)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subValue,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildPortfolioSummary(BuildContext context, TradingStore store) {
    final pnl = store.totalPnl;
    final isPos = pnl >= 0;

    return CustomCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _summaryBit('Total Portfolio Value', '₹${store.totalCurrentValue.toStringAsFixed(0)}', context),
          const VerticalDivider(width: 32),
          _summaryBit('Unrealized P&L', '${isPos ? '+' : ''}₹${pnl.abs().toStringAsFixed(0)}', context, color: isPos ? AppColors.success : AppColors.danger),
          const VerticalDivider(width: 32),
          _summaryBit('Funds Available', '₹${store.balance.toStringAsFixed(0)}', context, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _summaryBit(String label, String value, BuildContext context, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildChartCard(
    BuildContext context,
    Stock stock, {
    bool showInlineActions = true,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    final series = TradingChartService.buildSeries(
      symbol: stock.symbol,
      basePrice: stock.currentPrice,
      rangeIndex: _selectedRange,
    );
    final isPositive = series.close >= series.open;

    return CustomCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openStockDetail(context, stock.symbol),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.symbol, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text('${stock.name} • ${stock.sector}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${series.close.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${isPositive ? '+' : ''}${(((series.close - series.open) / series.open) * 100).toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isPositive ? AppColors.success : AppColors.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _rangeLabels.length; i++) _rangeChip(i, _rangeLabels[i]),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Chart settings',
                onPressed: () => _openChartSettings(context),
                icon: const Icon(LucideIcons.slidersHorizontal, size: 18),
              ),
            ],
          ),
          if (isMobile)
            Row(
              children: [
                IconButton(
                  onPressed: _mobileVisibleCandles > 18
                      ? () => setState(() => _mobileVisibleCandles -= 6)
                      : null,
                  icon: const Icon(LucideIcons.zoomIn, size: 16),
                  tooltip: 'Zoom In',
                ),
                IconButton(
                  onPressed: _mobileVisibleCandles < 90
                      ? () => setState(() => _mobileVisibleCandles += 6)
                      : null,
                  icon: const Icon(LucideIcons.zoomOut, size: 16),
                  tooltip: 'Zoom Out',
                ),
                const SizedBox(width: 4),
                Text('Pinch to zoom · Drag to pan', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          const SizedBox(height: 14),
          SizedBox(
            height: 280,
            child: _buildPrimaryChart(series),
          ),
          if (_showVolume) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: _buildVolumeChart(series),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _chartStat('O', series.open),
              _chartStat('H', series.high),
              _chartStat('L', series.low),
              _chartStat('C', series.close),
              _chartLabel('VWAP ${series.vwap.toStringAsFixed(2)}'),
              _chartLabel('RSI14 ${series.rsi14.toStringAsFixed(1)}'),
              _chartLabel('Vol ${(series.volume / 100000).toStringAsFixed(2)}L'),
            ],
          ),
          if (showInlineActions) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openOrderSheet(context, stock.symbol, OrderType.sell),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                    child: const Text('SELL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openOrderSheet(context, stock.symbol, OrderType.buy),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    child: const Text('BUY'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _openStockDetail(context, stock.symbol),
                  icon: const Icon(LucideIcons.expand, size: 16),
                  label: const Text('Detail'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWatchlistPanel(BuildContext context, List<Stock> stocks, Stock selectedStock) {
    return CustomCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Market Watch', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${stocks.length} symbols',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search symbol or company',
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 460,
            child: stocks.isEmpty
                ? Center(
                    child: Text('No symbols match your search.', style: Theme.of(context).textTheme.bodySmall),
                  )
                : ListView.separated(
                    itemCount: stocks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final stock = stocks[index];
                      final selected = stock.symbol == selectedStock.symbol;

                      return InkWell(
                        onTap: () {
                          setState(() => _selectedSymbol = stock.symbol);
                          _openStockDetail(context, stock.symbol);
                        },
                        child: Container(
                          color: selected ? AppColors.surfaceAlt : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  stock.symbol.characters.first,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(stock.symbol, style: Theme.of(context).textTheme.titleMedium),
                                    Text(stock.name, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              PriceText(
                                price: stock.currentPrice,
                                change: stock.changePercentage,
                                isChangePositive: stock.isPositive,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepthAndTape(BuildContext context, Stock stock, {required bool horizontal}) {
    final depth = _orderBook(stock.currentPrice);
    final trades = _recentTrades(stock.currentPrice);

    final orderBookCard = CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Book', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _bookHeader(),
          const SizedBox(height: 8),
          for (final row in depth)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: GoogleFonts.jetBrainsMono(color: AppColors.success, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final tapeCard = CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Trades', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _subHeader('Time', align: TextAlign.left),
              _subHeader('Price', align: TextAlign.center),
              _subHeader('Qty', align: TextAlign.right),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in trades)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1, style: Theme.of(context).textTheme.bodySmall)),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        color: row.$4 ? AppColors.success : AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: orderBookCard),
          const SizedBox(width: 16),
          Expanded(child: tapeCard),
        ],
      );
    }

    return Column(
      children: [
        orderBookCard,
        const SizedBox(height: 16),
        tapeCard,
      ],
    );
  }

  Widget _bookHeader() {
    return Row(
      children: [
        _subHeader('Bid', align: TextAlign.left),
        _subHeader('Qty', align: TextAlign.center),
        _subHeader('Ask', align: TextAlign.right),
      ],
    );
  }

  Widget _subHeader(String label, {required TextAlign align}) {
    return Expanded(
      child: Text(
        label,
        textAlign: align,
        style: GoogleFonts.sora(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _rangeChip(int index, String label) {
    final selected = _selectedRange == index;

    return InkWell(
      onTap: () {
        _chartTransformController.value = Matrix4.identity();
        setState(() => _selectedRange = index);
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: 220.ms,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _smallChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryChart(TradingChartSeries series) {
    if (_chartType == ChartType.candles) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CandlestickChart(
          _buildCandlestickData(series),
          duration: 350.ms,
          transformationConfig: FlTransformationConfig(
            scaleAxis: FlScaleAxis.horizontal,
            minScale: 1,
            maxScale: 7,
            panEnabled: true,
            scaleEnabled: true,
            transformationController: _chartTransformController,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LineChart(
        _buildChartData(series, isArea: _chartType == ChartType.area),
        duration: 350.ms,
        transformationConfig: FlTransformationConfig(
          scaleAxis: FlScaleAxis.horizontal,
          minScale: 1,
          maxScale: 7,
          panEnabled: true,
          scaleEnabled: true,
          transformationController: _chartTransformController,
        ),
      ),
    );
  }

  LineChartData _buildChartData(TradingChartSeries series, {required bool isArea}) {
    final points = series.closeSpots;
    final primaryColor = series.close >= series.open ? AppColors.success : AppColors.danger;
    final bounds = _viewportBounds(series.closeSpots.length);

    return LineChartData(
      minX: bounds.$1,
      maxX: bounds.$2,
      minY: points.map((e) => e.y).reduce(math.min) - 18,
      maxY: points.map((e) => e.y).reduce(math.max) + 18,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.4),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 56,
            getTitlesWidget: (value, _) => Text(
              '₹${value.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: math.max(1, points.length / 4),
            getTitlesWidget: (value, _) {
              final index = value.toInt();
              if (index < 0 || index >= series.xLabels.length) {
                return const SizedBox.shrink();
              }
              return Text(
                series.xLabels[index],
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.surfaceAlt,
          tooltipPadding: const EdgeInsets.all(8),
          getTooltipItems: (touchedSpots) {
            return touchedSpots
                .map(
                  (spot) => LineTooltipItem(
                    '₹${spot.y.toStringAsFixed(2)}',
                    GoogleFonts.jetBrainsMono(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                  ),
                )
                .toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: points,
          isCurved: true,
          color: primaryColor,
          barWidth: 2.8,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: isArea,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                primaryColor.withValues(alpha: 0.25),
                Colors.transparent,
              ],
            ),
          ),
        ),
        if (_showSma20)
          LineChartBarData(
            spots: series.sma20Spots,
            isCurved: true,
            color: AppColors.warning,
            barWidth: 1.4,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        if (_showSma50)
          LineChartBarData(
            spots: series.sma50Spots,
            isCurved: true,
            color: AppColors.accent,
            barWidth: 1.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    );
  }

  CandlestickChartData _buildCandlestickData(TradingChartSeries series) {
    return CandlestickChartData(
      candlestickSpots: series.candlestickSpots,
      minX: _viewportBounds(series.candlestickSpots.length).$1,
      maxX: _viewportBounds(series.candlestickSpots.length).$2,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.4),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 56,
            getTitlesWidget: (value, _) => Text(
              '₹${value.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: math.max(1, series.candlestickSpots.length / 4),
            getTitlesWidget: (value, _) {
              final index = value.toInt();
              if (index < 0 || index >= series.xLabels.length) {
                return const SizedBox.shrink();
              }
              return Text(series.xLabels[index], style: Theme.of(context).textTheme.bodySmall);
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      candlestickTouchData: CandlestickTouchData(
        enabled: true,
        touchTooltipData: CandlestickTouchTooltipData(
          getTooltipColor: (_) => AppColors.surfaceAlt,
        ),
      ),
    );
  }

  (double, double) _viewportBounds(int length) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    if (!isMobile || length <= _mobileVisibleCandles) {
      return (0, (length - 1).toDouble());
    }
    final start = (length - _mobileVisibleCandles).toDouble();
    return (start, (length - 1).toDouble());
  }

  Widget _buildVolumeChart(TradingChartSeries series) {
    final maxVolume = series.volumeBars
        .map((item) => item.barRods.first.toY)
        .reduce(math.max);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxVolume * 1.1,
        barGroups: series.volumeBars,
        alignment: BarChartAlignment.spaceBetween,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
      ),
    );
  }

  Widget _chartStat(String key, double value) {
    return Text(
      '$key ${value.toStringAsFixed(2)}',
      style: GoogleFonts.jetBrainsMono(
        color: AppColors.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _chartLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  List<(String, String, String)> _orderBook(double price) {
    return List.generate(8, (index) {
      final spread = (8 - index) * 0.55;
      final bid = (price - spread).toStringAsFixed(2);
      final ask = (price + spread).toStringAsFixed(2);
      final qty = (120 + (index * 45)).toString();
      return (bid, qty, ask);
    });
  }

  List<(String, String, String, bool)> _recentTrades(double price) {
    return List.generate(10, (index) {
      final up = index.isEven;
      final p = (price + (up ? index * 0.35 : -index * 0.28)).toStringAsFixed(2);
      final qty = (50 + (index * 15)).toString();
      final minute = 42 - index;
      return ('14:${minute.toString().padLeft(2, '0')}:17', p, qty, up);
    });
  }

  List<Stock> _filteredStocks(List<Stock> source) {
    if (_query.isEmpty) {
      return source;
    }
    final query = _query.toLowerCase();
    return source
        .where(
          (stock) =>
              stock.symbol.toLowerCase().contains(query) ||
              stock.name.toLowerCase().contains(query),
        )
        .toList();
  }

  Stock _resolveSelectedStock({
    required Stock fallback,
    required List<Stock> all,
    required List<Stock> filtered,
  }) {
    final selected = all.where((stock) => stock.symbol == _selectedSymbol).toList();
    if (selected.isNotEmpty) {
      return selected.first;
    }
    if (filtered.isNotEmpty) {
      return filtered.first;
    }
    return fallback;
  }

  void _openSearchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final controller = TextEditingController(text: _query);
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Find in watchlist',
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() => _query = controller.text.trim());
                  Navigator.pop(context);
                },
                child: const Text('Apply Search'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openChartSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chart Settings', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<ChartType>(
                    segments: const [
                      ButtonSegment(value: ChartType.candles, label: Text('Candles')),
                      ButtonSegment(value: ChartType.line, label: Text('Line')),
                      ButtonSegment(value: ChartType.area, label: Text('Area')),
                    ],
                    selected: {_chartType},
                    onSelectionChanged: (selection) {
                      setState(() => _chartType = selection.first);
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show SMA 20'),
                    value: _showSma20,
                    onChanged: (value) {
                      setState(() => _showSma20 = value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show SMA 50'),
                    value: _showSma50,
                    onChanged: (value) {
                      setState(() => _showSma50 = value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Volume'),
                    value: _showVolume,
                    onChanged: (value) {
                      setState(() => _showVolume = value);
                      setModalState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openOrderSheet(BuildContext context, String symbol, OrderType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickOrderSheet(symbol: symbol, type: type),
    );
  }

  void _openStockDetail(BuildContext context, String symbol) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: symbol)),
    );
  }

  Widget _buildMobileCtaBar(BuildContext context, Stock stock) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _openStockDetail(context, stock.symbol),
                child: const Text('DETAIL'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _openOrderSheet(context, stock.symbol, OrderType.sell),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('SELL'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _openOrderSheet(context, stock.symbol, OrderType.buy),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('BUY'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _rangeLabels = ['1D', '1W', '1M', '3M', '1Y'];

class _QuickOrderSheet extends StatefulWidget {
  final String symbol;
  final OrderType type;

  const _QuickOrderSheet({required this.symbol, required this.type});

  @override
  State<_QuickOrderSheet> createState() => _QuickOrderSheetState();
}

class _QuickOrderSheetState extends State<_QuickOrderSheet> {
  final _qtyController = TextEditingController(text: '10');

  double get _margin {
    final stock = TradingScope.of(context).stockBySymbol(widget.symbol);
    final qty = int.tryParse(_qtyController.text) ?? 0;
    return (stock.currentPrice * qty) / 5;
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);
    final isBuy = widget.type == OrderType.buy;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${isBuy ? 'Buy' : 'Sell'} ${stock.symbol}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
          Text('LTP ₹${stock.currentPrice.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity', suffixText: 'Qty'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          CustomCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Required Margin'),
                    Text(
                      '₹${_margin.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Available Margin'),
                    Text(
                      '₹${store.balance.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(_qtyController.text) ?? 0;
              final result = store.placeOrder(
                symbol: stock.symbol,
                quantity: qty,
                type: widget.type,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? (isBuy ? AppColors.success : AppColors.danger) : AppColors.warning,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: isBuy ? AppColors.success : AppColors.danger),
            child: Text(isBuy ? 'CONFIRM BUY' : 'CONFIRM SELL'),
          ),
        ],
      ),
    );
  }
}
