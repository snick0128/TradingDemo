import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/trading_models.dart';
import '../../services/subscription_manager.dart';
import '../../widgets/connection_banner.dart';
import 'backend_api_service.dart';

/// WebSocket-driven live market service.
///
/// Live prices come from backend stream `/ws/market`.
/// REST is used only for initial bootstrap snapshot (no recurring polling).
class LiveMarketService {
  LiveMarketService({required BackendApiService api, this.onError})
    : _api = api;

  final BackendApiService _api;
  final void Function(bool isError, String message)? onError;

  final _stockController        = StreamController<List<Stock>>.broadcast();
  final _moversController       = StreamController<Map<String, List<Stock>>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  // Connection state stream — consumed by ConnectionBannerController
  final _connStateController    = StreamController<WsConnectionStatus>.broadcast();

  final Map<String, Stock> _latestMap = {};
  // Start with all known symbols — MCX commodities included.
  // This set is updated by setSubscribedSymbols() as the user navigates.
  final Set<String> _subscriptions = {
    // NSE Equities
    'RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'ICICIBANK',
    'SBIN', 'WIPRO', 'AXISBANK', 'BAJFINANCE', 'HINDUNILVR',
    // MCX Commodities
    'GOLD', 'SILVER', 'CRUDEOIL', 'NATURALGAS',
    'COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL', 'COTTON',
  };

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _moversDebounce;
  Timer? _tickFlushTimer;
  Timer? _heartbeatTimer;
  Timer? _feedHealthTimer;
  Timer? _snapshotRefreshTimer;
  DateTime? _lastPongTime;
  static const _pingInterval            = Duration(seconds: 10);
  static const _pingTimeout             = Duration(seconds: 20);
  static const _feedHealthInterval      = Duration(seconds: 30);
  static const _feedHealthTimeout       = Duration(seconds: 60);
  static const _snapshotRefreshInterval = Duration(seconds: 30);
  // Reconnect delays: fast first attempts, cap at 10s (not 30s)
  static const _reconnectDelays    = [1, 1, 2, 3, 5, 10];
  int _reconnectAttempt = 0;
  final Map<String, int>    _lastSeqBySymbol          = {};
  final Map<String, double> _lastEmittedLtpBySymbol   = {};
  // Millisecond timestamp of the last tick per symbol — used to reject
  // out-of-order ticks that arrive after a newer one (common on reconnects).
  final Map<String, int>    _lastTickTsBySymbol        = {};
  // Same map tracks feed-health: if a symbol that was recently active goes
  // silent for >_feedHealthTimeout we force a re-subscribe to prod the server.
  final Map<String, int>    _lastTickFeedTsBySymbol    = {};

  // ── Tick trace ──────────────────────────────────────────────────────────────
  // Records per-tick timestamps at each pipeline stage for a configurable set
  // of symbols.  All data stays in-memory; Flutter periodically POSTs it to
  // /debug/tick-trace/client so the backend can produce a merged timeline.
  static const _traceMaxPerStage = 500;
  static const _traceWindowMs    = 120000;
  final Set<String>                            _traceSymbols      = {'CRUDEOIL'};
  final Map<String, List<Map<String, dynamic>>> _traceRx          = {};
  final Map<String, List<Map<String, dynamic>>> _traceRender      = {};
  final Map<String, int>                        _traceRxCounts    = {};
  final Map<String, int>                        _traceRenderCounts = {};

  bool _started = false;
  bool _hasError = false;
  bool get hasError => _hasError;
  bool _disposed = false;

  List<Stock> get latestStocks => _latestMap.values.toList(growable: false);

  Stream<List<Stock>> get stockUpdates => _stockController.stream;
  Stream<Map<String, List<Stock>>> get moversUpdates => _moversController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<WsConnectionStatus> get connectionStateStream => _connStateController.stream;

  String? _registeredUserId;

  Future<void> start() async {
    _started = true;
    SubscriptionManager.instance.attach(this);
    await _bootstrapSnapshot();
    _connectWs();
  }

