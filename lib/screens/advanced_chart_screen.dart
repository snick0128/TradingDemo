import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

// ─── Chart color constants ────────────────────────────────────────────────────
const _kBullColor = Color(0xFF00C853);
const _kBearColor = Color(0xFFD50000);
const _kChartBg = Colors.white;
const _kGridColor = Color(0xFFEEEEEE);
const _kAxisColor = Color(0xFF757575);

class AdvancedChartScreen extends StatefulWidget {
  final String symbol;
  final TradingChartSeries? initialSeries;
  const AdvancedChartScreen({super.key, required this.symbol, this.initialSeries});

  @override
  State<AdvancedChartScreen> createState() => _AdvancedChartScreenState();
}

class _AdvancedChartScreenState extends State<AdvancedChartScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, ChartTimeframe> _savedTimeframe = {};
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  ChartType _chartType = ChartType.candles;
  ChartTimeframe _timeframe = ChartTimeframe.d1;
  ChartDateRange _dateRange = ChartDateRange.mo1;

  // Animation
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  // Unique key forces AnimatedSwitcher to rebuild on data change
  int _chartVersion = 0;

  // Active indicators
  bool _showEma = false;
  bool _showBollinger = false;
  bool _showMacd = false;
  bool _showRsi = false;
  bool _showStochastic = false;
  bool _showCci = false;
  bool _showWilliamsR = false;
  bool _showObv = false;
  bool _showAtr = false;

  // Compare overlay
  String? _compareSymbol;
  final _compareController = TextEditingController();
  TradingChartSeries? _series;
  TradingChartSeries? _compareSeries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timeframe = _savedTimeframe[widget.symbol] ?? ChartTimeframe.d1;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    if (widget.initialSeries != null) {
      _series = widget.initialSeries;
      _loading = false;
      _fadeCtrl.forward();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSeries());
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _compareController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Fade out current chart immediately for snappy feel
    _fadeCtrl.reverse();
    try {
      final store = TradingScope.of(context);
      final stock = store.stockBySymbol(widget.symbol);
      final interval = _apiInterval(_timeframe);
      final now = DateTime.now().toUtc();
      final from = _fromForRange(now, _dateRange);
      final mainRows = await _api.getHistoricalData(
        stock.symbol,
        interval: interval,
        from: _fmtApiDate(from, interval: interval),
        to: _fmtApiDate(now, interval: interval),
        exchange: stock.exchange.isNotEmpty ? stock.exchange : null,
        token: stock.token.isNotEmpty ? stock.token : null,
      );
      TradingChartSeries? compare;
      if (_compareSymbol != null) {
        final cmpStock = store.stockBySymbol(_compareSymbol!);
        final cmpRows = await _api.getHistoricalData(
          cmpStock.symbol,
          interval: interval,
          from: _fmtApiDate(from, interval: interval),
          to: _fmtApiDate(now, interval: interval),
          exchange: cmpStock.exchange.isNotEmpty ? cmpStock.exchange : null,
          token: cmpStock.token.isNotEmpty ? cmpStock.token : null,
        );
        compare = TradingChartService.fromRawCandles(
          cmpRows,
          fallbackPrice: cmpStock.currentPrice,
        );
      }

      if (!mounted) return;
      setState(() {
        _series = TradingChartService.fromRawCandles(
          mainRows,
          fallbackPrice: stock.currentPrice,
        );
        _compareSeries = compare;
        _loading = false;
        _chartVersion++;
      });
      // Fade in new chart
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      _fadeCtrl.forward();
    }
  }

  DateTime _fromForRange(DateTime nowUtc, ChartDateRange r) {
    switch (r) {
      case ChartDateRange.d1:
        return nowUtc.subtract(const Duration(days: 1));
      case ChartDateRange.d5:
        return nowUtc.subtract(const Duration(days: 5));
      case ChartDateRange.mo1:
        return nowUtc.subtract(const Duration(days: 30));
      case ChartDateRange.mo3:
        return nowUtc.subtract(const Duration(days: 90));
      case ChartDateRange.mo6:
        return nowUtc.subtract(const Duration(days: 180));
      case ChartDateRange.y1:
        return nowUtc.subtract(const Duration(days: 365));
      case ChartDateRange.y3:
        return nowUtc.subtract(const Duration(days: 365 * 3));
      case ChartDateRange.y5:
        return nowUtc.subtract(const Duration(days: 365 * 5));
      case ChartDateRange.max:
        return nowUtc.subtract(const Duration(days: 365 * 10));
    }
  }

  String _apiInterval(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return '1m';
      case ChartTimeframe.m10:
        return '15m';
      case ChartTimeframe.m3:
      case ChartTimeframe.m5:
        return '5m';
      case ChartTimeframe.m15:
        return '15m';
      case ChartTimeframe.m30:
        return '30m';
      case ChartTimeframe.h1:
      case ChartTimeframe.h4:
        return '1h';
      case ChartTimeframe.d1:
      case ChartTimeframe.w1:
      case ChartTimeframe.mo1:
        return '1d';
    }
  }

  String _fmtApiDate(DateTime utc, {String interval = '1d'}) {
    final d = utc.toLocal();
    final int roundedMin;
    final int roundedHour;
    switch (interval) {
      case '1m':
        roundedMin = d.minute;
        roundedHour = d.hour;
      case '5m':
        roundedMin = (d.minute ~/ 5) * 5;
        roundedHour = d.hour;
      case '15m':
        roundedMin = (d.minute ~/ 15) * 15;
        roundedHour = d.hour;
      case '30m':
        roundedMin = (d.minute ~/ 30) * 30;
        roundedHour = d.hour;
      case '1h':
        roundedMin = 0;
        roundedHour = d.hour;
      default:
        roundedMin = 0;
        roundedHour = 0;
    }
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = roundedHour.toString().padLeft(2, '0');
    final min = roundedMin.toString().padLeft(2, '0');
    return '${d.year}-$m-$day $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);

    return Scaffold(
      backgroundColor: _kChartBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _buildMainView(stock),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomStatusBar(stock),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Interval pill
          GestureDetector(
            onTap: () => _showTimeframeSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _timeframe.name.toUpperCase().replaceFirst('M', 'm').replaceFirst('H', 'h'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Chart type icon
          IconButton(
            icon: Icon(
              _chartType == ChartType.line ? Icons.show_chart : Icons.candlestick_chart_outlined,
              color: const Color(0xFF555555),
              size: 20,
            ),
            onPressed: () => _showChartTypeSheet(),
          ),
          // Indicators
          IconButton(
            icon: const Icon(Icons.functions, color: Color(0xFF555555), size: 20),
            onPressed: () => _showIndicatorPanel(context),
          ),
          const Spacer(),
          // Undo/Redo
          IconButton(
            icon: const Icon(Icons.undo, color: Color(0xFFBDBDBD), size: 18),
            onPressed: null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, color: Color(0xFFBDBDBD), size: 18),
            onPressed: null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Color(0xFF555555), size: 20),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.open_in_full, color: Color(0xFF555555), size: 18),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMainView(Stock stock) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _cleanError(_error!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575)),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadSeries,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    final series = _series;
    if (series == null) return const SizedBox();

    final chartData = _chartType == ChartType.heikinAshi
        ? TradingChartService.toHeikinAshi(series.data)
        : series.data;

    if (chartData.isEmpty || (chartData.length <= 1 && chartData.first.close <= 0)) {
      return const Center(
        child: Text(
          'No data available',
          style: TextStyle(color: _kAxisColor),
        ),
      );
    }

    return Column(
      children: [
        // Symbol overlay label
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${stock.symbol} · ${_timeframe.name.toUpperCase()} · ${stock.exchange}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    stock.currentPrice.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: stock.isPositive ? _kBullColor : _kBearColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${stock.isPositive ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: stock.isPositive ? _kBullColor : _kBearColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Main Chart
        Expanded(
          flex: 5,
          child: _buildChart(chartData, series, null),
        ),
        // Volume Panel
        if (series.data.any((c) => c.volume > 0)) ...[
          Container(height: 1, color: const Color(0xFFEEEEEE)),
          SizedBox(
            height: 80,
            child: _buildVolumeChart(series.data),
          ),
        ],
        // Date Range Bar
        _buildDateRangeToolbar(),
      ],
    );
  }

  Widget _buildBottomStatusBar(Stock stock) {
    return Container(
      height: 48,
      color: stock.isPositive ? _kBullColor : _kBearColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.flash_on, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            stock.currentPrice.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          const Text(
            'LIVE MARKET',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _showTimeframeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Timeframe', style: TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: ListView(
                  children: ChartTimeframe.values.map((tf) {
                    return ListTile(
                      title: Text(tf.name.toUpperCase()),
                      selected: _timeframe == tf,
                      onTap: () {
                        setState(() => _timeframe = tf);
                        _loadSeries();
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChartTypeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: ChartType.values.map((ct) {
            return ListTile(
              leading: Icon(_iconForType(ct)),
              title: Text(ct.name.toUpperCase()),
              selected: _chartType == ct,
              onTap: () {
                setState(() => _chartType = ct);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  IconData _iconForType(ChartType type) {
    switch (type) {
      case ChartType.candles: return Icons.candlestick_chart;
      case ChartType.line: return Icons.show_chart;
      case ChartType.area: return Icons.area_chart;
      case ChartType.bar: return Icons.bar_chart;
      default: return Icons.auto_graph;
    }
  }

  Widget _buildDateRangeToolbar() {
    const labels = ['1D', '5D', '1M', '3M', '6M', '1Y', '5Y', 'All'];
    const values = [
      ChartDateRange.d1,
      ChartDateRange.d5,
      ChartDateRange.mo1,
      ChartDateRange.mo3,
      ChartDateRange.mo6,
      ChartDateRange.y1,
      ChartDateRange.y5,
      ChartDateRange.max,
    ];

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(labels.length, (i) {
          final selected = _dateRange == values[i];
          return GestureDetector(
            onTap: () {
              setState(() => _dateRange = values[i]);
              _loadSeries();
            },
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.black : const Color(0xFF9E9E9E),
              ),
            ),
          );
        }),
      ),
    );
  }



  Widget _buildChart(
    List<TradingCandle> chartData,
    TradingChartSeries series,
    TradingChartSeries? compareSeries,
  ) {
    if (chartData.length <= 1 && chartData.first.close <= 0) {
      return const Center(
        child: Text(
          'No candles available for this instrument',
          style: TextStyle(color: _kAxisColor, fontSize: 13),
        ),
      );
    }
    final closes = chartData.map((c) => c.close).toList();
    final emaValues = _showEma ? TradingChartService.ema(closes, 20) : null;
    final bbValues = _showBollinger
        ? TradingChartService.bollingerBands(closes, 20, 2.0)
        : null;

    // Determine if overall trend is up for line/area color
    final isUp = series.close >= series.open;

    // Show ~40 of the most-recent candles (right-anchored, no empty gaps).
    final n = chartData.length;
    final initialZoom = n > 40 ? (40 / n).clamp(0.02, 1.0) : 1.0;
    // Clamp X axis to data range so no empty pre/post-market gaps appear.
    final axisMin = chartData.first.time;
    final axisMax = chartData.last.time.add(
      _timeframe == ChartTimeframe.m1 || _timeframe == ChartTimeframe.m5
          ? const Duration(minutes: 5)
          : _timeframe == ChartTimeframe.m15
          ? const Duration(minutes: 15)
          : const Duration(days: 1),
    );

    return SfCartesianChart(
      key: ValueKey(_chartVersion),
      backgroundColor: _kChartBg,
      plotAreaBackgroundColor: _kChartBg,
      plotAreaBorderWidth: 0,
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      enableAxisAnimation: true,
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        enableMouseWheelZooming: true,
        maximumZoomLevel: 0.02,
        zoomMode: ZoomMode.x,
      ),
      crosshairBehavior: CrosshairBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        lineType: CrosshairLineType.both,
        lineColor: _kAxisColor,
        lineWidth: 1,
        lineDashArray: const [4, 4],
      ),
      trackballBehavior: TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
        lineType: TrackballLineType.vertical,
        lineColor: const Color(0xFF757575).withOpacity(0.4),
        lineWidth: 1,
        tooltipSettings: const InteractiveTooltip(
          enable: true,
          color: Color(0xFF333333),
          textStyle: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
      primaryXAxis: DateTimeAxis(
        initialZoomFactor: initialZoom,
        initialZoomPosition: 1.0,
        minimum: axisMin,
        maximum: axisMax,
        isVisible: true,
        majorGridLines: const MajorGridLines(color: _kGridColor, width: 1),
        axisLine: const AxisLine(width: 0),
        dateFormat: _dateFormatForRange(),
        intervalType: DateTimeIntervalType.auto,
        labelStyle: const TextStyle(fontSize: 11, color: _kAxisColor),
        majorTickLines: const MajorTickLines(size: 0),
      ),
      primaryYAxis: NumericAxis(
        opposedPosition: true,
        isVisible: true,
        majorGridLines: const MajorGridLines(color: _kGridColor, width: 1),
        axisLine: const AxisLine(width: 0),
        numberFormat: NumberFormat('#,##0.00'),
        rangePadding: ChartRangePadding.round,
        labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF333333)),
        majorTickLines: const MajorTickLines(size: 0),
        plotBands: series.close > 0
            ? [
                PlotBand(
                  start: series.close,
                  end: series.close,
                  borderColor: const Color(0xFF00897B),
                  borderWidth: 1.5,
                  dashArray: const [4, 4],
                  text: '  ${series.close.toStringAsFixed(2)}',
                  textStyle: const TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  verticalTextAlignment: TextAnchor.middle,
                ),
              ]
            : [],
      ),
      series: <CartesianSeries>[
        ..._buildMainSeries(chartData, series),
        if (emaValues != null) ..._buildEmaSeries(chartData, emaValues),
        if (bbValues != null) ..._buildBollingerSeries(chartData, bbValues),
        if (compareSeries != null) _buildCompareSeries(compareSeries),
      ],
    );
  }

  Widget _buildVolumeChart(List<TradingCandle> data) {
    return SfCartesianChart(
      backgroundColor: Colors.white,
      plotAreaBackgroundColor: Colors.white,
      plotAreaBorderWidth: 0,
      margin: const EdgeInsets.only(right: 8),
      primaryXAxis: DateTimeAxis(isVisible: false),
      primaryYAxis: NumericAxis(
        opposedPosition: true,
        isVisible: true,
        labelStyle: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E)),
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: const AxisLine(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
        numberFormat: NumberFormat.compact(),
      ),
      series: <CartesianSeries>[
        ColumnSeries<TradingCandle, DateTime>(
          dataSource: data,
          xValueMapper: (c, _) => c.time,
          yValueMapper: (c, _) => c.volume,
          pointColorMapper: (c, _) => c.close >= c.open
              ? const Color(0xFF00C853).withOpacity(0.4)
              : const Color(0xFFE53935).withOpacity(0.4),
          borderWidth: 0,
          spacing: 0.15,
          animationDuration: 0,
        ),
      ],
    );
  }

  DateFormat _dateFormatForRange() {
    switch (_dateRange) {
      case ChartDateRange.d1:
      case ChartDateRange.d5:
        return DateFormat.Hm();
      case ChartDateRange.mo1:
      case ChartDateRange.mo3:
        return DateFormat('dd MMM');
      default:
        return DateFormat('MMM yy');
    }
  }

  String _cleanError(String error) {
    return error.replaceFirst('BackendException: ', '');
  }

  List<CartesianSeries> _buildMainSeries(
    List<TradingCandle> data,
    TradingChartSeries series,
  ) {
    final isUp = series.close >= series.open;

    switch (_chartType) {
      case ChartType.candles:
      case ChartType.heikinAshi:
        return [
          CandleSeries<TradingCandle, DateTime>(
            name: 'OHLC',
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            lowValueMapper: (c, _) => c.low,
            highValueMapper: (c, _) => c.high,
            openValueMapper: (c, _) => c.open,
            closeValueMapper: (c, _) => c.close,
            enableSolidCandles: true,
            bearColor: _kBearColor,
            bullColor: _kBullColor,
            width: data.length > 180 ? 0.45 : 0.68,
            animationDuration: 150,
            animationDelay: 0,
          ),
        ];
      case ChartType.bar:
        return [
          CandleSeries<TradingCandle, DateTime>(
            name: 'OHLC',
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            lowValueMapper: (c, _) => c.low,
            highValueMapper: (c, _) => c.high,
            openValueMapper: (c, _) => c.open,
            closeValueMapper: (c, _) => c.close,
            enableSolidCandles: false,
            bearColor: _kBearColor,
            bullColor: _kBullColor,
            width: 0.3,
            animationDuration: 400,
            animationDelay: 0,
          ),
        ];
      case ChartType.hollowCandle:
        return [
          CandleSeries<TradingCandle, DateTime>(
            name: 'OHLC',
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            lowValueMapper: (c, _) => c.low,
            highValueMapper: (c, _) => c.high,
            openValueMapper: (c, _) => c.open,
            closeValueMapper: (c, _) => c.close,
            enableSolidCandles: false,
            bearColor: _kBearColor,
            bullColor: _kBullColor,
            width: 0.7,
            animationDuration: 400,
            animationDelay: 0,
          ),
        ];
      case ChartType.line:
        return [
          FastLineSeries<TradingCandle, DateTime>(
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            color: isUp ? _kBullColor : _kBearColor,
            width: 1.5,
            animationDuration: 500,
            animationDelay: 0,
          ),
        ];
      case ChartType.area:
        final areaColor = isUp ? _kBullColor : _kBearColor;
        return [
          AreaSeries<TradingCandle, DateTime>(
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            // Subtle gradient fill
            color: areaColor.withOpacity(0.08),
            borderColor: areaColor,
            borderWidth: 1.5,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [areaColor.withOpacity(0.18), areaColor.withOpacity(0.0)],
            ),
            animationDuration: 500,
            animationDelay: 0,
          ),
        ];
    }
  }

  List<CartesianSeries> _buildEmaSeries(
    List<TradingCandle> data,
    List<double?> emaValues,
  ) {
    final emaData = <(DateTime, double)>[];
    for (var i = 0; i < data.length; i++) {
      if (emaValues[i] != null) {
        emaData.add((data[i].time, emaValues[i]!));
      }
    }
    return [
      FastLineSeries<(DateTime, double), DateTime>(
        name: 'EMA 20',
        dataSource: emaData,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: const Color(0xFFFFA726), // amber
        width: 1.2,
        animationDuration: 400,
      ),
    ];
  }

  List<CartesianSeries> _buildBollingerSeries(
    List<TradingCandle> data,
    List<(double?, double?, double?)> bbValues,
  ) {
    final upper = <(DateTime, double)>[];
    final middle = <(DateTime, double)>[];
    final lower = <(DateTime, double)>[];
    for (var i = 0; i < data.length; i++) {
      final bb = bbValues[i];
      if (bb.$1 != null) {
        upper.add((data[i].time, bb.$1!));
        middle.add((data[i].time, bb.$2!));
        lower.add((data[i].time, bb.$3!));
      }
    }
    const bbColor = Color(0xFF9C27B0); // purple
    return [
      FastLineSeries<(DateTime, double), DateTime>(
        name: 'BB Upper',
        dataSource: upper,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: bbColor.withOpacity(0.8),
        width: 1,
        animationDuration: 400,
      ),
      FastLineSeries<(DateTime, double), DateTime>(
        name: 'BB Middle',
        dataSource: middle,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: bbColor.withOpacity(0.4),
        width: 1,
        dashArray: const [4, 3],
        animationDuration: 400,
      ),
      FastLineSeries<(DateTime, double), DateTime>(
        name: 'BB Lower',
        dataSource: lower,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: bbColor.withOpacity(0.8),
        width: 1,
        animationDuration: 400,
      ),
    ];
  }

  CartesianSeries _buildCompareSeries(TradingChartSeries compareSeries) {
    return FastLineSeries<TradingCandle, DateTime>(
      name: _compareSymbol ?? 'Compare',
      dataSource: compareSeries.data,
      xValueMapper: (c, _) => c.time,
      yValueMapper: (c, _) => c.close,
      color: const Color(0xFFFFD600), // yellow
      width: 1.5,
      animationDuration: 400,
    );
  }

  void _showIndicatorPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Indicators',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _indicatorChip('EMA', _showEma, (v) {
                    setState(() => _showEma = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('Bollinger Bands', _showBollinger, (v) {
                    setState(() => _showBollinger = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('MACD', _showMacd, (v) {
                    setState(() => _showMacd = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('RSI', _showRsi, (v) {
                    setState(() => _showRsi = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('Stochastic', _showStochastic, (v) {
                    setState(() => _showStochastic = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('CCI', _showCci, (v) {
                    setState(() => _showCci = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('Williams %R', _showWilliamsR, (v) {
                    setState(() => _showWilliamsR = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('OBV', _showObv, (v) {
                    setState(() => _showObv = v);
                    setModalState(() {});
                  }),
                  _indicatorChip('ATR', _showAtr, (v) {
                    setState(() => _showAtr = v);
                    setModalState(() {});
                  }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _indicatorChip(
    String label,
    bool active,
    ValueChanged<bool> onChanged,
  ) {
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: onChanged,
      selectedColor: AppColors.primary.withOpacity(0.15),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        color: active ? AppColors.primary : AppColors.textSecondary,
        fontSize: 12,
      ),
    );
  }

  void _showDrawingToolsSheet(BuildContext context) {
    final tools = [
      (LucideIcons.minus, 'Horizontal Line'),
      (LucideIcons.trendingUp, 'Trend Line'),
      (LucideIcons.square, 'Rectangle'),
      (LucideIcons.gitBranch, 'Fibonacci'),
      (LucideIcons.type, 'Text Annotation'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Drawing Tools',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tools.map((t) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Drawing tool: ${t.$2} selected'),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$1, size: 20, color: AppColors.textPrimary),
                            const SizedBox(height: 4),
                            Text(
                              t.$2,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCompareDialog(BuildContext context, dynamic store) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compare Symbol'),
        content: TextField(
          controller: _compareController,
          decoration: const InputDecoration(
            hintText: 'Enter symbol (e.g. RELIANCE)',
            labelText: 'Symbol',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _compareSymbol = null);
              _compareController.clear();
              _loadSeries();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final sym = _compareController.text.trim().toUpperCase();
              if (sym.isNotEmpty) {
                setState(() => _compareSymbol = sym);
                _loadSeries();
              }
              Navigator.pop(context);
            },
            child: const Text('Compare'),
          ),
        ],
      ),
    );
  }
}
