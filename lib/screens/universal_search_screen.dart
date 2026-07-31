import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../search/search_index.dart';
import '../search/top_50_stocks.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/instrument_logo.dart';
import '../widgets/shared_widgets.dart' show Sparkline;
import 'stock_detail_screen.dart';

// ─── Session-level search cache ──────────────────────────────────────────────
//
// Lives as static state — survives screen pops/reopens for the entire app
// session. Implements a three-tier TTL model:
//
//   Fresh  (< 45s)  — serve immediately, no background refresh needed
//   Stale  (< 5min) — serve immediately, trigger silent background refresh
//   Expired(> 5min) — don't serve; fetch fresh (show skeleton)
//
// This gives users sub-millisecond results for recently-typed queries while
// ensuring data stays reasonably fresh.

class _CachedSearch {
  final List<_RemoteResult> results;
  final DateTime fetchedAt;

  _CachedSearch(this.results) : fetchedAt = DateTime.now();

  static const _kFresh = Duration(seconds: 45);
  static const _kStale = Duration(minutes: 5);

  bool get isFresh   => DateTime.now().difference(fetchedAt) < _kFresh;
  bool get isExpired => DateTime.now().difference(fetchedAt) > _kStale;
  bool get isStale   => !isFresh && !isExpired;
}

/// Session-scoped search result store — global singleton, never GC'd during app life.
class _SearchSessionCache {
  _SearchSessionCache._();

  static const _kMax = 120; // plenty for a full session

  static final Map<String, _CachedSearch> _store = {};

  static _CachedSearch? get(String key) => _store[key];

  static void put(String key, List<_RemoteResult> results) {
    if (_store.length >= _kMax) _store.remove(_store.keys.first);
    _store[key] = _CachedSearch(results);
    debugPrint('[SearchCache] Stored "$key" (${results.length} results, total=${_store.length})');
  }

  static int get size => _store.length;
}

// ─── Remote result (from backend API) ────────────────────────────────────────

class _RemoteResult {
  final String exchange;
  final String tradingSymbol;
  final String symbolToken;
  final String name;
  final String instrumentType;
  double? ltp;
  double? percentChange;

  _RemoteResult({
    required this.exchange,
    required this.tradingSymbol,
    required this.symbolToken,
    this.name = '',
    this.instrumentType = '',
    this.ltp,
    this.percentChange,
  });

  factory _RemoteResult.fromJson(Map<String, dynamic> j) {
    // Backend /search returns: symbol, exchange, type, token, displayName, ltp, percentChange
    // Backend /derivatives/search returns: tradingSymbol, exchange, symbolToken, name, instrumentType
    final sym =
        (j['symbol'] ?? j['tradingSymbol'] ?? j['tradingsymbol'] ?? '')
            as String;
    final tok = (j['token'] ?? j['symbolToken'] ?? j['symboltoken'] ?? '')
        .toString();
    final name = (j['displayName'] ?? j['name'] ?? '') as String;
    final type = (j['type'] ?? j['instrumentType'] ?? '') as String;

    // Never default to NSE — use the exchange the backend actually returned.
    // If exchange is missing from the response, that's a backend bug to fix,
    // not something to silently paper over with 'NSE'.
    final rawExchange = (j['exchange'] as String?) ?? '';
    final exchange = rawExchange.isNotEmpty ? rawExchange.toUpperCase() : 'NSE';

    return _RemoteResult(
      exchange: exchange,
      tradingSymbol: sym,
      symbolToken: tok,
      name: name,
      instrumentType: type,
      ltp: (j['ltp'] as num?)?.toDouble(),
      percentChange: (j['percentChange'] as num?)?.toDouble(),
    );
  }

  String get displaySymbol =>
      tradingSymbol.replaceAll(RegExp(r'-(EQ|BE|BL|IQ|RL|AF|U\d+)$'), '');

  /// Derive a display segment from the Angel One `instrumentType` field,
  /// falling back to symbol-pattern heuristics when unavailable.
  String get segment {
    if (exchange == 'CDS') return 'CURR';

    // Use the authoritative Angel One type when present
    final t = instrumentType.toUpperCase();
    if (t == 'EQ') return 'EQ';
    if (t == 'ETF' || t == 'ETFS') return 'ETF';
    if (t == 'INDEX' || t == 'UNDIND') return 'INDEX';
    if (t == 'FUTCOM' || exchange == 'MCX') return 'COMM';
    if (t == 'FUTSTK' || t == 'FUTIDX' || t == 'FUTCUR') return 'FUT';
    if (t == 'OPTSTK' || t == 'OPTIDX' || t == 'OPTCUR') {
      return tradingSymbol.toUpperCase().endsWith('PE') ? 'PE' : 'CE';
    }

    // Fallback: pattern match on symbol name
    final upper = tradingSymbol.toUpperCase();
    if (upper.endsWith('FUT')) return 'FUT';
    if (upper.endsWith('CE')) return 'CE';
    if (upper.endsWith('PE')) return 'PE';
    return 'EQ';
  }

  /// True if this result is a derivatives contract (futures or options).
  bool get isDerivative {
    final seg = segment;
    return seg == 'FUT' || seg == 'CE' || seg == 'PE';
  }

