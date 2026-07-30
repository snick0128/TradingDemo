import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';

final _inr = NumberFormat('#,##,##0', 'en_IN');

/// Row of tappable quick-amount chips shown above an amount field so the
/// user doesn't have to type a round number by hand.
class WalletQuickAmountChips extends StatelessWidget {
  final List<double> amounts;
  final double? selected;
  final ValueChanged<double> onSelect;

  const WalletQuickAmountChips({
    super.key,
    required this.amounts,
    required this.onSelect,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: amounts.map((a) {
        final isSelected = selected == a;
        return InkWell(
          onTap: () => onSelect(a),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.25),
              ),
            ),
            child: Text(
              '₹${_inr.format(a)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Banner shown above a deposit/withdraw form when the user already has a
/// pending request of that kind, so they see its status instead of
/// submitting a duplicate blind.
class WalletPendingRequestBanner extends StatelessWidget {
  final String collection;
  final String userId;
  final String label; // e.g. 'deposit' or 'withdrawal'

  const WalletPendingRequestBanner({
    super.key,
    required this.collection,
    required this.userId,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final data   = docs.first.data();
        final amount = ((data['amount'] as num?) ?? 0).toDouble();
        final tsRaw  = data['createdAt'];
        final createdAt = tsRaw is Timestamp ? tsRaw.toDate() : null;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.clock, size: 16, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₹${amount.toStringAsFixed(2)} $label request pending review',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Submitted ${DateFormat('dd MMM, hh:mm a').format(createdAt)} · admin review usually within 1–2 business days',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Status chip used across deposit/withdrawal history cards.
class WalletStatusChip extends StatelessWidget {
  final String status;
  const WalletStatusChip({super.key, required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'APPROVED': return AppColors.success;
      case 'REJECTED': return AppColors.danger;
      default:         return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _color, letterSpacing: 0.3),
      ),
    );
  }
}

/// One card in a deposit/withdrawal history list — amount, status chip,
/// date, a subtitle (payment method / bank details), and the admin's
/// rejection reason when present. Shared so both histories look identical.
class WalletHistoryCard extends StatelessWidget {
  final double amount;
  final String status;
  final DateTime date;
  final String subtitle;
  final String? rejectionReason;
  final bool isCredit; // true = money in (deposit), false = money out (withdrawal)

  const WalletHistoryCard({
    super.key,
    required this.amount,
    required this.status,
    required this.date,
    required this.subtitle,
    this.rejectionReason,
    required this.isCredit,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isCredit ? AppColors.success : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(
                  isCredit ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                  size: 16,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              WalletStatusChip(status: status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(date),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if ((rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Admin note: $rejectionReason',
                  style: const TextStyle(fontSize: 11, color: AppColors.danger, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Success confirmation view shown after a deposit/withdraw request is
/// submitted — shared so both screens look and behave the same way.
class WalletRequestSuccessView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onSubmitAnother;

  const WalletRequestSuccessView({
    super.key,
    required this.title,
    required this.message,
    required this.onSubmitAnother,
  });

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(LucideIcons.checkCircle, size: 36, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            Text(title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: onSubmitAnother,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Submit Another Request',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
