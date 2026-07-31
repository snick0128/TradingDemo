import 'package:flutter/material.dart';

import '../state/trading_scope.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class MostActiveScreen extends StatelessWidget {
  const MostActiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stocks = store.knownStocks.where((s) => s.volume != null).toList()
      ..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0));
    final top20 = stocks.take(20).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Most Active by Volume'),
        leading: const BackButton(),
      ),
      body: Column(
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Price',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Change%',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Volume',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: top20.isEmpty
                ? const Center(child: Text('No data available'))
                : ListView.separated(
                    itemCount: top20.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final stock = top20[index];
                      final isPos = stock.changePercentage >= 0;
                      final vol = stock.volume!;

                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StockDetailScreen(symbol: stock.symbol),
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
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
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
                                  '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isPos
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${(vol / 100000).toStringAsFixed(2)}L',
                                  textAlign: TextAlign.right,
                                  style: AppTheme.mono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
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
      ),
    );
  }
}
