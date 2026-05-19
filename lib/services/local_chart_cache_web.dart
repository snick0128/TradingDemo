// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'trading_chart_service.dart';

class LocalChartCache {
  const LocalChartCache();

  static const _prefix = 'boxTrading.chart.';
  static const _schema = 1;
  static const _maxAgeMs = 1000 * 60 * 60 * 12;

  TradingChartSeries? readSeries(String key) {
    try {
      final raw = html.window.localStorage['$_prefix$key'];
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['schema'] != _schema) return null;
      final savedAt = (decoded['savedAt'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - savedAt > _maxAgeMs) {
        html.window.localStorage.remove('$_prefix$key');
        return null;
      }
      final rows =
          (decoded['candles'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      if (rows.isEmpty) return null;
      return TradingChartService.fromRawCandles(rows, fallbackPrice: 0);
    } catch (_) {
      return null;
    }
  }

  void writeSeries(String key, TradingChartSeries series) {
    if (series.data.isEmpty) return;
    try {
      final payload = {
        'schema': _schema,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'candles': series.data
            .map(
              (c) => {
                'time': c.time.toIso8601String(),
                'open': c.open,
                'high': c.high,
                'low': c.low,
                'close': c.close,
                'volume': c.volume,
              },
            )
            .toList(growable: false),
      };
      html.window.localStorage['$_prefix$key'] = jsonEncode(payload);
    } catch (_) {
      // Browsers can reject localStorage in private mode or when quota is full.
    }
  }
}
