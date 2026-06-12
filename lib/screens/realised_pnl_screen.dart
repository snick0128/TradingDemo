import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/trading_bottom_nav_bar.dart';

class RealisedPnlScreen extends StatelessWidget {
  final bool showAppBar;

  const RealisedPnlScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final today = DateTime.now();

    // Only show closing orders — orders that actually realize P&L.
    // Opening BUY orders have pnl = 0 and must be excluded so they don't
    // count as "losers" (their charges were not applied in paper trading).
    final executedOrders = store.orders.where((o) {
      if (o.status != OrderStatus.executed) return false;
      // Skip opening orders: pnl = 0 means no position was closed
      if ((o.pnl ?? 0.0) == 0.0) return false;
      final execAt = o.executedAt ?? o.dateTime;
      return execAt.year == today.year &&
          execAt.month == today.month &&
          execAt.day == today.day;
    }).toList();

    final trades = executedOrders.map((o) => _TradePnl.fromOrder(o)).toList();
    final totalNetPnl = trades.fold(0.0, (s, t) => s + t.netPnl);
    final totalGrossPnl = trades.fold(0.0, (s, t) => s + t.grossPnl);
    final totalCharges = trades.fold(0.0, (s, t) => s + t.totalCharges);
    final winners = trades.where((t) => t.netPnl > 0).length;
    final losers = trades.where((t) => t.netPnl < 0).length;

    final body = trades.isEmpty
        ? _buildEmptyState()
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, TradingBottomNavBar.bottomInset(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Summary cards ────────────────────────────────────────
                _SummaryGrid(
                  totalNetPnl: totalNetPnl,
                  totalGrossPnl: totalGrossPnl,
                  totalCharges: totalCharges,
                  tradeCount: trades.length,
                  winners: winners,
                  losers: losers,
                ),
                const SizedBox(height: 20),
                // ── Trade list ───────────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'Trade History',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${trades.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...trades.map((t) => _TradeCard(trade: t)),
              ],
            ),
          );

    // Do NOT wrap in Scaffold when embedded inside another Scaffold (e.g.
    // TabBarView in PortfolioScreen). Nested Scaffolds cause Flutter's
    // box.dart constraint assertions to fire on Expanded / double.infinity
    // children. The parent Scaffold already provides bounded constraints.
    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Realised P&L')),
      body: body,
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clipboardList, size: 48, color: AppColors.border),
          SizedBox(height: 16),
          Text(
            'No closed trades today',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Executed trades will appear here with P&L breakdown.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Grid ─────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final double totalNetPnl;
  final double totalGrossPnl;
  final double totalCharges;
  final int tradeCount;
  final int winners;
  final int losers;

  const _SummaryGrid({
    required this.totalNetPnl,
    required this.totalGrossPnl,
    required this.totalCharges,
    required this.tradeCount,
    required this.winners,
    required this.losers,
  });

  @override
  Widget build(BuildContext context) {
    final isPos = totalNetPnl >= 0;
    final pnlColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final winRate = tradeCount == 0 ? 0.0 : (winners / tradeCount) * 100;

    return Column(
      children: [
        // Top card — total net P&L hero
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Net P&L (Today)',
                style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
              const SizedBox(height: 8),
              Text(
                '${isPos ? '+' : ''}₹${totalNetPnl.abs().toStringAsFixed(2)}',
                style: AppTheme.tabular(
                  TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: pnlColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      'Gross P&L',
                      '${totalGrossPnl >= 0 ? '+' : ''}₹${totalGrossPnl.abs().toStringAsFixed(2)}',
                      totalGrossPnl >= 0
                          ? const Color(0xFF00C853)
                          : const Color(0xFFD50000),
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      'Charges',
                      '-₹${totalCharges.toStringAsFixed(2)}',
                      const Color(0xFF757575),
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      'Trades',
                      '$tradeCount',
                      AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Win/Loss row
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: LucideIcons.trendingUp,
                iconColor: const Color(0xFF00C853),
                label: 'Winners',
                value: '$winners',
                sub: '',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                icon: LucideIcons.trendingDown,
                iconColor: const Color(0xFFD50000),
                label: 'Losers',
                value: '$losers',
                sub: '',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                icon: LucideIcons.percent,
                iconColor: AppColors.primary,
                label: 'Win Rate',
                value: '${winRate.toStringAsFixed(0)}%',
                sub: '',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.tabular(TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor,
          )),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF757575))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.tabular(const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            )),
          ),
          if (sub.isNotEmpty)
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }
}

