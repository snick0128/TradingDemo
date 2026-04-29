import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

/// Brokerage charges per executed trade
class _TradeCharges {
  final Order order;
  final double tradeValue;
  final double brokerage;
  final double stt;
  final double gst;
  final double exchangeCharges;

  const _TradeCharges({
    required this.order,
    required this.tradeValue,
    required this.brokerage,
    required this.stt,
    required this.gst,
    required this.exchangeCharges,
  });

  double get totalCharges => brokerage + stt + gst + exchangeCharges;
}

_TradeCharges _computeCharges(Order order) {
  final tradeValue = order.quantity * order.price;
  const brokerageFlat = 20.0;
  final brokerage = brokerageFlat; // ₹20 flat
  final stt = tradeValue * 0.001; // 0.1%
  final gst = brokerage * 0.18; // 18% of brokerage
  final exchangeCharges = tradeValue * 0.0000325; // 0.00325%
  return _TradeCharges(
    order: order,
    tradeValue: tradeValue,
    brokerage: brokerage,
    stt: stt,
    gst: gst,
    exchangeCharges: exchangeCharges,
  );
}

class BrokerageStatementScreen extends StatelessWidget {
  final bool showAppBar;

  const BrokerageStatementScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final executedOrders = store.orders
        .where(
          (o) =>
              o.status == OrderStatus.approved ||
              o.status == OrderStatus.executed,
        )
        .toList();
    final charges = executedOrders.map(_computeCharges).toList();

    final body = executedOrders.isEmpty
        ? const Center(
            child: Text(
              'No executed trades found',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildHeader(context),
                const SizedBox(height: 8),
                ...charges.map((c) => _buildTradeRow(context, c)),
                const SizedBox(height: 16),
                _buildTotals(context, charges),
              ],
            ),
          );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Brokerage Statement')),
      body: body,
    );
  }

  Widget _buildHeader(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Symbol / Date', style: style)),
          Expanded(
            flex: 2,
            child: Text(
              'Trade Value',
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('Brokerage', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('STT', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('GST', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('Exch.', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeRow(BuildContext context, _TradeCharges c) {
    final isBuy = c.order.type == OrderType.buy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.order.symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: (isBuy ? AppColors.success : AppColors.danger)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isBuy ? 'BUY' : 'SELL',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isBuy ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(c.order.dateTime),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _mono(
              '₹${c.tradeValue.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${c.brokerage.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${c.stt.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${c.gst.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${c.exchangeCharges.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${c.totalCharges.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotals(BuildContext context, List<_TradeCharges> charges) {
    final totalBrokerage = charges.fold(0.0, (s, c) => s + c.brokerage);
    final totalStt = charges.fold(0.0, (s, c) => s + c.stt);
    final totalGst = charges.fold(0.0, (s, c) => s + c.gst);
    final totalExch = charges.fold(0.0, (s, c) => s + c.exchangeCharges);
    final grandTotal = charges.fold(0.0, (s, c) => s + c.totalCharges);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'Total Charges',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Expanded(flex: 2, child: SizedBox()),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${totalBrokerage.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              bold: true,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${totalStt.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              bold: true,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${totalGst.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              bold: true,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${totalExch.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              bold: true,
            ),
          ),
          Expanded(
            flex: 1,
            child: _mono(
              '₹${grandTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              bold: true,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mono(
    String text, {
    TextAlign textAlign = TextAlign.start,
    Color? color,
    bool bold = false,
  }) {
    return Text(
      text,
      textAlign: textAlign,
      style: AppTheme.tabular(
        TextStyle(
          fontSize: 12,
          color: color ?? AppColors.textPrimary,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
