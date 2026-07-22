import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/pricing/price_provider.dart';
import '../../state/trading_store.dart';

/// PriceProvider backed by [TradingStore]'s per-symbol [ValueNotifier]s.
///
/// Routes order-form price subscriptions through the existing LiveMarketService
/// connection instead of opening a second WebSocket to the same endpoint.
class TradingStorePriceProvider implements PriceProvider {
  TradingStorePriceProvider(this._store);

  final TradingStore _store;
  final Map<String, _SymbolStream> _streams = {};

  @override
  Stream<double> getPrice(String stock) {
    final symbol = stock.trim().toUpperCase();
    return _streams.putIfAbsent(symbol, () => _SymbolStream(_store, symbol)).stream;
  }

  void dispose() {
    for (final s in _streams.values) {
      s.dispose();
    }
    _streams.clear();
  }
}

class _SymbolStream {
  _SymbolStream(TradingStore store, String symbol) {
    _notifier = store.ltpNotifier(symbol);
    _ctrl = StreamController<double>.broadcast(
      onListen: _attach,
      onCancel: _detach,
    );
  }

  late final StreamController<double> _ctrl;
  late final ValueNotifier<double> _notifier;

  Stream<double> get stream => _ctrl.stream;

  void _attach() {
    _notifier.addListener(_onPrice);
    // Emit current value immediately so the order form has a price on open.
    final current = _notifier.value;
    if (current > 0 && !_ctrl.isClosed) _ctrl.add(current);
  }

  void _detach() {
    _notifier.removeListener(_onPrice);
  }

  void _onPrice() {
    final ltp = _notifier.value;
    if (ltp > 0 && !_ctrl.isClosed) _ctrl.add(ltp);
  }

  void dispose() {
    _notifier.removeListener(_onPrice);
    _ctrl.close();
  }
}
