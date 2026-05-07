import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

// ─── Search result model ──────────────────────────────────────────────────────

class ScripResult {
  final String exchange;
  final String tradingSymbol;
  final String symbolToken;
  final String name;
  final String instrumentType;
  double? ltp;
  double? percentChange;
  double? netChange;

  ScripResult({
    required this.exchange,
    required this.tradingSymbol,
    required this.symbolToken,
    this.name = '',
    this.instrumentType = '',
    this.ltp,
    this.percentChange,
    this.netChange,
  });

  factory ScripResult.fromJson(Map<String, dynamic> j) {
    final sym = (j['tradingSymbol'] ?? j['tradingsymbol'] ?? '') as String;
    final tok = (j['symbolToken'] ?? j['symboltoken'] ?? '').toString();
    final nm  = (j['name'] ?? '') as String;
    return ScripResult(
      exchange:       j['exchange'] as String? ?? 'NSE',
      tradingSymbol:  sym,
      symbolToken:    tok,
      name:           nm,
      instrumentType: j['instrumentType'] as String? ?? '',
    );
  }

  /// Display name — strips equity suffixes like -EQ, -BE, -BL, -IQ, -RL, -AF
  String get displaySymbol {
    final stripped = tradingSymbol.replaceAll(
      RegExp(r'-(EQ|BE|BL|IQ|RL|AF|U\d+)$'),
      '',
    );
    return stripped.isNotEmpty ? stripped : tradingSymbol;
  }

  bool get isFutures => tradingSymbol.endsWith('FUT') || exchange == 'MCX';
  bool get isOptions =>
      tradingSymbol.endsWith('CE') || tradingSymbol.endsWith('PE');
  bool get isEquity => !isFutures && !isOptions;

  String get segment {
    if (isFutures) return 'FUT';
    if (isOptions) return tradingSymbol.endsWith('CE') ? 'CE' : 'PE';
    return 'EQ';
  }

  /// Dedup key — same symbol on same exchange is one result
  String get _dedupKey => '${exchange}_$tradingSymbol';
}

// ─── All supported exchanges ──────────────────────────────────────────────────

const _kAllExchanges = ['NSE', 'BSE', 'NFO', 'MCX'];

