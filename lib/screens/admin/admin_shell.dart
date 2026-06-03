import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../state/security_scope.dart';
import '../../theme.dart';
import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'live_monitor_screen.dart';
import 'admin_users_screen.dart';
import 'risk_dashboard_screen.dart';
import 'admin_analytics_screen.dart';
import 'leverage_control_screen.dart';
import 'market_settings_screen.dart';
import 'admin_ipo_orders_screen.dart';
import 'platform_settings_screen.dart';
import 'admin_change_password_screen.dart';
import 'audit_log_screen.dart';
import 'broadcast_notifications_screen.dart';
import 'pending_withdrawals_screen.dart';
import 'stock_control_screen.dart';
import 'force_close_positions_screen.dart';
import 'risk_control_screen.dart';

// ── Breakpoints ────────────────────────────────────────────────────────────────
const _kSidebarBreakpoint = 768.0;
const _kSidebarExpandedWidth = 220.0;
const _kSidebarCollapsedWidth = 60.0;

// ── Primary destinations (always in sidebar + mobile bottom nav) ───────────────
const _kPrimary = [
  (LucideIcons.layoutDashboard, 'Dashboard'),
  (LucideIcons.clipboardList,   'Orders'),
  (LucideIcons.radio,           'Live'),
  (LucideIcons.users,           'Users'),
  (LucideIcons.shieldAlert,     'Risk'),
  (LucideIcons.barChart2,       'Analytics'),
];

// ── Secondary destinations (sidebar + "More" sheet on mobile) ─────────────────
typedef _Dest = (IconData, String);
const _kSecondary = <_Dest>[
  (LucideIcons.zap,              'Leverage'),
  (LucideIcons.clock,            'Market'),
  (LucideIcons.settings,         'Platform'),
  (LucideIcons.receipt,          'IPO Orders'),
  (LucideIcons.fileSearch,       'Audit Log'),
  (LucideIcons.megaphone,        'Broadcast'),
  (LucideIcons.barChart,         'Stock Control'),
  (LucideIcons.wallet,           'Withdrawals'),
  (LucideIcons.xCircle,          'Force Close'),
  (LucideIcons.sliders,          'Risk Limits'),
  (LucideIcons.keyRound,         'Password'),
];

