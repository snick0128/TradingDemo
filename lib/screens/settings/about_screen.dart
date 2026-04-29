import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // App logo & version
            CustomCard(
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ),
                    ),
                    child: const Icon(LucideIcons.candlestickChart,
                        size: 36, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text('Trade Kosh',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('Version 1.0.0 (Build 1)',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  const Text('Client Demo Build',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _infoTile('Platform', 'Flutter Web'),
                  const Divider(height: 1),
                  _infoTile('Framework', 'Flutter 3.x'),
                  const Divider(height: 1),
                  _infoTile('Charts', 'Syncfusion Flutter Charts'),
                  const Divider(height: 1),
                  _infoTile('State Management', 'InheritedNotifier'),
                  const Divider(height: 1),
                  _infoTile('License', 'Proprietary'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Credits
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Credits',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const _CreditRow(
                      name: 'Flutter', role: 'UI Framework by Google'),
                  const _CreditRow(
                      name: 'Syncfusion',
                      role: 'Charts & Data Visualization'),
                  const _CreditRow(
                      name: 'Google Fonts', role: 'Inter & JetBrains Mono'),
                  const _CreditRow(
                      name: 'Lucide Icons', role: 'Icon Library'),
                  const _CreditRow(
                      name: 'flutter_animate', role: 'Animation Library'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Legal
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _legalTile(context, 'Privacy Policy'),
                  const Divider(height: 1),
                  _legalTile(context, 'Terms of Service'),
                  const Divider(height: 1),
                  _legalTile(context, 'Risk Disclosure'),
                  const Divider(height: 1),
                  _legalTile(context, 'Open Source Licenses'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '© 2025 Trade Kosh. All rights reserved.\nThis is a demo application for evaluation purposes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _legalTile(BuildContext context, String title) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary, size: 20),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title coming soon')),
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String name;
  final String role;

  const _CreditRow({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(LucideIcons.heart,
              size: 14, color: AppColors.danger),
          const SizedBox(width: 8),
          Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(role,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
