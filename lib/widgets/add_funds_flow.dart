import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../data/services/deposit_service.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'wallet_bottom_sheet.dart';
import 'wallet_fund_widgets.dart';

const _kQuickAmounts = [1000.0, 2500.0, 5000.0, 10000.0, 25000.0, 50000.0];

/// Sentinel returned by the Payment Method sheet's "Back" button — distinct
/// from `null` (which means the whole flow was cancelled) so the orchestrator
/// below knows to reopen the Amount sheet instead of giving up entirely.
const _kBack = '__back__';

/// Deposit flow — Amount → Payment Method → Processing, as sequential modal
/// bottom sheets over the current screen (matches the wallet screen's own
/// visual language rather than a full-page push). Still goes through the
/// same [DepositService] pending-request write everything else does — this
/// only changes presentation, not the admin-approval requirement.
Future<void> showAddFundsFlow(BuildContext context) async {
  final payment = TradingScope.of(context).paymentConfig;
  if (!payment.enabled) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DepositsUnavailableSheet(),
    );
    return;
  }

  double? amount;
  while (context.mounted) {
    amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddFundsAmountSheet(initialAmount: amount),
    );
    if (amount == null || !context.mounted) return;

    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentMethodSheet(amount: amount!),
    );
    if (!context.mounted) return;
    if (method == null) return; // closed via X / backdrop — cancel entirely
    if (method == _kBack) continue; // "Back" — reopen the amount sheet

    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _buildDepositProcessingSheet(sheetContext, amount!, method),
      );
    }
    return;
  }
}

class _DepositsUnavailableSheet extends StatelessWidget {
  const _DepositsUnavailableSheet();

  @override
  Widget build(BuildContext context) {
    final support = TradingScope.of(context).supportConfig;
    return WalletSheetShell(
      title: 'Add Funds',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(LucideIcons.clock, size: 30, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('Deposits Coming Soon',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
          const SizedBox(height: 8),
          Text(
            support.phoneNumber.isNotEmpty
                ? 'Contact support at ${support.phoneNumber} to add funds.'
                : 'Please contact your administrator to add funds.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.5),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Step 1: Amount ───────────────────────────────────────────────────────────

class _AddFundsAmountSheet extends StatefulWidget {
  final double? initialAmount;
  const _AddFundsAmountSheet({this.initialAmount});

  @override
  State<_AddFundsAmountSheet> createState() => _AddFundsAmountSheetState();
}

class _AddFundsAmountSheetState extends State<_AddFundsAmountSheet> {
  late final _amountCtrl = TextEditingController(
    text: widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(0) : '',
  );
  double? _selectedQuickAmount;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());
  bool get _hasAmount => (_amount ?? 0) > 0;

  void _submit() {
    final amount = _amount;
    if (amount == null || amount <= 0) return;
    Navigator.pop(context, amount);
  }

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Add Funds',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('Enter Amount', style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _selectedQuickAmount = null),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D)),
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    prefixStyle: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E)),
                    hintText: '0',
                    hintStyle: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Color(0xFFBDBDBD)),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'QUICK ADD',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E), letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          WalletQuickAmountChips(
            amounts: _kQuickAmounts,
            selected: _selectedQuickAmount,
            onSelect: (a) => setState(() {
              _selectedQuickAmount = a;
              _amountCtrl.text = a.toStringAsFixed(0);
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _hasAmount ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _hasAmount ? 'Add ₹${_amount!.toStringAsFixed(0)}' : 'Enter an amount',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Payment Method ───────────────────────────────────────────────────

class _PaymentMethod {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const _PaymentMethod(this.key, this.label, this.description, this.icon, this.color);
}

const _kPaymentMethods = [
  _PaymentMethod('upi_qr', 'UPI / QR', 'GPay, PhonePe, BHIM, Paytm', LucideIcons.qrCode, Color(0xFF7B1FA2)),
  _PaymentMethod('net_banking', 'Net Banking', 'SBI, HDFC, ICICI, Axis & more', LucideIcons.building2, Color(0xFF546E7A)),
  _PaymentMethod('card', 'Debit / Credit Card', 'Visa, Mastercard, RuPay', LucideIcons.creditCard, Color(0xFF1565C0)),
];

class _PaymentMethodSheet extends StatefulWidget {
  final double amount;
  const _PaymentMethodSheet({required this.amount});

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  String? _selected = _kPaymentMethods.first.key;

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Payment Method',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Adding to TradeKosh',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                Text('₹${widget.amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'CHOOSE PAYMENT METHOD',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E), letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          ..._kPaymentMethods.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaymentMethodTile(
                  method: m,
                  selected: _selected == m.key,
                  onTap: () => setState(() => _selected = m.key),
                ),
              )),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.success),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '256-bit encrypted · PCI-DSS compliant · RBI regulated',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _kBack),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D0D0D),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Back', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Pay ₹${widget.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
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

class _PaymentMethodTile extends StatelessWidget {
  final _PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentMethodTile({required this.method, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE0E0E0), width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: method.color, shape: BoxShape.circle),
              child: Icon(method.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.label,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
                  const SizedBox(height: 2),
                  Text(method.description, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.primary : const Color(0xFFBDBDBD), width: 2),
                color: selected ? AppColors.primary : Colors.transparent,
              ),
              child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 3: Processing → success ─────────────────────────────────────────────

Widget _buildDepositProcessingSheet(BuildContext context, double amount, String paymentMethod) {
  return WalletProcessingSheet(
    action: () async {
      final user = AppScope.of(context).notifier?.user;
      if (user == null) throw Exception('You need to be signed in to add funds.');
      final ref = DepositService.prepareRef(FirebaseFirestore.instance);
      final referenceCode = DepositService.referenceCodeFor(ref);
      await DepositService.createDepositRequest(
        ref: ref,
        userId: user.uid,
        userName: user.name,
        email: user.email,
        phone: '',
        amount: amount,
        paymentMethod: paymentMethod,
        referenceCode: referenceCode,
      );
      return referenceCode;
    },
    successTitle: 'Request Submitted',
    errorMessage: (e) => 'Could not submit request: $e',
    successBuilder: (context, result) => Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('₹${amount.toStringAsFixed(0)} pending verification',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
        const SizedBox(height: 8),
        Text(
          'Your deposit request has been submitted and will be credited once verified. '
          'Reference: ${result ?? ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF757575), height: 1.5),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    ),
  );
}
