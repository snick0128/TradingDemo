import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app_scope.dart';
import '../../theme.dart';
import '../../state/security_scope.dart';
import '../../utils/responsive.dart';
import '../auth/admin_login_screen.dart';
import 'admin_stats_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_users_screen.dart';
import 'stock_control_screen.dart';
import 'risk_control_screen.dart';
import 'force_close_positions_screen.dart';
import 'admin_analytics_screen.dart';
import 'broadcast_notifications_screen.dart';
import 'audit_log_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    (LucideIcons.layoutDashboard, 'Dashboard'),
    (LucideIcons.users, 'Users'),
    (LucideIcons.activity, 'Orders'),
    (LucideIcons.toggleRight, 'Stocks'),
    (LucideIcons.shieldAlert, 'Risk'),
    (LucideIcons.xCircle, 'Force Close'),
    (LucideIcons.barChart2, 'Analytics'),
    (LucideIcons.bellRing, 'Broadcast'),
    (LucideIcons.shield, 'Audit Log'),
  ];

  static const _subtitle = [
    'Live platform pulse and controls',
    'Manage user lifecycle and access',
    'Monitor order flow',
    'Instrument tradability controls',
    'Risk limits and trading halt',
    'Force-close open positions',
    'Growth and performance trends',
    'Announcements to all users',
    'Immutable operational trail',
  ];

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final firebaseIsAdmin = appScope?.notifier?.isAdmin ?? false;
    final hasAdminAccess = (security.currentUser?.isAdmin ?? false) || firebaseIsAdmin;
    final layout = layoutForWidth(MediaQuery.of(context).size.width);
    final isDesktop = layout == AppLayoutBreakpoint.desktop;

    // Guard: non-admin users see unauthorized screen
    if (!hasAdminAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Console'),
          leading: const BackButton(),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shieldOff, size: 64, color: AppColors.danger),
              SizedBox(height: 16),
              Text(
                'Unauthorized',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You do not have admin access.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final screens = [
      const AdminStatsScreen(),
      const AdminUsersScreen(),
      const AdminOrdersScreen(),
      const StockControlScreen(),
      const RiskControlScreen(),
      const ForceClosePositionsScreen(),
      const AdminAnalyticsScreen(),
      const BroadcastNotificationsScreen(),
      const AuditLogScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                LucideIcons.shield,
                size: 16,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Admin Console'),
                Text(
                  _subtitle[_selectedIndex],
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final security = SecurityScope.of(context);
              final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
              if (appScope != null) {
                await appScope.authService.logout();
                if (!mounted) return;
                appScope.notifier!.setUser(null);
              }
              security.killAllSessions();
              if (nav.canPop()) {
                nav.pop();
              } else {
                nav.pushReplacement(
                  MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                );
              }
            },
            icon: const Icon(LucideIcons.logOut),
            tooltip: 'Exit Admin Mode',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop) ...[
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              labelType: NavigationRailLabelType.all,
              minWidth: 80,
              backgroundColor: AppColors.surface,
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.textSecondary,
              ),
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.$1),
                      label: Text(d.$2, style: const TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
          ],
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: screens),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.primary.withValues(alpha: 0.12),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: _destinations
                  .map(
                    (d) => NavigationDestination(icon: Icon(d.$1), label: d.$2),
                  )
                  .toList(),
            )
          : null,
    );
  }
}
