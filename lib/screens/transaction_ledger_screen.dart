import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class TransactionLedgerScreen extends StatefulWidget {
  final bool showAppBar;

  const TransactionLedgerScreen({super.key, this.showAppBar = true});

  @override
  State<TransactionLedgerScreen> createState() =>
      _TransactionLedgerScreenState();
}

class _TransactionLedgerScreenState extends State<TransactionLedgerScreen> {
  DateTimeRange? _dateRange;
  TransactionType? _typeFilter;

  static const _typeLabels = {
    null: 'All Types',
    TransactionType.deposit: 'Deposit',
    TransactionType.withdrawal: 'Withdrawal',
    TransactionType.marginBlocked: 'Margin Blocked',
    TransactionType.marginReleased: 'Margin Released',
    TransactionType.brokerage: 'Brokerage',
    TransactionType.stt: 'STT',
    TransactionType.gst: 'GST',
    TransactionType.exchangeCharges: 'Exchange Charges',
  };

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final filtered = _applyFilters(store.transactions.toList());

    final body = Column(
      children: [
        _buildFilters(context),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No transactions found',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _buildRow(context, filtered[i]),
                ),
        ),
      ],
    );

    if (!widget.showAppBar) return Scaffold(body: body);

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Ledger')),
      body: body,
    );
  }

  List<Transaction> _applyFilters(List<Transaction> txs) {
    return txs.where((tx) {
      if (_dateRange != null) {
        final d = tx.dateTime;
        if (d.isBefore(_dateRange!.start) ||
            d.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      if (_typeFilter != null && tx.type != _typeFilter) return false;
      return true;
    }).toList();
  }

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(
              _dateRange == null
                  ? 'Date Range'
                  : '${DateFormat('dd MMM').format(_dateRange!.start)} – ${DateFormat('dd MMM').format(_dateRange!.end)}',
              style: const TextStyle(fontSize: 13),
            ),
            onPressed: () => _pickDateRange(context),
          ),
          if (_dateRange != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _dateRange = null),
              tooltip: 'Clear date filter',
            ),
          ],
          const SizedBox(width: 12),
          DropdownButton<TransactionType?>(
            value: _typeFilter,
            underline: const SizedBox(),
            items: _typeLabels.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Widget _buildRow(BuildContext context, Transaction tx) {
    final isCredit = tx.isDeposit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isCredit ? AppColors.success : AppColors.danger)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
              color: isCredit ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(tx.dateTime),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(2)}',
            style: AppTheme.tabular(
              TextStyle(
                color: isCredit ? AppColors.success : AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