// ─── Trade Card ────────────────────────────────────────────────────────────────

class _TradeCard extends StatelessWidget {
  final _TradePnl trade;

  const _TradeCard({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isPos = trade.netPnl >= 0;
    final pnlColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final isSell = trade.type == OrderType.sell;
    final sideColor = isSell ? const Color(0xFFD50000) : const Color(0xFF00C853);
    final sideBg = isSell
        ? const Color(0xFFFFEBEE)
        : const Color(0xFFE8F5E9);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left color bar
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: pnlColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: symbol + net P&L
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            trade.symbol,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0D0D0D),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: sideBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isSell ? 'SELL' : 'BUY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: sideColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${isPos ? '+' : ''}₹${trade.netPnl.abs().toStringAsFixed(2)}',
                        style: AppTheme.tabular(
                          TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: pnlColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: qty · avg → exec + charges
                  Row(
                    children: [
                      Text(
                        '${trade.quantity} qty',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF757575)),
                      ),
                      const SizedBox(width: 6),
                      const Text('·',
                          style: TextStyle(color: Color(0xFF9E9E9E))),
                      const SizedBox(width: 6),
                      Text(
                        'Avg ₹${trade.avgPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF757575)),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward,
                          size: 12, color: Color(0xFF9E9E9E)),
                      const SizedBox(width: 6),
                      Text(
                        '₹${trade.execPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF757575)),
                      ),
                      const Spacer(),
                      Tooltip(
                        message:
                            'STT: ₹${trade.stt.toStringAsFixed(2)}\n'
                            'Brokerage: ₹${trade.brokerage.toStringAsFixed(2)}\n'
                            'GST: ₹${trade.gst.toStringAsFixed(2)}',
                        child: Text(
                          'Charges -₹${trade.totalCharges.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9E9E9E)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trade P&L Model ──────────────────────────────────────────────────────────

class _TradePnl {
  final String symbol;
  final OrderType type;
  final int quantity;
  final double avgPrice;
  final double execPrice;
  final double grossPnl;
  final double stt;
  final double brokerage;
  final double gst;

  _TradePnl({
    required this.symbol,
    required this.type,
    required this.quantity,
    required this.avgPrice,
    required this.execPrice,
    required this.grossPnl,
    required this.stt,
    required this.brokerage,
    required this.gst,
  });

  double get totalCharges => stt + brokerage + gst;
  double get netPnl => grossPnl - totalCharges;

  factory _TradePnl.fromOrder(Order order) {
    final execPrice = order.executedPrice ?? order.price;
    final avgPrice  = order.price;
    final qty       = order.executedQuantity ?? order.quantity;

    // Use backend-computed gross P&L.
    // The backend sets pnl = (exitPrice - avgEntryPrice) × qty for longs,
    // and pnl = (avgEntryPrice - exitPrice) × qty for shorts.
    // This is the ONLY reliable P&L source — deriving it from order.price
    // vs order.executedPrice gives 0 because both fields are the fill price.
    final grossPnl = order.pnl ?? 0.0;

    // Use backend-computed charges (brokerage + taxes combined).
    // Fall back to 0 — in paper trading, charges are often not configured.
    final totalBackendCharges = order.chargesApplied ?? 0.0;

    return _TradePnl(
      symbol: order.symbol,
      type: order.type,
      quantity: qty,
      avgPrice: avgPrice,
      execPrice: execPrice,
      grossPnl: grossPnl,
      stt: 0.0,
      brokerage: totalBackendCharges,
      gst: 0.0,
    );
  }
}
