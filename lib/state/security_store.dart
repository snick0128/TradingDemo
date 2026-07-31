import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/trading_models.dart';

class SecurityStore extends ChangeNotifier {
  SecurityStore({Duration? lockTimeout})
    : _lockTimeout = lockTimeout ?? const Duration(minutes: 5);

  final Duration _lockTimeout;

  String _pin = '1234';
  bool _isLocked = false;
  DateTime? _pausedAt;
  Timer? _idleTimer;

  // Authentication state
  bool _isAuthenticated = false;
  User? _currentUser;
  final List<DateTime> _sessionLog = [];

  bool get isLocked => _isLocked;
  String get pin => _pin;
  Duration get lockTimeout => _lockTimeout;
  bool get isAuthenticated => _isAuthenticated;
  User? get currentUser => _currentUser;
  List<DateTime> get sessionLog => List.unmodifiable(_sessionLog);

  // ─── Authentication ────────────────────────────────────────────────────────

  bool authenticate(String clientId, String password) {
    if (clientId == 'demo' && password == 'password') {
      _isAuthenticated = true;
      _currentUser = User(
        id: 'demo-user',
        clientId: 'demo',
        name: 'Demo User',
        email: 'demo@tradekosh.app',
        isActive: true,
        balance: 100000,
        marginLimit: 0,
        registeredAt: DateTime.now(),
      );
      _sessionLog.add(DateTime.now());
      _isLocked = false;
      _resetIdleTimer();
      notifyListeners();
      return true;
    }
    if (clientId == 'admin' && password == 'admin123') {
      _isAuthenticated = true;
      _currentUser = User(
        id: 'admin-user',
        clientId: 'admin',
        name: 'Admin',
        email: 'admin@tradekosh.app',
        isActive: true,
        balance: 0,
        marginLimit: 0,
        registeredAt: DateTime.now(),
        isAdmin: true,
      );
      _sessionLog.add(DateTime.now());
      _isLocked = false;
      _resetIdleTimer();
      notifyListeners();
      return true;
    }
    _isAuthenticated = false;
    _currentUser = null;
    notifyListeners();
    return false;
  }

  bool register(String name, String email, double balance) {
    if (name.trim().isEmpty || email.trim().isEmpty || balance < 0) {
      return false;
    }
    _isAuthenticated = true;
    _currentUser = User(
      id: 'reg-${DateTime.now().millisecondsSinceEpoch}',
      clientId: email.split('@').first,
      name: name.trim(),
      email: email.trim(),
      isActive: true,
      balance: balance,
      marginLimit: 0,
      registeredAt: DateTime.now(),
    );
    _sessionLog.add(DateTime.now());
    _isLocked = false;
    _resetIdleTimer();
    notifyListeners();
    return true;
  }

  void setPin(String pin) {
    _pin = pin;
    // PIN setup happens right after login/register, so ensure authenticated
    _isAuthenticated = true;
    if (_sessionLog.isEmpty) {
      _sessionLog.add(DateTime.now());
    }
    notifyListeners();
  }

  bool biometricUnlock() {
    // Simulate biometric: always succeeds for demo
    _isAuthenticated = true;
    _isLocked = false;
    _sessionLog.add(DateTime.now());
    _resetIdleTimer();
    notifyListeners();
    return true;
  }

  void killAllSessions() {
    _isAuthenticated = false;
    _currentUser = null;
    _isLocked = true;
    _idleTimer?.cancel();
    notifyListeners();
  }

  // ─── PIN / Lock ────────────────────────────────────────────────────────────

  void startMonitoring() {
    _resetIdleTimer();
  }

  void disposeMonitoring() {
    _idleTimer?.cancel();
  }

  void registerActivity() {
    if (!_isLocked) {
      _resetIdleTimer();
    }
  }

  void onAppPaused() {
    _pausedAt = DateTime.now();
  }

  void onAppResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;

    if (pausedAt == null) return;

    final awayDuration = DateTime.now().difference(pausedAt);
    if (awayDuration >= _lockTimeout) {
      lockNow();
      return;
    }

    if (!_isLocked) {
      _resetIdleTimer();
    }
  }

  void lockNow() {
    if (_isLocked) return;
    _isLocked = true;
    _idleTimer?.cancel();
    notifyListeners();
  }

  bool unlock(String pin) {
    if (pin != _pin) return false;
    _isLocked = false;
    _resetIdleTimer();
    notifyListeners();
    return true;
  }

  bool changePin({required String currentPin, required String newPin}) {
    if (currentPin != _pin || !_isValidPin(newPin)) return false;
    _pin = newPin;
    notifyListeners();
    return true;
  }

  bool resetPinWithOtp({required String otp, required String newPin}) {
    // Demo OTP gate for forgot-pin flow until backend OTP verifier is wired.
    if (otp.trim() != '123456' || !_isValidPin(newPin)) return false;
    _pin = newPin;
    killAllSessions();
    return true;
  }

  bool _isValidPin(String pin) {
    final regex = RegExp(r'^\d{4}$');
    return regex.hasMatch(pin);
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_lockTimeout, lockNow);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
