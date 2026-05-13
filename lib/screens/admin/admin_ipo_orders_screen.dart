import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_scope.dart';
import '../../theme.dart';
import 'admin_ui.dart';

class AdminIpoOrdersScreen extends StatefulWidget {
  const AdminIpoOrdersScreen({super.key});

  @override
  State<AdminIpoOrdersScreen> createState() => _AdminIpoOrdersScreenState();
}

class _AdminIpoOrdersScreenState extends State<AdminIpoOrdersScreen> {
  String _statusFilter = 'PENDING';

  @override
  Widget build(BuildContext context) {
    final appScope = AppScope.of(context);
    final db = appScope.firestoreService.raw;

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title: 'IPO Orders',
            subtitle: 'Approve or reject user IPO applications.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip('PENDING'),
                _statusChip('APPROVED'),
                _statusChip('REJECTED'),
                _statusChip('ALL'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('ipo_orders')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load IPO orders: ${snap.error}',
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  );
                }

                final docs = (snap.data?.docs ?? []).where((d) {
                  if (_statusFilter == 'ALL') return true;
                  final status = (d.data()['status'] as String? ?? '')
                      .toUpperCase();
                  return status == _statusFilter;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No IPO orders found.'));
                }

                return AdminPanel(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _row(context, appScope, docs[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    return AdminFilterChip(
      label: status,
      selected: _statusFilter == status,
      onTap: () => setState(() => _statusFilter = status),
    );
  }

  Widget _row(
    BuildContext context,
    AppScope appScope,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final status = (d['status'] as String? ?? 'PENDING').toUpperCase();
    final isPending = status == 'PENDING';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final fmtTime = createdAt != null
        ? DateFormat('dd MMM HH:mm').format(createdAt)
        : '—';

    final userId = (d['userId'] as String? ?? '—');
    final company =
        (d['companyName'] as String? ?? (d['ipoId'] as String? ?? 'IPO'));
    final blockedAmount = ((d['blockedAmount'] as num?) ?? 0).toDouble();
    final batchPrice = ((d['batchPrice'] as num?) ?? 0).toDouble();
    final lots = ((d['lots'] as num?) ?? 0).toInt();
    final bidPrice = ((d['bidPrice'] as num?) ?? 0).toDouble();

    Color statusColor;
    switch (status) {
      case 'APPROVED':
        statusColor = AppColors.success;
        break;
      case 'REJECTED':
        statusColor = AppColors.danger;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              fmtTime,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              userId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(company, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Lots:$lots  Bid:₹${bidPrice.toStringAsFixed(0)}\nBatch:₹${batchPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${blockedAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              status,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isPending) ...[
            const SizedBox(width: 8),
            _actionBtn(
              context,
              'Approve',
              AppColors.success,
              () => _approveOrder(appScope, doc),
            ),
            const SizedBox(width: 6),
            _actionBtn(
              context,
              'Reject',
              AppColors.danger,
              () => _rejectOrder(appScope, doc),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context,
    String label,
    Color color,
    Future<void> Function() onTap,
  ) {
    return InkWell(
      onTap: () async {
        try {
          await onTap();
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$label successful')));
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label failed: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _approveOrder(
    AppScope appScope,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final db = appScope.firestoreService.raw;
    final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';

    await db.runTransaction((tx) async {
      final orderRef = db.collection('ipo_orders').doc(doc.id);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw Exception('Order not found.');
      final order = orderSnap.data()!;

      final status = (order['status'] as String? ?? 'PENDING').toUpperCase();
      if (status != 'PENDING') throw Exception('Order already processed.');

      final userId = order['userId'] as String;
      final blockedAmount = ((order['blockedAmount'] as num?) ?? 0).toDouble();
      final batchPrice = ((order['batchPrice'] as num?) ?? 0).toDouble();
      final listingGainPct = ((order['listingGainPercent'] as num?) ?? 0)
          .toDouble();
      final profitAmount = batchPrice * listingGainPct / 100.0;
      final creditAmount = blockedAmount + profitAmount;

      final userRef = db.collection('users').doc(userId);
      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) throw Exception('User not found.');
      final userData = userSnap.data()!;
      final balance =
          ((userData['balance'] as num?) ??
                  (userData['available_balance'] as num?) ??
                  0)
              .toDouble();
      final newBalance = balance + creditAmount;

      tx.update(userRef, {
        'balance': newBalance,
        'available_balance': newBalance,
        'updatedAt': Timestamp.now(),
      });

      tx.update(orderRef, {
        'status': 'APPROVED',
        'profitAmount': profitAmount,
        'creditAmount': creditAmount,
        'approvedBy': adminId,
        'approvedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<void> _rejectOrder(
    AppScope appScope,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    final blockedAmount = ((d['blockedAmount'] as num?) ?? 0).toDouble();
    final cutController = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject IPO Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Blocked amount: ₹${blockedAmount.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            const Text(
              'How much should be cut from applied amount?',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cutController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cut amount',
                prefixText: '₹',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cutRaw = double.tryParse(cutController.text.trim()) ?? 0;
              final cutAmount = cutRaw.clamp(0, blockedAmount).toDouble();
              final refundAmount = (blockedAmount - cutAmount).toDouble();
              final db = appScope.firestoreService.raw;
              final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';

              await db.runTransaction((tx) async {
                final orderRef = db.collection('ipo_orders').doc(doc.id);
                final orderSnap = await tx.get(orderRef);
                if (!orderSnap.exists) throw Exception('Order not found.');
                final order = orderSnap.data()!;
                final status = (order['status'] as String? ?? 'PENDING')
                    .toUpperCase();
                if (status != 'PENDING')
                  throw Exception('Order already processed.');

                final userId = order['userId'] as String;
                final userRef = db.collection('users').doc(userId);
                final userSnap = await tx.get(userRef);
                if (!userSnap.exists) throw Exception('User not found.');

                final userData = userSnap.data()!;
                final balance =
                    ((userData['balance'] as num?) ??
                            (userData['available_balance'] as num?) ??
                            0)
                        .toDouble();
                final newBalance = balance + refundAmount;

                tx.update(userRef, {
                  'balance': newBalance,
                  'available_balance': newBalance,
                  'updatedAt': Timestamp.now(),
                });

                tx.update(orderRef, {
                  'status': 'REJECTED',
                  'cutAmount': cutAmount,
                  'refundAmount': refundAmount,
                  'rejectedBy': adminId,
                  'rejectedAt': Timestamp.now(),
                  'updatedAt': Timestamp.now(),
                });
              });

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
