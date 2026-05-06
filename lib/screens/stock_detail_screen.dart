import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import 'alert_creation_screen.dart';
import '../screens/advanced_chart_screen.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../widgets/order_form_drawer.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  int _selectedRange = 2;
  bool _useCandleChart = false; // default: line/area chart
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  OrderType _pendingOrderSide = OrderType.buy;
  late final TransformationController _chartTransformController;
  TradingChartSeries? _series;
  bool _loadingSeries = true;
  String? _seriesError;

  @override
  void initState() {
    super.initState();
    _chartTransformController = TransformationController();
    _loadSeries();
  }

  @override
  void dispose() {
    _chartTransformController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _loadingSeries = true;
      _seriesError = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final from = _fromForRange(now, _selectedRange);
      final interval = _intervalForRange(_selectedRange);
      final candles = await _api.getHistoricalData(
        widget.symbol.toUpperCase(),
        interval: interval,
        from: _fmtApiDate(from),
        to: _fmtApiDate(now),
      );
      if (!mounted) return;
      final store = TradingScope.of(context);
      final stock = store.stockBySymbol(widget.symbol);
      setState(() {
        _series = TradingChartService.fromRawCandles(
          candles,
          fallbackPrice: stock.currentPrice,
        );
        _loadingSeries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _seriesError = e.toString();
        _loadingSeries = false;
      });
    }
  }

  DateTime _fromForRange(DateTime nowUtc, int rangeIdx) {
    switch (rangeIdx) {
      case 0:
        return nowUtc.subtract(const Duration(days: 1));
      case 1:
        return nowUtc.subtract(const Duration(days: 7));
      case 2:
        return nowUtc.subtract(const Duration(days: 30));
      case 3:
        return nowUtc.subtract(const Duration(days: 90));
      case 4:
        return nowUtc.subtract(const Duration(days: 180));
      case 5:
        return nowUtc.subtract(const Duration(days: 365));
      default:
        return nowUtc.subtract(const Duration(days: 365 * 5));
    }
  }

  String _intervalForRange(int rangeIdx) {
    if (rangeIdx <= 1) return '5m';
    if (rangeIdx <= 3) return '30m';
    if (rangeIdx <= 5) return '1h';
    return '1d';
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
    final isDesktop = MediaQuery.of(context).size.width >= 1060;
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);
    final isPos = stock.changePercentage >= 0;
    final series =
        _series ??
        TradingChartService.fromRawCandles(
          const [],
          fallbackPrice: stock.currentPrice,
        );
    final chartColor = isPos
        ? const Color(0xFF00C853)
        : const Color(0xFFD50000);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, store, stock),
      bottomNavigationBar: _buildBottomBar(context, stock),
      endDrawer: OrderFormDrawer(stock: stock, initialSide: _pendingOrderSide),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stock header ──────────────────────────────────────────────
            _buildStockHeader(context, stock),
            // ── Chart ─────────────────────────────────────────────────────
            _buildChartSection(context, series, chartColor, !_useCandleChart),
            if (_loadingSeries)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_seriesError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Live chart unavailable: $_seriesError',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD32F2F),
                  ),
                ),
              ),
            // ── Timeframe selector ────────────────────────────────────────
            _buildTimeframeRow(context),
            const SizedBox(height: 24),
            // ── Market stats ──────────────────────────────────────────────
            _buildSectionHeader('Market stats'),
            _buildStatsGrid(context, stock, series, isDesktop),
            const SizedBox(height: 24),
            // ── Fundamentals ──────────────────────────────────────────────
            _buildSectionHeader('Fundamentals'),
            _buildFundamentalsGrid(context, stock),
            const SizedBox(height: 24),
            // ── About ─────────────────────────────────────────────────────
            _buildAboutSection(context, stock),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, store, Stock stock) {
    final inWatchlist = store.isInWatchlist(stock.symbol);
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF0D0D0D), size: 24),
        onPressed: () => Navigator.pop(context),
      ),
      title: null,
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_outlined,
            color: Color(0xFF0D0D0D),
            size: 24,
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlertCreationScreen(initialSymbol: stock.symbol),
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            inWatchlist ? Icons.bookmark : Icons.bookmark_border,
            color: inWatchlist
                ? const Color(0xFF00897B)
                : const Color(0xFF0D0D0D),
            size: 24,
          ),
          onPressed: () {
            if (inWatchlist) {
              store.removeFromWatchlist(stock.symbol);
            } else {
              store.addToWatchlist(stock.symbol);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  inWatchlist
                      ? '${stock.symbol} removed from watchlist'
                      : '${stock.symbol} added to watchlist',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
      shape: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
    );
  }

  Widget _buildStockHeader(BuildContext context, Stock stock) {
    final isPos = stock.changePercentage >= 0;
    final changeColor = isPos
        ? const Color(0xFF00C853)
        : const Color(0xFFD50000);
    final arrow = isPos ? '+' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo / letter avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            alignment: Alignment.center,
            child: Text(
              stock.symbol.isNotEmpty ? stock.symbol[0] : '?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Symbol · NSE
          Row(
            children: [
              Text(
                '${stock.symbol} · ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF757575),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NSE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Full company name
          Text(
            stock.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0D0D0D),
            ),
          ),
          const SizedBox(height: 8),
          // LTP
          Text(
            '₹${stock.currentPrice.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0D0D0D),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          // Change
          Text(
            '${arrow}${stock.changePercentage >= 0 ? '' : ''}${(stock.currentPrice * stock.changePercentage / 100).toStringAsFixed(2)} (${arrow}${stock.changePercentage.toStringAsFixed(2)}%) · 1D',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: changeColor,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChartSection(
    BuildContext context,
    TradingChartSeries series,
    Color chartColor,
    bool use1DLine,
  ) {
    return Stack(
      children: [
        SizedBox(
          height: 220,
          child: use1DLine
              ? SfCartesianChart(
                  enableAxisAnimation: false,
                  plotAreaBorderWidth: 0,
                  margin: EdgeInsets.zero,
                  primaryXAxis: DateTimeAxis(isVisible: false),
                  primaryYAxis: NumericAxis(
                    opposedPosition: true,
                    majorGridLines: const MajorGridLines(width: 0),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  trackballBehavior: TrackballBehavior(
                    enable: true,
                    activationMode: ActivationMode.singleTap,
                    lineColor: chartColor.withOpacity(0.5),
                    lineWidth: 1,
                  ),
                  series: <CartesianSeries>[
                    AreaSeries<TradingCandle, DateTime>(
                      dataSource: series.data,
                      xValueMapper: (c, _) => c.time,
                      yValueMapper: (c, _) => c.close,
                      color: chartColor.withOpacity(0.08),
                      borderColor: chartColor,
                      borderWidth: 2,
                      animationDuration: 0,
                    ),
                  ],
                )
              : SfCartesianChart(
                  enableAxisAnimation: false,
                  plotAreaBorderWidth: 0,
                  margin: EdgeInsets.zero,
                  primaryXAxis: DateTimeAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  primaryYAxis: NumericAxis(
                    opposedPosition: true,
                    majorGridLines: const MajorGridLines(
                      color: Color(0xFFF5F5F5),
                      width: 0.5,
                    ),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  trackballBehavior: TrackballBehavior(
                    enable: true,
                    activationMode: ActivationMode.singleTap,
                    lineColor: const Color(0xFF9E9E9E),
                    lineWidth: 1,
                  ),
                  series: <CartesianSeries>[
                    CandleSeries<TradingCandle, DateTime>(
                      dataSource: series.data,
                      xValueMapper: (c, _) => c.time,
                      lowValueMapper: (c, _) => c.low,
                      highValueMapper: (c, _) => c.high,
                      openValueMapper: (c, _) => c.open,
                      closeValueMapper: (c, _) => c.close,
                      enableSolidCandles: true,
                      bearColor: const Color(0xFFD50000),
                      bullColor: const Color(0xFF00C853),
                      animationDuration: 0,
                    ),
                  ],
                ),
        ),
        // Expand icon
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdvancedChartScreen(symbol: widget.symbol),
              ),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: const Icon(
                Icons.open_in_full,
                size: 16,
                color: Color(0xFF757575),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeframeRow(BuildContext context) {
    const labels = ['1D', '1W', '1M', '3M', '6M', '1Y', '5Y', 'All'];
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Timeframe pills — scrollable so they never overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: List.generate(labels.length, (i) {
                  final selected = i == _selectedRange;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedRange = i);
                      _loadSeries();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF0D0D0D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          // Candle / Line toggle button — same height as timeframe pills
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => setState(() => _useCandleChart = !_useCandleChart),
              child: Tooltip(
                message: _useCandleChart
                    ? 'Switch to Line chart'
                    : 'Switch to Candle chart',
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _useCandleChart
                        ? const Color(0xFF0D0D0D)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _useCandleChart
                          ? const Color(0xFF0D0D0D)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: _useCandleChart
                      ? const Icon(
                          Icons.show_chart,
                          size: 15,
                          color: Colors.white,
                        )
                      : _CandleIcon(size: 15, color: const Color(0xFF757575)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF0D0D0D),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context,
    Stock stock,
    TradingChartSeries series,
    bool isDesktop,
  ) {
    final base = stock.currentPrice;
    final stats = [
      ('Open', '₹${series.open.toStringAsFixed(2)}'),
      (
        'Prev Close',
        '₹${series.data.length > 1 ? series.data[series.data.length - 2].close.toStringAsFixed(2) : series.open.toStringAsFixed(2)}',
      ),
      ('High', '₹${series.high.toStringAsFixed(2)}'),
      ('Low', '₹${series.low.toStringAsFixed(2)}'),
      ('52W High', '₹${(base + 210).toStringAsFixed(2)}'),
      ('52W Low', '₹${(base - 390).toStringAsFixed(2)}'),
      ('Volume', '${(series.volume / 100000).toStringAsFixed(2)}L'),
      ('VWAP', '₹${series.vwap.toStringAsFixed(2)}'),
    ];
    return _twoColGrid(stats);
  }

  Widget _buildFundamentalsGrid(BuildContext context, Stock stock) {
    final base = stock.currentPrice;
    final stats = [
      ('Market Cap', '₹${(base * 6800000 / 10000000).toStringAsFixed(0)}Cr'),
      ('P/E Ratio', '${(base / 45).toStringAsFixed(1)}x'),
      ('EPS', '₹${(base / 22).toStringAsFixed(2)}'),
      ('ROE', '${(12 + base % 8).toStringAsFixed(1)}%'),
      ('P/B Ratio', '${(base / 800).toStringAsFixed(2)}x'),
      ('Div. Yield', '${(0.8 + base % 2).toStringAsFixed(2)}%'),
    ];
    return _twoColGrid(stats);
  }

  Widget _twoColGrid(List<(String, String)> stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.8,
        ),
        itemCount: stats.length,
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stats[i].$1,
                style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
              ),
              const SizedBox(height: 4),
              Text(
                stats[i].$2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0D0D0D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context, Stock stock) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About ${stock.name}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0D0D0D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${stock.name} is a leading company in the ${stock.sector} sector listed on NSE. '
            'The company operates across multiple business segments and has a strong market presence. '
            'It is known for its consistent performance and shareholder value creation.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF757575),
              height: 1.5,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {},
            child: const Text(
              'Read more',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, Stock stock) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // SELL
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => _openOrderDrawer(context, OrderType.sell),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'SELL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // BUY
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => _openOrderDrawer(context, OrderType.buy),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'BUY',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openOrderDrawer(BuildContext context, OrderType type) {
    setState(() => _pendingOrderSide = type);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildOrderDrawer(BuildContext context, Stock stock) {
    return OrderFormDrawer(stock: stock, initialSide: _pendingOrderSide);
  }
}

// ─── Candle chart icon (custom painted) ──────────────────────────────────────

class _CandleIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _CandleIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CandlePainter(color: color),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final Color color;
  const _CandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Three mini candles
    // Candle 1 (left, bearish — hollow)
    canvas.drawLine(
      Offset(w * 0.15, h * 0.1),
      Offset(w * 0.15, h * 0.9),
      paint,
    );
    canvas.drawRect(Rect.fromLTRB(w * 0.08, h * 0.3, w * 0.22, h * 0.7), paint);

    // Candle 2 (center, bullish — filled)
    canvas.drawLine(
      Offset(w * 0.5, h * 0.05),
      Offset(w * 0.5, h * 0.85),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.42, h * 0.2, w * 0.58, h * 0.65),
      fillPaint,
    );

    // Candle 3 (right, bearish — hollow)
    canvas.drawLine(
      Offset(w * 0.85, h * 0.15),
      Offset(w * 0.85, h * 0.95),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.78, h * 0.35, w * 0.92, h * 0.75),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) => old.color != color;
}
