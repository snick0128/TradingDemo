import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet & Margin'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMainBalanceCard(context, store),
            const SizedBox(height: 20),
            _buildSegregatedBreakdown(context, store),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Transaction History', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: const Text('Filter'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTransactionList(store),
          ],
        ),
      ),
    );
  }

  Widget _buildMainBalanceCard(BuildContext context, TradingStore store) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Available Margin (Cash)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                   SizedBox(height: 2),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
              ),
            ],
          ),
          Text(
            '₹${store.balance.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: -0.5),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.add_circle_outline,
                  label: 'Pay In',
                  bgColor: Colors.white,
                  textColor: AppColors.primary,
                  onTap: () => _openAmountSheet(context, isDeposit: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.outbox,
                  label: 'Pay Out',
                  bgColor: Colors.white.withValues(alpha: 0.15),
                  textColor: Colors.white,
                  onTap: () => _openAmountSheet(context, isDeposit: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegregatedBreakdown(BuildContext context, TradingStore store) {
    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Funds Segregation', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
          const SizedBox(height: 20),
          _breakdownRow(context, 'Opening Balance', '₹${store.openingBalance.toStringAsFixed(2)}'),
          _divider(),
          _breakdownRow(context, 'Pay-in (Deposits)', '+ ₹${store.payIn.toStringAsFixed(2)}', valueColor: AppColors.success),
          _divider(),
          _breakdownRow(context, 'Pay-out (Withdrawals)', '- ₹${store.payOut.toStringAsFixed(2)}', valueColor: AppColors.danger),
          _divider(),
          _breakdownRow(context, 'Used Margin (Blocked)', '₹${store.usedMargin.toStringAsFixed(2)}', valueColor: AppColors.warning),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Margin Available', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  '₹${store.balance.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, thickness: 0.5));

  Widget _buildTransactionList(TradingStore store) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: store.transactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final tx = store.transactions[index];
        return CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (tx.isDeposit ? AppColors.success : AppColors.primary).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tx.isDeposit ? Icons.add : Icons.remove,
                  size: 18,
                  color: tx.isDeposit ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(DateFormat('dd MMM hh:mm a').format(tx.dateTime), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text(
                '${tx.isDeposit ? '+' : '-'}₹${tx.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  color: tx.isDeposit ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _openAmountSheet(BuildContext context, {required bool isDeposit}) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final store = TradingScope.of(context);

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isDeposit ? 'Deposit Funds' : 'Withdraw Funds', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹'),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(controller.text.trim()) ?? 0;
                  final result = isDeposit ? store.deposit(amount) : store.withdraw(amount);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      backgroundColor: result.success ? (isDeposit ? AppColors.success : AppColors.primary) : AppColors.warning,
                    ),
                  );
                },
                child: Text(isDeposit ? 'ADD FUNDS' : 'WITHDRAW'),
              ),
            ],
          ),
        );
      },
    );
  }
}
