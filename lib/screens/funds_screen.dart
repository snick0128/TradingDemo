import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

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
        color: AppColors.danger.withOpacity(0.1),
        border: Border.all(color: AppColors.danger.withOpacity(0.4)),
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
    // 2-column layout to prevent overflow
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Available cash (hero)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available cash',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF757575),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${mb.availableCash.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D0D0D),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: Margin used + Margin available stacked
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Margin used',
                  style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${mb.marginUsed.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D0D0D),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Margin available',
                  style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${mb.marginAvailable.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D0D0D),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(BuildContext context, MarginBreakdown mb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Margin breakdown',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0D0D0D),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            children: [
              _breakdownRow('Available Cash', mb.availableCash,
                  valueColor: const Color(0xFF00C853)),
              _divider(),
              _breakdownRow('Margin Used', mb.marginUsed,
                  valueColor: mb.marginUsed > 0
                      ? const Color(0xFFD50000)
                      : const Color(0xFF9E9E9E)),
              _divider(),
              _breakdownRow('Margin Available', mb.marginAvailable),
              _divider(),
              _breakdownRow('Collateral Value', mb.collateralValue),
              _divider(),
              _breakdownRow('SPAN Margin', mb.spanMargin),
              _divider(),
              _breakdownRow('Exposure Margin', mb.exposureMargin),
              _divider(),
              _breakdownRow('Peak Margin', mb.peakMargin),
              Container(
                height: 1,
                color: const Color(0xFF0D0D0D).withOpacity(0.15),
              ),
              _breakdownRow(
                'Total Margin',
                mb.totalMargin,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D0D0D),
                ),
                valueStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1565C0),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _breakdownRow(
    String label,
    double value, {
    Color? valueColor,
    TextStyle? labelStyle,
    TextStyle? valueStyle,
  }) {
    final isZero = value == 0;
    final effectiveColor = isZero
        ? const Color(0xFF9E9E9E)
        : (valueColor ?? const Color(0xFF0D0D0D));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: labelStyle ??
                const TextStyle(fontSize: 13, color: Color(0xFF757575)),
          ),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: valueStyle ??
                TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: effectiveColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0));
}
