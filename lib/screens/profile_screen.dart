import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../state/security_scope.dart';
import '../state/tab_notifier.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import '../models/trading_models.dart';
import 'ipo_screen.dart';
import 'settings_hub_screen.dart';
import 'settings/help_support_screen.dart';
import 'admin/admin_shell.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _biometric = true;
  bool _tradeAlerts = true;
  bool _priceAlerts = true;

  // Snapshotted store values
  User? _user;
  double _balance = 0;
  int _ordersCount = 0;
  int _portfolioCount = 0;

  bool _isActiveTab = false;
  TradingStore? _store;

  @override
  void initState() {
    super.initState();
    _isActiveTab = activeTabNotifier.value == 4;
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      store.addListener(_onStoreChanged);
      _syncFromStore(store);
    }
  }

  void _syncFromStore(TradingStore store) {
    _user = store.currentUser;
    _balance = store.balance;
    _ordersCount = store.orders.length;
    _portfolioCount = store.portfolio.length;
  }

  void _onStoreChanged() {
    if (_store == null) return;
    final store = _store!;
    // Profile-relevant data doesn't change on price ticks; only rebuild when
    // the actual values change to avoid spurious rebuilds every tick.
    final newUser = store.currentUser;
    final newBalance = store.balance;
    final newOrdersCount = store.orders.length;
    final newPortfolioCount = store.portfolio.length;
    if (newUser == _user && newBalance == _balance &&
        newOrdersCount == _ordersCount && newPortfolioCount == _portfolioCount) {
      return;
    }
    _user = newUser;
    _balance = newBalance;
    _ordersCount = newOrdersCount;
    _portfolioCount = newPortfolioCount;
    if (_isActiveTab) setState(() {});
  }

  void _onTabVisibilityChanged() {
    final active = activeTabNotifier.value == 4;
    if (active == _isActiveTab) return;
    _isActiveTab = active;
    if (active) setState(() {});
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabVisibilityChanged);
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user ?? TradingScope.read(context).currentUser;
    final security = SecurityScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
            ),
            icon: const Icon(LucideIcons.settings2),
            tooltip: 'Settings',
          ),
          IconButton(
            onPressed: () => _openEditProfile(user),
            icon: const Icon(LucideIcons.userCog2),
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, TradingBottomNavBar.bottomInset(context)),
        child: Column(
          children: [
            _buildHeaderCard(context, user),
            const SizedBox(height: 14),
            _buildStatsRow(),
            const SizedBox(height: 14),
            _buildPreferencesCard(context),
            const SizedBox(height: 14),
            _buildActionsCard(context),
            const SizedBox(height: 14),
            _buildSecurityQuickActions(context, security),
            const SizedBox(height: 14),
            _buildLogoutButton(context),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, User user) {
    final initials = user.name
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
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'U' : initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Client ID: ${user.clientId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Account: ${user.isAdmin ? 'Admin' : 'Standard'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openEditProfile(user),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = [
      ('Balance', '₹${_balance.toStringAsFixed(0)}'),
      ('Orders', '$_ordersCount'),
      ('Holdings', '$_portfolioCount'),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Expanded(
            child: CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[i].$1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    stats[i].$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (i < stats.length - 1) const SizedBox(width: 8),
        ],
      ],
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
    final user = _user ?? TradingScope.read(context).currentUser;

    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _actionTile(
            icon: LucideIcons.barChart2,
            title: 'IPO',
            subtitle: 'Upcoming, ongoing, and recently listed IPOs',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IPOScreen()),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _actionTile(
            icon: LucideIcons.headphones,
            title: 'Help & Support',
            subtitle: 'Raise ticket, FAQs, and contact options',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            ),
          ),
          if (user.isAdmin) ...[
            const Divider(height: 1, indent: 56),
            _actionTile(
              icon: LucideIcons.settings2,
              title: 'Admin Panel',
              subtitle: 'Backend management and monitoring',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AdminShell())),
            ),
          ],
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
          backgroundColor: AppColors.danger.withOpacity(0.15),
          foregroundColor: AppColors.danger,
          elevation: 0,
        ),
        icon: const Icon(LucideIcons.logOut),
        label: const Text('Logout'),
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
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  void _openEditProfile(User user) {
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final store = TradingScope.read(context);

    AppBottomSheet.show(
      context,
      title: 'Edit Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              final updated = user.copyWith(
                name: nameController.text.trim().isEmpty
                    ? user.name
                    : nameController.text.trim(),
                email: emailController.text.trim().isEmpty
                    ? user.email
                    : emailController.text.trim(),
              );
              store.updateUser(updated);
              Navigator.pop(context);
              AppToast.success(context, 'Profile updated successfully.');
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _openChangePinSheet(BuildContext context) {
    final security = SecurityScope.of(context);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    AppBottomSheet.show(
      context,
      title: 'Change App PIN',
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          String error = '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: currentController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'New PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Confirm New PIN',
                  counterText: '',
                ),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final current = currentController.text.trim();
                  final next = newController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (next != confirm) {
                    setModalState(
                      () => error = 'New PIN and confirm PIN do not match.',
                    );
                    return;
                  }
                  final changed = security.changePin(
                    currentPin: current,
                    newPin: next,
                  );
                  if (!changed) {
                    setModalState(
                      () => error = 'Invalid PIN details. Use 4 digits.',
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  AppToast.success(context, 'App PIN changed successfully.');
                },
                child: const Text('Update PIN'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmLogout() {
    AppDialog.destructive(
      context,
      title: 'Logout?',
      message: 'You will need to login again to continue trading.',
      confirmLabel: 'Logout',
      onConfirm: () async {
        try {
          final appScope = context
              .dependOnInheritedWidgetOfExactType<AppScope>();
          if (appScope != null) {
            await appScope.authService.logout();
            appScope.notifier?.setUser(null);
          }
          if (context.mounted) {
            SecurityScope.of(context).killAllSessions();
            context.go('/app/login');
          }
        } catch (_) {
          if (context.mounted) {
            SecurityScope.of(context).killAllSessions();
            context.go('/app/login');
          }
        }
      },
    );
  }

  void _showMessage(String message) {
    AppToast.info(context, message);
  }
}
