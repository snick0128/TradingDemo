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
import '../state/tab_notifier.dart';

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
        activeTabNotifier.value = _selectedIndex;
        _updateTabSubscription(_selectedIndex);
      }
    });
  }

  void _onTabSelected(int idx) {
    setState(() => _selectedIndex = idx);
    activeTabNotifier.value = idx;
    _updateTabSubscription(idx);
  }

  void _updateTabSubscription(int idx) {
    final store = TradingScope.read(context);
    // Notify MarketWatchScreen whether it is the active tab so it can
    // subscribe/unsubscribe its own symbols without conflicting with other tabs.
    MarketWatchScreen.isActiveNotifier.value = idx == 1;

    if (idx == 0) {
      // Home — subscribe to dashboard symbols (user watchlist + open positions/holdings)
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
  String _pin = '';
  String _error = '';

  void _onDigit(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = '';
    });
    if (_pin.length == 4) _unlock();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _unlock() {
    final security = SecurityScope.of(context);
    final success = security.unlock(_pin);
    setState(() {
      _pin = '';
      _error = success ? '' : 'Incorrect PIN. Try again.';
    });
  }

  void _useBiometrics() {
    SecurityScope.of(context).biometricUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Enter PIN',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use PIN ${security.pin} to continue',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _pin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: filled ? AppColors.primary : AppColors.border,
                            width: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 18,
                    child: _error.isEmpty
                        ? null
                        : Text(
                            _error,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _keypadRow(['1', '2', '3']),
                  _keypadRow(['4', '5', '6']),
                  _keypadRow(['7', '8', '9']),
                  _keypadRow([null, '0', 'back']),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _useBiometrics,
                    icon: const Icon(Icons.fingerprint, size: 18, color: AppColors.primary),
                    label: const Text(
                      'Use Biometrics',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypadRow(List<String?> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((key) {
          if (key == null) return const SizedBox(width: 84, height: 60);
          if (key == 'back') return _keypadBackspaceButton();
          return _keypadDigitButton(key);
        }).toList(),
      ),
    );
  }

  Widget _keypadDigitButton(String digit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onDigit(digit),
          child: SizedBox(
            width: 72,
            height: 60,
            child: Center(
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypadBackspaceButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _onBackspace,
          child: const SizedBox(
            width: 72,
            height: 60,
            child: Center(
              child: Icon(Icons.backspace_outlined, size: 20, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
