import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class FundsScreen extends StatelessWidget {
  final bool showAppBar;

  const FundsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final mb = store.marginBreakdown;
    final total = mb.availableCash + mb.marginUsed;
    final isMarginCall = total > 0 && (mb.availableCash / total) < 0.10;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMarginCall) _buildMarginCallBanner(context),
          if (isMarginCall) const SizedBox(height: 16),
          _buildSummaryRow(context, mb),
          const SizedBox(height: 24),
          _buildBreakdownCard(context, mb),
        ],
      ),
    );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Funds')),
      body: body,
    );
  }

  Widget _buildMarginCallBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.alertTriangle,
            color: AppColors.danger,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Margin Call Warning: Available margin is below 10% of total. Please add funds to avoid auto square-off.',
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, MarginBreakdown mb) {
    return Row(
      children: [
        _summaryItem(context, 'Available Cash', mb.availableCash, isHero: true),
        const SizedBox(width: 32),
        _summaryItem(context, 'Margin Used', mb.marginUsed),
        const SizedBox(width: 32),
        _summaryItem(context, 'Margin Available', mb.marginAvailable),
      ],
    );
  }

  Widget _summaryItem(
    BuildContext context,
    String label,
    double value, {
    bool isHero = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: AppTheme.tabular(
            TextStyle(
              fontSize: isHero ? 26 : 18,
              fontWeight: isHero ? FontWeight.w700 : FontWeight.w500,
              color: isHero ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownCard(BuildContext context, MarginBreakdown mb) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Margin Breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          InfoRow(
            label: 'Available Cash',
            value: '₹${mb.availableCash.toStringAsFixed(2)}',
            valueColor: AppColors.success,
          ),
          InfoRow(
            label: 'Margin Used',
            value: '₹${mb.marginUsed.toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'Margin Available',
            value: '₹${mb.marginAvailable.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'Collateral Value',
            value: '₹${mb.collateralValue.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'SPAN Margin',
            value: '₹${mb.spanMargin.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'Exposure Margin',
            value: '₹${mb.exposureMargin.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'Peak Margin',
            value: '₹${mb.peakMargin.toStringAsFixed(2)}',
          ),
          const Divider(height: 24),
          InfoRow(
            label: 'Total Margin',
            value: '₹${mb.totalMargin.toStringAsFixed(2)}',
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
