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

  // Previous active symbol set — used to compute diffs on every subscription change.
  Set<String> _prevActiveSymbols = {};

  bool _attached = false;

  // Debounce timer for the pause→disconnect path.
  // Flutter Web fires AppLifecycleState.paused on every browser tab-switch or
  // window focus loss, which would cause a full WS disconnect+reconnect cycle
  // on every such interaction.  We delay the actual disconnect; if the app
  // resumes within the window the timer is cancelled and no reconnect occurs.
  Timer? _pauseDisconnectTimer;
  // Set to true ONLY when the timer fires and actually executes the disconnect.
  // Stays false if the timer is cancelled (brief switch) or never set (no pause).
  bool _wsDisconnectedByPause = false;
  static const Duration _pauseDisconnectDelay = Duration(seconds: 30);

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
    _pauseDisconnectTimer?.cancel();
    _pauseDisconnectTimer = null;
    _wsDisconnectedByPause = false;
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _connSub = null;
    _attached = false;
    _service = null;
  }

  // ── Centralized Screen Subscription API ──────────────────────────────────────

  // Monotonically increasing per-screenId generation counter. Guards against
  // a superseded screen instance's deferred dispose() (Flutter delays
  // dispose() until the pop transition animation finishes, ~300ms) calling
  // unsubscribeScreen() for a screenId a brand-new instance (e.g. the same
  // symbol's detail screen, re-pushed by a fast tap→back→tap) has already
  // re-registered. Optional at the call site — omit it to keep the old
  // unconditional-unsubscribe behavior for screenIds that are never
  // re-created under the same key (e.g. fixed singleton screens).
  final Map<String, int> _screenGeneration = {};

  /// Subscribe to symbols for a specific screen and mark the screen as active.
  /// If [screenId] is already in the stack, it is brought to the top.
  /// Returns this call's generation — pass it to [unsubscribeScreen] to make
  /// that unsubscribe a no-op if a newer call already superseded it.
  int subscribeForScreen(
    String screenId,
    Iterable<String> symbols, {
    List<String>? fnoTokens,
    String? fnoExchange,
  }) {
    final prevStack  = List.of(_screenStack);
    final prevCount  = activeSymbolCount;

    final generation = (_screenGeneration[screenId] ?? 0) + 1;
    _screenGeneration[screenId] = generation;

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

    _logNavTrace('subscribeForScreen', screenId, cleanSymbols,
        prevStack: prevStack, newStack: _screenStack, prevCount: prevCount);
    _applySubscriptions();
    return generation;
  }

  /// Unsubscribe a screen completely (e.g. when disposed/closed).
  /// If [generation] is provided and a newer [subscribeForScreen] call for
  /// this [screenId] has already landed, this is a no-op — the newer
  /// registration wins instead of being wiped out by a stale dispose().
  void unsubscribeScreen(String screenId, [int? generation]) {
    if (generation != null && _screenGeneration[screenId] != generation) {
      debugPrint('[STALE_UNSUBSCRIBE_IGNORED] screen=$screenId '
          'staleGen=$generation currentGen=${_screenGeneration[screenId]}');
      return;
    }

    final prevStack   = List.of(_screenStack);
    final prevCount   = activeSymbolCount;
    final ownedSymbols = Set<String>.of(_screenSymbols[screenId] ?? {});

    _screenSymbols.remove(screenId);
    _screenFnoTokens.remove(screenId);
    _screenFnoExchange.remove(screenId);
    _screenStack.remove(screenId);
    _screenGeneration.remove(screenId);

    debugPrint('[LEAK_CHECK] screen=$screenId '
        'released=${ownedSymbols.length} '
        'remainingScreens=${_screenStack.length} '
        'remainingSymbols=$activeSymbolCount '
        'stack=$_screenStack');

    _logNavTrace('unsubscribeScreen', screenId, ownedSymbols,
        prevStack: prevStack, newStack: _screenStack, prevCount: prevCount);
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

    debugPrint('[SubscriptionManager] replaceScreenSubscriptions($screenId) stack=$_screenStack');
    // Updating a registered screen must not make it visible. TradingStore keeps
    // dashboard and portfolio symbol sets fresh in the background; previously
    // those refreshes pushed an inactive screen to the top and replaced the
    // visible screen's WebSocket subscriptions.
    if (_screenStack.contains(screenId)) {
      _applySubscriptions();
    }
  }

  /// Exclusively switches base tab screens (e.g., dashboard, portfolio, other).
  /// This removes previous tabs from the stack and sets the new tab as base.
  void switchTab(String tabScreenId, Iterable<String> symbols) {
    final prevStack = List.of(_screenStack);
    final prevCount = activeSymbolCount;

    const tabs = {'dashboard', 'portfolio', 'other'};
    for (final tab in tabs) {
      _screenSymbols.remove(tab);
      _screenStack.remove(tab);
    }

    final cleanSymbols = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toSet();
    _screenSymbols[tabScreenId] = cleanSymbols;
    _screenStack.insert(0, tabScreenId);

    _logNavTrace('switchTab', tabScreenId, cleanSymbols,
        prevStack: prevStack, newStack: _screenStack, prevCount: prevCount);
    _applySubscriptions();
  }

  // ── Internal Recalculation and Application ──────────────────────────────────

  void _applySubscriptions() {
    final service = _service;
    if (service == null) return;

    if (_screenStack.isEmpty) {
      _logSubDiff(<String>{});
      _prevActiveSymbols = {};
      service.setSubscribedSymbols({});
      service.clearFnoTokens();
      return;
    }

    // Subscribe to the UNION of every registered screen's symbols — not just
    // the top of the stack. Restricting to top-only meant any backgrounded
    // screen (dashboard, market watch) silently stopped receiving live ticks
    // the instant another screen (stock detail, options chain, order form)
    // was pushed on top, with no error or indication anywhere. F&O option
    // tokens stay scoped to the top screen only — that subscription is
    // deliberately heavyweight and screen-specific.
    final topScreenId  = _screenStack.last;
    final activeSymbols = <String>{};
    for (final symbols in _screenSymbols.values) {
      activeSymbols.addAll(symbols);
    }
    final activeTokens  = _screenFnoTokens[topScreenId] ?? <String>[];
    final activeExchange = _screenFnoExchange[topScreenId] ?? 'NFO';

    // ── Diagnostics ──────────────────────────────────────────────────────────
    _logSubDiff(activeSymbols);
    _logSubOwnership(topScreenId, activeSymbols);
    _logZombies(service, activeSymbols);
    _logForcedSymbols(service, activeSymbols);
    dumpSubReport(topScreenId: topScreenId, activeSymbols: activeSymbols,
        activeTokens: activeTokens, service: service);
    // ─────────────────────────────────────────────────────────────────────────

    _prevActiveSymbols = Set.of(activeSymbols);
    _recordChange();

    service.setSubscribedSymbols(activeSymbols);
    if (activeTokens.isNotEmpty) {
      service.subscribeFnoTokens(activeTokens, activeExchange);
    } else {
      // No FNO tokens for this screen — clear any stale tokens so they are
      // not replayed on the next WS reconnect (e.g., after closing options chain).
      service.clearFnoTokens();
    }
  }

  // ── Diagnostic helpers ──────────────────────────────────────────────────────

  /// [SUB_DIFF] — symbols added/removed since last _applySubscriptions call.
  void _logSubDiff(Set<String> newActive) {
    final added   = newActive.difference(_prevActiveSymbols);
    final removed = _prevActiveSymbols.difference(newActive);
    final buf = StringBuffer('[SUB_DIFF]\n');
    buf.writeln('Added (${added.length}):');
    if (added.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (final s in added.toList()..sort()) buf.writeln('  $s');
    }
    buf.writeln('Removed (${removed.length}):');
    if (removed.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (final s in removed.toList()..sort()) buf.writeln('  $s');
    }
    buf.writeln('Current Active (${newActive.length}):');
    for (final s in newActive.toList()..sort()) buf.writeln('  $s');
    debugPrint(buf.toString());
  }

  /// [SUB_OWNERSHIP] — which screen owns each active symbol.
  void _logSubOwnership(String topScreenId, Set<String> activeSymbols) {
    final buf = StringBuffer('[SUB_OWNERSHIP]\n');
    buf.writeln('Top screen: $topScreenId');
    buf.writeln('Full stack: $_screenStack\n');
    for (final sym in activeSymbols.toList()..sort()) {
      final owners = _screenSymbols.entries
          .where((e) => e.value.contains(sym))
          .map((e) => e.key)
          .toList();
      buf.writeln('  $sym');
      buf.writeln('    Owner: ${owners.isEmpty ? "(none)" : owners.join(", ")}');
    }
    // Registered-but-background symbols (exist in the table but not subscribed)
    final background = <String>{};
    for (final e in _screenSymbols.entries) {
      if (e.key != topScreenId) background.addAll(e.value);
    }
    final bgOnly = background.difference(activeSymbols);
    if (bgOnly.isNotEmpty) {
      buf.writeln('\n  Background (registered but NOT currently subscribed to WS):');
      for (final sym in bgOnly.toList()..sort()) {
        final owners = _screenSymbols.entries
            .where((e) => e.value.contains(sym))
            .map((e) => e.key)
            .toList();
        buf.writeln('    $sym  ← ${owners.join(", ")}');
      }
    }
    debugPrint(buf.toString());
  }

  /// [ZOMBIE_SUBSCRIPTION] — symbols live in WS _subscriptions with no screen owner.
  void _logZombies(LiveMarketService service, Set<String> expectedActive) {
    final actual = service.subscribedSymbolsForDiagnostics;
    final traceSyms = service.traceSymbols;
    final zombies = actual
        .where((s) => !expectedActive.contains(s) && !traceSyms.contains(s))
        .toSet();
    if (zombies.isEmpty) return;
    final buf = StringBuffer('[ZOMBIE_SUBSCRIPTION]\n');
    buf.writeln('${zombies.length} symbol(s) in WS _subscriptions with no screen owner:\n');
    for (final sym in zombies.toList()..sort()) {
      final lastOwners = _screenSymbols.entries
          .where((e) => e.value.contains(sym))
          .map((e) => e.key)
          .toList();
      buf.writeln('  symbol=$sym');
      buf.writeln('    reason=no active owner, not in trace set');
      if (lastOwners.isNotEmpty) {
        buf.writeln('    last_registered_by=${lastOwners.join(", ")}');
      }
    }
    debugPrint(buf.toString());
  }

  /// [FORCED_SUBSCRIPTION] — trace symbols that are tracked but NOT currently
  /// subscribed (they do not appear in any screen's symbol set, so no WS ticks
  /// will arrive for them until a screen explicitly requests them).
  void _logForcedSymbols(LiveMarketService service, Set<String> screenActive) {
    final traceSyms = service.traceSymbols;
    final notSubscribed = traceSyms.where((s) => !screenActive.contains(s)).toSet();
    if (notSubscribed.isEmpty) return;
    final buf = StringBuffer('[FORCED_SUBSCRIPTION]\n');
    buf.writeln('Trace symbols NOT currently subscribed (no screen requests them):\n');
    for (final sym in notSubscribed.toList()..sort()) {
      buf.writeln('  symbol=$sym');
      buf.writeln('    note=tracked for latency only; ticks will NOT arrive until a screen subscribes this symbol');
    }
    debugPrint(buf.toString());
  }

  /// [NAV_TRACE] — navigation event with stack transition and symbol delta.
  void _logNavTrace(
    String event,
    String screenId,
    Set<String> symbols, {
    required List<String> prevStack,
    required List<String> newStack,
    required int prevCount,
  }) {
    final prevTop = prevStack.isEmpty ? '(none)' : prevStack.last;
    final newTop  = newStack.isEmpty  ? '(none)' : newStack.last;
    final buf = StringBuffer('[NAV_TRACE] $event\n');
    buf.writeln('  screen=$screenId');
    buf.writeln('  stack_before=[${prevStack.join(" → ")}]');
    buf.writeln('  stack_after =[${newStack.join(" → ")}]');
    buf.writeln('  top_before=$prevTop  →  top_after=$newTop');
    buf.writeln('  active_count_before=$prevCount  →  after=${activeSymbolCount}');
    buf.writeln('  screen_symbols (${symbols.length})=[${(symbols.toList()..sort()).join(", ")}]');
    debugPrint(buf.toString());
  }

  /// [SUB_REPORT] — full current state summary.
  /// Called automatically on every _applySubscriptions(); also callable externally.
  void dumpSubReport({
    String? topScreenId,
    Set<String>? activeSymbols,
    List<String>? activeTokens,
    LiveMarketService? service,
  }) {
    final top      = topScreenId ?? (_screenStack.isEmpty ? null : _screenStack.last);
    final actSyms  = activeSymbols ?? (top != null ? (_screenSymbols[top] ?? {}) : <String>{});
    final actToks  = activeTokens  ?? (top != null ? (_screenFnoTokens[top] ?? []) : <String>[]);
    final svc      = service ?? _service;

    final buf = StringBuffer('[SUB_REPORT]\n');
    buf.writeln('══════════════════════════════════════════════════');
    buf.writeln('Current Active Subscription Count: ${actSyms.length}');
    buf.writeln('Top Screen: ${top ?? "(none)"}');
    buf.writeln('Full Stack: $_screenStack');
    if (svc != null) {
      final wsActual = svc.subscribedSymbolsForDiagnostics;
      buf.writeln('WS _subscriptions.length: ${wsActual.length}');
      buf.writeln('F&O tokens active: ${actToks.length}');
    }
    buf.writeln();

    // ── Breakdown by screen ────────────────────────────────────────────────
    buf.writeln('Breakdown:');
    const _catLabel = <String, String>{
      'dashboard':    'Dashboard',
      'portfolio':    'Portfolio',
      'market_watch': 'Watchlist (MarketWatch)',
      'orders':       'Orders',
      'other':        'Other (Markets/Profile tab)',
      'options_chain':'Option Chain',
    };
    for (final e in _screenSymbols.entries) {
      final label = _catLabel[e.key]
          ?? (e.key.startsWith('stock_detail')    ? 'Stock Detail'
            : e.key.startsWith('advanced_chart')  ? 'Chart'
            : e.key.startsWith('order_form')       ? 'Order Form'
            : 'Unknown');
      final isTop = e.key == top;
      buf.writeln('  $label (${e.key})${isTop ? "  ← TOP" : ""}: ${e.value.length} symbols');
    }
    if (svc != null) {
      final traceSym = svc.traceSymbols;
      final traceInActive = traceSym.where(actSyms.contains).length;
      buf.writeln('  Trace/Forced: ${traceSym.length} total, $traceInActive in active WS send');
    }
    buf.writeln();

    // ── Currently active symbols (what backend is streaming NOW) ────────────
    buf.writeln('Currently streaming to this client (${actSyms.length} symbols):');
    for (final s in actSyms.toList()..sort()) buf.writeln('  $s');

    if (actToks.isNotEmpty) {
      buf.writeln();
      buf.writeln('F&O tokens (option chain, ${actToks.length}):');
      for (final t in actToks) buf.writeln('  $t');
    }

    if (svc != null) {
      final wsActual = svc.subscribedSymbolsForDiagnostics;
      final extra = wsActual.difference(actSyms);
      if (extra.isNotEmpty) {
        buf.writeln();
        buf.writeln('Extra in WS _subscriptions (not from top screen):');
        for (final s in extra.toList()..sort()) {
          final src = svc.traceSymbols.contains(s) ? 'TraceSystem' : 'unknown';
          buf.writeln('  $s  ← $src');
        }
      }
    }
    buf.writeln('══════════════════════════════════════════════════');
    debugPrint(buf.toString());
  }

  // ── Restore after reconnect ─────────────────────────────────────────────────

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

    // Stop tick processing immediately — we don't want background ticks
    // updating the UI or polluting the price state while the tab is hidden.
    service.setIsBackground(true);

    // Debounce the WS disconnect.  Flutter Web fires AppLifecycleState.paused
    // on every tab-switch or window focus loss; tearing down the WebSocket on
    // each of those events causes a full reconnect cycle (handshake + snapshot
    // + replay) for what is typically a 1–5 second user interaction.
    // If _onAppResumed fires within _pauseDisconnectDelay we cancel this timer
    // and skip the disconnect entirely — keeping the session alive.
    _pauseDisconnectTimer?.cancel();
    _pauseDisconnectTimer = Timer(_pauseDisconnectDelay, () {
      _pauseDisconnectTimer = null;
      _wsDisconnectedByPause = true;
      debugPrint(
        '[SubscriptionManager] Pause sustained >${_pauseDisconnectDelay.inSeconds}s '
        '— disconnecting WebSocket and clearing caches',
      );
      _lastSeqMap.clear();
      service.disconnectWsOnly();
      service.clearTickProcessingState();
    });
  }

  Future<void> _onAppResumed() async {
    final service = _service;
    if (service == null) return;

    // Set resume gate immediately — ticks broadcast from this moment forward
    // are accepted; ticks broadcast while we were inactive are rejected.
    service.setIsBackground(false);
    service.setAppResumeTimestamp(DateTime.now().millisecondsSinceEpoch);

    // Capture and reset disconnect flag BEFORE cancelling the timer so we
    // correctly distinguish three cases:
    //   A) Timer fired → _wsDisconnectedByPause=true  → full reconnect required
    //   B) Timer pending → _wsDisconnectedByPause=false → brief switch, cancel timer
    //   C) No pause event at all → _wsDisconnectedByPause=false → no action on WS
    final needReconnect = _wsDisconnectedByPause;
    _wsDisconnectedByPause = false;
    _pauseDisconnectTimer?.cancel();
    _pauseDisconnectTimer = null;

    if (!needReconnect) {
      // Cases B & C: WS is still alive.
      // Fetch a fresh snapshot to patch any prices missed while inactive,
      // then reapply subscriptions (idempotent — harmless if already correct).
      debugPrint(
        '[SubscriptionManager] App resumed — WS alive, refreshing snapshot only',
      );
      await service.fetchFreshSnapshot();
      _applySubscriptions();
      return;
    }

    // Case A: Genuine resume after a sustained background pause — full reconnect.
    debugPrint('[SubscriptionManager] App resumed after disconnect — reconnecting');
    await service.fetchFreshSnapshot();
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

  /// Total number of distinct symbols currently subscribed across ALL
  /// registered screens (the union _applySubscriptions() actually sends).
  int get activeSymbolCount {
    if (_screenStack.isEmpty) return 0;
    final all = <String>{};
    for (final symbols in _screenSymbols.values) {
      all.addAll(symbols);
    }
    return all.length;
  }

  // ── Subscription change diagnostics ────────────────────────────────────────

  int _changeCount = 0;
  int _lastMinuteCount = 0;
  DateTime? _minuteStart;

  void _recordChange() {
    final now = DateTime.now();
    if (_minuteStart == null || now.difference(_minuteStart!).inSeconds >= 60) {
      _lastMinuteCount = _changeCount;
      _changeCount = 0;
      _minuteStart = now;
    }
    _changeCount++;
  }

  /// Number of _applySubscriptions() calls in the last completed minute.
  int get subscriptionChangesPerMinute => _lastMinuteCount;

  /// Current symbol count per registered screen.
  Map<String, int> get symbolsByScreen =>
      Map.unmodifiable({for (final e in _screenSymbols.entries) e.key: e.value.length});
}