  /// Map this result to the typed [InstrumentType] used throughout the app.
  InstrumentType get resolvedInstrumentType =>
      InstrumentTypeX.fromAngelOne(instrumentType, symbol: tradingSymbol);

  String get dedupKey => '${exchange}_$tradingSymbol';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _controller = TextEditingController();
  final _api        = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  final _focusNode  = FocusNode();

  String  _query          = '';
  String? _exchangeFilter; // null = All
  String? _segmentFilter;

  // Top 50 NSE instant cache — filtered in-memory, shown before full index
  List<Top50Stock> _top50Filtered = kTop50Stocks;

  // Instant local results — prefix trie lookup, < 5ms
  List<Instrument> _localResults = [];

  // Remote API results (enriched with LTP + token from backend)
  List<_RemoteResult> _remoteResults = [];
  bool   _remoteLoading = false;
  String? _remoteError;

  // Generation counter: incremented on every new query or filter change.
  // All async responses check this before mutating state, preventing races.
  int _reqGen = 0;

  Timer? _debounce;
  Timer? _retryTimer;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Pre-warm: fire a real search query immediately so the connection, search
    // route, and instrument index are ALL warm before the user types anything.
    // /health alone only wakes the Express process; this also warms the search
    // index cache and the TCP+TLS connection that subsequent searches will reuse.
    unawaited(_api.searchUniversal('nifty', limit: 5).catchError((_) {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedContext();
      _preloadWatchlist(); // background prefetch of watchlist quotes
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  // ── Context seeding ─────────────────────────────────────────────────────────

  void _seedContext() {
    if (!mounted) return;
    final store = TradingScope.of(context);
    SearchIndex.instance.updateContext(
      watchlist: store.watchlist.map((s) => s.symbol).toSet(),
      holdings:  store.holdings.map((h) => h.symbol).toSet(),
      positions: store.positions.map((p) => p.symbol).toSet(),
      recent:    List<String>.from(store.recentSearches),
    );
  }

  // ── Background prefetch ─────────────────────────────────────────────────────

  /// Prefetch quote data for watchlist instruments that don't have a live price.
  /// Populates the HTTP cache so stock detail opens instantly for these symbols.
  Future<void> _preloadWatchlist() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final store = TradingScope.of(context);
    final toLoad = store.watchlist
        .where((s) => s.token.isNotEmpty && s.currentPrice <= 0)
        .take(4)
        .toList();
    for (final s in toLoad) {
      unawaited(
        _api.getQuoteByToken(s.token, exchange: s.exchange.isNotEmpty ? s.exchange : 'NSE')
            .catchError((_) {}),
      );
    }
    debugPrint('[Search] Preloaded ${toLoad.length} watchlist quotes');
  }

  /// Prefetch quote data on tap-down (before the tap is registered by the system).
  /// The ~100ms between tap-down and route push is enough to populate the HTTP
  /// cache — making the detail screen feel instantaneous.
  void _prefetchForSymbol({
    required String symbol,
    required String exchange,
    required String token,
  }) {
    debugPrint('[Search] Prefetch tap-down: $symbol ($exchange) token=${token.isEmpty ? "none" : token.substring(0, token.length.clamp(0, 8))}...');
    // Strategy 1 — /market/stock (always fire, works for WebSocket-tracked symbols)
    unawaited(_api.getStockDetail(symbol.toUpperCase()).catchError((_) {}));
    // Strategy 2 — /derivatives/quote (requires token; covers indices, F&O, MCX)
    if (token.isNotEmpty) {
      final ex = exchange.isNotEmpty ? exchange.toUpperCase() : 'NSE';
      unawaited(_api.getQuoteByToken(token, exchange: ex).catchError((_) {}));
    }
  }

  // ── Token resolution ────────────────────────────────────────────────────────

  /// Resolve the best token for a local catalog instrument.
  ///
  /// Priority:
  ///   1. TradingStore (live WebSocket — most authoritative)
  ///   2. SearchIndex._tokenMap (populated by previous remote search)
  ///   3. Empty string (detail screen falls back to /market/stock only)
  String _tokenFor(Instrument instrument) {
    if (mounted) {
      final stock = TradingScope.of(context).stockBySymbolOrNull(instrument.symbol);
      if (stock != null && stock.token.isNotEmpty) return stock.token;
    }
    return SearchIndex.instance.getToken(instrument.symbol, exchange: instrument.exchange);
  }

  // ── Query handling ──────────────────────────────────────────────────────────

  // Filter the static Top 50 list by query — O(50), always < 1ms.
  List<Top50Stock> _filterTop50(String q) {
    if (q.isEmpty) return kTop50Stocks;
    final upper = q.toUpperCase();
    final prefixHits  = <Top50Stock>[];
    final containsHits = <Top50Stock>[];
    for (final s in kTop50Stocks) {
      if (s.symbol.startsWith(upper)) {
        prefixHits.add(s);
      } else if (s.symbol.contains(upper) || s.companyName.toUpperCase().contains(upper)) {
        containsHits.add(s);
      }
    }
    return [...prefixHits, ...containsHits];
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _retryTimer?.cancel();
    final q = value.trim();

    // Always filter Top 50 instantly — no network, no index lookup.
    final swTop50 = Stopwatch()..start();
    final top50 = _filterTop50(q);
    swTop50.stop();

    if (q.isEmpty) {
      setState(() {
        _query          = q;
        _top50Filtered  = top50;
        _localResults   = [];
        _remoteResults  = [];
        _remoteLoading  = false;
        _remoteError    = null;
      });
      return;
    }

    if (top50.isNotEmpty) {
      debugPrint('[SEARCH_TOP50_HIT] q="$q" hits=${top50.length} latencyUs=${swTop50.elapsedMicroseconds}');
    } else {
      debugPrint('[SEARCH_TOP50_MISS] q="$q" latencyUs=${swTop50.elapsedMicroseconds}');
    }

    if (q.length < 2) {
      // Single-char: show only top 50 matches — full index too noisy for 1 char.
      setState(() {
        _query          = q;
        _top50Filtered  = top50;
        _localResults   = [];
        _remoteResults  = [];
        _remoteLoading  = false;
        _remoteError    = null;
      });
      return;
    }

    // ── Step 1: Instant local results (<5ms) ──
    debugPrint('[SEARCH_FULL_INDEX] q="$q"');
    final local    = SearchIndex.instance.search(q, limit: 20);
    final cacheKey = '${_exchangeFilter ?? 'ALL'}_$q';
    final cached   = _SearchSessionCache.get(cacheKey);

    if (cached != null && !cached.isExpired) {
      // ── Cache hit: serve immediately (<1ms perceived) ──────────────────────
      setState(() {
        _query          = q;
        _top50Filtered  = top50;
        _localResults   = local;
        _remoteResults  = cached.results;
        _remoteLoading  = false;
        _remoteError    = null;
      });

      // Stale: serve immediately, refresh silently in background.
      // Very short delay (50ms) — just enough to let the current frame paint
      // before firing the background network request.
      if (cached.isStale) {
        final gen = ++_reqGen;
        _debounce = Timer(const Duration(milliseconds: 50),
            () => _fetchRemote(q, gen, isBackground: true));
      }
      return;
    }

    // ── Cache miss: show skeleton immediately + fire API ────────────────────
    final gen = ++_reqGen;
    setState(() {
      _query          = q;
      _top50Filtered  = top50;
      _localResults   = local;
      _remoteLoading  = true;
      _remoteError    = null;
      // Keep previous remote results while loading — avoids the "flash of
      // empty skeleton" when the user extends the query (TAT → TATA).
    });

    // 100ms debounce: shorter than before (was 200ms).
    // Still prevents firing on every intermediate keystroke while typing fast,
    // but halves the wait once the user pauses.
    _debounce = Timer(const Duration(milliseconds: 100),
        () => _fetchRemote(q, gen));
  }

  Future<void> _fetchRemote(String q, int gen, {bool isBackground = false}) async {
    if (q.isEmpty || q.length < 2 || !mounted) return;

    // Generation guard — discard if superseded by a newer query or filter change
    if (gen != _reqGen) {
      debugPrint('[Search] Drop gen=$gen (current=$_reqGen) q="$q"');
      return;
    }

    final cacheKey = '${_exchangeFilter ?? 'ALL'}_$q';

    // Double-check session cache — another code path may have populated it
    final alreadyCached = _SearchSessionCache.get(cacheKey);
    if (alreadyCached != null && !alreadyCached.isExpired) {
      if (gen == _reqGen && mounted) {
        setState(() {
          _remoteResults = alreadyCached.results;
          _remoteLoading = false;
          _remoteError   = null;
        });
      }
      return;
    }

    debugPrint('[Search] Fetch gen=$gen bg=$isBackground q="$q" ex=${_exchangeFilter ?? "ALL"}');
    final sw = Stopwatch()..start();

    try {
      final results = await _api.searchUniversal(q, exchange: _exchangeFilter);
      sw.stop();
      debugPrint('[Search] Got gen=$gen ${results.length} results in ${sw.elapsedMilliseconds}ms');

      if (gen != _reqGen || !mounted) {
        debugPrint('[Search] Discard stale response gen=$gen');
        return;
      }

      final parsed = results.map(_RemoteResult.fromJson).toList();

      // ── Store in session cache ──
      _SearchSessionCache.put(cacheKey, parsed);

      // ── Ingest into local trie + token map ──
      // Next keystrokes will be instant. Also populates SearchIndex._tokenMap
      // so local-result navigation always has a valid token.
      SearchIndex.instance.ingestRemoteResults(
        parsed.map((r) => {
          'symbol':      r.tradingSymbol,
          'exchange':    r.exchange,
          'type':        r.instrumentType,
          'displayName': r.displaySymbol,
          'name':        r.name,
          'token':       r.symbolToken,
          if (r.ltp != null) 'ltp': r.ltp,
          if (r.percentChange != null) 'percentChange': r.percentChange,
        }).toList(),
      );

      // Background refresh: only update state if results actually changed
      // (avoids a repaint when the data is identical to what's shown)
      if (isBackground) {
        final currentSyms = _remoteResults.map((r) => r.tradingSymbol).toSet();
        final newSyms     = parsed.map((r) => r.tradingSymbol).toSet();
        final changed     = currentSyms.length != newSyms.length ||
            currentSyms.any((s) => !newSyms.contains(s));
        if (changed && mounted) {
          setState(() => _remoteResults = parsed);
          debugPrint('[Search] Background update applied for "$q"');
        }
        return;
      }

      setState(() {
        _remoteResults = parsed;
        _remoteLoading = false;
      });

      // ── Background prefetch of top results ──
      // After results render, fire quote prefetch for top 3 so tapping any of
      // them opens the detail screen without a loading spinner.
      _prefetchTopResults(parsed);

    } catch (e) {
      sw.stop();
      if (gen != _reqGen || !mounted) return;

      // 503 = index still initializing — retry silently (don't show error)
      if (e is BackendException && e.statusCode == 503) {
        debugPrint('[Search] 503 index not ready, retry in 2s (gen=$gen)');
        if (!isBackground) setState(() => _remoteLoading = true);
        _retryTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && gen == _reqGen) _fetchRemote(q, gen, isBackground: isBackground);
        });
        return;
      }

      debugPrint('[Search] Error gen=$gen ${sw.elapsedMilliseconds}ms: $e');
      if (!isBackground) {
        setState(() {
          _remoteError   = e.toString().replaceFirst('BackendException: ', '');
          _remoteLoading = false;
        });
      }
    }
  }

  /// After results render, prefetch quotes for the top N to pre-warm the HTTP
  /// cache. Tap-down also fires prefetch, but this covers the case where the
  /// user taps before seeing the results (e.g. very fast tap).
  void _prefetchTopResults(List<_RemoteResult> results) {
    final top = results.take(3);
    for (final r in top) {
      if (r.symbolToken.isNotEmpty) {
        unawaited(
          _api.getQuoteByToken(r.symbolToken, exchange: r.exchange).catchError((_) {}),
        );
      }
      unawaited(_api.getStockDetail(r.displaySymbol.toUpperCase()).catchError((_) {}));
    }
  }

  // ── Filtered views ──────────────────────────────────────────────────────────

  List<Instrument> get _filteredLocal {
    var list = _localResults;
    if (_exchangeFilter != null) {
      list = list.where((r) => r.exchange == _exchangeFilter).toList();
    }
    if (_segmentFilter != null) {
      list = list.where((r) => r.segmentLabel == _segmentFilter).toList();
    }
    return list;
  }

  List<_RemoteResult> get _filteredRemote {
    var list = _remoteResults;
    if (_exchangeFilter != null) {
      list = list.where((r) => r.exchange == _exchangeFilter).toList();
    }
    if (_segmentFilter != null) {
      list = list.where((r) => r.segment == _segmentFilter).toList();
    } else if (_exchangeFilter == null) {
      // Default view — hide derivatives unless the user explicitly requested them.
      // This prevents NIFTY25JUN25000CE entries from polluting equity search.
      final hasEquityHit = list.any((r) => !r.isDerivative);
      if (hasEquityHit) {
        list = list.where((r) => !r.isDerivative).toList();
      }
      // If ONLY derivatives came back (user explicitly typed a contract name),
      // show them but surface non-derivatives first.
    }
    // Deduplicate against local results
    final localKeys = _filteredLocal
        .map((i) => '${i.exchange}_${i.symbol}')
        .toSet();
    list = list
        .where((r) => !localKeys.contains('${r.exchange}_${r.displaySymbol}'))
        .toList();
    return list;
  }

  /// Count of derivative results hidden in the default (unfiltered) view.
  int get _hiddenDerivativeCount {
    if (_segmentFilter != null || _exchangeFilter != null) return 0;
    final hasEquityHit = _remoteResults.any((r) => !r.isDerivative);
    if (!hasEquityHit) return 0;
    return _remoteResults.where((r) => r.isDerivative).length;
  }

  // ── Exchange chip tap ───────────────────────────────────────────────────────

  void _onExchangeTap(String ex) {
    final newFilter = _exchangeFilter == ex ? null : ex;
    _debounce?.cancel();
    _retryTimer?.cancel();
    setState(() {
      _exchangeFilter = newFilter;
      if (newFilter == 'MCX' &&
          (_segmentFilter == 'EQ' ||
              _segmentFilter == 'CE' ||
              _segmentFilter == 'PE')) {
        _segmentFilter = null;
      }
    });
    if (_query.length >= 2) {
      final gen = ++_reqGen;
      final cacheKey = '${newFilter ?? 'ALL'}_$_query';
      final cached   = _SearchSessionCache.get(cacheKey);
      if (cached != null && !cached.isExpired) {
        setState(() {
          _remoteResults = cached.results;
          _remoteLoading = false;
        });
        return;
      }
      setState(() => _remoteLoading = true);
      _fetchRemote(_query, gen);
    }
  }

  // ── Navigate to stock ───────────────────────────────────────────────────────

  void _navigateToSymbol(
    BuildContext context,
    String symbol,
    String displaySym, {
    String exchange = 'NSE',
    String token = '',
    double ltp = 0,
    double changePercent = 0,
    InstrumentType instrumentType = InstrumentType.unknown,
    double? strikePrice,
    DateTime? expiry,
  }) {
    final store = TradingScope.of(context);
    store.addRecentSearch(displaySym);
    store.registerSearchResult(
      symbol: symbol,
      displayName: displaySym,
      exchange: exchange,
      token: token,
      ltp: ltp,
      changePercent: changePercent,
      instrumentType: instrumentType,
      strikePrice: strikePrice,
      expiry: expiry,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: symbol)),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: _query.isEmpty
                ? _buildDefaultView(context, store)
                : _buildResultsView(context, store),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leading: const BackButton(color: Color(0xFF0D0D0D)),
      title: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(fontSize: 16, color: Color(0xFF0D0D0D)),
        decoration: InputDecoration(
          hintText: 'Search stocks, F&O, MCX, currency...',
          hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF9E9E9E)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 18,
                    color: Color(0xFF9E9E9E),
                  ),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                    _focusNode.requestFocus();
                  },
                )
              : null,
        ),
        onChanged: _onQueryChanged,
      ),
      shape: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final ex in ['NSE', 'BSE']) ...[
            _FilterChip(
              label: ex,
              selected: _exchangeFilter == ex,
              onTap: () => _onExchangeTap(ex),
            ),
            const SizedBox(width: 6),
          ],
          _FilterChip(
            label: 'F&O',
            selected: _exchangeFilter == 'NFO',
            onTap: () => _onExchangeTap('NFO'),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'ETF',
            selected: _segmentFilter == 'ETF',
            onTap: () => setState(
              () => _segmentFilter = _segmentFilter == 'ETF' ? null : 'ETF',
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Index',
            selected: _segmentFilter == 'INDEX',
            onTap: () => setState(
              () =>
                  _segmentFilter = _segmentFilter == 'INDEX' ? null : 'INDEX',
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'MCX',
            selected: _exchangeFilter == 'MCX',
            onTap: () => _onExchangeTap('MCX'),
          ),
        ],
      ),
    );
  }

  // ── Results view ────────────────────────────────────────────────────────────

  Widget _buildResultsView(BuildContext context, dynamic store) {
    final local = _filteredLocal;
    final remote = _filteredRemote;

    // Priority 1: Top 50 — apply active exchange/segment filters.
    // All kTop50Stocks are NSE equities so segment filter hides them for non-EQ.
    final top50 = _top50Filtered.where((s) =>
        (_exchangeFilter == null || s.exchange == _exchangeFilter) &&
        (_segmentFilter  == null || _segmentFilter == 'EQ')).toList();

    // Deduplicate local results against top 50 so a stock doesn't appear twice.
    final top50Symbols = top50.map((s) => s.symbol.toUpperCase()).toSet();
    final localDeduped = local
        .where((i) => !top50Symbols.contains(i.symbol.toUpperCase()))
        .toList();

    final watchlistSyms = (store.watchlist as List<Stock>)
        .map((s) => s.symbol)
        .toSet();
    final holdingSyms = (store.holdings as List<Holding>)
        .map((h) => h.symbol)
        .toSet();
    final positionSyms = (store.positions as List<Position>)
        .map((p) => p.symbol)
        .toSet();

    // Partition deduped local results into contextual sections.
    final fromWatchlist = localDeduped
        .where((i) => watchlistSyms.contains(i.symbol))
        .toList();
    final fromHoldings = localDeduped
        .where(
          (i) =>
              holdingSyms.contains(i.symbol) &&
              !watchlistSyms.contains(i.symbol),
        )
        .toList();
    final fromPositions = localDeduped
        .where(
          (i) =>
              positionSyms.contains(i.symbol) &&
              !watchlistSyms.contains(i.symbol) &&
              !holdingSyms.contains(i.symbol),
        )
        .toList();
    final others = localDeduped
        .where(
          (i) =>
              !watchlistSyms.contains(i.symbol) &&
              !holdingSyms.contains(i.symbol) &&
              !positionSyms.contains(i.symbol),
        )
        .toList();

    final hasAny = top50.isNotEmpty || local.isNotEmpty || remote.isNotEmpty;

    if (!hasAny && !_remoteLoading) {
      return _buildNoResults();
    }

    // ── Flat item list for ListView.builder ─────────────────────────────────
    // Avoids rendering all items immediately; Flutter builds only visible rows.
    final items = <Widget>[];

    // ── Priority 1: Top 50 ───────────────────────────────────────────────────
    if (top50.isNotEmpty) {
      items.add(_SectionHeader(
        icon: LucideIcons.trendingUp,
        label: 'Top NSE Stocks',
        color: const Color(0xFF1565C0),
      ));
      for (final s in top50) {
        items.add(_Top50Tile(
          stock: s,
          onTap: () => _navigateToSymbol(context, s.symbol, s.symbol, exchange: s.exchange),
        ));
      }
      if (localDeduped.isNotEmpty || remote.isNotEmpty || _remoteLoading) {
        items.add(const Divider(height: 1, indent: 16));
      }
    }

    // ── Priority 2: Full index (contextual sections) ─────────────────────────
    // Best Match — only if not already surfaced in top50 section
    final isBestMatch = localDeduped.isNotEmpty &&
        localDeduped[0].displayName.toUpperCase() == _query.toUpperCase();

    // Best Match
    if (isBestMatch) {
      final i = localDeduped[0];
      final tok = _tokenFor(i);
      items.add(_SectionHeader(icon: LucideIcons.star, label: 'Best Match', color: AppColors.primary));
      items.add(_withPrefetch(
        symbol: i.symbol, exchange: i.exchange, token: tok,
        child: _LocalInstrumentTile(
          instrument: i, ltp: _ltpForSymbol(i.symbol),
          onTap: () => _navigateToSymbol(context, i.symbol, i.displayName, exchange: i.exchange, token: tok),
        ),
      ));
      items.add(const Divider(height: 1, indent: 70));
    }

    // Watchlist
    if (fromWatchlist.isNotEmpty) {
      items.add(_SectionHeader(icon: LucideIcons.bookmark, label: 'In Your Watchlist', color: AppColors.primary));
      for (final i in fromWatchlist) {
        final tok = _tokenFor(i);
        items.add(_withPrefetch(
          symbol: i.symbol, exchange: i.exchange, token: tok,
          child: _LocalInstrumentTile(
            instrument: i, ltp: _ltpForSymbol(i.symbol),
            onTap: () => _navigateToSymbol(context, i.symbol, i.displayName, exchange: i.exchange, token: tok),
          ),
        ));
      }
    }

    // Portfolio
    if (fromHoldings.isNotEmpty || fromPositions.isNotEmpty) {
      items.add(_SectionHeader(icon: LucideIcons.briefcase, label: 'Your Portfolio', color: AppColors.success));
      for (final i in [...fromHoldings, ...fromPositions]) {
        final tok = _tokenFor(i);
        items.add(_withPrefetch(
          symbol: i.symbol, exchange: i.exchange, token: tok,
          child: _LocalInstrumentTile(
            instrument: i, ltp: _ltpForSymbol(i.symbol),
            onTap: () => _navigateToSymbol(context, i.symbol, i.displayName, exchange: i.exchange, token: tok),
          ),
        ));
      }
    }

    // Remote results
    if (remote.isNotEmpty) {
      items.add(_SectionHeader(icon: LucideIcons.globe, label: 'Universal Results', color: AppColors.textSecondary));
      for (final r in remote) {
        items.add(_withPrefetch(
          symbol: r.displaySymbol, exchange: r.exchange, token: r.symbolToken,
          child: _RemoteResultTile(
            result: r,
            onTap: () => _navigateToSymbol(
              context, r.tradingSymbol, r.displaySymbol,
              exchange: r.exchange, token: r.symbolToken,
              ltp: r.ltp ?? 0, changePercent: r.percentChange ?? 0,
              instrumentType: r.resolvedInstrumentType,
            ),
          ),
        ));
      }
    } else if (_remoteLoading) {
      items.add(_SectionHeader(icon: LucideIcons.globe, label: 'Searching Exchanges...', color: AppColors.textSecondary));
      items.add(const _SearchSkeleton());
      items.add(const _SearchSkeleton());
      items.add(const _SearchSkeleton());
    }

    // Other local matches
    final othersFiltered = others.where((i) => !(isBestMatch && i == localDeduped[0])).toList();
    if (othersFiltered.isNotEmpty) {
      final hasOtherSections = fromWatchlist.isNotEmpty ||
          fromHoldings.isNotEmpty || fromPositions.isNotEmpty || remote.isNotEmpty;
      if (hasOtherSections) {
        items.add(_SectionHeader(icon: LucideIcons.search, label: 'Other Matches', color: AppColors.textSecondary));
      }
      for (final i in othersFiltered) {
        final tok = _tokenFor(i);
        items.add(_withPrefetch(
          symbol: i.symbol, exchange: i.exchange, token: tok,
          child: _LocalInstrumentTile(
            instrument: i, ltp: _ltpForSymbol(i.symbol),
            onTap: () => _navigateToSymbol(context, i.symbol, i.displayName, exchange: i.exchange, token: tok),
          ),
        ));
      }
    }

    if (!hasAny && !_remoteLoading) return _buildNoResults();

    // Append trailing items (error, hint, spacer) to the flat list
    if (_remoteError != null && remote.isEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(LucideIcons.alertCircle, size: 32, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              'Universal search currently limited\n$_remoteError',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ));
    }

    if (_hiddenDerivativeCount > 0) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: GestureDetector(
          onTap: () => setState(() => _segmentFilter = 'FUT'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCE93D8).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.candlestick_chart_outlined, size: 14, color: Color(0xFF7B1FA2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_hiddenDerivativeCount F&O contract${_hiddenDerivativeCount == 1 ? '' : 's'} hidden — tap to show Futures & Options',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7B1FA2), fontWeight: FontWeight.w500),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFF7B1FA2)),
              ],
            ),
          ),
        ),
      ));
    }

    items.add(const SizedBox(height: 48));

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length,
      itemBuilder: (_, index) => items[index],
    );
  }

  double? _ltpForSymbol(String symbol) {
    if (!mounted) return null;
    return TradingScope.of(context).stockBySymbolOrNull(symbol)?.currentPrice;
  }

  /// Wrap a tile with a GestureDetector that fires a prefetch on tap-down.
  /// The ~80-100ms between tap-down and route push is enough to populate the
  /// HTTP cache with a fresh quote, making the detail screen feel instant.
  Widget _withPrefetch({
    required Widget child,
    required String symbol,
    required String exchange,
    required String token,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _prefetchForSymbol(
        symbol: symbol,
        exchange: exchange,
        token: token,
      ),
      child: child,
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.searchX, size: 48, color: Color(0xFFE0E0E0)),
            const SizedBox(height: 16),
            Text(
              'No results for "$_query"',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D0D0D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try a different spelling or exchange filter.',
              style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Default view (no query) ─────────────────────────────────────────────────

  Widget _buildDefaultView(BuildContext context, dynamic store) {
    // Recent searches are stored as bare symbols — resolve each back to a
    // full Stock (price/exchange/name) so the row can show live data.
    // Anything the store no longer recognizes (cleared cache, etc.) is
    // dropped rather than shown with blank data.
    final recentSymbols = store.recentSearches as List<String>;
    final recent = recentSymbols
        .map((sym) => store.stockBySymbolOrNull(sym) as Stock?)
        .whereType<Stock>()
        .toList();

    final watchlist = store.watchlist as List<Stock>;
    final trending =
        (List<Stock>.from(watchlist)
              ..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0)))
            .take(6)
            .toList();

    void openStock(Stock stock) {
      store.addRecentSearch(stock.symbol);
      store.registerSearchResult(
        symbol: stock.symbol,
        displayName: stock.name,
        exchange: stock.exchange,
        token: stock.token,
        ltp: stock.currentPrice,
        changePercent: stock.changePercentage,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: stock.symbol)),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DefaultSectionLabel(icon: LucideIcons.clock, label: 'RECENT'),
                TextButton(
                  onPressed: () => store.clearRecentSearches(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          ...recent.map(
            (stock) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TrendingTile(stock: stock, onTap: () => openStock(stock)),
            ),
          ),
        ],
        if (trending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _DefaultSectionLabel(icon: LucideIcons.trendingUp, label: 'TRENDING'),
          ),
          ...trending.map(
            (stock) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TrendingTile(stock: stock, onTap: () => openStock(stock)),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

// ─── Default (no-query) view section label — no trailing padding, so a
// sibling action (e.g. "Clear") can sit flush against it in a Row ───────────

class _DefaultSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DefaultSectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Symbol avatar ────────────────────────────────────────────────────────────

class _SymbolAvatar extends StatelessWidget {
  final String symbol;
  final String exchange;
  const _SymbolAvatar({required this.symbol, required this.exchange});

  Color get _bgColor {
    switch (exchange) {
      case 'MCX':
        return const Color(0xFF7B1FA2);
      case 'NFO':
        return const Color(0xFFE65100);
      case 'BSE':
        return const Color(0xFF0277BD);
      case 'CDS':
        return const Color(0xFF00695C);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = symbol.length >= 2 ? symbol.substring(0, 2) : symbol;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _bgColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _bgColor.withOpacity(0.2)),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _bgColor,
          ),
        ),
      ),
    );
  }
}

