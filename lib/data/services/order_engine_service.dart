import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/pricing/price_provider.dart';
import 'trading_service.dart';

/// Admin-side order engine.
///
/// Responsibilities:
///   1. Process queued `order_requests` in near real-time (claim-and-process).
///   2. Monitor PENDING orders and execute them when price conditions are met.
///   3. Monitor active GTT orders and trigger them when price conditions are met.
///
/// This service runs exclusively in the admin app (main_admin.dart).
/// It never runs in the customer app.
class OrderEngineService {
  final TradingService _tradingService;
  final FirebaseFirestore _firestore;
  final PriceProvider _priceProvider;

  // ── Subscriptions ──────────────────────────────────────────────────────────
  final Map<String, StreamSubscription<double>> _priceSubscriptions = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderRequestsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingOrdersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _gttOrdersSub;

  // ── Processing state ───────────────────────────────────────────────────────
  bool _running = false;
  final String _processorId;

  /// Tracks in-flight request IDs to prevent double-processing.
  /// Each entry is auto-evicted after [_inFlightTimeout] to prevent
  /// permanent stalls if a processing task hangs or crashes.
  final Map<String, Timer> _inFlight = {};
  static const _inFlightTimeout = Duration(seconds: 45);

  OrderEngineService({
    required TradingService tradingService,
    required FirebaseFirestore firestore,
    required PriceProvider priceProvider,
    String processorId = 'ADMIN_ENGINE',
  }) : _tradingService = tradingService,
       _firestore = firestore,
       _priceProvider = priceProvider,
       _processorId = processorId;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void start() {
    if (_running) return;
    _running = true;

    print('[OrderEngine] Starting engine (ID: $_processorId)');
    // 1. Process queued order_requests in near real-time
    _orderRequestsSub = _firestore
        .collection('order_requests')
        .where('status', isEqualTo: 'QUEUED')
        .snapshots()
        .listen(_onQueuedRequests, onError: _onStreamError);

    // 2. Monitor PENDING orders (LIMIT, SL, SL-M, AMO) for price triggers
    _pendingOrdersSub = _firestore
        .collection('orders')
        .where('status', whereIn: const ['PENDING', 'PARTIALLY_EXECUTED'])
        .snapshots()
        .listen((_) => _recalculateWatchedStocks(), onError: _onStreamError);

    // 3. Monitor active GTT orders
    _gttOrdersSub = _firestore
        .collection('gtt_orders')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((_) => _recalculateWatchedStocks(), onError: _onStreamError);
  }

  void stop() {
    print('[OrderEngine] Stopping engine');
    _running = false;
    _orderRequestsSub?.cancel();
    _pendingOrdersSub?.cancel();
    _gttOrdersSub?.cancel();
    for (final sub in _priceSubscriptions.values) {
      sub.cancel();
    }
    _priceSubscriptions.clear();
    // Cancel all in-flight timeout timers
    for (final timer in _inFlight.values) {
      timer.cancel();
    }
    _inFlight.clear();
    _orderRequestsSub = null;
    _pendingOrdersSub = null;
    _gttOrdersSub = null;
  }

  // ── Order Request Processing ───────────────────────────────────────────────

  /// Called whenever the `order_requests` QUEUED snapshot changes.
  /// Processes each new QUEUED request exactly once (claim-and-process).
  void _onQueuedRequests(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isNotEmpty) {
      print('[OrderEngine] Received ${snapshot.docs.length} queued requests');
    }
    for (final doc in snapshot.docs) {
      final requestId = doc.id;
      if (_inFlight.containsKey(requestId)) continue;

      print('[OrderEngine] Picked up request: $requestId');
      // Register with a timeout timer — auto-evicts if processing hangs
      _inFlight[requestId] = Timer(_inFlightTimeout, () {
        print(
          '[OrderEngine] Request $requestId timed out in-flight, removing from guard',
        );
        _inFlight.remove(requestId);
      });
      _processRequest(requestId);
    }
  }

  Future<void> _processRequest(String requestId) async {
    try {
      await _tradingService.processOrderRequest(
        requestId,
        processorId: _processorId,
      );
    } catch (e) {
      // processOrderRequest handles its own error writing to Firestore.
      // ignore: avoid_print
      print('[OrderEngine] Error processing request $requestId: $e');
    } finally {
      _inFlight.remove(requestId)?.cancel();
    }
  }

  // ── Pending Order / GTT Price Monitoring ──────────────────────────────────

  /// Recalculates which stocks need price subscriptions based on current
  /// PENDING orders and active GTT orders.
  void _recalculateWatchedStocks() async {
    if (!_running) return;

    final stocksToWatch = <String>{};

    try {
      final pendingSnap = await _firestore
          .collection('orders')
          .where('status', whereIn: const ['PENDING', 'PARTIALLY_EXECUTED'])
          .get();
      for (final doc in pendingSnap.docs) {
        final stock = doc.data()['stock'] as String?;
        if (stock != null && stock.isNotEmpty) stocksToWatch.add(stock);
      }

      final gttSnap = await _firestore
          .collection('gtt_orders')
          .where('isActive', isEqualTo: true)
          .get();
      for (final doc in gttSnap.docs) {
        final symbol = doc.data()['symbol'] as String?;
        if (symbol != null && symbol.isNotEmpty) stocksToWatch.add(symbol);
      }
    } catch (_) {
      return; // Firestore error — retry on next snapshot
    }

    // Remove subscriptions for stocks no longer needed
    final currentStocks = _priceSubscriptions.keys.toList();
    for (final stock in currentStocks) {
      if (!stocksToWatch.contains(stock)) {
        _priceSubscriptions.remove(stock)?.cancel();
      }
    }

    // Add subscriptions for new stocks
    for (final stock in stocksToWatch) {
      if (!_priceSubscriptions.containsKey(stock)) {
        print('[OrderEngine] Starting monitor for $stock');
        _priceSubscriptions[stock] = _priceProvider
            .getPrice(stock)
            .listen(
              (price) {
                _checkOrdersForStock(stock, price);
              },
              onError: (e) {
                print('[OrderEngine] Price stream error for $stock: $e');
              },
              cancelOnError: false,
            );
      }
    }
  }

  void _checkOrdersForStock(String stock, double currentPrice) async {
    if (!_running) return;

    // 1. Check PENDING orders (LIMIT, SL, SL-M, AMO)
    try {
      final orderSnap = await _firestore
          .collection('orders')
          .where('stock', isEqualTo: stock)
          .where('status', whereIn: const ['PENDING', 'PARTIALLY_EXECUTED'])
          .get();

      for (final doc in orderSnap.docs) {
        await _tradingService.processPendingOrder(doc.id, currentPrice);
      }
    } catch (_) {
      // Non-fatal — will retry on next price tick
    }

    // 2. Check GTT orders
    try {
      final gttSnap = await _firestore
          .collection('gtt_orders')
          .where('symbol', isEqualTo: stock)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in gttSnap.docs) {
        await _tradingService.processGttTrigger(doc.id, currentPrice);
      }
    } catch (_) {
      // Non-fatal — will retry on next price tick
    }
  }

  void _onStreamError(Object error, StackTrace stack) {
    // ignore: avoid_print
    print('[OrderEngine] Stream error: $error');
  }
}
