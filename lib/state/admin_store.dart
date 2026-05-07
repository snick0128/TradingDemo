import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/services/firestore_service.dart';
import '../data/services/trading_service.dart';
import '../models/trading_models.dart';

class PlatformStats {
  final double dailyVolume;
  final int activeUsers;
  final int totalOrders;
  final double platformRevenue;
  final List<double> volumeHistory;

  const PlatformStats({
    required this.dailyVolume,
    required this.activeUsers,
    required this.totalOrders,
    required this.platformRevenue,
    required this.volumeHistory,
  });
}

class AdminOrderRecord {
  final String id;
  final String userId;
  final String userClientId;
  final String symbol;
  final OrderType type;
  final OrderStatus status;
  final int quantity;
  final double price;
  final DateTime dateTime;
  final String? rejectionReason;

  const AdminOrderRecord({
    required this.id,
    required this.userId,
    required this.userClientId,
    required this.symbol,
    required this.type,
    required this.status,
    required this.quantity,
    required this.price,
    required this.dateTime,
    this.rejectionReason,
  });

  AdminOrderRecord copyWith({
    String? id,
    String? userId,
    String? userClientId,
    String? symbol,
    OrderType? type,
    OrderStatus? status,
    int? quantity,
    double? price,
    DateTime? dateTime,
    String? rejectionReason,
  }) {
    return AdminOrderRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userClientId: userClientId ?? this.userClientId,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      status: status ?? this.status,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      dateTime: dateTime ?? this.dateTime,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}

class AdminStore extends ChangeNotifier {
  AdminStore({
    TradingService? tradingService,
    FirestoreService? firestoreService,
  }) : _tradingService = tradingService,
       _firestoreService = firestoreService,
       _users = <User>[],
       _masterOrderBook = <AdminOrderRecord>[],
       _auditLog = [],
       _stockEnabled = {},   // populated from Firestore stocks collection
       _broadcasts = [];

  final TradingService? _tradingService;
  final FirestoreService? _firestoreService;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _auditSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _broadcastSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _stocksSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _riskLimitsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _stockLeverageSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _configSub;

  List<User> _users;
  List<AdminOrderRecord> _masterOrderBook;
  List<AuditLogEntry> _auditLog;
  final Map<String, bool> _stockEnabled;
  List<AppNotification> _broadcasts;

  bool _maintenanceMode = false;
  bool _globalTradingHalt = false;
  final Map<String, Map<String, double>> _riskLimits = {};
  String _currentAdminId = 'SYSTEM';
  bool _streamsBound = false;

  bool get _isFirebaseMode =>
      _tradingService != null && _firestoreService != null;

  void setCurrentAdminId(String? adminId, {bool isAdmin = false}) {
    _currentAdminId = (adminId == null || adminId.isEmpty) ? 'SYSTEM' : adminId;
    if (!_isFirebaseMode || !isAdmin) {
      _unbindFirebaseStreams();
      return;
    }
    _bindFirebaseStreams();
  }

  UnmodifiableListView<User> get users => UnmodifiableListView(_users);
  UnmodifiableListView<AdminOrderRecord> get masterOrderBook =>
      UnmodifiableListView(_masterOrderBook);
  UnmodifiableListView<AuditLogEntry> get auditLog =>
      UnmodifiableListView(_auditLog);
  UnmodifiableListView<AppNotification> get broadcasts =>
      UnmodifiableListView(_broadcasts);
  bool get maintenanceMode => _maintenanceMode;
  bool get globalTradingHalt => _globalTradingHalt;

  UnmodifiableListView<AuditLogEntry> get auditLogs => auditLog;

  int get totalUsers => _users.length;
  int get activeSessions => _users.where((u) => u.isActive).length;
  int get totalOrders => _masterOrderBook.length;
  double get totalVolume => _masterOrderBook.fold<double>(
    0.0,
    (total, o) => total + (o.quantity * o.price),
  );
  double get platformPnl => totalVolume * 0.0008;
  double get revenue => totalVolume * 0.00025;

  PlatformStats get stats => PlatformStats(
    dailyVolume: totalVolume,
    activeUsers: activeSessions,
    totalOrders: totalOrders,
    platformRevenue: revenue,
    volumeHistory: _volumeHistory(),
  );

  bool isStockEnabled(String symbol) => _stockEnabled[symbol] ?? true;

