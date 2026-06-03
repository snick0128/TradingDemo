import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../theme.dart';

class IpoHistoryScreen extends StatelessWidget {
  final bool showAppBar;

  const IpoHistoryScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final appScope = AppScope.of(context);
    final uid      = appScope.notifier?.user?.uid;
    final db       = appScope.firestoreService.raw;

    if (uid == null) {
      return const Center(
        child: Text('Please log in to view IPO history.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('ipo_orders')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
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

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState();
        }

        final requests = docs.map((d) => IpoRequest.fromFirestore(d.id, d.data())).toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _IpoCard(req: requests[i]),
        );
      },
    );

    if (!showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('IPO Applications')),
      body: body,
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:        AppColors.primary.withOpacity(0.06),
              shape:        BoxShape.circle,
            ),
            child: const Icon(LucideIcons.fileText,
                size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('No IPO Applications',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Apply for IPOs from the IPO section.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── IPO Application Card ──────────────────────────────────────────────────────

class _IpoCard extends StatelessWidget {
  final IpoRequest req;

  const _IpoCard({required this.req});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (req.status) {
      case IpoRequestStatus.accepted:
        statusColor = AppColors.success;
        statusIcon  = LucideIcons.checkCircle;
        statusLabel = 'Accepted';
        break;
      case IpoRequestStatus.rejected:
        statusColor = AppColors.danger;
        statusIcon  = LucideIcons.xCircle;
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon  = LucideIcons.clock;
        statusLabel = 'Pending';
    }

    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        border:       Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color:  Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                // Company logo placeholder
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:        AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.building2,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(req.ipoName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize:   14,
                              color:      AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('Applied: ${fmt.format(req.appliedAt)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color:    AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusLabel,
                          style: TextStyle(
                              color:      statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize:   11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Details grid
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _detail('Lots Applied', '${req.lots}'),
                _detail('Lot Value', '₹${_fmt(req.lotValue)}'),
                _detail('Margin Blocked',
                    '₹${_fmt(req.marginBlocked)} (${req.marginPercent}%)'),
                _detail('Bid Price', '₹${_fmt(req.bidPrice)}'),
              ],
            ),
          ),

          // Settlement section (only for settled requests)
          if (req.status != IpoRequestStatus.pending) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (req.status == IpoRequestStatus.accepted) ...[
                    _detail('Margin Returned', '₹${_fmt(req.marginBlocked)}',
                        color: AppColors.success),
                    if (req.profitAmount != null && req.profitAmount! > 0)
                      _detail('Profit Credited', '₹${_fmt(req.profitAmount!)}',
                          color: AppColors.success),
                    _detail(
                      'Total Credited',
                      '₹${_fmt(req.marginBlocked + (req.profitAmount ?? 0))}',
                      color: AppColors.success,
                    ),
                  ],
                  if (req.status == IpoRequestStatus.rejected) ...[
                    if (req.lossAmount != null && req.lossAmount! > 0)
                      _detail('Loss Deducted', '₹${_fmt(req.lossAmount!)}',
                          color: AppColors.danger),
                    _detail(
                      'Amount Returned',
                      '₹${_fmt(req.returnAmount ?? (req.marginBlocked - (req.lossAmount ?? 0)))}',
                      color: AppColors.warning,
                    ),
                  ],
                  if (req.settledAt != null)
                    _detail('Settled', DateFormat('dd MMM yyyy').format(req.settledAt!)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color:      color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }
}
