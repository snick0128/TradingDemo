import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/live_market_service.dart';
import '../models/platform_settings.dart';
import '../models/trading_models.dart';
import '../services/alert_service.dart';
import '../services/market_data_service.dart';
import '../services/subscription_manager.dart';

// RMS FIX:
// Bug #9  — Flutter state was in-memory only, lost on refresh.
// Bug #12 — Sell credited ₹0 to balance in offline path.
// Bug #13 — Opening balance hardcoded to ₹45,000 vs backend ₹1,00,000.
// Solution: TradingStore now streams Firestore for balance, holdings, orders.
//           Flutter is a rendering layer — backend is source of truth.
//           Local mutations are kept ONLY for the offline/mock path.
//           When Firebase auth is present, all state comes from Firestore.

class OrderResult {
  final bool success;
  final String? orderId;
  final String? errorMessage;

  const OrderResult({required this.success, this.orderId, this.errorMessage});

  /// Backward-compatible message getter
  String get message =>
      success ? (orderId ?? 'Success') : (errorMessage ?? 'Error');
}

class TradingStore extends ChangeNotifier {
  TradingStore()
    : _watchlist = <Stock>[],
      _watchlistUniverse = {},
      _orders = <Order>[],
      _portfolio = <PortfolioItem>[],
      _positions = <Position>[],
      _holdings = <Holding>[],
      _transactions = <Transaction>[],
      _currentUser = User(
        id: '',
        clientId: '',
        name: '',
        email: '',
        isActive: false,
        balance: 0.0,
        marginLimit: 0.0,
        registeredAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      _balance = 0.0 {
    // Stub service — no random prices. Live backend fills the watchlist.
    _marketDataService = MarketDataService({});
    _alertService = AlertService(this, _marketDataService);
  }

  late final MarketDataService _marketDataService;
  MarketDataService get marketDataService => _marketDataService;
  late final AlertService _alertService;
  // No mock price subscription — live backend is the only price source.
  StreamSubscription<Map<String, double>>? _priceSubscription;

  // Track last known LTP per symbol to suppress no-op emissions.
  final Map<String, double> _lastLtpBySymbol = {};

  // Per-symbol notifiers for zero-overhead targeted price rebuilds.
  final Map<String, ValueNotifier<double>> _ltpNotifiers = {};

  // Granular per-metric notifiers — widgets subscribe directly and bypass
  // notifyListeners() so only the subscribing widget rebuilds, not the tree.
  final Map<String, ValueNotifier<double>> _changeNotifiers = {};
  final _runningPnlNotifier      = ValueNotifier<double>(0.0);
  final _equityNotifier          = ValueNotifier<double>(0.0);
  final _availableMarginNotifier = ValueNotifier<double>(0.0);
  final _marginShortfallNotifier = ValueNotifier<double>(0.0);
  final _topMoversNotifier       = ValueNotifier<List<Stock>>(const []);

  // Targeted structural version counters — increment only when that data
  // category changes (never on price ticks). Screens subscribe to exactly
  // one and skip the structural-gate boilerplate entirely.
  final _positionsVersion = ValueNotifier<int>(0);
  final _ordersVersion    = ValueNotifier<int>(0);
  final _accountVersion   = ValueNotifier<int>(0);

  // Render tracing: batch addPostFrameCallback so we schedule at most 1 per frame.
  bool _renderTracePending = false;
  final List<({String symbol, double ltp, int storeExitTs})> _pendingRenderTrace = [];

  // Tick-to-frame latency ring buffer — last 512 measurements, reported every 30s.
  final List<int> _frameLatencies = [];
  Timer? _latencyReportTimer;

  /// Returns a [ValueNotifier<double>] for [symbol] that fires on every tick.
  /// Use with [ValueListenableBuilder] for instant, targeted price rebuilds.
  ValueNotifier<double> ltpNotifier(String symbol) =>
      _ltpNotifiers.putIfAbsent(
          symbol, () => ValueNotifier(_lastLtpBySymbol[symbol] ?? 0.0));

  /// Per-symbol change-% notifier, seeded from already-cached stock data.
  ValueNotifier<double> changeNotifier(String symbol) =>
      _changeNotifiers.putIfAbsent(symbol, () {
        final existing = _watchlistUniverse[symbol];
        return ValueNotifier(existing?.changePercentage ?? 0.0);
      });

  ValueNotifier<double>       get runningPnlNotifier      => _runningPnlNotifier;
  ValueNotifier<double>       get equityNotifier          => _equityNotifier;
  ValueNotifier<double>       get availableMarginNotifier => _availableMarginNotifier;
  ValueNotifier<double>       get marginShortfallNotifier => _marginShortfallNotifier;
  ValueNotifier<List<Stock>>  get topMoversNotifier       => _topMoversNotifier;
  ValueNotifier<int>          get positionsVersion        => _positionsVersion;
  ValueNotifier<int>          get ordersVersion           => _ordersVersion;
  ValueNotifier<int>          get accountVersion          => _accountVersion;

  // ── Live backend wiring ────────────────────────────────────────────────────
  LiveMarketService? _liveMarketService;
  StreamSubscription<List<Stock>>? _liveStockSub;
  StreamSubscription<Map<String, dynamic>>? _wsNotifSub;
  StreamSubscription<Map<String, List<Stock>>>? _moversSub;

  // Pre-computed top movers from the movers stream (updated every ~5 s, not every tick).
  List<Stock> _topGainers = [];
  List<Stock> _topLosers  = [];
  bool _usingLiveBackend = false;
  bool get usingLiveBackend => _usingLiveBackend;
  LiveMarketService? get liveMarketService => _liveMarketService;
  int get activeTradingStoreListeners =>
      [_liveStockSub, _wsNotifSub, _moversSub].where((s) => s != null).length;
  int get activeNotifiers => _ltpNotifiers.length;

  /// Call this once after the store is created to switch from mock prices
  /// to live prices from the Node.js backend.
  ///
  /// Safe to call multiple times — idempotent.
  void connectLiveBackend({String? baseUrl}) {
    if (_usingLiveBackend) return;

    final api = BackendApiService(
      baseUrl: baseUrl ?? BackendConfig.backendBaseUrl,
    );
    _liveMarketService = LiveMarketService(
      api: api,
      onError: (isError, message) {
        setBackendError(isError, message: message);
      },
    );

    // Stop mock price timer — live service takes over
    _priceSubscription?.cancel();
    _marketDataService.dispose();

    _liveStockSub = _liveMarketService!.stockUpdates.listen(_onLiveStockUpdate);
    _wsNotifSub   = _liveMarketService!.notificationStream.listen(_onWsNotification);
    _moversSub    = _liveMarketService!.moversUpdates.listen(_onMoversUpdate);
    unawaited(_liveMarketService!.start());
    _refreshMarketSubscriptions();
    _usingLiveBackend = true;
    _latencyReportTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _reportLatencyStats(),
    );
  }

