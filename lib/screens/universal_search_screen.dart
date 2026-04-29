import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  // Filter state
  String? _exchangeFilter; // NSE / BSE
  String? _segmentFilter; // EQ / FO
  String? _sectorFilter;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Stock> _filtered(List<Stock> all) {
    var result = all.where((s) {
      final q = _query.toLowerCase();
      final matchesQuery =
          q.isEmpty ||
          s.symbol.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q);
      final matchesExchange =
          _exchangeFilter == null || s.exchange == _exchangeFilter;
      final matchesSector = _sectorFilter == null || s.sector == _sectorFilter;
      return matchesQuery && matchesExchange && matchesSector;
    }).toList();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final all = store.watchlist.toList();
    final filtered = _filtered(all);

    final sectors = all.map((s) => s.sector).toSet().toList()..sort();
    final trending =
        (List<Stock>.from(all)
              ..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0)))
            .take(5)
            .toList();

    final showResults =
        _query.isNotEmpty ||
        _exchangeFilter != null ||
        _segmentFilter != null ||
        _sectorFilter != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: const BackButton(),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search stocks by symbol or name...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip(
                  label: 'NSE',
                  selected: _exchangeFilter == 'NSE',
                  onTap: () => setState(
                    () => _exchangeFilter = _exchangeFilter == 'NSE'
                        ? null
                        : 'NSE',
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'BSE',
                  selected: _exchangeFilter == 'BSE',
                  onTap: () => setState(
                    () => _exchangeFilter = _exchangeFilter == 'BSE'
                        ? null
                        : 'BSE',
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'EQ',
                  selected: _segmentFilter == 'EQ',
                  onTap: () => setState(
                    () => _segmentFilter = _segmentFilter == 'EQ' ? null : 'EQ',
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'FO',
                  selected: _segmentFilter == 'FO',
                  onTap: () => setState(
                    () => _segmentFilter = _segmentFilter == 'FO' ? null : 'FO',
                  ),
                ),
                const SizedBox(width: 8),
                ...sectors.map(
                  (sector) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _filterChip(
                      label: sector,
                      selected: _sectorFilter == sector,
                      onTap: () => setState(
                        () => _sectorFilter = _sectorFilter == sector
                            ? null
                            : sector,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: showResults
                ? _buildResults(context, filtered, store)
                : _buildDefaultView(context, store, trending),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultView(
    BuildContext context,
    dynamic store,
    List<Stock> trending,
  ) {
    final recent = store.recentSearches as List<String>;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
                .map(
                  (symbol) => ActionChip(
                    label: Text(symbol),
                    avatar: const Icon(LucideIcons.clock, size: 14),
                    onPressed: () {
                      _controller.text = symbol;
                      setState(() => _query = symbol);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        Text('Trending Stocks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...trending.map(
          (stock) => _StockResultTile(
            stock: stock,
            onTap: () => _openStock(context, store, stock.symbol),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(
    BuildContext context,
    List<Stock> stocks,
    dynamic store,
  ) {
    if (stocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.searchX,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "$_query"',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: stocks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final stock = stocks[index];
        return _StockResultTile(
          stock: stock,
          onTap: () => _openStock(context, store, stock.symbol),
        );
      },
    );
  }

  void _openStock(BuildContext context, dynamic store, String symbol) {
    store.addRecentSearch(symbol);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: symbol)),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _StockResultTile extends StatelessWidget {
  final Stock stock;
  final VoidCallback onTap;

  const _StockResultTile({required this.stock, required this.onTap});

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
              color: AppColors.primary,
            ),
          ),
        ),
      ),
      title: Text(
        stock.symbol,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        '${stock.name} • ${stock.exchange} • ${stock.sector}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${stock.currentPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isPos ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
