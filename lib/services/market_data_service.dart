import 'dart:async';

import '../models/trading_models.dart';

/// Stub MarketDataService — no longer generates random prices.
///
/// The live backend (LiveMarketService) is the sole price source.
/// This class is kept only because TradingStore still references it
/// for market depth and trade streams (which are not yet wired to the backend).
/// The price update stream never emits — prices come from LiveMarketService.
class MarketDataService {
  final _priceController =
      StreamController<Map<String, double>>.broadcast();
  final _depthControllers = <String, StreamController<MarketDepth>>{};
  final _tradeControllers = <String, StreamController<Trade>>{};

  final Map<String, bool?> _lastDirection = {};

  // No timer — no random walk.
  MarketDataService(Map<String, double> initialPrices);

  Stream<Map<String, double>> get priceUpdates => _priceController.stream;

  Stream<MarketDepth> depthUpdates(String symbol) {
    return _depthControllers
        .putIfAbsent(symbol, () => StreamController<MarketDepth>.broadcast())
        .stream;
  }

  Stream<Trade> tradeUpdates(String symbol) {
    return _tradeControllers
        .putIfAbsent(symbol, () => StreamController<Trade>.broadcast())
        .stream;
  }

  bool? getPriceDirection(String symbol) => _lastDirection[symbol];

  /// Called by TradingStore when live backend emits a price update,
  /// so direction arrows still work.
  void recordDirection(String symbol, double oldPrice, double newPrice) {
    _lastDirection[symbol] = newPrice > oldPrice;
  }

  void dispose() {
    _priceController.close();
    for (final c in _depthControllers.values) c.close();
    for (final c in _tradeControllers.values) c.close();
  }
}
