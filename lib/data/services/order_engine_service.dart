import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/pricing/price_provider.dart';
import 'trading_service.dart';

/// A basic client-side order engine for demonstration.
/// In a production system, this logic would run in a trusted backend environment (e.g., Cloud Functions).
class OrderEngineService {
  final TradingService _tradingService;
  final FirebaseFirestore _firestore;
  final PriceProvider _priceProvider;

  final Map<String, StreamSubscription> _priceSubscriptions = {};
  StreamSubscription? _pendingOrdersSubscription;
  StreamSubscription? _gttOrdersSubscription;

  OrderEngineService({
    required TradingService tradingService,
    required FirebaseFirestore firestore,
    required PriceProvider priceProvider,
  }) : _tradingService = tradingService,
       _firestore = firestore,
       _priceProvider = priceProvider;

  void start() {
    _pendingOrdersSubscription = _firestore
        .collection('orders')
        .where('status', isEqualTo: 'PENDING')
        .snapshots()
        .listen((_) => _recalculateWatchedStocks());

    _gttOrdersSubscription = _firestore
        .collection('gtt_orders')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((_) => _recalculateWatchedStocks());
  }

  void stop() {
    _pendingOrdersSubscription?.cancel();
    _gttOrdersSubscription?.cancel();
    for (var sub in _priceSubscriptions.values) {
      sub.cancel();
    }
    _priceSubscriptions.clear();
  }

  // Cache to store the latest pending orders and GTTs to avoid heavy fetching on every price tick
  final Map<String, List<Map<String, dynamic>>> _pendingOrdersCache = {};
  final Map<String, List<Map<String, dynamic>>> _gttOrdersCache = {};

  void _recalculateWatchedStocks() async {
    final stocksToWatch = <String>{};

    final pendingSnap = await _firestore
        .collection('orders')
        .where('status', isEqualTo: 'PENDING')
        .get();

    _pendingOrdersCache.clear();
    for (var doc in pendingSnap.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      final stock = data['stock'] as String;
      stocksToWatch.add(stock);
      _pendingOrdersCache.putIfAbsent(stock, () => []).add(data);
    }

    final gttSnap = await _firestore
        .collection('gtt_orders')
        .where('isActive', isEqualTo: true)
        .get();

    _gttOrdersCache.clear();
    for (var doc in gttSnap.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      final symbol = data['symbol'] as String;
      stocksToWatch.add(symbol);
      _gttOrdersCache.putIfAbsent(symbol, () => []).add(data);
    }

    // Remove subscriptions for stocks no longer needed
    final currentStocks = _priceSubscriptions.keys.toList();
    for (var stock in currentStocks) {
      if (!stocksToWatch.contains(stock)) {
        _priceSubscriptions.remove(stock)?.cancel();
      }
    }

    // Add subscriptions for new stocks
    for (var stock in stocksToWatch) {
      if (!_priceSubscriptions.containsKey(stock)) {
        _priceSubscriptions[stock] =
            _priceProvider.getPrice(stock).listen((price) {
          _checkOrdersForStock(stock, price);
        });
      }
    }
  }


  // Map to track processing state to avoid duplicate triggers while a transaction is in flight
  final Set<String> _processingOrders = {};

  void _checkOrdersForStock(String stock, double currentPrice) async {
    try {
      // 1. Check Pending Orders from cache
      final pendingOrders = _pendingOrdersCache[stock] ?? [];
      for (var order in pendingOrders) {
        final orderId = order['id'] as String;
        if (_processingOrders.contains(orderId)) continue;

        _processingOrders.add(orderId);
        try {
          await _tradingService.processPendingOrder(orderId, currentPrice);
        } catch (e) {
          // One failed order doesn't stop others
        } finally {
          _processingOrders.remove(orderId);
        }
      }

      // 2. Check GTT Orders from cache
      final gttOrders = _gttOrdersCache[stock] ?? [];
      for (var gtt in gttOrders) {
        final gttId = gtt['id'] as String;
        if (_processingOrders.contains(gttId)) continue;

        _processingOrders.add(gttId);
        try {
          await _tradingService.processGttTrigger(gttId, currentPrice);
        } catch (e) {
          // Inner catch
        } finally {
          _processingOrders.remove(gttId);
        }
      }
    } catch (e) {
      // Prevents crash
    }
  }
}
