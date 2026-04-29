import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app_router.dart';
import 'firebase_options.dart';
import 'app/app_scope.dart';
import 'data/providers/mock_price_provider.dart';
import 'data/services/auth_service.dart';
import 'data/services/firestore_service.dart';
import 'data/services/trading_service.dart';
import 'domain/auth/app_user_profile.dart';
import 'domain/auth/auth_session.dart';
import 'models/trading_models.dart';
import 'screens/main_shell.dart';
import 'state/admin_scope.dart';
import 'state/admin_store.dart';
import 'state/security_scope.dart';
import 'state/security_store.dart';
import 'state/trading_scope.dart';
import 'state/trading_store.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (_) {
    // Firebase not configured — app runs in mock-only mode.
  }

  runApp(BoxTradingApp(firebaseReady: firebaseReady));
}

class BoxTradingApp extends StatefulWidget {
  final bool firebaseReady;
  const BoxTradingApp({super.key, required this.firebaseReady});

  @override
  State<BoxTradingApp> createState() => _BoxTradingAppState();
}

class _BoxTradingAppState extends State<BoxTradingApp> {
  // Existing mock stores (power the full trading UI)
  late final TradingStore _tradingStore;
  late final SecurityStore _securityStore;
  late final AdminStore _adminStore;

  // Firebase / clean-arch layer
  late final AuthSession _authSession;
  FirestoreService? _firestoreService;
  AuthService? _authService;
  TradingService? _tradingService;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _positionsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _holdingsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _tradingStore = TradingStore();
    _securityStore = SecurityStore(lockTimeout: const Duration(minutes: 5));
    _authSession = AuthSession();
    _authSession.addListener(_syncTradingUserFromAuthSession);

