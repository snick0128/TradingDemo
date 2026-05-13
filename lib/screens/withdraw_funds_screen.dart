import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
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
  bool _loading = false;
  bool _submitted = false;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.trim());

    setState(() => _loading = true);

    try {
      // Get the current user's UID from the auth session.
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      final uid = appScope?.notifier?.user?.uid;

      if (uid == null || uid.isEmpty) {
        _showError('You must be logged in to submit a withdrawal request.');
        return;
      }

      final firestore = appScope!.firestoreService;

      await firestore.addDocument('withdrawal_requests', {
        'userId': uid,
        'amount': amount,
        'bankAccount': _selectedBank,
        'status': 'PENDING',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      _showError('Something went wrong. Please try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    final body = _submitted ? _buildSuccessView() : _buildForm(store);

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw Funds')),
      body: body,
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.checkCircle,
                size: 36,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Request Submitted',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your withdrawal request has been submitted and is pending admin approval.\nYou will be notified once it is processed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => setState(() {
                _submitted = false;
                _amountController.clear();
              }),
              child: const Text('Submit Another Request'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(dynamic store) {
    return SingleChildScrollView(
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
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Available balance: ₹${store.balance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                // Info banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Withdrawal requests are reviewed by admin. Funds are credited within 1–2 business days after approval.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                    if (val == null || val <= 0) {
                      return 'Enter a valid amount greater than 0';
                    }
                    if (val > store.balance) {
                      return 'Amount exceeds available balance';
                    }
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit Withdrawal Request'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
