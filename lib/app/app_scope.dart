import 'package:flutter/widgets.dart';

import '../data/services/auth_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/trading_service.dart';
import '../domain/auth/auth_session.dart';

class AppScope extends InheritedNotifier<AuthSession> {
  const AppScope({
    super.key,
    required super.notifier,
    required this.authService,
    required this.firestoreService,
    required this.tradingService,
    required super.child,
  });

  final AuthService authService;
  final FirestoreService firestoreService;
  final TradingService tradingService;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing in widget tree.');
    return scope!;
  }

  static AuthSession sessionOf(BuildContext context) => of(context).notifier!;
}
