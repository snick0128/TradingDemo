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
        .listen(_onPendingOrdersUpdate);
  }

  void stop() {
    _pendingOrdersSubscription?.cancel();
    for (var sub in _priceSubscriptions.values) {
      sub.cancel();
    }
    _priceSubscriptions.clear();
  }

  void _onPendingOrdersUpdate(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final stocksToWatch = <String>{};
    for (var doc in snapshot.docs) {
      stocksToWatch.add(doc.data()['stock'] as String);
    }

    // Remove subscriptions for stocks no longer in pending orders
    final currentStocks = _priceSubscriptions.keys.toList();
    for (var stock in currentStocks) {
      if (!stocksToWatch.contains(stock)) {
        _priceSubscriptions.remove(stock)?.cancel();
      }
    }

    // Add subscriptions for new stocks
    for (var stock in stocksToWatch) {
      if (!_priceSubscriptions.containsKey(stock)) {
        _priceSubscriptions[stock] = _priceProvider.getPrice(stock).listen((price) {
          _checkOrdersForStock(stock, price);
        });
      }
    }
  }

  void _checkOrdersForStock(String stock, double currentPrice) async {
    // Fetch pending orders for this stock
    // In production, you'd want to be careful with read volume here.
    final snapshot = await _firestore
        .collection('orders')
        .where('stock', isEqualTo: stock)
        .where('status', isEqualTo: 'PENDING')
        .get();

    for (var doc in snapshot.docs) {
      await _tradingService.processPendingOrder(doc.id, currentPrice);
    }
  }
}
