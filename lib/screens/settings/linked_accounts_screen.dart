import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class _BankAccount {
  final String bankName;
  final String accountNumber;
  final String ifsc;
  final bool isPrimary;

  const _BankAccount({
    required this.bankName,
    required this.accountNumber,
    required this.ifsc,
    required this.isPrimary,
  });
}

const _accounts = <_BankAccount>[];

class LinkedAccountsScreen extends StatelessWidget {
  const LinkedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Linked Bank Accounts'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bank accounts are verified via NACH mandate. Contact support to add or remove accounts.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No linked bank accounts found.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ..._accounts.map((acc) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AccountCard(account: acc),
                  )),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Contact support to add a new bank account.')),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add Bank Account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final _BankAccount account;
  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.building2,
                color: AppColors.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(account.bankName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (account.isPrimary) ...[
                      const SizedBox(width: 8),
                      StatusBadge(label: 'Primary', color: AppColors.success),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(account.accountNumber,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                Text('IFSC: ${account.ifsc}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Icon(LucideIcons.checkCircle,
              color: AppColors.success, size: 20),
        ],
      ),
    );
  }
}
