import 'package:flutter/widgets.dart';

import 'trading_store.dart';

class TradingScope extends InheritedNotifier<TradingStore> {
  const TradingScope({
    super.key,
    required TradingStore super.notifier,
    required super.child,
  });

  static TradingStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TradingScope>();
    assert(scope != null, 'TradingScope is not available in this context.');
    return scope!.notifier!;
  }
}
