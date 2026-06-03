import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../app/app_scope.dart';
import '../theme.dart';
import '../utils/responsive.dart';
import '../state/security_scope.dart';
import '../state/security_store.dart';
import '../widgets/shared_widgets.dart';
import 'dashboard_screen.dart';
import 'ipo_screen.dart';
import 'orders_screen.dart';
import 'portfolio_screen.dart';
import 'wallet_screen.dart';
import 'profile_screen.dart';

/// Thin route wrapper so auth screens can navigate here without importing main.dart.
class MainShellRoute extends StatelessWidget {
  const MainShellRoute({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_isSignedIn(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/app/login');
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return MainShell(onThemeToggle: ThemeControllerRef.of(context));
  }
}

/// Allows MainShellRoute to look up the theme toggle callback.
class ThemeControllerRef extends InheritedWidget {
  final VoidCallback onThemeToggle;
  const ThemeControllerRef({
    super.key,
    required this.onThemeToggle,
    required super.child,
  });

  static VoidCallback of(BuildContext context) {
    final ref = context
        .dependOnInheritedWidgetOfExactType<ThemeControllerRef>();
    return ref?.onThemeToggle ?? () {};
  }

  @override
  bool updateShouldNotify(covariant ThemeControllerRef oldWidget) => false;
}

class MainShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const MainShell({super.key, required this.onThemeToggle});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _monitoringStarted = false;

  final List<Widget> _screens = const [
    DashboardScreen(),
    OrdersScreen(),
    PortfolioScreen(),
    WalletScreen(),
    IPOScreen(showAppBar: false),
    ProfileScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_monitoringStarted) {
      SecurityScope.of(context).startMonitoring();
      _monitoringStarted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);

    // Guard: accept either Firebase auth session or legacy security auth.
    if (!_isSignedIn(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/app/login');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final layout = layoutForWidth(MediaQuery.of(context).size.width);
    final isDesktop = layout == AppLayoutBreakpoint.desktop;

    return WidgetsBindingObserverWrapper(
      onPaused: security.onAppPaused,
      onResumed: security.onAppResumed,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => security.registerActivity(),
        onPointerMove: (_) => security.registerActivity(),
        child: Stack(
          children: [
            Scaffold(
              body: Row(
                children: [
                  if (isDesktop)
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (idx) =>
                          setState(() => _selectedIndex = idx),
                      labelType: NavigationRailLabelType.all,
                      minWidth: 80,
                      backgroundColor: AppColors.surface,
                      unselectedIconTheme: const IconThemeData(
                        color: AppColors.textSecondary,
                      ),
                      selectedIconTheme: const IconThemeData(
                        color: AppColors.primary,
                      ),
                      unselectedLabelTextStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      selectedLabelTextStyle: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.home),
                          label: Text('Home'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.listTodo),
                          label: Text('Orders'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.pieChart),
                          label: Text('Portfolio'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.wallet),
                          label: Text('Wallet'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.barChart2),
                          label: Text('IPO'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(LucideIcons.user),
                          label: Text('Profile'),
                        ),
                      ],
                    ),
                  if (isDesktop)
                    const VerticalDivider(
                      thickness: 1,
                      width: 1,
                      color: AppColors.border,
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _screens,
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: !isDesktop
                  ? Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(
                          top: BorderSide(color: AppColors.border, width: 1),
                        ),
                      ),
                      child: SizedBox(
                        height: 60,
                        child: BottomNavigationBar(
                          currentIndex: _selectedIndex,
                          onTap: (idx) => setState(() => _selectedIndex = idx),
                          backgroundColor: AppColors.surface,
                          selectedItemColor: const Color(0xFF2962FF),
                          unselectedItemColor: const Color(0xFF9E9E9E),
                          type: BottomNavigationBarType.fixed,
                          elevation: 0,
                          selectedLabelStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelStyle: const TextStyle(fontSize: 11),
                          items: const [
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.home),
                              label: 'Home',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.listTodo),
                              label: 'Orders',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.pieChart),
                              label: 'Portfolio',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.wallet),
                              label: 'Wallet',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.barChart2),
                              label: 'IPO',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(LucideIcons.user),
                              label: 'Profile',
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
            if (security.isLocked)
              const Positioned.fill(child: PinLockOverlay()),
          ],
        ),
      ),
    );
  }
}

bool _isSignedIn(BuildContext context) {
  final security = SecurityScope.of(context);
  if (security.isAuthenticated) return true;

  final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
  final authSession = appScope?.notifier;
  return authSession?.isAuthenticated ?? false;
}

// ─── Supporting widgets (moved from main.dart) ────────────────────────────────

class WidgetsBindingObserverWrapper extends StatefulWidget {
  final VoidCallback onPaused;
  final VoidCallback onResumed;
  final Widget child;

  const WidgetsBindingObserverWrapper({
    super.key,
    required this.onPaused,
    required this.onResumed,
    required this.child,
  });

  @override
  State<WidgetsBindingObserverWrapper> createState() =>
      _WidgetsBindingObserverWrapperState();
}

class _WidgetsBindingObserverWrapperState
    extends State<WidgetsBindingObserverWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      widget.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PinLockOverlay extends StatefulWidget {
  const PinLockOverlay({super.key});

  @override
  State<PinLockOverlay> createState() => _PinLockOverlayState();
}

class _PinLockOverlayState extends State<PinLockOverlay> {
  final TextEditingController _pinController = TextEditingController();
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);

    return ColoredBox(
      color: AppColors.background.withOpacity(0.96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: CustomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.shield,
                  size: 30,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 10),
                Text(
                  'Session Locked',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter your 4-digit PIN to continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: '4-digit PIN',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() => _error = ''),
                  onSubmitted: (_) => _unlock(security),
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _unlock(security),
                  child: const Text('Unlock App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _unlock(SecurityStore security) {
    final input = _pinController.text.trim();
    final success = security.unlock(input);
    if (!success) {
      setState(() => _error = 'Invalid PIN. Try again.');
      return;
    }
    _pinController.clear();
    setState(() => _error = '');
  }
}
