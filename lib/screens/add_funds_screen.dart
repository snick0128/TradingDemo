import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/wallet_fund_widgets.dart';
import 'deposit_payment_method_screen.dart';

const _kQuickAmounts = [1000.0, 2000.0, 5000.0, 10000.0, 25000.0, 50000.0];

/// Step 1 of the deposit flow — just an amount. No UTR, no reference, no
/// remarks: those only ever existed to let admin verify a payment, and that
/// job is now done by a reference code the app generates on its own.
class AddFundsScreen extends StatefulWidget {
  final bool showAppBar;

  const AddFundsScreen({super.key, this.showAppBar = true});

  @override
  State<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends State<AddFundsScreen> {
  final _amountCtrl = TextEditingController();
  double? _selectedAmount;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());

  bool get _canContinue => (_amount ?? 0) > 0;

  void _continue() {
    final amount = _amount;
    if (amount == null || amount <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DepositPaymentMethodScreen(amount: amount)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payment = TradingScope.of(context).paymentConfig;
    final uid     = AppScope.of(context).notifier?.user?.uid ?? '';

    final body = !payment.enabled
        ? _buildUnavailable(context)
        : _buildForm(context, uid);

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Funds')),
      body: body,
    );
  }

  Widget _buildUnavailable(BuildContext context) {
    final support = TradingScope.of(context).supportConfig;
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
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.clock, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Deposits Coming Soon',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Online deposits are being set up for your account.\n'
              '${support.phoneNumber.isNotEmpty ? "Contact support at ${support.phoneNumber} to add funds." : "Please contact your administrator to add funds."}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, String uid) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.wallet, size: 40, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('Add Funds',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                'Enter an amount to add to your wallet.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              WalletPendingRequestBanner(
                collection: 'deposit_requests',
                userId: uid,
                label: 'deposit',
              ),

              // Large amount field
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setState(() => _selectedAmount = null),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    hintText: '0',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              WalletQuickAmountChips(
                amounts: _kQuickAmounts,
                selected: _selectedAmount,
                onSelect: (a) => setState(() {
                  _selectedAmount = a;
                  _amountCtrl.text = a.toStringAsFixed(0);
                }),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canContinue ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