  /// Register userId with the live backend WebSocket for real-time notification push.
  void registerLiveUser(String userId) {
    _liveMarketService?.registerUser(userId);
  }

  /// Called when the app returns to the foreground. Immediately reconnects the
  /// WebSocket so stale or dropped connections are detected without waiting for
  /// the 45-second heartbeat timeout. Also refreshes the subscription list in
  /// case positions/holdings changed while backgrounded.
  void onAppResumed() {
    // Handled by SubscriptionManager globally. Refresh registered screen subscriptions.
    _refreshMarketSubscriptions();
  }

  void _onWsNotification(Map<String, dynamic> raw) {
    final id        = raw['id']        as String? ?? '${DateTime.now().millisecondsSinceEpoch}';
    final title     = raw['title']     as String? ?? '';
    final body      = raw['body']      as String? ?? '';
    final typeStr   = raw['type']      as String? ?? '';
    final createdAt = raw['createdAt'] as int?;
    final ts = createdAt != null
        ? DateTime.fromMillisecondsSinceEpoch(createdAt)
        : DateTime.now();

    final alertType = _alertTypeFromNotifType(typeStr);
    final notif = AppNotification(
      id:               id,
      title:            title,
      message:          body,
      timestamp:        ts,
      isRead:           false,
      relatedAlertType: alertType,
    );
    addNotification(notif);
  }

  AlertType? _alertTypeFromNotifType(String type) {
    switch (type) {
      case 'order_executed':      return AlertType.orderExecution;
      case 'order_rejected':      return AlertType.orderRejection;
      case 'margin_warning':      return AlertType.marginWarning;
      case 'rms_alert':           return AlertType.marginWarning;
      case 'rms_auto_squareoff':  return AlertType.autoSquareOffWarning;
      case 'squareoff_warning':   return AlertType.autoSquareOffWarning;
      default:                    return AlertType.news;
    }
  }

  /// Disconnect from live backend.
  void disconnectLiveBackend() {
    if (!_usingLiveBackend) return;
    _liveStockSub?.cancel();
    _wsNotifSub?.cancel();
    _moversSub?.cancel();
    _liveMarketService?.dispose();
    _liveMarketService = null;
    _usingLiveBackend = false;
  }

  // ── Live backend status ────────────────────────────────────────────────────
  bool _backendError = false;
  bool get backendError => _backendError;
  String _backendErrorMessage = '';
  String get backendErrorMessage => _backendErrorMessage;

  void setBackendError(bool error, {String message = ''}) {
    if (_backendError == error && _backendErrorMessage == message) return;
    _backendError = error;
    _backendErrorMessage = message;
    notifyListeners();
  }

  // ── Firestore state streaming ──────────────────────────────────────────────
  // All Firestore streams are managed by main.dart (_bindUserRealtime).
  // main.dart calls replaceOrders / replaceHoldings / replacePositions on this
  // store when Firestore emits. TradingStore is a pure in-memory state holder —
  // it does NOT open its own Firestore listeners.

