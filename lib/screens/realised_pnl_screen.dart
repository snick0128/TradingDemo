import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class RealisedPnlScreen extends StatelessWidget {
  final bool showAppBar;

  const RealisedPnlScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final today = DateTime.now();

    // Filter executed orders for today
    final executedOrders = store.orders.where((o) {
      if (o.status != OrderStatus.executed) return false;
      final execAt = o.executedAt ?? o.dateTime;
      return execAt.year == today.year &&
          execAt.month == today.month &&
          execAt.day == today.day;
    }).toList();

    // Compute trade P&L entries
    final trades = executedOrders.map((o) => _TradePnl.fromOrder(o)).toList();
    final totalNetPnl = trades.fold(0.0, (s, t) => s + t.netPnl);

    final body = Column(
      children: [
        _TotalPnlBanner(totalNetPnl: totalNetPnl, tradeCount: trades.length),
        const Divider(height: 1),
        Expanded(
          child: trades.isEmpty ? _buildEmptyState() : _buildTradeList(trades),
        ),
      ],
    );

    if (!showAppBar) return Scaffold(body: body);

    return Scaffold(
      appBar: AppBar(title: const Text('Realised P&L')),
      body: body,
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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

  Widget _buildTradeList(List<_TradePnl> trades) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              _tableHeader(),
              const Divider(height: 1),
              ...trades.map((t) => _TradeRow(trade: t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: AppColors.surfaceAlt.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Instrument', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Qty', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Avg Price', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Exec Price', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Gross P&L', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Charges', style: _headerStyle)),
          Expanded(
            flex: 2,
            child: Text(
              'Net P&L',
              style: _headerStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
  );
}

// ─── Total P&L Banner ─────────────────────────────────────────────────────────

class _TotalPnlBanner extends StatelessWidget {
  final double totalNetPnl;
  final int tradeCount;

  const _TotalPnlBanner({required this.totalNetPnl, required this.tradeCount});

  @override
  Widget build(BuildContext context) {
    final isPos = totalNetPnl >= 0;
    final color = isPos ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Net P&L (Today)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                '${isPos ? '+' : ''}₹${totalNetPnl.abs().toStringAsFixed(2)}',
                style: AppTheme.tabular(
                  TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Trades',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                '$tradeCount',
                style: AppTheme.tabular(
                  const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Trade Row ────────────────────────────────────────────────────────────────

class _TradeRow extends StatelessWidget {
  final _TradePnl trade;

  const _TradeRow({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isPos = trade.netPnl >= 0;
    final pnlColor = isPos ? AppColors.success : AppColors.danger;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Instrument
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trade.symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      trade.type == OrderType.sell ? 'SELL' : 'BUY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: trade.type == OrderType.sell
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              // Qty
              Expanded(
                flex: 2,
                child: Text(
                  '${trade.quantity}',
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              // Avg price
              Expanded(
                flex: 2,
                child: Text(
                  trade.avgPrice.toStringAsFixed(2),
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              // Exec price
              Expanded(
                flex: 2,
                child: Text(
                  trade.execPrice.toStringAsFixed(2),
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              // Gross P&L
              Expanded(
                flex: 2,
                child: Text(
                  '${trade.grossPnl >= 0 ? '+' : ''}${trade.grossPnl.toStringAsFixed(2)}',
                  style: AppTheme.tabular(
                    TextStyle(
                      fontSize: 13,
                      color: trade.grossPnl >= 0
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                ),
              ),
              // Charges
              Expanded(
                flex: 2,
                child: Tooltip(
                  message:
                      'STT: ₹${trade.stt.toStringAsFixed(2)}\n'
                      'Brokerage: ₹${trade.brokerage.toStringAsFixed(2)}\n'
                      'GST: ₹${trade.gst.toStringAsFixed(2)}',
                  child: Text(
                    '-₹${trade.totalCharges.toStringAsFixed(2)}',
                    style: AppTheme.tabular(
                      const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              // Net P&L
              Expanded(
                flex: 2,
                child: Text(
                  '${isPos ? '+' : ''}₹${trade.netPnl.abs().toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: AppTheme.tabular(
                    TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: pnlColor,
                    ),
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
    final avgPrice = order.price;
    final qty = order.executedQuantity ?? order.quantity;
    final tradeValue = execPrice * qty;

    // Gross P&L: for sells, profit = (execPrice - avgPrice) * qty
    // For buys (covering short), profit = (avgPrice - execPrice) * qty
    final grossPnl = order.type == OrderType.sell
        ? (execPrice - avgPrice) * qty
        : (avgPrice - execPrice) * qty;

    // Charges
    final stt = tradeValue * 0.001; // 0.1% of trade value
    const brokerage = 20.0; // flat ₹20
    final gst = brokerage * 0.18; // 18% of brokerage

    return _TradePnl(
      symbol: order.symbol,
      type: order.type,
      quantity: qty,
      avgPrice: avgPrice,
      execPrice: execPrice,
      grossPnl: grossPnl,
      stt: stt,
      brokerage: brokerage,
      gst: gst,
    );
  }
}
