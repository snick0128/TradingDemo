import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../models/trading_models.dart';
import '../../theme.dart';
import '../../state/security_scope.dart';
import 'admin_stats_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_users_screen.dart';
import 'admin_analytics_screen.dart';
import 'leverage_control_screen.dart';
import 'market_settings_screen.dart';
import 'admin_ipo_orders_screen.dart';

// ── Breakpoint ────────────────────────────────────────────────────────────────
const _kWebBreakpoint = 768.0;

// ── Nav destinations ──────────────────────────────────────────────────────────
const _kDestinations = [
  (LucideIcons.layoutDashboard, 'Dashboard'),
  (LucideIcons.barChart2, 'Analytics'),
  (LucideIcons.users, 'Users'),
  (LucideIcons.activity, 'Orders'),
  (LucideIcons.zap, 'Leverage'),
  (LucideIcons.receipt, 'IPO'),
  (LucideIcons.clock, 'Market'),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  static const _screens = [
    AdminStatsScreen(),
    AdminAnalyticsScreen(),
    AdminUsersScreen(),
    AdminOrdersScreen(),
    LeverageControlScreen(),
    AdminIpoOrdersScreen(),
    MarketSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final isAdmin =
        (security.currentUser?.isAdmin ?? false) ||
        (appScope?.notifier?.isAdmin ?? false);
    final isWeb = MediaQuery.of(context).size.width >= _kWebBreakpoint;

    // ── Unauthorized guard ────────────────────────────────────────────────────
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Console'),
          leading: const BackButton(),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.shieldOff,
                size: 64,
                color: AppColors.danger,
              ),
              const SizedBox(height: 16),
              Text(
                'Unauthorized',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have admin access.',
                style: GoogleFonts.inter(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return isWeb
        ? _WebLayout(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
            screens: _screens,
            onLogout: () => _logout(context, appScope),
          )
        : _MobileLayout(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
            screens: _screens,
            onLogout: () => _logout(context, appScope),
          );
  }

  Future<void> _logout(BuildContext context, AppScope? appScope) async {
    if (appScope != null) {
      await appScope.authService.logout();
      if (mounted) appScope.notifier!.setUser(null);
    }
    if (context.mounted) context.go('/admin/login');
  }
}

// ── Web layout: icon-only sidebar + content ───────────────────────────────────

class _WebLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<Widget> screens;
  final VoidCallback onLogout;

  const _WebLayout({
    required this.selectedIndex,
    required this.onSelect,
    required this.screens,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      resizeToAvoidBottomInset: true,
      body: Row(
        children: [
          // ── Sidebar ────────────────────────────────────────────────────────
          Container(
            width: 72,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // App icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.shield,
                    size: 20,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(height: 24),
                // Nav icons
                ...List.generate(_kDestinations.length, (i) {
                  final selected = selectedIndex == i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Tooltip(
                      message: _kDestinations[i].$2,
                      preferBelow: false,
                      child: InkWell(
                        onTap: () => onSelect(i),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF1565C0)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _kDestinations[i].$1,
                            size: 20,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF757575),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                // Logout
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Tooltip(
                    message: 'Logout',
                    child: InkWell(
                      onTap: onLogout,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.logOut,
                          size: 20,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Content ────────────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(index: selectedIndex, children: screens),
          ),
        ],
      ),
    );
  }
}

// ── Mobile layout: bottom nav ─────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<Widget> screens;
  final VoidCallback onLogout;

  const _MobileLayout({
    required this.selectedIndex,
    required this.onSelect,
    required this.screens,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _kDestinations[selectedIndex].$2,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0D0D0D),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: Color(0xFF757575)),
            tooltip: 'Logout',
            onPressed: onLogout,
          ),
        ],
        shape: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: selectedIndex, children: screens),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 58,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: List.generate(_kDestinations.length, (i) {
              final selected = selectedIndex == i;
              final color = selected
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF9E9E9E);
              // Compact icon+label for 7-item mobile nav
              const iconSize = 19.0;
              const labelSize = 9.0;
              return Expanded(
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_kDestinations[i].$1, size: iconSize, color: color),
                      const SizedBox(height: 2),
                      Text(
                        _kDestinations[i].$2,
                        style: GoogleFonts.inter(
                          fontSize: labelSize,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
