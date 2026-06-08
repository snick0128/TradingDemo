import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence layer using SharedPreferences.
///
/// Used as L3 fallback cache so screens can render stale-but-valid data
/// immediately while fresh data loads from the network. Data is stored as
/// JSON strings under namespaced keys.
///
/// Key categories:
///   prices.*     — last-known LTP map (symbol → price)
///   portfolio.*  — last-known holdings / positions snapshot
///   watchlist.*  — user's saved watchlist symbols
///   orders.*     — last-known open orders list
class PersistenceService {
  PersistenceService._();

  static final instance = PersistenceService._();

  SharedPreferences? _prefs;

  static const _keyPrices     = 'prices.ltp_map';
  static const _keyPortfolio  = 'portfolio.snapshot';
  static const _keyWatchlist  = 'watchlist.symbols';
  static const _keyOrders     = 'orders.open_list';
  static const _keyBalanceTs  = 'balance.last_ts';

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    assert(_prefs != null, 'PersistenceService.init() must be awaited first');
    return _prefs!;
  }

  // ── Prices ───────────────────────────────────────────────────────────────────

  /// Save symbol → ltp map. Called after every market snapshot / tick flush.
  Future<void> savePrices(Map<String, double> prices) async {
    try {
      final encoded = jsonEncode(prices.map((k, v) => MapEntry(k, v)));
      await _p.setString(_keyPrices, encoded);
    } catch (_) {}
  }

  /// Returns last-saved symbol → ltp map, or empty map on error.
  Map<String, double> loadPrices() {
    try {
      final raw = _p.getString(_keyPrices);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  // ── Portfolio snapshot ────────────────────────────────────────────────────────

  /// Save the current holdings/positions list as a JSON snapshot.
  Future<void> savePortfolio(List<Map<String, dynamic>> items) async {
    try {
      await _p.setString(_keyPortfolio, jsonEncode(items));
    } catch (_) {}
  }

  /// Returns last-saved portfolio list (may be empty on first launch).
  List<Map<String, dynamic>> loadPortfolio() {
    try {
      final raw = _p.getString(_keyPortfolio);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── Watchlist ─────────────────────────────────────────────────────────────────

  Future<void> saveWatchlist(List<String> symbols) async {
    try {
      await _p.setStringList(_keyWatchlist, symbols);
    } catch (_) {}
  }

  List<String> loadWatchlist() {
    try {
      return _p.getStringList(_keyWatchlist) ?? [];
    } catch (_) {
      return [];
    }
  }

  // ── Open orders ───────────────────────────────────────────────────────────────

  Future<void> saveOpenOrders(List<Map<String, dynamic>> orders) async {
    try {
      await _p.setString(_keyOrders, jsonEncode(orders));
    } catch (_) {}
  }

  List<Map<String, dynamic>> loadOpenOrders() {
    try {
      final raw = _p.getString(_keyOrders);
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── Balance timestamp (for stale-data detection) ──────────────────────────────

  Future<void> saveBalanceTimestamp(int epochMs) async {
    try {
      await _p.setInt(_keyBalanceTs, epochMs);
    } catch (_) {}
  }

  int loadBalanceTimestamp() {
    return _p.getInt(_keyBalanceTs) ?? 0;
  }

  // ── Generic helpers ───────────────────────────────────────────────────────────

  Future<void> setJson(String key, Object value) async {
    try {
      await _p.setString(key, jsonEncode(value));
    } catch (_) {}
  }

  T? getJson<T>(String key) {
    try {
      final raw = _p.getString(key);
      if (raw == null) return null;
      return jsonDecode(raw) as T?;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    try {
      await _p.remove(key);
    } catch (_) {}
  }
}
