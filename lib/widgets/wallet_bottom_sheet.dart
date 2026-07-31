import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared chrome for every wallet-flow bottom sheet (Add Funds, Withdraw,
/// ...): drag handle, title row with an optional close (X), rounded top
/// corners. Keeping this in one place is what makes every step across every
/// wallet flow look like part of the same system instead of independently
/// drifting copies.
class WalletSheetShell extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;
  final Widget child;

  const WalletSheetShell({super.key, required this.title, required this.onClose, required this.child});

  @override
  Widget build(BuildContext context) {
    // Shift the whole sheet above the on-screen keyboard, and let content
    // scroll instead of overflowing — without this, a sheet with more than a
    // couple of text fields (e.g. Add Bank Account) gets its lower fields,
    // error text, and submit button pushed off-screen and unreachable the
    // moment the keyboard opens, which reads as "broken" even though the
    // widgets underneath are working fine.
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D)),
                    ),
                    if (onClose != null)
                      InkWell(
                        onTap: onClose,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Color(0xFFF5F5F5), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF757575)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Generic "processing → success" final step shared by every wallet flow —
/// runs [action] once on mount so every flow shows the literal same
/// spinner/progress-bar animation and timing, not just a visually similar
/// re-implementation. On success shows a green check + [successBuilder]'s
/// content; on failure shows a plain error state instead.
class WalletProcessingSheet extends StatefulWidget {
  final Future<Object?> Function() action;
  final String processingTitle;
  final String processingMessage;
  final String successTitle;
  final Widget Function(BuildContext context, Object? result) successBuilder;
  final String Function(Object error) errorMessage;

  const WalletProcessingSheet({
    super.key,
    required this.action,
    this.processingTitle = 'Processing Payment',
    this.processingMessage = 'Please wait while we confirm your payment...',
    required this.successTitle,
    required this.successBuilder,
    required this.errorMessage,
  });

  @override
  State<WalletProcessingSheet> createState() => _WalletProcessingSheetState();
}

class _WalletProcessingSheetState extends State<WalletProcessingSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  Object? _result;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final result = await widget.action();
      // A brief, deliberate pause so "Processing" reads as real work rather
      // than flashing past — the write itself usually resolves in well under
      // that time.
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _result = result;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = widget.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return WalletSheetShell(
        title: 'Error',
        onClose: () => Navigator.pop(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
            const SizedBox(height: 12),
          ],
        ),
      );
    }

    if (_done) {
      return WalletSheetShell(
        title: widget.successTitle,
        onClose: () => Navigator.pop(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, size: 34, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            widget.successBuilder(context, _result),
          ],
        ),
      );
    }

    return WalletSheetShell(
      title: 'Processing',
      onClose: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RotationTransition(
            turns: _spinCtrl,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.autorenew, size: 30, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(widget.processingTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
          const SizedBox(height: 6),
          Text(widget.processingMessage,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E))),
          const Text('Do not close or press Back', style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E))),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0xFFF0F0F0),
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
