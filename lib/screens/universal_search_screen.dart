import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../search/search_index.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

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
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  final _focusNode = FocusNode();

  String _query = '';
  String? _exchangeFilter; // null = All
  String? _segmentFilter;

  // Local catalog results (instant)
  List<Instrument> _localResults = [];

  // Remote API results (enriched with LTP)
  List<_RemoteResult> _remoteResults = [];
  bool _remoteLoading = false;
  String? _remoteError;

  // Cache to avoid duplicate requests
  final Map<String, List<_RemoteResult>> _searchCache = {};

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Seed context into search index
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedContext());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _seedContext() {
    if (!mounted) return;
    final store = TradingScope.of(context);
    SearchIndex.instance.updateContext(
      watchlist: store.watchlist.map((s) => s.symbol).toSet(),
      holdings: store.holdings.map((h) => h.symbol).toSet(),
      positions: store.positions.map((p) => p.symbol).toSet(),
      recent: List<String>.from(store.recentSearches),
    );
  }

  // ── Query handling ──────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      _remoteError = null;
    });

    // Clear results for empty or single-char queries — no API call
    if (q.length < 2) {
      setState(() {
        _localResults = [];
        _remoteResults = [];
        _remoteLoading = false;
      });
      return;
    }

    // Instant local results — no debounce needed (pure in-memory)
    final local = SearchIndex.instance.search(q, limit: 20);
    setState(() {
      _localResults = local;
    });

    // Remote enrichment — 350ms debounce to avoid spamming the API
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchRemote(q));
  }

  Future<void> _fetchRemote(String q) async {
    if (q.isEmpty || q.length < 2) return;

    // Check cache first — avoids duplicate API calls for the same query
    final cacheKey = '${_exchangeFilter ?? 'ALL'}_$q';
    if (_searchCache.containsKey(cacheKey)) {
      setState(() {
        _remoteResults = _searchCache[cacheKey]!;
        _remoteLoading = false;
        _remoteError = null;
      });
      return;
    }

    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });

    try {
      final results = await _api.searchUniversal(q, exchange: _exchangeFilter);

      // Stale response guard: discard if query has changed since request was sent
      if (_query != q || !mounted) return;

      final parsed = results.map(_RemoteResult.fromJson).toList();
      _searchCache[cacheKey] = parsed;

      setState(() {
        _remoteResults = parsed;
        _remoteLoading = false;
      });
    } catch (e) {
      if (_query != q || !mounted) return;
      setState(() {
        _remoteError = e.toString().replaceFirst('BackendException: ', '');
        _remoteLoading = false;
      });
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
    setState(() {
      _exchangeFilter = newFilter;
      if (newFilter == 'MCX' &&
          (_segmentFilter == 'EQ' ||
              _segmentFilter == 'CE' ||
              _segmentFilter == 'PE')) {
        _segmentFilter = null;
      }
    });
    if (_query.length >= 2) _fetchRemote(_query);
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
          _FilterChip(
            label: 'All',
            selected: _exchangeFilter == null,
            onTap: () {
              if (_exchangeFilter != null) {
                setState(() => _exchangeFilter = null);
                if (_query.length >= 2) _fetchRemote(_query);
              }
            },
          ),
          const SizedBox(width: 6),
          for (final ex in ['NSE', 'BSE', 'NFO', 'MCX', 'CDS']) ...[
            _FilterChip(
              label: ex,
              selected: _exchangeFilter == ex,
              onTap: () => _onExchangeTap(ex),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            width: 1,
            height: 18,
            color: const Color(0xFFE0E0E0),
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          if (_exchangeFilter != 'MCX' && _exchangeFilter != 'CDS') ...[
            _FilterChip(
              label: 'EQ',
              selected: _segmentFilter == 'EQ',
              onTap: () => setState(
                () => _segmentFilter = _segmentFilter == 'EQ' ? null : 'EQ',
              ),
            ),
            const SizedBox(width: 6),
          ],
          _FilterChip(
            label: 'FUT',
            selected: _segmentFilter == 'FUT',
            onTap: () => setState(
              () => _segmentFilter = _segmentFilter == 'FUT' ? null : 'FUT',
            ),
          ),
          if (_exchangeFilter != 'MCX' && _exchangeFilter != 'CDS') ...[
            const SizedBox(width: 6),
            _FilterChip(
              label: 'CE',
              selected: _segmentFilter == 'CE',
              onTap: () => setState(
                () => _segmentFilter = _segmentFilter == 'CE' ? null : 'CE',
              ),
            ),
            const SizedBox(width: 6),
            _FilterChip(
              label: 'PE',
              selected: _segmentFilter == 'PE',
              onTap: () => setState(
                () => _segmentFilter = _segmentFilter == 'PE' ? null : 'PE',
              ),
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
              label: 'INDEX',
              selected: _segmentFilter == 'INDEX',
              onTap: () => setState(
                () =>
                    _segmentFilter = _segmentFilter == 'INDEX' ? null : 'INDEX',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Results view ────────────────────────────────────────────────────────────

  Widget _buildResultsView(BuildContext context, dynamic store) {
    final local = _filteredLocal;
    final remote = _filteredRemote;
    final watchlistSyms = (store.watchlist as List<Stock>)
        .map((s) => s.symbol)
        .toSet();
    final holdingSyms = (store.holdings as List<Holding>)
        .map((h) => h.symbol)
        .toSet();
    final positionSyms = (store.positions as List<Position>)
        .map((p) => p.symbol)
        .toSet();

    // Partition local results into sections
    final fromWatchlist = local
        .where((i) => watchlistSyms.contains(i.symbol))
        .toList();
    final fromHoldings = local
        .where(
          (i) =>
              holdingSyms.contains(i.symbol) &&
              !watchlistSyms.contains(i.symbol),
        )
        .toList();
    final fromPositions = local
        .where(
          (i) =>
              positionSyms.contains(i.symbol) &&
              !watchlistSyms.contains(i.symbol) &&
              !holdingSyms.contains(i.symbol),
        )
        .toList();
    final others = local
        .where(
          (i) =>
              !watchlistSyms.contains(i.symbol) &&
              !holdingSyms.contains(i.symbol) &&
              !positionSyms.contains(i.symbol),
        )
        .toList();

    final hasAny = local.isNotEmpty || remote.isNotEmpty;

    if (!hasAny && !_remoteLoading) {
      return _buildNoResults();
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // ── Top Match (Exact match boost) ──────────────────────────────────
        if (local.isNotEmpty &&
            local[0].displayName.toUpperCase() == _query.toUpperCase()) ...[
          _SectionHeader(
            icon: LucideIcons.star,
            label: 'Best Match',
            color: AppColors.primary,
          ),
          _LocalInstrumentTile(
            instrument: local[0],
            ltp: _ltpForSymbol(local[0].symbol),
            onTap: () => _navigateToSymbol(
              context,
              local[0].symbol,
              local[0].displayName,
              exchange: local[0].exchange,
            ),
          ),
          const Divider(height: 1, indent: 70),
        ],

        // ── Watchlist section ──────────────────────────────────────────────
        if (fromWatchlist.isNotEmpty) ...[
          _SectionHeader(
            icon: LucideIcons.bookmark,
            label: 'In Your Watchlist',
            color: AppColors.primary,
          ),
          ...fromWatchlist.map(
            (i) => _LocalInstrumentTile(
              instrument: i,
              ltp: _ltpForSymbol(i.symbol),
              onTap: () => _navigateToSymbol(
                context,
                i.symbol,
                i.displayName,
                exchange: i.exchange,
              ),
            ),
          ),
        ],

        // ── Holdings & Positions ───────────────────────────────────────────
        if (fromHoldings.isNotEmpty || fromPositions.isNotEmpty) ...[
          _SectionHeader(
            icon: LucideIcons.briefcase,
            label: 'Your Portfolio',
            color: AppColors.success,
          ),
          ...fromHoldings.map(
            (i) => _LocalInstrumentTile(
              instrument: i,
              ltp: _ltpForSymbol(i.symbol),
              onTap: () => _navigateToSymbol(
                context,
                i.symbol,
                i.displayName,
                exchange: i.exchange,
              ),
            ),
          ),
          ...fromPositions.map(
            (i) => _LocalInstrumentTile(
              instrument: i,
              ltp: _ltpForSymbol(i.symbol),
              onTap: () => _navigateToSymbol(
                context,
                i.symbol,
                i.displayName,
                exchange: i.exchange,
              ),
            ),
          ),
        ],

        // ── Global Search Results ──────────────────────────────────────────
        if (remote.isNotEmpty) ...[
          _SectionHeader(
            icon: LucideIcons.globe,
            label: 'Universal Results',
            color: AppColors.textSecondary,
          ),
          ...remote.map(
            (r) => _RemoteResultTile(
              result: r,
              onTap: () => _navigateToSymbol(
                context,
                r.tradingSymbol,
                r.displaySymbol,
                exchange: r.exchange,
                token: r.symbolToken,
                ltp: r.ltp ?? 0,
                changePercent: r.percentChange ?? 0,
                instrumentType: r.resolvedInstrumentType,
              ),
            ),
          ),
        ] else if (_remoteLoading) ...[
          _SectionHeader(
            icon: LucideIcons.globe,
            label: 'Searching Exchanges...',
            color: AppColors.textSecondary,
          ),
          const _SearchSkeleton(),
          const _SearchSkeleton(),
          const _SearchSkeleton(),
        ],

        // ── Other Local matches ────────────────────────────────────────────
        if (others.isNotEmpty &&
            others.length >
                (local[0].displayName.toUpperCase() == _query.toUpperCase()
                    ? 1
                    : 0)) ...[
          if (fromWatchlist.isNotEmpty ||
              fromHoldings.isNotEmpty ||
              fromPositions.isNotEmpty ||
              remote.isNotEmpty)
            _SectionHeader(
              icon: LucideIcons.search,
              label: 'Other Matches',
              color: AppColors.textSecondary,
            ),
          ...others
              .where((i) => i != (local.isNotEmpty ? local[0] : null))
              .map(
                (i) => _LocalInstrumentTile(
                  instrument: i,
                  ltp: _ltpForSymbol(i.symbol),
                  onTap: () => _navigateToSymbol(
                    context,
                    i.symbol,
                    i.displayName,
                    exchange: i.exchange,
                  ),
                ),
              ),
        ],

        if (_remoteError != null && remote.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 32,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 12),
                Text(
                  'Universal search currently limited\n$_remoteError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        // ── F&O hint row ───────────────────────────────────────────────────
        if (_hiddenDerivativeCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: GestureDetector(
              onTap: () => setState(() => _segmentFilter = 'FUT'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFCE93D8).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.candlestick_chart_outlined,
                      size: 14,
                      color: Color(0xFF7B1FA2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_hiddenDerivativeCount F&O contract${_hiddenDerivativeCount == 1 ? '' : 's'} hidden — tap to show Futures & Options',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7B1FA2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Color(0xFF7B1FA2),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 48),
      ],
    );
  }

  double? _ltpForSymbol(String symbol) {
    if (!mounted) return null;
    final store = TradingScope.of(context);
    final stock = store.stockBySymbolOrNull(symbol);
    return stock?.currentPrice;
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
    final recent = store.recentSearches as List<String>;
    final watchlist = store.watchlist as List<Stock>;
    final trending =
        (List<Stock>.from(watchlist)
              ..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0)))
            .take(6)
            .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Recent searches
        if (recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D0D0D),
                ),
              ),
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recent
                .map(
                  (sym) => ActionChip(
                    label: Text(sym, style: const TextStyle(fontSize: 12)),
                    avatar: const Icon(LucideIcons.clock, size: 13),
                    onPressed: () {
                      _controller.text = sym;
                      _onQueryChanged(sym);
                    },
                    backgroundColor: AppColors.surfaceAlt,
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        // Trending
        if (trending.isNotEmpty) ...[
          const Text(
            'Trending',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D0D0D),
            ),
          ),
          const SizedBox(height: 8),
          ...trending.map(
            (stock) => _TrendingTile(
              stock: stock,
              onTap: () {
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
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(symbol: stock.symbol),
                  ),
                );
              },
            ),
          ),
        ] else ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Search across NSE, BSE, NFO, MCX, CDS\nEquities · F&O · Commodities · Currency · ETFs',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9E9E9E),
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

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
        leading: _SymbolAvatar(
          symbol: instrument.displayName,
          exchange: instrument.exchange,
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
        leading: _SymbolAvatar(
          symbol: result.displaySymbol,
          exchange: result.exchange,
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
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${result.ltp!.toStringAsFixed(2)}',
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
                      color: isPos ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
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

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: _SymbolAvatar(symbol: stock.symbol, exchange: stock.exchange),
      title: Text(
        stock.symbol,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Color(0xFF0D0D0D),
        ),
      ),
      subtitle: Text(
        stock.name,
        style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${stock.currentPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D0D0D),
            ),
          ),
          Text(
            '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isPos ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
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