// ─── Screen ───────────────────────────────────────────────────────────────────

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _controller = TextEditingController();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  String _query = '';

  // null = "All" (search every exchange); non-null = filter to that exchange
  String? _exchangeFilter;

  // Segment sub-filter (EQ / FUT / CE / PE)
  String? _segmentFilter;

  List<ScripResult> _results = [];
  bool _searching = false;
  String? _searchError;

  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Query change ────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      _searchError = null;
    });

    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(q),
    );
  }

  // ── Search — fires parallel requests for all (or selected) exchanges ────────

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });

    // Which exchanges to query
    final exchanges =
        _exchangeFilter != null ? [_exchangeFilter!] : _kAllExchanges;

    try {
      // Fire all exchange searches in parallel
      final futures = exchanges.map((ex) => _api
          .searchScrip(q, exchange: ex)
          .then((raw) => raw.map(ScripResult.fromJson).toList())
          .catchError((_) => <ScripResult>[])); // one exchange failing won't kill all

      final lists = await Future.wait(futures);

      // Merge + deduplicate (same symbol on same exchange = one entry)
      final seen = <String>{};
      final merged = <ScripResult>[];
      for (final list in lists) {
        for (final r in list) {
          if (seen.add(r._dedupKey)) merged.add(r);
        }
      }

      // Best-effort: fetch LTP for the very first result
      if (merged.isNotEmpty && merged[0].symbolToken.isNotEmpty) {
        try {
          final quoteRes = await _api.getQuoteByToken(
            merged[0].symbolToken,
            exchange: merged[0].exchange,
          );
          final ltp = (quoteRes['ltp'] as num?)?.toDouble();
          if (ltp != null && ltp > 0) {
            merged[0].ltp = ltp;
            merged[0].percentChange =
                (quoteRes['percentChange'] as num?)?.toDouble();
            merged[0].netChange =
                (quoteRes['netChange'] as num?)?.toDouble();
          }
        } catch (_) {
          // Non-fatal
        }
      }

      setState(() {
        _results = merged;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString().replaceFirst('BackendException: ', '');
        _searching = false;
        _results = [];
      });
    }
  }

  // ── Filtered view ───────────────────────────────────────────────────────────

  List<ScripResult> get _filtered {
    var list = _results;
    // Exchange filter (already applied at search time, but also filter display
    // so switching chips on existing results is instant without re-fetching)
    if (_exchangeFilter != null) {
      list = list.where((r) => r.exchange == _exchangeFilter).toList();
    }
    if (_segmentFilter != null) {
      list = list.where((r) => r.segment == _segmentFilter).toList();
    }
    return list;
  }

  // ── Exchange chip tap ───────────────────────────────────────────────────────

  void _onExchangeTap(String ex) {
    final newFilter = _exchangeFilter == ex ? null : ex; // toggle
    setState(() {
      _exchangeFilter = newFilter;
      // Clear segment filters incompatible with MCX
      if (newFilter == 'MCX' &&
          (_segmentFilter == 'EQ' ||
           _segmentFilter == 'CE' ||
           _segmentFilter == 'PE')) {
        _segmentFilter = null;
      }
    });
    // Re-search so we get full results for the new scope
    if (_query.length >= 2) _search(_query);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: const BackButton(),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search stocks, F&O, MCX commodities...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _query = '';
                  _results = [];
                  _searchError = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filter bar ──────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // "All" chip
                _Chip(
                  label: 'All',
                  selected: _exchangeFilter == null,
                  onTap: () {
                    if (_exchangeFilter != null) {
                      setState(() => _exchangeFilter = null);
                      if (_query.length >= 2) _search(_query);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Per-exchange chips (toggle to narrow)
                ..._kAllExchanges.map((ex) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: ex,
                    selected: _exchangeFilter == ex,
                    onTap: () => _onExchangeTap(ex),
                  ),
                )),

                // Divider
                Container(
                  width: 1,
                  height: 20,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),

                // Segment chips — hide EQ/CE/PE when MCX-only selected
                if (_exchangeFilter != 'MCX') ...[
                  _Chip(
                    label: 'EQ',
                    selected: _segmentFilter == 'EQ',
                    onTap: () => setState(() =>
                        _segmentFilter = _segmentFilter == 'EQ' ? null : 'EQ'),
                  ),
                  const SizedBox(width: 8),
                ],
                _Chip(
                  label: 'FUT',
                  selected: _segmentFilter == 'FUT',
                  onTap: () => setState(() =>
                      _segmentFilter =
                          _segmentFilter == 'FUT' ? null : 'FUT'),
                ),
                if (_exchangeFilter != 'MCX') ...[
                  const SizedBox(width: 8),
                  _Chip(
                    label: 'CE',
                    selected: _segmentFilter == 'CE',
                    onTap: () => setState(() =>
                        _segmentFilter =
                            _segmentFilter == 'CE' ? null : 'CE'),
                  ),
                  const SizedBox(width: 8),
                  _Chip(
                    label: 'PE',
                    selected: _segmentFilter == 'PE',
                    onTap: () => setState(() =>
                        _segmentFilter =
                            _segmentFilter == 'PE' ? null : 'PE'),
                  ),
                ],
              ],
            ),
          ),

          // Result count badge when searching all
          if (_query.length >= 2 && !_searching && _results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '${_filtered.length} result${_filtered.length == 1 ? '' : 's'}'
                '${_exchangeFilter == null ? ' across all exchanges' : ' on $_exchangeFilter'}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ),

          const Divider(height: 1),
          Expanded(child: _buildBody(context, store)),
        ],
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, dynamic store) {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(height: 12),
            Text('Searching all exchanges...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertCircle,
                  size: 36, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(_searchError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _search(_query),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_query.length >= 2) {
      final filtered = _filtered;
      if (filtered.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.searchX,
                  size: 48, color: AppColors.border),
              const SizedBox(height: 12),
              Text('No results for "$_query"',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text(
                'Try removing the exchange or segment filter.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = filtered[index];
          return _ScripTile(
            result: result,
            onTap: () {
              final display = result.displaySymbol;
              final raw = result.tradingSymbol;
              final knownSymbol =
                  store.stockBySymbolOrNull(display) != null ? display : raw;
              store.addRecentSearch(display);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StockDetailScreen(symbol: knownSymbol),
                ),
              );
            },
          );
        },
      );
    }

    return _buildDefaultView(context, store);
  }

  Widget _buildDefaultView(BuildContext context, dynamic store) {
    final recent = store.recentSearches as List<String>;
    final watchlist = store.watchlist as List<Stock>;
    final trending = (List<Stock>.from(watchlist)
          ..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0)))
        .take(5)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Searches',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => store.clearRecentSearches(),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recent
                .map((symbol) => ActionChip(
                      label: Text(symbol),
                      avatar: const Icon(LucideIcons.clock, size: 14),
                      onPressed: () {
                        _controller.text = symbol;
                        _onQueryChanged(symbol);
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        if (trending.isNotEmpty) ...[
          Text('Trending (by volume)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...trending.map((stock) => _WatchlistTile(
                stock: stock,
                onTap: () {
                  store.addRecentSearch(stock.symbol);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StockDetailScreen(symbol: stock.symbol),
                    ),
                  );
                },
              )),
        ] else ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Type at least 2 characters to search\nacross NSE, BSE, NFO and MCX.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, height: 1.6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Tiles ────────────────────────────────────────────────────────────────────

