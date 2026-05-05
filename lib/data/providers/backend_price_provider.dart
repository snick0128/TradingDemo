import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/pricing/price_provider.dart';
import '../services/backend_api_service.dart';

/// PriceProvider backed by backend WebSocket `/ws/market`.
///
/// No REST polling is used for live prices.
class BackendPriceProvider implements PriceProvider {
  BackendPriceProvider({required BackendApiService api}) : _api = api;

  final BackendApiService _api;
  final Map<String, double> _cache = {};
  final Map<String, int> _serverTsBySymbol = {};
  final Map<String, StreamController<double>> _controllers = {};

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connected = false;

  @override
  Stream<double> getPrice(String stock) {
    final symbol = stock.trim().toUpperCase();
    final ctrl = _controllers.putIfAbsent(
      symbol,
      () => StreamController<double>.broadcast(
        onListen: () {
          _ensureConnected();
          _sendSubscribe();
          final cached = _cache[symbol];
          if (cached != null) {
            final c = _controllers[symbol];
            if (c != null && !c.isClosed) c.add(cached);
          }
        },
        onCancel: _sendSubscribe,
      ),
    );
    return ctrl.stream;
  }

  void _ensureConnected() {
    if (_disposed || _connected) return;
    try {
      final wsUrl = _toWsUrl(_api.baseUrl);
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: _reconnect,
        onError: (_) => _reconnect(),
        cancelOnError: true,
      );
      _connected = true;
    } catch (_) {
      _reconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final m = jsonDecode(message as String) as Map<String, dynamic>;
      final type = m['type']?.toString();
      if (type == 'snapshot') {
        final rows =
            (m['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        for (final row in rows) {
          _publishRow(row);
        }
        return;
      }
      if (type == 'tick') {
        final row = m['data'] as Map<String, dynamic>?;
        if (row == null) return;
        _publishRow(row);
      }
    } catch (_) {
      // ignore malformed stream frame
    }
  }

  void _publishRow(Map<String, dynamic> row) {
    final symbol = row['symbol'] as String?;
    final ltp = (row['ltp'] as num?)?.toDouble();
    final stale = row['stale'] == true;
    final serverTs =
        (row['serverTs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final ageMs = DateTime.now().millisecondsSinceEpoch - serverTs;
    if (symbol == null || ltp == null || ltp <= 0) return;
    if (stale || ageMs > 5000) return;
    _cache[symbol] = ltp;
    _serverTsBySymbol[symbol] = serverTs;
    final ctrl = _controllers[symbol];
    if (ctrl != null && !ctrl.isClosed && ctrl.hasListener) {
      ctrl.add(ltp);
    }
  }

  void _sendSubscribe() {
    if (!_connected || _channel == null) return;
    final symbols = _controllers.entries
        .where((e) => e.value.hasListener)
        .map((e) => e.key)
        .toList(growable: false);
    if (symbols.isEmpty) return;
    _channel!.sink.add(jsonEncode({'type': 'subscribe', 'symbols': symbols}));
    _channel!.sink.add(jsonEncode({'type': 'snapshot', 'symbols': symbols}));
  }

  void _reconnect() {
    if (_disposed) return;
    _connected = false;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _ensureConnected);
  }

  String _toWsUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws/market').toString();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
    _controllers.clear();
    _cache.clear();
    _serverTsBySymbol.clear();
  }
}
