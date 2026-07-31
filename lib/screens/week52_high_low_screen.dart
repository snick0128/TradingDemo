import 'package:flutter/material.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class Week52HighLowScreen extends StatelessWidget {
  const Week52HighLowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('52-Week High / Low'),
          leading: const BackButton(),
          bottom: const TabBar(
            tabs: [
              Tab(text: '52W Highs'),
              Tab(text: '52W Lows'),
            ],
          ),
        ),
        body: Builder(
          builder: (context) {
            final store = TradingScope.of(context);
            final all = store.knownStocks.toList();

            final highs =
                all
                    .where(
                      (s) =>
                          s.week52High != null &&
                          s.currentPrice >= s.week52High! * 0.98,
                    )
                    .toList()
                  ..sort((a, b) => b.currentPrice.compareTo(a.currentPrice));

            final lows =
                all
                    .where(
                      (s) =>
                          s.week52Low != null &&
                          s.currentPrice <= s.week52Low! * 1.02,
                    )
                    .toList()
                  ..sort((a, b) => a.currentPrice.compareTo(b.currentPrice));

            return TabBarView(
              children: [
                _Week52List(stocks: highs, isHigh: true),
                _Week52List(stocks: lows, isHigh: false),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Week52List extends StatelessWidget {
  final List<Stock> stocks;
  final bool isHigh;

  const _Week52List({required this.stocks, required this.isHigh});

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) {
      return Center(
        child: Text(
          isHigh
              ? 'No stocks near 52-week highs'
              : 'No stocks near 52-week lows',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
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
                  isHigh ? '52W High' : '52W Low',
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
              final extremePrice = isHigh
                  ? stock.week52High!
                  : stock.week52Low!;

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
                          style: AppTheme.mono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '₹${extremePrice.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: AppTheme.mono(
                            fontSize: 12,
                            color: isHigh
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isPos ? AppColors.success : AppColors.danger,
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
