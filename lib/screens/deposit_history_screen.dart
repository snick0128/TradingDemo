import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../theme.dart';
import '../widgets/wallet_fund_widgets.dart';

const _kMethodLabels = {
  'gpay': 'Google Pay',
  'phonepe': 'PhonePe',
  'paytm': 'Paytm',
  'upi': 'UPI',
  'bank_transfer': 'Bank Transfer',
};

/// Full deposit history — card-based, newest first.
class DepositHistoryScreen extends StatelessWidget {
  const DepositHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AppScope.of(context).notifier?.user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Deposit History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('deposit_requests')
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
                  Text('No deposits yet', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final req = DepositRequest.fromFirestore(docs[i].id, docs[i].data());
              return WalletHistoryCard(
                amount: req.amount,
                status: req.status,
                date: req.createdAt,
                subtitle: _kMethodLabels[req.paymentMethod] ?? req.paymentMethod,
                rejectionReason: req.rejectionReason,
                isCredit: true,
              );
            },
          );
        },
      ),
    );
  }
}
