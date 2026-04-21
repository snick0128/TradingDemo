import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
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
    final isDesktop = MediaQuery.of(context).size.width >= 1060;
    final isMobile = MediaQuery.of(context).size.width < 760;
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);
    final series = TradingChartService.buildSeries(
      symbol: stock.symbol,
      basePrice: stock.currentPrice,
      rangeIndex: _selectedRange,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${stock.symbol} Detail'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(LucideIcons.bell)),
          IconButton(onPressed: () {}, icon: const Icon(LucideIcons.star)),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildFixedMobileActions(context, stock) : null,
      body: Container(
        color: AppColors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(context, stock),
              const SizedBox(height: 16),
              _chartCard(context, series),
              const SizedBox(height: 16),
              _statsGrid(context, stock, series, isDesktop),
              const SizedBox(height: 16),
              _depthAndTrades(context, series, isDesktop),
              if (!isMobile) ...[
                const SizedBox(height: 16),
                _actionBar(context, stock),
              ],
              if (isMobile) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context, Stock stock) {
    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              stock.symbol.characters.first,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stock.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${stock.symbol} • ${stock.sector}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${stock.currentPrice.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
              Text(
                '${stock.isPositive ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: stock.isPositive ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartCard(BuildContext context, TradingChartSeries series) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _ranges.length; i++) _rangeChip(i, _ranges[i]),
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
          const SizedBox(height: 12),
          SizedBox(height: 320, child: _buildPrimaryChart(series)),
          if (_showVolume) ...[
            const SizedBox(height: 8),
            SizedBox(height: 90, child: _volumeChart(series)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _valueChip('O', series.open),
              _valueChip('H', series.high),
              _valueChip('L', series.low),
              _valueChip('C', series.close),
              Text('VWAP ₹${series.vwap.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
              Text('RSI14 ${series.rsi14.toStringAsFixed(1)}', style: Theme.of(context).textTheme.bodySmall),
              Text('Vol ${(series.volume / 100000).toStringAsFixed(2)}L', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(BuildContext context, Stock stock, TradingChartSeries series, bool isDesktop) {
    final base = stock.currentPrice;
    final stats = [
      ('Open', '₹${series.open.toStringAsFixed(2)}'),
      ('High', '₹${series.high.toStringAsFixed(2)}'),
      ('Low', '₹${series.low.toStringAsFixed(2)}'),
      ('Prev Close', '₹${series.closeSpots.length > 1 ? series.closeSpots[series.closeSpots.length - 2].y.toStringAsFixed(2) : series.open.toStringAsFixed(2)}'),
      ('52W High', '₹${(base + 210).toStringAsFixed(2)}'),
      ('52W Low', '₹${(base - 390).toStringAsFixed(2)}'),
      ('Upper Circuit', '₹${(base * 1.1).toStringAsFixed(2)}'),
      ('Lower Circuit', '₹${(base * 0.9).toStringAsFixed(2)}'),
    ];

    final crossCount = isDesktop ? 4 : 2;

    return GridView.builder(
      itemCount: stats.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(stat.$1, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 5),
              Text(
                stat.$2,
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _depthAndTrades(BuildContext context, TradingChartSeries series, bool isDesktop) {
    final depth = _depthRows(series.close);
    final trades = _tradeRows(series.close);

    final left = CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Market Depth', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _headerCell('Bid', TextAlign.left),
              _headerCell('Qty', TextAlign.center),
              _headerCell('Ask', TextAlign.right),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in depth)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
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
                      style: Theme.of(context).textTheme.bodySmall,
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

    final right = CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trades', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _headerCell('Time', TextAlign.left),
              _headerCell('Price', TextAlign.center),
              _headerCell('Qty', TextAlign.right),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in trades)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
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

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      );
    }

    return Column(
      children: [
        left,
        const SizedBox(height: 16),
        right,
      ],
    );
  }

  Widget _actionBar(BuildContext context, Stock stock) {
    return CustomCard(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showTradeModal(context, stock.symbol, OrderType.sell),
              icon: const Icon(LucideIcons.arrowDownRight, color: AppColors.danger),
              label: const Text('SELL', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showTradeModal(context, stock.symbol, OrderType.buy),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              icon: const Icon(LucideIcons.arrowUpRight),
              label: const Text('BUY'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(int index, String label) {
    final selected = index == _selectedRange;

    return InkWell(
      onTap: () {
        _chartTransformController.value = Matrix4.identity();
        setState(() => _selectedRange = index);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, TextAlign align) {
    return Expanded(
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPrimaryChart(TradingChartSeries series) {
    if (_chartType == ChartType.candles) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CandlestickChart(
          _candlestickData(series),
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
        _chartData(series, isArea: _chartType == ChartType.area),
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

  LineChartData _chartData(TradingChartSeries series, {required bool isArea}) {
    final points = series.closeSpots;
    final primaryColor = series.close >= series.open ? AppColors.success : AppColors.danger;
    final bounds = _viewportBounds(series.closeSpots.length);

    return LineChartData(
      minX: bounds.$1,
      maxX: bounds.$2,
      minY: points.map((e) => e.y).reduce(math.min) - 20,
      maxY: points.map((e) => e.y).reduce(math.max) + 20,
      clipData: const FlClipData.all(),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.4),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 54,
            interval: 20,
            getTitlesWidget: (value, _) => Text(
              '₹${value.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: math.max(1, points.length / 5),
            getTitlesWidget: (value, _) {
              final index = value.toInt();
              if (index < 0 || index >= series.xLabels.length) {
                return const SizedBox.shrink();
              }
              return Text(
                series.xLabels[index],
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.surfaceAlt,
          getTooltipItems: (spots) => spots
              .map(
                (s) => LineTooltipItem(
                  '₹${s.y.toStringAsFixed(2)}',
                  GoogleFonts.jetBrainsMono(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: points,
          isCurved: true,
          color: primaryColor,
          barWidth: 2.6,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: isArea,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                primaryColor.withValues(alpha: 0.24),
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
            barWidth: 1.3,
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

  CandlestickChartData _candlestickData(TradingChartSeries series) {
    return CandlestickChartData(
      candlestickSpots: series.candlestickSpots,
      minX: _viewportBounds(series.candlestickSpots.length).$1,
      maxX: _viewportBounds(series.candlestickSpots.length).$2,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.4),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 54,
            interval: 20,
            getTitlesWidget: (value, _) => Text(
              '₹${value.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: math.max(1, series.candlestickSpots.length / 5),
            getTitlesWidget: (value, _) {
              final index = value.toInt();
              if (index < 0 || index >= series.xLabels.length) {
                return const SizedBox.shrink();
              }
              return Text(
                series.xLabels[index],
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              );
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

  Widget _volumeChart(TradingChartSeries series) {
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

  Widget _valueChip(String label, double value) {
    return Text(
      '$label ${value.toStringAsFixed(2)}',
      style: GoogleFonts.jetBrainsMono(
        color: AppColors.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  List<(String, String, String)> _depthRows(double price) {
    return List.generate(10, (index) {
      final tick = (10 - index) * 0.45;
      return (
        (price - tick).toStringAsFixed(2),
        (95 + index * 18).toString(),
        (price + tick).toStringAsFixed(2),
      );
    });
  }

  List<(String, String, String, bool)> _tradeRows(double price) {
    return List.generate(11, (index) {
      final up = index % 3 != 0;
      return (
        '14:${(34 - index).toString().padLeft(2, '0')}:04',
        (price + (up ? index * 0.25 : -index * 0.31)).toStringAsFixed(2),
        (45 + index * 14).toString(),
        up,
      );
    });
  }

  void _showTradeModal(BuildContext context, String symbol, OrderType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TradeModal(symbol: symbol, type: type),
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

  Widget _buildFixedMobileActions(BuildContext context, Stock stock) {
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
              child: OutlinedButton.icon(
                onPressed: () => _showTradeModal(context, stock.symbol, OrderType.sell),
                icon: const Icon(LucideIcons.arrowDownRight, color: AppColors.danger),
                label: const Text(
                  'SELL',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showTradeModal(context, stock.symbol, OrderType.buy),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                icon: const Icon(LucideIcons.arrowUpRight),
                label: const Text('BUY'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _ranges = ['1D', '1W', '1M', '3M', '1Y'];

class _TradeModal extends StatefulWidget {
  final String symbol;
  final OrderType type;

  const _TradeModal({required this.symbol, required this.type});

  @override
  State<_TradeModal> createState() => _TradeModalState();
}

class _TradeModalState extends State<_TradeModal> {
  final TextEditingController _qtyController = TextEditingController(text: '1');

  double _margin(Stock stock) {
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
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
            ],
          ),
          const SizedBox(height: 4),
          Text('NSE • LTP ₹${stock.currentPrice.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Quantity', suffixText: 'Qty'),
          ),
          const SizedBox(height: 16),
          CustomCard(
            child: Column(
              children: [
                _row('Required Margin', '₹${_margin(stock).toStringAsFixed(2)}', AppColors.textPrimary),
                const SizedBox(height: 8),
                _row('Available Margin', '₹${store.balance.toStringAsFixed(2)}', AppColors.accent),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(_qtyController.text) ?? 0;
              final result = store.placeOrder(symbol: stock.symbol, quantity: qty, type: widget.type);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? (isBuy ? AppColors.success : AppColors.danger) : AppColors.warning,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: isBuy ? AppColors.success : AppColors.danger),
            child: Text('SUBMIT ${isBuy ? 'BUY' : 'SELL'}'),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
