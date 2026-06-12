import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../app/app_scope.dart';
import '../theme.dart';
import '../utils/responsive.dart';
import '../state/security_scope.dart';
import '../state/security_store.dart';
import '../state/trading_scope.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import 'dashboard_screen.dart';
import 'market_watch_screen.dart';
import 'orders_screen.dart';
import 'portfolio_screen.dart';
import 'profile_screen.dart';
import '../services/subscription_manager.dart';

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

  // Tab indices:
  //   0 → Home (Dashboard)
  //   1 → Markets (Market Watch)
  //   2 → Orders
  //   3 → Portfolio
  //   4 → Profile
  final List<Widget> _screens = const [
    DashboardScreen(),
    MarketWatchScreen(),
    OrdersScreen(),
    PortfolioScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateTabSubscription(_selectedIndex);
      }
    });
  }

  void _onTabSelected(int idx) {
    setState(() => _selectedIndex = idx);
    _updateTabSubscription(idx);
  }

  void _updateTabSubscription(int idx) {
    final store = TradingScope.read(context);
    if (idx == 0) {
      // Home — subscribe to dashboard symbols (watchlist + open positions/holdings)
      final symbols = {
        'NIFTY',
        'BANKNIFTY',
        ...store.watchlist.map((s) => s.symbol),
        ...store.positions.map((p) => p.symbol),
        ...store.holdings.map((h) => h.symbol),
      };
      SubscriptionManager.instance.switchTab('dashboard', symbols);
    } else if (idx == 3) {
      // Portfolio — subscribe to live P&L symbols
      final symbols = {
        ...store.positions.map((p) => p.symbol),
        ...store.holdings.map((h) => h.symbol),
      };
      SubscriptionManager.instance.switchTab('portfolio', symbols);
    } else {
      // Markets / Orders / Profile — MarketWatchScreen manages its own subs
      SubscriptionManager.instance.switchTab('other', {});
    }
  }

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
      onResumed: () {
        security.onAppResumed();
        TradingScope.read(context).onAppResumed();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => security.registerActivity(),
        onPointerMove: (_) => security.registerActivity(),
        child: Stack(
          children: [
            Scaffold(
              // Allow the body to extend behind the floating glass nav bar
              // so BackdropFilter actually picks up real content to blur.
              extendBody: true,
              // ── Desktop: side rail ───────────────────────────────────
              // ── Mobile/Tablet: body fills screen; floating nav overlaid
              //    below in the Stack with a transparent spacer here.
              body: Row(
                children: [
                  if (isDesktop)
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _onTabSelected,
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
                          icon: Icon(LucideIcons.trendingUp),
                          label: Text('Markets'),
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

              // Invisible spacer so Scaffold reserves bottom space and inner
              // screens' scroll views don't go behind the floating pill.
              // TradingBottomNavBar renders the actual UI in the Stack below.
              bottomNavigationBar: !isDesktop
                  ? SizedBox(height: TradingBottomNavBar.kReservedHeight)
                  : null,
            ),

            // ── Floating bottom nav (mobile + tablet) ────────────────────
            if (!isDesktop)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TradingBottomNavBar(
                  selectedIndex: _selectedIndex,
                  onTap: _onTabSelected,
                ),
              ),

            // ── Security lock overlay ─────────────────────────────────────
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
