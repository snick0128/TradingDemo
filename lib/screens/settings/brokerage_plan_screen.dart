import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class BrokeragePlanScreen extends StatelessWidget {
  const BrokeragePlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Brokerage Plan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current plan badge
            CustomCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.award,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current Plan',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        Text('Standard Plan',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text('Active since Jan 2024',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  StatusBadge(label: 'Active', color: AppColors.success),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text('Plan Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _planRow('Equity Delivery', 'Zero brokerage', AppColors.success),
                  const Divider(height: 1),
                  _planRow('Equity Intraday', '₹20 or 0.03% (whichever lower)', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('F&O', '₹20 per executed order', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('Currency', '₹20 per executed order', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('Commodity', '₹20 per executed order', AppColors.textPrimary),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text('Other Charges',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _planRow('STT (Equity Delivery)', '0.1% on buy & sell', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('STT (Intraday)', '0.025% on sell side', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('Exchange Transaction Charges', '0.00345% (NSE)', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('GST', '18% on brokerage + charges', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('SEBI Charges', '₹10 per crore', AppColors.textPrimary),
                  const Divider(height: 1),
                  _planRow('Stamp Duty', '0.015% on buy side', AppColors.textPrimary),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Plan upgrade coming soon!')),
              ),
              icon: const Icon(LucideIcons.arrowUpCircle, size: 18),
              label: const Text('Upgrade Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor)),
        ],
      ),
    );
  }
}
