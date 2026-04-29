import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../state/trading_scope.dart';
import '../theme.dart';

class AddFundsScreen extends StatefulWidget {
  final bool showAppBar;

  const AddFundsScreen({super.key, this.showAppBar = true});

  @override
  State<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends State<AddFundsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String _selectedUpi = 'user@upi';

  static const _upiOptions = ['user@upi', 'user@paytm', 'user@gpay'];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  LucideIcons.indianRupee,
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Funds via UPI',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Funds will be credited instantly to your trading account.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    hintText: 'Enter amount',
                  ),
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val <= 0)
                      return 'Enter a valid amount greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _selectedUpi,
                  decoration: const InputDecoration(labelText: 'UPI ID'),
                  items: _upiOptions
                      .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedUpi = v!),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Pay Now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Funds')),
      body: body,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text);

    // Show loading dialog
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
    Navigator.pop(context); // close loading

    final store = TradingScope.of(context);
    store.deposit(amount);

    // Show success dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.checkCircle, color: AppColors.success),
            SizedBox(width: 8),
            Text('Payment Successful'),
          ],
        ),
        content: Text(
          '₹${amount.toStringAsFixed(2)} has been added to your account via $_selectedUpi.',
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
