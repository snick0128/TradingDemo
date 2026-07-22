import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import 'alert_creation_screen.dart';
import '../screens/advanced_chart_screen.dart';
import '../screens/options_chain_screen.dart';
import '../services/local_chart_cache.dart';
import '../services/subscription_manager.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, int> _savedRangeBySymbol = {};
  static final Map<String, TradingChartSeries> _chartCache = {};
  static final Map<String, Stock> _quoteCache = {};
  static final Map<String, DateTime> _firstOpenedAt = {};
  static const _localChartCache = LocalChartCache();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  int _selectedRange = 0;
  bool _useCandleChart = true;
  TradingChartSeries? _series;
  TradingChartSeries? _prevSeries;
  bool _loadingSeries = false;
  bool _hydrationStarted = false;
  String? _seriesError;
  String _quoteStage = 'cached';
  String _chartStage = 'cached';

  // Market settings stream
  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  int _loadGeneration = 0;
  int _screenBuildCount = 0;
  int _headerBuildCount = 0;
  int _chartBuildCount = 0;
  int _priceBuildCount = 0;
  Timer? _refreshTimer;
  Timer? _tickDebounce;
  TradingStore? _store;
  ValueNotifier<double>? _ltpNotifier;
  double? _lastRealtimePrice;
  double? _pendingRealtimePrice;
  bool _firstTickLogged = false;

  // ── Chart viewport tracking ────────────────────────────────────────────────
  // Used to implement "Go To Live" and auto-follow behavior.
  // _chartKey is incremented to force a zoom-reset to latest when needed.
  int _chartKey = 0;
  bool _isAtLive = true;
  double _currentZoomFactor = 0.5; // fraction of candles visible

  // Nearest F&O expiry for index instruments (NIFTY, BANKNIFTY, etc.).
  // Fetched once on open; null if not an index or fetch failed.
  String? _indexNearestExpiry;

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
    _firstOpenedAt[_cacheSymbol] = DateTime.now();
    // Render from cache/placeholders first. Network hydration starts after the
    // first frame so no API can hold the initial route paint hostage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _logStage('screen_open_ms', _openElapsedMs());
      _startProgressiveHydration();
    });
  }

  String get _screenId => 'stock_detail_${widget.symbol}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store == store) return;
    _ltpNotifier?.removeListener(_onLtpChanged);
    _store = store;
    _ltpNotifier = store.ltpNotifier(widget.symbol);
    _ltpNotifier!.addListener(_onLtpChanged);
    SubscriptionManager.instance.subscribeForScreen(_screenId, {widget.symbol});
    _primeInstantState(store);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startProgressiveHydration();
    });
  }

  String get _cacheSymbol => widget.symbol.trim().toUpperCase();

  String get _seriesCacheKey => '$_cacheSymbol:$_selectedRange';

  int _openElapsedMs() {
    final openedAt = _firstOpenedAt[_cacheSymbol];
    if (openedAt == null) return 0;
    return DateTime.now().difference(openedAt).inMilliseconds;
  }

  void _logStage(String name, Object value) {
    debugPrint('[StockDetailPerf] ${widget.symbol} $name=$value');
  }

  void _primeInstantState(TradingStore store) {
    final cachedSeries =
        _chartCache[_seriesCacheKey] ??
        _localChartCache.readSeries(_seriesCacheKey);
    final cachedQuote = _quoteCache[_cacheSymbol];
    final liveStock = store.stockBySymbol(widget.symbol);
    if (cachedQuote != null && liveStock.currentPrice <= 0) {
      store.registerSearchResult(
        symbol: widget.symbol,
        displayName: cachedQuote.name.isNotEmpty
            ? cachedQuote.name
            : widget.symbol,
        exchange: cachedQuote.exchange.isNotEmpty
            ? cachedQuote.exchange
            : 'NSE',
        token: cachedQuote.token,
        ltp: cachedQuote.currentPrice,
        changePercent: cachedQuote.changePercentage,
        instrumentType: cachedQuote.instrumentType,
        strikePrice: cachedQuote.strikePrice,
        expiry: cachedQuote.expiry,
      );
    }
    if (cachedSeries != null && _series == null) {
      _series = cachedSeries;
      _loadingSeries = false;
      _chartStage = 'memory-cache';
      _fadeCtrl.value = 1;
    }
  }

  void _startProgressiveHydration() {
    if (_hydrationStarted || !mounted) return;
    _hydrationStarted = true;
    // Subscription already registered in didChangeDependencies via SubscriptionManager
    _logStage('instant_render_ms', _openElapsedMs());

    // Independent background work. Quote, chart, and websocket subscription are
    // deliberately not awaited together.
    unawaited(_fetchLiveQuoteIfNeeded());
    unawaited(_loadSeries());
    unawaited(_fetchIndexExpiryIfNeeded());
    _logStage('ws_attach_requested_ms', _openElapsedMs());
  }

  /// Fetch a live price for instruments that have no WebSocket tick yet.
  ///
  /// Covers: indices (NIFTY 50, SENSEX), MCX futures, options, any symbol
  /// that isn't in the backend's hardcoded WebSocket subscription list.
  ///
  /// Two-strategy approach:
  ///   S1: /market/stock?symbol=  — fast (< 100ms), works for tracked symbols
  ///   S2: /derivatives/quote?token=  — Angel One REST, works for ANY instrument
  ///       with a valid token. Token comes from registerSearchResult() which
  ///       is called by the search screen BEFORE Navigator.push.
  ///
  /// If both strategies fail on the first attempt, we retry once after 1s.
  /// This handles transient network blips and Angel One token refresh races.
  Future<void> _fetchLiveQuoteIfNeeded({int attempt = 0}) async {
    if (!mounted) return;
    final store = _store!;
    final stock = store.stockBySymbol(widget.symbol);

    // Already has a live price — nothing to do
    if (stock.currentPrice > 0) {
      _quoteCache[_cacheSymbol] = stock;
      _quoteStage = 'live-store';
      debugPrint('[StockDetail] Using live price for ${widget.symbol}: ₹${stock.currentPrice} (attempt $attempt)');
      return;
    }

    debugPrint('[StockDetail] No live price for ${widget.symbol} (token="${stock.token}" exchange="${stock.exchange}") — fetching (attempt $attempt)');
    final sw = Stopwatch()..start();
    if (mounted) setState(() => _quoteStage = 'refreshing');

    double ltp = 0;
    double pct = 0;
    String source = '';

    // ── Strategy 1: /market/stock (live WebSocket cache on backend) ──────────
    try {
      final detail = await _api
          .getStockDetail(widget.symbol.toUpperCase())
          .timeout(const Duration(seconds: 4));
      final rawLtp = (detail['ltp'] as num?)?.toDouble() ?? 0.0;
      if (rawLtp > 0) {
        ltp    = rawLtp;
        pct    = (detail['changePercent'] as num?)?.toDouble() ?? 0.0;
        source = 'market/stock';
        debugPrint('[StockDetail] S1 OK: ₹$ltp for ${widget.symbol}');
      } else {
        debugPrint('[StockDetail] S1 returned ltp=0 for ${widget.symbol}');
      }
    } catch (e) {
      debugPrint('[StockDetail] S1 failed for ${widget.symbol}: $e');
    }

    // ── Strategy 2: /derivatives/quote?token=&exchange= (Angel One REST) ────
    // This is the primary path for non-WebSocket instruments (indices, F&O, MCX).
    // Token MUST be non-empty — passed from search screen via registerSearchResult.
    if (ltp <= 0) {
      final token    = stock.token;
      final exchange = stock.exchange.isNotEmpty ? stock.exchange : 'NSE';

      if (token.isNotEmpty) {
        try {
          final quote = await _api
              .getQuoteByToken(token, exchange: exchange)
              .timeout(const Duration(seconds: 4));
          final rawLtp = (quote['ltp'] as num?)?.toDouble() ?? 0.0;
          if (rawLtp > 0) {
            ltp    = rawLtp;
            pct    = (quote['percentChange'] as num?)?.toDouble() ?? 0.0;
            source = 'derivatives/quote';
            debugPrint('[StockDetail] S2 OK: ₹$ltp for ${widget.symbol} (token=$token exchange=$exchange)');
          } else {
            debugPrint('[StockDetail] S2 returned ltp=0 for ${widget.symbol} (token=$token exchange=$exchange)');
          }
        } catch (e) {
          debugPrint('[StockDetail] S2 failed for ${widget.symbol} (token=$token exchange=$exchange): $e');
        }
      } else {
        debugPrint('[StockDetail] S2 skipped: no token for ${widget.symbol}. '
            'Ensure search screen calls registerSearchResult before navigating.');
      }
    }

    sw.stop();
    _logStage('quote_fetch_ms_attempt$attempt', sw.elapsedMilliseconds);

    if (!mounted) return;

    if (ltp > 0) {
      final resolvedExchange = stock.exchange.isNotEmpty ? stock.exchange : 'NSE';
      final resolvedStock = Stock(
        symbol:           widget.symbol,
        name:             stock.name.isNotEmpty ? stock.name : widget.symbol,
        currentPrice:     ltp,
        changePercentage: pct,
        sector:           stock.sector,
        exchange:         resolvedExchange,
        token:            stock.token,
        prevClose:        stock.prevClose,
        volume:           stock.volume,
        isStale:          stock.isStale,
        expiry:           stock.expiry,
        instrumentType:   stock.instrumentType,
        strikePrice:      stock.strikePrice,
      );
      _quoteCache[_cacheSymbol] = resolvedStock;
      store.registerSearchResult(
        symbol:         widget.symbol,
        displayName:    stock.name.isNotEmpty ? stock.name : widget.symbol,
        exchange:       resolvedExchange,
        token:          stock.token,
        ltp:            ltp,
        changePercent:  pct,
        instrumentType: stock.instrumentType,
        strikePrice:    stock.strikePrice,
        expiry:         stock.expiry,
      );
      if (mounted) setState(() => _quoteStage = 'fresh');
      debugPrint('[StockDetail] Price resolved: ${widget.symbol} = ₹$ltp via $source (${sw.elapsedMilliseconds}ms)');
    } else {
      // Both strategies failed — retry once after a short delay.
      // Covers: transient network errors, Angel One token refresh in-progress.
      if (attempt < 1) {
        debugPrint('[StockDetail] Both strategies failed for ${widget.symbol}, retrying in 1.5s...');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted) return _fetchLiveQuoteIfNeeded(attempt: attempt + 1);
      } else {
        if (mounted) setState(() => _quoteStage = 'unavailable');
        debugPrint('[StockDetail] Could not resolve price for ${widget.symbol} after 2 attempts (${sw.elapsedMilliseconds}ms total)');
      }
    }
  }

  /// Fetch nearest expiry date for index instruments (NIFTY 50, BANKNIFTY, etc.).
  /// Only runs if the instrument is a market index; silently skips otherwise.
  Future<void> _fetchIndexExpiryIfNeeded() async {
    if (!mounted) return;
    final store = _store!;
    final stock = store.stockBySymbol(widget.symbol);
    final isIndex = stock.instrumentType == InstrumentType.marketIndex ||
        const {'NIFTY 50', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY', 'SENSEX', 'INDIA VIX'}
            .contains(widget.symbol.toUpperCase());
    if (!isIndex) return;

    final exchange = widget.symbol.toUpperCase() == 'SENSEX' ? 'BFO' : 'NFO';
    try {
      final expiries = await _api
          .getFnoExpiryDates(
            widget.symbol.toUpperCase(),
            exchange: exchange,
            typeFilter: 'ALL',
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted || expiries.isEmpty) return;
      // Take the nearest upcoming expiry (first entry from backend — already sorted).
      final nearest = expiries.first;
      setState(() => _indexNearestExpiry = nearest);
      debugPrint('[StockDetail] Index expiry: ${widget.symbol} → $nearest (exchange=$exchange)');
    } catch (e) {
      debugPrint('[StockDetail] Could not fetch expiry for ${widget.symbol}: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickDebounce?.cancel();
    SubscriptionManager.instance.unsubscribeScreen(_screenId);
    _ltpNotifier?.removeListener(_onLtpChanged);
    _fadeCtrl.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _onLtpChanged() {
    if (!mounted) return;
    final price = _ltpNotifier!.value;
    if (price <= 0 || price == _lastRealtimePrice) return;
    final stock = _store?.stockBySymbol(widget.symbol);
    if (stock != null) _quoteCache[_cacheSymbol] = stock;
    if (!_firstTickLogged) {
      _firstTickLogged = true;
      _logStage('first_tick_latency_ms', _openElapsedMs());
    }

    // On 1M / 1Y / 5Y / Max tabs the candles are too coarse to merge intraday
    // ticks. LivePriceText and the change chip VLB both subscribe to ltpNotifier
    // directly, so NO setState() is needed here — a full screen rebuild on every
    // tick would be wasted work.
    if (_selectedRange > 1) {
      _lastRealtimePrice = price;
      return;
    }

    // On 1D / 1W tabs: merge tick into live candle and update chart.
    _pendingRealtimePrice = price;
    _tickDebounce ??= Timer(Duration.zero, () {
      _tickDebounce = null;
      final pending = _pendingRealtimePrice;
      if (!mounted || pending == null || pending == _lastRealtimePrice) return;
      _lastRealtimePrice = pending;
      final current = _series;
      if (current == null) {
        setState(() {});
        return;
      }
      debugPrint('[Chart] Tick ${widget.symbol} ₹$pending '
          'candles=${current.data.length} range=$_selectedRange at_live=$_isAtLive');

      final (:series, :isNewCandle) = TradingChartService.mergeRealtimeTick(
        current,
        pending,
        intervalMinutes: _intervalMinutesForRange(_selectedRange),
      );
      _chartCache[_seriesCacheKey] = series;

      debugPrint('[Chart] ${isNewCandle ? "🕯 New candle" : "📈 Updated"} '
          'total=${series.data.length} latest=${series.data.last.time.toIso8601String()}');

      setState(() {
        _series = series;
        if (isNewCandle && _isAtLive) {
          _currentZoomFactor = _defaultZoomFactor(series.data.length);
          _chartKey++;
        }
      });
    });
  }

  Future<void> _loadSeries() async {
    if (!mounted) return;
    _refreshTimer?.cancel();
    final gen = ++_loadGeneration;

    final cached =
        _chartCache[_seriesCacheKey] ??
        _localChartCache.readSeries(_seriesCacheKey);
    setState(() {
      _loadingSeries = true;
      _seriesError = null;
      _prevSeries = _series ?? cached;
      if (_series == null && cached != null) {
        _series = cached;
        _chartStage = 'memory-cache-refreshing';
      } else {
        _chartStage = 'refreshing';
      }
    });
    _fadeCtrl.reverse();

    for (int attempt = 0; attempt < 2; attempt++) {
      if (gen != _loadGeneration || !mounted) return;
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: 2 << (attempt - 1)));
        if (gen != _loadGeneration || !mounted) return;
      }
      try {
        final sw = Stopwatch()..start();
        final now = DateTime.now().toUtc();
        final interval = _intervalForRange(_selectedRange);
        final from = _fromForRange(now, _selectedRange);
        final store = _store!;
        final stock = store.stockBySymbol(widget.symbol);

        // Warmup ping on first attempt — avoids Render cold-start blocking the fetch.
        if (attempt == 0) {
          _api.getHealth().catchError((_) => <String, dynamic>{});
        }

        final candles = await _api
            .getHistoricalData(
              widget.symbol.toUpperCase(),
              interval: interval,
              from: _fmtApiDate(from, interval: interval),
              to: _fmtApiDate(now, interval: interval),
              exchange: stock.exchange.isNotEmpty ? stock.exchange : null,
              token: stock.token.isNotEmpty ? stock.token : null,
            )
            .timeout(const Duration(seconds: 8));
        if (gen != _loadGeneration || !mounted) return;
        final maxCandles = _maxCandlesForRange(_selectedRange);
        final visibleCandles = candles.length > maxCandles
            ? candles.sublist(candles.length - maxCandles)
            : candles;
        final nextSeries = TradingChartService.fromRawCandles(
          visibleCandles,
          fallbackPrice: stock.currentPrice,
        );
        _chartCache[_seriesCacheKey] = nextSeries;
        _localChartCache.writeSeries(_seriesCacheKey, nextSeries);
        setState(() {
          _series = nextSeries;
          _prevSeries = null;
          _loadingSeries = false;
          _seriesError = null;
          _chartStage = 'fresh';
          // Reset viewport to live on fresh data load.
          _isAtLive = true;
          _currentZoomFactor = _defaultZoomFactor(nextSeries.data.length);
          _chartKey++;
          debugPrint('[Chart] Loaded ${nextSeries.data.length} candles for '
              '${widget.symbol} zoom=${_currentZoomFactor.toStringAsFixed(3)}');
        });
        _fadeCtrl.forward();
        sw.stop();
        _logStage('chart_fetch_ms', sw.elapsedMilliseconds);
        // Auto-refresh intraday and weekly charts every 30s.
        // Guard is required: _loadSeries() is async and may reach this point
        // after dispose() has already run and cancelled the previous timer.
        if (!mounted) return;
        if (_selectedRange <= 1) {
          _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted) _loadSeries();
          });
        }
        return;
      } catch (e) {
        // 400 means the backend could not resolve a token for this instrument
        // (e.g. ETF with missing token). Retrying won't help — skip straight to
        // the unavailable state with a clear message.
        final isClientError = e is BackendException && (e.statusCode ?? 0) < 500 && (e.statusCode ?? 0) >= 400;
        if (attempt < 1 && !isClientError) continue; // one retry for server errors only
        if (gen != _loadGeneration || !mounted) return;
        final displayError = isClientError
            ? 'Chart data unavailable for this instrument.'
            : e.toString();
        setState(() {
          _seriesError = displayError;
          _loadingSeries = false;
          _chartStage = _series != null || _prevSeries != null
              ? 'stale'
              : 'unavailable';
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

  /// Candle interval in minutes for the given range tab index.
  int _intervalMinutesForRange(int rangeIdx) {
    switch (rangeIdx) {
      case 0: return 5;          // 1D  → 5m candles
      case 1: return 15;         // 1W  → 15m candles
      case 2: return 60;         // 1M  → 1h candles
      case 3: return 24 * 60;    // 1Y  → daily candles
      default: return 24 * 60 * 7; // 5Y/max → weekly candles
    }
  }

  /// Compute default zoom factor so ~60 candles are visible initially.
  double _defaultZoomFactor(int candleCount) {
    if (candleCount <= 0) return 1.0;
    final visible = 60.clamp(1, candleCount);
    return (visible / candleCount).clamp(0.05, 1.0);
  }

  /// Format a DateTime for the x-axis label in the inline chart.
  String _formatAxisLabel(DateTime t, int rangeIdx) {
    final local = t.toLocal();
    if (rangeIdx <= 1) {
      // intraday / weekly — show HH:mm
      return '${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')}';
    }
    if (rangeIdx == 2) {
      // monthly — show "dd MMM"
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${local.day} ${months[local.month - 1]}';
    }
    // yearly / max — show "MMM yy"
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[local.month - 1]} ${(local.year % 100).toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    _screenBuildCount += 1;
    assert(() {
      debugPrint(
        '[StockDetailPerf] ${widget.symbol} screen_build=$_screenBuildCount',
      );
      return true;
    }());
    final store = _store!;
    final rawStock = store.stockBySymbol(widget.symbol);

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
            _buildHydrationStrip(),
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

  Widget _buildHydrationStrip() {
    final messages = <String>[];
    if (_quoteStage == 'refreshing') messages.add('Refreshing quote');
    if (_quoteStage == 'unavailable') messages.add('Using cached quote');
    if (_chartStage == 'refreshing' ||
        _chartStage == 'memory-cache-refreshing') {
      messages.add('Refreshing chart');
    }
    if (_chartStage == 'stale') messages.add('Showing cached chart');
    if (messages.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          if (_quoteStage == 'refreshing' || _chartStage.contains('refreshing'))
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            ),
          if (_quoteStage == 'refreshing' || _chartStage.contains('refreshing'))
            const SizedBox(width: 6),
          Expanded(
            child: Text(
              messages.join(' • '),
              style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
    assert(() {
      _headerBuildCount++;
      debugPrint('[StockDetailPerf] ${widget.symbol} header_build=$_headerBuildCount');
      return true;
    }());
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
                                  horizontal: 5,
                                  vertical: 1,
                                ),
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
                          ] else if (_indexNearestExpiry != null) ...[
                            const SizedBox(height: 3),
                            _IndexExpiryBadge(
                              expiryIso: _indexNearestExpiry!,
                              exchange: stock.exchange,
                            ),
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
                  LivePriceText(
                    symbol: widget.symbol,
                    store: _store!,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0D0D0D),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Change chip updates on every tick via its own VLB so the
                  // full screen does NOT need to rebuild for price movement.
                  ValueListenableBuilder<double>(
                    valueListenable: _store!.ltpNotifier(widget.symbol),
                    builder: (_, ltp, __) {
                      assert(() {
                        _priceBuildCount++;
                        debugPrint('[StockDetailPerf] ${widget.symbol} price_build=$_priceBuildCount');
                        return true;
                      }());
                      final effectiveLtp = ltp > 0 ? ltp : stock.currentPrice;
                      final pct = stock.changePercentage;
                      final amt = effectiveLtp * pct / 100;
                      final isChipPos = pct >= 0;
                      final chipArrow = isChipPos ? '+' : '';
                      final chipColor = isChipPos
                          ? const Color(0xFF00C853)
                          : const Color(0xFFD50000);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$chipArrow${amt.toStringAsFixed(2)} ($chipArrow${pct.abs().toStringAsFixed(2)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                      );
                    },
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
    assert(() {
      _chartBuildCount++;
      debugPrint('[StockDetailPerf] ${widget.symbol} chart_build=$_chartBuildCount');
      return true;
    }());
    final fadeOpacity = _loadingSeries && _prevSeries == null
        ? const AlwaysStoppedAnimation(0.4)
        : _fadeAnim;
    final hasRealCandles = series.data.isNotEmpty && series.close > 0;
    // Use line chart when only 1 candle exists — candle series can't render a single point
    final effectiveLineMode = use1DLine || series.data.length <= 1;
    final showVolume = series.data.any((c) => c.volume > 0);
    final n = series.data.length;

    final prevCloseRef = _selectedRange == 0
        ? series.open
        : (series.data.isNotEmpty ? series.data.first.close : 0.0);

    // ── Index-based x-axis setup ───────────────────────────────────────────
    // Using candle list-index (0, 1, 2, …, n-1) as the x-value eliminates
    // overnight gaps, weekend blanks, and any other timestamp-proportional
    // spacing that caused the "candles compressed to one side" bug.
    // The axis min/max are fixed to the data extents; labels are formatted
    // from the actual candle timestamp via axisLabelFormatter.
    final zoomFactor   = _currentZoomFactor.clamp(0.05, 1.0);
    final zoomPosition = _isAtLive
        ? (1.0 - zoomFactor).clamp(0.0, 1.0)   // right-anchored (live)
        : (1.0 - zoomFactor).clamp(0.0, 1.0);   // same on initial; Syncfusion preserves pan after first render

    NumericAxis _buildXAxis({bool visible = false}) => NumericAxis(
      minimum: -0.5,           // half-candle gap on left edge
      maximum: n - 0.5,        // half-candle gap on right edge
      initialZoomFactor:   zoomFactor,
      initialZoomPosition: zoomPosition,
      isVisible: visible,
      majorGridLines: const MajorGridLines(width: 0),
      axisLine:        const AxisLine(width: 0),
      majorTickLines:  const MajorTickLines(size: 0),
      axisLabelFormatter: visible
          ? (AxisLabelRenderDetails details) {
              final idx = details.value.round();
              if (idx >= 0 && idx < n) {
                return ChartAxisLabel(
                  _formatAxisLabel(series.data[idx].time, _selectedRange),
                  details.textStyle,
                );
              }
              return ChartAxisLabel('', details.textStyle);
            }
          : null,
    );

    // Track whether the user is at the live (right) edge so we can show
    // or hide the "Go To Live" button without blocking panning.
    void onRangeChanged(ActualRangeChangedArgs args) {
      if (args.orientation != AxisOrientation.horizontal) return;
      final vMax    = (args.visibleMax as num).toDouble();
      final aMax    = (args.actualMax  as num).toDouble();
      final vMin    = (args.visibleMin as num).toDouble();
      final aMin    = (args.actualMin  as num).toDouble();
      final span    = aMax - aMin;
      if (span > 0) {
        final newFactor = ((vMax - vMin) / span).clamp(0.05, 1.0);
        if ((newFactor - _currentZoomFactor).abs() > 0.001) {
          _currentZoomFactor = newFactor;
        }
      }
      final atLive = vMax >= (aMax - 0.5);
      if (atLive != _isAtLive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isAtLive = atLive);
        });
      }
      debugPrint('[Chart] Viewport: idx ${vMin.toStringAsFixed(1)}–${vMax.toStringAsFixed(1)} '
          'of 0–${aMax.toStringAsFixed(0)} | at_live=$atLive zoom=${_currentZoomFactor.toStringAsFixed(3)}');
    }

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
                              style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
                            ),
                          )
                        : effectiveLineMode
                        // ── Line chart ─────────────────────────────────────
                        ? SfCartesianChart(
                            key: ValueKey('line_${widget.symbol}_${_selectedRange}_$_chartKey'),
                            backgroundColor: Colors.white,
                            plotAreaBackgroundColor: Colors.white,
                            enableAxisAnimation: false,
                            plotAreaBorderWidth: 0,
                            margin: const EdgeInsets.only(right: 8),
                            primaryXAxis: _buildXAxis(),
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
                            onActualRangeChanged: onRangeChanged,
                            trackballBehavior: TrackballBehavior(
                              enable: true,
                              activationMode: ActivationMode.singleTap,
                              lineColor: chartColor.withOpacity(0.4),
                              lineWidth: 1,
                            ),
                            series: <CartesianSeries>[
                              // xValueMapper uses index `i` — equal spacing, no gaps
                              FastLineSeries<TradingCandle, num>(
                                dataSource: series.data,
                                xValueMapper: (c, i) => i,
                                yValueMapper: (c, _) => c.close,
                                color: chartColor,
                                width: 2.2,
                                animationDuration: 0,
                              ),
                            ],
                          )
                        // ── Candle chart ────────────────────────────────────
                        : SfCartesianChart(
                            key: ValueKey('candle_${widget.symbol}_${_selectedRange}_$_chartKey'),
                            backgroundColor: Colors.white,
                            plotAreaBackgroundColor: Colors.white,
                            enableAxisAnimation: false,
                            plotAreaBorderWidth: 0,
                            margin: const EdgeInsets.only(right: 8),
                            primaryXAxis: _buildXAxis(),
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
                            onActualRangeChanged: onRangeChanged,
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
                              CandleSeries<TradingCandle, num>(
                                dataSource: series.data,
                                xValueMapper: (c, i) => i,
                                lowValueMapper:   (c, _) => c.low,
                                highValueMapper:  (c, _) => c.high,
                                openValueMapper:  (c, _) => c.open,
                                closeValueMapper: (c, _) => c.close,
                                enableSolidCandles: true,
                                bearColor: const Color(0xFFE53935),
                                bullColor: const Color(0xFF00C853),
                                width:   n > 100 ? 0.7 : 0.6,
                                spacing: n > 100 ? 0.1 : 0.15,
                                animationDuration: 0,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            // ── Volume bar chart ───────────────────────────────────────────
            // Also uses index-based x-axis so it stays aligned with the main chart.
            if (showVolume)
              SizedBox(
                height: 44,
                child: FadeTransition(
                  opacity: fadeOpacity,
                  child: SfCartesianChart(
                    key: ValueKey('vol_${widget.symbol}_${_selectedRange}_$_chartKey'),
                    enableAxisAnimation: false,
                    plotAreaBorderWidth: 0,
                    margin: const EdgeInsets.only(right: 8),
                    primaryXAxis: NumericAxis(
                      minimum: -0.5,
                      maximum: n - 0.5,
                      initialZoomFactor:   zoomFactor,
                      initialZoomPosition: zoomPosition,
                      isVisible: false,
                      majorGridLines: const MajorGridLines(width: 0),
                      axisLine:       const AxisLine(width: 0),
                      majorTickLines: const MajorTickLines(size: 0),
                    ),
                    primaryYAxis: NumericAxis(
                      isVisible: false,
                      majorGridLines: const MajorGridLines(width: 0),
                    ),
                    series: <CartesianSeries>[
                      ColumnSeries<TradingCandle, num>(
                        dataSource: series.data,
                        xValueMapper: (c, i) => i,
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
        // ── Loading shimmer ────────────────────────────────────────────────
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
        // ── "Go To Live" button — shown when user has panned away ──────────
        if (!_isAtLive && hasRealCandles && _selectedRange <= 1)
          Positioned(
            top: 24,
            right: 52,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isAtLive = true;
                  _chartKey++;   // recreate chart scrolled to latest candle
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Go To Live',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // ── Expand icon ────────────────────────────────────────────────────
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
                exchange: ex == 'MCX'
                    ? 'MCX'
                    : ex == 'BFO'
                    ? 'BFO'
                    : 'NFO',
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
                exchange: ex == 'MCX'
                    ? 'MCX'
                    : ex == 'BFO'
                    ? 'BFO'
                    : 'NFO',
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
      final chainExchange = ex == 'MCX'
          ? 'MCX'
          : ex == 'BFO'
          ? 'BFO'
          : 'NFO';
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
        _store!.stockBySymbol(widget.symbol),
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
    final expiry = stock.expiry;      // DateTime?  — safe nullable access
    final days   = stock.daysToExpiry; // int?       — safe nullable access

    debugPrint(
      '[EXPIRY_BADGE] symbol=${stock.symbol} '
      'instrumentType=${stock.instrumentType} '
      'expiry=$expiry',
    );

    // Equity, unknown types, and commodity contracts that haven't resolved
    // their active contract yet all arrive here with expiry == null.
    // Hide the badge entirely rather than crashing.
    if (expiry == null) return const SizedBox.shrink();

    // Colour: red if ≤7 days, amber if ≤30 days, grey otherwise.
    // days can still be negative (expired) — treat that as urgent red.
    final int safeDays = days ?? 0;
    final Color bg;
    final Color fg;
    if (safeDays <= 7) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFD32F2F);
    } else if (safeDays <= 30) {
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFE65100);
    } else {
      bg = const Color(0xFFF3E5F5);
      fg = const Color(0xFF7B1FA2);
    }

    final day = expiry.day.toString().padLeft(2, '0');
    final month = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
          if (safeDays <= 30) ...[
            const SizedBox(width: 4),
            Text(
              '($safeDays d)',
              style: TextStyle(fontSize: 9, color: fg.withOpacity(0.8)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Nearest expiry badge for index instruments ───────────────────────────────
// Shows the nearest F&O contract expiry for underlying indices (NIFTY, BANKNIFTY
// etc.) where the stock itself has no expiry field but its derivatives do.

class _IndexExpiryBadge extends StatelessWidget {
  final String expiryIso; // ISO date string from backend, e.g. '2026-06-26'
  final String exchange;

  const _IndexExpiryBadge({required this.expiryIso, required this.exchange});

  @override
  Widget build(BuildContext context) {
    DateTime? expiry;
    try {
      expiry = DateTime.parse(expiryIso);
    } catch (_) {
      return const SizedBox.shrink();
    }

    final days = expiry.difference(DateTime.now()).inDays;

    final Color bg;
    final Color fg;
    if (days <= 7) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFD32F2F);
    } else if (days <= 30) {
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFE65100);
    } else {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    }

    final day = expiry.day.toString().padLeft(2, '0');
    final month = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
          const SizedBox(width: 4),
          Text(
            '($days d)',
            style: TextStyle(fontSize: 9, color: fg.withOpacity(0.8)),
          ),
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
