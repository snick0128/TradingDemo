import 'package:flutter/material.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class SectorHeatmapScreen extends StatelessWidget {
  const SectorHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stocks = store.watchlist.toList();

    // Group by sector and compute average change%
    final Map<String, List<Stock>> bySector = {};
    for (final s in stocks) {
      bySector.putIfAbsent(s.sector, () => []).add(s);
    }

    final sectors = bySector.entries.map((e) {
      final avg =
          e.value.fold(0.0, (sum, s) => sum + s.changePercentage) /
          e.value.length;
      return _SectorData(name: e.key, avgChange: avg, stocks: e.value);
    }).toList()..sort((a, b) => b.avgChange.compareTo(a.avgChange));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sector Heatmap'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tap a sector to view stocks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sectors.map((s) => _SectorCell(data: s)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectorData {
  final String name;
  final double avgChange;
  final List<Stock> stocks;

  const _SectorData({
    required this.name,
    required this.avgChange,
    required this.stocks,
  });
}

class _SectorCell extends StatelessWidget {
  final _SectorData data;

  const _SectorCell({required this.data});

  Color _cellColor() {
    final magnitude = data.avgChange.abs().clamp(0.0, 5.0);
    final intensity = (magnitude / 5.0 * 0.7 + 0.15).clamp(0.0, 1.0);
    if (data.avgChange >= 0) {
      return AppColors.success.withValues(alpha: intensity);
    } else {
      return AppColors.danger.withValues(alpha: intensity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPos = data.avgChange >= 0;
    final bgColor = _cellColor();
    final textColor = data.avgChange.abs() > 1.5
        ? Colors.white
        : (isPos ? AppColors.success : AppColors.danger);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _SectorStocksScreen(sectorName: data.name, stocks: data.stocks),
        ),
      ),
      child: Container(
        width: 140,
        height: 80,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (isPos ? AppColors.success : AppColors.danger).withValues(
              alpha: 0.3,
            ),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              data.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${isPos ? '+' : ''}${data.avgChange.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            Text(
              '${data.stocks.length} stocks',
              style: TextStyle(
                fontSize: 10,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sector Stocks List ───────────────────────────────────────────────────────

class _SectorStocksScreen extends StatelessWidget {
  final String sectorName;
  final List<Stock> stocks;

  const _SectorStocksScreen({required this.sectorName, required this.stocks});

  @override
  Widget build(BuildContext context) {
    final sorted = List<Stock>.from(stocks)
      ..sort((a, b) => b.changePercentage.compareTo(a.changePercentage));

    return Scaffold(
      appBar: AppBar(title: Text(sectorName), leading: const BackButton()),
      body: ListView.separated(
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final stock = sorted[index];
          final isPos = stock.changePercentage >= 0;

          return ListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StockDetailScreen(symbol: stock.symbol),
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
              stock.name,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
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
        },
      ),
    );
  }
}