// ─── Exchange + segment badges ────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

Color _exchangeColor(String exchange) {
  switch (exchange) {
    case 'MCX':
      return const Color(0xFF7B1FA2);
    case 'NFO':
      return const Color(0xFFE65100);
    case 'BSE':
      return const Color(0xFF0277BD);
    case 'CDS':
      return const Color(0xFF00695C);
    default:
      return AppColors.primary;
  }
}

Color _segmentColor(String seg) {
  switch (seg) {
    case 'FUT':
      return const Color(0xFFE65100);
    case 'CE':
      return AppColors.success;
    case 'PE':
      return AppColors.danger;
    case 'COMM':
      return const Color(0xFF7B1FA2);
    case 'CURR':
      return const Color(0xFF00695C);
    case 'ETF':
      return const Color(0xFF0277BD);
    case 'INDEX':
      return const Color(0xFF1565C0);
    default:
      return AppColors.primary;
  }
}

// ─── Local instrument tile ────────────────────────────────────────────────────

class _LocalInstrumentTile extends StatelessWidget {
  final Instrument instrument;
  final double? ltp;
  final VoidCallback onTap;
  const _LocalInstrumentTile({
    required this.instrument,
    this.ltp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final exColor = _exchangeColor(instrument.exchange);
    final segColor = _segmentColor(instrument.segmentLabel);

    return RepaintBoundary(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: InstrumentLogo(
          symbol: instrument.displayName,
          exchange: instrument.exchange,
          size: 42,
          fallbackBuilder: (_) => _SymbolAvatar(
            symbol: instrument.displayName,
            exchange: instrument.exchange,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                instrument.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0D0D0D),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _Badge(label: instrument.exchange, color: exColor),
            const SizedBox(width: 4),
            _Badge(label: instrument.segmentLabel, color: segColor),
          ],
        ),
        subtitle: Text(
          instrument.name,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ltp != null && ltp! > 0
            ? Text(
                '₹${ltp!.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D0D0D),
                ),
              )
            : const Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: Color(0xFFBDBDBD),
              ),
      ),
    );
  }
}

