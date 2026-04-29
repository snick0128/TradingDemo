import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/trading_scope.dart';
import '../models/trading_models.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class TopGainersLosersScreen extends StatelessWidget {
  const TopGainersLosersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Top Gainers & Losers'),
          leading: const BackButton(),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Top Gainers'),
              Tab(text: 'Top Losers'),
            ],
          ),
        ),
        body: Builder(
          builder: (context) {
            final store = TradingScope.of(context);
            final sorted = store.watchlist.toList();

            final gainers =
                (List<Stock>.from(sorted)..sort(
                      (a, b) =>
                          b.changePercentage.compareTo(a.changePercentage),
                    ))
                    .take(20)
                    .toList();

            final losers =
                (List<Stock>.from(sorted)..sort(
                      (a, b) =>
                          a.changePercentage.compareTo(b.changePercentage),
                    ))
                    .take(20)
                    .toList();

            return TabBarView(
              children: [
                _StockList(stocks: gainers, isGainers: true),
                _StockList(stocks: losers, isGainers: false),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StockList extends StatelessWidget {
  final List<Stock> stocks;
  final bool isGainers;

  const _StockList({required this.stocks, required this.isGainers});

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
              const SizedBox(width: 28),
              Expanded(
                flex: 3,
                child: Text(
                  'Symbol',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Price',
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Change%',
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Volume',
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: stocks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final stock = stocks[index];
              final isPos = stock.changePercentage >= 0;
              final color = isPos ? AppColors.success : AppColors.danger;
              final volume = stock.volume;

              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(symbol: stock.symbol),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stock.symbol,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              stock.name,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '₹${stock.currentPrice.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          volume != null
                              ? '${(volume / 100000).toStringAsFixed(2)}L'
                              : '-',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
