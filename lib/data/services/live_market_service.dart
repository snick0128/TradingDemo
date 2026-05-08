import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/trading_models.dart';
import 'backend_api_service.dart';

/// WebSocket-driven live market service.
///
/// Live prices come from backend stream `/ws/market`.
/// REST is used only for initial bootstrap snapshot (no recurring polling).
class LiveMarketService {
  LiveMarketService({required BackendApiService api, this.onError})
    : _api = api;

  final BackendApiService _api;
  final void Function(bool isError, String message)? onError;

  final _stockController = StreamController<List<Stock>>.broadcast();
  final _moversController =
      StreamController<Map<String, List<Stock>>>.broadcast();

  final Map<String, Stock> _latestMap = {};
  final Set<String> _subscriptions = {
    'RELIANCE',
    'TCS',
    'INFY',
    'HDFCBANK',
    'ICICIBANK',
    'SBIN',
    'WIPRO',
    'AXISBANK',
    'BAJFINANCE',
    'HINDUNILVR',
  };

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _hasError = false;
  bool get hasError => _hasError;
  bool _disposed = false;

  List<Stock> get latestStocks => _latestMap.values.toList(growable: false);

  Stream<List<Stock>> get stockUpdates => _stockController.stream;
  Stream<Map<String, List<Stock>>> get moversUpdates =>
      _moversController.stream;

  Future<void> start() async {
    _started = true;
    await _bootstrapSnapshot();
    _connectWs();
  }

  void setSubscribedSymbols(Iterable<String> symbols) {
    _subscriptions
      ..clear()
      ..addAll(
        symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty),
      );
    _sendSubscribe();
  }

  void stop() {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    stop();
    if (!_stockController.isClosed) _stockController.close();
    if (!_moversController.isClosed) _moversController.close();
  }

  Future<void> _bootstrapSnapshot() async {
    try {
      final data = await _api.getAllMarketData();
      for (final item in data) {
        final stock = _mapToStock(item);
        if (stock != null) _latestMap[stock.symbol] = stock;
      }
      _emitStocks();
      _emitMovers();
      _setError(false, '');
    } catch (e) {
      _setError(true, 'Bootstrap market snapshot failed: $e');
    }
  }

  void _connectWs() {
    if (_disposed || !_started) return;
    final wsUrl = _toWsUrl(_api.baseUrl);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (e) => _onWsError('WebSocket error: $e'),
        onDone: () => _onWsError('WebSocket disconnected'),
        cancelOnError: true,
      );
      _sendSubscribe();
      _setError(false, '');
    } catch (e) {
      _onWsError('WebSocket connect failed: $e');
    }
  }

  void _onWsMessage(dynamic message) {
    try {
      final m = jsonDecode(message as String) as Map<String, dynamic>;
      final type = m['type']?.toString();
      if (type == 'snapshot') {
        final rows =
            (m['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        for (final row in rows) {
          final stock = _mapToStock(row);
          if (stock != null) _latestMap[stock.symbol] = stock;
        }
        _emitStocks();
        _emitMovers();
        _setError(false, '');
        return;
      }
      if (type == 'tick') {
        final row = m['data'] as Map<String, dynamic>?;
        if (row == null) return;
        final stock = _mapToStock(row);
        if (stock == null) return;
        _latestMap[stock.symbol] = stock;
        _emitStocks();
        _emitMovers();
        _setError(false, '');
      }
    } catch (e) {
      _onWsError('Invalid market stream payload: $e');
    }
  }

  void _onWsError(String message) {
    _setError(true, message);
    if (!_started || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _connectWs);
  }

  void _emitStocks() {
    if (!_stockController.isClosed) {
      _stockController.add(_latestMap.values.toList(growable: false));
    }
  }

  void _emitMovers() {
    final list = _latestMap.values.where((s) => s.currentPrice > 0).toList();
    list.sort((a, b) => b.changePercentage.compareTo(a.changePercentage));
    final gainers = list.take(5).toList();
    final losers = list.reversed.take(5).toList().reversed.toList();
    if (!_moversController.isClosed) {
      _moversController.add({'gainers': gainers, 'losers': losers});
    }
  }

  void _sendSubscribe() {
    final channel = _channel;
    if (channel == null) return;
    final payload = jsonEncode({
      'type': 'subscribe',
      'symbols': _subscriptions.toList(growable: false),
    });
    channel.sink.add(payload);
  }

  void _setError(bool isError, String message) {
    if (_hasError == isError && message.isEmpty) return;
    _hasError = isError;
    onError?.call(isError, message);
  }

  String _toWsUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws/market').toString();
  }

  static Stock? _mapToStock(Map<String, dynamic> d) {
    final symbol = d['symbol'] as String?;
    final ltp = (d['ltp'] as num?)?.toDouble();
    if (symbol == null || ltp == null || ltp <= 0) return null;

    final stale = d['stale'] == true;
    final changePercent = (d['changePercent'] as num?)?.toDouble() ?? 0.0;
    final prevClose = (d['prevClose'] as num?)?.toDouble();
    final volume = (d['volume'] as num?)?.toDouble();

    // Use exchange from backend data — never hardcode NSE
    // Backend sends 'NSE', 'MCX', 'NFO', 'CDS', 'BSE' etc.
    final exchange = (d['exchange'] as String?)?.toUpperCase() ?? 'NSE';

    // Token is needed for MCX/NFO/CDS historical data and quote lookups
    final token = (d['token'] as String?) ?? '';

    return Stock(
      symbol: symbol,
      name: _names[symbol] ?? symbol,
      currentPrice: ltp,
      changePercentage: changePercent,
      sector: _sectors[symbol] ?? _sectorForExchange(exchange),
      exchange: exchange,
      token: token,
      prevClose: prevClose,
      volume: volume,
      isStale: stale,
    );
  }

  /// Returns a sensible default sector label based on exchange.
  static String _sectorForExchange(String exchange) {
    switch (exchange) {
      case 'MCX':   return 'Commodity';
      case 'NFO':   return 'F&O';
      case 'CDS':   return 'Currency';
      case 'BFO':   return 'F&O';
      case 'NCDEX': return 'Commodity';
      default:      return 'Equity';
    }
  }

  static const _names = {
    'RELIANCE': 'Reliance Industries',
    'TCS': 'Tata Consultancy Services',
    'INFY': 'Infosys',
    'HDFCBANK': 'HDFC Bank',
    'ICICIBANK': 'ICICI Bank',
    'SBIN': 'State Bank of India',
    'WIPRO': 'Wipro Limited',
    'AXISBANK': 'Axis Bank',
    'BAJFINANCE': 'Bajaj Finance',
    'HINDUNILVR': 'Hindustan Unilever',
  };

  static const _sectors = {
    'RELIANCE': 'Energy',
    'TCS': 'IT',
    'INFY': 'IT',
    'HDFCBANK': 'Banking',
    'ICICIBANK': 'Banking',
    'SBIN': 'Banking',
    'WIPRO': 'IT',
    'AXISBANK': 'Banking',
    'BAJFINANCE': 'Finance',
    'HINDUNILVR': 'FMCG',
  };
}
