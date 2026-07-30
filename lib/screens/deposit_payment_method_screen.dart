import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import 'deposit_payment_screen.dart';

class _PaymentMethodOption {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _PaymentMethodOption({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const _kMethods = [
  _PaymentMethodOption(
    key: 'gpay',
    label: 'Google Pay',
    description: 'Pay instantly using Google Pay',
    icon: LucideIcons.smartphone,
    color: Color(0xFF4285F4),
  ),
  _PaymentMethodOption(
    key: 'phonepe',
    label: 'PhonePe',
    description: 'Pay instantly using PhonePe',
    icon: LucideIcons.smartphone,
    color: Color(0xFF5F259F),
  ),
  _PaymentMethodOption(
    key: 'paytm',
    label: 'Paytm',
    description: 'Pay instantly using Paytm',
    icon: LucideIcons.smartphone,
    color: Color(0xFF00BAF2),
  ),
  _PaymentMethodOption(
    key: 'upi',
    label: 'Any UPI App',
    description: 'Scan the QR with any UPI app',
    icon: LucideIcons.qrCode,
    color: AppColors.primary,
  ),
  _PaymentMethodOption(
    key: 'bank_transfer',
    label: 'Bank Transfer',
    description: 'IMPS / NEFT to our bank-linked UPI ID',
    icon: LucideIcons.building2,
    color: Color(0xFF00897B),
  ),
];

/// Step 2 of the deposit flow — pick how you'll pay. Purely a UI choice that
/// changes what Step 3 renders (QR + UPI deep link vs. bank details).
class DepositPaymentMethodScreen extends StatefulWidget {
  final double amount;

  const DepositPaymentMethodScreen({super.key, required this.amount});

  @override
  State<DepositPaymentMethodScreen> createState() => _DepositPaymentMethodScreenState();
}

class _DepositPaymentMethodScreenState extends State<DepositPaymentMethodScreen> {
  String? _selected = _kMethods.first.key;

  void _continue() {
    final method = _selected;
    if (method == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DepositPaymentScreen(amount: widget.amount, paymentMethod: method),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Method')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${widget.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Choose how you\'d like to pay',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      ..._kMethods.map((m) => _MethodCard(
                            option: m,
                            selected: _selected == m.key,
                            onTap: () => setState(() => _selected = m.key),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selected == null ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final _PaymentMethodOption option;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? option.color.withOpacity(0.06) : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? option.color : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: option.color.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: option.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(option.icon, color: option.color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(option.description,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? option.color : AppColors.border, width: 2),
                    color: selected ? option.color : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