    if (widget.firebaseReady) {
      final firestore = FirestoreService(FirebaseFirestore.instance);
      _firestoreService = firestore;
      _authService = AuthService(
        auth: FirebaseAuth.instance,
        firestore: firestore,
      );
      _tradingService = TradingService(
        firestore: firestore,
        priceProvider: MockPriceProvider(),
      );
      _adminStore = AdminStore(
        tradingService: _tradingService,
        firestoreService: _firestoreService,
      );

      // Restore session from Firebase auth state on app start only.
      // Skip if session already has a user (set by loginUser/loginAdmin directly).
      _authService!.authStateChanges.listen((firebaseUser) async {
        if (firebaseUser == null) {
          await _ordersSub?.cancel();
          await _positionsSub?.cancel();
          await _holdingsSub?.cancel();
          await _userSub?.cancel();
          _ordersSub = null;
          _positionsSub = null;
          _holdingsSub = null;
          _userSub = null;
          _tradingStore.replaceOrders(const <Order>[]);
          _tradingStore.replacePositions(const <Position>[]);
          _authSession.setUser(null);
        } else if (!_authSession.isAuthenticated) {
          // Only fetch from Firestore on cold start (page refresh / app reopen).
          // During active login, loginUser() already set the session — skip.
          try {
            final profile = await _authService!.getCurrentProfile();
            _authSession.setUser(profile);
            _bindUserRealtime(profile?.uid);
          } catch (_) {
            _authSession.setUser(null);
          }
        }
      });
    } else {
      _adminStore = AdminStore();
      _authSession.setLoading(false);
    }
  }

  void _syncTradingUserFromAuthSession() {
    final profile = _authSession.user;
    _adminStore.setCurrentAdminId(
      profile?.uid,
      isAdmin: profile?.isAdmin ?? false,
    );
    _bindUserRealtime(profile?.uid);
    if (profile == null) return;

    final mappedUser = _mapProfileToTradingUser(
      profile,
      fallback: _tradingStore.currentUser,
    );
    _tradingStore.updateUser(mappedUser, updateBalance: true);
  }

  User _mapProfileToTradingUser(
    AppUserProfile profile, {
    required User fallback,
  }) {
    final emailLocalPart = profile.email.split('@').first.trim();
    final uidPrefix = profile.uid.substring(0, profile.uid.length > 8 ? 8 : profile.uid.length);
    final clientId = emailLocalPart.isNotEmpty
        ? emailLocalPart
        : uidPrefix;

    return fallback.copyWith(
      id: profile.uid,
      clientId: clientId,
      name: profile.name,
      email: profile.email,
      isActive: profile.tradingEnabled,
      balance: profile.balance,
      isAdmin: profile.isAdmin,
      lastLoginAt: DateTime.now(),
      brokeragePlan: profile.isAdmin ? 'Admin' : fallback.brokeragePlan,
    );
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  void dispose() {
    _authSession.removeListener(_syncTradingUserFromAuthSession);
    _ordersSub?.cancel();
    _positionsSub?.cancel();
    _holdingsSub?.cancel();
    _userSub?.cancel();
    _adminStore.dispose();
    _tradingStore.dispose();
    _securityStore.dispose();
    super.dispose();
  }

  void _bindUserRealtime(String? userId) {
    if (_tradingService == null) return;
    if (userId == null || userId.isEmpty) {
      _ordersSub?.cancel();
      _positionsSub?.cancel();
      _holdingsSub?.cancel();
      _userSub?.cancel();
      _ordersSub = null;
      _positionsSub = null;
      _holdingsSub = null;
      _userSub = null;
      _tradingStore.replaceOrders(const <Order>[]);
      _tradingStore.replacePositions(const <Position>[]);
      return;
    }

    _userSub?.cancel();
    _userSub = _firestoreService?.raw.doc('users/$userId').snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final current = _tradingStore.currentUser;
      final name = (data['name'] as String?) ?? current.name;
      final email = (data['email'] as String?) ?? current.email;
      final balance = ((data['balance'] as num?) ?? current.balance).toDouble();
      final enabled = (data['tradingEnabled'] as bool?) ?? current.isActive;
      final role = (data['role'] as String?) ?? (current.isAdmin ? 'admin' : 'user');

      _tradingStore.updateUser(
        current.copyWith(
          id: userId,
          name: name,
          email: email,
          balance: balance,
          isActive: enabled,
          isAdmin: role == 'admin',
        ),
        updateBalance: true,
      );
    });

    _ordersSub?.cancel();
    _ordersSub = _tradingService!.ordersStreamForUser(userId).listen((snapshot) {
      final List<Order> mapped = snapshot.docs.map<Order>((doc) {
        final data = doc.data();
        final rawType = (data['type'] as String?)?.toUpperCase() ?? 'BUY';
        final rawStatus = (data['status'] as String?)?.toUpperCase() ?? 'PENDING';
        final timestamp = data['createdAt'];
        final dateTime = timestamp is Timestamp
            ? timestamp.toDate()
            : DateTime.now();

        return Order(
          id: doc.id,
          symbol: (data['stock'] as String?) ?? 'N/A',
          name: (data['stock'] as String?) ?? 'N/A',
          quantity: ((data['qty'] as num?) ?? 0).toInt(),
          price: ((data['fillPrice'] as num?) ?? (data['price'] as num?) ?? 0)
              .toDouble(),
          type: rawType == 'SELL' ? OrderType.sell : OrderType.buy,
          status: _mapOrderStatus(rawStatus),
          dateTime: dateTime,
          rejectionReason: data['rejectionReason'] as String?,
          executedPrice: (data['fillPrice'] as num?)?.toDouble(),
        );
      }).toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

      _tradingStore.replaceOrders(mapped);
    });

    _positionsSub?.cancel();
    _positionsSub = _tradingService!.positionsStreamForUser(userId).listen((snapshot) {
      final List<Position> mapped = snapshot.docs.map((doc) {
        final data = doc.data();
        final qty = ((data['qty'] as num?) ?? 0).toInt();
        final signedQty = qty == 0 ? 0 : qty;
        final symbol = (data['stock'] as String?) ?? 'N/A';
        // Field is written as 'avg_price' (snake_case) by TradingService
        final avgPrice = ((data['avg_price'] as num?) ?? 0).toDouble();
        final currentPrice = _tradingStore.stockBySymbol(symbol).currentPrice;
        final updatedAt = data['updatedAt'];
        final openedAt = updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now();

        return Position(
          symbol: symbol,
          name: symbol,
          product: ProductType.nrml,
          quantity: signedQty.abs(),
          avgPrice: avgPrice,
          currentPrice: currentPrice,
          side: signedQty >= 0 ? OrderType.buy : OrderType.sell,
          openedAt: openedAt,
        );
      }).where((p) => p.quantity > 0).toList();

      _tradingStore.replacePositions(mapped);
    });

    // Holdings stream — reads from portfolios/{uid}/holdings/{stock}
    _holdingsSub?.cancel();
    _holdingsSub = _tradingService!.holdingsStreamForUser(userId).listen((snapshot) {
      final List<Holding> mapped = snapshot.docs.map((doc) {
        final data = doc.data();
        final symbol = (data['stock'] as String?) ?? doc.id;
        final qty = ((data['qty'] as num?) ?? 0).toInt();
        final avgPrice = ((data['avg_price'] as num?) ?? 0).toDouble();
        final currentPrice = _tradingStore.stockBySymbol(symbol).currentPrice;
        final updatedAt = data['updatedAt'];
        final purchaseDate = updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now();

        return Holding(
          symbol: symbol,
          name: symbol,
          quantity: qty,
          avgPrice: avgPrice,
          currentPrice: currentPrice,
          purchaseDate: purchaseDate,
        );
      }).where((h) => h.quantity > 0).toList();

      _tradingStore.replaceHoldings(mapped);
    });
  }

  OrderStatus _mapOrderStatus(String status) {
    switch (status) {
      case 'APPROVED':
        return OrderStatus.approved;
      case 'REJECTED':
        return OrderStatus.rejected;
      case 'CANCELLED':
        return OrderStatus.cancelled;
      case 'EXECUTED':
        return OrderStatus.executed;
      case 'PARTIALLY_EXECUTED':
        return OrderStatus.partiallyExecuted;
      default:
        return OrderStatus.pending;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget app = _buildFirebaseRequiredApp();

    if (widget.firebaseReady &&
        _authService != null &&
        _firestoreService != null &&
        _tradingService != null) {
      app = AppScope(
        notifier: _authSession,
        authService: _authService!,
        firestoreService: _firestoreService!,
        tradingService: _tradingService!,
        child: _buildRouterApp(),
      );
    }

    return SecurityScope(
      notifier: _securityStore,
      child: AdminScope(
        notifier: _adminStore,
        child: TradingScope(
          notifier: _tradingStore,
          child: ThemeController(
            onThemeToggle: _toggleTheme,
            child: ThemeControllerRef(
              onThemeToggle: _toggleTheme,
              child: app,
            ),
          ),
        ),
      ),
    );
  }

  /// Firebase mode: GoRouter with dual entry points and role guards.
  Widget _buildRouterApp() {
    final router = createAppRouter(_authSession);
    return MaterialApp.router(
      title: 'Trade Kosh',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        final ts = TradingScope.of(context);
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(ts.textScaleFactor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildFirebaseRequiredApp() {
    return MaterialApp(
      title: 'Trade Kosh',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase initialization failed.\n'
              'User app now requires Firebase and mock user/order data is disabled.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeController extends InheritedWidget {
  final VoidCallback onThemeToggle;
  const ThemeController({
    super.key,
    required this.onThemeToggle,
    required super.child,
  });
  static ThemeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeController>();
  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}
