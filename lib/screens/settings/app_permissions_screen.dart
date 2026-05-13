import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class _Permission {
  final String name;
  final String description;
  final IconData icon;
  final bool isGranted;

  const _Permission({
    required this.name,
    required this.description,
    required this.icon,
    this.isGranted = true,
  });
}

const _permissions = [
  _Permission(
    name: 'Notifications',
    description: 'Receive price alerts, order updates, and news',
    icon: LucideIcons.bell,
    isGranted: true,
  ),
  _Permission(
    name: 'Biometric Authentication',
    description: 'Use Face ID or fingerprint to unlock the app',
    icon: LucideIcons.fingerprint,
    isGranted: true,
  ),
  _Permission(
    name: 'Camera',
    description: 'Required for KYC document upload',
    icon: LucideIcons.camera,
    isGranted: false,
  ),
  _Permission(
    name: 'Storage',
    description: 'Save contract notes and statements locally',
    icon: LucideIcons.hardDrive,
    isGranted: true,
  ),
  _Permission(
    name: 'Network Access',
    description: 'Required for live market data and trading',
    icon: LucideIcons.wifi,
    isGranted: true,
  ),
];

class AppPermissionsScreen extends StatelessWidget {
  const AppPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('App Permissions'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(
                    LucideIcons.shieldAlert,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manage permissions from your device settings. Some features may not work without required permissions.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: _permissions.asMap().entries.map((e) {
                  final perm = e.value;
                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                (perm.isGranted
                                        ? AppColors.success
                                        : AppColors.danger)
                                    .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            perm.icon,
                            size: 18,
                            color: perm.isGranted
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                        title: Text(
                          perm.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          perm.description,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: StatusBadge(
                          label: perm.isGranted ? 'Granted' : 'Denied',
                          color: perm.isGranted
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                      if (e.key < _permissions.length - 1)
                        const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
