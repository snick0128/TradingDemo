import 'package:flutter/foundation.dart';

import '../models/trading_models.dart';
import 'commodity_icon_map.dart';
import 'logo_cache_manager.dart';
import 'logo_resolver.dart';
import 'symbol_parser.dart';

/// Facade over [SymbolParser] + [LogoCacheManager] + [LogoResolver] +
/// [CommodityIconMap] — the single entry point screens/widgets use to
/// resolve an instrument's icon, whether that's a company logo fetched from
/// the network or a bundled MCX commodity asset.
///
/// Call [ensureLoaded] once at app startup (see `PersistenceService.init()`
/// in main.dart for the equivalent pattern); it's also safe to call from
/// [InstrumentLogo] itself since repeated calls reuse the same in-flight
/// load. Listen via [addListener] to rebuild once the mapping arrives —
/// [InstrumentLogo] does this for you.
class InstrumentLogoService extends ChangeNotifier {
  InstrumentLogoService._();

  static final instance = InstrumentLogoService._();

  Map<String, String> _mapping = const {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void>? _initFuture;

  Future<void> ensureLoaded() {
    return _initFuture ??= _load();
  }

  Future<void> _load() async {
    _mapping = await LogoCacheManager.instance.loadMapping();
    _loaded = true;
    notifyListeners();
  }

  static const _excludedTypes = {
    InstrumentType.marketIndex,
    InstrumentType.futuresCom,
    InstrumentType.currency,
  };

  /// Returns the logo URL for [symbol], or null if unresolved, not yet
  /// loaded, or excluded via [instrumentType] (index/commodity/currency).
  /// Synchronous — returns null until [ensureLoaded] completes even when a
  /// mapping ultimately exists for [symbol].
  String? logoUrlForSymbol(
    String symbol, {
    String exchange = 'NSE',
    InstrumentType? instrumentType,
  }) {
    if (!_loaded) return null;
    if (instrumentType != null && _excludedTypes.contains(instrumentType)) {
      return null;
    }
    final ticker = SymbolParser.underlyingOf(symbol);
    return LogoResolver.resolve(
      ticker: ticker,
      exchange: exchange,
      mapping: _mapping,
    );
  }

  String? logoUrlForStock(Stock stock) => logoUrlForSymbol(
        stock.symbol,
        exchange: stock.exchange,
        instrumentType: stock.instrumentType,
      );

  /// Returns a bundled asset path (e.g. "assets/images/gold.png") for MCX
  /// commodity [symbol]s, or null otherwise. Synchronous and independent of
  /// [ensureLoaded] — these are packaged with the app, not fetched.
  String? localAssetForSymbol(String symbol) {
    final ticker = SymbolParser.underlyingOf(symbol);
    return CommodityIconMap.assetFor(ticker);
  }

  String? localAssetForStock(Stock stock) => localAssetForSymbol(stock.symbol);
}
