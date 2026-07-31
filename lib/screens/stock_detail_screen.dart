import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import '../theme.dart';
import 'alert_creation_screen.dart';
import '../screens/advanced_chart_screen.dart';
import '../screens/market_depth_screen.dart';
import '../screens/options_chain_screen.dart';
import '../screens/time_and_sales_screen.dart';
import '../services/local_chart_cache.dart';
import '../services/subscription_manager.dart';
import '../services/trading_chart_service.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../widgets/app_dialog.dart';
import '../widgets/instrument_logo.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';
import 'universal_search_screen.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, ChartTimeframe> _savedTimeframeBySymbol = {};
  static final Map<String, TradingChartSeries> _chartCache = {};
  static final Map<String, Stock> _quoteCache = {};
  static final Map<String, DateTime> _firstOpenedAt = {};
  static const _localChartCache = LocalChartCache();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  // Timeframe tabs shown in the inline chart — ordered finest to coarsest.
  static const _timeframeTabs = [
    ChartTimeframe.m1,
    ChartTimeframe.m5,
    ChartTimeframe.m15,
    ChartTimeframe.h1,
    ChartTimeframe.d1,
    ChartTimeframe.w1,
  ];
  static const _timeframeLabels = ['1m', '5m', '15m', '1H', '1D', '1W'];

  // Fine enough that a live tick can be merged into the most recent candle
  // (rather than requiring a full refetch) and worth auto-refreshing.
  static const _liveMergeableTimeframes = {
    ChartTimeframe.m1,
    ChartTimeframe.m5,
    ChartTimeframe.m15,
  };

  ChartTimeframe _timeframe = ChartTimeframe.m5;
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
    _timeframe = _savedTimeframeBySymbol[widget.symbol] ?? ChartTimeframe.m5;
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
  int? _subGen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store == store) return;
    _ltpNotifier?.removeListener(_onLtpChanged);
    _store = store;
    _ltpNotifier = store.ltpNotifier(widget.symbol);
    _ltpNotifier!.addListener(_onLtpChanged);
    _subGen = SubscriptionManager.instance.subscribeForScreen(_screenId, {widget.symbol});
    _primeInstantState(store);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startProgressiveHydration();
    });
  }

  String get _cacheSymbol => widget.symbol.trim().toUpperCase();

  String get _seriesCacheKey => '$_cacheSymbol:${_timeframe.name}';

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
    SubscriptionManager.instance.unsubscribeScreen(_screenId, _subGen);
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

    // On 1H / 1D / 1W tabs the candles are too coarse to merge intraday
    // ticks. LivePriceText and the change chip VLB both subscribe to ltpNotifier
    // directly, so NO setState() is needed here — a full screen rebuild on every
    // tick would be wasted work.
    if (!_liveMergeableTimeframes.contains(_timeframe)) {
      _lastRealtimePrice = price;
      return;
    }

    // On 1m / 5m / 15m tabs: merge tick into live candle and update chart.
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
          'candles=${current.data.length} timeframe=${_timeframe.name} at_live=$_isAtLive');

      final (:series, :isNewCandle) = TradingChartService.mergeRealtimeTick(
        current,
        pending,
        intervalMinutes: _intervalMinutes(_timeframe),
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
        final interval = _apiInterval(_timeframe);
        final from = _fromForTimeframe(now, _timeframe);
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
        final maxCandles = _maxCandlesForTimeframe(_timeframe);
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
        if (_liveMergeableTimeframes.contains(_timeframe)) {
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

  int _maxCandlesForTimeframe(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return 400; // 1m over 1 day → ~375 candles in a trading day
      case ChartTimeframe.m5:
        return 78; // 5m over 1 day → ~78 candles in a trading day
      case ChartTimeframe.m15:
        return 130; // 15m over 7 days → ~120 candles
      case ChartTimeframe.h1:
        return 160; // 1h over 30 days → ~160 candles
      case ChartTimeframe.d1:
        return 250; // 1d over 1 year → ~250 trading days
      default: // w1
        return 260; // 1w over 5 years → ~260 weeks
    }
  }

  DateTime _fromForTimeframe(DateTime nowUtc, ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
      case ChartTimeframe.m5:
        return nowUtc.subtract(const Duration(days: 1));
      case ChartTimeframe.m15:
        return nowUtc.subtract(const Duration(days: 7));
      case ChartTimeframe.h1:
        return nowUtc.subtract(const Duration(days: 30));
      case ChartTimeframe.d1:
        return nowUtc.subtract(const Duration(days: 365));
      default: // w1
        return nowUtc.subtract(const Duration(days: 365 * 5));
    }
  }

  String _apiInterval(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return '1m';
      case ChartTimeframe.m5:
        return '5m';
      case ChartTimeframe.m15:
        return '15m';
      case ChartTimeframe.h1:
        return '1h';
      case ChartTimeframe.d1:
        return '1d';
      default: // w1
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

  /// Candle interval in minutes for the given timeframe.
  int _intervalMinutes(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1: return 1;
      case ChartTimeframe.m5: return 5;
      case ChartTimeframe.m15: return 15;
      case ChartTimeframe.h1: return 60;
      case ChartTimeframe.d1: return 24 * 60;
      default: return 24 * 60 * 7; // w1
    }
  }

  /// Compute default zoom factor so ~60 candles are visible initially.
  double _defaultZoomFactor(int candleCount) {
    if (candleCount <= 0) return 1.0;
    final visible = 60.clamp(1, candleCount);
    return (visible / candleCount).clamp(0.05, 1.0);
  }

  /// Format a DateTime for the x-axis label in the inline chart.
  String _formatAxisLabel(DateTime t, ChartTimeframe tf) {
    final local = t.toLocal();
    if (tf == ChartTimeframe.m1 || tf == ChartTimeframe.m5 || tf == ChartTimeframe.m15) {
      // intraday — show HH:mm
      return '${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')}';
    }
    if (tf == ChartTimeframe.h1) {
      // hourly over a month — show "dd MMM"
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${local.day} ${months[local.month - 1]}';
    }
    // daily / weekly — show "MMM yy"
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
    final chartColor = isPos ? AppColors.success : AppColors.danger;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: _buildAppBar(context, store, stock),
      bottomNavigationBar: _buildBottomBar(context, stock),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStockHeader(context, stock),
            _buildHydrationStrip(),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppColors.cardRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildTimeframeRow(context, displaySeries),
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
                            style: TextStyle(fontSize: 11, color: AppColors.danger),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _loadSeries,
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildDayRangeRow(stock, displaySeries),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(
              'Market stats',
              trailingLabel: 'View All',
              onTrailingTap: () => _showFundamentalsSheet(context, stock),
            ),
            _buildStatsGrid(
              context,
              stock,
              displaySeries,
              MediaQuery.of(context).size.width >= 1060,
            ),
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
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    TradingStore store,
    Stock stock,
  ) {
    final inWatchlist =
        store.watchlists.any((wl) => wl.symbols.contains(stock.symbol));
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
        onPressed: () => Navigator.pop(context),
      ),
      title: null,
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.search, color: AppColors.textPrimary, size: 22),
          tooltip: 'Search',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UniversalSearchScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.notifications_outlined,
            color: AppColors.textPrimary,
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
            color: inWatchlist ? AppColors.primary : AppColors.textPrimary,
            size: 24,
          ),
          onPressed: () => _handleSaveTap(context, store, stock),
        ),
        const SizedBox(width: 4),
      ],
      shape: const Border(bottom: BorderSide(color: AppColors.divider)),
    );
  }

  void _handleSaveTap(BuildContext context, TradingStore store, Stock stock) {
    final watchlists = store.watchlists;
    if (watchlists.length > 1) {
      AppBottomSheet.show(
        context,
        title: 'Save to Watchlist',
        child: _ChooseWatchlistSheet(store: store, stock: stock),
      );
      return;
    }

    // Zero or one watchlist — no choice to make, keep a single-tap toggle.
    final wl = watchlists.isEmpty ? null : watchlists.first;
    if (wl == null) return;
    final inWatchlist = wl.symbols.contains(stock.symbol);
    if (inWatchlist) {
      store.removeSymbolFromWatchlist(wl.id, stock.symbol);
    } else {
      store.addSymbolToWatchlist(wl.id, stock.symbol);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inWatchlist
              ? '${stock.symbol} removed from ${wl.name}'
              : '${stock.symbol} added to ${wl.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _segmentLabel(InstrumentType t) {
    switch (t) {
      case InstrumentType.equity: return 'EQ';
      case InstrumentType.marketIndex: return 'IDX';
      case InstrumentType.etf: return 'ETF';
      case InstrumentType.futuresStkIdx:
      case InstrumentType.futuresCom: return 'FUT';
      case InstrumentType.optionCE: return 'CE';
      case InstrumentType.optionPE: return 'PE';
      case InstrumentType.currency: return 'CCY';
      case InstrumentType.unknown: return 'EQ';
    }
  }

  Widget _buildStockHeader(BuildContext context, Stock stock) {
    assert(() {
      _headerBuildCount++;
      debugPrint('[StockDetailPerf] ${widget.symbol} header_build=$_headerBuildCount');
      return true;
    }());
    final chips = _derivativeChips(context, stock);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity row: avatar · symbol · exchange/segment chips · name ─
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InstrumentLogo.forStock(stock, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stock.symbol,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppTagChip.neutral(stock.exchange.isNotEmpty ? stock.exchange : 'NSE'),
                        const SizedBox(width: 4),
                        AppTagChip(_segmentLabel(stock.instrumentType)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stock.name,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    // Expiry badge on its own line so it never overlaps price
                    if (stock.isFutures) ...[
                      const SizedBox(height: 4),
                      _ExpiryBadge(stock: stock),
                    ] else if (_indexNearestExpiry != null) ...[
                      const SizedBox(height: 4),
                      _IndexExpiryBadge(
                        expiryIso: _indexNearestExpiry!,
                        exchange: stock.exchange,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Price hero — the dominant element on this screen ────────────
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
              final isPos = pct >= 0;
              final color = isPos ? AppColors.success : AppColors.danger;
              final sign = isPos ? '+' : '';
              final marketOpen = _marketSettings.isTimeOpen(stock.exchange);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PriceFlashWidget(
                      price: effectiveLtp,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '₹${effectiveLtp.toStringAsFixed(2)}',
                              style: AppTheme.mono(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.0),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                isPos ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                size: 16,
                                color: color,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '$sign${amt.toStringAsFixed(2)} ($sign${pct.abs().toStringAsFixed(2)}%)',
                                  style: AppTheme.mono(fontSize: 15, fontWeight: FontWeight.w700, color: color),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    height: 36,
                    child: Sparkline(
                      valueListenable: _store!.ltpNotifier(widget.symbol),
                      color: color,
                      seedValue: effectiveLtp,
                      symbol: stock.symbol,
                      exchange: stock.exchange,
                      token: stock.token,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: marketOpen ? AppColors.success : AppColors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            marketOpen ? 'LIVE' : 'CLOSED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: marketOpen ? AppColors.success : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        marketOpen ? 'Market Open' : 'Market Closed',
                        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          // ── Derivative chips ────────────────────────────────────────────
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: chips),
          ],
          const SizedBox(height: 14),
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

    final prevCloseRef = (_timeframe == ChartTimeframe.m1 || _timeframe == ChartTimeframe.m5)
        ? series.open
        : (series.data.isNotEmpty ? series.data.first.close : 0.0);
    final liveLtp = _store!.ltpNotifier(widget.symbol).value;
    final effectiveLtp = liveLtp > 0 ? liveLtp : series.close;

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
                  _formatAxisLabel(series.data[idx].time, _timeframe),
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
              color: AppColors.surface,
              child: SizedBox(
                height: 260,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FadeTransition(
                    opacity: fadeOpacity,
                    child: !hasRealCandles
                        ? const Center(
                            child: Text(
                              'Chart data unavailable',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          )
                        : effectiveLineMode
                        // ── Line chart ─────────────────────────────────────
                        ? SfCartesianChart(
                            key: ValueKey('line_${widget.symbol}_${_timeframe.name}_$_chartKey'),
                            backgroundColor: AppColors.surface,
                            plotAreaBackgroundColor: AppColors.surface,
                            enableAxisAnimation: false,
                            plotAreaBorderWidth: 0,
                            margin: const EdgeInsets.only(right: 8),
                            primaryXAxis: _buildXAxis(),
                            primaryYAxis: NumericAxis(
                              isVisible: true,
                              opposedPosition: true,
                              rangePadding: ChartRangePadding.round,
                              labelStyle: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                              axisLabelFormatter: (details) => ChartAxisLabel(
                                _fmtAxisPrice(details.value.toDouble()),
                                details.textStyle,
                              ),
                              plotBands: [
                                if (hasRealCandles && prevCloseRef > 0)
                                  PlotBand(
                                    start: prevCloseRef,
                                    end: prevCloseRef,
                                    borderColor: AppColors.border,
                                    borderWidth: 1,
                                    dashArray: const <double>[5, 4],
                                  ),
                                if (hasRealCandles && effectiveLtp > 0)
                                  PlotBand(
                                    start: effectiveLtp,
                                    end: effectiveLtp,
                                    borderColor: chartColor,
                                    borderWidth: 1.2,
                                    dashArray: const <double>[4, 4],
                                    text: '  ${_fmtAxisPrice(effectiveLtp)}',
                                    textStyle: TextStyle(
                                      color: chartColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    verticalTextAlignment: TextAnchor.middle,
                                  ),
                              ],
                              majorGridLines: const MajorGridLines(width: 1, color: AppColors.divider),
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
                            key: ValueKey('candle_${widget.symbol}_${_timeframe.name}_$_chartKey'),
                            backgroundColor: AppColors.surface,
                            plotAreaBackgroundColor: AppColors.surface,
                            enableAxisAnimation: false,
                            plotAreaBorderWidth: 0,
                            margin: const EdgeInsets.only(right: 8),
                            primaryXAxis: _buildXAxis(),
                            primaryYAxis: NumericAxis(
                              isVisible: true,
                              opposedPosition: true,
                              rangePadding: ChartRangePadding.round,
                              labelStyle: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                              axisLabelFormatter: (details) => ChartAxisLabel(
                                _fmtAxisPrice(details.value.toDouble()),
                                details.textStyle,
                              ),
                              plotBands: [
                                if (hasRealCandles && prevCloseRef > 0)
                                  PlotBand(
                                    start: prevCloseRef,
                                    end: prevCloseRef,
                                    borderColor: AppColors.border,
                                    borderWidth: 1,
                                    dashArray: const <double>[5, 4],
                                  ),
                                if (hasRealCandles && effectiveLtp > 0)
                                  PlotBand(
                                    start: effectiveLtp,
                                    end: effectiveLtp,
                                    borderColor: chartColor,
                                    borderWidth: 1.2,
                                    dashArray: const <double>[4, 4],
                                    text: '  ${_fmtAxisPrice(effectiveLtp)}',
                                    textStyle: TextStyle(
                                      color: chartColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    verticalTextAlignment: TextAnchor.middle,
                                  ),
                              ],
                              majorGridLines: const MajorGridLines(width: 1, color: AppColors.divider),
                              axisLine: const AxisLine(width: 0),
                              majorTickLines: const MajorTickLines(size: 0),
                            ),
                            onActualRangeChanged: onRangeChanged,
                            trackballBehavior: TrackballBehavior(
                              enable: true,
                              activationMode: ActivationMode.singleTap,
                              lineColor: AppColors.textTertiary,
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
                                bearColor: AppColors.danger,
                                bullColor: AppColors.success,
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
                    key: ValueKey('vol_${widget.symbol}_${_timeframe.name}_$_chartKey'),
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
                            ? AppColors.success.withOpacity(0.28)
                            : AppColors.danger.withOpacity(0.28),
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
        if (!_isAtLive && hasRealCandles && _liveMergeableTimeframes.contains(_timeframe))
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
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                  boxShadow: AppColors.floatingShadow,
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
      ],
    );
  }

  Widget _buildTimeframeRow(BuildContext context, TradingChartSeries series) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Timeframe pills — scrollable so they never overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(_timeframeTabs.length, (i) {
                  final tf = _timeframeTabs[i];
                  final selected = tf == _timeframe;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _timeframe = tf);
                      _savedTimeframeBySymbol[widget.symbol] = tf;
                      _loadSeries();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppColors.radiusPill),
                      ),
                      child: Text(
                        _timeframeLabels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.textSecondary,
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
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _useCandleChart = !_useCandleChart),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _useCandleChart ? Icons.show_chart : Icons.bar_chart,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          // Fullscreen — opens the full-featured advanced chart screen
          Padding(
            padding: const EdgeInsets.only(right: 12),
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
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? trailingLabel, VoidCallback? onTrailingTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (trailingLabel != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trailingLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Day's Range — a compact low/high bar with a dot marking today's price,
  /// derived from the same real candle series already loaded for the chart.
  Widget _buildDayRangeRow(Stock stock, TradingChartSeries series) {
    final low = series.low > 0 ? series.low : (stock.low ?? 0);
    final high = series.high > 0 ? series.high : (stock.high ?? 0);
    if (low <= 0 || high <= 0 || high <= low) return const SizedBox.shrink();
    final liveLtp = _store!.ltpNotifier(widget.symbol).value;
    final current = liveLtp > 0 ? liveLtp : stock.currentPrice;
    final fraction = ((current - low) / (high - low)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppColors.radiusSm),
            ),
            child: const Icon(Icons.equalizer_rounded, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            "Day's Range",
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Text(
            '₹${low.toStringAsFixed(2)}',
            style: AppTheme.mono(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 2, color: AppColors.border),
                      Positioned(
                        left: (fraction * (constraints.maxWidth - 10)).clamp(0.0, constraints.maxWidth - 10),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Text(
            '₹${high.toStringAsFixed(2)}',
            style: AppTheme.mono(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ],
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
    final avgVolume = series.data.isNotEmpty
        ? series.data.map((c) => c.volume).reduce((a, b) => a + b) / series.data.length
        : 0.0;
    final base = stock.currentPrice;
    final stats = [
      ('Open', series.open > 0 ? '₹${series.open.toStringAsFixed(2)}' : '—'),
      ('Prev Close', prevClose > 0 ? '₹${prevClose.toStringAsFixed(2)}' : '—'),
      ('High', series.high > 0 ? '₹${series.high.toStringAsFixed(2)}' : '—'),
      ('Low', series.low > 0 ? '₹${series.low.toStringAsFixed(2)}' : '—'),
      (
        'Volume',
        series.volume > 0
            ? _fmtVolume(series.volume)
            : stock.volume != null
            ? _fmtVolume(stock.volume!)
            : '—',
      ),
      ('Avg. Volume', avgVolume > 0 ? _fmtVolume(avgVolume) : '—'),
      (
        'Upper Circuit',
        stock.upperCircuit != null ? '₹${stock.upperCircuit!.toStringAsFixed(2)}' : '—',
      ),
      (
        'Lower Circuit',
        stock.lowerCircuit != null ? '₹${stock.lowerCircuit!.toStringAsFixed(2)}' : '—',
      ),
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
        'Mkt Cap',
        stock.marketCap != null
            ? _fmtMarketCap(stock.marketCap!)
            : '₹${(base * 6800000 / 10000000).toStringAsFixed(0)}Cr',
      ),
      ('VWAP', series.vwap > 0 ? '₹${series.vwap.toStringAsFixed(2)}' : '—'),
    ];
    return _twoColGrid(stats, columns: 4);
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

  /// Formats a chart axis price with thousands separators (e.g. "1,292.90")
  /// without pulling in `intl` just for this.
  String _fmtAxisPrice(double v) {
    final isNeg = v < 0;
    final fixed = v.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${isNeg ? '-' : ''}$buf.${parts[1]}';
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

  Widget _twoColGrid(List<(String, String)> stats, {int columns = 2}) {
    final isFourCol = columns >= 4;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: isFourCol ? 8 : 10,
          mainAxisSpacing: isFourCol ? 8 : 10,
          childAspectRatio: isFourCol ? 1.35 : 2.6,
        ),
        itemCount: stats.length,
        itemBuilder: (_, i) => Container(
          padding: EdgeInsets.symmetric(horizontal: isFourCol ? 10 : 14, vertical: isFourCol ? 10 : 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stats[i].$1,
                style: TextStyle(fontSize: isFourCol ? 10.5 : 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                stats[i].$2,
                style: AppTheme.mono(fontSize: isFourCol ? 12.5 : 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
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
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
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
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
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
  // Base derivative chips (Option Chain / Futures) plus one always-present
  // "More" chip pointing at other real per-symbol screens already in the
  // app (Market Depth, Time & Sales) — no fabricated News/Events actions.
  List<Widget> _derivativeChips(BuildContext context, Stock stock) {
    final base = _baseDerivativeChips(context, stock);
    return [
      ...base,
      if (base.isNotEmpty) const SizedBox(width: 8),
      _DerivativeChip(
        label: 'More',
        icon: Icons.more_horiz_rounded,
        onTap: () => _showMoreSheet(context, stock),
      ),
    ];
  }

  void _showMoreSheet(BuildContext context, Stock stock) {
    AppBottomSheet.show<void>(
      context,
      title: stock.symbol,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LucideIcons.layers, size: 18, color: AppColors.textSecondary),
            title: const Text('Market Depth', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => MarketDepthScreen(symbol: stock.symbol)));
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.clock3, size: 18, color: AppColors.textSecondary),
            title: const Text('Time & Sales', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAndSalesScreen(symbol: stock.symbol)));
            },
          ),
        ],
      ),
    );
  }

  void _showFundamentalsSheet(BuildContext context, Stock stock) {
    AppBottomSheet.show<void>(
      context,
      title: 'Fundamentals',
      child: _buildFundamentalsGrid(context, stock),
    );
  }

  List<Widget> _baseDerivativeChips(BuildContext context, Stock stock) {
    final type = stock.instrumentType;
    final ex = stock.exchange.toUpperCase();

    // Futures: show "View Option Chain" link (NSE and MCX both support options)
    if (type.isFuturesContract) {
      return [
        _DerivativeChip(
          label: 'Option Chain',
          icon: Icons.grid_view_rounded,
          primary: true,
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
          primary: true,
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
          primary: true,
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

  /// Real countdown to market close, computed from the admin-configured
  /// per-segment market hours ([MarketSettings]) — not a fabricated timer.
  (String, String)? _marketOpenCountdown(Stock stock) {
    if (!_marketSettings.isTimeOpen(stock.exchange)) return null;
    final seg = _marketSettings.forExchange(stock.exchange);
    final closeParts = seg.marketClose.split(':');
    final closeHour = int.tryParse(closeParts[0]) ?? 15;
    final closeMin = int.tryParse(closeParts.length > 1 ? closeParts[1] : '30') ?? 30;
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final closeIst = DateTime(nowIst.year, nowIst.month, nowIst.day, closeHour, closeMin);
    final remaining = closeIst.difference(nowIst);
    if (remaining.isNegative) return null;
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return (_fmtTime12h(closeHour, closeMin), '${h}h ${m}m remaining');
  }

  String _fmtTime12h(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }

  void _showTradingHoursSheet(BuildContext context, Stock stock) {
    final seg = _marketSettings.forExchange(stock.exchange);
    final openParts = seg.marketOpen.split(':');
    final closeParts = seg.marketClose.split(':');
    AppBottomSheet.show<void>(
      context,
      title: 'Trading Hours',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '${_fmtTime12h(int.tryParse(openParts[0]) ?? 9, int.tryParse(openParts.length > 1 ? openParts[1] : '15') ?? 15)}'
          ' – '
          '${_fmtTime12h(int.tryParse(closeParts[0]) ?? 15, int.tryParse(closeParts.length > 1 ? closeParts[1] : '30') ?? 30)}'
          ' IST, Mon–Fri',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, Stock stock) {
    final sellBlock = _marketSettings.checkAction(stock.exchange, isBuy: false);
    final buyBlock = _marketSettings.checkAction(stock.exchange, isBuy: true);
    final anyBlock = sellBlock ?? buyBlock;
    final openCountdown = anyBlock == null ? _marketOpenCountdown(stock) : null;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Market status — an elegant, subtle banner, not a warning box.
          if (anyBlock != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppColors.radiusPill),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 13, color: AppColors.warning),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      anyBlock,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (openCountdown != null) ...[
            GestureDetector(
              onTap: () => _showTradingHoursSheet(context, stock),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 13, color: AppColors.success),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Market Open  ',
                              style: TextStyle(fontSize: 11.5, color: AppColors.success, fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: 'Closes at ${openCountdown.$1} • ${openCountdown.$2}',
                              style: TextStyle(fontSize: 11.5, color: AppColors.success.withOpacity(0.85), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 15, color: AppColors.success.withOpacity(0.7)),
                  ],
                ),
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
                      backgroundColor: AppColors.danger,
                      disabledBackgroundColor: AppColors.border,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.cardRadius),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SELL',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // BUY
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: buyBlock != null
                        ? null
                        : () => _openOrderDrawer(context, OrderType.buy),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      disabledBackgroundColor: AppColors.border,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.cardRadius),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'BUY',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
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

}

// ─── Derivative shortcut chip (Options Chain / Futures) ──────────────────────

class _DerivativeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _DerivativeChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.primary;
    return Material(
      color: primary ? AppColors.primary : AppColors.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(AppColors.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
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
      bg = AppColors.danger.withOpacity(0.10);
      fg = AppColors.danger;
    } else if (safeDays <= 30) {
      bg = AppColors.warning.withOpacity(0.10);
      fg = AppColors.warning;
    } else {
      bg = AppColors.chipNeutralBg;
      fg = AppColors.chipNeutralText;
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
      bg = AppColors.danger.withOpacity(0.10);
      fg = AppColors.danger;
    } else if (days <= 30) {
      bg = AppColors.warning.withOpacity(0.10);
      fg = AppColors.warning;
    } else {
      bg = AppColors.success.withOpacity(0.10);
      fg = AppColors.success;
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


// ─── Choose Watchlist sheet ───────────────────────────────────────────────────
// Shown from the save/bookmark button when the user has more than one
// watchlist, so they can pick which one(s) to save the stock into.

class _ChooseWatchlistSheet extends StatefulWidget {
  final TradingStore store;
  final Stock stock;

  const _ChooseWatchlistSheet({required this.store, required this.stock});

  @override
  State<_ChooseWatchlistSheet> createState() => _ChooseWatchlistSheetState();
}

class _ChooseWatchlistSheetState extends State<_ChooseWatchlistSheet> {
  @override
  Widget build(BuildContext context) {
    final watchlists = widget.store.watchlists;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final wl in watchlists)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(wl.name),
            subtitle: Text(
              '${wl.symbols.length} stock${wl.symbols.length == 1 ? '' : 's'}',
            ),
            value: wl.symbols.contains(widget.stock.symbol),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  widget.store.addSymbolToWatchlist(wl.id, widget.stock.symbol);
                } else {
                  widget.store.removeSymbolFromWatchlist(wl.id, widget.stock.symbol);
                }
              });
            },
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _createAndAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New watchlist'),
        ),
      ],
    );
  }

  void _createAndAdd() {
    if (widget.store.watchlists.length >= Watchlist.maxWatchlists) {
      AppToast.warning(context, 'Maximum ${Watchlist.maxWatchlists} watchlists allowed.');
      return;
    }
    AppDialog.input(
      context,
      title: 'New Watchlist',
      hint: 'Watchlist name',
      confirmLabel: 'Create',
      onSubmit: (name) {
        widget.store.createWatchlist(name);
        final created = widget.store.watchlists.last;
        widget.store.addSymbolToWatchlist(created.id, widget.stock.symbol);
        setState(() {});
      },
    );
  }
}
