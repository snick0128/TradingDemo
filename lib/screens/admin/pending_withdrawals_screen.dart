import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../theme.dart';
import 'admin_ui.dart';

class PendingWithdrawalsScreen extends StatelessWidget {
  const PendingWithdrawalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final firestore = appScope?.firestoreService.raw;

    if (firestore == null) {
      return const AdminPage(
        child: Center(child: Text('Firebase not available.')),
      );
    }

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title: 'Pending Withdrawals',
            subtitle: 'Review and action user withdrawal requests.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('withdrawal_requests')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading withdrawals: ${snapshot.error}',
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.inbox,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No withdrawal requests',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return AdminPanel(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return _WithdrawalRow(
                        docId: doc.id,
                        data: doc.data(),
                        firestore: firestore,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;

  const _WithdrawalRow({
    required this.docId,
    required this.data,
    required this.firestore,
  });

  String get _status => (data['status'] as String?) ?? 'PENDING';
  double get _amount => ((data['amount'] as num?) ?? 0).toDouble();
  String get _userId => (data['userId'] as String?) ?? 'Unknown';
  String get _bank => (data['bankAccount'] as String?) ?? 'N/A';
  DateTime get _createdAt {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.now();
  }

  Color get _statusColor {
    switch (_status.toUpperCase()) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');
    final isPending = _status.toUpperCase() == 'PENDING';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          LucideIcons.arrowDownLeft,
          size: 18,
          color: AppColors.primary,
        ),
      ),
      title: Text(
        '₹${_amount.toStringAsFixed(2)}',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        '$_bank\nUser: $_userId\n${fmt.format(_createdAt)}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      isThreeLine: true,
      trailing: isPending
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _actionButton(
                  context,
                  label: 'Approve',
                  color: AppColors.success,
                  onTap: () => _updateStatus(context, 'APPROVED'),
                ),
                const SizedBox(width: 8),
                _actionButton(
                  context,
                  label: 'Reject',
                  color: AppColors.danger,
                  onTap: () => _updateStatus(context, 'REJECTED'),
                ),
              ],
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _status,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    try {
      await firestore.collection('withdrawal_requests').doc(docId).update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Withdrawal $newStatus successfully.'),
            backgroundColor: newStatus == 'APPROVED'
                ? AppColors.success
                : AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}
