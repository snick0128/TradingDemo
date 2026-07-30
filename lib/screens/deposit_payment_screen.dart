import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../app/app_scope.dart';
import '../data/services/deposit_service.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'deposit_status_screen.dart';

class _MethodMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _MethodMeta(this.label, this.icon, this.color);
}

// Mirrors the choices offered on the previous screen (DepositPaymentMethodScreen)
// so this screen can honor — rather than re-ask — the method the user already
// picked there.
const _kMethodMeta = {
  'gpay': _MethodMeta('Google Pay', LucideIcons.smartphone, Color(0xFF4285F4)),
  'phonepe': _MethodMeta('PhonePe', LucideIcons.smartphone, Color(0xFF5F259F)),
  'paytm': _MethodMeta('Paytm', LucideIcons.smartphone, Color(0xFF00BAF2)),
  'upi': _MethodMeta('UPI App', LucideIcons.qrCode, AppColors.primary),
};

/// Step 3 of the deposit flow. Shows a QR code + UPI deep links so the user
/// can pay from any device. Detects the return-from-payment-app moment via
/// [WidgetsBindingObserver] and silently creates the deposit request with
/// zero user input — a single "I've Made the Payment" tap is kept only as a
/// fallback for the (very common) case where payment happens by scanning
/// this screen's QR with a *different* phone, which never triggers an
/// app-lifecycle event on this device at all.
class DepositPaymentScreen extends StatefulWidget {
  final double amount;
  final String paymentMethod;

  const DepositPaymentScreen({super.key, required this.amount, required this.paymentMethod});

  @override
  State<DepositPaymentScreen> createState() => _DepositPaymentScreenState();
}

class _DepositPaymentScreenState extends State<DepositPaymentScreen> with WidgetsBindingObserver {
  late final DocumentReference<Map<String, dynamic>> _ref;
  late final String _referenceCode;

  bool _hasLeftApp = false;
  bool _creating = false;
  bool _created = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ref = DepositService.prepareRef(FirebaseFirestore.instance);
    _referenceCode = DepositService.referenceCodeFor(_ref);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _hasLeftApp = true;
    } else if (state == AppLifecycleState.resumed && _hasLeftApp && !_created && !_creating) {
      _confirmPayment(paymentMethod: widget.paymentMethod);
    }
  }

  Future<void> _confirmPayment({required String paymentMethod}) async {
    if (_creating || _created) return;
    setState(() => _creating = true);

    final appScope = AppScope.of(context);
    final user     = appScope.notifier?.user;
    if (user == null) {
      if (mounted) setState(() => _creating = false);
      return;
    }

    try {
      await DepositService.createDepositRequest(
        ref: _ref,
        userId: user.uid,
        userName: user.name,
        email: user.email,
        phone: '',
        amount: widget.amount,
        paymentMethod: paymentMethod,
        referenceCode: _referenceCode,
      );
      _created = true;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DepositStatusScreen(depositId: _ref.id)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
    );
  }

  void _share(String upiUri, String upiId) {
    Share.share('Pay ₹${widget.amount.toStringAsFixed(2)} to $upiId via UPI: $upiUri');
  }

  @override
  Widget build(BuildContext context) {
    final payment = TradingScope.of(context).paymentConfig;

    if (payment.upiId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Payment details are not configured yet. Please contact support.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    // Generic upi:// intent — every UPI app's scanner understands this, so
    // the QR code always uses it regardless of which method was chosen.
    final upiUri = DepositService.buildUpiUri(
      upiId: payment.upiId,
      merchantName: payment.merchantName,
      amount: widget.amount,
      referenceCode: _referenceCode,
    );
    final isBankTransfer = widget.paymentMethod == 'bank_transfer';
    final methodMeta = _kMethodMeta[widget.paymentMethod] ?? _kMethodMeta['upi']!;
    // App-specific intent for the "Pay with X" button — routes straight to
    // the app the user picked on the previous screen instead of letting the
    // OS pick whatever it resolves the generic upi:// intent to.
    final appUri = DepositService.buildUpiUri(
      upiId: payment.upiId,
      merchantName: payment.merchantName,
      amount: widget.amount,
      referenceCode: _referenceCode,
      scheme: DepositService.schemeForMethod(widget.paymentMethod),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Complete Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Amount + merchant card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D2B6B), Color(0xFF1565C0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1565C0).withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('₹${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('to ${payment.merchantName}',
                          style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(payment.upiId,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(
                            onPressed: () => _copy(payment.upiId, 'UPI ID'),
                            icon: const Icon(LucideIcons.copy, size: 16, color: Colors.white),
                            tooltip: 'Copy UPI ID',
                          ),
                          IconButton(
                            onPressed: () => _share(upiUri, payment.upiId),
                            icon: const Icon(LucideIcons.share2, size: 16, color: Colors.white),
                            tooltip: 'Share',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (!isBankTransfer) ...[
                  // QR code
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: upiUri,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Scan with any UPI app to pay',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Single CTA reflecting the method already chosen on the previous
                  // screen — no re-asking which app to use.
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => DepositService.launchUpiUri(appUri),
                      icon: Icon(methodMeta.icon, color: methodMeta.color, size: 18),
                      label: Text('Pay with ${methodMeta.label}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: methodMeta.color)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: methodMeta.color.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'Transfer the amount via IMPS/NEFT using the UPI ID above (most banks '
                      'support sending to a UPI-linked VPA directly from net banking).',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.info, size: 14, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Once you pay, come back here — we\'ll detect it automatically. '
                          'Paying from another device? Tap the button below once done.',
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _creating ? null : () => _confirmPayment(paymentMethod: widget.paymentMethod),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _creating
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text("I've Made the Payment", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
