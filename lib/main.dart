import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app_router.dart';
import 'firebase_options.dart';
import 'app/app_scope.dart';
import 'config/backend_config.dart';
import 'models/platform_settings.dart';
import 'data/providers/backend_price_provider.dart';
import 'data/services/auth_service.dart';
import 'data/services/backend_api_service.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _gttSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _positionsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _holdingsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rmsSub;

  // Separate position lists from each Firestore source so they are merged
  // rather than one stream wiping out the other's results.
  // _positionsSub reads portfolios/{uid}/positions (TradingService MIS path).
  // _holdingsSub reads portfolios/{uid}/holdings (backend orderEngine path).
  List<Position> _positionsFromPositionsColl = [];
  List<Position> _positionsFromHoldings = [];

  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _tradingStore = TradingStore();
    _securityStore = SecurityStore(lockTimeout: const Duration(minutes: 5));
    _authSession = AuthSession();
    _authSession.addListener(_syncTradingUserFromAuthSession);

    // ── Connect live backend prices ──────────────────────────────────────────
    // Replaces the mock random-walk price feed with real Angel One data.
    // Set BackendConfig.useLiveBackend = false to run fully offline.
    if (BackendConfig.useLiveBackend) {
      _tradingStore.connectLiveBackend();
    }

    if (widget.firebaseReady) {
      final firestore = FirestoreService(FirebaseFirestore.instance);
      _firestoreService = firestore;
      _authService = AuthService(
        auth: FirebaseAuth.instance,
        firestore: firestore,
      );
      _tradingService = TradingService(
        firestore: firestore,
        priceProvider: BackendPriceProvider(
          api: BackendApiService(baseUrl: BackendConfig.backendBaseUrl),
        ),
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
          await _gttSub?.cancel();
          await _positionsSub?.cancel();
          await _holdingsSub?.cancel();
          await _userSub?.cancel();
          _ordersSub = null;
          _gttSub = null;
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
    final uidPrefix = profile.uid.substring(
      0,
      profile.uid.length > 8 ? 8 : profile.uid.length,
    );
    final clientId = emailLocalPart.isNotEmpty ? emailLocalPart : uidPrefix;

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

  // Returns the best available unique key for a position.
  // Token (globally unique in Angel One's instrument DB) is used when
  // available; exchange:symbol is the fallback for positions loaded before
  // symbolToken was persisted to Firestore.
  static String _positionKey(Position p) =>
      p.token.isNotEmpty ? p.token : '${p.exchange}:${p.symbol}';

  // Merge positions from both Firestore sources and push to the store.
  // Holdings-stream positions take precedence; positions-stream positions
  // only fill in keys not already present from the holdings stream.
  void _mergeAndReplacePositions() {
    final holdingKeys = _positionsFromHoldings.map(_positionKey).toSet();
    final merged = <Position>[
      ..._positionsFromHoldings,
      ..._positionsFromPositionsColl.where(
        (p) => !holdingKeys.contains(_positionKey(p)),
      ),
    ];
    _tradingStore.replacePositions(merged);
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  void dispose() {
    _authSession.removeListener(_syncTradingUserFromAuthSession);
    _ordersSub?.cancel();
    _gttSub?.cancel();
    _positionsSub?.cancel();
    _holdingsSub?.cancel();
    _userSub?.cancel();
    _rmsSub?.cancel();
    _adminStore.dispose();
    _tradingStore.dispose();
    _securityStore.dispose();
    super.dispose();
  }

  String? _boundUserId; // tracks which user's streams are currently active

  void _bindUserRealtime(String? userId) {
    if (_tradingService == null) return;
    if (userId == null || userId.isEmpty) {
      _boundUserId = null;
      _ordersSub?.cancel();
      _positionsSub?.cancel();
      _holdingsSub?.cancel();
      _userSub?.cancel();
      _ordersSub = null;
      _positionsSub = null;
      _holdingsSub = null;
      _userSub = null;
      _positionsFromPositionsColl = [];
      _positionsFromHoldings = [];
      _tradingStore.replaceOrders(const <Order>[]);
      _tradingStore.replacePositions(const <Position>[]);
      return;
    }

    // Guard: don't re-bind if already listening for this user.
    // Prevents duplicate listeners when _syncTradingUserFromAuthSession and
    // the authStateChanges listener both call _bindUserRealtime for the same uid.
    if (_boundUserId == userId) return;
    _boundUserId = userId;

    // Register user with WebSocket for real-time notification push
    _tradingStore.registerLiveUser(userId);

    // Load platform settings (leverage config + support config) on user bind
    _loadPlatformSettings();

    _userSub?.cancel();
    _userSub = _firestoreService?.raw
        .doc('users/$userId')
        .snapshots()
        .listen(
          (doc) {
            final data = doc.data();
            if (data == null) return;
            final current = _tradingStore.currentUser;
            final name = (data['name'] as String?) ?? current.name;
            final email = (data['email'] as String?) ?? current.email;
            final balance = ((data['balance'] as num?) ?? current.balance)
                .toDouble();
            final enabled =
                (data['tradingEnabled'] as bool?) ?? current.isActive;
            final role =
                (data['role'] as String?) ??
                (current.isAdmin ? 'admin' : 'user');

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

            // Parse and stream live equity metrics persisted by the backend RMS engine.
            // The backend writes: walletBalance, usedMargin, freeMargin, equity,
            // marginLevel, runningPnL, lastEquityUpdate to this document on every tick.
            final equityData = data.cast<String, dynamic>();
            _tradingStore.updateAccountEquity(
              AccountEquity.fromFirestore(equityData),
            );
          },
          onError: (e) {
            // Non-fatal: user profile stream error — keep showing cached data
          },
        );

    _ordersSub?.cancel();
    _ordersSub = _tradingService!
        .ordersStreamForUser(userId)
        .listen(
          (snapshot) {
            final List<Order> mapped = snapshot.docs.map<Order>((doc) {
              final data = doc.data();
              final rawType = (data['type'] as String?)?.toUpperCase() ?? 'BUY';
              final rawStatus =
                  (data['status'] as String?)?.toUpperCase() ?? 'PENDING';
              final timestamp = data['createdAt'];
              final dateTime = timestamp is Timestamp
                  ? timestamp.toDate()
                  : timestamp is int
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp as int)
                  : DateTime.utc(1970);

              // product: backend writes 'productType', TradingService writes 'product'
              final rawProduct = ((data['productType'] as String?) ??
                      (data['product'] as String?) ??
                      'MIS')
                  .toUpperCase();
              // variety: normalize backend 'MARKET' / TradingService 'MARKET'
              final rawVariety = ((data['variety'] as String?) ?? 'MARKET')
                  .toUpperCase();

              return Order(
                id: doc.id,
                symbol: (data['stock'] as String?)?.trim().isNotEmpty == true
                    ? (data['stock'] as String).trim()
                    : doc.id,
                name:
                    (data['symbolName'] as String?)?.trim() ??
                    (data['stock'] as String?)?.trim() ??
                    doc.id,
                quantity: ((data['qty'] as num?) ?? 0).toInt(),
                price:
                    ((data['avg_executed_price'] as num?) ??
                            (data['executed_price'] as num?) ??
                            (data['fillPrice'] as num?) ??
                            (data['price'] as num?) ??
                            0)
                        .toDouble(),
                type: rawType == 'SELL' ? OrderType.sell : OrderType.buy,
                status: _mapOrderStatus(rawStatus),
                dateTime: dateTime,
                product: _mapProductType(rawProduct),
                variety: _mapOrderVariety(rawVariety),
                rejectionReason: data['rejectionReason'] as String?,
                executedAt: data['executedAt'] is Timestamp
                    ? (data['executedAt'] as Timestamp).toDate()
                    : data['executedAt'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                        data['executedAt'] as int,
                      )
                    : null,
                executedPrice:
                    ((data['avg_executed_price'] as num?) ??
                            (data['executed_price'] as num?) ??
                            (data['fillPrice'] as num?))
                        ?.toDouble(),
                pnl: ((data['pnl'] as num?) ?? 0).toDouble(),
                chargesApplied: (data['chargesApplied'] as num?)?.toDouble(),
                exchange: (data['exchange'] as String?)?.trim().toUpperCase(),
                leverageApplied:
                    (data['leverageApplied'] as num?)?.toDouble(),
                marginUsed: (data['marginUsed'] as num?)?.toDouble(),
                isAutoSquareOff:
                    (data['isAutoSquareOff'] as bool?) ?? false,
              );
            }).toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

            _tradingStore.replaceOrders(mapped);
          },
          onError: (e) {
            // Non-fatal: orders stream error — keep showing cached orders.
            // Most likely cause: missing composite index (userId + createdAt).
            // Deploy firestore.indexes.json to fix permanently.
          },
        );

    _gttSub?.cancel();
    _gttSub = _tradingService!
        .gttOrdersStreamForUser(userId)
        .listen(
          (snapshot) {
            final List<GTTOrder> mapped = snapshot.docs.map((doc) {
              final data = doc.data();
              final timestamp = data['createdAt'];
              final createdAt = timestamp is Timestamp
                  ? timestamp.toDate()
                  : DateTime.now();

              return GTTOrder(
                id: doc.id,
                symbol: (data['symbol'] as String?) ?? 'N/A',
                type: (data['type'] as String?) == 'OCO'
                    ? GTTType.oco
                    : GTTType.single,
                triggerPrice: (data['triggerPrice'] as num).toDouble(),
                secondTriggerPrice: (data['secondTriggerPrice'] as num?)
                    ?.toDouble(),
                orderType: (data['orderType'] as String?) == 'SELL'
                    ? OrderType.sell
                    : OrderType.buy,
                quantity: (data['quantity'] as num).toInt(),
                limitPrice: (data['limitPrice'] as num?)?.toDouble(),
                isActive: (data['isActive'] as bool?) ?? true,
                createdAt: createdAt,
                triggeredAt: data['triggeredAt'] is Timestamp
                    ? (data['triggeredAt'] as Timestamp).toDate()
                    : data['triggeredAt'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                        data['triggeredAt'] as int,
                      )
                    : null,
              );
            }).toList();
            _tradingStore.replaceGttOrders(mapped);
          },
          onError: (e) {
            // Non-fatal: GTT orders stream error
          },
        );

    _positionsSub?.cancel();
    _positionsSub = _tradingService!
        .positionsStreamForUser(userId)
        .listen(
          (snapshot) {
            final List<Position> mapped = snapshot.docs
                .map((doc) {
                  final data = doc.data();
                  final qty = ((data['qty'] as num?) ?? 0).toInt();
                  final rawSymbol = (data['stock'] as String?)?.trim() ?? '';
                  final symbol = rawSymbol.isNotEmpty ? rawSymbol : doc.id;
                  final symbolName =
                      (data['symbolName'] as String?)?.trim() ??
                      (data['name'] as String?)?.trim() ??
                      symbol;
                  final rawProduct =
                      (data['product'] as String?)?.trim() ?? 'MIS';
                  final rawSide =
                      (data['side'] as String?)?.trim().toUpperCase() ??
                      (qty >= 0 ? 'BUY' : 'SELL');
                  final avgPrice = ((data['avg_price'] as num?) ?? 0)
                      .toDouble();
                  final stockLtp = _tradingStore
                      .stockBySymbol(symbol)
                      .currentPrice;
                  final currentPrice = stockLtp > 0 ? stockLtp : avgPrice;
                  final updatedAt = data['updatedAt'];
                  final openedAt = updatedAt is Timestamp
                      ? updatedAt.toDate()
                      : DateTime.now();

                  final rawExchange =
                      (data['exchange'] as String?)?.trim().toUpperCase() ??
                      'NSE';
                  // Prefer symbolToken stored in Firestore; fall back to token
                  // cached in the live-price universe (populated after WS tick
                  // or search-result registration).
                  final token =
                      (data['symbolToken'] as String?)?.trim() ??
                      _tradingStore.stockBySymbolOrNull(symbol)?.token ??
                      '';
                  return Position(
                    symbol: symbol,
                    name: symbolName,
                    product: _mapProductType(rawProduct),
                    quantity: qty.abs(),
                    avgPrice: avgPrice,
                    currentPrice: currentPrice,
                    side: rawSide == 'SELL' ? OrderType.sell : OrderType.buy,
                    openedAt: openedAt,
                    exchange: rawExchange,
                    token: token,
                  );
                })
                .where((p) => p.quantity > 0)
                .toList();

            _positionsFromPositionsColl = mapped;
            _mergeAndReplacePositions();
          },
          onError: (e) {
            // Non-fatal: positions stream error
          },
        );

    // Holdings stream — reads from portfolios/{uid}/holdings/{stock}
    // The backend writes ALL trades here (MIS + CNC/NRML).
    // Split by productType: MIS → positions, CNC/NRML → holdings.
    _holdingsSub?.cancel();
    _holdingsSub = _tradingService!
        .holdingsStreamForUser(userId)
        .listen(
          (snapshot) {
            final List<Holding> newHoldings = [];
            final List<Position> newPositions = [];

            for (final doc in snapshot.docs) {
              final data = doc.data();
              final symbol = ((data['stock'] as String?) ?? doc.id)
                  .toUpperCase();
              final qty = ((data['qty'] as num?) ?? 0).toInt();
              if (qty <= 0) continue;

              final avgPrice = ((data['avg_price'] as num?) ?? 0).toDouble();
              final productType = ((data['productType'] as String?) ?? 'MIS')
                  .toUpperCase();
              final rawSide =
                  ((data['side'] as String?) ?? 'BUY').trim().toUpperCase();
              final isShort = rawSide == 'SELL';
              final stockLtp = _tradingStore
                  .stockBySymbol(symbol)
                  .currentPrice;
              final currentPrice = stockLtp > 0 ? stockLtp : avgPrice;
              final updatedAt = data['updatedAt'];
              final date = updatedAt is Timestamp
                  ? updatedAt.toDate()
                  : updatedAt is int
                  ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
                  : DateTime.now();

              if ((productType == 'CNC' || productType == 'NRML') &&
                  !isShort) {
                // Long NRML/CNC holdings → Holdings tab
                newHoldings.add(
                  Holding(
                    symbol: symbol,
                    name: symbol,
                    quantity: qty,
                    avgPrice: avgPrice,
                    currentPrice: currentPrice,
                    purchaseDate: date,
                  ),
                );
              } else {
                // MIS positions + short NRML/MIS → Positions tab
                final posExchange =
                    ((data['exchange'] as String?)?.trim().toUpperCase()) ??
                    'NSE';
                final posToken =
                    (data['symbolToken'] as String?)?.trim() ??
                    _tradingStore.stockBySymbolOrNull(symbol)?.token ??
                    '';
                newPositions.add(
                  Position(
                    symbol: symbol,
                    name: symbol,
                    product: productType == 'NRML'
                        ? ProductType.nrml
                        : ProductType.mis,
                    quantity: qty,
                    avgPrice: avgPrice,
                    currentPrice: currentPrice,
                    side: isShort ? OrderType.sell : OrderType.buy,
                    openedAt: date,
                    exchange: posExchange,
                    marginUsed: (data['marginUsed'] as num?)?.toDouble() ?? 0.0,
                    token: posToken,
                  ),
                );
              }
            }

            _tradingStore.replaceHoldings(newHoldings);
            _positionsFromHoldings = newPositions;
            _mergeAndReplacePositions();
          },
          onError: (e) {
            // Non-fatal: holdings stream error
          },
        );
  }

  Future<void> _loadPlatformSettings() async {
    final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
    try {
      final results = await Future.wait([
        api.getRmsSettings(),
        api.getSupportConfig(),
      ]);
      _tradingStore.updateRmsSettings(PlatformRmsSettings.fromMap(results[0]));
      _tradingStore.updateSupportConfig(SupportConfig.fromMap(results[1]));
    } catch (_) {
      // Non-fatal — defaults remain in effect
    }

    // Subscribe to real-time updates from admin_config/rms_settings so that
    // leverage changes made by the admin propagate to all open sessions
    // without requiring a page reload.
    _rmsSub?.cancel();
    _rmsSub = FirebaseFirestore.instance
        .collection('admin_config')
        .doc('rms_settings')
        .snapshots()
        .listen((doc) {
          if (!doc.exists) return;
          final updated = PlatformRmsSettings.fromMap(doc.data()!);
          _tradingStore.updateRmsSettings(updated);
        }, onError: (_) {});
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
      case 'FAILED':
        return OrderStatus.rejected;
      default:
        return OrderStatus.pending;
    }
  }

  ProductType _mapProductType(String product) {
    switch (product.toUpperCase()) {
      case 'MIS':
        return ProductType.mis;
      case 'NRML':
        return ProductType.nrml;
      case 'OVERNIGHT':
        return ProductType.overnight;
      case 'MTF':
        return ProductType.mtf;
      default:
        return ProductType.mis;
    }
  }

  OrderVariety _mapOrderVariety(String variety) {
    switch (variety.toUpperCase()) {
      case 'LIMIT':
        return OrderVariety.limit;
      case 'SL':
      case 'SL_LIMIT':
        return OrderVariety.sl;
      case 'AMO':
        return OrderVariety.amo;
      case 'ICEBERG':
        return OrderVariety.iceberg;
      case 'MARKET':
      default:
        return OrderVariety.market;
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
            child: ThemeControllerRef(onThemeToggle: _toggleTheme, child: app),
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
          data: mq.copyWith(textScaler: TextScaler.linear(ts.textScaleFactor)),
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
