import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/profile_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'state/security_scope.dart';
import 'state/security_store.dart';
import 'state/trading_scope.dart';
import 'state/trading_store.dart';
import 'widgets/shared_widgets.dart';

void main() {
  runApp(const BoxTradingApp());
}

class BoxTradingApp extends StatefulWidget {
  const BoxTradingApp({super.key});

  @override
  State<BoxTradingApp> createState() => _BoxTradingAppState();
}

class _BoxTradingAppState extends State<BoxTradingApp> {
  late final TradingStore _store;
  late final SecurityStore _securityStore;

  @override
  void initState() {
    super.initState();
    _store = TradingStore();
    _securityStore = SecurityStore(lockTimeout: const Duration(minutes: 5));
  }

  @override
  void dispose() {
    _securityStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SecurityScope(
      notifier: _securityStore,
      child: TradingScope(
        notifier: _store,
        child: MaterialApp(
          title: 'Box Trading',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          home: const MainShell(),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _monitoringStarted = false;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const OrdersScreen(),
    const PortfolioScreen(),
    const WalletScreen(),
    const ProfileScreen(),
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
    // Check screen width for responsiveness
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

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
                      onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: AppColors.surface,
                      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
                      selectedIconTheme: const IconThemeData(color: AppColors.primary),
                      destinations: const [
                        NavigationRailDestination(icon: Icon(LucideIcons.home), label: Text('Home')),
                        NavigationRailDestination(icon: Icon(LucideIcons.listTodo), label: Text('Orders')),
                        NavigationRailDestination(icon: Icon(LucideIcons.pieChart), label: Text('Portfolio')),
                        NavigationRailDestination(icon: Icon(LucideIcons.wallet), label: Text('Wallet')),
                        NavigationRailDestination(icon: Icon(LucideIcons.user), label: Text('Profile')),
                      ],
                    ),
                  if (isDesktop) const VerticalDivider(thickness: 1, width: 1, color: AppColors.border),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _screens,
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: !isDesktop
                  ? BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap: (idx) => setState(() => _selectedIndex = idx),
                      items: const [
                        BottomNavigationBarItem(icon: Icon(LucideIcons.home, size: 20), label: 'Home'),
                        BottomNavigationBarItem(icon: Icon(LucideIcons.listTodo, size: 20), label: 'Orders'),
                        BottomNavigationBarItem(icon: Icon(LucideIcons.pieChart, size: 20), label: 'Portfolio'),
                        BottomNavigationBarItem(icon: Icon(LucideIcons.wallet, size: 20), label: 'Wallet'),
                        BottomNavigationBarItem(icon: Icon(LucideIcons.user, size: 20), label: 'Profile'),
                      ],
                    )
                  : null,
            ),
            if (security.isLocked) const Positioned.fill(child: PinLockOverlay()),
          ],
        ),
      ),
    );
  }
}

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
  State<WidgetsBindingObserverWrapper> createState() => _WidgetsBindingObserverWrapperState();
}

class _WidgetsBindingObserverWrapperState extends State<WidgetsBindingObserverWrapper>
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
      color: AppColors.background.withValues(alpha: 0.96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: CustomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shield, size: 30, color: AppColors.accent),
                const SizedBox(height: 10),
                Text('Session Locked', style: Theme.of(context).textTheme.titleMedium),
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
                    child: Text(_error, style: const TextStyle(color: AppColors.danger)),
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
