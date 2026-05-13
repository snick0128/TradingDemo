import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app_scope.dart';
import 'config/backend_config.dart';
import 'data/providers/backend_price_provider.dart';
import 'data/services/auth_service.dart';
import 'data/services/backend_api_service.dart';
import 'data/services/firestore_service.dart';
import 'data/services/order_engine_service.dart';
import 'data/services/trading_service.dart';
import 'domain/auth/auth_session.dart';
import 'firebase_options.dart';
import 'screens/auth/admin_login_screen.dart';
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
    // Firebase not configured — fallback to local mock mode.
  }

  runApp(BoxTradingAdminApp(firebaseReady: firebaseReady));
}

class BoxTradingAdminApp extends StatefulWidget {
  final bool firebaseReady;
  const BoxTradingAdminApp({super.key, required this.firebaseReady});

  @override
  State<BoxTradingAdminApp> createState() => _BoxTradingAdminAppState();
}

class _BoxTradingAdminAppState extends State<BoxTradingAdminApp> {
  late final SecurityStore _securityStore;
  late final TradingStore _tradingStore;
  late final AdminStore _adminStore;

  late final AuthSession _authSession;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  TradingService? _tradingService;
  OrderEngineService? _orderEngineService;

  final ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _securityStore = SecurityStore(lockTimeout: const Duration(minutes: 15));
    _tradingStore = TradingStore();
    _authSession = AuthSession();
    _authSession.addListener(_syncAdminContext);

    if (widget.firebaseReady) {
      final firestore = FirestoreService(FirebaseFirestore.instance);
      _firestoreService = firestore;
      _authService = AuthService(
        auth: FirebaseAuth.instance,
        firestore: firestore,
      );
      final priceProvider = BackendPriceProvider(
        api: BackendApiService(baseUrl: BackendConfig.backendBaseUrl),
      );
      _tradingService = TradingService(
        firestore: firestore,
        priceProvider: priceProvider,
      );
      _orderEngineService = OrderEngineService(
        tradingService: _tradingService!,
        firestore: FirebaseFirestore.instance,
        priceProvider: priceProvider,
      );
      // ⚠️ Do NOT start the engine here — it must only run when an admin
      // is authenticated. Starting before login means all Firestore reads
      // inside processOrderRequest run as unauthenticated and fail silently.

      _adminStore = AdminStore(
        tradingService: _tradingService,
        firestoreService: _firestoreService,
      );

      _authService!.authStateChanges.listen((firebaseUser) async {
        if (firebaseUser == null) {
          _orderEngineService?.stop(); // stop engine on logout
          _authSession.setUser(null);
        } else if (!_authSession.isAuthenticated) {
          try {
            final profile = await _authService!.getCurrentProfile();
            _authSession.setUser(profile);
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

  void _syncAdminContext() {
    final user = _authSession.user;
    final isAdmin = user?.isAdmin ?? false;

    _adminStore.setCurrentAdminId(user?.uid, isAdmin: isAdmin);

    // Start the order engine only when an admin is authenticated.
    // Stop it when the admin logs out.
    if (isAdmin && user != null) {
      _orderEngineService?.start();
    } else {
      _orderEngineService?.stop();
    }
  }

  @override
  void dispose() {
    _orderEngineService?.stop();
    _authSession.removeListener(_syncAdminContext);
    _adminStore.dispose();
    _tradingStore.dispose();
    _securityStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget app = _buildAdminApp();

    if (widget.firebaseReady &&
        _authService != null &&
        _firestoreService != null &&
        _tradingService != null) {
      app = AppScope(
        notifier: _authSession,
        authService: _authService!,
        firestoreService: _firestoreService!,
        tradingService: _tradingService!,
        child: app,
      );
    }

    return SecurityScope(
      notifier: _securityStore,
      child: TradingScope(
        notifier: _tradingStore,
        child: AdminScope(notifier: _adminStore, child: app),
      ),
    );
  }

  Widget _buildAdminApp() {
    if (!widget.firebaseReady) {
      return MaterialApp(
        title: 'Box Trading Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Firebase initialization failed.\nAdmin portal requires Firebase and will not run in mock mode.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Box Trading Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const AdminLoginScreen(),
      builder: (context, child) {
        final tradingStore = TradingScope.of(context);
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(tradingStore.textScaleFactor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
