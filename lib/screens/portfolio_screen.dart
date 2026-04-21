import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final holdings = store.portfolio;

    final totalInvestment = store.totalInvestment;
    final totalCurrentValue = store.totalCurrentValue;
    final totalPnl = store.totalPnl;
    final totalPnlPercentage = totalInvestment == 0 ? 0 : (totalPnl / totalInvestment) * 100;
    final isPositive = totalPnl >= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio & Holdings'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPortfolioSummaryCard(context, store),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Holdings (${holdings.length})', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.sort, size: 18),
                  label: const Text('Sort'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (holdings.isEmpty)
              CustomCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(LucideIcons.briefcase, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('No holdings yet.', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: holdings.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = holdings[index];
                  final pnlPercentage = item.pnlPercentage;
                  final isItemPositive = item.pnl >= 0;

                  return CustomCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.symbol, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
                            const SizedBox(height: 4),
                            _labelValue('Qty', '${item.totalQuantity}', context),
                            _labelValue('Avg', '₹${item.avgPrice.toStringAsFixed(2)}', context),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${item.currentValue.toStringAsFixed(2)}',
                              style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${isItemPositive ? '+' : ''}${pnlPercentage.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: isItemPositive ? AppColors.success : AppColors.danger,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            _buildMarginInfo(store),
          ],
        ),
      ),
    );
  }

  Widget _buildPortfolioSummaryCard(BuildContext context, TradingStore store) {
    final totalInvestment = store.totalInvestment;
    final totalCurrentValue = store.totalCurrentValue;
    final totalPnl = store.totalPnl;
    final totalPnlPercentage = totalInvestment == 0 ? 0 : (totalPnl / totalInvestment) * 100;
    final isPositive = totalPnl >= 0;

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              _summaryItem('Invested', '₹${totalInvestment.toStringAsFixed(2)}', context),
              const Spacer(),
              _summaryItem('Current Value', '₹${totalCurrentValue.toStringAsFixed(2)}', context),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, thickness: 0.5)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Unrealized P&L', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isPositive ? '+' : ''}₹${totalPnl.abs().toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                      color: isPositive ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    '(${isPositive ? '+' : ''}${totalPnlPercentage.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: isPositive ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ],
    );
  }

  Widget _labelValue(String label, String value, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildMarginInfo(TradingStore store) {
    return CustomCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Available Margin', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text('₹${store.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(LucideIcons.info, size: 16),
            label: const Text('Breakup'),
          ),
        ],
      ),
    );
  }


  Widget _buildSummaryItem(String label, String value, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