  /// Called when the live backend emits a tick for one or more stocks.
  /// Ticks arrive one-at-a-time (immediate emit — no batch timer).
  void _onLiveStockUpdate(List<Stock> stocks) {
    if (stocks.isEmpty) return;
    bool anyPriceChanged = false;

    // Clear error state — backend is responding
    if (_backendError) {
      _backendError = false;
      _backendErrorMessage = '';
      anyPriceChanged = true; // force notify to clear error banner
    }

    for (final stock in stocks) {
      final newLtp = stock.currentPrice;
      final storeEntryTs = DateTime.now().millisecondsSinceEpoch;

      if (newLtp > 0) {
        _lastLtpBySymbol[stock.symbol] = newLtp;
        _ltpNotifiers[stock.symbol]?.value = newLtp;
        // Also update by raw token so _LiveOptionLtp can fall back to token
        // as the notifier key when ceSymbol is absent from the options chain API.
        if (stock.token.isNotEmpty) {
          _ltpNotifiers[stock.token]?.value = newLtp;
        }
        // Push change% — guarded so only actual changes fire the notifier.
        final changeN = _changeNotifiers[stock.symbol];
        if (changeN != null) {
          final newChange = stock.changePercentage;
          if (changeN.value != newChange) changeN.value = newChange;
        }
      }
      final ltpNotifierTs = DateTime.now().millisecondsSinceEpoch;
      anyPriceChanged = true;

      final existing = _watchlistUniverse[stock.symbol];
      final oldPrice = existing?.currentPrice;

      // Update watchlist entry — O(1) via index map.
      // Only symbols the user explicitly added are in _watchlist/_watchlistIndex.
      // All ticking symbols go into _watchlistUniverse for price lookups.
      final idx = _watchlistIndex[stock.symbol] ?? -1;
      if (idx >= 0) {
        _diagWatchlistIndexHits++;
        _watchlist[idx] = stock;
      } else {
        _diagWatchlistIndexMisses++;
      }
      _watchlistUniverse[stock.symbol] = stock;

      // Record direction for price flash arrows
      if (oldPrice != null && oldPrice != newLtp) {
        _marketDataService.recordDirection(stock.symbol, oldPrice, newLtp);
      }

      // Push depth update to MarketDepthScreen stream when tick carries depth.
      if (stock.depth != null) {
        _marketDataService.pushDepth(stock.symbol, stock.depth!);
      }

      // Token-based lookup preferred (globally unique per contract); falls back
      // to exchange:symbol for positions loaded before the token was persisted.
      final posIndices =
          (stock.token.isNotEmpty ? _positionTokenIndex[stock.token] : null) ??
          _positionIndex['${stock.exchange}:${stock.symbol}'];
      if (posIndices != null) {
        for (final i in posIndices) {
          _positions[i] = _positions[i].copyWith(currentPrice: newLtp);
        }
      }

      // Update holdings with new price (O(1) via index map).
      // Holdings don't carry exchange, so symbol-only key is used here.
      final holdingIdx = _holdingIndex[stock.symbol];
      if (holdingIdx != null) {
        _holdings[holdingIdx] = _holdings[holdingIdx].copyWith(currentPrice: newLtp);
      }

      // Latency audit: record store-side timestamps for traced symbols.
      if (newLtp > 0 && (_liveMarketService?.isTraced(stock.symbol) ?? false)) {
        final storeExitTs = DateTime.now().millisecondsSinceEpoch;
        _liveMarketService!.patchLastStoreTrace(
          stock.symbol, newLtp,
          storeEntryTs:  storeEntryTs,
          ltpNotifierTs: ltpNotifierTs,
          storeExitTs:   storeExitTs,
        );
        _pendingRenderTrace.add((symbol: stock.symbol, ltp: newLtp, storeExitTs: storeExitTs));
      }
    }

    // Push granular P&L/margin notifiers after every batch so VLB-subscribed
    // widgets update without waiting for the full notifyListeners() rebuild.
    // Compute once to avoid the runningPnL fold() running 4 times per tick.
    if (anyPriceChanged) {
      final newPnL = _positions.fold<double>(0.0, (s, p) => s + p.unrealizedPnl);
      final um = usedMargin; // single fold over positions for margin
      final newEquity = _balance + um + newPnL;
      final newAvailableMargin = (newEquity - um).clamp(0.0, double.infinity);
      final newMarginShortfall = (um - newEquity).clamp(0.0, double.infinity);
      if (_runningPnlNotifier.value != newPnL) _runningPnlNotifier.value = newPnL;
      if (_equityNotifier.value != newEquity) _equityNotifier.value = newEquity;
      if (_availableMarginNotifier.value != newAvailableMargin) _availableMarginNotifier.value = newAvailableMargin;
      if (_marginShortfallNotifier.value != newMarginShortfall) _marginShortfallNotifier.value = newMarginShortfall;
    }

    if (!anyPriceChanged) return;

    // Schedule post-frame measurement for every tick batch (not just traced symbols).
    // batchExitTs is captured here, just before notifyListeners() schedules rebuilds,
    // so frameMs = renderTs - batchExitTs covers the full store-to-paint latency.
    if (!_renderTracePending) {
      _renderTracePending = true;
      final batchExitTs = DateTime.now().millisecondsSinceEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _renderTracePending = false;
        final renderTs = DateTime.now().millisecondsSinceEpoch;
        final frameMs = renderTs - batchExitTs;
        _addFrameLatency(frameMs);
        if (_pendingRenderTrace.isNotEmpty) {
          for (final entry in _pendingRenderTrace) {
            _liveMarketService?.recordRenderCompletion(
                entry.symbol, entry.ltp, renderTs, entry.storeExitTs);
          }
          _pendingRenderTrace.clear();
        }
      });
    }

    // Price ticks flow exclusively through per-symbol ltpNotifier/changeNotifier
    // VLBs and the granular P&L notifiers above.  Global notifyListeners() is
    // intentionally absent here — every price-path widget already uses a
    // targeted ValueListenableBuilder, so a global rebuild is pure overhead.
  }

  void _addFrameLatency(int ms) {
    _frameLatencies.add(ms);
    if (_frameLatencies.length > 512) _frameLatencies.removeAt(0);
  }

  void _reportLatencyStats() {
    _frameLatencies.clear();
  }

  void _onMoversUpdate(Map<String, List<Stock>> data) {
    _topGainers = data['gainers'] ?? [];
    _topLosers  = data['losers']  ?? [];
    _topMoversNotifier.value = topMovers.toList();
    // topMoversNotifier VLB drives _TopMoversGrid — no global notify needed.
  }

  void _refreshMarketSubscriptions() {
    final dashboardSymbols = <String>{
      'NIFTY',
      'BANKNIFTY',
      ..._watchlist.map((s) => s.symbol),
      ..._positions.map((p) => p.symbol),
      ..._holdings.map((h) => h.symbol),
    };
    if (!setEquals(_lastDashboardSymbols, dashboardSymbols)) {
      _lastDashboardSymbols = Set.unmodifiable(dashboardSymbols);
      SubscriptionManager.instance.replaceScreenSubscriptions('dashboard', dashboardSymbols);
    }

    final portfolioSymbols = <String>{
      ..._positions.map((p) => p.symbol),
      ..._holdings.map((h) => h.symbol),
    };
    if (!setEquals(_lastPortfolioSymbols, portfolioSymbols)) {
      _lastPortfolioSymbols = Set.unmodifiable(portfolioSymbols);
      SubscriptionManager.instance.replaceScreenSubscriptions('portfolio', portfolioSymbols);
    }
  }

  void monitorSymbol(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty || !_monitoredSymbols.add(normalized)) return;
    _refreshMarketSubscriptions();
  }

  void unmonitorSymbol(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    if (!_monitoredSymbols.remove(normalized)) return;
    _refreshMarketSubscriptions();
  }

  void monitorSymbols(Iterable<String> symbols) {
    var added = false;
    for (final s in symbols) {
      final n = s.trim().toUpperCase();
      if (n.isNotEmpty && _monitoredSymbols.add(n)) added = true;
    }
    if (added) _refreshMarketSubscriptions();
  }

  void unmonitorSymbols(Iterable<String> symbols) {
    var removed = false;
    for (final s in symbols) {
      final n = s.trim().toUpperCase();
      if (_monitoredSymbols.remove(n)) removed = true;
    }
    if (removed) _refreshMarketSubscriptions();
  }

  void subscribeFnoTokens(List<String> tokens, String exchange) {
    _liveMarketService?.subscribeFnoTokens(tokens, exchange);
  }

  final List<Stock> _watchlist;
  final Map<String, Stock> _watchlistUniverse;
  final Set<String> _monitoredSymbols = {};
  final List<Order> _orders;
  final List<PortfolioItem> _portfolio;
  final List<Position> _positions;
  final List<Holding> _holdings;
  final List<Transaction> _transactions;

  // O(1) index maps for tick-driven price updates — rebuilt on every replace.
  // _positionIndex    : "exchange:symbol" → indices  (always populated)
  // _positionTokenIndex: token           → indices  (populated only when position.token != '')
  // Lookup uses token first (globally unique per contract) then falls back
  // to exchange:symbol, so positions without a stored token still receive updates.
  final Map<String, List<int>> _positionIndex      = {};
  final Map<String, List<int>> _positionTokenIndex = {};
  final Map<String, int> _holdingIndex = {}; // symbol → index (unique per symbol)
  // symbol → index in _watchlist — O(1) replacement for indexWhere in the tick path.
  // Maintained incrementally on add; fully rebuilt on removal (non-hot-path).
  final Map<String, int> _watchlistIndex = {};

  // Dedup guards: _refreshMarketSubscriptions() skips replaceScreenSubscriptions
  // if the symbol set hasn't changed since the last call.
  Set<String>? _lastDashboardSymbols;
  Set<String>? _lastPortfolioSymbols;

  // ── Watchlist index diagnostics (lifetime counters) ───────────────────────
  int _diagWatchlistIndexHits   = 0;
  int _diagWatchlistIndexMisses = 0;
  User _currentUser;

  double _balance;
  // RMS FIX Bug #13: Opening balance was hardcoded to ₹45,000.
  // Backend creates users with ₹1,00,000. Use backend default as reference.
  // When Firestore streams are active, _balance is overwritten from Firestore.
  final double _openingBalance = 100000;
  String _fontSizePreset = 'Medium';
  double _textScaleFactor = 1.0;

  bool _showMisSquareOffWarning = false;
  bool get showMisSquareOffWarning => _showMisSquareOffWarning;

  // ── Account Equity (streamed from Firestore users/{userId}) ───────────────
  AccountEquity _accountEquity = AccountEquity.zero;
  AccountEquity get accountEquity => _accountEquity;

  // ── Platform settings (leverage, RMS, support) ────────────────────────────
  PlatformRmsSettings _rmsSettings = PlatformRmsSettings.defaults;
  SupportConfig _supportConfig = const SupportConfig();

  PlatformRmsSettings get rmsSettings => _rmsSettings;
  SupportConfig get supportConfig => _supportConfig;

  void updateRmsSettings(PlatformRmsSettings settings) {
    _rmsSettings = settings;
    notifyListeners();
  }

  void updateSupportConfig(SupportConfig config) {
    _supportConfig = config;
    notifyListeners();
  }

  /// Effective intraday leverage — uses admin setting or 5x default.
  double get intradayLeverage => _rmsSettings.intradayLeverage;
  double get shortSellLeverage => _rmsSettings.shortSellLeverage;

  void setMisSquareOffWarning(bool value) {
    if (_showMisSquareOffWarning == value) return;
    _showMisSquareOffWarning = value;
    notifyListeners();
  }

  bool? getPriceDirection(String symbol) =>
      _marketDataService.getPriceDirection(symbol);

  @override
  void dispose() {
    _latencyReportTimer?.cancel();
    _priceSubscription?.cancel();
    _liveStockSub?.cancel();
    _wsNotifSub?.cancel();
    _moversSub?.cancel();
    _liveMarketService?.dispose();
    _alertService.dispose();
    _marketDataService.dispose();
    for (final n in _ltpNotifiers.values) n.dispose();
    _ltpNotifiers.clear();
    for (final n in _changeNotifiers.values) n.dispose();
    _changeNotifiers.clear();
    _runningPnlNotifier.dispose();
    _equityNotifier.dispose();
    _availableMarginNotifier.dispose();
    _marginShortfallNotifier.dispose();
    _topMoversNotifier.dispose();
    _positionsVersion.dispose();
    _ordersVersion.dispose();
    _accountVersion.dispose();
    super.dispose();
  }

  UnmodifiableListView<Stock> get watchlist => UnmodifiableListView(_watchlist);

  /// All symbols ever seen from live ticks or snapshots, available for price
  /// lookups even if not in the user's curated watchlist.
  Iterable<Stock> get knownStocks => _watchlistUniverse.values;

  /// Top gainers and losers from the last movers update (updated ~every 5 s).
  /// Gainers first, then losers — up to 10 stocks total.
  List<Stock> get topMovers => [..._topGainers, ..._topLosers];

  Map<String, dynamic> get watchlistDiagnostics => {
    'watchlistSize':        _watchlist.length,
    'watchlistIndexHits':   _diagWatchlistIndexHits,
    'watchlistIndexMisses': _diagWatchlistIndexMisses,
  };
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<PortfolioItem> get portfolio =>
      UnmodifiableListView(_portfolio);
  UnmodifiableListView<Position> get positions =>
      UnmodifiableListView(_positions);
  UnmodifiableListView<Holding> get holdings => UnmodifiableListView(_holdings);
  UnmodifiableListView<Transaction> get transactions =>
      UnmodifiableListView(_transactions);
  User get currentUser => _currentUser;

  double get balance => _balance;
  double get openingBalance => _openingBalance;
  String get fontSizePreset => _fontSizePreset;
  double get textScaleFactor => _textScaleFactor;

  double get payIn => _transactions
      .where((tx) => tx.isDeposit && tx.title.contains('Funds'))
      .fold(0.0, (sum, tx) => sum + tx.amount);
  double get payOut => _transactions
      .where((tx) => !tx.isDeposit && tx.title.contains('Withdrawal'))
      .fold(0.0, (sum, tx) => sum + tx.amount);
  /// Used margin — single source of truth for live and offline paths.
  ///
  /// Live backend (Firebase): sum of `marginUsed` on every open MIS/NRML
  /// position loaded from Firestore. This is the margin the backend actually
  /// blocked, so it always matches the balance deduction.
  ///
  /// Offline / mock path: computed from local mock transaction log (legacy).
  double get usedMargin {
    if (_usingLiveBackend) {
      // Derive from positions written by the backend — never from local state.
      return _positions
          .where((p) =>
              p.product == ProductType.mis ||
              p.product == ProductType.nrml)
          .fold(0.0, (sum, p) => sum + p.marginUsed);
    }
    // Mock / offline path: use transaction log.
    return _transactions
        .where((tx) => !tx.isDeposit && tx.title.contains('Margin blocked'))
        .fold(0.0, (sum, tx) => sum + tx.amount) -
    _transactions
        .where((tx) => tx.isDeposit && tx.title.contains('Margin released'))
        .fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double get totalInvestment =>
      _portfolio.fold(0, (sum, item) => sum + item.investedValue);
  double get totalCurrentValue =>
      _portfolio.fold(0, (sum, item) => sum + item.currentValue);
  double get totalPnl => totalCurrentValue - totalInvestment;
  double get totalBalance => _balance + usedMargin;

  MarginBreakdown get marginBreakdown {
    final spanMargin = usedMargin * 0.6;
    final exposureMargin = usedMargin * 0.4;
    final collateralValue = _holdings.fold<double>(
      0,
      (sum, h) => sum + h.currentValue * 0.5,
    );
    final marginAvailable = _balance + collateralValue;
    return MarginBreakdown(
      availableCash: _balance,
      marginUsed: usedMargin,
      marginAvailable: marginAvailable,
      collateralValue: collateralValue,
      spanMargin: spanMargin,
      exposureMargin: exposureMargin,
      peakMargin: usedMargin * 1.1,
    );
  }

  // ── Equity getters — always computed live from streaming state ──────────
  //
  // IMPORTANT: Do NOT use _accountEquity.equity / freeMargin / runningPnL for
  // primary display. Those fields are written to Firestore only when the backend
  // RMS engine receives a price tick for a symbol with an open position.
  // Between ticks — and whenever there are no open positions — they are stale.
  // A user whose balance was ₹22,000 but whose equity field was last written at
  // ₹2,000 would see ₹2,000 displayed. Always compute from live streams instead.
  //
  // Formula:
  //   runningPnL    = sum(unrealizedPnl across open positions)  [from _positions stream]
  //   walletBalance = _balance + usedMargin                     [_balance = free cash from user stream]
  //   equity        = walletBalance + runningPnL
  //   freeMargin    = equity - usedMargin

  /// Sum of unrealized P&L across all open MIS/NRML positions.
  /// Always computed from the live Firestore-streamed _positions list.
  double get runningPnL =>
      _positions.fold<double>(0.0, (s, p) => s + p.unrealizedPnl);

  /// Live equity = walletBalance + runningPnL.
  /// walletBalance = _balance (free cash) + usedMargin (blocked margin).
  double get equity {
    final running = runningPnL;
    // _balance = free cash after margin is blocked (from Firestore user stream)
    // usedMargin = sum of marginUsed on open positions (from Firestore holdings stream)
    // walletBalance = _balance + usedMargin (margin is blocked, not permanently deducted)
    return _balance + usedMargin + running;
  }

  /// Cash available for new orders = equity - usedMargin.
  double get freeMargin => equity - usedMargin;

  /// Available margin — never negative. max(0, equity − usedMargin)
  double get availableMargin => (equity - usedMargin).clamp(0.0, double.infinity);

  /// Margin shortfall — how far equity is below the required margin. Zero when healthy.
  double get marginShortfall => (usedMargin - equity).clamp(0.0, double.infinity);

  /// Margin level % = (equity / usedMargin) × 100. Null when no open positions.
  double? get marginLevel {
    final um = usedMargin;
    if (um <= 0) return null;
    return (equity / um) * 100;
  }

  /// Update equity metrics from the Firestore users/{userId} document.
  /// Called by main.dart's user stream listener on every snapshot.
  void updateAccountEquity(AccountEquity newEquity) {
    // Only notify if a meaningful field changed (avoids spurious rebuilds).
    if (_accountEquity.equity == newEquity.equity &&
        _accountEquity.freeMargin == newEquity.freeMargin &&
        _accountEquity.usedMargin == newEquity.usedMargin &&
        _accountEquity.runningPnL == newEquity.runningPnL) return;
    _accountEquity = newEquity;
    _accountVersion.value++;
    notifyListeners();
  }

  Stock? stockBySymbolOrNull(String symbol) {
    // Exact match first
    Stock? exact = _watchlistUniverse[symbol];
    if (exact == null) {
      for (final s in _watchlist) {
        if (s.symbol == symbol) { exact = s; break; }
      }
    }
    if (exact != null) return exact;
    // Case-insensitive fallback (handles RELIANCE vs reliance)
    final upper = symbol.toUpperCase();
    if (_watchlistUniverse.containsKey(upper)) return _watchlistUniverse[upper];
    for (final s in _watchlist) {
      if (s.symbol.toUpperCase() == upper) return s;
    }
    return null;
  }

  /// Last non-zero LTP received from the live feed for [symbol].
  /// Returns 0 if no valid tick has ever been received.
  /// Survives reconnects and watchlist changes — never reset to 0 once set.
  double lastValidLtp(String symbol) => _lastLtpBySymbol[symbol] ?? 0;

  Stock stockBySymbol(String symbol) {
    final found = stockBySymbolOrNull(symbol);
    if (found != null) return found;
    // Not in universe — use last known LTP if available so callers don't see
    // a stale 0 after a brief disconnect or watchlist navigation.
    return Stock(
      symbol: symbol,
      name: symbol,
      currentPrice: _lastLtpBySymbol[symbol] ?? 0,
      changePercentage: 0,
      sector: '',
    );
  }

  /// Register a stock from a search result so the detail screen can access
  /// its exchange and token even if it's not in the watchlist.
  /// Does NOT add it to the watchlist — only to the universe map.
  ///
  /// ALWAYS updates exchange+token — never skips if already registered,
  /// because the existing entry may have been seeded with wrong defaults
  /// (e.g. NSE from the bootstrap snapshot before the search result arrived).
  void registerSearchResult({
    required String symbol,
    required String displayName,
    required String exchange,
    required String token,
    double ltp = 0,
    double changePercent = 0,
    InstrumentType instrumentType = InstrumentType.unknown,
    double? strikePrice,
    DateTime? expiry,
  }) {
    final resolvedExchange = exchange.isNotEmpty
        ? exchange.toUpperCase()
        : 'NSE';

    debugPrint(
      '[DETAIL_OPEN] symbol=$symbol exchange=$resolvedExchange token=$token type=$instrumentType',
    );

    final existing = _watchlistUniverse[symbol];
    if (existing != null) {
      _watchlistUniverse[symbol] = Stock(
        symbol: existing.symbol,
        name: displayName.isNotEmpty ? displayName : existing.name,
        currentPrice: ltp > 0 ? ltp : existing.currentPrice,
        changePercentage: changePercent != 0
            ? changePercent
            : existing.changePercentage,
        sector: existing.sector,
        exchange: resolvedExchange,
        token: token.isNotEmpty ? token : existing.token,
        prevClose: existing.prevClose,
        volume: existing.volume,
        isStale: existing.isStale,
        // Always update from the authoritative search result
        instrumentType: instrumentType != InstrumentType.unknown
            ? instrumentType
            : existing.instrumentType,
        strikePrice: strikePrice ?? existing.strikePrice,
        expiry: expiry ?? existing.expiry,
      );
    } else {
      _watchlistUniverse[symbol] = Stock(
        symbol: symbol,
        name: displayName.isNotEmpty ? displayName : symbol,
        currentPrice: ltp,
        changePercentage: changePercent,
        sector: '',
        exchange: resolvedExchange,
        token: token,
        instrumentType: instrumentType,
        strikePrice: strikePrice,
        expiry: expiry,
      );
    }
    // No notifyListeners — this is a silent registration
  }

  bool isInWatchlist(String symbol) => _watchlistIndex.containsKey(symbol);

  void addToWatchlist(String symbol) {
    if (isInWatchlist(symbol)) return;
    final stock = _watchlistUniverse[symbol];
    if (stock == null) return;
    _watchlistIndex[stock.symbol] = _watchlist.length;
    _watchlist.add(stock);
    _refreshMarketSubscriptions();
    notifyListeners();
  }

  void removeFromWatchlist(String symbol) {
    _watchlist.removeWhere((stock) => stock.symbol == symbol);
    _rebuildWatchlistIndex();
    _refreshMarketSubscriptions();
    notifyListeners();
  }

  void _rebuildWatchlistIndex() {
    _watchlistIndex.clear();
    for (var i = 0; i < _watchlist.length; i++) {
      _watchlistIndex[_watchlist[i].symbol] = i;
    }
  }

  void setFontSizePreset(String preset) {
    if (_fontSizePreset == preset) return;
    _fontSizePreset = preset;
    switch (preset) {
      case 'Small':
        _textScaleFactor = 0.9;
        break;
      case 'Large':
        _textScaleFactor = 1.12;
        break;
      default:
        _textScaleFactor = 1.0;
        break;
    }
    notifyListeners();
  }

  /// Returns the required margin for an order using admin-configured leverage.
  /// - MIS/MTF BUY:  tradeValue / intradayLeverage
  /// - MIS/MTF SHORT: tradeValue / shortSellLeverage
  /// - NRML BUY:     tradeValue / nrmlBuyLeverage  (default 1x = full value)
  /// - NRML SHORT:   tradeValue / nrmlSellLeverage (default 1x = full value)
  /// - CNC/Overnight: 100% of trade value
  /// - SELL exits:    0 (no margin needed)
  double requiredMargin(
    int quantity,
    double price,
    ProductType product, {
    bool isSell = false,
    bool opensShort = false,
  }) {
    if (isSell && !opensShort) return 0; // Exit orders never require margin
    final fullValue = quantity * price;
    if (product == ProductType.mis || product == ProductType.mtf) {
      final leverage = isSell
          ? _rmsSettings.shortSellLeverage
          : _rmsSettings.intradayLeverage;
      return fullValue / leverage;
    }
    if (product == ProductType.nrml) {
      final leverage = isSell
          ? _rmsSettings.nrmlSellLeverage
          : _rmsSettings.nrmlBuyLeverage;
      return fullValue / leverage;
    }
    return fullValue; // CNC/overnight: full value
  }

  OrderResult placeOrder({
    required String symbol,
    required int quantity,
    required OrderType type,
    OrderVariety variety = OrderVariety.market,
    ProductType product = ProductType.mis,
    OrderValidity validity = OrderValidity.day,
    DateTime? validityDate,
    double price = 0,
    double? triggerPrice,
    int? disclosedQuantity,
    double? targetPrice,
    double? stopLossPrice,
  }) {
    // Validation
    if (quantity <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter a quantity greater than zero.',
      );
    }

    final effectivePrice = price > 0
        ? price
        : stockBySymbol(symbol).currentPrice;

    if (variety == OrderVariety.limit || variety == OrderVariety.sl) {
      if (price < 0) {
        return const OrderResult(
          success: false,
          errorMessage:
              'Limit price cannot be negative. Please enter a valid price.',
        );
      }
    }

    final stock = stockBySymbol(symbol);
    final margin = requiredMargin(quantity, effectivePrice, product);

    if (type == OrderType.buy) {
      if (_balance < margin) {
        return const OrderResult(
          success: false,
          errorMessage:
              'Not enough funds to place this order. Please add funds or reduce your order size.',
        );
      }

      _balance -= margin;
      _applyBuy(stock, quantity);

      // Update positions or holdings based on product type
      if (product == ProductType.mis || product == ProductType.nrml) {
        _applyPositionBuy(stock, quantity, effectivePrice, product, type);
      } else {
        // Overnight or MTF -> holdings (carry-forward delivery)
        _applyHoldingBuy(stock, quantity, effectivePrice);
      }

      _transactions.insert(
        0,
        Transaction(
          id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Margin blocked • BUY ${stock.symbol}',
          amount: margin,
          dateTime: DateTime.now(),
          isDeposit: false,
        ),
      );
    } else {
      // Sell
      final holdingIndex = _portfolio.indexWhere(
        (item) => item.symbol == stock.symbol,
      );
      if (holdingIndex < 0) {
        return const OrderResult(
          success: false,
          errorMessage: 'You don\'t have any holdings of this stock to sell.',
        );
      }

      final holding = _portfolio[holdingIndex];
      if (quantity > holding.totalQuantity) {
        return OrderResult(
          success: false,
          errorMessage:
              'You only have ${holding.totalQuantity} shares available. Please reduce your sell quantity.',
        );
      }

      // RMS FIX Bug #12: Sell must credit FULL PROCEEDS to balance.
      // Old code: _balance += margin (which was 0 for sells — completely wrong).
      // New code: _balance += price × qty (full sell proceeds).
      final sellProceeds = quantity * effectivePrice;
      _balance += sellProceeds;

      _applySell(stock, quantity, holdingIndex);

      // Update positions or holdings based on product type
      if (product == ProductType.mis || product == ProductType.nrml) {
        _applyPositionSell(stock, quantity, effectivePrice, product);
      } else {
        _applyHoldingSell(stock, quantity);
      }

      _transactions.insert(
        0,
        Transaction(
          id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Margin released • SELL ${stock.symbol}',
          amount: sellProceeds,
          dateTime: DateTime.now(),
          isDeposit: true,
        ),
      );
    }

    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final newOrder = Order(
      id: orderId,
      symbol: stock.symbol,
      name: stock.name,
      quantity: quantity,
      price: effectivePrice,
      type: type,
      status: OrderStatus.pending,
      dateTime: DateTime.now(),
      variety: variety,
      product: product,
      validity: validity,
      validityDate: validityDate,
      triggerPrice: triggerPrice,
      disclosedQuantity: disclosedQuantity,
      targetPrice: targetPrice,
      stopLossPrice: stopLossPrice,
    );
    _orders.insert(0, newOrder);
    _ordersVersion.value++;
    notifyListeners();

    return OrderResult(success: true, orderId: orderId);
  }

  OrderResult deposit(double amount) {
    if (amount <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter an amount greater than zero to deposit.',
      );
    }

    _balance += amount;
    _transactions.insert(
      0,
      Transaction(
        id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Funds added',
        amount: amount,
        dateTime: DateTime.now(),
        isDeposit: true,
      ),
    );

    _accountVersion.value++;
    notifyListeners();
    return const OrderResult(success: true, orderId: 'Funds added to wallet.');
  }

  OrderResult withdraw(double amount) {
    if (amount <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter an amount greater than zero to withdraw.',
      );
    }

    if (amount > _balance) {
      return const OrderResult(
        success: false,
        errorMessage: 'Withdrawal amount exceeds your available balance.',
      );
    }

    _balance -= amount;
    _transactions.insert(
      0,
      Transaction(
        id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Withdrawal',
        amount: amount,
        dateTime: DateTime.now(),
        isDeposit: false,
      ),
    );

    _accountVersion.value++;
    notifyListeners();
    return const OrderResult(success: true, orderId: 'Withdrawal successful.');
  }

  // ─── Portfolio (PortfolioItem) helpers ────────────────────────────────────

  void _applyBuy(Stock stock, int quantity) {
    final index = _portfolio.indexWhere((item) => item.symbol == stock.symbol);

    if (index < 0) {
      _portfolio.add(
        PortfolioItem(
          symbol: stock.symbol,
          name: stock.name,
          totalQuantity: quantity,
          avgPrice: stock.currentPrice,
          currentPrice: stock.currentPrice,
        ),
      );
      return;
    }

    final current = _portfolio[index];
    final newQty = current.totalQuantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.totalQuantity) +
            (stock.currentPrice * quantity)) /
        newQty;

    _portfolio[index] = PortfolioItem(
      symbol: current.symbol,
      name: current.name,
      totalQuantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applySell(Stock stock, int quantity, int holdingIndex) {
    final current = _portfolio[holdingIndex];
    final remainingQty = current.totalQuantity - quantity;

    if (remainingQty <= 0) {
      _portfolio.removeAt(holdingIndex);
      return;
    }

    _portfolio[holdingIndex] = PortfolioItem(
      symbol: current.symbol,
      name: current.name,
      totalQuantity: remainingQty,
      avgPrice: current.avgPrice,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Position helpers (MIS / NRML) ────────────────────────────────────────

  void _applyPositionBuy(
    Stock stock,
    int quantity,
    double price,
    ProductType product,
    OrderType side,
  ) {
    final index = _positions.indexWhere(
      (p) => p.symbol == stock.symbol && p.product == product,
    );

    if (index < 0) {
      _positions.add(
        Position(
          symbol: stock.symbol,
          name: stock.name,
          product: product,
          quantity: quantity,
          avgPrice: price,
          currentPrice: stock.currentPrice,
          side: side,
          openedAt: DateTime.now(),
        ),
      );
      return;
    }

    final current = _positions[index];
    final newQty = current.quantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.quantity) + (price * quantity)) / newQty;

    _positions[index] = current.copyWith(
      quantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applyPositionSell(
    Stock stock,
    int quantity,
    double price,
    ProductType product,
  ) {
    final index = _positions.indexWhere(
      (p) => p.symbol == stock.symbol && p.product == product,
    );

    if (index < 0) return;

    final current = _positions[index];
    final remainingQty = current.quantity - quantity;

    if (remainingQty <= 0) {
      _positions.removeAt(index);
      return;
    }

    _positions[index] = current.copyWith(
      quantity: remainingQty,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Holding helpers (CNC / MTF) ──────────────────────────────────────────

  void _applyHoldingBuy(Stock stock, int quantity, double price) {
    final index = _holdings.indexWhere((h) => h.symbol == stock.symbol);

    if (index < 0) {
      _holdings.add(
        Holding(
          symbol: stock.symbol,
          name: stock.name,
          quantity: quantity,
          avgPrice: price,
          currentPrice: stock.currentPrice,
          purchaseDate: DateTime.now(),
        ),
      );
      return;
    }

    final current = _holdings[index];
    final newQty = current.quantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.quantity) + (price * quantity)) / newQty;

    _holdings[index] = current.copyWith(
      quantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applyHoldingSell(Stock stock, int quantity) {
    final index = _holdings.indexWhere((h) => h.symbol == stock.symbol);
    if (index < 0) return;

    final current = _holdings[index];
    final remainingQty = current.quantity - quantity;

    if (remainingQty <= 0) {
      _holdings.removeAt(index);
      return;
    }

    _holdings[index] = current.copyWith(
      quantity: remainingQty,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Position product conversion ─────────────────────────────────────────

  void convertPositionProduct(String symbol, ProductType from, ProductType to) {
    final index = _positions.indexWhere(
      (p) => p.symbol == symbol && p.product == from,
    );
    if (index < 0) return;
    _positions[index] = _positions[index].copyWith(product: to);
    _positionsVersion.value++;
    notifyListeners();
  }

  // ─── Cancel Order ─────────────────────────────────────────────────────────

  void cancelOrder(String orderId) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    if (order.status != OrderStatus.pending) return;
    _orders[index] = order.copyWith(status: OrderStatus.cancelled);
    _ordersVersion.value++;
    notifyListeners();
  }

  // ─── GTT Orders ───────────────────────────────────────────────────────────

  final List<GTTOrder> _gttOrders = [];

  UnmodifiableListView<GTTOrder> get gttOrders =>
      UnmodifiableListView(_gttOrders);

  void createGTTOrder(GTTOrder order) {
    _gttOrders.add(order);
    _ordersVersion.value++;
    notifyListeners();
  }

  void editGTTOrder(String id, GTTOrder updated) {
    final index = _gttOrders.indexWhere((o) => o.id == id);
    if (index >= 0) {
      _gttOrders[index] = updated;
      _ordersVersion.value++;
      notifyListeners();
    }
  }

  void cancelGTTOrder(String id) {
    _gttOrders.removeWhere((o) => o.id == id);
    _ordersVersion.value++;
    notifyListeners();
  }

  // ─── Basket Orders ────────────────────────────────────────────────────────

  final List<BasketOrder> _basketOrders = [];

  UnmodifiableListView<BasketOrder> get basketOrders =>
      UnmodifiableListView(_basketOrders);

  void createBasket(BasketOrder basket) {
    _basketOrders.add(basket);
    _ordersVersion.value++;
    notifyListeners();
  }

  OrderResult executeBasket(String basketId) {
    final index = _basketOrders.indexWhere((b) => b.id == basketId);
    if (index < 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Basket order not found. It may have been removed.',
      );
    }

    final basket = _basketOrders[index];
    for (final entry in basket.entries) {
      final result = placeOrder(
        symbol: entry.symbol,
        quantity: entry.quantity,
        type: entry.type,
        variety: entry.variety,
        product: entry.product,
        price: entry.price ?? 0,
      );
      if (!result.success) {
        return OrderResult(
          success: false,
          errorMessage:
              'Order for ${entry.symbol} failed: ${result.errorMessage}',
        );
      }
    }

    _basketOrders[index] = basket.copyWith(executedAt: DateTime.now());
    _ordersVersion.value++;
    notifyListeners();
    return OrderResult(success: true, orderId: basketId);
  }

  void saveBasket(BasketOrder basket) {
    final index = _basketOrders.indexWhere((b) => b.id == basket.id);
    if (index >= 0) {
      _basketOrders[index] = basket;
    } else {
      _basketOrders.add(basket);
    }
    _ordersVersion.value++;
    notifyListeners();
  }

  // ─── Alerts ───────────────────────────────────────────────────────────────

  final List<Alert> _alerts = [];

  UnmodifiableListView<Alert> get alerts => UnmodifiableListView(_alerts);

  void createAlert(Alert alert) {
    _alerts.add(alert);
    notifyListeners();
  }

  void deleteAlert(String id) {
    _alerts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  final List<AppNotification> _notifications = [];

  // Callbacks wired by main.dart to write mark-read state back to Firestore.
  void Function(String notifId)? _onNotifMarkRead;
  void Function()? _onNotifMarkAllRead;
  void Function()? _onNotifClearAll;

  void setNotificationCallbacks({
    void Function(String notifId)? onMarkRead,
    void Function()? onMarkAllRead,
    void Function()? onClearAll,
  }) {
    _onNotifMarkRead    = onMarkRead;
    _onNotifMarkAllRead = onMarkAllRead;
    _onNotifClearAll    = onClearAll;
  }

  UnmodifiableListView<AppNotification> get notifications =>
      UnmodifiableListView(_notifications);

  int get unreadNotificationCount =>
      _notifications.where((n) => !n.isRead).length;

  /// Replace the full notification list (Firestore snapshot source of truth).
  void replaceNotifications(List<AppNotification> list) {
    _notifications
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  /// Add a single notification (WS real-time delivery). Deduplicates by ID.
  void addNotification(AppNotification notification) {
    if (_notifications.any((n) => n.id == notification.id)) return;
    _notifications.insert(0, notification);
    notifyListeners();
  }

  void markNotificationRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index >= 0) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      notifyListeners();
      _onNotifMarkRead?.call(id);
    }
  }

  void markAllNotificationsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
    _onNotifMarkAllRead?.call();
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
    _onNotifClearAll?.call();
  }

  void addOrUpdateOrder(Order order) {
    final index = _orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      _orders[index] = order;
    } else {
      _orders.insert(0, order);
    }
    _ordersVersion.value++;
    notifyListeners();
  }

  void replaceOrders(List<Order> orders) {
    _orders
      ..clear()
      ..addAll(orders);
    _ordersVersion.value++;
    notifyListeners();
  }

  void _rebuildPositionIndex() {
    _positionIndex.clear();
    _positionTokenIndex.clear();
    for (var i = 0; i < _positions.length; i++) {
      final p = _positions[i];
      _positionIndex
          .putIfAbsent('${p.exchange}:${p.symbol}', () => [])
          .add(i);
      if (p.token.isNotEmpty) {
        _positionTokenIndex.putIfAbsent(p.token, () => []).add(i);
      }
    }
  }

  void _rebuildHoldingIndex() {
    _holdingIndex.clear();
    for (var i = 0; i < _holdings.length; i++) {
      _holdingIndex[_holdings[i].symbol] = i;
    }
  }

  void replacePositions(List<Position> positions) {
    // Preserve live WS prices — Firestore currentPrice may be seconds behind
    // the latest tick. If we have a live price from the WS feed, stamp it onto
    // the incoming position so the screen never shows a stale Firestore value.
    final merged = positions.map((p) {
      final live = _lastLtpBySymbol[p.symbol];
      return (live != null && live > 0) ? p.copyWith(currentPrice: live) : p;
    }).toList();
    _positions
      ..clear()
      ..addAll(merged);
    _rebuildPositionIndex();
    _refreshMarketSubscriptions();
    _positionsVersion.value++;
    notifyListeners();
  }

  void replaceHoldings(List<Holding> holdings) {
    // Same: stamp live WS price so Firestore writes never overwrite tick data.
    final merged = holdings.map((h) {
      final live = _lastLtpBySymbol[h.symbol];
      return (live != null && live > 0) ? h.copyWith(currentPrice: live) : h;
    }).toList();
    _holdings
      ..clear()
      ..addAll(merged);
    _rebuildHoldingIndex();
    _refreshMarketSubscriptions();
    _positionsVersion.value++;
    notifyListeners();
  }

  void replaceGttOrders(List<GTTOrder> gttOrders) {
    _gttOrders
      ..clear()
      ..addAll(gttOrders);
    _ordersVersion.value++;
    notifyListeners();
  }

  // ─── User data readiness ─────────────────────────────────────────────────
  //
  // Tracks whether the first Firestore user-document snapshot has arrived.
  // Until it has, _balance is 0.0 — a stub value, not the real balance.
  // Order forms must not evaluate "insufficient funds" against 0.0.

  bool _isUserDataLoaded = false;

  /// True once the first Firestore user-document snapshot has been applied.
  /// Order forms should gate balance validation behind this flag.
  bool get isUserDataLoaded => _isUserDataLoaded;

  // ─── User update ──────────────────────────────────────────────────────────

  void updateUser(User updated, {bool updateBalance = false}) {
    _currentUser = updated;
    if (updateBalance) {
      _balance = updated.balance;
      _isUserDataLoaded = true; // real balance has arrived
    }
    _accountVersion.value++;
    notifyListeners();
  }

  /// Optimistically update balance after a successful order response.
  /// The Firestore stream will confirm/correct this within ~1 second.
  void setOptimisticBalance(double newBalance) {
    if (_balance == newBalance) return;
    _balance = newBalance;
    _accountVersion.value++;
    notifyListeners();
  }

  // ─── Recent Searches ──────────────────────────────────────────────────────

  final List<String> _recentSearches = [];

  UnmodifiableListView<String> get recentSearches =>
      UnmodifiableListView(_recentSearches);

  void addRecentSearch(String symbol) {
    _recentSearches.remove(symbol);
    _recentSearches.insert(0, symbol);
    if (_recentSearches.length > 10) {
      _recentSearches.removeLast();
    }
    notifyListeners();
  }

  void clearRecentSearches() {
    _recentSearches.clear();
    notifyListeners();
  }
}