// ── All screens ────────────────────────────────────────────────────────────────
// Indices 0-5 = primary; 6-16 = secondary
const _kAllScreens = [
  AdminDashboardScreen(),
  AdminOrdersScreen(),
  LiveMonitorScreen(),
  AdminUsersScreen(),
  RiskDashboardScreen(),
  AdminAnalyticsScreen(),
  LeverageControlScreen(),
  MarketSettingsScreen(),
  PlatformSettingsScreen(),
  AdminIpoOrdersScreen(),
  AuditLogScreen(),
  BroadcastNotificationsScreen(),
  StockControlScreen(),
  PendingWithdrawalsScreen(),
  ForceClosePositionsScreen(),
  RiskControlScreen(),
  AdminChangePasswordScreen(),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final isAdmin =
        (security.currentUser?.isAdmin ?? false) ||
        (appScope?.notifier?.isAdmin ?? false);
    final isDesktop =
        MediaQuery.of(context).size.width >= _kSidebarBreakpoint;

    if (!isAdmin) return _UnauthorizedScreen();

    return isDesktop
        ? _DesktopLayout(
            selectedIndex: _selectedIndex,
            expanded: _sidebarExpanded,
            onSelect: (i) => setState(() => _selectedIndex = i),
            onToggleSidebar: () =>
                setState(() => _sidebarExpanded = !_sidebarExpanded),
            onLogout: () => _logout(context, appScope),
          )
        : _MobileLayout(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
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

// ── Unauthorized ───────────────────────────────────────────────────────────────

class _UnauthorizedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Console')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.shieldOff, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            Text('Unauthorized',
                style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger)),
            const SizedBox(height: 8),
            Text('You do not have admin access.',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Desktop layout: collapsible sidebar ───────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleSidebar;
  final VoidCallback onLogout;

  const _DesktopLayout({
    required this.selectedIndex,
    required this.expanded,
    required this.onSelect,
    required this.onToggleSidebar,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: selectedIndex,
            expanded: expanded,
            onSelect: onSelect,
            onToggle: onToggleSidebar,
            onLogout: onLogout,
          ),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: _kAllScreens,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.selectedIndex,
    required this.expanded,
    required this.onSelect,
    required this.onToggle,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final w =
        expanded ? _kSidebarExpandedWidth : _kSidebarCollapsedWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: w,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo ────────────────────────────────────────────────────
          _SidebarHeader(expanded: expanded, onToggle: onToggle),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // ── Primary nav ─────────────────────────────────────────────
          ...List.generate(_kPrimary.length, (i) {
            return _SidebarItem(
              icon: _kPrimary[i].$1,
              label: _kPrimary[i].$2,
              selected: selectedIndex == i,
              expanded: expanded,
              onTap: () => onSelect(i),
            );
          }),

          const SizedBox(height: 8),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Text('SETTINGS',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.2)),
            )
          else
            Divider(
                height: 1,
                indent: 10,
                endIndent: 10,
                color: AppColors.border),
          const SizedBox(height: 4),

          // ── Secondary nav ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(_kSecondary.length, (i) {
                  final idx = _kPrimary.length + i;
                  return _SidebarItem(
                    icon: _kSecondary[i].$1,
                    label: _kSecondary[i].$2,
                    selected: selectedIndex == idx,
                    expanded: expanded,
                    onTap: () => onSelect(idx),
                    secondary: true,
                  );
                }),
              ),
            ),
          ),

          const Divider(height: 1),
          // ── Logout ──────────────────────────────────────────────────
          _SidebarItem(
            icon: LucideIcons.logOut,
            label: 'Logout',
            selected: false,
            expanded: expanded,
            onTap: onLogout,
            danger: true,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _SidebarHeader({required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF2962FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.shield,
                size: 16, color: Colors.white),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Trade Kosh',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          IconButton(
            icon: Icon(
              expanded
                  ? LucideIcons.panelLeftClose
                  : LucideIcons.panelLeftOpen,
              size: 16,
              color: AppColors.textSecondary,
            ),
            onPressed: onToggle,
            tooltip: expanded ? 'Collapse' : 'Expand',
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final bool secondary;
  final bool danger;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
    this.secondary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        danger ? AppColors.danger : AppColors.primary;
    final iconColor = selected
        ? activeColor
        : danger
            ? AppColors.danger.withOpacity(0.6)
            : AppColors.textSecondary;
    final textColor = selected
        ? activeColor
        : danger
            ? AppColors.danger.withOpacity(0.7)
            : secondary
                ? AppColors.textSecondary
                : AppColors.textPrimary;

    final item = Tooltip(
      message: expanded ? '' : label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: EdgeInsets.symmetric(
              horizontal: expanded ? 10 : 0, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (!expanded) const Spacer(),
              Icon(icon, size: secondary ? 16 : 18, color: iconColor),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: secondary ? 12 : 13,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (!expanded) const Spacer(),
              if (expanded && selected)
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return item;
  }
}

// ── Mobile layout: bottom nav + "More" modal ──────────────────────────────────

class _MobileLayout extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _MobileLayout({
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout> {
  // Mobile bottom nav shows 5 items: Dashboard, Orders, Live, Users, More
  static const _kBottomNav = [
    (LucideIcons.layoutDashboard, 'Dashboard', 0),
    (LucideIcons.clipboardList, 'Orders', 1),
    (LucideIcons.radio, 'Live', 2),
    (LucideIcons.users, 'Users', 3),
  ];

  int get _bottomIndex {
    // Map screen index to bottom tab index (0-3 = primary, anything else = "More")
    if (widget.selectedIndex < 4) return widget.selectedIndex;
    return -1; // "More" active
  }

  String get _screenTitle {
    if (widget.selectedIndex < _kPrimary.length) {
      return _kPrimary[widget.selectedIndex].$2;
    }
    final secIdx = widget.selectedIndex - _kPrimary.length;
    if (secIdx < _kSecondary.length) return _kSecondary[secIdx].$2;
    return 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF2962FF)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.shield,
                  size: 14, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(
              _screenTitle,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut,
                size: 18, color: AppColors.textSecondary),
            onPressed: widget.onLogout,
            tooltip: 'Logout',
          ),
        ],
        shape: const Border(
            bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: widget.selectedIndex,
          children: _kAllScreens,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 62,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              ..._kBottomNav.map((dest) {
                final (icon, label, idx) = dest;
                final active = _bottomIndex == idx;
                final color =
                    active ? AppColors.primary : AppColors.navInactive;
                return Expanded(
                  child: InkWell(
                    onTap: () => widget.onSelect(idx),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (active)
                          Container(
                            width: 28,
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        Icon(icon, size: 20, color: color),
                        const SizedBox(height: 3),
                        Text(label,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: color,
                            )),
                      ],
                    ),
                  ),
                );
              }),
              // "More" tab
              Expanded(
                child: InkWell(
                  onTap: () => _showMoreSheet(context),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_bottomIndex == -1)
                        Container(
                          width: 28,
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      Icon(LucideIcons.moreHorizontal,
                          size: 20,
                          color: _bottomIndex == -1
                              ? AppColors.primary
                              : AppColors.navInactive),
                      const SizedBox(height: 3),
                      Text('More',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: _bottomIndex == -1
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _bottomIndex == -1
                                ? AppColors.primary
                                : AppColors.navInactive,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        // "More" screen items: Risk (4), Analytics (5), then all secondary
        final moreItems = <(IconData, String, int)>[
          (_kPrimary[4].$1, _kPrimary[4].$2, 4),
          (_kPrimary[5].$1, _kPrimary[5].$2, 5),
          ..._kSecondary.asMap().entries.map(
              (e) => (e.value.$1, e.value.$2, _kPrimary.length + e.key)),
        ];

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('More Options',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    children: moreItems.map((item) {
                      final (icon, label, idx) = item;
                      final active = widget.selectedIndex == idx;
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon,
                              size: 16,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                        ),
                        title: Text(label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            )),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelect(idx);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
