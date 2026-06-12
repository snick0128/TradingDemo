import 'dart:async';
import 'package:flutter/material.dart';
import '../data/services/live_market_service.dart';

/// Tracks active WebSocket subscriptions per screen, manages visibility stack,
/// implements reference counting, and observes global app lifecycle.
class SubscriptionManager with WidgetsBindingObserver {
  SubscriptionManager._();
  static final instance = SubscriptionManager._();

  LiveMarketService? _service;
  StreamSubscription? _connSub;

  // Track subscriptions per screen
  final Map<String, Set<String>> _screenSymbols = {};
  final Map<String, List<String>> _screenFnoTokens = {};
  final Map<String, String> _screenFnoExchange = {};

  // Stack of active/visible screens. The top of the stack (or overlay screens)
  // are considered currently visible to the user.
  final List<String> _screenStack = [];

  // symbol → List<interval> for active chart screens (retained for compatibility)
  final Map<String, List<String>> _activeCandleSubs = {};

  // Last known seq per symbol — sent on reconnect for gap-fill replay (retained for compatibility)
  final Map<String, int> _lastSeqMap = {};

  bool _attached = false;

  /// Wire this manager to [service]. Call once at startup.
  void attach(LiveMarketService service) {
    if (_attached) return;
    _attached = true;
    _service = service;

    // Register this manager as a global app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Listen for reconnect events — re-apply subscriptions
    _connSub = service.connectionStateStream.listen((status) {
      if (status.isConnected) {
        _restoreSubscriptions();
      }
    });
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _connSub = null;
    _attached = false;
    _service = null;
  }

  // ── Centralized Screen Subscription API ──────────────────────────────────────

  /// Subscribe to symbols for a specific screen and mark the screen as active.
  /// If [screenId] is already in the stack, it is brought to the top.
  void subscribeForScreen(
    String screenId,
    Iterable<String> symbols, {
    List<String>? fnoTokens,
    String? fnoExchange,
  }) {
    final cleanSymbols = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toSet();
    _screenSymbols[screenId] = cleanSymbols;

    if (fnoTokens != null) {
      _screenFnoTokens[screenId] = fnoTokens;
    } else {
      _screenFnoTokens.remove(screenId);
    }

    if (fnoExchange != null) {
      _screenFnoExchange[screenId] = fnoExchange;
    } else {
      _screenFnoExchange.remove(screenId);
    }

    // Bring/push to top of the stack
    _screenStack.remove(screenId);
    _screenStack.add(screenId);

    debugPrint('[SubscriptionManager] subscribeForScreen($screenId) symbols=$cleanSymbols fnoTokens=$fnoTokens stack=$_screenStack');
    _applySubscriptions();
  }

  /// Unsubscribe a screen completely (e.g. when disposed/closed).
  void unsubscribeScreen(String screenId) {
    _screenSymbols.remove(screenId);
    _screenFnoTokens.remove(screenId);
    _screenFnoExchange.remove(screenId);
    _screenStack.remove(screenId);

    debugPrint('[SubscriptionManager] unsubscribeScreen($screenId) stack=$_screenStack');
    _applySubscriptions();
  }

  /// Replace subscriptions for an active screen (e.g. when expiry changes).
  void replaceScreenSubscriptions(
    String screenId,
    Iterable<String> symbols, {
    List<String>? fnoTokens,
    String? fnoExchange,
  }) {
    _screenSymbols[screenId] = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toSet();

    if (fnoTokens != null) {
      _screenFnoTokens[screenId] = fnoTokens;
    } else {
      _screenFnoTokens.remove(screenId);
    }

    if (fnoExchange != null) {
      _screenFnoExchange[screenId] = fnoExchange;
    } else {
      _screenFnoExchange.remove(screenId);
    }

    if (!_screenStack.contains(screenId)) {
      _screenStack.add(screenId);
    }

    debugPrint('[SubscriptionManager] replaceScreenSubscriptions($screenId) stack=$_screenStack');
    _applySubscriptions();
  }

