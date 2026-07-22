import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../debug/crudeoil_tick_tracer.dart';
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
  // Subscription set is managed exclusively by SubscriptionManager.
  // Start empty — SubscriptionManager.replaceScreenSubscriptions() populates
  // this after the first _refreshMarketSubscriptions() call in TradingStore.
  final Set<String> _subscriptions = {};

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  bool _isBackground = false;
  int? _appResumeTimestamp;
  // Auto-clears _appResumeTimestamp after this duration so permanent clock-skew
  // cannot block live ticks indefinitely (see setAppResumeTimestamp).
  Timer? _resumeGateTimer;
  static const int _resumeGateDurationMs = 15000;

  // ── Tick filter counters ──────────────────────────────────────────────────
  // Accumulated since last _filterStatsTimer report. Not reset by clearTickProcessingState
  // (lifecycle resets) — these are session-level totals for observability.
  int _acceptedTicks           = 0;
  int _staleRejectedTicks      = 0;
  int _backgroundRejectedTicks = 0;
  int _sequenceRejectedTicks   = 0;
  int _timestampRejectedTicks  = 0;
  Timer? _filterStatsTimer;

  Timer? _reconnectTimer;
  Timer? _moversDebounce;
  Timer? _tickFlushTimer;
  Timer? _heartbeatTimer;
  Timer? _feedHealthTimer;
  Timer? _snapshotRefreshTimer;
  Timer? _traceUploadTimer;
  Timer? _clockSyncTimer;
  Timer? _deviceReportTimer;

  // ── Tick-batch state ─────────────────────────────────────────────────────
  // Previously used for 16ms batching. Now unused — ticks are emitted immediately.
  final Set<String> _pendingSymbols = {}; // kept for diagnostics reset in clearTickProcessingState

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
  // Symbols with replay in progress (first replay tick received → 'replay_complete').
  // Cleared on every WS reconnect. Used to log [LIVE_DURING_REPLAY] and to
  // prevent stale replay ticks from rolling back a live price already applied.
  final Set<String> _activeReplaySymbols = {};

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
    'activeWebSocketListeners':  _wsSub == null ? 0 : 1,
    'activeTimers':              _activeTimerCount,
    'subscribedSymbols':         _subscriptions.length,
    // Tick filter stats (accumulated since last 30s report window)
    'acceptedTicks':             _acceptedTicks,
    'staleRejectedTicks':        _staleRejectedTicks,
    'backgroundRejectedTicks':   _backgroundRejectedTicks,
    'sequenceRejectedTicks':     _sequenceRejectedTicks,
    'timestampRejectedTicks':    _timestampRejectedTicks,
    'clockOffsetMs':             _clockOffsetMs,
    'resumeGateActive':          _appResumeTimestamp != null,
  };

  int get _activeTimerCount => [
    _reconnectTimer,
    _moversDebounce,
    _tickFlushTimer,
    _heartbeatTimer,
    _feedHealthTimer,
    _snapshotRefreshTimer,
    _traceUploadTimer,
    _clockSyncTimer,
    _deviceReportTimer,
    _diagTimer,
    _resumeGateTimer,
    _filterStatsTimer,
  ].where((timer) => timer?.isActive ?? false).length;

  Set<String> get subscribedSymbolsForDiagnostics =>
      Set.unmodifiable(_subscriptions);

  /// Current F&O tokens in the persisted subscription — for diagnostics only.
  List<String> get fnoTokensForDiagnostics => List.unmodifiable(_fnoTokens);

  Stream<List<Stock>> get stockUpdates => _stockController.stream;
  Stream<Map<String, List<Stock>>> get moversUpdates => _moversController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<WsConnectionStatus> get connectionStateStream => _connStateController.stream;

  String? _registeredUserId;

  Future<void> start() async {
    _started = true;
    _deviceId = _generateDeviceId();
    SubscriptionManager.instance.attach(this);
    // _traceSymbols are NOT injected into _subscriptions here — SubscriptionManager
    // is the sole owner of that set. Trace symbols receive ticks only when
    // SubscriptionManager independently subscribes them (e.g., user watchlist includes NIFTY).
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
    // Tick filter stats: log cumulative counters every 30 s then reset.
    _filterStatsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_started || _disposed) return;
      final total = _acceptedTicks + _staleRejectedTicks +
          _backgroundRejectedTicks + _sequenceRejectedTicks +
          _timestampRejectedTicks;
      debugPrint(
        '[TICK_FILTER_STATS] '
        'accepted=$_acceptedTicks '
        'staleRejected=$_staleRejectedTicks '
        'backgroundRejected=$_backgroundRejectedTicks '
        'sequenceRejected=$_sequenceRejectedTicks '
        'timestampRejected=$_timestampRejectedTicks '
        'total=$total '
        'clockOffset=${_clockOffsetMs.toStringAsFixed(1)}ms '
        'resumeGateActive=${_appResumeTimestamp != null}',
      );
      _acceptedTicks           = 0;
      _staleRejectedTicks      = 0;
      _backgroundRejectedTicks = 0;
      _sequenceRejectedTicks   = 0;
      _timestampRejectedTicks  = 0;
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
    final newSet = symbols
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    // [WS_UNSUBSCRIBE] — symbols being dropped from the active WS subscription.
    final removed = _subscriptions.difference(newSet);
    if (removed.isNotEmpty) {
      final buf = StringBuffer('[WS_UNSUBSCRIBE]\n');
      buf.writeln('count=${removed.length}');
      buf.writeln('symbols=[');
      for (final s in removed.toList()..sort()) buf.writeln('  $s,');
      buf.writeln(']');
      debugPrint(buf.toString());
    }

    _subscriptions
      ..clear()
      ..addAll(newSet);
    _sendSubscribe(source: 'manual');
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
    _filterStatsTimer?.cancel();
    _filterStatsTimer = null;
    _resumeGateTimer?.cancel();
    _resumeGateTimer = null;
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
    debugPrint('[RESUME_GATE] resumeTs=$ts clockOffset=${_clockOffsetMs.toStringAsFixed(1)}ms');
    // Auto-clear the gate after _resumeGateDurationMs so a persistent clock skew
    // between backend and client cannot block live ticks indefinitely.
    // The closure captures [ts] so a subsequent resume cannot clear a newer gate.
    _resumeGateTimer?.cancel();
    _resumeGateTimer = Timer(
      Duration(milliseconds: _resumeGateDurationMs),
      () {
        if (_appResumeTimestamp == ts) {
          _appResumeTimestamp = null;
          debugPrint('[RESUME_GATE_CLEARED] gateTs=$ts expiredAfter=${_resumeGateDurationMs}ms');
        }
      },
    );
  }

  void disconnectWsOnly() {
    debugPrint(
      '[WS_DISCONNECTED] reason=app_background '
      'subscriptions=${_subscriptions.length}',
    );
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
    _activeReplaySymbols.clear();
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
    debugPrint(
      '[WS_RECONNECTED] reason=app_resume '
      'subscriptions=${_subscriptions.length}',
    );
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
    debugPrint('[WS_CREATED] source=LiveMarketService generation=$_wsGeneration '
        'url=$wsUrl managedSubscriptions=${_subscriptions.length}');
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
      _sendSubscribe(source: generation > 1 ? 'reconnect' : 'connect');
      _sendFnoSubscribe(); // re-subscribe F&O option tokens after every reconnect
      // Re-subscribe chart candle streams that were active before disconnect.
      _activeCandleSubscriptions.forEach(_sendCandleSubscribe);
      _sendUserRegister();
      _startHeartbeat();
      _startFeedHealthWatchdog();
      _startSnapshotRefresh();
      _setError(false, '');
      _reconnectAttempt = 0;
      debugPrint(
        '[${generation > 1 ? "WS_RECONNECTED" : "WS_CONNECTED"}] '
        'generation=$generation subscriptions=${_subscriptions.length}',
      );
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
      debugPrint('[HEARTBEAT_SENT] gen=$gen ts=${DateTime.now().millisecondsSinceEpoch}');
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
        // Log per-symbol so we can correlate with tick traces.
        for (final sym in staleSymbols) {
          final lastAge = now - (_lastTickFeedTsBySymbol[sym] ?? 0);
          debugPrint(
            '[WATCHDOG_FIRE] symbol=$sym '
            'lastTickAgeMs=$lastAge '
            'lastSeq=${_lastSeqBySymbol[sym] ?? 0} '
            'connectionGeneration=$_wsGeneration',
          );
        }
        // Request a fresh HTTP snapshot — do NOT call _sendSubscribe or
        // reconnectWsOnly. Either would include a lastSeq map that triggers
        // server-side replay, creating a watchdog → replay → watchdog loop.
        fetchFreshSnapshot();
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
      _backgroundRejectedTicks++;
      return;
    }
    // Capture receive timestamp before any processing — this is stage "client_rx".
    final clientReceiveTs = DateTime.now().millisecondsSinceEpoch;
    try {
      final m = jsonDecode(message as String) as Map<String, dynamic>;
      final type = m['type']?.toString();
      if (type == 'pong') {
        _lastPongTime = DateTime.now();
        debugPrint('[HEARTBEAT_RECEIVED] ts=${_lastPongTime!.millisecondsSinceEpoch}');
        return;
      }
      if (type == 'snapshot') {
        // Use the snapshot envelope timestamp as the freshness reference.
        // The backend sets ts=Date.now() at the moment the snapshot is serialised,
        // which is comparable to the broadcastEntryTs stored in _lastTickTsBySymbol.
        final snapshotTs = (m['ts'] as num?)?.toInt() ?? 0;
        final rows =
            (m['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        int accepted = 0;
        int skipped  = 0;
        for (final row in rows) {
          final stock = _mapToStock(row);
          if (stock == null) continue;
          final sym = stock.symbol;
          // Guard: reject snapshot rows that are older than (or same-age as) the
          // last live tick we accepted for this symbol. Without this, the 30-second
          // periodic snapshot refresh silently overwrites a newer live-tick price,
          // producing a price rollback that persists until the next real tick.
          // Only apply when snapshotTs is non-zero AND we already have a tick for
          // this symbol — on the first snapshot after reconnect _lastTickTsBySymbol
          // is empty, so all rows are accepted regardless.
          if (snapshotTs > 0) {
            final lastTs = _lastTickTsBySymbol[sym] ?? 0;
            if (lastTs > 0 && snapshotTs <= lastTs) {
              skipped++;
              continue;
            }
            // Record snapshot timestamp so future ticks with ts<=snapshotTs are
            // also rejected (prevents replay ticks sent between snapshot request
            // and snapshot response from being double-applied).
            _lastTickTsBySymbol[sym] = snapshotTs;
          }
          // Phase 2: log when a stale snapshot price overwrites _latestMap.
          // stale=true means liveDataHub has not received a fresh Angel One tick
          // for > 5 s — the price being applied may be wrong.
          if (stock.isStale) {
            debugPrint(
              '[TICK_STALE_ACCEPTED] symbol=$sym snapshotTs=$snapshotTs '
              'ltp=${stock.currentPrice} source=snapshot gen=$_wsGeneration',
            );
          }
          _latestMap[sym] = stock;
          accepted++;
        }
        if (skipped > 0) {
          debugPrint(
            '[SNAPSHOT_STALE] snapshotTs=$snapshotTs '
            'accepted=$accepted skipped=$skipped — stale rows not applied',
          );
        }
        _emitStocks();
        _emitMovers();
        _setError(false, '');
        return;
      }
      if (type == 'tick') {
        final symbol = (m['symbol'] as String? ?? '').toUpperCase();
        // Resume gate: reject ticks broadcast before the app was resumed.
        // IMPORTANT: correct for server-client clock skew before comparing.
        // _clockOffsetMs > 0 means client is ahead of server by that many ms.
        // Adjusting ts by +_clockOffsetMs maps the backend timestamp into
        // the client's clock domain before comparing against _appResumeTimestamp.
        final ts = (m['ts'] as num?)?.toInt() ?? 0;
        // Replay ticks are explicitly requested gap-fills (server responded to our
        // lastSeq map on reconnect). They are NOT accidental WS-buffer residuals.
        // They bypass the resume gate and both timestamp guards because:
        //   • Their outer ts is the ORIGINAL broadcast time (intentionally old).
        //   • Their exchangeTs is historical and will always precede live ticks.
        // Live-tick freshness cursors (_lastTickTsBySymbol, _monoExchangeTs) are
        // updated ONLY by live ticks to prevent replay from contaminating them.
        final bool _isReplayedTick = m['replayed'] == true;
        if (!_isReplayedTick && _appResumeTimestamp != null && ts > 0) {
          final adjustedTs = ts + _clockOffsetMs.round();
          final isStale = adjustedTs < _appResumeTimestamp!;
          if (isStale) {
            _staleRejectedTicks++;
            return;
          }
        }
        // ── GUARD 1: sequence dedup (validation only — no state mutation yet) ──────
        // Seq advancement is deliberately deferred to AFTER all timestamp guards.
        // Advancing seq before a timestamp rejection was the root cause of the
        // replay-stream corruption bug (seqAdvancedBeforeRejection=true in logs).
        final seq = (m['seq'] as num?)?.toInt() ?? 0;
        // _seqAdvancedForThisTick is set true only once all guards pass and seq
        // state is committed.  In any rejection path it stays false — the
        // [TICK_SEQ_ROLLBACK_GUARD] diagnostic fires if that invariant breaks.
        bool _seqAdvancedForThisTick = false;
        if (symbol.isNotEmpty && seq > 0) {
          final lastSeq = _lastSeqBySymbol[symbol] ?? 0;
          if (seq <= lastSeq) {
            // Server-restart detection: if seq resets to near 1 while we hold a
            // large lastSeq, the backend restarted and its symbolTickSeq map was
            // zeroed. Reset our tracking so new ticks are accepted instead of
            // being silently dropped until the next app-level reconnect.
            // This removal is safe even if the tick is later rejected by a
            // timestamp guard — future ticks will start fresh from a clean slate.
            if (seq <= 5 && lastSeq > 50) {
              debugPrint(
                '[SEQ_RESET_DETECTED] symbol=$symbol lastSeq=$lastSeq newSeq=$seq '
                '— backend restart assumed, resetting sequence tracking',
              );
              _lastSeqBySymbol.remove(symbol);
              // fall through — continue to timestamp guards
            } else {
              // Temporary diagnostic: replay ticks should only be rejected here
              // (seq dedup). If this fires post-fix, the server is replaying an
              // already-processed seq — normal and expected on double-reconnect.
              if (_isReplayedTick) {
                debugPrint(
                  '[REPLAY_REJECTED] symbol=$symbol seq=$seq '
                  'reason=seq_dedup lastSeq=$lastSeq gen=$_wsGeneration',
                );
              }
              _sequenceRejectedTicks++;
              return;
            }
          }
          // Gap detection is recorded only after all guards pass (see below).
        }

        // ── GUARD 2: broadcast-timestamp dedup (live ticks only) ──────────────────
        // Rejects stale live ticks from a buffered WS pipeline after a reconnect.
        // Replay ticks bypass entirely: ts is their original broadcast time, which
        // is always older than the live ticks received post-reconnect.
        // _lastTickTsBySymbol is updated ONLY here (live path) so replay cannot
        // corrupt the freshness cursor used to filter future live ticks.
        if (!_isReplayedTick && ts > 0 && symbol.isNotEmpty) {
          final lastTs = _lastTickTsBySymbol[symbol] ?? 0;
          if (ts < lastTs) {
            _timestampRejectedTicks++;
            final _rejRow = m['data'] as Map<String, dynamic>?;
            final _rejLtp = (_rejRow?['ltp'] as num?)?.toDouble() ?? 0.0;
            final _rejEts = (_rejRow?['exchangeTs'] as num?)?.toInt() ?? 0;
            // Regression guard: seq must NOT have been advanced before this rejection.
            if (_seqAdvancedForThisTick) {
              debugPrint(
                '[TICK_SEQ_ROLLBACK_GUARD] symbol=$symbol seq=$seq '
                'guard=broadcastTs — seq was advanced before rejection (bug!)',
              );
              assert(false, 'TICK_SEQ_ROLLBACK_GUARD: seq advanced before ts rejection');
            }
            debugPrint(
              '[TICK_TS_REJECTED] symbol=$symbol seq=$seq '
              'tickTs=$ts lastTs=$lastTs diff=${lastTs - ts}ms '
              'ltp=$_rejLtp isReplayed=false '
              'seqAdvancedBeforeRejection=$_seqAdvancedForThisTick '
              'gen=$_wsGeneration',
            );
            CrudeoilTickTracer.instance.checkCorruption(
              symbol: symbol,
              ltp: _rejLtp,
              exchangeTs: _rejEts,
              seq: seq,
              clientReceiveTs: clientReceiveTs,
              accepted: false,
              isReplayed: false,
              seqAdvancedBeforeRejection: _seqAdvancedForThisTick,
            );
            if (symbol == 'CRUDEOIL') {
              CrudeoilTickTracer.instance.record(TickRecord(
                tickId:                    CrudeoilTickTracer.instance.nextId,
                symbol:                    symbol,
                ltp:                       _rejLtp,
                seq:                       seq,
                exchangeTs:                _rejEts,
                brokerTs:                  ts,
                backendReceiveTs:
                    (_rejRow?['backendReceiveTs'] as num?)?.toInt() ?? 0,
                hubEntryTs:
                    (_rejRow?['hubEntryTs'] as num?)?.toInt() ?? 0,
                hubExitTs:
                    (_rejRow?['hubExitTs'] as num?)?.toInt() ?? 0,
                broadcastTs:               ts,
                clientReceiveTs:           clientReceiveTs,
                storeEntryTs:              0,
                storeExitTs:               0,
                paintTs:                   0,
                connectionId:              'gen_$_wsGeneration',
                source:                    'live',
                wasRejected:               true,
                rejectionReason:           'ts',
                isReplayed:                false,
                seqAdvancedBeforeRejection: _seqAdvancedForThisTick,
              ));
            }
            return; // strictly older — drop
          }
          _lastTickTsBySymbol[symbol] = ts;
        }

        // ── GUARD 3: monotonic exchangeTs guard (live ticks only) ─────────────────
        // Rejects live ticks whose Angel One exchange timestamp went backward.
        // Replay ticks bypass entirely: their exchangeTs is historical and will
        // always precede live ticks accepted after reconnect.
        // _monoExchangeTs is updated ONLY by checkMonotonicExchangeTs on the live
        // path so replay cannot corrupt the monotonic baseline.
        if (!_isReplayedTick) {
          final _p5Row = m['data'] as Map<String, dynamic>?;
          final _p5Ets = (_p5Row?['exchangeTs'] as num?)?.toInt() ?? 0;
          if (symbol.isNotEmpty && _p5Ets > 0) {
            final _monoOk =
                CrudeoilTickTracer.instance.checkMonotonicExchangeTs(symbol, _p5Ets);
            if (!_monoOk) {
              _timestampRejectedTicks++;
              final _rejLtp2 = (_p5Row?['ltp'] as num?)?.toDouble() ?? 0.0;
              // Regression guard: seq must NOT have been advanced before this rejection.
              if (_seqAdvancedForThisTick) {
                debugPrint(
                  '[TICK_SEQ_ROLLBACK_GUARD] symbol=$symbol seq=$seq '
                  'guard=exchangeTs_mono — seq was advanced before rejection (bug!)',
                );
                assert(false, 'TICK_SEQ_ROLLBACK_GUARD: seq advanced before exchangeTs rejection');
              }
              if (symbol == 'CRUDEOIL') {
                CrudeoilTickTracer.instance.record(TickRecord(
                  tickId:                    CrudeoilTickTracer.instance.nextId,
                  symbol:                    symbol,
                  ltp:                       _rejLtp2,
                  seq:                       seq,
                  exchangeTs:                _p5Ets,
                  brokerTs:                  ts,
                  backendReceiveTs:
                      (_p5Row?['backendReceiveTs'] as num?)?.toInt() ?? 0,
                  hubEntryTs:
                      (_p5Row?['hubEntryTs'] as num?)?.toInt() ?? 0,
                  hubExitTs:
                      (_p5Row?['hubExitTs'] as num?)?.toInt() ?? 0,
                  broadcastTs:               ts,
                  clientReceiveTs:           clientReceiveTs,
                  storeEntryTs:              0,
                  storeExitTs:               0,
                  paintTs:                   0,
                  connectionId:              'gen_$_wsGeneration',
                  source:                    'live',
                  wasRejected:               true,
                  rejectionReason:           'exchangeTs_mono',
                  isReplayed:                false,
                  seqAdvancedBeforeRejection: _seqAdvancedForThisTick,
                ));
              }
              return; // exchangeTs regression — drop
            }
          }
        }

        // ── ALL GUARDS PASSED — commit sequence state ─────────────────────────────
        // Sequence advancement and gap recording happen here, AFTER every validation
        // guard, so that a rejected tick never inflates _lastSeqBySymbol or the
        // SubscriptionManager's replay cursor.
        if (symbol.isNotEmpty && seq > 0) {
          final lastSeqNow = _lastSeqBySymbol[symbol] ?? 0;
          // Gap detection: record skipped seq numbers now that this tick is accepted.
          if (lastSeqNow > 0 && seq > lastSeqNow + 1) {
            final gaps = _seqGaps.putIfAbsent(symbol, () => []);
            if (gaps.length >= _maxSeqGapsPerSymbol) gaps.removeAt(0);
            gaps.add({
              'expected': lastSeqNow + 1,
              'received': seq,
              'at':       DateTime.now().millisecondsSinceEpoch,
            });
            _totalDropped[symbol] = (_totalDropped[symbol] ?? 0) + (seq - lastSeqNow - 1);
          }
          _totalReceived[symbol] = (_totalReceived[symbol] ?? 0) + 1;
          _lastSeqBySymbol[symbol] = seq;
          // Track seq in SubscriptionManager for next reconnect's lastSeq map.
          // This is now safe: the tick is fully accepted before the cursor advances.
          SubscriptionManager.instance.onTickSeq(symbol, seq);
          _seqAdvancedForThisTick = true;
          // Record seq→ltp for cross-device LTP comparison at the backend.
          final _seqRow = m['data'] as Map<String, dynamic>?;
          final _ltpForSeq = (_seqRow?['ltp'] as num?)?.toDouble();
          if (_ltpForSeq != null && _ltpForSeq > 0) {
            final seqMap = _seqLtpMap.putIfAbsent(symbol, () => {});
            seqMap[seq] = _ltpForSeq;
            if (seqMap.length > _maxSeqLtpEntries) {
              final oldest = seqMap.keys.reduce(math.min);
              seqMap.remove(oldest);
            }
          }
        }
        // Track replay activity for [LIVE_DURING_REPLAY] and stale-price guard.
        if (_isReplayedTick) {
          _activeReplaySymbols.add(symbol);
        } else if (_activeReplaySymbols.contains(symbol)) {
          debugPrint(
            '[LIVE_DURING_REPLAY] symbol=$symbol liveSeq=$seq gen=$_wsGeneration',
          );
        }
        final row = m['data'] as Map<String, dynamic>?;
        if (row == null) return;
        // Record received tick for the trace.
        _recordTraceRx(symbol, m, row, clientReceiveTs);
        Stock? stock = _mapToStock(row);
        if (stock == null) return;
        // Guard: if this replay tick's original broadcast time is older than the
        // most-recent live tick already applied for this symbol, skip the price
        // update entirely. The seq cursor was advanced above so the gap is recorded.
        // This prevents a replay burst from rolling back a live price in the UI.
        if (_isReplayedTick && ts > 0 && ts < (_lastTickTsBySymbol[symbol] ?? 0)) {
          return;
        }
        _lastEmittedLtpBySymbol[stock.symbol] = stock.currentPrice;
        // Update feed-health tracking so the watchdog knows this symbol is live.
        // Replay ticks carry their original broadcast ts (20-30s old). Using that
        // old ts would make the watchdog see the symbol as still-stale and fire
        // again 35s later, creating a replay loop. Always use wall-clock now.
        _lastTickFeedTsBySymbol[stock.symbol] = DateTime.now().millisecondsSinceEpoch;
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
        final _storeEntryTs = DateTime.now().millisecondsSinceEpoch;
        _latestMap[stock.symbol] = stock;
        final _storeExitTs = DateTime.now().millisecondsSinceEpoch;
        _recordTraceRender(stock.symbol, stock.currentPrice);
        _acceptedTicks++;
        // Temporary diagnostic: confirm replay ticks reach the apply stage.
        if (_isReplayedTick) {
          debugPrint(
            '[REPLAY_ACCEPTED] symbol=$symbol seq=$seq '
            'ltp=${stock.currentPrice} gen=$_wsGeneration',
          );
        }
        _emitTickImmediate(stock);
        final _paintTs = DateTime.now().millisecondsSinceEpoch;
        // Phase 1: record accepted tick in the CRUDEOIL tracer.
        if (stock.symbol == 'CRUDEOIL') {
          final _accRow    = m['data'] as Map<String, dynamic>?;
          final _accEts    = (_accRow?['exchangeTs'] as num?)?.toInt() ?? 0;
          final _accBrTs   = (m['ts'] as num?)?.toInt() ?? 0;
          final _accBrRts  = (_accRow?['backendReceiveTs'] as num?)?.toInt() ?? 0;
          final _accHubIn  = (_accRow?['hubEntryTs'] as num?)?.toInt() ?? 0;
          final _accHubOut = (_accRow?['hubExitTs'] as num?)?.toInt() ?? 0;
          final _isReplayed = m['replayed'] == true;
          CrudeoilTickTracer.instance.checkCorruption(
            symbol:                    stock.symbol,
            ltp:                       stock.currentPrice,
            exchangeTs:                _accEts,
            seq:                       seq,
            clientReceiveTs:           clientReceiveTs,
            accepted:                  true,
            isReplayed:                _isReplayed,
            seqAdvancedBeforeRejection: false,
          );
          CrudeoilTickTracer.instance.record(TickRecord(
            tickId:                    CrudeoilTickTracer.instance.nextId,
            symbol:                    stock.symbol,
            ltp:                       stock.currentPrice,
            seq:                       seq,
            exchangeTs:                _accEts,
            brokerTs:                  _accBrTs,
            backendReceiveTs:          _accBrRts,
            hubEntryTs:                _accHubIn,
            hubExitTs:                 _accHubOut,
            broadcastTs:               _accBrTs,
            clientReceiveTs:           clientReceiveTs,
            storeEntryTs:              _storeEntryTs,
            storeExitTs:               _storeExitTs,
            paintTs:                   _paintTs,
            connectionId:              'gen_$_wsGeneration',
            source:                    _isReplayed ? 'replay' : 'live',
            wasRejected:               false,
            rejectionReason:           '',
            isReplayed:                _isReplayed,
            seqAdvancedBeforeRejection: false,
          ));
        }
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
      if (type == 'replay_complete') {
        final sym = m['symbol']?.toString();
        if (sym != null && sym.isNotEmpty) {
          _activeReplaySymbols.remove(sym.toUpperCase());
        } else {
          _activeReplaySymbols.clear();
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
    debugPrint(
      '[WS_DISCONNECTED] reason="$message" generation=$_wsGeneration '
      'subscriptions=${_subscriptions.length}',
    );
    _setError(true, message);
    if (!_started || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    _emitConnState(WsConnectionStatus.reconnectingAttempt(_reconnectAttempt));
    final delaySeconds =
        _reconnectDelays[(_reconnectAttempt - 1).clamp(0, _reconnectDelays.length - 1)];
    final jitterMs = math.Random().nextInt(1000); // 0–999 ms jitter to prevent thundering herd
    _reconnectTimer = Timer(
      Duration(milliseconds: delaySeconds * 1000 + jitterMs),
      _connectWs,
    );
  }

  void _emitConnState(WsConnectionStatus s) {
    if (!_connStateController.isClosed) _connStateController.add(s);
  }

  // Emit [stock] immediately to subscribers — no batching, no timer.
  // Each tick is pushed to the stream as soon as it arrives from the WebSocket.
  void _emitTickImmediate(Stock stock) {
    if (_stockController.isClosed) return;
    _diagMessagesReceived++;
    _diagBatchesSent++;
    _diagSymbolsTotal++;
    _stockController.add([stock]);
  }

  // Full-snapshot emit — used by bootstrap and WS snapshot messages.
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

  // Persisted candle subscriptions — re-sent automatically after every reconnect.
  final Map<String, List<String>> _activeCandleSubscriptions = {};

  /// Tell the backend to send 500 ms-resolution candle updates for [symbol]
  /// and the given [intervals] (e.g. `['5m']`). Call from the chart screen's
  /// `initState` after connecting; call [unsubscribeCandleStream] on dispose.
  void subscribeCandleStream(String symbol, List<String> intervals) {
    final sym = symbol.toUpperCase();
    _activeCandleSubscriptions[sym] = List.unmodifiable(intervals);
    _sendCandleSubscribe(sym, intervals);
  }

  void _sendCandleSubscribe(String symbol, List<String> intervals) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({
      'type':      'subscribe_candles',
      'symbol':    symbol,
      'intervals': intervals,
    }));
  }

  /// Release the dedicated chart subscription for [symbol].
  /// Call when the chart screen closes to free backend resources.
  void unsubscribeCandleStream(String symbol) {
    final sym = symbol.toUpperCase();
    _activeCandleSubscriptions.remove(sym);
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({
      'type':   'unsubscribe_candles',
      'symbol': sym,
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

    // [WS_SUBSCRIBE_FNO] — F&O token subscription payload sent to backend.
    final buf = StringBuffer('[WS_SUBSCRIBE_FNO]\n');
    buf.writeln('count=${_fnoTokens.length}');
    buf.writeln('exchange=$_fnoExchange');
    buf.writeln('tokens=[');
    for (final t in _fnoTokens) buf.writeln('  $t,');
    buf.writeln(']');
    debugPrint(buf.toString());

    debugPrint('[SUB_SOURCE] class=LiveMarketService method=_sendFnoSubscribe '
        'generation=$_wsGeneration tokenCount=${_fnoTokens.length} exchange=$_fnoExchange');
    channel.sink.add(jsonEncode({
      'type':     'subscribe_fno',
      'tokens':   _fnoTokens,
      'exchange': _fnoExchange,
    }));
  }

  void _sendSubscribe({String source = 'connect'}) {
    final channel = _channel;
    if (channel == null) return;

    final sortedSymbols = _subscriptions.toList(growable: false)..sort();

    // [WS_SUBSCRIBE] — exact payload being sent to the backend WebSocket.
    final buf = StringBuffer('[WS_SUBSCRIBE]\n');
    buf.writeln('count=${sortedSymbols.length}');
    buf.writeln('source=$source  generation=$_wsGeneration');
    buf.writeln('symbols=[');
    for (final s in sortedSymbols) {
      final tag = _traceSymbols.contains(s) ? '  ← trace/forced' : '';
      buf.writeln('  $s,$tag');
    }
    buf.writeln(']');
    debugPrint(buf.toString());

    // lastSeq is ONLY sent on genuine WS reconnects (source == 'reconnect').
    // All other subscribe calls (manual symbol change, tab switch, initial connect,
    // watchdog) happen while the WebSocket is still alive — there is no gap to fill.
    // Including lastSeq in those cases makes the server treat every subscription
    // update as a reconnect and triggers a full replay burst for all 140 symbols.
    final lastSeq = source == 'reconnect'
        ? SubscriptionManager.instance.lastSeqMap
        : const <String, int>{};
    final payload = jsonEncode({
      'type':    'subscribe',
      'symbols': sortedSymbols,
      if (lastSeq.isNotEmpty) 'lastSeq': lastSeq,
    });
    debugPrint('[SUB_SOURCE] class=LiveMarketService method=_sendSubscribe '
        'source=$source generation=$_wsGeneration '
        'count=${sortedSymbols.length} '
        'first20=${sortedSymbols.take(20).toList()}');
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

    // expiry is sent as ISO-8601 string for futures contracts, null for equities.
    // Backend may use 'expiry', 'expiryDate', or 'contractExpiry' depending on
    // the data source (Angel One symbol file vs. market-routes enrichment).
    DateTime? expiry;
    final expiryRaw = d['expiry'] ?? d['expiryDate'] ?? d['contractExpiry'];
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

    // ── Real-time latency breakdown (visible in adb logcat / flutter logs) ──
    if (kDebugMode) {
      final broadcastTs      = (m['ts']                    as num?)?.toInt() ?? 0;
      final backendReceiveTs = (data['backendReceiveTs']   as num?)?.toInt() ?? 0;
      final serverTs         = (data['serverTs']           as num?)?.toInt() ?? 0;
      final exchangeTs       = (data['exchangeTs']         as num?)?.toInt() ?? 0;
      final ltp              = data['ltp'];

      final wsLag      = broadcastTs > 0 ? clientReceiveTs - broadcastTs       : -1;
      final backendLag = (backendReceiveTs > 0 && serverTs > 0)
                           ? backendReceiveTs - serverTs                        : -1;
      final exchLag    = (serverTs > 0 && exchangeTs > 0)
                           ? serverTs - exchangeTs                              : -1;

      debugPrint(
        '[LatencyTrace] RX  $symbol '
        'ltp=$ltp  '
        'WS→Client=${wsLag}ms  '
        'Backend→Broadcast=${backendLag < 0 ? "?" : "${backendLag}ms"}  '
        'Exchange→Backend=${exchLag < 0 ? "?" : "${exchLag}ms"}',
      );
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

        // ── Store processing latency (debug) ───────────────────────────────
        if (kDebugMode) {
          final rxTs         = (list[i]['clientReceiveTs'] as int?) ?? 0;
          final storeMs      = storeExitTs - storeEntryTs;
          final notifierMs   = ltpNotifierTs - storeEntryTs;
          final clientStoreMs = rxTs > 0 ? storeExitTs - rxTs : -1;
          debugPrint(
            '[LatencyTrace] STORE $symbol '
            'Store_total=${storeMs}ms  '
            'to_notifier=${notifierMs}ms  '
            'Client→StoreExit=${clientStoreMs < 0 ? "?" : "${clientStoreMs}ms"}',
          );
        }
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

    // ── End-to-end render latency (debug) ──────────────────────────────────
    if (kDebugMode) {
      final rxList = _traceRx[symbol];
      int rxTs = 0;
      if (rxList != null) {
        for (int j = rxList.length - 1; j >= 0; j--) {
          if (rxList[j]['ltp'] == ltp) {
            rxTs = (rxList[j]['clientReceiveTs'] as int?) ?? 0;
            break;
          }
        }
      }
      final storeExitToRender = renderTs - storeExitTs;
      final clientToRender    = rxTs > 0 ? renderTs - rxTs : -1;
    }

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

  /// Configure which symbols are actively traced for latency measurement.
  /// Trace symbols are NOT injected into _subscriptions — SubscriptionManager
  /// is the sole authority over that set.  Ticks arrive only when the symbol
  /// is independently subscribed by the current screen (e.g. NIFTY on watchlist).
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
