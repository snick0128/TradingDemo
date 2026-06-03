import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../theme.dart';

/// Unified wallet ledger — shows all credits and debits from the `ledger`
/// collection ordered by date.  Supports type filtering and date-range filters.
class WalletLedgerScreen extends StatefulWidget {
  final bool showAppBar;

  const WalletLedgerScreen({super.key, this.showAppBar = true});

  @override
  State<WalletLedgerScreen> createState() => _WalletLedgerScreenState();
}

class _WalletLedgerScreenState extends State<WalletLedgerScreen> {
  LedgerEntryType? _typeFilter;
  DateTimeRange?   _dateRange;

  static const _typeLabels = <LedgerEntryType?, String>{
    null:                          'All Types',
    LedgerEntryType.deposit:       'Deposit',
    LedgerEntryType.adminCredit:   'Admin Credit',
    LedgerEntryType.bonus:         'Bonus',
    LedgerEntryType.referral:      'Referral',
    LedgerEntryType.ipoProfit:     'IPO Profit',
    LedgerEntryType.ipoLoss:       'IPO Loss',
    LedgerEntryType.ipoMarginBlocked: 'IPO Margin',
    LedgerEntryType.withdrawal:    'Withdrawal',
    LedgerEntryType.marginBlocked: 'Margin Blocked',
    LedgerEntryType.marginReleased:'Margin Released',
    LedgerEntryType.brokerage:     'Brokerage',
    LedgerEntryType.manualAdjustment: 'Adjustment',
  };

  @override
  Widget build(BuildContext context) {
    final appScope = AppScope.of(context);
    final uid      = appScope.notifier?.user?.uid;
    final db       = appScope.firestoreService.raw;

    if (uid == null) {
      return const Center(
        child: Text('Please log in to view wallet history.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final body = Column(
      children: [
        _buildFilters(context),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('ledger')
                .where('userId', isEqualTo: uid)
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text('Error: ${snap.error}',
                      style: const TextStyle(color: AppColors.danger)),
                );
              }

              final all = (snap.data?.docs ?? [])
                  .map((d) => WalletLedgerEntry.fromFirestore(d.id, d.data()))
                  .toList();

              final filtered = _applyFilters(all);

              if (filtered.isEmpty) {
                return _emptyState();
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _LedgerRow(entry: filtered[i]),
              );
            },
          ),
        ),
      ],
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet History')),
      body: body,
    );
  }

  List<WalletLedgerEntry> _applyFilters(List<WalletLedgerEntry> entries) {
    return entries.where((e) {
      if (_typeFilter != null && e.type != _typeFilter) return false;
      if (_dateRange != null) {
        if (e.createdAt.isBefore(_dateRange!.start) ||
            e.createdAt.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 15),
            label: Text(
              _dateRange == null
                  ? 'Date Range'
                  : '${DateFormat('dd MMM').format(_dateRange!.start)} – ${DateFormat('dd MMM').format(_dateRange!.end)}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _pickDateRange(context),
          ),
          if (_dateRange != null) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.close, size: 15),
              onPressed: () => setState(() => _dateRange = null),
              tooltip: 'Clear date filter',
              visualDensity: VisualDensity.compact,
            ),
          ],
          const SizedBox(width: 12),
          DropdownButton<LedgerEntryType?>(
            value: _typeFilter,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(
                fontSize: 12,
                color:    AppColors.textPrimary),
            items: _typeLabels.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context:          context,
      firstDate:        DateTime(2020),
      lastDate:         DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.fileText,
              size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('No transactions found',
              style: TextStyle(color: AppColors.textSecondary)),
          if (_typeFilter != null || _dateRange != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _typeFilter = null;
                _dateRange  = null;
              }),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ledger Row ────────────────────────────────────────────────────────────────

class _LedgerRow extends StatelessWidget {
  final WalletLedgerEntry entry;

  const _LedgerRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCredit  = entry.credit > 0;
    final amount    = entry.amount;
    final fmt       = DateFormat('dd MMM yyyy, hh:mm a');
    final numFmt    = NumberFormat('#,##,##0.00');

    Color dotColor;
    IconData icon;
    if (entry.type == LedgerEntryType.ipoProfit) {
      dotColor = AppColors.success;
      icon     = LucideIcons.trendingUp;
    } else if (entry.type == LedgerEntryType.ipoLoss) {
      dotColor = AppColors.danger;
      icon     = LucideIcons.trendingDown;
    } else if (entry.type == LedgerEntryType.withdrawal) {
      dotColor = AppColors.danger;
      icon     = LucideIcons.arrowUpRight;
    } else if (entry.type == LedgerEntryType.deposit ||
               entry.type == LedgerEntryType.adminCredit) {
      dotColor = AppColors.success;
      icon     = LucideIcons.arrowDownLeft;
    } else if (entry.type == LedgerEntryType.marginBlocked ||
               entry.type == LedgerEntryType.ipoMarginBlocked) {
      dotColor = AppColors.warning;
      icon     = LucideIcons.lock;
    } else if (entry.type == LedgerEntryType.marginReleased) {
      dotColor = AppColors.success;
      icon     = LucideIcons.unlock;
    } else {
      dotColor = isCredit ? AppColors.success : AppColors.danger;
      icon     = isCredit ? LucideIcons.plus : LucideIcons.minus;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Icon dot
          Container(
            width:  36,
            height: 36,
            decoration: BoxDecoration(
              color:        dotColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 16, color: dotColor),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.type.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize:   13,
                      color:      AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                if (entry.remarks.isNotEmpty)
                  Text(entry.remarks,
                      style: const TextStyle(
                          fontSize: 11,
                          color:    AppColors.textSecondary),
                      maxLines:  2,
                      overflow:  TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(fmt.format(entry.createdAt),
                    style: const TextStyle(
                        fontSize: 10,
                        color:    AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Amount column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}₹${numFmt.format(amount)}',
                style: AppTheme.tabular(TextStyle(
                    color:      dotColor,
                    fontWeight: FontWeight.w700,
                    fontSize:   14)),
              ),
              if (entry.balanceAfter > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Bal: ₹${numFmt.format(entry.balanceAfter)}',
                  style: AppTheme.tabular(const TextStyle(
                      fontSize: 10,
                      color:    AppColors.textSecondary)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
