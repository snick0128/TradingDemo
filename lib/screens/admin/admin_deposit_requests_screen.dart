import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../config/backend_config.dart';
import '../../data/services/backend_api_service.dart';
import '../../data/services/wallet_ledger_service.dart';
import '../../theme.dart';
import 'admin_ui.dart';

const _kMethodLabels = {
  'gpay': 'Google Pay',
  'phonepe': 'PhonePe',
  'paytm': 'Paytm',
  'upi': 'UPI',
  'bank_transfer': 'Bank Transfer',
};

final _notifyApi = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

class AdminDepositRequestsScreen extends StatefulWidget {
  const AdminDepositRequestsScreen({super.key});

  @override
  State<AdminDepositRequestsScreen> createState() => _AdminDepositRequestsScreenState();
}

class _AdminDepositRequestsScreenState extends State<AdminDepositRequestsScreen> {
  String _statusFilter = 'PENDING';

  @override
  Widget build(BuildContext context) {
    final appScope  = AppScope.of(context);
    final firestore = appScope.firestoreService.raw;

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title:    'Deposit Requests',
            subtitle: 'Verify payment references and approve or reject user deposit requests.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['PENDING', 'APPROVED', 'REJECTED', 'ALL']
                  .map((s) => AdminFilterChip(
                        label:    s,
                        selected: _statusFilter == s,
                        onTap:    () => setState(() => _statusFilter = s),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('deposit_requests')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: AppColors.danger)),
                  );
                }

                final docs = (snapshot.data?.docs ?? []).where((d) {
                  if (_statusFilter == 'ALL') return true;
                  final s = (d.data()['status'] as String? ?? '').toUpperCase();
                  return s == _statusFilter;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.inbox, size: 48, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text('No deposit requests',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                }

                return AdminPanel(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _DepositRow(
                      docId:     docs[index].id,
                      data:      docs[index].data(),
                      firestore: firestore,
                      appScope:  appScope,
                    ),
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

// ── Single deposit row ─────────────────────────────────────────────────────

class _DepositRow extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;
  final AppScope appScope;

  const _DepositRow({
    required this.docId,
    required this.data,
    required this.firestore,
    required this.appScope,
  });

  String get _status        => (data['status']        as String?) ?? 'PENDING';
  double get _amount        => ((data['amount']        as num?) ?? 0).toDouble();
  String get _userId        => (data['userId']         as String?) ?? 'Unknown';
  String get _userName      => (data['userName']       as String?) ?? '';
  String get _paymentMethodLabel =>
      _kMethodLabels[data['paymentMethod'] as String? ?? ''] ?? (data['paymentMethod'] as String? ?? 'N/A');
  String get _referenceCode => (data['referenceCode']  as String?) ?? (data['referenceId'] as String?) ?? '';
  String get _remarks       => (data['remarks']        as String?) ?? '';

  DateTime get _createdAt {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.now();
  }

  Color get _statusColor {
    switch (_status.toUpperCase()) {
      case 'APPROVED': return AppColors.success;
      case 'REJECTED': return AppColors.danger;
      default:         return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt       = DateFormat('dd MMM yyyy, hh:mm a');
    final isPending = _status.toUpperCase() == 'PENDING';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.arrowUpRight, size: 18, color: AppColors.success),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '₹${_amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize:   15,
                          color:      AppColors.textPrimary),
                    ),
                    const Spacer(),
                    if (isPending) ...[
                      _actionButton(context, 'Approve', AppColors.success,
                          () => _showApproveDialog(context)),
                      const SizedBox(width: 8),
                      _actionButton(context, 'Reject', AppColors.danger,
                          () => _showRejectDialog(context)),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:        _statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_status.toUpperCase(),
                            style: TextStyle(
                                color:      _statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize:   11)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_userName.isNotEmpty ? "$_userName · " : ""}$_userId',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_paymentMethodLabel${_referenceCode.isNotEmpty ? "  ·  Ref: $_referenceCode" : ""}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (_remarks.isNotEmpty)
                  Text('Remarks: $_remarks',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(fmt.format(_createdAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext ctx, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border:       Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  // ── Approve deposit ─────────────────────────────────────────────────────────

  void _showApproveDialog(BuildContext context) {
    final noteCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => _ApproveDepositDialog(
        amount:     _amount,
        controller: noteCtrl,
        onConfirm:  () => _approve(context, noteCtrl.text.trim()),
      ),
    );
  }

  Future<void> _approve(BuildContext context, [String note = '']) async {
    final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';
    String? userId;
    double amount = 0;
    try {
      await firestore.runTransaction((tx) async {
        final reqRef  = firestore.collection('deposit_requests').doc(docId);
        final reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) throw Exception('Request not found.');

        final reqData = reqSnap.data()!;
        final status  = (reqData['status'] as String? ?? '').toUpperCase();
        if (status != 'PENDING') throw Exception('Already processed ($status).');

        userId = reqData['userId'] as String;
        amount = ((reqData['amount'] as num?) ?? 0).toDouble();

        final userRef  = firestore.collection('users').doc(userId);
        final userSnap = await tx.get(userRef);
        if (!userSnap.exists) throw Exception('User not found.');

        final userData      = userSnap.data()!;
        final balanceBefore = ((userData['balance'] as num?) ?? 0).toDouble();
        final balanceAfter  = balanceBefore + amount;

        // Credit wallet
        tx.update(userRef, {
          'balance':           balanceAfter,
          'available_balance': balanceAfter,
          'updatedAt':         Timestamp.now(),
        });

        // Mark approved
        tx.update(reqRef, {
          'status':     'APPROVED',
          'approvedBy': adminId,
          'approvedAt': Timestamp.now(),
          'updatedAt':  Timestamp.now(),
          if (note.isNotEmpty) 'adminNote': note,
        });

        final referenceCode = (reqData['referenceCode'] as String?) ?? (reqData['referenceId'] as String?) ?? '';

        // Ledger entry: deposit credit
        WalletLedgerService.writeLedgerEntry(tx, firestore,
          userId:        userId!,
          type:          'DEPOSIT',
          credit:        amount,
          balanceBefore: balanceBefore,
          balanceAfter:  balanceAfter,
          referenceId:   docId,
          referenceType: 'DEPOSIT_REQUEST',
          remarks:       'Deposit approved · ${(reqData['paymentMethod'] as String?) ?? ""} '
                         'ref $referenceCode${note.isNotEmpty ? " · $note" : ""}',
          createdBy:     adminId,
        );

        // Audit log
        WalletLedgerService.writeAuditLog(tx, firestore,
          action:        'DEPOSIT_APPROVE',
          userId:        userId!,
          adminId:       adminId,
          balanceBefore: balanceBefore,
          balanceAfter:  balanceAfter,
          amount:        amount,
          referenceId:   docId,
          referenceType: 'DEPOSIT_REQUEST',
          remarks:       'Deposit of ₹${amount.toStringAsFixed(2)} approved${note.isNotEmpty ? ": $note" : ""}',
        );
      });

      if (userId != null) {
        try {
          await _notifyApi.sendNotificationToUserId(
            userId: userId!,
            title: 'Deposit Approved',
            message: '₹${amount.toStringAsFixed(2)} has been added to your wallet.',
            data: {'type': 'deposit_approved', 'depositId': docId},
          );
        } catch (_) {
          // Non-fatal — balance is already credited.
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('Deposit of ₹${_amount.toStringAsFixed(2)} approved.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ── Reject deposit ──────────────────────────────────────────────────────────

  void _showRejectDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => _RejectDepositDialog(
        amount:     _amount,
        controller: reasonCtrl,
        onConfirm:  () => _reject(context, reasonCtrl.text.trim()),
      ),
    );
  }

  Future<void> _reject(BuildContext context, String reason) async {
    final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';
    String? userId;
    try {
      final reqRef = firestore.collection('deposit_requests').doc(docId);

      await firestore.runTransaction((tx) async {
        final snap = await tx.get(reqRef);
        if (!snap.exists) throw Exception('Request not found.');
        final status = (snap.data()!['status'] as String? ?? '').toUpperCase();
        if (status != 'PENDING') throw Exception('Already processed ($status).');

        tx.update(reqRef, {
          'status':          'REJECTED',
          'rejectionReason': reason,
          'rejectedBy':      adminId,
          'rejectedAt':      Timestamp.now(),
          'updatedAt':       Timestamp.now(),
        });

        userId = snap.data()!['userId'] as String;
        final amount = ((snap.data()!['amount'] as num?) ?? 0).toDouble();

        WalletLedgerService.writeAuditLog(tx, firestore,
          action:        'DEPOSIT_REJECT',
          userId:        userId!,
          adminId:       adminId,
          balanceBefore: 0,
          balanceAfter:  0,
          amount:        amount,
          referenceId:   docId,
          referenceType: 'DEPOSIT_REQUEST',
          remarks:       'Rejected: $reason',
        );
      });

      if (userId != null) {
        try {
          await _notifyApi.sendNotificationToUserId(
            userId: userId!,
            title: 'Deposit Could Not Be Verified',
            message: reason.isNotEmpty
                ? 'Your deposit of ₹${_amount.toStringAsFixed(2)} could not be verified: $reason'
                : 'Your deposit of ₹${_amount.toStringAsFixed(2)} could not be verified.',
            data: {'type': 'deposit_rejected', 'depositId': docId},
          );
        } catch (_) {
          // Non-fatal — rejection is already recorded.
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deposit request rejected.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejection failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

// ── Reject dialog ─────────────────────────────────────────────────────────────

// ── Approve dialog ────────────────────────────────────────────────────────────

class _ApproveDepositDialog extends StatefulWidget {
  final double amount;
  final TextEditingController controller;
  final Future<void> Function() onConfirm;

  const _ApproveDepositDialog({
    required this.amount,
    required this.controller,
    required this.onConfirm,
  });

  @override
  State<_ApproveDepositDialog> createState() => _ApproveDepositDialogState();
}

class _ApproveDepositDialogState extends State<_ApproveDepositDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.checkCircle, size: 18, color: AppColors.success),
          ),
          const SizedBox(width: 12),
          const Text('Approve Deposit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount: ₹${widget.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Wallet will be credited immediately.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText:  'e.g. Verified against bank statement',
              border:    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    await widget.onConfirm();
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Approve', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _RejectDepositDialog extends StatefulWidget {
  final double amount;
  final TextEditingController controller;
  final Future<void> Function() onConfirm;

  const _RejectDepositDialog({
    required this.amount,
    required this.controller,
    required this.onConfirm,
  });

  @override
  State<_RejectDepositDialog> createState() => _RejectDepositDialogState();
}

class _RejectDepositDialogState extends State<_RejectDepositDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.xCircle, size: 18, color: AppColors.danger),
          ),
          const SizedBox(width: 12),
          const Text('Reject Deposit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount: ₹${widget.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Wallet balance will NOT be credited.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Rejection Reason',
              hintText:  'e.g. Payment reference could not be verified',
              border:    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    await widget.onConfirm();
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reject', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
