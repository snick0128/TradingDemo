import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/wallet_fund_widgets.dart';

const _kQuickAmounts = [1000.0, 5000.0, 10000.0, 25000.0];

class WithdrawFundsScreen extends StatefulWidget {
  final bool showAppBar;

  const WithdrawFundsScreen({super.key, this.showAppBar = true});

  @override
  State<WithdrawFundsScreen> createState() => _WithdrawFundsScreenState();
}

class _WithdrawFundsScreenState extends State<WithdrawFundsScreen> {
  final _formKey         = GlobalKey<FormState>();
  final _amountCtrl      = TextEditingController();
  final _bankCtrl        = TextEditingController();
  final _upiCtrl         = TextEditingController();
  final _remarksCtrl     = TextEditingController();
  bool  _loading         = false;
  bool  _submitted       = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankCtrl.dispose();
    _upiCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());

    setState(() => _loading = true);

    try {
      final appScope = AppScope.of(context);
      final uid      = appScope.notifier?.user?.uid;
      final userName = appScope.notifier?.user?.name ?? '';

      if (uid == null || uid.isEmpty) {
        _showError('You must be logged in to submit a withdrawal request.');
        return;
      }

      final firestore = appScope.firestoreService;

      await firestore.addDocument('withdrawal_requests', {
        'userId':      uid,
        'userName':    userName,
        'amount':      amount,
        'bankAccount': _bankCtrl.text.trim(),
        'upiId':       _upiCtrl.text.trim(),
        'remarks':     _remarksCtrl.text.trim(),
        'status':      'PENDING',
        'createdAt':   Timestamp.now(),
        'updatedAt':   Timestamp.now(),
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
    final body  = _submitted ? _buildSuccessView() : _buildForm(store);

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw Funds')),
      body: body,
    );
  }

  Widget _buildSuccessView() {
    return WalletRequestSuccessView(
      title: 'Request Submitted',
      message:
          'Your withdrawal request has been submitted and is pending admin approval.\n'
          'You will be notified once it is processed.',
      onSubmitAnother: () => setState(() {
        _submitted = false;
        _amountCtrl.clear();
        _bankCtrl.clear();
        _upiCtrl.clear();
        _remarksCtrl.clear();
      }),
    );
  }

  Widget _buildForm(dynamic store) {
    final availableBalance = store.balance;
    final usedMargin       = store.usedMargin;
    final freeBalance      = store.freeMargin;
    final uid              = AppScope.of(context).notifier?.user?.uid ?? '';

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
                const Icon(LucideIcons.building2,
                    size: 40, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text('Withdraw Funds',
                    style: TextStyle(
                        fontSize:   24,
                        fontWeight: FontWeight.w700,
                        color:      AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  'Available: ₹${availableBalance.toStringAsFixed(2)}  ·  Free: ₹${freeBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                WalletPendingRequestBanner(
                  collection: 'withdrawal_requests',
                  userId: uid,
                  label: 'withdrawal',
                ),

                // Info banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:  AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.info, size: 14, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only free balance (not margin-locked funds) can be withdrawn. '
                          'Requests are reviewed within 1–2 business days.',
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Amount
                TextFormField(
                  controller: _amountCtrl,
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
                    if (val > availableBalance) {
                      return 'Amount exceeds available balance (₹${availableBalance.toStringAsFixed(2)})';
                    }
                    if (val > freeBalance && usedMargin > 0) {
                      return 'Amount includes margin-locked funds. Max: ₹${freeBalance.toStringAsFixed(2)}';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                WalletQuickAmountChips(
                  amounts: _kQuickAmounts.where((a) => a <= freeBalance).toList(),
                  selected: double.tryParse(_amountCtrl.text.trim()),
                  onSelect: (a) => setState(() {
                    _amountCtrl.text = a.toStringAsFixed(0);
                  }),
                ),
                const SizedBox(height: 18),

                // Bank Account
                TextFormField(
                  controller: _bankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bank Account Details',
                    hintText:  'e.g. HDFC Bank XXXX 1234 / IFSC: HDFC0001234',
                    prefixIcon: Icon(LucideIcons.building2, size: 16),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Bank account details are required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // UPI ID (optional)
                TextFormField(
                  controller: _upiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID (optional)',
                    hintText:  'e.g. yourname@okaxis',
                    prefixIcon: Icon(LucideIcons.smartphone, size: 16),
                  ),
                ),
                const SizedBox(height: 18),

                // Remarks (optional)
                TextFormField(
                  controller: _remarksCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    hintText:  'Any additional note for admin',
                    prefixIcon: Icon(LucideIcons.messageSquare, size: 16),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width:  20,
                            child:  CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Withdrawal Request',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
