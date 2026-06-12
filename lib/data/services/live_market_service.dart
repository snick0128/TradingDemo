import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
  bool _isBackground = false;
  int? _appResumeTimestamp;
  Timer? _reconnectTimer;
  Timer? _moversDebounce;
  Timer? _tickFlushTimer;
  Timer? _heartbeatTimer;
  Timer? _feedHealthTimer;
  Timer? _snapshotRefreshTimer;
  Timer? _traceUploadTimer;
  Timer? _clockSyncTimer;
  Timer? _deviceReportTimer;

  // ── Tick-batch state ──────────────────────────────────────────────────────
  // Symbols that received a tick since the last 16 ms flush. A Set ensures
  // rapid-fire ticks for the same symbol within one frame are deduplicated.
  final Set<String> _pendingSymbols = {};

  // ── Batch diagnostics (raw counters, reset every second) ─────────────────
  int _diagMessagesReceived = 0; // WS tick messages received
  int _diagBatchesSent      = 0; // flush calls that actually emitted
  int _diagSymbolsTotal     = 0; // sum of symbols across all flushed batches
  Timer? _diagTimer;
  // Snapshots updated by the diagnostics timer — safe to read from any widget.
  double _diagMessagesPerSec  = 0.0;
  double _diagBatchesPerSec   = 0.0;
  double _diagSymbolsPerBatch = 0.0;

  // NTP-style clock offset: clientClock − serverClock (ms).
  // Positive = client is ahead; negative = client is behind.
  double _clockOffsetMs = 0.0;
  final List<double> _clockOffsetHistory = []; // last 20 samples
  double get clockOffsetMs => _clockOffsetMs;
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

  // ── Device-registry: sequence gap tracking ──────────────────────────────────
  // Unique stable device ID — generated once per session (or reused from memory).
  late final String _deviceId;
  // symbol → list of gap records {expected, received, at}
  final Map<String, List<Map<String, dynamic>>> _seqGaps = {};
  // symbol → last 200 {seq, ltp} entries for cross-device LTP comparison
  final Map<String, Map<int, double>>           _seqLtpMap = {};
  // Total ticks received per symbol since session start
  final Map<String, int> _totalReceived = {};
  // Total seq gaps detected per symbol
  final Map<String, int> _totalDropped  = {};
  static const _maxSeqGapsPerSymbol = 50;
  static const _maxSeqLtpEntries    = 200;

  // ── Tick trace ──────────────────────────────────────────────────────────────
  // Records per-tick timestamps at each pipeline stage for a configurable set
  // of symbols.  All data stays in-memory; Flutter periodically POSTs it to
  // /debug/tick-trace/client so the backend can produce a merged timeline.
  static const _traceMaxPerStage    = 200;   // in-memory cap; cleared on each successful upload
  static const _traceWindowMs       = 600000;
  static const _traceUploadMaxEntries = 150; // max entries per symbol per upload cycle (~41 KB/symbol)
  final Set<String> _traceSymbols = {
    'CRUDEOIL', 'NIFTY', 'BANKNIFTY', 'GOLD', 'SILVER',
    'RELIANCE', 'TCS', 'INFY',
  };
  final Map<String, List<Map<String, dynamic>>> _traceRx          = {};
  final Map<String, List<Map<String, dynamic>>> _traceRender      = {};
  final Map<String, int>                        _traceRxCounts    = {};
  final Map<String, int>                        _traceRenderCounts = {};

  // Last F&O token subscription — re-sent on every reconnect so CE/PE prices
  // resume automatically after background → foreground or any WS restart.
  List<String> _fnoTokens  = [];
  String       _fnoExchange = 'NFO';

  bool _started = false;
  bool _hasError = false;
  bool get hasError => _hasError;
  bool _disposed = false;

  List<Stock> get latestStocks => _latestMap.values.toList(growable: false);

  /// Per-second throughput metrics for the tick-batch pipeline.
  /// Updated every 1 s by an internal timer; safe to read from any widget.
  Map<String, dynamic> get tickBatchDiagnostics => {
    'messagesReceivedPerSecond': _diagMessagesPerSec,
    'batchesSentPerSecond':      _diagBatchesPerSec,
    'symbolsPerBatch':           _diagSymbolsPerBatch,
  };

  Stream<List<Stock>> get stockUpdates => _stockController.stream;
  Stream<Map<String, List<Stock>>> get moversUpdates => _moversController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<WsConnectionStatus> get connectionStateStream => _connStateController.stream;

  String? _registeredUserId;

  Future<void> start() async {
    _started = true;
    _deviceId = _generateDeviceId();
    SubscriptionManager.instance.attach(this);
    // Ensure every traced symbol is also subscribed to the WS feed.
    // Without this, symbols in _traceSymbols but not in _subscriptions
    // never receive ticks and produce zero trace data.
    for (final sym in _traceSymbols) {
      _subscriptions.add(sym);
    }
    await _bootstrapSnapshot();
    _connectWs();
    // Measure clock offset immediately, then re-measure every 5 minutes.
    // The initial measurement runs after a short delay so the WS is connected.
    Future.delayed(const Duration(seconds: 3), () {
      if (_started && !_disposed) measureClockOffset();
    });
    _clockSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!_started || _disposed) return;
      measureClockOffset();
    });
    // Auto-upload Flutter trace data every 60 s so the backend always has
    // fresh telemetry without requiring manual UI interaction.
    debugPrint('[Trace] starting upload timer (60s interval), traceSymbols: ${_traceSymbols.toList()}');
    _traceUploadTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_started || _disposed) return;
      debugPrint('[Trace] upload timer fired');
      _uploadAllTraces();
    });
    // Upload sequence-gap reports every 60 s for cross-device comparison.
    _deviceReportTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_started || _disposed) return;
      _uploadDeviceReports();
      _uploadRebuildMetrics();
    });
    // Diagnostics: snapshot per-second rates and reset raw counters.
    _diagTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _diagMessagesPerSec  = _diagMessagesReceived.toDouble();
      _diagBatchesPerSec   = _diagBatchesSent.toDouble();
      _diagSymbolsPerBatch = _diagBatchesSent > 0
          ? _diagSymbolsTotal / _diagBatchesSent
          : 0.0;
      _diagMessagesReceived = 0;
      _diagBatchesSent      = 0;
      _diagSymbolsTotal     = 0;
    });
  }

  Future<void> _uploadAllTraces() async {
    debugPrint('[Trace] _uploadAllTraces started — symbols: ${_traceSymbols.toList()}');
    int uploaded = 0;
    for (final sym in List<String>.from(_traceSymbols)) {
      final rxFull     = _traceRx[sym];
      final renderFull = _traceRender[sym];
      final rxLen     = rxFull?.length ?? 0;
      final renderLen = renderFull?.length ?? 0;
      if (rxLen == 0) {
        debugPrint('[Trace] $sym skipped — rx=0 render=$renderLen');
        continue;
      }

      // Slice newest entries only. Strips 6 unused rx fields to reduce payload:
      // only backend-consumed fields: broadcastTs, clientReceiveTs, storeEntryTs,
      // ltpNotifierTs, storeExitTs, ltp. Saves ~125 bytes per rx entry.
      final rxStart = (rxLen - _traceUploadMaxEntries).clamp(0, rxLen);
      final rxSlice = rxFull!
          .sublist(rxStart)
          .map((e) => <String, dynamic>{
                'broadcastTs':     e['broadcastTs'],
                'clientReceiveTs': e['clientReceiveTs'],
                'storeEntryTs':    e['storeEntryTs'],
                'ltpNotifierTs':   e['ltpNotifierTs'],
                'storeExitTs':     e['storeExitTs'],
                'ltp':             e['ltp'],
              })
          .toList();

      final renderStart = renderFull == null
          ? 0
          : (renderLen - _traceUploadMaxEntries).clamp(0, renderLen);
      final renderSlice = renderFull == null
          ? <Map<String, dynamic>>[]
          : renderFull.sublist(renderStart);

      final body = <String, dynamic>{
        'symbol': sym,
        'rx':     rxSlice,
        'render': renderSlice,
        'counts': {
          'rxTotal':       _traceRxCounts[sym]     ?? 0,
          'renderedTotal': _traceRenderCounts[sym] ?? 0,
        },
        'clockOffsetMs': _clockOffsetMs,
      };

      final payloadBytes = jsonEncode(body).length;
      final url = '/debug/tick-trace/client?symbol=$sym';
      debugPrint('[Trace] $sym rx=${rxSlice.length}/${rxLen} render=${renderSlice.length}/${renderLen} ~${payloadBytes}B → POST $url');

      try {
        final resp = await _api.postJson(url, body);
        debugPrint('[Trace] $sym upload OK — ${resp['rxMerged']}rx ${resp['renderMerged']}render merged');
        // Clear buffers so next cycle sends only new ticks — prevents re-uploading
        // the same entries and keeps payloads small even if backend was slow.
        _traceRx[sym]?.clear();
        _traceRender[sym]?.clear();
        uploaded++;
      } on BackendException catch (e) {
        debugPrint('[Trace] $sym upload FAILED BackendException: ${e.message} (HTTP ${e.statusCode})');
      } catch (e) {
        debugPrint('[Trace] $sym upload FAILED unexpected: $e');
      }
    }
    debugPrint('[Trace] _uploadAllTraces done — $uploaded/${_traceSymbols.length} uploaded');
  }

  /// NTP-style clock offset measurement.
  /// Sends 5 sequential requests to /debug/clock-sync, computes
  /// offset = (t_send + t_receive) / 2 - serverTs for each,
  /// then takes the median to filter outliers.
  /// Sets _clockOffsetMs (positive = client ahead of server).
  Future<void> measureClockOffset() async {
    const probes = 5;
    final samples = <double>[];
    debugPrint('[ClockSync] measuring clock offset ($probes probes)');
    for (int i = 0; i < probes; i++) {
      try {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        // Append unique ?t= to bypass BackendApiService in-memory GET cache.
        // Without this, probes 2-5 return the same cached serverTs, corrupting the median.
        final resp = await _api.getJson('/debug/clock-sync?t=$t1');
        final t4 = DateTime.now().millisecondsSinceEpoch;
        final serverTs = (resp['serverTs'] as num?)?.toInt();
        if (serverTs == null) {
          debugPrint('[ClockSync] probe $i — serverTs missing in response: $resp');
          continue;
        }
        final rtt = t4 - t1;
        final offset = ((t1 + t4) / 2.0) - serverTs;
        debugPrint('[ClockSync] probe $i — rtt=${rtt}ms offset=${offset.toStringAsFixed(1)}ms');
        samples.add(offset);
      } catch (e) {
        debugPrint('[ClockSync] probe $i failed: $e');
      }
      if (i < probes - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    if (samples.isEmpty) {
      debugPrint('[ClockSync] all probes failed — clock offset unchanged');
      return;
    }
    final sorted = List<double>.from(samples)..sort();
    _clockOffsetMs = sorted[sorted.length ~/ 2]; // median
    _clockOffsetHistory.addAll(samples);
    if (_clockOffsetHistory.length > 20) {
      _clockOffsetHistory.removeRange(0, _clockOffsetHistory.length - 20);
    }
    debugPrint('[ClockSync] complete — median offset=${_clockOffsetMs.toStringAsFixed(1)}ms (${samples.length} samples)');
  }

  /// Returns clock offset statistics across all measured samples.
  Map<String, dynamic> getClockOffsetStats() {
    if (_clockOffsetHistory.isEmpty) {
      return {'count': 0, 'current': _clockOffsetMs};
    }
    final sorted = List<double>.from(_clockOffsetHistory)..sort();
    final avg = sorted.reduce((a, b) => a + b) / sorted.length;
    int pct(double p) {
      final idx = (p / 100 * sorted.length).ceil() - 1;
      return sorted[idx.clamp(0, sorted.length - 1)].round();
    }
    return {
      'count':   sorted.length,
      'current': _clockOffsetMs.round(),
      'avg':     avg.round(),
      'p50':     pct(50),
      'p95':     pct(95),
      'max':     sorted.last.round(),
      'min':     sorted.first.round(),
      'interpretation': _clockOffsetMs > 0
          ? 'client is ${_clockOffsetMs.abs().round()}ms AHEAD of server'
          : 'client is ${_clockOffsetMs.abs().round()}ms BEHIND server',
      'note': 'bcastToClientRxCorrected = raw - clockOffset. Positive offset inflates raw measurement.',
    };
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
    _pendingSymbols.clear();
    _diagTimer?.cancel();
    _diagTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _feedHealthTimer?.cancel();
    _feedHealthTimer = null;
    _snapshotRefreshTimer?.cancel();
    _snapshotRefreshTimer = null;
    _traceUploadTimer?.cancel();
    _traceUploadTimer = null;
    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
    _deviceReportTimer?.cancel();
    _deviceReportTimer = null;
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

  void setIsBackground(bool isBg) {
    _isBackground = isBg;
    debugPrint('[LiveMarketService] setIsBackground($isBg)');
  }

  void setAppResumeTimestamp(int ts) {
    _appResumeTimestamp = ts;
    debugPrint('[LiveMarketService] setAppResumeTimestamp($ts)');
  }

  void disconnectWsOnly() {
    debugPrint('[LiveMarketService] disconnectWsOnly()');
    _wsSub?.cancel();
    _wsSub = null;
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _emitConnState(WsConnectionStatus.reconnectingAttempt(0));
  }

  void clearTickProcessingState() {
    debugPrint('[LiveMarketService] clearTickProcessingState()');
    _lastSeqBySymbol.clear();
    _lastEmittedLtpBySymbol.clear();
    _lastTickTsBySymbol.clear();
    _lastTickFeedTsBySymbol.clear();
    _seqGaps.clear();
    _seqLtpMap.clear();
    _totalReceived.clear();
    _totalDropped.clear();
    _traceRx.clear();
    _traceRender.clear();
    _traceRxCounts.clear();
    _traceRenderCounts.clear();
  }

  Future<void> fetchFreshSnapshot() async {
    debugPrint('[LiveMarketService] fetchFreshSnapshot()');
    await _bootstrapSnapshot();
  }

  void reconnectWsOnly() {
    debugPrint('[LiveMarketService] reconnectWsOnly()');
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
        // Replace stale prices immediately
        _latestMap[stock.symbol] = stock;
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
      _sendFnoSubscribe(); // re-subscribe F&O option tokens after every reconnect
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
    if (_isBackground) {
      // Ignore ticks received while app was in background
      return;
    }
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
        // Reject ticks if they were generated before the app was resumed.
        final ts = (m['ts'] as num?)?.toInt() ?? 0;
        if (_appResumeTimestamp != null && ts > 0 && ts < _appResumeTimestamp!) {
          debugPrint('[LiveMarketService] Rejecting background/stale tick for $symbol (ts=$ts < resume=$_appResumeTimestamp)');
          return;
        }
        // Sequence-number dedup: reject retransmitted or reordered messages.
        // replayed ticks (from gap-fill) have seq > lastSeq so they pass through.
        final seq = (m['seq'] as num?)?.toInt() ?? 0;
        if (symbol.isNotEmpty && seq > 0) {
          final lastSeq = _lastSeqBySymbol[symbol] ?? 0;
          if (seq <= lastSeq) return;
          // Sequence gap detection: record if we skipped one or more seq numbers.
          if (lastSeq > 0 && seq > lastSeq + 1) {
            final gaps = _seqGaps.putIfAbsent(symbol, () => []);
            if (gaps.length >= _maxSeqGapsPerSymbol) gaps.removeAt(0);
            gaps.add({
              'expected': lastSeq + 1,
              'received': seq,
              'at':       DateTime.now().millisecondsSinceEpoch,
            });
            _totalDropped[symbol] = (_totalDropped[symbol] ?? 0) + (seq - lastSeq - 1);
          }
          _totalReceived[symbol] = (_totalReceived[symbol] ?? 0) + 1;
          _lastSeqBySymbol[symbol] = seq;
          // Track seq in SubscriptionManager for next reconnect's lastSeq map
          SubscriptionManager.instance.onTickSeq(symbol, seq);
        }
        // Record seq→ltp for cross-device LTP comparison at the backend.
        if (symbol.isNotEmpty && seq > 0) {
          final row2 = m['data'] as Map<String, dynamic>?;
          final ltpForSeq = (row2?['ltp'] as num?)?.toDouble();
          if (ltpForSeq != null && ltpForSeq > 0) {
            final seqMap = _seqLtpMap.putIfAbsent(symbol, () => {});
            seqMap[seq] = ltpForSeq;
            // Keep only the most recent _maxSeqLtpEntries entries
            if (seqMap.length > _maxSeqLtpEntries) {
              final oldest = seqMap.keys.reduce(math.min);
              seqMap.remove(oldest);
            }
          }
        }

        // Timestamp dedup: second guard for out-of-order ticks on reconnect
        // bursts where seq numbers reset (server restart) but stale ticks
        // arrive from a buffered WS pipeline.
        final tickTs = (m['ts'] as num?)?.toInt() ?? 0;
        if (tickTs > 0 && symbol.isNotEmpty) {
          final lastTs = _lastTickTsBySymbol[symbol] ?? 0;
          if (tickTs < lastTs) return; // strictly older — drop
          _lastTickTsBySymbol[symbol] = tickTs;
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
        _scheduleTick(stock.symbol);
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

  // Mark [symbol] as changed and arm the 16 ms batch timer.
  // The null-guard ensures at most one timer is live at any moment; rapid-fire
  // ticks for the same symbol within one frame are deduplicated by the Set.
  void _scheduleTick(String symbol) {
    _pendingSymbols.add(symbol);
    _diagMessagesReceived++;
    _tickFlushTimer ??= Timer(const Duration(milliseconds: 16), _flushBatch);
  }

  // Emit only the stocks that changed since the last flush.
  // Called by _tickFlushTimer — fires at most once per 16 ms frame.
  void _flushBatch() {
    _tickFlushTimer = null;
    if (_pendingSymbols.isEmpty || _stockController.isClosed) {
      _pendingSymbols.clear();
      return;
    }
    final changed = <Stock>[];
    for (final symbol in _pendingSymbols) {
      final s = _latestMap[symbol];
      if (s != null) changed.add(s);
    }
    _pendingSymbols.clear();
    if (changed.isEmpty) return;
    _diagBatchesSent++;
    _diagSymbolsTotal += changed.length;
    _stockController.add(changed);
  }

  // Full-snapshot emit — used by bootstrap and WS snapshot messages.
  // NOT called on individual ticks; those go through _scheduleTick/_flushBatch.
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

  /// Tell the backend to subscribe the given option token IDs to Angel One's
  /// WebSocket and forward their ticks to this client. The payload is persisted
  /// so it can be re-sent automatically after every reconnect.
  void subscribeFnoTokens(List<String> tokens, String exchange) {
    if (tokens.isEmpty) return;
    _fnoTokens  = List.unmodifiable(tokens);
    _fnoExchange = exchange.toUpperCase();
    _sendFnoSubscribe();
  }

  /// Clear the persisted F&O token list so it is not re-sent on the next
  /// reconnect. Called by SubscriptionManager when the user navigates away
  /// from any screen that uses F&O subscriptions.
  void clearFnoTokens() {
    _fnoTokens  = const [];
    _fnoExchange = 'NFO';
  }

  void _sendFnoSubscribe() {
    final channel = _channel;
    if (channel == null || _fnoTokens.isEmpty) return;
    channel.sink.add(jsonEncode({
      'type':     'subscribe_fno',
      'tokens':   _fnoTokens,
      'exchange': _fnoExchange,
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
    // Log first tick received for each traced symbol so we know ticks are flowing.
    if (list.isEmpty) {
      debugPrint('[Trace] first tick received for $symbol ltp=${data['ltp']}');
    }
    _traceRxCounts[symbol] = (_traceRxCounts[symbol] ?? 0) + 1;
    final cutoff = clientReceiveTs - _traceWindowMs;
    while (list.isNotEmpty && (list.first['clientReceiveTs'] as int) < cutoff) {
      list.removeAt(0);
    }
    if (list.length >= _traceMaxPerStage) list.removeAt(0);
    list.add({
      'exchangeTs':       data['exchangeTs'],
      'serverTs':         data['serverTs'],
      'broadcastTs':      m['ts'],
      'backendReceiveTs': data['backendReceiveTs'],
      'clientReceiveTs':  clientReceiveTs,
      'ltp':              data['ltp'],
      'token':            data['token'] ?? '',
      'exchange':         data['exchange'] ?? '',
      'expiry':           data['expiry'],
      // store-side timestamps patched later by TradingStore
      'storeEntryTs':   null,
      'ltpNotifierTs':  null,
      'storeExitTs':    null,
    });
  }

  // Called by TradingStore after it processes the tick and sets ltpNotifier.
  void patchLastStoreTrace(String symbol, double ltp, {
    required int storeEntryTs,
    required int ltpNotifierTs,
    required int storeExitTs,
  }) {
    if (!_traceSymbols.contains(symbol)) return;
    final list = _traceRx[symbol];
    if (list == null || list.isEmpty) return;
    for (int i = list.length - 1; i >= 0; i--) {
      if (list[i]['ltp'] == ltp && list[i]['storeEntryTs'] == null) {
        list[i] = Map<String, dynamic>.from(list[i])
          ..['storeEntryTs']  = storeEntryTs
          ..['ltpNotifierTs'] = ltpNotifierTs
          ..['storeExitTs']   = storeExitTs;
        break;
      }
    }
  }

  void _recordTraceRender(String symbol, double ltp) {
    if (!_traceSymbols.contains(symbol)) return;
    final list = _traceRender.putIfAbsent(symbol, () => []);
    _traceRenderCounts[symbol] = (_traceRenderCounts[symbol] ?? 0) + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _traceWindowMs;
    while (list.isNotEmpty && (list.first['clientRenderedTs'] as int? ?? 0) < cutoff) {
      list.removeAt(0);
    }
    if (list.length >= _traceMaxPerStage) list.removeAt(0);
    list.add({'ltp': ltp, 'clientRenderedTs': now});
  }

  // Called by TradingStore via addPostFrameCallback — records true render completion time.
  // storeExitTs: timestamp captured at end of _onLiveStockUpdate loop iteration.
  // renderTs: addPostFrameCallback timestamp = first frame drawn after the tick.
  void recordRenderCompletion(String symbol, double ltp, int renderTs, int storeExitTs) {
    if (!_traceSymbols.contains(symbol)) return;
    final list = _traceRender.putIfAbsent(symbol, () => []);
    for (int i = list.length - 1; i >= 0; i--) {
      if (list[i]['ltp'] == ltp && list[i]['renderTs'] == null) {
        list[i] = Map<String, dynamic>.from(list[i])
          ..['renderTs']    = renderTs
          ..['storeExitTs'] = storeExitTs;
        return;
      }
    }
    // No unpatched matching entry — add a new one
    if (list.length >= _traceMaxPerStage) list.removeAt(0);
    list.add({
      'ltp':          ltp,
      'clientRenderedTs': renderTs,
      'renderTs':     renderTs,
      'storeExitTs':  storeExitTs,
    });
  }

  // ── Device registry helpers ─────────────────────────────────────────────────

  /// Generates a stable random device ID for this browser session.
  /// In a real app this would persist to localStorage; here we generate once
  /// per LiveMarketService instance (stable within a page session).
  String _generateDeviceId() {
    final rand = math.Random();
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return 'dev_' + List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Upload per-symbol gap reports to /debug/devices/report for all traced
  /// symbols that have seen at least one tick.
  Future<void> _uploadDeviceReports() async {
    // Compute render P50/P95 from local trace render buffers
    for (final sym in List<String>.from(_traceSymbols)) {
      final received = _totalReceived[sym] ?? 0;
      if (received == 0) continue;

      // Render lag samples (renderTs − clientReceiveTs)
      final rxList     = _traceRx[sym] ?? [];
      final renderList = _traceRender[sym] ?? [];
      final renderLags = <int>[];
      for (final r in renderList) {
        final rTs  = (r['renderTs'] as num?)?.toInt() ?? 0;
        final rxTs = (rxList.isNotEmpty
            ? rxList.lastWhere(
                (e) => e['ltp'] == r['ltp'],
                orElse: () => {},
              )['clientReceiveTs']
            : null);
        if (rTs > 0 && rxTs is int && rxTs > 0) renderLags.add(rTs - rxTs);
      }
      renderLags.sort();
      int? renderP50, renderP95;
      if (renderLags.isNotEmpty) {
        renderP50 = renderLags[(renderLags.length * 0.50).floor().clamp(0, renderLags.length - 1)];
        renderP95 = renderLags[(renderLags.length * 0.95).floor().clamp(0, renderLags.length - 1)];
      }

      final seqMapForSym = _seqLtpMap[sym] ?? {};
      final gapsForSym   = _seqGaps[sym] ?? [];

      final body = <String, dynamic>{
        'deviceId':      _deviceId,
        'symbol':        sym,
        'seqMap':        seqMapForSym.map((k, v) => MapEntry(k.toString(), v)),
        'gaps':          List<Map<String, dynamic>>.from(gapsForSym),
        'lastSeq':       _lastSeqBySymbol[sym] ?? 0,
        'totalReceived': received,
        'totalDropped':  _totalDropped[sym] ?? 0,
        'clockOffsetMs': _clockOffsetMs,
        if (renderP50 != null) 'renderP50': renderP50,
        if (renderP95 != null) 'renderP95': renderP95,
        'reportedAt':    DateTime.now().millisecondsSinceEpoch,
      };

      try {
        await _api.postJson('/debug/devices/report', body);
        debugPrint('[DeviceReg] $sym report sent — gaps=${gapsForSym.length} dropped=${_totalDropped[sym] ?? 0}');
      } catch (e) {
        debugPrint('[DeviceReg] $sym report failed: $e');
      }
    }
  }

  /// Uploads the widget rebuild heatmap from [RebuildMetrics] to the backend.
  /// Only runs in debug builds (RebuildMetrics.instance.snapshot() returns empty
  /// counts in release mode because the assert() calls that populate it are
  /// compiled out). Safe to call unconditionally.
  Future<void> _uploadRebuildMetrics() async {
    // Import is in options_chain_screen.dart — access via a static interface.
    // We use a separate callback to avoid a circular import.
    final fn = _rebuildMetricsSnapshot;
    if (fn == null) return;
    try {
      final snap = fn();
      if ((snap['counts'] as Map?)?.isEmpty ?? true) return;
      await _api.postJson('/debug/flutter-rebuilds', {
        'deviceId': _deviceId,
        ...snap,
      });
      debugPrint('[RebuildMetrics] uploaded: ${snap['counts']}');
    } catch (e) {
      debugPrint('[RebuildMetrics] upload failed: $e');
    }
  }

  /// Set by the app shell after the options chain screen is wired up.
  /// Avoids a circular import: options_chain_screen imports live_market_service
  /// but live_market_service should not import options_chain_screen.
  static Map<String, dynamic> Function()? _rebuildMetricsSnapshot;
  static void setRebuildMetricsProvider(Map<String, dynamic> Function() fn) {
    _rebuildMetricsSnapshot = fn;
  }

  bool isTraced(String symbol) => _traceSymbols.contains(symbol.toUpperCase());

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

  /// Configure which symbols are actively traced.
  /// Also adds them to the WS subscription set so ticks actually arrive.
  void setTraceSymbols(Set<String> symbols) {
    _traceSymbols
      ..clear()
      ..addAll(symbols.map((s) => s.toUpperCase()));
    // Bridge: every traced symbol must also be subscribed so ticks arrive.
    for (final sym in _traceSymbols) {
      _subscriptions.add(sym);
    }
    _sendSubscribe();
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
