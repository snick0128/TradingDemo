import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import '../widgets/shared_widgets.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/security_settings_screen.dart';
import 'settings/brokerage_plan_screen.dart';
import 'settings/help_support_screen.dart';
import 'settings/about_screen.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('App Preference'),
          _SettingsTile(
            icon: LucideIcons.palette,
            title: 'Appearance',
            subtitle: 'Font size and display preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppearanceSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: LucideIcons.shieldCheck,
            title: 'Security',
            subtitle: 'PIN, biometrics, session log',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Account'),
          _SettingsTile(
            icon: LucideIcons.creditCard,
            title: 'Brokerage Plan',
            subtitle: 'View or change your trading plan',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BrokeragePlanScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: LucideIcons.link2,
            title: 'Linked Accounts',
            subtitle: 'Bank accounts, demat, external apps',
            onTap: () => _showComingSoon(context),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Support & Legal'),
          _SettingsTile(
            icon: LucideIcons.headphones,
            title: 'Help & Support',
            subtitle: 'Contact us, FAQs, tickets',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: LucideIcons.info,
            title: 'About',
            subtitle: 'Version, terms, privacy policy',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Trade Kosh v1.0.0',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This feature is coming soon!')),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(
          Icons.chevron_right,
          size: 18,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}