class _ScripTile extends StatelessWidget {
  final ScripResult result;
  final VoidCallback onTap;

  const _ScripTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPos = (result.percentChange ?? 0) >= 0;
    final hasPrice = result.ltp != null && result.ltp! > 0;

    Color segmentColor;
    switch (result.segment) {
      case 'FUT':
        segmentColor = AppColors.warning;
        break;
      case 'CE':
        segmentColor = AppColors.success;
        break;
      case 'PE':
        segmentColor = AppColors.danger;
        break;
      default:
        segmentColor = AppColors.primary;
    }

    // Exchange badge color
    Color exchangeColor;
    switch (result.exchange) {
      case 'MCX':
        exchangeColor = const Color(0xFF7B1FA2); // purple for MCX
        break;
      case 'NFO':
        exchangeColor = AppColors.warning;
        break;
      case 'BSE':
        exchangeColor = const Color(0xFF0277BD);
        break;
      default:
        exchangeColor = AppColors.primary;
    }

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: segmentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            result.exchange == 'MCX' ? 'MCX' : result.segment,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: result.exchange == 'MCX' ? 9 : 11,
                color: result.exchange == 'MCX' ? exchangeColor : segmentColor),
          ),
        ),
      ),
      title: Text(
        result.displaySymbol,
        style: const TextStyle(
            fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      subtitle: Row(
        children: [
          // Exchange badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: exchangeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: exchangeColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              result.exchange,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: exchangeColor),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (result.name.isNotEmpty) result.name,
                result.tradingSymbol,
              ].join(' • '),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: hasPrice
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${result.ltp!.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                Text(
                  '${isPos ? '+' : ''}${result.percentChange!.toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isPos ? AppColors.success : AppColors.danger),
                ),
              ],
            )
          : const Icon(LucideIcons.chevronRight,
              size: 16, color: AppColors.textSecondary),
    );
  }
}

class _WatchlistTile extends StatelessWidget {
  final Stock stock;
  final VoidCallback onTap;

  const _WatchlistTile({required this.stock, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            stock.symbol.substring(0, stock.symbol.length.clamp(0, 2)),
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.primary),
          ),
        ),
      ),
      title: Text(stock.symbol,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text(
        '${stock.name} • ${stock.exchange} • ${stock.sector}',
        style: const TextStyle(
            fontSize: 11, color: AppColors.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${stock.currentPrice.toStringAsFixed(2)}',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          Text(
            '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPos ? AppColors.success : AppColors.danger),
          ),
        ],
      ),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
    );
  }
}