  void setSubscribedSymbols(Iterable<String> symbols) {
    _subscriptions
      ..clear()
      ..addAll(
        symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty),
      );
    _sendSubscribe();
  }

  void stop() {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _moversDebounce?.cancel();
    _moversDebounce = null;
    _tickFlushTimer?.cancel();
    _tickFlushTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _feedHealthTimer?.cancel();
    _feedHealthTimer = null;
    _snapshotRefreshTimer?.cancel();
    _snapshotRefreshTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    stop();
    if (!_stockController.isClosed)        _stockController.close();
    if (!_moversController.isClosed)       _moversController.close();
    if (!_notificationController.isClosed) _notificationController.close();
    if (!_connStateController.isClosed)    _connStateController.close();
  }

  /// Called when the app returns to the foreground (tab visible / app resumed).
  /// Immediately tears down the existing WebSocket and reconnects without
  /// waiting for the heartbeat timeout. Resets the backoff counter so the
  /// first attempt is instant.
  void reconnectNow() {
    if (!_started || _disposed) return;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectWs();
  }

  /// Register this client's userId with the backend WebSocket so the server
  /// can push per-user notifications in real-time.
  void registerUser(String userId) {
    _registeredUserId = userId;
    _sendUserRegister();
  }

  void _sendUserRegister() {
    final channel = _channel;
    if (channel == null || _registeredUserId == null) return;
    channel.sink.add(jsonEncode({'type': 'register_user', 'userId': _registeredUserId}));
  }

  Future<void> _bootstrapSnapshot() async {
    try {
      final data = await _api.getAllMarketData();
      for (final item in data) {
        final stock = _mapToStock(item);
        if (stock == null) continue;
        // Only seed if no fresher WS tick has already arrived.
        // `start()` calls this before `_connectWs()` so the map is normally
        // empty here, but the guard prevents stale REST data from overwriting
        // a live tick if `start()` is ever called again after the WS is up.
        _latestMap.putIfAbsent(stock.symbol, () => stock);
      }
      _emitStocks();
      _emitMovers();
      _setError(false, '');
    } catch (e) {
      _setError(
        true,
        'Could not load market data. Please check your connection and try again.',
      );
    }
  }

  // Generation counter: each call to _connectWs() gets a unique ID.
  // Stale onError/onDone callbacks captured by a previous generation are
  // no-ops, preventing cascading reconnect loops when a dying connection
  // fires events AFTER a new connection is already set up.
  int _wsGeneration = 0;

  void _connectWs() {
    if (_disposed || !_started) return;

    // Tear down the previous channel/subscription before creating a new one.
    // Without this, the old channel's onDone fires after the new channel is
    // already live, triggering a spurious _onWsError that resets the backoff
    // and starts an infinite reconnect cascade.
    _wsSub?.cancel();
    _wsSub = null;
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;

    _wsGeneration++;
    final int generation = _wsGeneration;

    // Clear stale dedup state so the first tick on reconnect is never silently
    // dropped. Without this, if the price hasn't changed since we disconnected
    // the client would show a stale price until the next price move.
    _lastEmittedLtpBySymbol.clear();
    _lastTickTsBySymbol.clear();

    final wsUrl = _toWsUrl(_api.baseUrl);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (e) {
          if (generation != _wsGeneration) return; // stale — ignore
          _onWsError('Live market feed interrupted. Reconnecting…');
        },
        onDone: () {
          if (generation != _wsGeneration) return; // stale — ignore
          _onWsError('Live market feed disconnected. Reconnecting…');
        },
        cancelOnError: true,
      );
      _sendSubscribe();
      _sendUserRegister();
      _startHeartbeat();
      _startFeedHealthWatchdog();
      _startSnapshotRefresh();
      _setError(false, '');
      _reconnectAttempt = 0;
      _emitConnState(WsConnectionStatus.connected);
    } catch (e) {
      _onWsError('Could not connect to the live market feed. Retrying…');
    }
  }

  /// Sends a ping every [_pingInterval] and reconnects if no pong arrives
  /// within [_pingTimeout]. Catches silent TCP freezes that don't emit a
  /// close/error event (e.g. load-balancer idle-timeout, mobile NAT expiry).
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastPongTime = DateTime.now();
    final int gen = _wsGeneration;
    _heartbeatTimer = Timer.periodic(_pingInterval, (_) {
      if (gen != _wsGeneration) return; // stale timer from old connection
      final channel = _channel;
      if (channel == null || _disposed || !_started) return;
      if (DateTime.now().difference(_lastPongTime!) > _pingTimeout) {
        _onWsError('Market feed heartbeat timeout. Reconnecting…');
        return;
      }
      channel.sink.add(jsonEncode({'type': 'ping'}));
    });
  }

  /// Watches for symbols that were recently active (ticked within the last
  /// _feedHealthTimeout window) but have gone silent. A TCP-level ping/pong
  /// only proves the socket is alive; this proves market data is flowing.
  /// When silence is detected, a re-subscribe is sent to prod the server into
  /// re-fanning ticks for those symbols (handles silent broker-feed stalls).
  void _startFeedHealthWatchdog() {
    _feedHealthTimer?.cancel();
    _feedHealthTimer = Timer.periodic(_feedHealthInterval, (_) {
      if (_disposed || !_started || _channel == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final staleSymbols = <String>[];
      for (final entry in _lastTickFeedTsBySymbol.entries) {
        final age = now - entry.value;
        // Only flag as stale if the symbol WAS active recently (within 5min)
        // but has been silent for >_feedHealthTimeout. Ignores after-hours
        // symbols that never tick during a session.
        if (age > _feedHealthTimeout.inMilliseconds &&
            age < const Duration(minutes: 5).inMilliseconds * 2) {
          staleSymbols.add(entry.key);
        }
      }
      if (staleSymbols.isNotEmpty && _subscriptions.isNotEmpty) {
        _sendSubscribe(); // re-subscribe all — cheapest server-side refresh
      }
    });
  }

  /// Periodically requests a fresh price snapshot from the backend via WS.
  /// Acts as a safety net when ticks slow down or a price-change gap occurred
  /// (e.g. after a silent reconnect). The backend responds with current prices
  /// from liveDataHub so the UI never shows stale values longer than 30s.
  void _startSnapshotRefresh() {
    _snapshotRefreshTimer?.cancel();
    final int gen = _wsGeneration;
    _snapshotRefreshTimer = Timer.periodic(_snapshotRefreshInterval, (_) {
      if (gen != _wsGeneration) return;
      if (_disposed || !_started || _channel == null) return;
      if (_subscriptions.isEmpty) return;
      _channel!.sink.add(jsonEncode({
        'type':    'snapshot',
        'symbols': _subscriptions.toList(growable: false),
      }));
    });
  }

  void _onWsMessage(dynamic message) {
    // Capture receive timestamp before any processing — this is stage "client_rx".
    final clientReceiveTs = DateTime.now().millisecondsSinceEpoch;
    try {
      final m = jsonDecode(message as String) as Map<String, dynamic>;
      final type = m['type']?.toString();
      if (type == 'pong') {
        _lastPongTime = DateTime.now();
        return;
      }
      if (type == 'snapshot') {
        final rows =
            (m['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        for (final row in rows) {
          final stock = _mapToStock(row);
          if (stock != null) _latestMap[stock.symbol] = stock;
        }
        _emitStocks();
        _emitMovers();
        _setError(false, '');
        return;
      }
      if (type == 'tick') {
        final symbol = (m['symbol'] as String? ?? '').toUpperCase();
        // Sequence-number dedup: reject retransmitted or reordered messages.
        // replayed ticks (from gap-fill) have seq > lastSeq so they pass through.
        final seq = (m['seq'] as num?)?.toInt() ?? 0;
        if (symbol.isNotEmpty && seq > 0) {
          final lastSeq = _lastSeqBySymbol[symbol] ?? 0;
          if (seq <= lastSeq) return;
          _lastSeqBySymbol[symbol] = seq;
          // Track seq in SubscriptionManager for next reconnect's lastSeq map
          SubscriptionManager.instance.onTickSeq(symbol, seq);
        }
        // Timestamp dedup: second guard for out-of-order ticks on reconnect
        // bursts where seq numbers reset (server restart) but stale ticks
        // arrive from a buffered WS pipeline.
        final ts = (m['ts'] as num?)?.toInt() ?? 0;
        if (ts > 0 && symbol.isNotEmpty) {
          final lastTs = _lastTickTsBySymbol[symbol] ?? 0;
          if (ts < lastTs) return; // strictly older — drop
          _lastTickTsBySymbol[symbol] = ts;
        }
        final row = m['data'] as Map<String, dynamic>?;
        if (row == null) return;
        // Record received tick for the trace.
        _recordTraceRx(symbol, m, row, clientReceiveTs);
        Stock? stock = _mapToStock(row);
        if (stock == null) return;
        _lastEmittedLtpBySymbol[stock.symbol] = stock.currentPrice;
        // Update feed-health tracking so the watchdog knows this symbol is live.
        _lastTickFeedTsBySymbol[stock.symbol] =
            ts > 0 ? ts : DateTime.now().millisecondsSinceEpoch;
        // Preserve existing depth/OHLC if this tick didn't include depth data
        // (Angel One sends depth only on full-mode ticks, not every heartbeat).
        final existing = _latestMap[stock.symbol];
        if (stock.depth == null && existing?.depth != null) {
          stock = Stock(
            symbol: stock.symbol,
            name: stock.name,
            currentPrice: stock.currentPrice,
            changePercentage: stock.changePercentage,
            sector: stock.sector,
            exchange: stock.exchange,
            token: stock.token,
            open: stock.open,
            high: stock.high,
            low: stock.low,
            prevClose: stock.prevClose,
            week52High: stock.week52High,
            week52Low: stock.week52Low,
            upperCircuit: stock.upperCircuit,
            lowerCircuit: stock.lowerCircuit,
            volume: stock.volume,
            marketCap: stock.marketCap,
            isStale: stock.isStale,
            expiry: stock.expiry,
            instrumentType: stock.instrumentType,
            strikePrice: stock.strikePrice,
            bid: stock.bid ?? existing?.bid,
            ask: stock.ask ?? existing?.ask,
            depth: existing!.depth,
          );
        }
        _latestMap[stock.symbol] = stock;
        _recordTraceRender(stock.symbol, stock.currentPrice);
        _scheduleTick();
        _scheduleMovers();
        _setError(false, '');
        return;
      }
      // Backend signals that the Angel One feed disconnected / is recovering.
      // Flutter shows a degraded-data banner while prices may be delayed.
      if (type == 'feed_status') {
        final degraded = m['degraded'] == true;
        _emitConnState(
          degraded ? WsConnectionStatus.feedDegraded : WsConnectionStatus.connected,
        );
        return;
      }
      if (type == 'notification') {
        final data = m['data'] as Map<String, dynamic>?;
        if (data != null && !_notificationController.isClosed) {
          _notificationController.add(data);
        }
        return;
      }
    } catch (e) {
      _onWsError(
        'Received unexpected data from the market feed. Reconnecting…',
      );
    }
  }

  void _onWsError(String message) {
    _setError(true, message);
    if (!_started || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    _emitConnState(WsConnectionStatus.reconnectingAttempt(_reconnectAttempt));
    final delaySeconds =
        _reconnectDelays[(_reconnectAttempt - 1).clamp(0, _reconnectDelays.length - 1)];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _connectWs);
  }

  void _emitConnState(WsConnectionStatus s) {
    if (!_connStateController.isClosed) _connStateController.add(s);
  }

  void _scheduleTick() {
    _emitStocks();
  }

  void _emitStocks() {
    if (!_stockController.isClosed) {
      _stockController.add(_latestMap.values.toList(growable: false));
    }
  }

  void _emitMovers() {
    final list = _latestMap.values.where((s) => s.currentPrice > 0).toList();
    list.sort((a, b) => b.changePercentage.compareTo(a.changePercentage));
    final gainers = list.take(5).toList();
    final losers = list.reversed.take(5).toList().reversed.toList();
    if (!_moversController.isClosed) {
      _moversController.add({'gainers': gainers, 'losers': losers});
    }
  }

  void _scheduleMovers() {
    _moversDebounce ??= Timer(const Duration(seconds: 5), () {
      _moversDebounce = null;
      _emitMovers();
    });
  }

  // ── Dedicated candle subscriptions (chart screens) ───────────────────────────

  /// Tell the backend to send 500 ms-resolution candle updates for [symbol]
  /// and the given [intervals] (e.g. `['5m']`). Call from the chart screen's
  /// `initState` after connecting; call [unsubscribeCandleStream] on dispose.
  void subscribeCandleStream(String symbol, List<String> intervals) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({
      'type':      'subscribe_candles',
      'symbol':    symbol.toUpperCase(),
      'intervals': intervals,
    }));
  }

  /// Release the dedicated chart subscription for [symbol].
  /// Call when the chart screen closes to free backend resources.
  void unsubscribeCandleStream(String symbol) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({
      'type':   'unsubscribe_candles',
      'symbol': symbol.toUpperCase(),
    }));
  }

  void _sendSubscribe() {
    final channel = _channel;
    if (channel == null) return;
    if (_subscriptions.isEmpty) return;
    // Include lastSeq map so the server can replay ticks missed during disconnect
    final lastSeq = SubscriptionManager.instance.lastSeqMap;
    final payload = jsonEncode({
      'type':    'subscribe',
      'symbols': _subscriptions.toList(growable: false),
      if (lastSeq.isNotEmpty) 'lastSeq': lastSeq,
    });
    channel.sink.add(payload);
  }

  void _setError(bool isError, String message) {
    if (_hasError == isError && message.isEmpty) return;
    _hasError = isError;
    onError?.call(isError, message);
  }

  String _toWsUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws/market').toString();
  }

  static Stock? _mapToStock(Map<String, dynamic> d) {
    final symbol = d['symbol'] as String?;
    if (symbol == null || symbol.isEmpty) return null;

    // ltp can be null for symbols not yet ticked — skip those
    final ltpRaw = d['ltp'];
    final ltp = ltpRaw is num ? ltpRaw.toDouble() : null;
    if (ltp == null || ltp <= 0) return null;

    final stale = d['stale'] == true;

    // Backend sends 'changePercent' (not 'changePercentage')
    final changePercent =
        (d['changePercent'] as num?)?.toDouble() ??
        (d['changePercentage'] as num?)?.toDouble() ??
        0.0;

    final prevClose = (d['prevClose'] as num?)?.toDouble();
    final volume = (d['volume'] as num?)?.toDouble();

    // exchange is always present now — backend enriches every payload
    final exchange = (d['exchange'] as String?)?.toUpperCase() ?? 'NSE';

    // token is needed for MCX/NFO historical data and quote lookups
    final token = (d['token'] as String?) ?? '';

    // expiry is sent as ISO-8601 string for futures contracts, null for equities
    DateTime? expiry;
    final expiryRaw = d['expiry'];
    if (expiryRaw is String && expiryRaw.isNotEmpty) {
      expiry = DateTime.tryParse(expiryRaw);
    }

    final bid = (d['bid'] as num?)?.toDouble();
    final ask = (d['ask'] as num?)?.toDouble();

    // Parse top-5 market depth levels when present in the tick payload.
    // The backend includes depthBids/depthAsks only when Angel One provides them,
    // so callers should preserve the previous depth when this returns null.
    MarketDepth? depth;
    final rawBids = d['depthBids'];
    final rawAsks = d['depthAsks'];
    if (rawBids is List && rawAsks is List) {
      MarketDepthLevel _parseLevel(dynamic l) {
        final m = l as Map<String, dynamic>;
        return MarketDepthLevel(
          price: (m['price'] as num?)?.toDouble() ?? 0,
          quantity: (m['quantity'] as num?)?.toInt() ?? 0,
          orders: (m['orders'] as num?)?.toInt() ?? 0,
        );
      }
      depth = MarketDepth(
        symbol: symbol,
        bids: rawBids.map(_parseLevel).toList(),
        asks: rawAsks.map(_parseLevel).toList(),
        timestamp: DateTime.now(),
      );
    }

    return Stock(
      symbol: symbol,
      name: _names[symbol] ?? symbol,
      currentPrice: ltp,
      changePercentage: changePercent,
      sector: _sectors[symbol] ?? _sectorForExchange(exchange),
      exchange: exchange,
      token: token,
      prevClose: prevClose,
      volume: volume,
      isStale: stale,
      expiry: expiry,
      bid: bid,
      ask: ask,
      depth: depth,
    );
  }

  /// Returns a sensible default sector label based on exchange.
  static String _sectorForExchange(String exchange) {
    switch (exchange) {
      case 'MCX':
        return 'Commodity';
      case 'NFO':
        return 'F&O';
      case 'CDS':
        return 'Currency';
      case 'BFO':
        return 'F&O';
      case 'NCDEX':
        return 'Commodity';
      default:
        return 'Equity';
    }
  }

  static const _names = {
    // NSE Equities
    'RELIANCE': 'Reliance Industries',
    'TCS': 'Tata Consultancy Services',
    'INFY': 'Infosys',
    'HDFCBANK': 'HDFC Bank',
    'ICICIBANK': 'ICICI Bank',
    'SBIN': 'State Bank of India',
    'WIPRO': 'Wipro Limited',
    'AXISBANK': 'Axis Bank',
    'BAJFINANCE': 'Bajaj Finance',
    'HINDUNILVR': 'Hindustan Unilever',
    // MCX Commodities
    'GOLD': 'Gold Futures',
    'SILVER': 'Silver Futures',
    'CRUDEOIL': 'Crude Oil Futures',
    'NATURALGAS': 'Natural Gas Futures',
    'COPPER': 'Copper Futures',
    'ZINC': 'Zinc Futures',
    'LEAD': 'Lead Futures',
    'ALUMINIUM': 'Aluminium Futures',
    'NICKEL': 'Nickel Futures',
    'COTTON': 'Cotton Futures',
  };

  static const _sectors = {
    // NSE Equities
    'RELIANCE': 'Energy',
    'TCS': 'IT',
    'INFY': 'IT',
    'HDFCBANK': 'Banking',
    'ICICIBANK': 'Banking',
    'SBIN': 'Banking',
    'WIPRO': 'IT',
    'AXISBANK': 'Banking',
    'BAJFINANCE': 'Finance',
    'HINDUNILVR': 'FMCG',
    // MCX Commodities
    'GOLD': 'Commodity',
    'SILVER': 'Commodity',
    'CRUDEOIL': 'Commodity',
    'NATURALGAS': 'Commodity',
    'COPPER': 'Commodity',
    'ZINC': 'Commodity',
    'LEAD': 'Commodity',
    'ALUMINIUM': 'Commodity',
    'NICKEL': 'Commodity',
    'COTTON': 'Commodity',
  };

  // ── Tick trace helpers ──────────────────────────────────────────────────────

  void _recordTraceRx(
    String symbol,
    Map<String, dynamic> m,
    Map<String, dynamic> data,
    int clientReceiveTs,
  ) {
    if (!_traceSymbols.contains(symbol)) return;
    final list = _traceRx.putIfAbsent(symbol, () => []);
    _traceRxCounts[symbol] = (_traceRxCounts[symbol] ?? 0) + 1;
    final cutoff = clientReceiveTs - _traceWindowMs;
    while (list.isNotEmpty && (list.first['clientReceiveTs'] as int) < cutoff) {
      list.removeAt(0);
    }
    if (list.length >= _traceMaxPerStage) list.removeAt(0);
    list.add({
      'exchangeTs':      data['exchangeTs'],
      'serverTs':        data['serverTs'],
      'broadcastTs':     m['ts'],
      'clientReceiveTs': clientReceiveTs,
      'ltp':             data['ltp'],
      'token':           data['token'] ?? '',
      'exchange':        data['exchange'] ?? '',
      'expiry':          data['expiry'],
    });
  }

  void _recordTraceRender(String symbol, double ltp) {
    if (!_traceSymbols.contains(symbol)) return;
    final list = _traceRender.putIfAbsent(symbol, () => []);
    _traceRenderCounts[symbol] = (_traceRenderCounts[symbol] ?? 0) + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _traceWindowMs;
    while (list.isNotEmpty && (list.first['clientRenderedTs'] as int) < cutoff) {
      list.removeAt(0);
    }
    if (list.length >= _traceMaxPerStage) list.removeAt(0);
    list.add({'ltp': ltp, 'clientRenderedTs': now});
  }

  // ── Public trace API ────────────────────────────────────────────────────────

  /// Returns the local (Flutter-side) trace data for [symbol].
  Map<String, dynamic> getLocalTrace(String symbol) {
    final sym = symbol.toUpperCase();
    return {
      'symbol': sym,
      'rx':     List<Map<String, dynamic>>.from(_traceRx[sym] ?? []),
      'render': List<Map<String, dynamic>>.from(_traceRender[sym] ?? []),
      'counts': {
        'rxTotal':       _traceRxCounts[sym]     ?? 0,
        'renderedTotal': _traceRenderCounts[sym] ?? 0,
      },
    };
  }

  /// POST Flutter's trace data to the backend so it can build the merged timeline.
  Future<void> reportTrace(String symbol) async {
    try {
      final sym  = symbol.toUpperCase();
      final data = getLocalTrace(sym);
      await _api.postJson('/debug/tick-trace/client?symbol=$sym', data);
    } catch (_) {}
  }

  /// Configure which symbols are actively traced (default: CRUDEOIL only).
  void setTraceSymbols(Set<String> symbols) {
    _traceSymbols
      ..clear()
      ..addAll(symbols.map((s) => s.toUpperCase()));
  }

  Set<String> get traceSymbols => Set.unmodifiable(_traceSymbols);

  /// One-shot: POST Flutter trace to backend, then GET the merged timeline.
  Future<Map<String, dynamic>> fetchTrace(String symbol,
      {int windowMs = 60000}) async {
    final sym = symbol.toUpperCase();
    await reportTrace(sym);
    return _api.getJson('/debug/tick-trace?symbol=$sym&windowMs=$windowMs');
  }
}
