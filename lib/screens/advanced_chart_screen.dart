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

class AdvancedChartScreen extends StatefulWidget {
  final String symbol;
  const AdvancedChartScreen({super.key, required this.symbol});

  @override
  State<AdvancedChartScreen> createState() => _AdvancedChartScreenState();
}

class _AdvancedChartScreenState extends State<AdvancedChartScreen> {
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  ChartType _chartType = ChartType.candles;
  ChartTimeframe _timeframe = ChartTimeframe.d1;
  ChartDateRange _dateRange = ChartDateRange.mo1;

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
    _loadSeries();
  }

  @override
  void dispose() {
    _compareController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = TradingScope.of(context);
      final stock = store.stockBySymbol(widget.symbol);
      final mainRows = await _api.getHistoricalData(
        stock.symbol,
        interval: _apiInterval(_timeframe),
        from: _fmtApiDate(_fromForRange(DateTime.now().toUtc(), _dateRange)),
        to: _fmtApiDate(DateTime.now().toUtc()),
      );
      TradingChartSeries? compare;
      if (_compareSymbol != null) {
        final cmpStock = store.stockBySymbol(_compareSymbol!);
        final cmpRows = await _api.getHistoricalData(
          cmpStock.symbol,
          interval: _apiInterval(_timeframe),
          from: _fmtApiDate(_fromForRange(DateTime.now().toUtc(), _dateRange)),
          to: _fmtApiDate(DateTime.now().toUtc()),
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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

  String _fmtApiDate(DateTime utc) {
    final d = utc.toLocal();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$m-$day $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);
    final series =
        _series ??
        TradingChartService.fromRawCandles(
          const [],
          fallbackPrice: stock.currentPrice,
        );
    final compareSeries = _compareSeries;

    final chartData = _chartType == ChartType.heikinAshi
        ? TradingChartService.toHeikinAshi(series.data)
        : series.data;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${stock.symbol} — Advanced Chart'),
        actions: [
          IconButton(
            tooltip: 'Indicators',
            icon: const Icon(LucideIcons.barChart2, size: 20),
            onPressed: () => _showIndicatorPanel(context),
          ),
          IconButton(
            tooltip: 'Compare',
            icon: const Icon(LucideIcons.gitCompare, size: 20),
            onPressed: () => _showCompareDialog(context, store),
          ),
          IconButton(
            tooltip: 'Drawing Tools',
            icon: const Icon(LucideIcons.edit, size: 20),
            onPressed: () => _showDrawingToolsSheet(context),
          ),
          IconButton(
            tooltip: 'Screenshot',
            icon: const Icon(LucideIcons.camera, size: 20),
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Screenshot saved'))),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Live chart unavailable: $_error',
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          Expanded(child: _buildChart(chartData, series, compareSeries)),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Chart type selector
            _chartTypeSelector(),
            const SizedBox(width: 16),
            const VerticalDivider(width: 1, thickness: 1),
            const SizedBox(width: 16),
            // Timeframe chips
            ..._timeframeChips(),
            const SizedBox(width: 16),
            const VerticalDivider(width: 1, thickness: 1),
            const SizedBox(width: 16),
            // Date range chips
            ..._dateRangeChips(),
          ],
        ),
      ),
    );
  }

  Widget _chartTypeSelector() {
    final types = [
      (ChartType.candles, 'Candles', LucideIcons.candlestickChart),
      (ChartType.heikinAshi, 'HA', LucideIcons.candlestickChart),
      (ChartType.line, 'Line', LucideIcons.trendingUp),
      (ChartType.area, 'Area', LucideIcons.areaChart),
      (ChartType.bar, 'Bar', LucideIcons.barChart),
    ];
    return Row(
      children: types.map((t) {
        final selected = _chartType == t.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: InkWell(
            onTap: () => setState(() => _chartType = t.$1),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
              ),
              child: Text(
                t.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _timeframeChips() {
    const labels = [
      '1m',
      '3m',
      '5m',
      '15m',
      '30m',
      '1H',
      '4H',
      '1D',
      '1W',
      '1M',
    ];
    const values = [
      ChartTimeframe.m1,
      ChartTimeframe.m3,
      ChartTimeframe.m5,
      ChartTimeframe.m15,
      ChartTimeframe.m30,
      ChartTimeframe.h1,
      ChartTimeframe.h4,
      ChartTimeframe.d1,
      ChartTimeframe.w1,
      ChartTimeframe.mo1,
    ];
    return List.generate(labels.length, (i) {
      final selected = _timeframe == values[i];
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _toolbarChip(labels[i], selected, () {
          setState(() => _timeframe = values[i]);
          _loadSeries();
        }),
      );
    });
  }

  List<Widget> _dateRangeChips() {
    const labels = ['1D', '5D', '1M', '3M', '6M', '1Y', '3Y', '5Y', 'Max'];
    const values = [
      ChartDateRange.d1,
      ChartDateRange.d5,
      ChartDateRange.mo1,
      ChartDateRange.mo3,
      ChartDateRange.mo6,
      ChartDateRange.y1,
      ChartDateRange.y3,
      ChartDateRange.y5,
      ChartDateRange.max,
    ];
    return List.generate(labels.length, (i) {
      final selected = _dateRange == values[i];
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _toolbarChip(labels[i], selected, () {
          setState(() => _dateRange = values[i]);
          _loadSeries();
        }),
      );
    });
  }

  Widget _toolbarChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildChart(
    List<TradingCandle> chartData,
    TradingChartSeries series,
    TradingChartSeries? compareSeries,
  ) {
    final closes = chartData.map((c) => c.close).toList();
    final emaValues = _showEma ? TradingChartService.ema(closes, 20) : null;
    final bbValues = _showBollinger
        ? TradingChartService.bollingerBands(closes, 20, 2.0)
        : null;

    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      margin: const EdgeInsets.all(8),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        enableMouseWheelZooming: true,
        zoomMode: ZoomMode.x,
      ),
      trackballBehavior: TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
        lineType: TrackballLineType.vertical,
        lineColor: AppColors.textSecondary.withOpacity(0.5),
        lineWidth: 1,
        tooltipSettings: const InteractiveTooltip(
          enable: true,
          format: 'point.x : point.y',
        ),
      ),
      primaryXAxis: DateTimeAxis(
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: const AxisLine(width: 0),
        dateFormat: DateFormat.Hm(),
        intervalType: DateTimeIntervalType.auto,
        labelStyle: const TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary,
        ),
      ),
      primaryYAxis: NumericAxis(
        opposedPosition: true,
        majorGridLines: const MajorGridLines(
          color: AppColors.border,
          width: 0.5,
        ),
        axisLine: const AxisLine(width: 0),
        numberFormat: NumberFormat.simpleCurrency(decimalDigits: 0, name: '₹'),
        labelStyle: const TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary,
        ),
      ),
      series: <CartesianSeries>[
        ..._buildMainSeries(chartData, series),
        if (emaValues != null) ..._buildEmaSeries(chartData, emaValues),
        if (bbValues != null) ..._buildBollingerSeries(chartData, bbValues),
        if (compareSeries != null) _buildCompareSeries(compareSeries),
      ],
    );
  }

  List<CartesianSeries> _buildMainSeries(
    List<TradingCandle> data,
    TradingChartSeries series,
  ) {
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
            bearColor: AppColors.danger,
            bullColor: AppColors.success,
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
            enableSolidCandles: true,
            bearColor: AppColors.danger,
            bullColor: AppColors.success,
            width: 0.3,
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
            bearColor: AppColors.danger,
            bullColor: AppColors.success,
          ),
        ];
      case ChartType.line:
        return [
          LineSeries<TradingCandle, DateTime>(
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            color: series.close >= series.open
                ? AppColors.success
                : AppColors.danger,
            width: 2,
          ),
        ];
      case ChartType.area:
        return [
          AreaSeries<TradingCandle, DateTime>(
            dataSource: data,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            color:
                (series.close >= series.open
                        ? AppColors.success
                        : AppColors.danger)
                    .withOpacity(0.1),
            borderColor: series.close >= series.open
                ? AppColors.success
                : AppColors.danger,
            borderWidth: 2,
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
      LineSeries<(DateTime, double), DateTime>(
        name: 'EMA 20',
        dataSource: emaData,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: Colors.orange,
        width: 1.5,
        dashArray: const [4, 2],
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
    return [
      LineSeries<(DateTime, double), DateTime>(
        name: 'BB Upper',
        dataSource: upper,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: Colors.purple.withOpacity(0.7),
        width: 1,
      ),
      LineSeries<(DateTime, double), DateTime>(
        name: 'BB Middle',
        dataSource: middle,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: Colors.purple.withOpacity(0.4),
        width: 1,
        dashArray: const [4, 2],
      ),
      LineSeries<(DateTime, double), DateTime>(
        name: 'BB Lower',
        dataSource: lower,
        xValueMapper: (d, _) => d.$1,
        yValueMapper: (d, _) => d.$2,
        color: Colors.purple.withOpacity(0.7),
        width: 1,
      ),
    ];
  }

  CartesianSeries _buildCompareSeries(TradingChartSeries compareSeries) {
    return LineSeries<TradingCandle, DateTime>(
      name: _compareSymbol ?? 'Compare',
      dataSource: compareSeries.data,
      xValueMapper: (c, _) => c.time,
      yValueMapper: (c, _) => c.close,
      color: Colors.amber,
      width: 2,
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
