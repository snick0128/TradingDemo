import 'dart:async';
import 'dart:math';

import '../models/trading_models.dart';

class MarketDataService {
  final _random = Random();
  final _priceController = StreamController<Map<String, double>>.broadcast();
  final _depthControllers = <String, StreamController<MarketDepth>>{};
  final _tradeControllers = <String, StreamController<Trade>>{};

  final Map<String, double> _currentPrices = {};
  final Map<String, double> _initialPrices = {};
  final Map<String, bool?> _lastDirection = {};
  Timer? _timer;

  MarketDataService(Map<String, double> initialPrices) {
    _currentPrices.addAll(initialPrices);
    _initialPrices.addAll(initialPrices);
    _timer = Timer.periodic(const Duration(seconds: 2), _tick);
  }

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

  void _tick(Timer _) {
    final priceUpdates = <String, double>{};

    for (final entry in _currentPrices.entries) {
      final symbol = entry.key;
      final price = entry.value;
      final initial = _initialPrices[symbol]!;

      // Random walk: small factor between -0.005 and +0.005
      final randomFactor = (_random.nextDouble() - 0.5) * 0.01;

      // Mean reversion: nudge 10% back toward initial price
      final deviation = price - initial;
      final reversionFactor = -0.10 * deviation / initial;

      final newPrice = price * (1 + randomFactor + reversionFactor);
      final rounded = double.parse(newPrice.toStringAsFixed(2));

      _lastDirection[symbol] = rounded > price;
      _currentPrices[symbol] = rounded;
      priceUpdates[symbol] = rounded;

      // Push depth update if anyone is listening
      if (_depthControllers.containsKey(symbol)) {
        _depthControllers[symbol]!.add(_generateDepth(symbol, rounded));
      }

      // Push trade update (randomly, not every tick)
      if (_tradeControllers.containsKey(symbol) && _random.nextDouble() > 0.3) {
        _tradeControllers[symbol]!.add(_generateTrade(rounded));
      }
    }

    _priceController.add(priceUpdates);
  }

  MarketDepth _generateDepth(String symbol, double price) {
    return MarketDepth(
      symbol: symbol,
      bids: List.generate(5, (i) {
        return MarketDepthLevel(
          price: double.parse((price - (i + 1) * 0.05).toStringAsFixed(2)),
          quantity: (_random.nextInt(5000) + 100),
          orders: _random.nextInt(50) + 1,
        );
      }),
      asks: List.generate(5, (i) {
        return MarketDepthLevel(
          price: double.parse((price + (i + 1) * 0.05).toStringAsFixed(2)),
          quantity: (_random.nextInt(5000) + 100),
          orders: _random.nextInt(50) + 1,
        );
      }),
      timestamp: DateTime.now(),
    );
  }

  Trade _generateTrade(double price) {
    return Trade(
      time: DateTime.now(),
      price: double.parse(
        (price + (_random.nextDouble() - 0.5) * 0.2).toStringAsFixed(2),
      ),
      quantity: (_random.nextInt(100) + 1) * 5,
      isBuyerInitiated: _random.nextBool(),
    );
  }

  void dispose() {
    _timer?.cancel();
    _priceController.close();
    for (final c in _depthControllers.values) {
      c.close();
    }
    for (final c in _tradeControllers.values) {
      c.close();
    }
  }
}
