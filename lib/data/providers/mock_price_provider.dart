import 'dart:async';
import 'dart:math';

import '../../domain/pricing/price_provider.dart';

class MockPriceProvider implements PriceProvider {
  final Random _random = Random();
  final Map<String, StreamController<double>> _controllers = {};
  final Map<String, Timer> _timers = {};
  final Map<String, double> _prices = {};

  @override
  Stream<double> getPrice(String stock) {
    if (_controllers.containsKey(stock)) {
      return _controllers[stock]!.stream;
    }
    final controller = StreamController<double>.broadcast();
    _controllers[stock] = controller;

    _prices[stock] = _seedPrice(stock);
    controller.add(_prices[stock]!);

    _timers[stock] = Timer.periodic(const Duration(seconds: 2), (_) {
      final previous = _prices[stock]!;
      final delta = (previous * 0.003) * (_random.nextDouble() * 2 - 1);
      final next = (previous + delta).clamp(1.0, 1000000.0);
      _prices[stock] = next;
      if (!controller.isClosed) {
        controller.add(next);
      }
    });

    controller.onCancel = () {
      if (!controller.hasListener) {
        _timers.remove(stock)?.cancel();
        _controllers.remove(stock)?.close();
      }
    };
    return controller.stream;
  }

  double _seedPrice(String symbol) {
    final hash = symbol.codeUnits.fold<int>(0, (a, b) => a + b);
    return (50 + (hash % 5000)).toDouble();
  }
}
