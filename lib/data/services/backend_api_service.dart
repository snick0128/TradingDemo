import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Central HTTP client for the Node.js paper trading backend.
///
/// Base URL is configured via [BackendApiService.baseUrl].
/// For local testing: http://localhost:3000
/// For production:    https://paper-trading-backend-bnn7.onrender.com
///
/// All methods return parsed Maps/Lists — callers convert to domain models.
class BackendApiService {
  BackendApiService({String? baseUrl})
      : baseUrl = baseUrl ?? _defaultBaseUrl;

  /// Change this to your deployed backend URL when going to production.
  static const String _defaultBaseUrl = 'http://localhost:3000';

  final String baseUrl;

  // ── HTTP helpers ────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _parse(response);
    } on TimeoutException {
      throw BackendException('Request timed out: $path');
    } catch (e) {
      throw BackendException('GET $path failed: $e');
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _parse(response);
    } on TimeoutException {
      throw BackendException('Request timed out: $path');
    } catch (e) {
      throw BackendException('POST $path failed: $e');
    }
  }

  Map<String, dynamic> _parse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw BackendException(
        body['error'] as String? ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  // ── Health ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getHealth() => _get('/health');

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
  Future<List<Map<String, dynamic>>> getHistoricalData(
    String symbol, {
    String interval = '5m',
    String? from,
    String? to,
  }) async {
    var path = '/market/historical?symbol=$symbol&interval=$interval';
    if (from != null) path += '&from=${Uri.encodeComponent(from)}';
    if (to != null) path += '&to=${Uri.encodeComponent(to)}';
    final res = await _get(path);
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  // ── Orders ──────────────────────────────────────────────────────────────────

  /// Place a simulated BUY or SELL order.
  /// Returns the order result including executedPrice and newBalance.
  Future<Map<String, dynamic>> placeOrder({
    required String userId,
    required String symbol,
    required int qty,
    required String type, // 'BUY' or 'SELL'
  }) async {
    return _post('/orders', {
      'userId': userId,
      'symbol': symbol,
      'qty': qty,
      'type': type,
    });
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
  /// Returns list of { exchange, tradingSymbol, symbolToken }
  Future<List<Map<String, dynamic>>> searchScrip(
    String query, {
    String exchange = 'NSE',
  }) async {
    final encoded = Uri.encodeComponent(query);
    final res = await _get(
      '/derivatives/search?q=$encoded&exchange=$exchange',
    );
    return List<Map<String, dynamic>>.from(res['data'] as List);
  }

  /// Get live quote for any instrument by token.
  Future<Map<String, dynamic>> getQuoteByToken(
    String token, {
    String exchange = 'NSE',
  }) async {
    final res = await _get('/derivatives/quote?token=$token&exchange=$exchange');
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
