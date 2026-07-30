import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../theme.dart';
import '../widgets/wallet_fund_widgets.dart';

/// Full withdrawal history — card-based, newest first.
class WithdrawalHistoryScreen extends StatelessWidget {
  const WithdrawalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AppScope.of(context).notifier?.user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawal History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('withdrawal_requests')
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.receipt, size: 44, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No withdrawals yet', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final req = WithdrawalRequest.fromFirestore(docs[i].id, docs[i].data());
              return WalletHistoryCard(
                amount: req.amount,
                status: req.status,
                date: req.createdAt,
                subtitle: req.upiId.isNotEmpty ? 'UPI: ${req.upiId}' : req.bankAccount,
                rejectionReason: req.rejectionReason,
                isCredit: false,
              );
            },
          );
        },
      ),
    );
  }
}
