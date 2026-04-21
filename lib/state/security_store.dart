import 'dart:async';

import 'package:flutter/widgets.dart';

class SecurityStore extends ChangeNotifier {
  SecurityStore({Duration? lockTimeout}) : _lockTimeout = lockTimeout ?? const Duration(minutes: 5);

  final Duration _lockTimeout;

  String _pin = '1234';
  bool _isLocked = false;
  DateTime? _pausedAt;
  Timer? _idleTimer;

  bool get isLocked => _isLocked;
  Duration get lockTimeout => _lockTimeout;

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

    if (pausedAt == null) {
      return;
    }

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
    if (_isLocked) {
      return;
    }
    _isLocked = true;
    _idleTimer?.cancel();
    notifyListeners();
  }

  bool unlock(String pin) {
    if (pin != _pin) {
      return false;
    }

    _isLocked = false;
    _resetIdleTimer();
    notifyListeners();
    return true;
  }

  bool changePin({required String currentPin, required String newPin}) {
    if (currentPin != _pin || !_isValidPin(newPin)) {
      return false;
    }

    _pin = newPin;
    notifyListeners();
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
