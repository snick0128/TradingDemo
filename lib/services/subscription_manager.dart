import 'dart:async';
import '../data/services/live_market_service.dart';

/// Tracks active WebSocket subscriptions and automatically restores them
/// after reconnects. Call [attach] once from your Provider/service setup.
///
/// Covers:
///   • Tick subscriptions  — symbols the user is watching
///   • Candle subscriptions — chart screens' dedicated 500 ms streams
///   • User registration   — userId for push notifications
///
/// On reconnect the WS server already sends a new `welcome` → the service
/// calls `_connectWs()` which sends a `subscribe` message, so tick subs
/// are already restored automatically. This manager's job is to:
///   1. Track candle subscriptions and re-send them after reconnect.
///   2. Re-register the userId if present.
///   3. Send `lastSeq` map on reconnect so the server can replay missed ticks.
class SubscriptionManager {
  SubscriptionManager._();
  static final instance = SubscriptionManager._();

  LiveMarketService? _service;
  StreamSubscription? _connSub;

  // symbol → List<interval> for active chart screens
  final Map<String, List<String>> _activeCandleSubs = {};

  // Last known seq per symbol — sent on reconnect for gap-fill replay
  final Map<String, int> _lastSeqMap = {};

  bool _attached = false;

  /// Wire this manager to [service]. Call once at startup.
  void attach(LiveMarketService service) {
    if (_attached) return;
    _attached = true;
    _service = service;

    // Listen for reconnect events — re-subscribe candle streams after each
    // successful WS connection.
    _connSub = service.connectionStateStream.listen((status) {
      if (status.isConnected && _activeCandleSubs.isNotEmpty) {
        _restoreCandleSubs();
      }
    });
  }

  void detach() {
    _connSub?.cancel();
    _connSub = null;
    _attached = false;
    _service = null;
  }

  // ── Candle subscription tracking ─────────────────────────────────────────────

  /// Subscribe to candle streams for [symbol]+[intervals].
  /// Idempotent — calling twice for the same symbol merges intervals.
  void subscribeCandleStream(String symbol, List<String> intervals) {
    final sym = symbol.toUpperCase();
    final existing = _activeCandleSubs[sym];
    if (existing != null) {
      final merged = {...existing, ...intervals}.toList();
      _activeCandleSubs[sym] = merged;
    } else {
      _activeCandleSubs[sym] = List.of(intervals);
    }
    _service?.subscribeCandleStream(sym, intervals);
  }

  /// Unsubscribe from candle streams for [symbol].
  void unsubscribeCandleStream(String symbol) {
    final sym = symbol.toUpperCase();
    _activeCandleSubs.remove(sym);
    _service?.unsubscribeCandleStream(sym);
  }

  // ── Tick sequence tracking (for gap-fill) ─────────────────────────────────────

  /// Called by the tick handler each time a tick with a sequence number arrives.
  /// Used to build the lastSeq map sent on reconnect.
  void onTickSeq(String symbol, int seq) {
    if (seq > (_lastSeqMap[symbol] ?? 0)) {
      _lastSeqMap[symbol] = seq;
    }
  }

  /// The current lastSeq map — pass to `subscribe` message on reconnect.
  Map<String, int> get lastSeqMap => Map.unmodifiable(_lastSeqMap);

  // ── Internal ──────────────────────────────────────────────────────────────────

  void _restoreCandleSubs() {
    for (final entry in _activeCandleSubs.entries) {
      _service?.subscribeCandleStream(entry.key, entry.value);
    }
  }

  /// Number of active candle subscriptions (for diagnostics).
  int get activeCandleSubscriptionCount => _activeCandleSubs.length;
}