  /// Exclusively switches base tab screens (e.g., dashboard, portfolio, other).
  /// This removes previous tabs from the stack and sets the new tab as base.
  void switchTab(String tabScreenId, Iterable<String> symbols) {
    const tabs = {'dashboard', 'portfolio', 'other'};
    for (final tab in tabs) {
      _screenSymbols.remove(tab);
      _screenStack.remove(tab);
    }

    _screenSymbols[tabScreenId] = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toSet();
    _screenStack.insert(0, tabScreenId);

    debugPrint('[SubscriptionManager] switchTab($tabScreenId) stack=$_screenStack');
    _applySubscriptions();
  }

  // ── Internal Recalculation and Application ──────────────────────────────────

  void _applySubscriptions() {
    final service = _service;
    if (service == null) return;

    if (_screenStack.isEmpty) {
      service.setSubscribedSymbols({});
      service.clearFnoTokens();
      return;
    }

    // In screen-scoped subscription system, we only subscribe to the top screen
    // on the visibility stack. This prevents subscribing to screens in the
    // background of the navigation stack (like dashboard when option chain is open).
    final topScreenId = _screenStack.last;
    final activeSymbols = _screenSymbols[topScreenId] ?? <String>{};
    final activeTokens = _screenFnoTokens[topScreenId] ?? <String>[];
    final activeExchange = _screenFnoExchange[topScreenId] ?? 'NFO';

    debugPrint('[SubscriptionManager] Applying subscriptions for top screen ($topScreenId): symbols=$activeSymbols, tokens=$activeTokens');

    service.setSubscribedSymbols(activeSymbols);
    if (activeTokens.isNotEmpty) {
      service.subscribeFnoTokens(activeTokens, activeExchange);
    } else {
      // No FNO tokens for this screen — clear any stale tokens so they are
      // not replayed on the next WS reconnect (e.g., after closing options chain).
      service.clearFnoTokens();
    }
  }

  void _restoreSubscriptions() {
    _applySubscriptions();
    _restoreCandleSubs();
  }

  // ── Global App Lifecycle Handling ───────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      debugPrint('[SubscriptionManager] App paused — disconnecting WebSocket and clearing caches');
      _onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[SubscriptionManager] App resumed — updating snapshot and reconnecting');
      _onAppResumed();
    }
  }

  void _onAppPaused() {
    final service = _service;
    if (service == null) return;

    _lastSeqMap.clear();
    service.setIsBackground(true);
    service.disconnectWsOnly();
    service.clearTickProcessingState();
  }

  Future<void> _onAppResumed() async {
    final service = _service;
    if (service == null) return;

    // 1. Fetch latest market snapshot
    // 2. Replace stale prices immediately
    // 3. Reconnect WebSocket
    // 4. Reset background flags & set resume timestamp
    // 5. Subscribe only to visible screen's symbols
    // 6. Start processing live ticks
    await service.fetchFreshSnapshot();

    service.setIsBackground(false);
    service.setAppResumeTimestamp(DateTime.now().millisecondsSinceEpoch);

    service.reconnectWsOnly();
    _applySubscriptions();
  }

  // ── Candle subscription tracking (retained for compatibility) ───────────────

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

  void unsubscribeCandleStream(String symbol) {
    final sym = symbol.toUpperCase();
    _activeCandleSubs.remove(sym);
    _service?.unsubscribeCandleStream(sym);
  }

  void _restoreCandleSubs() {
    for (final entry in _activeCandleSubs.entries) {
      _service?.subscribeCandleStream(entry.key, entry.value);
    }
  }

  // ── Tick sequence tracking (retained for compatibility) ──────────────────────

  void onTickSeq(String symbol, int seq) {
    if (seq > (_lastSeqMap[symbol] ?? 0)) {
      _lastSeqMap[symbol] = seq;
    }
  }

  Map<String, int> get lastSeqMap => Map.unmodifiable(_lastSeqMap);

  int get activeCandleSubscriptionCount => _activeCandleSubs.length;

  /// Total number of symbols currently subscribed for the top visible screen.
  int get activeSymbolCount =>
      _screenStack.isEmpty ? 0 : (_screenSymbols[_screenStack.last]?.length ?? 0);
}