  void enableUser(String userId) {
    _setUserActiveLocal(userId, true);
    _logAction('SYSTEM', 'Enable User', userId);
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _tradingService!.setTradingEnabled(
          adminId: _currentAdminId,
          userId: userId,
          enabled: true,
        ),
        onError: (e) => _notifyError('Failed to enable user: $e'),
      );
    }
  }

  void disableUser(String userId) {
    _setUserActiveLocal(userId, false);
    _logAction('SYSTEM', 'Disable User', userId);
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _tradingService!.setTradingEnabled(
          adminId: _currentAdminId,
          userId: userId,
          enabled: false,
        ),
        onError: (e) => _notifyError('Failed to disable user: $e'),
      );
    }
  }

  void adjustUserBalance(String userId, double amount) {
    if (amount == 0) return;
    final index = _users.indexWhere((u) => u.id == userId);
    if (index < 0) return;

    if (_isFirebaseMode) {
      // In Firebase mode, do NOT update local state optimistically.
      // The Firestore stream will update it once the transaction commits.
      _fireAndForget(
        () => _tradingService!.addBalance(
          adminId: _currentAdminId,
          userId: userId,
          amount: amount,
        ),
        onError: (e) => _notifyError('Failed to adjust balance: $e'),
      );
    } else {
      _users[index] = _users[index].copyWith(
        balance: _users[index].balance + amount,
      );
      _logAction('SYSTEM', 'Adjust User Balance', '$userId: $amount');
      notifyListeners();
    }
  }

  void adjustUserMargin(String userId, double amount) {
    final index = _users.indexWhere((u) => u.id == userId);
    if (index < 0 || amount == 0) return;

    _users[index] = _users[index].copyWith(
      marginLimit: _users[index].marginLimit + amount,
    );
    _logAction('SYSTEM', 'Adjust User Margin', '$userId: $amount');
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.updateDocument('users/$userId', {
          'marginLimit': _users[index].marginLimit,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to adjust margin: $e'),
      );
    }
  }

  void enableStock(String symbol) {
    _stockEnabled[symbol] = true;
    _logAction('SYSTEM', 'Enable Stock', symbol);
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.setDocument('stocks/$symbol', {
          'symbol': symbol,
          'tradable': true,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to enable stock: $e'),
      );
    }
  }

  void disableStock(String symbol) {
    _stockEnabled[symbol] = false;
    _logAction('SYSTEM', 'Disable Stock', symbol);
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.setDocument('stocks/$symbol', {
          'symbol': symbol,
          'tradable': false,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to disable stock: $e'),
      );
    }
  }

  Future<void> approveOrder(String orderId) async {
    // approveOrder is removed — system uses auto-execution model.
    // Orders are executed atomically at placement time; there is no
    // pending → approved workflow. This method is a no-op to avoid
    // breaking callers during migration.
    final index = _masterOrderBook.indexWhere((o) => o.id == orderId);
    if (index >= 0) {
      _masterOrderBook[index] = _masterOrderBook[index].copyWith(
        status: OrderStatus.approved,
        rejectionReason: null,
      );
      notifyListeners();
    }
    _logAction('SYSTEM', 'Approve Order (local only)', orderId);
  }

  Future<void> rejectOrder(String orderId, {String? reason}) async {
    // rejectOrder is removed — system uses auto-execution model.
    // This method updates local state only for UI consistency.
    final index = _masterOrderBook.indexWhere((o) => o.id == orderId);
    if (index >= 0) {
      _masterOrderBook[index] = _masterOrderBook[index].copyWith(
        status: OrderStatus.rejected,
        rejectionReason: reason,
      );
      notifyListeners();
    }
    _logAction('SYSTEM', 'Reject Order (local only)', '$orderId ${reason ?? ''}'.trim());
  }

  void broadcastNotification({
    required String title,
    required String message,
    AlertType type = AlertType.news,
  }) {
    final notification = AppNotification(
      id: 'BCAST-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: message,
      timestamp: DateTime.now(),
      relatedAlertType: type,
    );
    _broadcasts.insert(0, notification);
    _logAction('SYSTEM', 'Broadcast Notification', title);
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.addDocument('notifications', {
          'title': title,
          'message': message,
          'type': _alertTypeToDb(type),
          'createdBy': _currentAdminId,
          'createdAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to broadcast notification: $e'),
      );
    }
  }

  void toggleMaintenanceMode() {
    _maintenanceMode = !_maintenanceMode;
    _logAction('SYSTEM', 'Maintenance Mode', _maintenanceMode ? 'ON' : 'OFF');
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.setDocument('admin_config/platform', {
          'maintenanceMode': _maintenanceMode,
          'updatedBy': _currentAdminId,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to toggle maintenance mode: $e'),
      );
    }
  }

  void setRiskLimit(String userId, String limitType, double value) {
    _riskLimits[userId] ??= {};
    _riskLimits[userId]![limitType] = value;
    _logAction('SYSTEM', 'Set Risk Limit', '$userId: $limitType=$value');
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.setDocument('risk_limits/$userId', {
          limitType: value,
          'updatedBy': _currentAdminId,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to set risk limit: $e'),
      );
    }
  }

  double? getRiskLimit(String userId, String limitType) =>
      _riskLimits[userId]?[limitType];

  // ── Per-stock leverage (platform-wide, not per-user) ──────────────────────
  // Stored in Firestore: stock_leverage/{symbol} → { leverage: N, updatedBy, updatedAt }
  // In-memory: _stockLeverage map

  final Map<String, double> _stockLeverage = {};

  /// Get the platform leverage for a symbol (null = use platform default/max).
  double? getStockLeverage(String symbol) => _stockLeverage[symbol.toUpperCase()];

  /// Set leverage for multiple symbols at once.
  /// [leverages] map: symbol → leverage multiplier (e.g. 'GOLD' → 100.0)
  /// Pass an empty map or omit a symbol to reset it to default.
  void setStockLeverages(Map<String, double> leverages) {
    // Update in-memory
    _stockLeverage.clear();
    _stockLeverage.addAll({
      for (final e in leverages.entries)
        e.key.toUpperCase(): e.value,
    });
    _logAction(
      _currentAdminId,
      'SET_STOCK_LEVERAGE',
      leverages.entries.map((e) => '${e.key}=${e.value}x').join(', '),
    );
    notifyListeners();

    if (_isFirebaseMode) {
      // Write each symbol's leverage as a separate doc for granular reads
      for (final entry in leverages.entries) {
        final symbol = entry.key.toUpperCase();
        _fireAndForget(
          () => _firestoreService!.setDocument('stock_leverage/$symbol', {
            'symbol': symbol,
            'leverage': entry.value,
            'updatedBy': _currentAdminId,
            'updatedAt': Timestamp.now(),
          }),
          onError: (e) => _notifyError('Failed to set leverage for $symbol: $e'),
        );
      }
    }
  }

  /// Set per-segment leverage for a user.
  /// [segmentLeverages] is a map of segment key → leverage value,
  /// e.g. { 'mcxFutures': 500.0, 'nseFutures': 500.0, ... }
  void setUserSegmentLeverages(String userId, Map<String, double> segmentLeverages) {
    _riskLimits[userId] ??= {};
    for (final entry in segmentLeverages.entries) {
      _riskLimits[userId]!['lev_${entry.key}'] = entry.value;
    }
    _logAction(_currentAdminId, 'SET_LEVERAGE',
        '$userId: ${segmentLeverages.entries.map((e) => '${e.key}=${e.value}x').join(', ')}');
    notifyListeners();

    if (_isFirebaseMode) {
      final data = <String, dynamic>{
        for (final e in segmentLeverages.entries) 'lev_${e.key}': e.value,
        'updatedBy': _currentAdminId,
        'updatedAt': Timestamp.now(),
      };
      _fireAndForget(
        () => _firestoreService!.setDocument('risk_limits/$userId', data),
        onError: (e) => _notifyError('Failed to set leverage: $e'),
      );
    }
  }

  /// Get leverage for a specific segment key for a user.
  double? getSegmentLeverage(String userId, String segmentKey) =>
      _riskLimits[userId]?['lev_$segmentKey'];

  /// Get all segment leverages for a user as a map.
  Map<String, double> getAllSegmentLeverages(String userId) {
    final limits = _riskLimits[userId] ?? {};
    return {
      for (final entry in limits.entries)
        if (entry.key.startsWith('lev_'))
          entry.key.substring(4): entry.value,
    };
  }

  void toggleGlobalTradingHalt(bool halt) {
    _globalTradingHalt = halt;
    _logAction('SYSTEM', 'Global Trading Halt', halt ? 'ENABLED' : 'DISABLED');
    notifyListeners();

    if (_isFirebaseMode) {
      _fireAndForget(
        () => _firestoreService!.setDocument('admin_config/platform', {
          'globalTradingHalt': halt,
          'updatedBy': _currentAdminId,
          'updatedAt': Timestamp.now(),
        }),
        onError: (e) => _notifyError('Failed to toggle trading halt: $e'),
      );
    }
  }

  void forceClosePosition(String userId, String positionId) {
    _logAction('SYSTEM', 'Force Close Position', '$userId / $positionId');
    notifyListeners();
  }

  void forceCloseAllPositions(String userId) {
    _logAction('SYSTEM', 'Force Close All Positions', userId);
    notifyListeners();
  }

  void toggleUserStatus(String userId) {
    final user = _users.cast<User?>().firstWhere(
      (u) => u?.id == userId,
      orElse: () => null,
    );
    if (user == null) return;
    if (user.isActive) {
      disableUser(userId);
    } else {
      enableUser(userId);
    }
  }

  void _bindFirebaseStreams() {
    if (_streamsBound) return;
    final tradingService = _tradingService;
    final firestoreService = _firestoreService;
    if (tradingService == null || firestoreService == null) return;
    _streamsBound = true;

    // Paginated — limit prevents full-collection downloads as platform grows
    _usersSub = tradingService.usersStream().listen((snapshot) {
      _users = snapshot.docs.map(_mapUserDoc).toList()
        ..sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
      notifyListeners();
    }, onError: (e, _) => _notifyError('Users stream error: $e'));

    _ordersSub = tradingService.ordersStream().listen((snapshot) {
      _masterOrderBook = snapshot.docs.map(_mapOrderDoc).toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      notifyListeners();
    }, onError: (e, _) => _notifyError('Orders stream error: $e'));

    _auditSub = firestoreService.raw
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      _auditLog = snapshot.docs.map(_mapAuditDoc).toList();
      notifyListeners();
    }, onError: (e, _) => _notifyError('Audit log stream error: $e'));

    _broadcastSub = firestoreService.raw
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      _broadcasts = snapshot.docs.map(_mapNotificationDoc).toList();
      notifyListeners();
    }, onError: (e, _) => _notifyError('Notifications stream error: $e'));

    _stocksSub = firestoreService.getCollectionStream('stocks').listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final symbol = (data['symbol'] as String?) ?? doc.id;
        final tradable = (data['tradable'] as bool?) ?? true;
        _stockEnabled[symbol] = tradable;
      }
      notifyListeners();
    }, onError: (e, _) => _notifyError('Stocks stream error: $e'));

    _riskLimitsSub = firestoreService
        .getCollectionStream('risk_limits')
        .listen((snapshot) {
      _riskLimits
        ..clear()
        ..addAll({
          for (final doc in snapshot.docs)
            doc.id: {
              for (final entry in doc.data().entries)
                if (entry.value is num &&
                    entry.key != 'updatedAt' &&
                    entry.key != 'updatedBy')
                  entry.key: (entry.value as num).toDouble(),
            },
        });
      notifyListeners();
    }, onError: (e, _) => _notifyError('Risk limits stream error: $e'));

    // Per-stock leverage stream
    _stockLeverageSub = firestoreService
        .getCollectionStream('stock_leverage')
        .listen((snapshot) {
      _stockLeverage.clear();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final symbol = ((data['symbol'] as String?) ?? doc.id).toUpperCase();
        final lev = (data['leverage'] as num?)?.toDouble();
        if (lev != null && lev > 0) _stockLeverage[symbol] = lev;
      }
      notifyListeners();
    }, onError: (e, _) => _notifyError('Stock leverage stream error: $e'));

    _configSub = firestoreService
        .raw
        .doc('admin_config/platform')
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      _maintenanceMode = (data['maintenanceMode'] as bool?) ?? _maintenanceMode;
      _globalTradingHalt =
          (data['globalTradingHalt'] as bool?) ?? _globalTradingHalt;
      notifyListeners();
    }, onError: (e, _) => _notifyError('Platform config stream error: $e'));
  }

  void _unbindFirebaseStreams() {
    _usersSub?.cancel();
    _ordersSub?.cancel();
    _auditSub?.cancel();
    _broadcastSub?.cancel();
    _stocksSub?.cancel();
    _riskLimitsSub?.cancel();
    _stockLeverageSub?.cancel();
    _configSub?.cancel();

    _usersSub = null;
    _ordersSub = null;
    _auditSub = null;
    _broadcastSub = null;
    _stocksSub = null;
    _riskLimitsSub = null;
    _stockLeverageSub = null;
    _configSub = null;
    _streamsBound = false;
  }

  User _mapUserDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final email = (data['email'] as String?) ?? '';
    final emailPrefix = email.split('@').first.trim();
    final uidPrefix = doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length);

    return User(
      id: doc.id,
      clientId: (data['clientId'] as String?) ??
          (emailPrefix.isNotEmpty ? emailPrefix : uidPrefix),
      name: (data['name'] as String?) ?? 'User',
      email: email,
      isActive: (data['tradingEnabled'] as bool?) ?? true,
      balance: ((data['balance'] as num?) ?? 0).toDouble(),
      marginLimit: ((data['marginLimit'] as num?) ?? 0).toDouble(),
      registeredAt: _asDate(data['createdAt']),
      lastLoginAt: _asNullableDate(data['lastLoginAt']),
      brokeragePlan: (data['brokeragePlan'] as String?) ?? 'Standard',
      isAdmin: (data['role'] as String?) == 'admin',
    );
  }

  AdminOrderRecord _mapOrderDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final userId = (data['userId'] as String?) ?? 'unknown';
    final fallbackClientId = userId.substring(0, userId.length > 8 ? 8 : userId.length);

    final userClientId = _users.cast<User?>().firstWhere(
          (u) => u?.id == userId,
          orElse: () => null,
        )?.clientId ??
        fallbackClientId;

    return AdminOrderRecord(
      id: doc.id,
      userId: userId,
      userClientId: userClientId,
      symbol: (data['stock'] as String?) ?? 'N/A',
      type: _orderTypeFromDb(data['type'] as String?),
      status: _orderStatusFromDb(data['status'] as String?),
      quantity: ((data['qty'] as num?) ?? 0).toInt(),
      price: ((data['fillPrice'] as num?) ?? (data['price'] as num?) ?? 0)
          .toDouble(),
      dateTime: _asDate(data['createdAt'] ?? data['updatedAt']),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  AuditLogEntry _mapAuditDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AuditLogEntry(
      id: doc.id,
      adminId: (data['adminId'] as String?) ?? 'SYSTEM',
      action: (data['action'] as String?) ?? 'UNKNOWN',
      targetId: (data['targetId'] as String?) ?? 'N/A',
      timestamp: _asDate(data['timestamp']),
      metadata: (data['metadata'] as Map<String, dynamic>?),
    );
  }

  AppNotification _mapNotificationDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final type = _alertTypeFromDb(data['type'] as String?);

    return AppNotification(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Broadcast',
      message: (data['message'] as String?) ?? '',
      timestamp: _asDate(data['createdAt']),
      relatedAlertType: type,
      isRead: false,
    );
  }

  DateTime _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  DateTime? _asNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  OrderType _orderTypeFromDb(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    return value == 'SELL' ? OrderType.sell : OrderType.buy;
  }

  OrderStatus _orderStatusFromDb(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
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
      case 'PENDING':
      default:
        return OrderStatus.pending;
    }
  }

  AlertType _alertTypeFromDb(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'WARNING':
        return AlertType.marginWarning;
      case 'MAINTENANCE':
        return AlertType.autoSquareOffWarning;
      case 'ALERT':
        return AlertType.news;
      case 'BROADCAST':
      case 'INFO':
      default:
        return AlertType.news;
    }
  }

  String _alertTypeToDb(AlertType type) {
    switch (type) {
      case AlertType.marginWarning:
        return 'WARNING';
      case AlertType.autoSquareOffWarning:
        return 'MAINTENANCE';
      case AlertType.news:
      default:
        return 'INFO';
    }
  }

  void _setUserActiveLocal(String userId, bool isActive) {
    final index = _users.indexWhere((u) => u.id == userId);
    if (index < 0) return;
    _users[index] = _users[index].copyWith(isActive: isActive);
  }

  void _logAction(String adminId, String action, String targetId) {
    _auditLog.insert(
      0,
      AuditLogEntry(
        id: 'LOG-${DateTime.now().millisecondsSinceEpoch}',
        adminId: adminId,
        action: action,
        targetId: targetId,
        timestamp: DateTime.now(),
      ),
    );
  }

  List<double> _volumeHistory() {
    final base = totalVolume / 10000000;
    return List<double>.generate(7, (i) {
      final wave = (i.isEven ? 0.85 : 1.15);
      return (base * wave) + i * 0.18;
    });
  }

  /// Fires an async action without awaiting it.
  /// Errors are surfaced via [onError] — never silently swallowed.
  void _fireAndForget(
    Future<void> Function() action, {
    required void Function(Object error) onError,
  }) {
    action().catchError((Object e) => onError(e));
  }

  /// Last error message for the UI to display (e.g. via a listener).
  String? _lastError;
  String? get lastError => _lastError;

  void _notifyError(String message) {
    _lastError = message;
    notifyListeners();
    // Auto-clear after 5 seconds so the UI doesn't show stale errors
    Future.delayed(const Duration(seconds: 5), () {
      if (_lastError == message) {
        _lastError = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _unbindFirebaseStreams();
    super.dispose();
  }
}
