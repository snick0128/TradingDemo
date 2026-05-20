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

  final _stockController        = StreamController<List<Stock>>.broadcast();
  final _moversController       = StreamController<Map<String, List<Stock>>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, Stock> _latestMap = {};
  // Start with all known symbols — MCX commodities included.
  // This set is updated by setSubscribedSymbols() as the user navigates.
  final Set<String> _subscriptions = {
    // NSE Equities
    'RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'ICICIBANK',
    'SBIN', 'WIPRO', 'AXISBANK', 'BAJFINANCE', 'HINDUNILVR',
    // MCX Commodities
    'GOLD', 'SILVER', 'CRUDEOIL', 'NATURALGAS',
    'COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL', 'COTTON',
  };

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _moversDebounce;
  Timer? _tickFlushTimer;
  int _reconnectAttempt = 0;
  final Map<String, int> _lastSeqBySymbol = {};
  final Map<String, double> _lastEmittedLtpBySymbol = {};
  bool _started = false;
  bool _hasError = false;
  bool get hasError => _hasError;
  bool _disposed = false;

  List<Stock> get latestStocks => _latestMap.values.toList(growable: false);

  Stream<List<Stock>> get stockUpdates => _stockController.stream;
  Stream<Map<String, List<Stock>>> get moversUpdates => _moversController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;

  String? _registeredUserId;

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
    _moversDebounce?.cancel();
    _moversDebounce = null;
    _tickFlushTimer?.cancel();
    _tickFlushTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    stop();
    if (!_stockController.isClosed)        _stockController.close();
    if (!_moversController.isClosed)       _moversController.close();
    if (!_notificationController.isClosed) _notificationController.close();
  }

  /// Register this client's userId with the backend WebSocket so the server
  /// can push per-user notifications in real-time.
  void registerUser(String userId) {
    _registeredUserId = userId;
    _sendUserRegister();
  }

  void _sendUserRegister() {
    final channel = _channel;
    if (channel == null || _registeredUserId == null) return;
    channel.sink.add(jsonEncode({'type': 'register_user', 'userId': _registeredUserId}));
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
      _setError(
        true,
        'Could not load market data. Please check your connection and try again.',
      );
    }
  }

  void _connectWs() {
    if (_disposed || !_started) return;
    final wsUrl = _toWsUrl(_api.baseUrl);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (e) =>
            _onWsError('Live market feed interrupted. Reconnecting…'),
        onDone: () =>
            _onWsError('Live market feed disconnected. Reconnecting…'),
        cancelOnError: true,
      );
      _sendSubscribe();
      _sendUserRegister(); // re-register after reconnect
      _setError(false, '');
      _reconnectAttempt = 0;
    } catch (e) {
      _onWsError('Could not connect to the live market feed. Retrying…');
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
        final symbol = (m['symbol'] as String? ?? '').toUpperCase();
        final seq = (m['seq'] as num?)?.toInt() ?? 0;
        if (symbol.isNotEmpty && seq > 0) {
          final lastSeq = _lastSeqBySymbol[symbol] ?? 0;
          if (seq <= lastSeq) {
            return;
          }
          _lastSeqBySymbol[symbol] = seq;
        }
        final row = m['data'] as Map<String, dynamic>?;
        if (row == null) return;
        final stock = _mapToStock(row);
        if (stock == null) return;
        final lastLtp = _lastEmittedLtpBySymbol[stock.symbol] ?? 0;
        if (lastLtp == stock.currentPrice) return;
        _lastEmittedLtpBySymbol[stock.symbol] = stock.currentPrice;
        _latestMap[stock.symbol] = stock;
        _scheduleTick();
        _scheduleMovers();
        _setError(false, '');
        return;
      }
      if (type == 'notification') {
        final data = m['data'] as Map<String, dynamic>?;
        if (data != null && !_notificationController.isClosed) {
          _notificationController.add(data);
        }
        return;
      }
    } catch (e) {
      _onWsError(
        'Received unexpected data from the market feed. Reconnecting…',
      );
    }
  }

  void _onWsError(String message) {
    _setError(true, message);
    if (!_started || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    final delaySeconds = _reconnectAttempt <= 2
        ? 1
        : (_reconnectAttempt <= 5 ? 2 : 5);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _connectWs);
  }

  void _scheduleTick() {
    _tickFlushTimer ??= Timer(const Duration(milliseconds: 50), () {
      _tickFlushTimer = null;
      _emitStocks();
    });
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

  void _scheduleMovers() {
    _moversDebounce ??= Timer(const Duration(seconds: 5), () {
      _moversDebounce = null;
      _emitMovers();
    });
  }

  void _sendSubscribe() {
    final channel = _channel;
    if (channel == null) return;
    if (_subscriptions.isEmpty) return;
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
    if (symbol == null || symbol.isEmpty) return null;

    // ltp can be null for symbols not yet ticked — skip those
    final ltpRaw = d['ltp'];
    final ltp = ltpRaw is num ? ltpRaw.toDouble() : null;
    if (ltp == null || ltp <= 0) return null;

    final stale = d['stale'] == true;

    // Backend sends 'changePercent' (not 'changePercentage')
    final changePercent =
        (d['changePercent'] as num?)?.toDouble() ??
        (d['changePercentage'] as num?)?.toDouble() ??
        0.0;

    final prevClose = (d['prevClose'] as num?)?.toDouble();
    final volume = (d['volume'] as num?)?.toDouble();

    // exchange is always present now — backend enriches every payload
    final exchange = (d['exchange'] as String?)?.toUpperCase() ?? 'NSE';

    // token is needed for MCX/NFO historical data and quote lookups
    final token = (d['token'] as String?) ?? '';

    // expiry is sent as ISO-8601 string for futures contracts, null for equities
    DateTime? expiry;
    final expiryRaw = d['expiry'];
    if (expiryRaw is String && expiryRaw.isNotEmpty) {
      expiry = DateTime.tryParse(expiryRaw);
    }

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
      expiry: expiry,
    );
  }

  /// Returns a sensible default sector label based on exchange.
  static String _sectorForExchange(String exchange) {
    switch (exchange) {
      case 'MCX':
        return 'Commodity';
      case 'NFO':
        return 'F&O';
      case 'CDS':
        return 'Currency';
      case 'BFO':
        return 'F&O';
      case 'NCDEX':
        return 'Commodity';
      default:
        return 'Equity';
    }
  }

  static const _names = {
    // NSE Equities
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
    // MCX Commodities
    'GOLD': 'Gold Futures',
    'SILVER': 'Silver Futures',
    'CRUDEOIL': 'Crude Oil Futures',
    'NATURALGAS': 'Natural Gas Futures',
    'COPPER': 'Copper Futures',
    'ZINC': 'Zinc Futures',
    'LEAD': 'Lead Futures',
    'ALUMINIUM': 'Aluminium Futures',
    'NICKEL': 'Nickel Futures',
    'COTTON': 'Cotton Futures',
  };

  static const _sectors = {
    // NSE Equities
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
    // MCX Commodities
    'GOLD': 'Commodity',
    'SILVER': 'Commodity',
    'CRUDEOIL': 'Commodity',
    'NATURALGAS': 'Commodity',
    'COPPER': 'Commodity',
    'ZINC': 'Commodity',
    'LEAD': 'Commodity',
    'ALUMINIUM': 'Commodity',
    'NICKEL': 'Commodity',
    'COTTON': 'Commodity',
  };
}
