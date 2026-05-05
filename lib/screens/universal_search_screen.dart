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
    // Angel One returns 'tradingsymbol' (lowercase s) — handle both
    final sym = (j['tradingSymbol'] ?? j['tradingsymbol'] ?? '') as String;
    final tok = (j['symbolToken'] ?? j['symboltoken'] ?? '').toString();
    final nm  = (j['name'] ?? '') as String;
    return ScripResult(
      exchange:      j['exchange'] as String? ?? 'NSE',
      tradingSymbol: sym,
      symbolToken:   tok,
      name:          nm,
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

  bool get isFutures => tradingSymbol.endsWith('FUT');
  bool get isOptions =>
      tradingSymbol.endsWith('CE') || tradingSymbol.endsWith('PE');
  bool get isEquity => !isFutures && !isOptions;

  String get segment {
    if (isFutures) return 'FUT';
    if (isOptions) return tradingSymbol.endsWith('CE') ? 'CE' : 'PE';
    return 'EQ';
  }
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

  String _query = '';
  String _exchange = 'NSE';
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

    // Debounce 400ms
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(q),
    );
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final raw = await _api.searchScrip(q, exchange: _exchange);
      final results = raw.map(ScripResult.fromJson).toList();

      // Best-effort: fetch quote for the first result only
      if (results.isNotEmpty && results[0].symbolToken.isNotEmpty) {
        try {
          final quoteRes = await _api.getQuoteByToken(
            results[0].symbolToken,
            exchange: _exchange,
          );
          // ltp may be null if the token has no data (expired contract, wrong segment)
          final ltp = (quoteRes['ltp'] as num?)?.toDouble();
          if (ltp != null && ltp > 0) {
            results[0].ltp = ltp;
            results[0].percentChange =
                (quoteRes['percentChange'] as num?)?.toDouble();
            results[0].netChange =
                (quoteRes['netChange'] as num?)?.toDouble();
          }
        } catch (_) {
          // Non-fatal — show result without price
        }
      }

      setState(() {
        _results = results;
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

  List<ScripResult> get _filtered {
    if (_segmentFilter == null) return _results;
    return _results.where((r) => r.segment == _segmentFilter).toList();
  }

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
            hintText: 'Search any stock, F&O, index...',
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
          // ── Filter bar ────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _Chip(
                  label: 'NSE',
                  selected: _exchange == 'NSE',
                  onTap: () {
                    setState(() => _exchange = 'NSE');
                    if (_query.length >= 2) _search(_query);
                  },
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'BSE',
                  selected: _exchange == 'BSE',
                  onTap: () {
                    setState(() => _exchange = 'BSE');
                    if (_query.length >= 2) _search(_query);
                  },
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'NFO',
                  selected: _exchange == 'NFO',
                  onTap: () {
                    setState(() => _exchange = 'NFO');
                    if (_query.length >= 2) _search(_query);
                  },
                ),
                const SizedBox(width: 16),
                _Chip(
                  label: 'EQ',
                  selected: _segmentFilter == 'EQ',
                  onTap: () => setState(() =>
                      _segmentFilter = _segmentFilter == 'EQ' ? null : 'EQ'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'FUT',
                  selected: _segmentFilter == 'FUT',
                  onTap: () => setState(() =>
                      _segmentFilter = _segmentFilter == 'FUT' ? null : 'FUT'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'CE',
                  selected: _segmentFilter == 'CE',
                  onTap: () => setState(() =>
                      _segmentFilter = _segmentFilter == 'CE' ? null : 'CE'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'PE',
                  selected: _segmentFilter == 'PE',
                  onTap: () => setState(() =>
                      _segmentFilter = _segmentFilter == 'PE' ? null : 'PE'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, store)),
        ],
      ),
    );
  }

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
            Text('Searching...',
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
              const Text('Try a different exchange or remove the segment filter.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
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
              // Resolve the best symbol to navigate to:
              // prefer displaySymbol if it's in the watchlist,
              // otherwise fall back to tradingSymbol (raw from API).
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
                'Type at least 2 characters to search\nany stock, futures, or options.',
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
            result.segment,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: segmentColor),
          ),
        ),
      ),
      title: Text(
        result.displaySymbol,
        style: const TextStyle(
            fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        [
          if (result.name.isNotEmpty) result.name,
          result.tradingSymbol,
          result.exchange,
        ].join(' • '),
        style: const TextStyle(
            fontSize: 11, color: AppColors.textSecondary),
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
