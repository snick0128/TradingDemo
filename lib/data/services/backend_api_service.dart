import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  // Singleton HTTP client — reuses TCP connections across all orders and
  // market data requests, avoiding per-request TLS handshake overhead.
  static final http.Client _client = http.Client();

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
    // Gzip compression — reduces payload size by ~70% for large JSON responses
    // (instrument lists, options chains). The http.Client decompresses transparently.
    'Accept-Encoding': 'gzip, deflate',
  };

  // Render free-tier cold starts can take up to 40s. Use 35s as the cap for
  // order/portfolio requests so they survive a cold start. Search uses its own
  // shorter timeout (see _searchTimeout) to give fast feedback instead of hanging.
  static const _getTimeout    = Duration(seconds: 35);
  static const _searchTimeout = Duration(seconds: 8);

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration? ttl,
    Duration? timeout,
    int attempt = 0,
  }) async {
    final effectiveTtl     = ttl ?? _shortTtl;
    final effectiveTimeout = timeout ?? _getTimeout;
    final now = DateTime.now();
    final cached = _cache[path];
    if (cached != null && now.isBefore(cached.expiry)) {
      return cached.data;
    }

    final uri = Uri.parse('$baseUrl$path');
    final pending = _inFlightGets[path];
    if (pending != null) return pending;

    debugPrint('[BackendAPI] GET: $path (attempt ${attempt + 1}, timeout=${effectiveTimeout.inSeconds}s)');
    final request = () async {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(effectiveTimeout);
      debugPrint('[BackendAPI] ${response.statusCode} $path');
      final result = _parse(response);
      _cache[path] = _CacheEntry(data: result, expiry: now.add(effectiveTtl));
      return result;
    }();

    _inFlightGets[path] = request;
    try {
      return await request;
    } on BackendException {
      rethrow; // 4xx/5xx — pass the real backend error through
    } on TimeoutException {
      if (cached != null) {
        debugPrint('[BackendAPI] Timeout on $path — serving stale cache');
        return cached.data; // stale-while-revalidate
      }
      // One automatic retry for timeouts on the long-timeout path — covers Render cold starts.
      // Short-timeout callers (search) should NOT retry automatically — they fail fast.
      if (attempt == 0 && effectiveTimeout == _getTimeout) {
        _inFlightGets.remove(path);
        return _get(path, ttl: ttl, timeout: timeout, attempt: 1);
      }
      throw BackendException(
        'Server is waking up — please try again in a moment.',
      );
    } catch (e) {
      if (cached != null) {
        debugPrint('[BackendAPI] Network error on $path — serving stale cache');
        return cached.data; // stale-while-revalidate
      }
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
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10)); // warm server — no cold-start risk
      return _parse(response);
    } on BackendException {
      rethrow; // 4xx/5xx — pass the real error message through
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
    // For F&O contracts (options/futures) not tracked by the live WebSocket feed,
    // pass the current LTP from the options chain or detail screen so the backend
    // can price the order instead of throwing "Live price unavailable".
    double? lockedLtp,
    String? clientRequestId,
    String? symbolToken,
  }) async {
    final result = await _post('/orders', {
      'userId': userId,
      'symbol': symbol,
      'qty': qty,
      'type': type,
      'productType': productType,
      'exchange': exchange,
      if (lockedLtp != null && lockedLtp > 0) 'lockedLtp': lockedLtp,
      if (clientRequestId != null) 'clientRequestId': clientRequestId,
      if (symbolToken != null && symbolToken.isNotEmpty) 'symbolToken': symbolToken,
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
  ///
  /// Uses an 8-second timeout (vs 35s for order/portfolio calls) so that
  /// search fails fast on Render cold starts and the UI can show a retry
  /// prompt immediately instead of freezing for 35 seconds.
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
    final res = await _get(path, ttl: _mediumTtl, timeout: _searchTimeout);
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

  // ── F&O Instruments ─────────────────────────────────────────────────────────

  /// Get all F&O underlyings for an exchange.
  /// [exchange]: 'NFO' | 'BFO' | 'MCX'
  Future<List<Map<String, dynamic>>> getFnoUnderlyings({
    String exchange = 'NFO',
  }) async {
    final res = await _get(
      '/derivatives/fno-underlyings?exchange=${Uri.encodeComponent(exchange)}',
      ttl: _longTtl,
    );
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Get expiry dates for a symbol.
  /// Returns ISO date strings e.g. ['2026-05-26', '2026-06-30'].
  /// [typeFilter]: 'OPT' for options only, 'FUT' for futures only, 'ALL' for both.
  Future<List<String>> getFnoExpiryDates(
    String symbol, {
    String exchange = 'NFO',
    String typeFilter = 'ALL',
  }) async {
    final res = await _get(
      '/derivatives/expiry-dates?symbol=${Uri.encodeComponent(symbol)}&exchange=${Uri.encodeComponent(exchange)}&type=${Uri.encodeComponent(typeFilter)}',
      ttl: _mediumTtl,
    );
    return List<String>.from(res['data'] as List);
  }

  /// Get live options chain for symbol + expiry.
  /// Returns raw map with keys: underlying, expiry, underlyingLtp, strikes.
  Future<Map<String, dynamic>> getOptionsChainData(
    String symbol,
    String expiry, {
    String exchange = 'NFO',
  }) async {
    final res = await _get(
      '/derivatives/options-chain?symbol=${Uri.encodeComponent(symbol)}&expiry=${Uri.encodeComponent(expiry)}&exchange=${Uri.encodeComponent(exchange)}',
      ttl: _shortTtl,
    );
    return res['data'] as Map<String, dynamic>;
  }

  /// Browse F&O instruments (paginated).
  /// [type]: 'ALL' | 'FUT' | 'OPT'
  Future<List<Map<String, dynamic>>> getFnoInstruments({
    String exchange = 'NFO',
    String type = 'ALL',
    String? underlying,
    int limit = 50,
    int offset = 0,
  }) async {
    var path =
        '/derivatives/fno-instruments?exchange=${Uri.encodeComponent(exchange)}&type=${Uri.encodeComponent(type)}&limit=$limit&offset=$offset';
    if (underlying != null && underlying.isNotEmpty) {
      path += '&underlying=${Uri.encodeComponent(underlying)}';
    }
    final res = await _get(path, ttl: _longTtl);
    return List<Map<String, dynamic>>.from(res['data'] as List);
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

  // ── FCM Notifications ────────────────────────────────────────────────────────

  /// Broadcast a push notification to all subscribed users via "all_users" topic.
  Future<Map<String, dynamic>> broadcastNotification({
    required String title,
    required String message,
    Map<String, String>? data,
  }) => _post('/admin/notifications/broadcast', {
    'title': title,
    'message': message,
    if (data != null) 'data': data,
  });

  /// Send a push notification to a specific FCM token (one device).
  Future<Map<String, dynamic>> sendNotificationToToken({
    required String fcmToken,
    required String title,
    required String message,
    Map<String, String>? data,
  }) => _post('/admin/notifications/send-to-user', {
    'fcmToken': fcmToken,
    'title': title,
    'message': message,
    if (data != null) 'data': data,
  });

  /// Send a push notification to multiple FCM tokens (batch, max 500).
  Future<Map<String, dynamic>> sendNotificationToTokens({
    required List<String> tokens,
    required String title,
    required String message,
    Map<String, String>? data,
  }) => _post('/admin/notifications/send-to-tokens', {
    'tokens': tokens,
    'title': title,
    'message': message,
    if (data != null) 'data': data,
  });

  // ── Platform settings ────────────────────────────────────────────────────────

  /// Fetch admin-controlled platform RMS and leverage settings.
  Future<Map<String, dynamic>> getRmsSettings() async {
    final res = await _get('/admin/config/rms-settings', ttl: _mediumTtl);
    return res['data'] as Map<String, dynamic>;
  }

  /// Update platform RMS settings (admin only).
  Future<void> updateRmsSettings(Map<String, dynamic> settings) async {
    await _post('/admin/config/rms-settings', settings);
    invalidate('/admin/config/rms-settings');
  }

  /// Fetch support contact configuration.
  Future<Map<String, dynamic>> getSupportConfig() async {
    final res = await _get('/admin/config/support', ttl: _longTtl);
    return res['data'] as Map<String, dynamic>;
  }

  /// Update support contact config (admin only).
  Future<void> updateSupportConfig(Map<String, dynamic> config) async {
    await _post('/admin/config/support', config);
    invalidate('/admin/config/support');
  }

  // ── In-app Notifications ─────────────────────────────────────────────────────

  /// Fetch paginated notifications for a user.
  Future<List<Map<String, dynamic>>> getUserNotifications(
    String userId, {
    int limit = 50,
    String? startAfter,
  }) async {
    var path = '/notifications/$userId?limit=$limit';
    if (startAfter != null) path += '&startAfter=$startAfter';
    final res = await _get(path, ttl: _shortTtl);
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Mark a single notification as read.
  Future<void> markNotificationRead(String userId, String notifId) =>
      _post('/notifications/$userId/$notifId/read', {});

  /// Mark all notifications as read for a user.
  Future<void> markAllNotificationsRead(String userId) =>
      _post('/notifications/$userId/read-all', {});

  // ── Admin password change ────────────────────────────────────────────────────

  /// Change admin password via Firebase Admin SDK on the backend.
  Future<void> changeAdminPassword({
    required String uid,
    required String newPassword,
  }) async {
    await _post('/admin/change-password', {
      'uid': uid,
      'newPassword': newPassword,
    });
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