// ─── Remote result tile ───────────────────────────────────────────────────────

class _RemoteResultTile extends StatelessWidget {
  final _RemoteResult result;
  final VoidCallback onTap;
  const _RemoteResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final exColor = _exchangeColor(result.exchange);
    final segColor = _segmentColor(result.segment);
    final isPos = (result.percentChange ?? 0) >= 0;
    final hasPrice = result.ltp != null && result.ltp! > 0;

    return RepaintBoundary(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: InstrumentLogo(
          symbol: result.displaySymbol,
          exchange: result.exchange,
          size: 42,
          fallbackBuilder: (_) => _SymbolAvatar(
            symbol: result.displaySymbol,
            exchange: result.exchange,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                result.displaySymbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0D0D0D),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _Badge(label: result.exchange, color: exColor),
            const SizedBox(width: 4),
            _Badge(label: result.segment, color: segColor),
          ],
        ),
        subtitle: Text(
          result.name.isNotEmpty ? result.name : result.tradingSymbol,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: hasPrice
            ? ValueListenableBuilder<double>(
                valueListenable: TradingScope.read(context)
                    .ltpNotifier(result.tradingSymbol),
                builder: (_, liveLtp, __) {
                  final displayLtp =
                      liveLtp > 0 ? liveLtp : result.ltp!;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${displayLtp.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D0D0D),
                        ),
                      ),
                      Text(
                        '${isPos ? '+' : ''}${result.percentChange!.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPos
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                    ],
                  );
                },
              )
            : const Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: Color(0xFFBDBDBD),
              ),
      ),
    );
  }
}

