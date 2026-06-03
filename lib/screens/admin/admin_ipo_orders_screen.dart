import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../data/services/wallet_ledger_service.dart';
import '../../models/trading_models.dart';
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
    final db       = appScope.firestoreService.raw;

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title:    'IPO Requests',
            subtitle: 'Settle IPO applications — enter profit or loss amount.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['PENDING', 'APPROVED', 'REJECTED', 'ALL']
                  .map((s) => AdminFilterChip(
                        label: s,
                        selected: _statusFilter == s,
                        onTap: () => setState(() => _statusFilter = s),
                      ))
                  .toList(),
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
                    child: Text('Error: ${snap.error}',
                        style: const TextStyle(color: AppColors.danger)),
                  );
                }

                final docs = (snap.data?.docs ?? []).where((d) {
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
                        Text('No IPO requests found.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                }

                return AdminPanel(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _IpoRequestRow(
                      doc:      docs[i],
                      appScope: appScope,
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

// ── Single row ────────────────────────────────────────────────────────────────

class _IpoRequestRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppScope appScope;

  const _IpoRequestRow({required this.doc, required this.appScope});

  @override
  Widget build(BuildContext context) {
    final req    = IpoRequest.fromFirestore(doc.id, doc.data());
    final fmt    = DateFormat('dd MMM HH:mm');
    final isPending = req.status == IpoRequestStatus.pending;

    Color statusColor;
    String statusLabel;
    switch (req.status) {
      case IpoRequestStatus.accepted:
        statusColor  = AppColors.success;
        statusLabel  = 'ACCEPTED';
        break;
      case IpoRequestStatus.rejected:
        statusColor  = AppColors.danger;
        statusLabel  = 'REJECTED';
        break;
      default:
        statusColor  = AppColors.warning;
        statusLabel  = 'PENDING';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Time
              SizedBox(
                width: 100,
                child: Text(fmt.format(req.appliedAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ),
              // Company
              Expanded(
                flex: 3,
                child: Text(req.ipoName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              // User
              Expanded(
                flex: 2,
                child: Text(
                  req.userName.isNotEmpty ? req.userName : req.userId,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Status / Actions
              if (isPending) ...[
                _actionBtn(context, 'Accept', AppColors.success,
                    () => _showAcceptDialog(context, req)),
                const SizedBox(width: 6),
                _actionBtn(context, 'Reject', AppColors.danger,
                    () => _showRejectDialog(context, req)),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip('Lots: ${req.lots}'),
              const SizedBox(width: 8),
              _chip('Lot Value: ₹${req.lotValue.toStringAsFixed(0)}'),
              const SizedBox(width: 8),
              _chip('Margin: ₹${req.marginBlocked.toStringAsFixed(2)} (${req.marginPercent}%)'),
              if (req.profitAmount != null) ...[
                const SizedBox(width: 8),
                _chip('Profit: ₹${req.profitAmount!.toStringAsFixed(2)}',
                    color: AppColors.success),
              ],
              if (req.lossAmount != null && req.lossAmount! > 0) ...[
                const SizedBox(width: 8),
                _chip('Loss: ₹${req.lossAmount!.toStringAsFixed(2)}',
                    color: AppColors.danger),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        (color ?? AppColors.textSecondary).withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color:    color ?? AppColors.textSecondary,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _actionBtn(
    BuildContext context,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.1),
          border:       Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                color:      color,
                fontWeight: FontWeight.w700,
                fontSize:   11)),
      ),
    );
  }

  // ── Accept dialog ───────────────────────────────────────────────────────────

  void _showAcceptDialog(BuildContext context, IpoRequest req) {
    final profitCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SettlementDialog(
        title:    'Accept IPO — ${req.ipoName}',
        subtitle: 'Blocked margin: ₹${req.marginBlocked.toStringAsFixed(2)} will be credited back.',
        fieldLabel: 'Profit Amount (₹)',
        fieldHint:  'Enter profit to credit',
        fieldIcon:  LucideIcons.trendingUp,
        fieldColor: AppColors.success,
        controller: profitCtrl,
        confirmLabel: 'Accept & Credit',
        confirmColor: AppColors.success,
        infoLines: [
          'Margin ₹${req.marginBlocked.toStringAsFixed(2)} + Profit → credited to wallet',
          'Status → ACCEPTED, Ledger entry: IPO_PROFIT',
        ],
        onConfirm: () async {
          final profit = double.tryParse(profitCtrl.text.trim()) ?? 0;
          await _processAccept(context, req, profit);
        },
      ),
    );
  }

  // ── Reject dialog ───────────────────────────────────────────────────────────

  void _showRejectDialog(BuildContext context, IpoRequest req) {
    final lossCtrl = TextEditingController(text: '0');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SettlementDialog(
        title:    'Reject IPO — ${req.ipoName}',
        subtitle: 'Blocked margin: ₹${req.marginBlocked.toStringAsFixed(2)}',
        fieldLabel: 'Loss Amount (₹)',
        fieldHint:  'Amount to deduct (0 = full refund)',
        fieldIcon:  LucideIcons.trendingDown,
        fieldColor: AppColors.danger,
        controller: lossCtrl,
        confirmLabel: 'Reject & Settle',
        confirmColor: AppColors.danger,
        infoLines: [
          'Return = Blocked Margin − Loss Amount',
          'Max loss capped at blocked margin',
          'Status → REJECTED, Ledger entry: IPO_LOSS',
        ],
        onConfirm: () async {
          final loss = (double.tryParse(lossCtrl.text.trim()) ?? 0)
              .clamp(0, req.marginBlocked)
              .toDouble();
          await _processReject(context, req, loss);
        },
      ),
    );
  }

  // ── Accept transaction ──────────────────────────────────────────────────────

  Future<void> _processAccept(
    BuildContext context,
    IpoRequest req,
    double profitAmount,
  ) async {
    final db      = appScope.firestoreService.raw;
    final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';

    try {
      await db.runTransaction((tx) async {
        final orderRef = db.collection('ipo_orders').doc(req.id);
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) throw Exception('IPO request not found.');

        final currentStatus = ((orderSnap.data()!['status'] as String?) ?? '').toUpperCase();
        if (currentStatus != 'PENDING') throw Exception('Already settled (status: $currentStatus).');

        final userRef  = db.collection('users').doc(req.userId);
        final userSnap = await tx.get(userRef);
        if (!userSnap.exists) throw Exception('User not found.');

        final userData      = userSnap.data()!;
        final balanceBefore = ((userData['balance'] as num?) ?? 0).toDouble();
        final creditAmount  = req.marginBlocked + profitAmount;
        final balanceAfter  = balanceBefore + creditAmount;

        // Update wallet
        tx.update(userRef, {
          'balance':           balanceAfter,
          'available_balance': balanceAfter,
          'updatedAt':         Timestamp.now(),
        });

        // Update IPO order
        tx.update(orderRef, {
          'status':       'APPROVED',
          'profitAmount': profitAmount,
          'creditAmount': creditAmount,
          'approvedBy':   adminId,
          'approvedAt':   Timestamp.now(),
          'updatedAt':    Timestamp.now(),
        });

        // Ledger entry: margin release
        WalletLedgerService.writeLedgerEntry(tx, db,
          userId:        req.userId,
          type:          'MARGIN_RELEASED',
          credit:        req.marginBlocked,
          balanceBefore: balanceBefore,
          balanceAfter:  balanceBefore + req.marginBlocked,
          referenceId:   req.id,
          referenceType: 'IPO_ORDER',
          remarks:       'Margin released — ${req.ipoName} IPO accepted',
          createdBy:     adminId,
        );

        // Ledger entry: profit credit
        if (profitAmount > 0) {
          WalletLedgerService.writeLedgerEntry(tx, db,
            userId:        req.userId,
            type:          'IPO_PROFIT',
            credit:        profitAmount,
            balanceBefore: balanceBefore + req.marginBlocked,
            balanceAfter:  balanceAfter,
            referenceId:   req.id,
            referenceType: 'IPO_ORDER',
            remarks:       '${req.ipoName} IPO profit',
            createdBy:     adminId,
          );
        }

        // Audit log
        WalletLedgerService.writeAuditLog(tx, db,
          action:        'IPO_ACCEPT',
          userId:        req.userId,
          adminId:       adminId,
          balanceBefore: balanceBefore,
          balanceAfter:  balanceAfter,
          amount:        creditAmount,
          referenceId:   req.id,
          referenceType: 'IPO_ORDER',
          remarks:       '${req.ipoName} — margin ${req.marginBlocked.toStringAsFixed(2)} + profit ${profitAmount.toStringAsFixed(2)}',
        );
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('IPO accepted. ₹${(req.marginBlocked + profitAmount).toStringAsFixed(2)} credited.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ── Reject transaction ──────────────────────────────────────────────────────

  Future<void> _processReject(
    BuildContext context,
    IpoRequest req,
    double lossAmount,
  ) async {
    final db      = appScope.firestoreService.raw;
    final adminId = appScope.notifier?.user?.uid ?? 'SYSTEM';

    try {
      await db.runTransaction((tx) async {
        final orderRef  = db.collection('ipo_orders').doc(req.id);
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) throw Exception('IPO request not found.');

        final currentStatus = ((orderSnap.data()!['status'] as String?) ?? '').toUpperCase();
        if (currentStatus != 'PENDING') throw Exception('Already settled (status: $currentStatus).');

        final userRef   = db.collection('users').doc(req.userId);
        final userSnap  = await tx.get(userRef);
        if (!userSnap.exists) throw Exception('User not found.');

        final userData      = userSnap.data()!;
        final balanceBefore = ((userData['balance'] as num?) ?? 0).toDouble();
        final returnAmount  = req.marginBlocked - lossAmount;
        final balanceAfter  = balanceBefore + returnAmount;

        // Update wallet
        tx.update(userRef, {
          'balance':           balanceAfter,
          'available_balance': balanceAfter,
          'updatedAt':         Timestamp.now(),
        });

        // Update IPO order
        tx.update(orderRef, {
          'status':       'REJECTED',
          'lossAmount':   lossAmount,
          'cutAmount':    lossAmount,
          'refundAmount': returnAmount,
          'rejectedBy':   adminId,
          'rejectedAt':   Timestamp.now(),
          'updatedAt':    Timestamp.now(),
        });

        // Ledger entry: margin return (credit)
        if (returnAmount > 0) {
          WalletLedgerService.writeLedgerEntry(tx, db,
            userId:        req.userId,
            type:          'MARGIN_RELEASED',
            credit:        returnAmount,
            balanceBefore: balanceBefore,
            balanceAfter:  balanceBefore + returnAmount,
            referenceId:   req.id,
            referenceType: 'IPO_ORDER',
            remarks:       'Partial margin returned — ${req.ipoName} IPO rejected',
            createdBy:     adminId,
          );
        }

        // Ledger entry: loss deduction
        if (lossAmount > 0) {
          WalletLedgerService.writeLedgerEntry(tx, db,
            userId:        req.userId,
            type:          'IPO_LOSS',
            debit:         lossAmount,
            balanceBefore: balanceBefore + req.marginBlocked,
            balanceAfter:  balanceAfter,
            referenceId:   req.id,
            referenceType: 'IPO_ORDER',
            remarks:       '${req.ipoName} IPO loss',
            createdBy:     adminId,
          );
        }

        // Audit log
        WalletLedgerService.writeAuditLog(tx, db,
          action:        'IPO_REJECT',
          userId:        req.userId,
          adminId:       adminId,
          balanceBefore: balanceBefore,
          balanceAfter:  balanceAfter,
          amount:        lossAmount,
          referenceId:   req.id,
          referenceType: 'IPO_ORDER',
          remarks:       '${req.ipoName} — loss ${lossAmount.toStringAsFixed(2)}, returned ${returnAmount.toStringAsFixed(2)}',
        );
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('IPO rejected. ₹${(req.marginBlocked - lossAmount).toStringAsFixed(2)} returned.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

// ── Reusable settlement dialog ────────────────────────────────────────────────

class _SettlementDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String fieldLabel;
  final String fieldHint;
  final IconData fieldIcon;
  final Color fieldColor;
  final TextEditingController controller;
  final String confirmLabel;
  final Color confirmColor;
  final List<String> infoLines;
  final Future<void> Function() onConfirm;

  const _SettlementDialog({
    required this.title,
    required this.subtitle,
    required this.fieldLabel,
    required this.fieldHint,
    required this.fieldIcon,
    required this.fieldColor,
    required this.controller,
    required this.confirmLabel,
    required this.confirmColor,
    required this.infoLines,
    required this.onConfirm,
  });

  @override
  State<_SettlementDialog> createState() => _SettlementDialogState();
}

class _SettlementDialogState extends State<_SettlementDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:        widget.fieldColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.fieldIcon, size: 18, color: widget.fieldColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(widget.subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText:   widget.fieldLabel,
              hintText:    widget.fieldHint,
              prefixText:  '₹ ',
              border:      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.fieldColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:        AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.infoLines
                  .map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                            Expanded(
                              child: Text(l,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
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
          style: ElevatedButton.styleFrom(backgroundColor: widget.confirmColor),
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
                        SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppColors.danger),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.confirmLabel,
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
