import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../state/trading_scope.dart';
import '../theme.dart';

class WithdrawFundsScreen extends StatefulWidget {
  final bool showAppBar;

  const WithdrawFundsScreen({super.key, this.showAppBar = true});

  @override
  State<WithdrawFundsScreen> createState() => _WithdrawFundsScreenState();
}

class _WithdrawFundsScreenState extends State<WithdrawFundsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String _selectedBank = 'HDFC Bank ****1234';

  static const _bankOptions = [
    'HDFC Bank ****1234',
    'ICICI Bank ****5678',
    'SBI ****9012',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.building2,
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Withdraw Funds',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Available balance: ₹${store.balance.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    hintText: 'Enter amount to withdraw',
                  ),
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val <= 0)
                      return 'Enter a valid amount greater than 0';
                    if (val > store.balance)
                      return 'Amount exceeds available balance';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _selectedBank,
                  decoration: const InputDecoration(labelText: 'Bank Account'),
                  items: _bankOptions
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedBank = v!),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('Withdraw'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw Funds')),
      body: body,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    Navigator.pop(context);

    final store = TradingScope.of(context);
    final result = store.withdraw(amount);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Withdrawal failed')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.checkCircle, color: AppColors.success),
            SizedBox(width: 8),
            Text('Transfer Initiated'),
          ],
        ),
        content: Text(
          '₹${amount.toStringAsFixed(2)} will be credited to $_selectedBank within 1-2 business days.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _amountController.clear();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
