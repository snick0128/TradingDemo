import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../config/backend_config.dart';

/// Central HTTP client for the Node.js paper trading backend.
///
/// Base URL is configured via [BackendApiService.baseUrl].
/// For local testing: http://localhost:3000
/// For production:    https://paper-trading-backend-bnn7.onrender.com
///
/// All methods return parsed Maps/Lists — callers convert to domain models.
class BackendApiService {
  BackendApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  /// Default base URL — reads from BackendConfig so it always matches the
  /// configured environment (local or production).
  static String get _defaultBaseUrl => BackendConfig.backendBaseUrl;

  final String baseUrl;

  // ── In-memory cache ─────────────────────────────────────────────────────────

  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<Map<String, dynamic>>> _inFlightGets = {};

  static const _shortTtl = Duration(seconds: 30);
  static const _mediumTtl = Duration(minutes: 2);
  static const _longTtl = Duration(minutes: 5);

  /// Remove all cached responses (e.g. after placing an order).
  static void clearCache() => _cache.clear();

  /// Invalidate all cached paths that start with [prefix].
  static void invalidate(String prefix) =>
      _cache.removeWhere((k, _) => k.startsWith(prefix));

  // ── HTTP helpers ────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> _get(String path, {Duration? ttl}) async {
    final effectiveTtl = ttl ?? _shortTtl;
    final now = DateTime.now();
    final cached = _cache[path];
    if (cached != null && now.isBefore(cached.expiry)) {
      return cached.data;
    }

    final uri = Uri.parse('$baseUrl$path');
    final pending = _inFlightGets[path];
    if (pending != null) return pending;

    print('[BackendAPI] GET: $uri');
    final request = () async {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      print('[BackendAPI] Response: ${response.statusCode} for $path');
      final result = _parse(response);
      _cache[path] = _CacheEntry(data: result, expiry: now.add(effectiveTtl));
      return result;
    }();

