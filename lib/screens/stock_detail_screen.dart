import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import 'alert_creation_screen.dart';
import '../screens/advanced_chart_screen.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_drawer.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  OrderType _pendingOrderSide = OrderType.buy;
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
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(stock.symbol),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AlertCreationScreen(initialSymbol: stock.symbol),
              ),
            ),
            icon: const Icon(LucideIcons.bell, size: 20),
            tooltip: 'Create alert',
          ),
          IconButton(
            onPressed: () {
              final isInWatchlist = store.isInWatchlist(stock.symbol);
              if (isInWatchlist) {
                store.removeFromWatchlist(stock.symbol);
              } else {
                store.addToWatchlist(stock.symbol);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isInWatchlist
                        ? '${stock.symbol} removed from watchlist'
                        : '${stock.symbol} added to watchlist',
                  ),
                ),
              );
            },
            icon: Icon(
              store.isInWatchlist(stock.symbol)
                  ? Icons.star
                  : Icons.star_border,
              size: 20,
            ),
            tooltip: 'Toggle watchlist',
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: isMobile
          ? _buildFixedMobileActions(context, stock)
          : null,
      endDrawer: _buildOrderDrawer(
        context,
        stock,
      ), // Sliding drawer instead of modal
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stock.symbol,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'NSE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(stock.name, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${stock.currentPrice.toStringAsFixed(2)}',
                style: AppTheme.tabular(
                  Theme.of(context).textTheme.headlineMedium!.copyWith(
                    color: stock.isPositive
                        ? AppColors.success
                        : AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${stock.isPositive ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: stock.isPositive
                      ? AppColors.success
                      : AppColors.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
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
                    for (var i = 0; i < _ranges.length; i++)
                      _rangeChip(i, _ranges[i]),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Screenshot',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Screenshot saved')),
                ),
                icon: const Icon(LucideIcons.camera, size: 18),
              ),
              IconButton(
                tooltip: 'Full screen chart',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdvancedChartScreen(symbol: widget.symbol),
                  ),
                ),
                icon: const Icon(LucideIcons.maximize2, size: 18),
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
                Text(
                  'Pinch to zoom · Drag to pan',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
              Text(
                'VWAP ₹${series.vwap.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'RSI14 ${series.rsi14.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Vol ${(series.volume / 100000).toStringAsFixed(2)}L',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(
    BuildContext context,
    Stock stock,
    TradingChartSeries series,
    bool isDesktop,
  ) {
    final base = stock.currentPrice;
    final stats = [
      ('Open', '₹${series.open.toStringAsFixed(2)}'),
      ('High', '₹${series.high.toStringAsFixed(2)}'),
      ('Low', '₹${series.low.toStringAsFixed(2)}'),
      (
        'Prev Close',
        '₹${series.data.length > 1 ? series.data[series.data.length - 2].close.toStringAsFixed(2) : series.open.toStringAsFixed(2)}',
      ),
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

  Widget _depthAndTrades(
    BuildContext context,
    TradingChartSeries series,
    bool isDesktop,
  ) {
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
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.success,
                        fontSize: 12,
                      ),
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
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
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
                  Expanded(
                    child: Text(
                      row.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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

    return Column(children: [left, const SizedBox(height: 16), right]);
  }

  Widget _actionBar(BuildContext context, Stock stock) {
    return CustomCard(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openOrderDrawer(context, OrderType.sell),
              icon: const Icon(
                LucideIcons.arrowDownRight,
                color: AppColors.danger,
              ),
              label: const Text(
                'SELL',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _openOrderDrawer(context, OrderType.buy),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
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
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
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
    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      margin: EdgeInsets.zero,
      trackballBehavior: TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
        lineType: TrackballLineType.vertical,
        lineColor: AppColors.textSecondary.withValues(alpha: 0.5),
        lineWidth: 1,
      ),
      primaryXAxis: DateTimeAxis(
        majorGridLines: MajorGridLines(width: 0),
        axisLine: AxisLine(width: 0),
        dateFormat: DateFormat.Hm(),
        intervalType: DateTimeIntervalType.auto,
        labelStyle: const TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary,
        ),
      ),
      primaryYAxis: NumericAxis(
        opposedPosition: true,
        majorGridLines: MajorGridLines(color: AppColors.border, width: 0.5),
        axisLine: AxisLine(width: 0),
        numberFormat: NumberFormat.simpleCurrency(decimalDigits: 0, name: '₹'),
        labelStyle: AppTheme.tabular(
          const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ),
      series: <CartesianSeries>[
        if (_chartType == ChartType.candles)
          CandleSeries<TradingCandle, DateTime>(
            name: 'OHLC',
            dataSource: series.data,
            xValueMapper: (TradingCandle c, _) => c.time,
            lowValueMapper: (TradingCandle c, _) => c.low,
            highValueMapper: (TradingCandle c, _) => c.high,
            openValueMapper: (TradingCandle c, _) => c.open,
            closeValueMapper: (TradingCandle c, _) => c.close,
            enableSolidCandles: true,
            bearColor: AppColors.danger,
            bullColor: AppColors.success,
          )
        else if (_chartType == ChartType.line)
          LineSeries<TradingCandle, DateTime>(
            dataSource: series.data,
            xValueMapper: (TradingCandle c, _) => c.time,
            yValueMapper: (TradingCandle c, _) => c.close,
            color: series.close >= series.open
                ? AppColors.success
                : AppColors.danger,
            width: 2,
          )
        else if (_chartType == ChartType.area)
          AreaSeries<TradingCandle, DateTime>(
            dataSource: series.data,
            xValueMapper: (TradingCandle c, _) => c.time,
            yValueMapper: (TradingCandle c, _) => c.close,
            color:
                (series.close >= series.open
                        ? AppColors.success
                        : AppColors.danger)
                    .withValues(alpha: 0.1),
            borderColor: (series.close >= series.open
                ? AppColors.success
                : AppColors.danger),
            borderWidth: 2,
          ),
      ],
    );
  }

  Widget _volumeChart(TradingChartSeries series) {
    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      margin: EdgeInsets.zero,
      primaryXAxis: DateTimeAxis(isVisible: false),
      primaryYAxis: NumericAxis(isVisible: false),
      series: <CartesianSeries>[
        ColumnSeries<TradingCandle, DateTime>(
          dataSource: series.data,
          xValueMapper: (TradingCandle c, _) => c.time,
          yValueMapper: (TradingCandle c, _) => c.volume,
          pointColorMapper: (TradingCandle c, _) =>
              (c.close >= c.open ? AppColors.success : AppColors.danger)
                  .withValues(alpha: 0.3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
        ),
      ],
    );
  }

  Widget _buildOrderDrawer(BuildContext context, Stock stock) {
    return OrderFormDrawer(stock: stock, initialSide: _pendingOrderSide);
  }

  void _openOrderDrawer(BuildContext context, OrderType type) {
    setState(() => _pendingOrderSide = type);
    _scaffoldKey.currentState?.openEndDrawer();
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
                  Text(
                    'Chart Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ChartType>(
                    segments: const [
                      ButtonSegment(
                        value: ChartType.candles,
                        label: Text('Candles'),
                      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _openOrderDrawer(context, OrderType.sell),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: const Text('SELL'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _openOrderDrawer(context, OrderType.buy),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              child: const Text('BUY'),
            ),
          ),
        ],
      ),
    );
  }
}

const _ranges = ['1D', '1W', '1M', '3M', '1Y'];
