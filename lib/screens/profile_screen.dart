import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../state/security_scope.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = 'John Doe';
  String _email = 'johndoe@example.com';
  String _phone = '+91 98765 43210';

  bool _emailVerified = true;
  bool _phoneVerified = true;
  bool _panVerified = false;

  bool _biometric = true;
  bool _tradeAlerts = true;
  bool _priceAlerts = true;

  DateTime _lastLogin = DateTime.now().subtract(const Duration(hours: 2, minutes: 18));

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final security = SecurityScope.of(context);
    final completion = _profileCompletion;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        actions: [
          IconButton(
            onPressed: _openEditProfile,
            icon: const Icon(LucideIcons.userCog2),
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeaderCard(context),
            const SizedBox(height: 14),
            _buildStatsRow(store),
            const SizedBox(height: 14),
            _buildVerificationCard(context, completion),
            const SizedBox(height: 14),
            _buildPreferencesCard(context),
            const SizedBox(height: 14),
            _buildActionsCard(context),
            const SizedBox(height: 14),
            _buildSessionCard(context),
            const SizedBox(height: 14),
            _buildSecurityQuickActions(context, security),
            const SizedBox(height: 14),
            _buildLogoutButton(context),
            const SizedBox(height: 30),
            Text('v1.0.0 (Client Demo Build)', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  int get _profileCompletion {
    var completed = 0;
    if (_name.trim().isNotEmpty) completed++;
    if (_emailVerified) completed++;
    if (_phoneVerified) completed++;
    if (_panVerified) completed++;
    return ((completed / 4) * 100).round();
  }

  Widget _buildHeaderCard(BuildContext context) {
    final initials = _name
        .split(' ')
        .where((item) => item.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();

    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'U' : initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(_email, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_phone, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            onPressed: _openEditProfile,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(store) {
    final stats = [
      ('Balance', '₹${store.balance.toStringAsFixed(0)}'),
      ('Orders', '${store.orders.length}'),
      ('Holdings', '${store.portfolio.length}'),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Expanded(
            child: CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stats[i].$1, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 5),
                  Text(stats[i].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (i < stats.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildVerificationCard(BuildContext context, int completion) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Account Verification', style: Theme.of(context).textTheme.titleMedium),
              Text('$completion%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: completion / 100,
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              color: completion == 100 ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(height: 12),
          _statusRow('Email', _emailVerified, onTap: () => setState(() => _emailVerified = true)),
          _statusRow('Phone', _phoneVerified, onTap: () => setState(() => _phoneVerified = true)),
          _statusRow('PAN / KYC', _panVerified, onTap: _openKycSheet),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Biometric Login'),
            subtitle: const Text('Use Face ID / Fingerprint for app unlock'),
            value: _biometric,
            onChanged: (value) => setState(() => _biometric = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Trade Alerts'),
            subtitle: const Text('Order status and rejection notifications'),
            value: _tradeAlerts,
            onChanged: (value) => setState(() => _tradeAlerts = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Price Alerts'),
            subtitle: const Text('Price movement and trigger notifications'),
            value: _priceAlerts,
            onChanged: (value) => setState(() => _priceAlerts = value),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _actionTile(
            icon: LucideIcons.shieldCheck,
            title: 'Security Center',
            subtitle: 'Password, trusted devices, sessions',
            onTap: () => _openChangePinSheet(context),
          ),
          const Divider(height: 1, indent: 56),
          _actionTile(
            icon: LucideIcons.fileCheck,
            title: 'Tax & Statements',
            subtitle: 'P&L report, ledger, contract notes',
            onTap: () => _showMessage('Statement download will be available in next build.'),
          ),
          const Divider(height: 1, indent: 56),
          _actionTile(
            icon: Icons.support_agent,
            title: 'Help & Support',
            subtitle: 'Raise ticket or live chat',
            onTap: () => _showMessage('Support center opened.'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context) {
    return CustomCard(
      child: Row(
        children: [
          const Icon(LucideIcons.clock3, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Last Login', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(DateFormat('dd MMM yyyy, hh:mm a').format(_lastLogin), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _lastLogin = DateTime.now());
              _showMessage('Session refreshed.');
            },
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityQuickActions(BuildContext context, security) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openChangePinSheet(context),
            icon: const Icon(LucideIcons.keyRound, size: 16),
            label: const Text('Change PIN'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              security.lockNow();
              _showMessage('App locked. Enter PIN to continue.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            icon: const Icon(LucideIcons.lock, size: 16),
            label: const Text('Lock Now'),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _confirmLogout,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.danger.withValues(alpha: 0.15),
          foregroundColor: AppColors.danger,
          elevation: 0,
        ),
        icon: const Icon(LucideIcons.logOut),
        label: const Text('Logout'),
      ),
    );
  }

  Widget _statusRow(String label, bool verified, {required VoidCallback onTap}) {
    return InkWell(
      onTap: verified ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              verified ? LucideIcons.badgeCheck : LucideIcons.circleDashed,
              size: 16,
              color: verified ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(
              verified ? 'Verified' : 'Complete',
              style: TextStyle(
                color: verified ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
      onTap: onTap,
    );
  }

  void _openEditProfile() {
    final nameController = TextEditingController(text: _name);
    final emailController = TextEditingController(text: _email);
    final phoneController = TextEditingController(text: _phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Edit Profile', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 10),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _name = nameController.text.trim().isEmpty ? _name : nameController.text.trim();
                    _email = emailController.text.trim().isEmpty ? _email : emailController.text.trim();
                    _phone = phoneController.text.trim().isEmpty ? _phone : phoneController.text.trim();
                  });
                  Navigator.pop(context);
                  _showMessage('Profile updated successfully.');
                },
                child: const Text('Save Changes'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openKycSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Complete KYC', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('Upload PAN and identity proof to unlock all trading features.'),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  setState(() => _panVerified = true);
                  Navigator.pop(context);
                  _showMessage('KYC marked as completed.');
                },
                child: const Text('Submit KYC'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openChangePinSheet(BuildContext context) {
    final security = SecurityScope.of(context);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String error = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Change App PIN', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currentController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'Current PIN', counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'New PIN', counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'Confirm New PIN', counterText: ''),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error, style: const TextStyle(color: AppColors.danger)),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final current = currentController.text.trim();
                      final next = newController.text.trim();
                      final confirm = confirmController.text.trim();

                      if (next != confirm) {
                        setModalState(() => error = 'New PIN and confirm PIN do not match.');
                        return;
                      }

                      final changed = security.changePin(currentPin: current, newPin: next);
                      if (!changed) {
                        setModalState(() => error = 'Invalid PIN details. Use 4 digits.');
                        return;
                      }

                      Navigator.pop(context);
                      _showMessage('App PIN changed successfully.');
                    },
                    child: const Text('Update PIN'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('You will need to login again to continue trading.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showMessage('Logged out from this demo session.');
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
