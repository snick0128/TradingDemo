import 'package:flutter/widgets.dart';

import 'trading_store.dart';

class TradingScope extends InheritedNotifier<TradingStore> {
  const TradingScope({
    super.key,
    required TradingStore super.notifier,
    required super.child,
  });

  /// Dependency-tracking read.
  ///
  /// Registers the calling element as a dependent of [TradingScope].
  /// The widget WILL rebuild on every [TradingStore.notifyListeners] call.
  ///
  /// Use ONLY in widgets whose entire UI must respond to every store change
  /// (e.g. watchlist screen where every row must repaint on each tick).
  /// For screens that manage their own listener via addListener(), use [read].
  static TradingStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TradingScope>();
    assert(scope != null, 'TradingScope is not available in this context.');
    return scope!.notifier!;
  }

  /// Non-tracking read — does NOT register a rebuild dependency.
  ///
  /// The widget will NOT rebuild automatically when the store fires
  /// [notifyListeners].  Use this when you want the store reference
  /// without subscribing to every tick (e.g. detail screens that attach
  /// their own [addListener] callback for targeted updates).
  static TradingStore read(BuildContext context) {
    final scope = context.findAncestorWidgetOfExactType<TradingScope>();
    assert(scope != null, 'TradingScope is not available in this context.');
    return scope!.notifier!;
  }
}