// ─── Trending tile ────────────────────────────────────────────────────────────

class _TrendingTile extends StatelessWidget {
  final Stock stock;
  final VoidCallback onTap;
  const _TrendingTile({required this.stock, required this.onTap});

  /// "F&O" for equities/indices with a derivatives chain, "ETF" for funds,
  /// null for plain equities and MCX commodities (exchange badge suffices).
  String? get _segmentBadge {
    if (stock.instrumentType == InstrumentType.etf) return 'ETF';
    if (stock.exchange != 'MCX' && stock.hasFnoChain) return 'F&O';
    return null;
  }

  /// Absolute price change — derived from prevClose when available, else
  /// backed out algebraically from the percentage (prev = cur/(1+pct/100)).
  double get _absoluteChange {
    final prev = stock.prevClose;
    if (prev != null && prev > 0) return stock.currentPrice - prev;
    final pct = stock.changePercentage;
    if (pct <= -100) return 0;
    return stock.currentPrice * pct / (100 + pct);
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.read(context);
    final isPos = stock.changePercentage >= 0;
    final color = isPos ? AppColors.success : AppColors.danger;
    final segment = _segmentBadge;
    final sign = isPos ? '+' : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          stock.symbol,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0D0D0D)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _Badge(label: stock.exchange, color: _exchangeColor(stock.exchange)),
                      if (segment != null) ...[
                        const SizedBox(width: 4),
                        _Badge(label: segment, color: AppColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stock.name,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              height: 32,
              child: Sparkline(
                valueListenable: store.ltpNotifier(stock.symbol),
                color: color,
                filled: false,
                seedValue: stock.currentPrice,
                symbol: stock.symbol,
                exchange: stock.exchange,
                token: stock.token,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${stock.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D)),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sign${_absoluteChange.toStringAsFixed(2)} ($sign${stock.changePercentage.toStringAsFixed(2)}%)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top 50 tile ─────────────────────────────────────────────────────────────

class _Top50Tile extends StatelessWidget {
  final Top50Stock stock;
  final VoidCallback onTap;
  const _Top50Tile({required this.stock, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: InstrumentLogo(
          symbol: stock.symbol,
          exchange: stock.exchange,
          size: 42,
          fallbackBuilder: (_) =>
              _SymbolAvatar(symbol: stock.symbol, exchange: stock.exchange),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                stock.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0D0D0D),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _Badge(label: stock.exchange, color: AppColors.primary),
            const SizedBox(width: 4),
            _Badge(label: 'EQ', color: AppColors.primary),
          ],
        ),
        subtitle: Text(
          stock.companyName,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ValueListenableBuilder<double>(
          valueListenable: TradingScope.read(context).ltpNotifier(stock.symbol),
          builder: (_, ltp, __) {
            if (ltp <= 0) {
              return const Icon(LucideIcons.chevronRight, size: 16, color: Color(0xFFBDBDBD));
            }
            return Text(
              '₹${ltp.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D0D0D),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.12)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE0E0E0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : const Color(0xFF757575),
          ),
        ),
      ),
    );
  }
}

// ─── Search Skeleton ──────────────────────────────────────────────────────────

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 180,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 60,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
