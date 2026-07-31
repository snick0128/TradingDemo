import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class MarketDepthScreen extends StatefulWidget {
  final String? symbol;
  final bool showAppBar;

  const MarketDepthScreen({super.key, this.symbol, this.showAppBar = true});

  @override
  State<MarketDepthScreen> createState() => _MarketDepthScreenState();
}

class _MarketDepthScreenState extends State<MarketDepthScreen> {
  @override
  Widget build(BuildContext context) {
    final store = TradingScope.read(context); // read-only: stream drives updates, not InheritedWidget
    final sym = widget.symbol ?? 'NIFTY';

    // Seed with any depth already cached on the stock so the screen isn't blank
    // while waiting for the next tick. The StreamBuilder will overwrite this as
    // real-time ticks arrive.
    final cachedDepth = store.stockBySymbolOrNull(sym)?.depth;

    return StreamBuilder<MarketDepth>(
      stream: store.marketDataService.depthUpdates(sym),
      initialData: cachedDepth,
      builder: (context, snapshot) {
        final depth = snapshot.data;

        final body = depth == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Waiting for live depth data…',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary row
                    Row(
                      children: [
                        Expanded(
                          child: CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Buy Qty',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmt(depth.totalBuyQuantity),
                                  style: AppTheme.mono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Sell Qty',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmt(depth.totalSellQuantity),
                                  style: AppTheme.mono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Buy/Sell Ratio',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  depth.buyToSellRatio.toStringAsFixed(2),
                                  style: AppTheme.mono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: depth.buyToSellRatio >= 1
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Depth table
                    CustomCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _tableHeader(context),
                          const Divider(height: 1),
                          ...List.generate(5, (i) {
                            final bid = depth.bids[i];
                            final ask = depth.asks[i];
                            return _depthRow(context, bid, ask, i);
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Visual bar
                    _buildDepthBar(depth),
                  ],
                ),
              );

        if (!widget.showAppBar) return Scaffold(body: body);

        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: Text('Market Depth — $sym'),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _tableHeader(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Container(
      color: AppColors.surfaceAlt.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(child: Text('Orders', style: style)),
          Expanded(child: Text('Qty', style: style)),
          Expanded(
            child: Text('Bid', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('Ask', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('Qty', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            child: Text('Orders', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _depthRow(
    BuildContext context,
    MarketDepthLevel bid,
    MarketDepthLevel ask,
    int i,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${bid.orders}',
                  style: AppTheme.mono(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _fmt(bid.quantity),
                  style: AppTheme.mono(
                    fontSize: 12,
                    color: AppColors.success,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  bid.price.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  ask.price.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _fmt(ask.quantity),
                  textAlign: TextAlign.right,
                  style: AppTheme.mono(
                    fontSize: 12,
                    color: AppColors.danger,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${ask.orders}',
                  textAlign: TextAlign.right,
                  style: AppTheme.mono(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildDepthBar(MarketDepth depth) {
    final total = depth.totalBuyQuantity + depth.totalSellQuantity;
    final buyFraction = total == 0 ? 0.5 : depth.totalBuyQuantity / total;

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buy vs Sell Pressure',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (buyFraction * 100).round(),
                  child: Container(height: 12, color: AppColors.success),
                ),
                Expanded(
                  flex: ((1 - buyFraction) * 100).round(),
                  child: Container(height: 12, color: AppColors.danger),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Buy ${(buyFraction * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Sell ${((1 - buyFraction) * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(int qty) {
    if (qty >= 100000) return '${(qty / 100000).toStringAsFixed(1)}L';
    if (qty >= 1000) return '${(qty / 1000).toStringAsFixed(1)}K';
    return '$qty';
  }
}
