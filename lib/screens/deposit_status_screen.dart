import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'settings/help_support_screen.dart';

/// Step 4 of the deposit flow — a live view of `deposit_requests/{depositId}`
/// that animates between Pending / Approved / Rejected as admin acts on it,
/// with zero polling (Firestore snapshot listener).
class DepositStatusScreen extends StatelessWidget {
  final String depositId;

  const DepositStatusScreen({super.key, required this.depositId});

  // Falls back to the dashboard when there's nothing to pop — this screen can
  // be reached without a normal push stack (e.g. a fresh page load/reload
  // while a deposit is pending), in which case Navigator.canPop() is false
  // and popping would silently do nothing, leaving the user stuck here.
  void _backToFunds(BuildContext context) {
    final nav = Navigator.of(context);
    if (!nav.canPop()) {
      context.go('/app/dashboard');
      return;
    }
    while (nav.canPop()) {
      nav.pop();
    }
  }

  void _tryAgain(BuildContext context) {
    final nav = Navigator.of(context);
    if (!nav.canPop()) {
      context.go('/app/dashboard');
      return;
    }
    if (nav.canPop()) nav.pop();
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deposit Status'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('deposit_requests').doc(depositId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
            return const Center(child: CircularProgressIndicator());
          }
          final req = DepositRequest.fromFirestore(depositId, snapshot.data!.data()!);

          switch (req.status.toUpperCase()) {
            case 'APPROVED':
              return _ApprovedView(request: req, onDone: () => _backToFunds(context));
            case 'REJECTED':
              return _RejectedView(
                request: req,
                onTryAgain: () => _tryAgain(context),
              );
            default:
              return _PendingView(request: req, onClose: () => _backToFunds(context));
          }
        },
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  final DepositRequest request;
  final VoidCallback onClose;
  const _PendingView({required this.request, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(LucideIcons.clock, size: 40, color: AppColors.warning),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                  begin: const Offset(1, 1), end: const Offset(1.08, 1.08), duration: 900.ms),
            const SizedBox(height: 28),
            Text('₹${request.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Verifying your payment',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'We\'ve received your request and are confirming the payment. '
              'This usually takes a few minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            _Timeline(steps: const [
              _TimelineStep('Request submitted', done: true),
              _TimelineStep('Verifying payment', done: false, active: true),
              _TimelineStep('Wallet credited', done: false),
            ]),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Ref: ${request.referenceCode}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, letterSpacing: 0.4)),
            ),
            const SizedBox(height: 28),
            // Verification can take a few minutes (or longer) — the user must
            // be able to leave and keep using the app while it's pending.
            // Leaving here does not cancel the request; it stays PENDING in
            // Firestore and is still visible under "Pending Deposits".
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onClose,
                child: const Text('Back to Wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;
  final bool active;
  const _TimelineStep(this.label, {required this.done, this.active = false});
}

class _Timeline extends StatelessWidget {
  final List<_TimelineStep> steps;
  const _Timeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (i) {
        final s = steps[i];
        final color = s.done
            ? AppColors.success
            : (s.active ? AppColors.warning : AppColors.border);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: s.done ? AppColors.success : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: s.done
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : (s.active
                          ? Center(
                              child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                              ),
                            )
                          : null),
                ),
                if (i < steps.length - 1)
                  Container(width: 2, height: 28, color: color.withOpacity(0.4)),
              ],
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                s.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: s.active ? FontWeight.w700 : FontWeight.w500,
                  color: s.done || s.active ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ApprovedView extends StatelessWidget {
  final DepositRequest request;
  final VoidCallback onDone;
  const _ApprovedView({required this.request, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final balance = TradingScope.of(context).balance;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(LucideIcons.checkCircle2, size: 44, color: AppColors.success),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut, begin: const Offset(0.4, 0.4), end: const Offset(1, 1)),
            const SizedBox(height: 24),
            Text('₹${request.amount.toStringAsFixed(2)} Added',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Your deposit has been verified and credited to your wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.success.withOpacity(0.25)),
              ),
              child: Column(
                children: [
                  const Text('New Wallet Balance', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('₹${balance.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectedView extends StatelessWidget {
  final DepositRequest request;
  final VoidCallback onTryAgain;
  const _RejectedView({required this.request, required this.onTryAgain});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(LucideIcons.xCircle, size: 44, color: AppColors.danger),
            ).animate().shake(duration: 400.ms, hz: 4),
            const SizedBox(height: 24),
            Text('Couldn\'t verify ₹${request.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if ((request.rejectionReason ?? '').isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withOpacity(0.25)),
                ),
                child: Text(request.rejectionReason!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.4)),
              )
            else
              const Text(
                'We could not confirm this payment. Please try again or contact support.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onTryAgain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Try Again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
                child: const Text('Contact Support'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
