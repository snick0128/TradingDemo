import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import 'alert_creation_screen.dart';
import '../screens/advanced_chart_screen.dart';
import '../screens/options_chain_screen.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../widgets/order_form_sheet.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, int> _savedRangeBySymbol = {};
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  int _selectedRange = 0;
  bool _useCandleChart = true;
  TradingChartSeries? _series;
  TradingChartSeries? _prevSeries;
  bool _loadingSeries = true;
  String? _seriesError;

  // Market settings stream
  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  bool _initializing = true;
  int _loadGeneration = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _selectedRange = _savedRangeBySymbol[widget.symbol] ?? 0;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _settingsSub = _settingsService.stream.listen((s) {
      if (mounted) setState(() => _marketSettings = s);
    });
    // Load required quote + chart data first, then render the detail UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAndOpen());
  }

  Future<void> _initializeAndOpen() async {
    try {
      await _loadSeries();
      await _fetchLiveQuoteIfNeeded();
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  /// If the stock has no live price (currentPrice == 0), fetch a quote
  /// from the backend using the token registered by the search screen.
  /// This covers indices (NIFTY, SENSEX) and any non-tracked instrument.
  Future<void> _fetchLiveQuoteIfNeeded() async {
    if (!mounted) return;
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(widget.symbol);

    // Already has a live price — nothing to do
    if (stock.currentPrice > 0) return;

    debugPrint(
      '[StockDetail] No live price for ${widget.symbol} — fetching...',
    );

    double ltp = 0;
    double pct = 0;

    // Strategy 1: Try /market/stock?symbol= (reads from live WebSocket cache)
    // This works for any symbol the backend has ever received a tick for.
    try {
      final detail = await _api.getStockDetail(widget.symbol.toUpperCase());
      final rawLtp = (detail['ltp'] as num?)?.toDouble() ?? 0.0;
      if (rawLtp > 0) {
        ltp = rawLtp;
        pct = (detail['changePercent'] as num?)?.toDouble() ?? 0.0;
        debugPrint('[StockDetail] Got price from /market/stock: ₹$ltp');
      }
    } catch (_) {}

    // Strategy 2: Try /derivatives/quote?token=...&exchange=... (Angel One REST)
    // Works for any instrument with a valid token, including MCX futures.
    if (ltp <= 0 && stock.token.isNotEmpty) {
      try {
        final quote = await _api.getQuoteByToken(
          stock.token,
          exchange: stock.exchange.isNotEmpty ? stock.exchange : 'NSE',
        );
        final rawLtp = (quote['ltp'] as num?)?.toDouble() ?? 0.0;
        if (rawLtp > 0) {
          ltp = rawLtp;
          pct = (quote['percentChange'] as num?)?.toDouble() ?? 0.0;
          debugPrint('[StockDetail] Got price from /derivatives/quote: ₹$ltp');
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (ltp > 0) {
      store.registerSearchResult(
        symbol: widget.symbol,
        displayName: stock.name.isNotEmpty ? stock.name : widget.symbol,
        exchange: stock.exchange.isNotEmpty ? stock.exchange : 'NSE',
        token: stock.token,
        ltp: ltp,
        changePercent: pct,
      );
      if (mounted) setState(() {});
      debugPrint('[StockDetail] Price updated: ${widget.symbol} = ₹$ltp');
    } else {
      debugPrint('[StockDetail] Could not fetch price for ${widget.symbol}');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fadeCtrl.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    if (!mounted) return;
    _refreshTimer?.cancel();
    final gen = ++_loadGeneration;

    setState(() {
      _loadingSeries = true;
      _seriesError = null;
      _prevSeries = _series;
    });
    _fadeCtrl.reverse();

    for (int attempt = 0; attempt < 4; attempt++) {
      if (gen != _loadGeneration || !mounted) return;
      if (attempt > 0) {
        // Exponential backoff: 2s, 4s, 8s
        await Future.delayed(Duration(seconds: 2 << (attempt - 1)));
        if (gen != _loadGeneration || !mounted) return;
      }
      try {
        final now = DateTime.now().toUtc();
        final interval = _intervalForRange(_selectedRange);
        final from = _fromForRange(now, _selectedRange);
        final store = TradingScope.of(context);
        final stock = store.stockBySymbol(widget.symbol);

        // Warmup ping on first attempt — avoids Render cold-start blocking the fetch.
        if (attempt == 0) {
          _api.getHealth().catchError((_) => <String, dynamic>{});
        }

        final candles = await _api.getHistoricalData(
          widget.symbol.toUpperCase(),
          interval: interval,
          from: _fmtApiDate(from, interval: interval),
          to: _fmtApiDate(now, interval: interval),
          exchange: stock.exchange.isNotEmpty ? stock.exchange : null,
          token: stock.token.isNotEmpty ? stock.token : null,
        );
        if (gen != _loadGeneration || !mounted) return;
        setState(() {
          final maxCandles = _maxCandlesForRange(_selectedRange);
          final visibleCandles = candles.length > maxCandles
              ? candles.sublist(candles.length - maxCandles)
              : candles;
          _series = TradingChartService.fromRawCandles(
            visibleCandles,
            fallbackPrice: stock.currentPrice,
          );
          _prevSeries = null;
          _loadingSeries = false;
          _seriesError = null;
        });
        _fadeCtrl.forward();
        // Auto-refresh intraday and weekly charts every 30s
        if (_selectedRange <= 1) {
          _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted) _loadSeries();
          });
        }
        return;
      } catch (e) {
        if (attempt < 3) continue; // retry with backoff
        if (gen != _loadGeneration || !mounted) return;
        setState(() {
          _seriesError = e.toString();
          _loadingSeries = false;
        });
        _fadeCtrl.forward();
      }
    }
  }

  int _maxCandlesForRange(int rangeIdx) {
    switch (rangeIdx) {
      case 0:
        return 78; // 1D @ 5m → ~78 candles in a trading day
      case 1:
        return 120; // 1W @ 15m → ~120 candles
      case 2:
        return 160; // 1M @ 1h → ~160 candles
      case 3:
        return 250; // 1Y @ 1d → ~250 trading days
      case 4:
        return 260; // 5Y @ 1w → ~260 weeks
      default:
        return 300; // Max @ 1w
    }
  }

  DateTime _fromForRange(DateTime nowUtc, int rangeIdx) {
    switch (rangeIdx) {
      case 0:
        return nowUtc.subtract(const Duration(days: 1)); // 1D
      case 1:
        return nowUtc.subtract(const Duration(days: 7)); // 1W
      case 2:
        return nowUtc.subtract(const Duration(days: 30)); // 1M
      case 3:
        return nowUtc.subtract(const Duration(days: 365)); // 1Y
      case 4:
        return nowUtc.subtract(const Duration(days: 365 * 5)); // 5Y
      default:
        return nowUtc.subtract(const Duration(days: 365 * 20)); // Max
    }
  }

  String _intervalForRange(int rangeIdx) {
    switch (rangeIdx) {
      case 0: // 1D
        return '5m';
      case 1: // 1W
        return '15m';
      case 2: // 1M
        return '1h';
      case 3: // 1Y
        return '1d';
      case 4: // 5Y
        return '1w';
      default: // Max
        return '1w';
    }
  }

  /// Format a date for the API, rounding down to the candle interval boundary
  /// so the cache key stays stable between screen opens within the same window.
  /// e.g. 17:17 on a 30m chart → 17:00, on a 5m chart → 17:15.
  String _fmtApiDate(DateTime utc, {String interval = '1d'}) {
    final d = utc.toLocal();
    final int roundedMin;
    final int roundedHour;
    switch (interval) {
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
      case '4h':
        roundedMin = 0;
        roundedHour = (d.hour ~/ 4) * 4;
      default: // '1d', '1w' and anything coarser → truncate to midnight
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
    final rawStock = store.stockBySymbol(widget.symbol);

    if (_initializing) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(context, store, rawStock),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text(
                'Fetching live price & chart…',
                style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
              ),
            ],
          ),
        ),
      );
    }

    // Show previous series while loading new one (no blank flash)
    final displaySeries =
        _series ??
        _prevSeries ??
        TradingChartService.fromRawCandles(
          const [],
          fallbackPrice: rawStock.currentPrice,
        );
    // If watchlist/universe doesn't have a live quote yet (e.g. index symbols),
    // use latest candle close so header/order UI never shows ₹0.00.
    final stock = _withSeriesFallback(rawStock, displaySeries);
    final isPos = stock.changePercentage >= 0;
    final chartColor = isPos
        ? const Color(0xFF00C853)
        : const Color(0xFFD50000);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, store, stock),
      bottomNavigationBar: _buildBottomBar(context, stock),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStockHeader(context, stock),
            _buildChartSection(
              context,
              displaySeries,
              chartColor,
              !_useCandleChart,
            ),
            // Error banner with retry button
            if (_seriesError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    const Text(
                      'Chart unavailable',
                      style: TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _loadSeries,
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _buildTimeframeRow(context),
            const SizedBox(height: 24),
            _buildSectionHeader('Market stats'),
            _buildStatsGrid(
              context,
              stock,
              displaySeries,
              MediaQuery.of(context).size.width >= 1060,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Fundamentals'),
            _buildFundamentalsGrid(context, stock),
            const SizedBox(height: 24),
            if (_supportsDerivatives(stock)) _buildDerivativesSection(context),
            const SizedBox(height: 24),
            _buildAboutSection(context, stock),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  /// Build a display-safe stock model by falling back to chart-derived values
  /// when stream quote is unavailable.
  Stock _withSeriesFallback(Stock stock, TradingChartSeries series) {
    final hasLiveLtp = stock.currentPrice > 0;
    final hasSeries = series.data.isNotEmpty;
    if (hasLiveLtp || !hasSeries) return stock;

    final ltp = series.data.last.close;
    final prevClose = series.data.length > 1
        ? series.data[series.data.length - 2].close
        : (series.open > 0 ? series.open : ltp);
    final pct = prevClose > 0 ? ((ltp - prevClose) / prevClose) * 100 : 0.0;

    return Stock(
      symbol: stock.symbol,
      name: stock.name,
      currentPrice: ltp,
      changePercentage: pct,
      sector: stock.sector,
      exchange: stock.exchange,
      token: stock.token,
      open: stock.open,
      high: stock.high,
      low: stock.low,
      prevClose: stock.prevClose ?? prevClose,
      week52High: stock.week52High,
      week52Low: stock.week52Low,
      upperCircuit: stock.upperCircuit,
      lowerCircuit: stock.lowerCircuit,
      volume: stock.volume,
      marketCap: stock.marketCap,
      isStale: stock.isStale,
      expiry: stock.expiry,
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
    final changeColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final arrow = isPos ? '+' : '';
    final exColor = _exchangeBadgeColor(stock.exchange);
    final chips = _derivativeChips(context, stock);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compact two-column header row ──────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: avatar + symbol + name
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small letter badge
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: exColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: exColor.withOpacity(0.25)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        stock.symbol.isNotEmpty ? stock.symbol[0] : '?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: exColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Symbol + exchange badge row
                          Row(
                            children: [
                              Text(
                                stock.symbol,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0D0D0D),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: exColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  stock.exchange.isNotEmpty
                                      ? stock.exchange
                                      : 'NSE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: exColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Expiry badge on its own line so it never overlaps price
                          if (stock.isFutures) ...[
                            const SizedBox(height: 3),
                            _ExpiryBadge(stock: stock),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            stock.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right: LTP + change
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${stock.currentPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0D0D0D),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: changeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$arrow${(stock.currentPrice * stock.changePercentage / 100).toStringAsFixed(2)} ($arrow${stock.changePercentage.abs().toStringAsFixed(2)}%)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: changeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // ── Derivative chips ────────────────────────────────────────────
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: chips),
          ],
          const SizedBox(height: 12),
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
    final fadeOpacity = _loadingSeries && _prevSeries == null
        ? const AlwaysStoppedAnimation(0.4)
        : _fadeAnim;
    final hasRealCandles = series.data.isNotEmpty && series.close > 0;
    // Use line chart when only 1 candle exists — candle series can't render a single point
    final effectiveLineMode = use1DLine || series.data.length <= 1;
    final low = hasRealCandles
        ? series.data.map((c) => c.low).reduce((a, b) => a < b ? a : b)
        : 0.0;
    final high = hasRealCandles
        ? series.data.map((c) => c.high).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final pad = high > low ? (high - low) * 0.12 : high * 0.01;
    final showVolume = series.data.any((c) => c.volume > 0);

    final prevCloseRef = _selectedRange == 0
        ? series.open // 1D: use today's open
        : (series.data.isNotEmpty
            ? series.data.first.close // other ranges: first candle close
            : 0.0);

    // Clamp axis to data range so no empty gaps appear (e.g. NIFTY index charts)
    final axisMin = hasRealCandles ? series.data.first.time : null;
    final axisMax = hasRealCandles
        ? series.data.last.time.add(
            _selectedRange <= 1
                ? const Duration(minutes: 5)
                : const Duration(days: 1),
          )
        : null;

    return Stack(
      children: [
        Column(
          children: [
            Container(
              color: Colors.white,
              child: SizedBox(
                height: 300,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FadeTransition(
                    opacity: fadeOpacity,
                    child: !hasRealCandles
                        ? const Center(
                            child: Text(
                              'Chart data unavailable',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF757575),
                              ),
                            ),
                          )
                        : effectiveLineMode
                        ? SfCartesianChart(
                            backgroundColor: Colors.white,
                            plotAreaBackgroundColor: Colors.white,
                            enableAxisAnimation: true,
                            plotAreaBorderWidth: 0,
                            margin: const EdgeInsets.only(right: 8),
                        primaryXAxis: DateTimeAxis(
                          isVisible: false,
                          minimum: axisMin,
                          maximum: axisMax,
                          majorGridLines: const MajorGridLines(width: 0),
                          axisLine: const AxisLine(width: 0),
                          majorTickLines: const MajorTickLines(size: 0),
                        ),
                        primaryYAxis: NumericAxis(
                          isVisible: false,
                          rangePadding: ChartRangePadding.round,
                          plotBands: hasRealCandles && prevCloseRef > 0
                              ? <PlotBand>[
                                  PlotBand(
                                    start: prevCloseRef,
                                    end: prevCloseRef,
                                    borderColor: const Color(0xFFBDBDBD),
                                    borderWidth: 1,
                                    dashArray: const <double>[5, 4],
                                  ),
                                ]
                              : [],
                          majorGridLines: const MajorGridLines(width: 0),
                          axisLine: const AxisLine(width: 0),
                          majorTickLines: const MajorTickLines(size: 0),
                        ),
                        trackballBehavior: TrackballBehavior(
                          enable: true,
                          activationMode: ActivationMode.singleTap,
                          lineColor: chartColor.withOpacity(0.4),
                          lineWidth: 1,
                        ),
                        series: <CartesianSeries>[
                          LineSeries<TradingCandle, DateTime>(
                            dataSource: series.data,
                            xValueMapper: (c, _) => c.time,
                            yValueMapper: (c, _) => c.close,
                            color: chartColor,
                            width: 2.2,
                            animationDuration: 0,
                          ),
                        ],
                      )
                    : SfCartesianChart(
                        backgroundColor: Colors.white,
                        plotAreaBackgroundColor: Colors.white,
                        enableAxisAnimation: true,
                        plotAreaBorderWidth: 0,
                        margin: const EdgeInsets.only(right: 8),
                        primaryXAxis: DateTimeAxis(
                          isVisible: false,
                          minimum: axisMin,
                          maximum: axisMax,
                          majorGridLines: const MajorGridLines(width: 0),
                          axisLine: const AxisLine(width: 0),
                          majorTickLines: const MajorTickLines(size: 0),
                        ),
                        primaryYAxis: NumericAxis(
                          isVisible: false,
                          rangePadding: ChartRangePadding.round,
                          plotBands: hasRealCandles && prevCloseRef > 0
                              ? <PlotBand>[
                                  PlotBand(
                                    start: prevCloseRef,
                                    end: prevCloseRef,
                                    borderColor: const Color(0xFFBDBDBD),
                                    borderWidth: 1,
                                    dashArray: const <double>[5, 4],
                                  ),
                                ]
                              : [],
                          majorGridLines: const MajorGridLines(width: 0),
                          axisLine: const AxisLine(width: 0),
                          majorTickLines: const MajorTickLines(size: 0),
                        ),
                        trackballBehavior: TrackballBehavior(
                          enable: true,
                          activationMode: ActivationMode.singleTap,
                          lineColor: const Color(0xFFBDBDBD),
                          lineWidth: 1,
                        ),
                        zoomPanBehavior: ZoomPanBehavior(
                          enablePinching: true,
                          enablePanning: true,
                          enableMouseWheelZooming: true,
                          zoomMode: ZoomMode.x,
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
                            bearColor: const Color(0xFFE53935),
                            bullColor: const Color(0xFF00C853),
                            width: series.data.length > 100 ? 0.7 : 0.6,
                            spacing: series.data.length > 100 ? 0.1 : 0.15,
                            animationDuration: 0,
                          ),
                        ],
                      ),
                  ),
                ),
              ),
            ),
            // ── Volume overlay ─────────────────────────────────────────────
            if (showVolume)
              SizedBox(
                height: 44,
                child: FadeTransition(
                  opacity: fadeOpacity,
                  child: SfCartesianChart(
                    enableAxisAnimation: false,
                    plotAreaBorderWidth: 0,
                    margin: const EdgeInsets.only(right: 4),
                    primaryXAxis: DateTimeAxis(isVisible: false),
                    primaryYAxis: NumericAxis(
                      isVisible: false,
                      majorGridLines: const MajorGridLines(width: 0),
                    ),
                    series: <CartesianSeries>[
                      ColumnSeries<TradingCandle, DateTime>(
                        dataSource: series.data,
                        xValueMapper: (c, _) => c.time,
                        yValueMapper: (c, _) => c.volume,
                        pointColorMapper: (c, _) => c.close >= c.open
                            ? const Color(0xFF00C853).withOpacity(0.28)
                            : const Color(0xFFE53935).withOpacity(0.28),
                        borderWidth: 0,
                        spacing: 0.25,
                        animationDuration: 0,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // Loading shimmer overlay
        if (_loadingSeries)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _loadingSeries ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
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
                builder: (_) => AdvancedChartScreen(
                  symbol: widget.symbol,
                  initialSeries: series,
                ),
              ),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0E0E0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
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
    const labels = ['1D', '1W', '1M', '1Y', '5Y', 'Max'];
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
                      _savedRangeBySymbol[widget.symbol] = i;
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
                            ? const Color(0xFFE8EEF7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? const Color(0xFF1565C0)
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
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: Icon(
                  _useCandleChart ? Icons.show_chart : Icons.bar_chart,
                  size: 20,
                  color: const Color(0xFF555555),
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
    final prevClose = series.data.length > 1
        ? series.data[series.data.length - 2].close
        : series.open;
    final stats = [
      ('Open', series.open > 0 ? '₹${series.open.toStringAsFixed(2)}' : '—'),
      ('Prev Close', prevClose > 0 ? '₹${prevClose.toStringAsFixed(2)}' : '—'),
      ('High', series.high > 0 ? '₹${series.high.toStringAsFixed(2)}' : '—'),
      ('Low', series.low > 0 ? '₹${series.low.toStringAsFixed(2)}' : '—'),
      (
        '52W High',
        stock.week52High != null
            ? '₹${stock.week52High!.toStringAsFixed(2)}'
            : series.data.isNotEmpty
            ? '₹${series.data.map((c) => c.high).reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}'
            : '—',
      ),
      (
        '52W Low',
        stock.week52Low != null
            ? '₹${stock.week52Low!.toStringAsFixed(2)}'
            : series.data.isNotEmpty
            ? '₹${series.data.map((c) => c.low).reduce((a, b) => a < b ? a : b).toStringAsFixed(2)}'
            : '—',
      ),
      (
        'Volume',
        series.volume > 0
            ? _fmtVolume(series.volume)
            : stock.volume != null
            ? _fmtVolume(stock.volume!)
            : '—',
      ),
      ('VWAP', series.vwap > 0 ? '₹${series.vwap.toStringAsFixed(2)}' : '—'),
    ];
    return _twoColGrid(stats);
  }

  Widget _buildFundamentalsGrid(BuildContext context, Stock stock) {
    // MCX futures — show contract-relevant info instead of equity fundamentals
    if (stock.exchange.toUpperCase() == 'MCX' || stock.isFutures) {
      final expiry = stock.expiry;
      final daysLeft = stock.daysToExpiry;
      final expiryStr = expiry != null
          ? '${expiry.day.toString().padLeft(2, '0')} '
                '${_monthName(expiry.month)} ${expiry.year}'
          : '—';
      final daysStr = daysLeft != null
          ? daysLeft == 0
                ? 'Today'
                : daysLeft == 1
                ? '1 day left'
                : '$daysLeft days left'
          : '—';
      final stats = [
        ('Contract Expiry', expiryStr),
        ('Days to Expiry', daysStr),
        (
          'Prev Close',
          stock.prevClose != null
              ? '₹${stock.prevClose!.toStringAsFixed(2)}'
              : '—',
        ),
        ('Volume', stock.volume != null ? _fmtVolume(stock.volume!) : '—'),
        ('Lot Size', _lotSizeForSymbol(stock.symbol)),
        ('Tick Size', _tickSizeForSymbol(stock.symbol)),
      ];
      return _twoColGrid(stats);
    }

    // NSE equities — fundamentals (use real data when available)
    final base = stock.currentPrice;
    final stats = [
      (
        'Market Cap',
        stock.marketCap != null
            ? _fmtMarketCap(stock.marketCap!)
            : '₹${(base * 6800000 / 10000000).toStringAsFixed(0)}Cr',
      ),
      ('P/E Ratio', '${(base / 45).toStringAsFixed(1)}x'),
      ('EPS', '₹${(base / 22).toStringAsFixed(2)}'),
      ('ROE', '${(12 + base % 8).toStringAsFixed(1)}%'),
      ('P/B Ratio', '${(base / 800).toStringAsFixed(2)}x'),
      ('Div. Yield', '${(0.8 + base % 2).toStringAsFixed(2)}%'),
    ];
    return _twoColGrid(stats);
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _fmtVolume(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtMarketCap(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    return '₹${v.toStringAsFixed(0)}';
  }

  /// Standard MCX lot sizes (contracts per lot).
  String _lotSizeForSymbol(String symbol) {
    const lots = {
      'GOLD': '100 gm',
      'SILVER': '30 kg',
      'CRUDEOIL': '100 bbl',
      'NATURALGAS': '1250 mmBtu',
      'COPPER': '2500 kg',
      'ZINC': '5000 kg',
      'LEAD': '5000 kg',
      'ALUMINIUM': '5000 kg',
      'NICKEL': '1500 kg',
      'COTTON': '25 bales',
    };
    return lots[symbol.toUpperCase()] ?? '—';
  }

  /// Standard MCX tick sizes.
  String _tickSizeForSymbol(String symbol) {
    const ticks = {
      'GOLD': '₹1',
      'SILVER': '₹1',
      'CRUDEOIL': '₹1',
      'NATURALGAS': '₹0.10',
      'COPPER': '₹0.05',
      'ZINC': '₹0.05',
      'LEAD': '₹0.05',
      'ALUMINIUM': '₹0.05',
      'NICKEL': '₹0.10',
      'COTTON': '₹10',
    };
    return ticks[symbol.toUpperCase()] ?? '—';
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
          childAspectRatio: 2.4,
        ),
        itemCount: stats.length,
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    final isMcx = stock.exchange.toUpperCase() == 'MCX' || stock.isFutures;
    final description = isMcx
        ? _commodityDescription(stock.symbol)
        : '${stock.name} is a leading company in the ${stock.sector} sector listed on NSE. '
              'The company operates across multiple business segments and has a strong market presence. '
              'It is known for its consistent performance and shareholder value creation.';

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
            description,
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

  String _commodityDescription(String symbol) {
    const descriptions = {
      'GOLD':
          'Gold futures on MCX track the international spot price of gold. '
          'Traded in lots of 100 grams, it is one of the most liquid commodity contracts in India. '
          'Prices are influenced by global demand, USD strength, and inflation expectations.',
      'SILVER':
          'Silver futures on MCX are traded in lots of 30 kg. '
          'Silver has both industrial and investment demand, making it more volatile than gold. '
          'Prices track international silver rates adjusted for INR/USD exchange rates.',
      'CRUDEOIL':
          'Crude Oil futures on MCX are based on WTI crude oil prices. '
          'Traded in lots of 100 barrels, it is highly sensitive to OPEC decisions, '
          'geopolitical events, and global demand-supply dynamics.',
      'NATURALGAS':
          'Natural Gas futures on MCX track Henry Hub natural gas prices. '
          'Traded in lots of 1250 mmBtu, prices are driven by weather patterns, '
          'storage levels, and seasonal demand.',
      'COPPER':
          'Copper futures on MCX are traded in lots of 2500 kg. '
          'Often called "Dr. Copper" for its ability to predict economic trends, '
          'prices are driven by industrial demand, especially from China.',
      'ZINC':
          'Zinc futures on MCX are traded in lots of 5000 kg. '
          'Zinc is primarily used for galvanizing steel. '
          'Prices are influenced by global mining output and construction activity.',
      'LEAD':
          'Lead futures on MCX are traded in lots of 5000 kg. '
          'Lead is primarily used in batteries. '
          'Prices are driven by automotive sector demand and recycling rates.',
      'ALUMINIUM':
          'Aluminium futures on MCX are traded in lots of 5000 kg. '
          'Aluminium is widely used in packaging, construction, and transportation. '
          'Prices are influenced by energy costs and global production levels.',
      'NICKEL':
          'Nickel futures on MCX are traded in lots of 1500 kg. '
          'Nickel is a key input for stainless steel and EV batteries. '
          'Prices are driven by stainless steel demand and the EV industry.',
      'COTTON':
          'Cotton futures on MCX are traded in lots of 25 bales. '
          'Prices are influenced by monsoon patterns, global textile demand, '
          'and competition from synthetic fibres.',
    };
    return descriptions[symbol.toUpperCase()] ??
        '${symbol} is a commodity futures contract traded on MCX. '
            'Prices track international commodity markets adjusted for INR/USD exchange rates.';
  }

  /// True only when an option chain section should be shown in the body.
  /// Equities/indices on NSE/BSE can have F&O; derivatives don't need one.
  bool _supportsDerivatives(Stock stock) {
    if (stock.instrumentType.isDerivative) return false;
    final ex = stock.exchange.toUpperCase();
    return ex == 'NSE' || ex == 'BSE' || ex == 'NFO';
  }

  /// Returns the appropriate derivative action chips for this instrument.
  /// Rules:
  ///   equity / index on NSE/BSE  → "Options Chain" + "Futures"
  ///   futures contract (NSE/MCX) → "View Option Chain" (underlying)
  ///   option CE/PE               → "Option Chain" (back to chain)
  ///   ETF / MCX commodity        → [] (no chips)
  ///   unknown on NSE/BSE         → "Options Chain" + "Futures" (backward compat)
  List<Widget> _derivativeChips(BuildContext context, Stock stock) {
    final type = stock.instrumentType;
    final ex = stock.exchange.toUpperCase();

    // Futures: show "View Option Chain" link (NSE and MCX both support options)
    if (type.isFuturesContract) {
      return [
        _DerivativeChip(
          label: 'Option Chain',
          icon: Icons.grid_view_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OptionsChainScreen(
                symbol: _underlyingSymbol(stock.symbol),
                exchange: ex == 'MCX' ? 'MCX' : ex == 'BFO' ? 'BFO' : 'NFO',
              ),
            ),
          ),
        ),
      ];
    }

    // Options: link back to the chain for the underlying
    if (type.isOption) {
      return [
        _DerivativeChip(
          label: 'View Full Chain',
          icon: Icons.grid_view_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OptionsChainScreen(
                symbol: _underlyingSymbol(stock.symbol),
                exchange: ex == 'MCX' ? 'MCX' : ex == 'BFO' ? 'BFO' : 'NFO',
              ),
            ),
          ),
        ),
      ];
    }

    // Equity / index / unknown on NSE/BSE/MCX — show option chain action
    if (ex == 'NSE' ||
        ex == 'BSE' ||
        ex == 'NFO' ||
        ex == 'MCX' ||
        type == InstrumentType.equity ||
        type == InstrumentType.marketIndex) {
      final chainExchange = ex == 'MCX' ? 'MCX' : ex == 'BFO' ? 'BFO' : 'NFO';
      return [
        _DerivativeChip(
          label: 'Option Chain',
          icon: Icons.grid_view_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OptionsChainScreen(
                symbol: stock.symbol,
                exchange: chainExchange,
              ),
            ),
          ),
        ),
        if (ex != 'MCX') ...[
          const SizedBox(width: 8),
          _DerivativeChip(
            label: 'Futures',
            icon: Icons.trending_up_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OptionsChainScreen(
                  symbol: stock.symbol,
                  exchange: chainExchange,
                ),
              ),
            ),
          ),
        ],
      ];
    }

    return [];
  }

  /// Extract the underlying symbol from a derivative contract name.
  /// e.g. "NIFTY25JUN25000CE" → "NIFTY", "RELIANCE25JUNFUT" → "RELIANCE"
  String _underlyingSymbol(String symbol) {
    // Strip common F&O suffixes with regex
    return symbol
        .replaceAll(
          RegExp(r'\d{2}[A-Z]{3}\d{2,5}(CE|PE|FUT)$', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\d{2}[A-Z]{3}FUT$', caseSensitive: false), '')
        .trim();
  }

  Widget _buildDerivativesSection(BuildContext context) {
    return const SizedBox.shrink(); // buttons moved to header; section removed
  }

  Widget _buildBottomBar(BuildContext context, Stock stock) {
    final sellBlock = _marketSettings.checkAction(stock.exchange, isBuy: false);
    final buyBlock = _marketSettings.checkAction(stock.exchange, isBuy: true);
    final anyBlock = sellBlock ?? buyBlock;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Market closed / disabled banner
          if (anyBlock != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 13,
                    color: Color(0xFFE65100),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      anyBlock,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              // SELL
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: sellBlock != null
                        ? null
                        : () => _openOrderDrawer(context, OrderType.sell),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
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
                    onPressed: buyBlock != null
                        ? null
                        : () => _openOrderDrawer(context, OrderType.buy),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
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
        ],
      ),
    );
  }

  void _openOrderDrawer(BuildContext context, OrderType type) {
    OrderFormSheet.show(
      context,
      stock: _withSeriesFallback(
        TradingScope.of(context).stockBySymbol(widget.symbol),
        _series ??
            TradingChartService.fromRawCandles(const [], fallbackPrice: 0),
      ),
      initialSide: type,
    );
  }

  /// Returns the badge colour for a given exchange string.
  Color _exchangeBadgeColor(String exchange) {
    switch (exchange.toUpperCase()) {
      case 'MCX':
        return const Color(0xFF7B1FA2);
      case 'NFO':
        return const Color(0xFFE65100);
      case 'BSE':
        return const Color(0xFF0277BD);
      case 'CDS':
        return const Color(0xFF00695C);
      case 'BFO':
        return const Color(0xFF558B2F);
      case 'NCDEX':
        return const Color(0xFF6D4C41);
      default:
        return const Color(0xFF1565C0); // NSE blue
    }
  }
}

// ─── Derivative shortcut chip (Options Chain / Futures) ──────────────────────

class _DerivativeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DerivativeChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF1565C0)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Expiry badge for futures contracts ──────────────────────────────────────

class _ExpiryBadge extends StatelessWidget {
  final Stock stock;
  const _ExpiryBadge({required this.stock});

  @override
  Widget build(BuildContext context) {
    final expiry = stock.expiry!;
    final days = stock.daysToExpiry!;

    // Colour: red if ≤7 days, amber if ≤30 days, grey otherwise
    final Color bg;
    final Color fg;
    if (days <= 7) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFD32F2F);
    } else if (days <= 30) {
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFE65100);
    } else {
      bg = const Color(0xFFF3E5F5);
      fg = const Color(0xFF7B1FA2);
    }

    final day = expiry.day.toString().padLeft(2, '0');
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][expiry.month - 1];
    final label = 'Exp $day $month ${expiry.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          if (days <= 30) ...[
            const SizedBox(width: 4),
            Text(
              '($days d)',
              style: TextStyle(fontSize: 9, color: fg.withOpacity(0.8)),
            ),
          ],
        ],
      ),
    );
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