    _inFlightGets[path] = request;
    try {
      return await request;
    } on TimeoutException {
      if (cached != null) return cached.data; // serve stale on timeout
      throw BackendException(
        'The request took too long. Please check your connection and try again.',
      );
    } catch (e) {
      if (cached != null) return cached.data; // serve stale on network error
      throw BackendException(
        'Could not reach the server. Please check your connection and try again.',
      );
    } finally {
      _inFlightGets.remove(path);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(
            const Duration(seconds: 30),
          ); // increased from 15s — Render cold starts + Firestore reads
      return _parse(response);
    } on TimeoutException {
      throw BackendException(
        'The request took too long. Please check your connection and try again.',
      );
    } catch (e) {
      throw BackendException(
        'Could not reach the server. Please check your connection and try again.',
      );
    }
  }

  Map<String, dynamic> _parse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw BackendException(
        body['error'] as String? ?? 'Something went wrong. Please try again.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  // ── Health ──────────────────────────────────────────────────────────────────

  // Cache the health ping for 60s — it's purely a warmup call, not live data.
  Future<Map<String, dynamic>> getHealth() =>
      _get('/health', ttl: const Duration(seconds: 60));

  // ── Market data ─────────────────────────────────────────────────────────────

  /// Returns all tracked symbols with LTP, buyPrice, sellPrice, change, changePercent.
  Future<List<Map<String, dynamic>>> getAllMarketData() async {
    final res = await _get('/market');
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Returns LTP + OHLC for a single symbol.
  Future<Map<String, dynamic>> getStockDetail(String symbol) async {
    final res = await _get('/market/stock?symbol=$symbol');
    return res['data'] as Map<String, dynamic>;
  }

  /// Returns top gainers and losers.
  Future<Map<String, dynamic>> getMovers({int limit = 5}) async {
    final res = await _get('/market/movers?limit=$limit');
    return res['data'] as Map<String, dynamic>;
  }

  /// Returns historical OHLCV candles.
  /// [interval]: '1m' | '5m' | '15m' | '30m' | '1h' | '1d'
  /// [exchange] + [token]: required for MCX/NFO/CDS instruments not in the
  /// backend's hardcoded symbol list (e.g. instruments found via universal search)
  Future<List<Map<String, dynamic>>> getHistoricalData(
    String symbol, {
    String interval = '5m',
    String? from,
    String? to,
    String? exchange,
    String? token,
  }) async {
    var path = '/market/historical?symbol=$symbol&interval=$interval';
    if (from != null) path += '&from=${Uri.encodeComponent(from)}';
    if (to != null) path += '&to=${Uri.encodeComponent(to)}';
    // Pass exchange+token so the backend can look up non-standard instruments
    if (exchange != null && exchange.isNotEmpty) {
      path += '&exchange=${Uri.encodeComponent(exchange)}';
    }
    if (token != null && token.isNotEmpty) {
      path += '&token=${Uri.encodeComponent(token)}';
    }
    // Historical candles change infrequently — cache for 5 minutes
    final res = await _get(path, ttl: _longTtl);
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  // ── Orders ──────────────────────────────────────────────────────────────────

  /// Place a simulated BUY or SELL order.
  ///
  // RMS FIX:
  // Bug #2 — productType and exchange never sent to backend
  // Problem: Backend received only {userId, symbol, qty, type}.
  //          Product type (MIS/CNC/NRML) was silently dropped.
  //          Exchange defaulted to 'NSE' even for MCX orders.
  // Solution: Add productType and exchange as required parameters.
  //           Backend now receives full order context for leverage + market check.
  // Migration notes: Backend orderRoutes.js updated to consume these fields.
  Future<Map<String, dynamic>> placeOrder({
    required String userId,
    required String symbol,
    required int qty,
    required String type, // 'BUY' or 'SELL'
    String productType = 'MIS', // 'MIS' | 'CNC' | 'NRML'
    String exchange = 'NSE', // 'NSE' | 'MCX' | 'BSE' etc.
    String? clientRequestId,
  }) async {
    final result = await _post('/orders', {
      'userId': userId,
      'symbol': symbol,
      'qty': qty,
      'type': type,
      'productType': productType,
      'exchange': exchange,
      if (clientRequestId != null) 'clientRequestId': clientRequestId,
    });
    // Invalidate stale portfolio/order caches after a successful order
    invalidate('/orders');
    invalidate('/positions');
    invalidate('/market/stock');
    return result;
  }

  /// Get order history for a user.
  Future<List<Map<String, dynamic>>> getOrderHistory(
    String userId, {
    int limit = 50,
  }) async {
    final res = await _get('/orders/$userId?limit=$limit');
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  // ── Portfolio ───────────────────────────────────────────────────────────────

  /// Get full portfolio with live P&L for a user.
  Future<Map<String, dynamic>> getPortfolio(String userId) async {
    final res = await _get('/positions/$userId');
    return res['data'] as Map<String, dynamic>;
  }

  // ── Users ───────────────────────────────────────────────────────────────────

  /// Create or fetch a user account (auto-creates with ₹1,00,000 balance).
  Future<Map<String, dynamic>> getOrCreateUser(String userId) async {
    return _post('/users', {'userId': userId});
  }

  Future<Map<String, dynamic>> getUser(String userId) async {
    final res = await _get('/users/$userId');
    return res['data'] as Map<String, dynamic>;
  }

  // ── Derivatives ─────────────────────────────────────────────────────────────

  /// Top gainers/losers in derivatives segment.
  /// [datatype]: PercOIGainers | PercOILosers | PercPriceGainers | PercPriceLosers
  /// [expiry]: NEAR | NEXT | FAR
  Future<List<Map<String, dynamic>>> getDerivativeGainersLosers({
    String datatype = 'PercOIGainers',
    String expiry = 'NEAR',
  }) async {
    final res = await _get(
      '/derivatives/gainers-losers?datatype=$datatype&expiry=$expiry',
    );
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Put-Call Ratio for all F&O symbols.
  Future<List<Map<String, dynamic>>> getPCR() async {
    final res = await _get('/derivatives/pcr');
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// OI Buildup data.
  /// [datatype]: Long Built Up | Short Built Up | Short Covering | Long Unwinding
  /// [expiry]: NEAR | NEXT | FAR
  Future<List<Map<String, dynamic>>> getOIBuildup({
    String datatype = 'Long Built Up',
    String expiry = 'NEAR',
  }) async {
    final encoded = Uri.encodeComponent(datatype);
    final res = await _get(
      '/derivatives/oi-buildup?datatype=$encoded&expiry=$expiry',
    );
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Universal scrip search — searches across all instruments on the exchange.
  /// Returns list of { exchange, tradingSymbol, symbolToken, name, type, ltp, percentChange }
  Future<List<Map<String, dynamic>>> searchScrip(
    String query, {
    String exchange = 'NSE',
  }) async {
    final encoded = Uri.encodeComponent(query);
    final res = await _get(
      '/derivatives/search?q=$encoded&exchange=$exchange',
      ttl: _mediumTtl,
    );
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Universal search across all exchanges and segments.
  /// Returns enriched results with LTP and change data.
  Future<List<Map<String, dynamic>>> searchUniversal(
    String query, {
    String? exchange,
    int limit = 40,
    int offset = 0,
  }) async {
    final encoded = Uri.encodeComponent(query);
    var path = '/search?q=$encoded&limit=$limit&offset=$offset';
    if (exchange != null && exchange != 'ALL') {
      path += '&exchange=${Uri.encodeComponent(exchange)}';
    }
    final res = await _get(path, ttl: _mediumTtl);
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Get live quote for any instrument by token.
  Future<Map<String, dynamic>> getQuoteByToken(
    String token, {
    String exchange = 'NSE',
  }) async {
    // Ensure exchange is never empty — default to NSE only if truly unspecified
    final ex = (exchange.isNotEmpty) ? exchange.toUpperCase() : 'NSE';
    final res = await _get('/derivatives/quote?token=$token&exchange=$ex');
    return res['data'] as Map<String, dynamic>;
  }

  // ── IPO ─────────────────────────────────────────────────────────────────────

  /// Returns all IPOs. Optionally filter by [status]: upcoming | ongoing | closed | listed.
  Future<List<Map<String, dynamic>>> getIPOs({String? status}) async {
    final path = status != null ? '/ipos?status=$status' : '/ipos';
    final res = await _get(path);
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Returns a single IPO by [id].
  Future<Map<String, dynamic>> getIPOById(String id) async {
    final res = await _get('/ipos/$id');
    return res['data'] as Map<String, dynamic>;
  }
}

// ── Cache entry ───────────────────────────────────────────────────────────────

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiry;
  const _CacheEntry({required this.data, required this.expiry});
}

// ── Exception ─────────────────────────────────────────────────────────────────

class BackendException implements Exception {
  final String message;
  final int? statusCode;

  const BackendException(this.message, {this.statusCode});

  @override
  String toString() => statusCode != null
      ? 'BackendException [$statusCode]: $message'
      : 'BackendException: $message';
}
