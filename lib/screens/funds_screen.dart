import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'add_funds_screen.dart';
import 'withdraw_funds_screen.dart';

// ── Indian currency formatter (full, no abbreviations) ────────────────────────
String _formatCurrency(double value) {
  final formatter = NumberFormat('#,##,##0.00', 'en_IN');
  return '₹${formatter.format(value)}';
}

class FundsScreen extends StatelessWidget {
  final bool showAppBar;

  const FundsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final mb = store.marginBreakdown;

    final unrealizedPnl = store.positions.fold(0.0, (s, p) => s + p.unrealizedPnl);
    final realizedPnl = store.orders
        .where((o) => o.status == OrderStatus.executed && o.type == OrderType.sell)
        .fold(0.0, (sum, o) => sum + (o.executedPrice ?? o.price) * o.quantity);
    final todayPnl = unrealizedPnl + realizedPnl;

    final body = Container(
      color: const Color(0xFFFAFAFA),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildHeroCard(context, mb),
            const SizedBox(height: 16),
            _buildBreakdownSection(context, mb),
            const SizedBox(height: 24),
            _buildQuickStatsRow(context, todayPnl, realizedPnl, unrealizedPnl),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Funds')),
      body: body,
    );
  }

  Widget _buildHeroCard(BuildContext context, MarginBreakdown mb) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available cash',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // FittedBox keeps the amount on one line regardless of value size
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(mb.availableCash),
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _actionButton(
                    context,
                    label: 'Add Funds',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddFundsScreen()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    context,
                    label: 'Withdraw',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WithdrawFundsScreen()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            height: 1,
            color: Colors.white.withOpacity(0.2),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Margin used',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(mb.marginUsed),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Margin available',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _formatCurrency(mb.marginAvailable),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context,
      {required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownSection(BuildContext context, MarginBreakdown mb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 20, bottom: 12),
          child: Text(
            'Margin breakdown',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF0D0D0D),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _breakdownRow('Available Cash', mb.availableCash,
                  valueColor: const Color(0xFF00C853)),
              _separator(),
              _breakdownRow('Margin Used', mb.marginUsed,
                  valueColor: mb.marginUsed > 0
                      ? const Color(0xFFD50000)
                      : const Color(0xFF9E9E9E)),
              _separator(),
              _breakdownRow('Margin Available', mb.marginAvailable),
              _separator(),
              _breakdownRow('Collateral Value', mb.collateralValue),
              _separator(),
              _breakdownRow('SPAN Margin', mb.spanMargin),
              _separator(),
              _breakdownRow('Exposure Margin', mb.exposureMargin),
              _separator(),
              _breakdownRow('Peak Margin', mb.peakMargin),              Container(
                height: 1,
                color: const Color(0xFFE0E0E0),
              ),
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Margin',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D0D0D),
                      ),
                    ),
                    Text(
                      _formatCurrency(mb.totalMargin),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _breakdownRow(String label, double value, {Color? valueColor}) {
    final isZero = value == 0;
    final effectiveColor = isZero
        ? const Color(0xFF9E9E9E)
        : (valueColor ?? const Color(0xFF0D0D0D));

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF757575),
            ),
          ),
          Text(
            _formatCurrency(value),
            style: GoogleFonts.inter(
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

  Widget _separator() {
    return Container(
      height: 1,
      color: const Color(0xFFF5F5F5),
    );
  }

  Widget _buildQuickStatsRow(
      BuildContext context, double todayPnl, double realized, double unrealized) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _statColumn(
              label: "Today's P&L",
              value: todayPnl,
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFFE0E0E0),
          ),
          Expanded(
            child: _statColumn(
              label: 'Realized',
              value: realized,
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFFE0E0E0),
          ),
          Expanded(
            child: _statColumn(
              label: 'Unrealized',
              value: unrealized,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn({required String label, required double value}) {
    final isPositive = value > 0;
    final isZero = value == 0;
    final color = isZero
        ? const Color(0xFF9E9E9E)
        : (isPositive ? const Color(0xFF00C853) : const Color(0xFFD50000));

    return Column(
      children: [
        Text(
          '${isPositive ? '+' : isZero ? '' : '-'}${_formatCurrency(value.abs())}',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFF9E9E9E),
          ),
        ),
      ],
    );
  }

}
