import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/trading_models.dart';

class TradingCandle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double? sma20;
  final double? sma50;

  const TradingCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.sma20,
    this.sma50,
  });

  TradingCandle copyWith({
    DateTime? time,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
    double? sma20,
    double? sma50,
  }) {
    return TradingCandle(
      time: time ?? this.time,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      sma20: sma20 ?? this.sma20,
      sma50: sma50 ?? this.sma50,
    );
  }
}

class TradingChartSeries {
  final List<TradingCandle> data;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double vwap;
  final double rsi14;

  const TradingChartSeries({
    required this.data,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.vwap,
    required this.rsi14,
  });
}

class TradingChartService {
  @Deprecated('Synthetic generation removed. Use fromRawCandles instead.')
  static TradingChartSeries buildSeries({
    required String symbol,
    required double basePrice,
    int rangeIndex = 2,
    ChartTimeframe timeframe = ChartTimeframe.d1,
    ChartDateRange dateRange = ChartDateRange.mo1,
  }) {
    throw UnsupportedError(
      'Synthetic chart generation was removed. Use fromRawCandles().',
    );
  }

  static TradingChartSeries fromRawCandles(
    List<Map<String, dynamic>> rawCandles, {
    required double fallbackPrice,
  }) {
    final candles = <TradingCandle>[];
    for (final row in rawCandles) {
      final timeStr = row['time']?.toString();
      final time = DateTime.tryParse(timeStr ?? '');
      if (time == null) continue;

      final open = (row['open'] as num?)?.toDouble();
      final high = (row['high'] as num?)?.toDouble();
      final low = (row['low'] as num?)?.toDouble();
      final close = (row['close'] as num?)?.toDouble();
      final volume = (row['volume'] as num?)?.toDouble() ?? 0;
      if (open == null || high == null || low == null || close == null) {
        continue;
      }

      candles.add(
        TradingCandle(
          time: time,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ),
      );
    }

    if (candles.isEmpty) {
      // Avoid showing a fake ₹1.00 placeholder while real quote/candles load.
      final px = fallbackPrice > 0 ? fallbackPrice : 0.0;
      candles.add(
        TradingCandle(
          time: DateTime.now(),
          open: px,
          high: px,
          low: px,
          close: px,
          volume: 0,
        ),
      );
    }

    final closes = candles.map((c) => c.close).toList(growable: false);
    final highs = candles.map((c) => c.high).toList(growable: false);
    final lows = candles.map((c) => c.low).toList(growable: false);
    final volumes = candles.map((c) => c.volume).toList(growable: false);

    final enriched = <TradingCandle>[];
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      enriched.add(
        TradingCandle(
          time: c.time,
          open: c.open,
          high: c.high,
          low: c.low,
          close: c.close,
          volume: c.volume,
          sma20: _sma(closes, i, 20),
          sma50: _sma(closes, i, 50),
        ),
      );
    }

    final seriesHigh = highs.reduce(math.max);
    final seriesLow = lows.reduce(math.min);
    final totalVolume = volumes.fold<double>(0, (sum, item) => sum + item);
    var vwapNumerator = 0.0;
    for (var i = 0; i < enriched.length; i++) {
      final tp = (enriched[i].high + enriched[i].low + enriched[i].close) / 3;
      vwapNumerator += tp * enriched[i].volume;
    }

    return TradingChartSeries(
      data: enriched,
      open: enriched.first.open,
      high: seriesHigh,
      low: seriesLow,
      close: enriched.last.close,
      volume: totalVolume,
      vwap: totalVolume == 0
          ? enriched.last.close
          : vwapNumerator / totalVolume,
      rsi14: _rsi(closes, 14),
    );
  }

  // ─── Build series from already-parsed candle objects ────────────────────────

  static TradingChartSeries fromCandleObjects(
    List<TradingCandle> candles, {
    required double fallbackPrice,
  }) {
    if (candles.isEmpty) {
      final px = fallbackPrice > 0 ? fallbackPrice : 0.0;
      return TradingChartSeries(
        data: [
          TradingCandle(
            time: DateTime.now(),
            open: px, high: px, low: px, close: px, volume: 0,
          ),
        ],
        open: px, high: px, low: px, close: px,
        volume: 0, vwap: px, rsi14: 50,
      );
    }
    final closes  = candles.map((c) => c.close).toList(growable: false);
    final highs   = candles.map((c) => c.high).toList(growable: false);
    final lows    = candles.map((c) => c.low).toList(growable: false);
    final volumes = candles.map((c) => c.volume).toList(growable: false);
    final totalVol = volumes.fold<double>(0, (s, v) => s + v);
    var vwapNum = 0.0;
    for (final c in candles) {
      vwapNum += ((c.high + c.low + c.close) / 3) * c.volume;
    }
    return TradingChartSeries(
      data: candles,
      open: candles.first.open,
      high: highs.reduce(math.max),
      low: lows.reduce(math.min),
      close: candles.last.close,
      volume: totalVol,
      vwap: totalVol == 0 ? candles.last.close : vwapNum / totalVol,
      rsi14: _rsi(closes, 14),
    );
  }

  // ─── Real-time tick merge (new candle detection) ─────────────────────────────

  /// Merge a live price tick into an existing series.
  ///
  /// Returns a record with:
  /// - [series]: updated series (either last candle updated or new candle appended)
  /// - [isNewCandle]: true when a new interval started and a new candle was created
  ///
  /// [intervalMinutes] must match the chart's current timeframe (e.g. 5 for 5m).
  static ({TradingChartSeries series, bool isNewCandle}) mergeRealtimeTick(
    TradingChartSeries series,
    double price, {
    required int intervalMinutes,
  }) {
    if (series.data.isEmpty || price <= 0) return (series: series, isNewCandle: false);

    final now = DateTime.now().toLocal();
    final candles = [...series.data];
    final last = candles.last;

    // Floor both the last candle's time and "now" to the same interval grid.
    final lastSlot = _floorToInterval(last.time.toLocal(), intervalMinutes);
    final nowSlot  = _floorToInterval(now, intervalMinutes);

    bool isNewCandle = false;
    if (nowSlot.isAfter(lastSlot)) {
      // New candle interval has started.
      candles.add(TradingCandle(
        time: nowSlot,
        open: price, high: price, low: price, close: price, volume: 0,
      ));
      isNewCandle = true;
      debugPrint('[ChartService] New candle opened at $nowSlot '
          'price=$price total=${candles.length}');
    } else {
      // Still inside the same candle — update OHLC.
      candles[candles.length - 1] = TradingCandle(
        time:   last.time,
        open:   last.open,
        high:   math.max(last.high, price),
        low:    last.low == 0 ? price : math.min(last.low, price),
        close:  price,
        volume: last.volume,
        sma20:  last.sma20,
        sma50:  last.sma50,
      );
    }

    final highs   = candles.map((c) => c.high);
    final lows    = candles.map((c) => c.low);
    final closes  = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume).toList();
    final totalVol = volumes.fold<double>(0, (s, v) => s + v);
    var vwapNum = 0.0;
    for (final c in candles) {
      vwapNum += ((c.high + c.low + c.close) / 3) * c.volume;
    }

    return (
      series: TradingChartSeries(
        data: candles,
        open: candles.first.open,
        high: highs.reduce(math.max),
        low: lows.reduce(math.min),
        close: price,
        volume: totalVol,
        vwap: totalVol == 0 ? price : vwapNum / totalVol,
        rsi14: _rsi(closes, 14),
      ),
      isNewCandle: isNewCandle,
    );
  }

  /// Floor [t] down to the nearest [intervalMinutes] boundary (local time).
  static DateTime _floorToInterval(DateTime t, int intervalMinutes) {
    if (intervalMinutes >= 24 * 60) {
      return DateTime(t.year, t.month, t.day);
    }
    final totalMin = t.hour * 60 + t.minute;
    final floored  = (totalMin ~/ intervalMinutes) * intervalMinutes;
    return DateTime(t.year, t.month, t.day, floored ~/ 60, floored % 60);
  }

  static TradingChartSeries withRealtimePrice(
    TradingChartSeries series,
    double price,
  ) {
    if (series.data.isEmpty || price <= 0) return series;
    final candles = [...series.data];
    final last = candles.last;
    candles[candles.length - 1] = TradingCandle(
      time: last.time,
      open: last.open,
      high: math.max(last.high, price),
      low: last.low == 0 ? price : math.min(last.low, price),
      close: price,
      volume: last.volume,
      sma20: last.sma20,
      sma50: last.sma50,
    );

    final highs = candles.map((c) => c.high).toList(growable: false);
    final lows = candles.map((c) => c.low).toList(growable: false);
    final volumes = candles.map((c) => c.volume).toList(growable: false);
    final closes = candles.map((c) => c.close).toList(growable: false);
    final totalVolume = volumes.fold<double>(0, (sum, item) => sum + item);
    var vwapNumerator = 0.0;
    for (final candle in candles) {
      final tp = (candle.high + candle.low + candle.close) / 3;
      vwapNumerator += tp * candle.volume;
    }

    return TradingChartSeries(
      data: candles,
      open: candles.first.open,
      high: highs.reduce(math.max),
      low: lows.reduce(math.min),
      close: price,
      volume: totalVolume,
      vwap: totalVolume == 0 ? price : vwapNumerator / totalVolume,
      rsi14: _rsi(closes, 14),
    );
  }

  // ─── Heikin-Ashi ────────────────────────────────────────────────────────────

  static List<TradingCandle> toHeikinAshi(List<TradingCandle> candles) {
    if (candles.isEmpty) return [];
    final result = <TradingCandle>[];

    double prevHaOpen = (candles.first.open + candles.first.close) / 2;
    double prevHaClose =
        (candles.first.open +
            candles.first.high +
            candles.first.low +
            candles.first.close) /
        4;

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final haClose = (c.open + c.high + c.low + c.close) / 4;
      final haOpen = i == 0
          ? (c.open + c.close) / 2
          : (prevHaOpen + prevHaClose) / 2;
      final haHigh = math.max(c.high, math.max(haOpen, haClose));
      final haLow = math.min(c.low, math.min(haOpen, haClose));

      result.add(
        TradingCandle(
          time: c.time,
          open: haOpen,
          high: haHigh,
          low: haLow,
          close: haClose,
          volume: c.volume,
          sma20: c.sma20,
          sma50: c.sma50,
        ),
      );

      prevHaOpen = haOpen;
      prevHaClose = haClose;
    }

    return result;
  }

  // ─── Indicator Calculations ─────────────────────────────────────────────────

  /// Exponential Moving Average
  static List<double?> ema(List<double> prices, int period) {
    if (prices.length < period) return List.filled(prices.length, null);
    final result = List<double?>.filled(prices.length, null);
    final k = 2.0 / (period + 1);

    // Seed with SMA of first `period` values
    double sum = 0;
    for (var i = 0; i < period; i++) {
      sum += prices[i];
    }
    result[period - 1] = sum / period;

    for (var i = period; i < prices.length; i++) {
      result[i] = prices[i] * k + result[i - 1]! * (1 - k);
    }
    return result;
  }

  /// Bollinger Bands — returns (upper, middle, lower)
  static List<(double?, double?, double?)> bollingerBands(
    List<double> prices,
    int period,
    double stdDev,
  ) {
    final result = <(double?, double?, double?)>[];
    for (var i = 0; i < prices.length; i++) {
      if (i + 1 < period) {
        result.add((null, null, null));
        continue;
      }
      final slice = prices.sublist(i + 1 - period, i + 1);
      final mean = slice.reduce((a, b) => a + b) / period;
      final variance =
          slice.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          period;
      final sd = math.sqrt(variance);
      result.add((mean + stdDev * sd, mean, mean - stdDev * sd));
    }
    return result;
  }

  /// MACD (12, 26, 9) — returns (macd, signal, histogram)
  static List<(double?, double?, double?)> macd(List<double> prices) {
    const fastPeriod = 12;
    const slowPeriod = 26;
    const signalPeriod = 9;

    final fastEma = ema(prices, fastPeriod);
    final slowEma = ema(prices, slowPeriod);

    final macdLine = List<double?>.filled(prices.length, null);
    for (var i = 0; i < prices.length; i++) {
      if (fastEma[i] != null && slowEma[i] != null) {
        macdLine[i] = fastEma[i]! - slowEma[i]!;
      }
    }

    // Signal line: EMA(9) of MACD line
    final macdValues = <double>[];
    final macdStartIndex = <int>[];
    for (var i = 0; i < macdLine.length; i++) {
      if (macdLine[i] != null) {
        macdValues.add(macdLine[i]!);
        macdStartIndex.add(i);
      }
    }

    final signalValues = ema(macdValues, signalPeriod);
    final signalMap = <int, double?>{};
    for (var i = 0; i < macdStartIndex.length; i++) {
      signalMap[macdStartIndex[i]] = signalValues[i];
    }

    final result = <(double?, double?, double?)>[];
    for (var i = 0; i < prices.length; i++) {
      final m = macdLine[i];
      final s = signalMap[i];
      final h = (m != null && s != null) ? m - s : null;
      result.add((m, s, h));
    }
    return result;
  }

  /// Stochastic %K
  static List<double?> stochastic(List<TradingCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    for (var i = period - 1; i < candles.length; i++) {
      final slice = candles.sublist(i + 1 - period, i + 1);
      final highestHigh = slice.map((c) => c.high).reduce(math.max);
      final lowestLow = slice.map((c) => c.low).reduce(math.min);
      final range = highestHigh - lowestLow;
      result[i] = range == 0
          ? 50
          : (candles[i].close - lowestLow) / range * 100;
    }
    return result;
  }

  /// Commodity Channel Index
  static List<double?> cci(List<TradingCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    for (var i = period - 1; i < candles.length; i++) {
      final slice = candles.sublist(i + 1 - period, i + 1);
      final typicals = slice
          .map((c) => (c.high + c.low + c.close) / 3)
          .toList();
      final mean = typicals.reduce((a, b) => a + b) / period;
      final meanDev =
          typicals.map((t) => (t - mean).abs()).reduce((a, b) => a + b) /
          period;
      result[i] = meanDev == 0 ? 0 : (typicals.last - mean) / (0.015 * meanDev);
    }
    return result;
  }

  /// Williams %R
  static List<double?> williamsR(List<TradingCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    for (var i = period - 1; i < candles.length; i++) {
      final slice = candles.sublist(i + 1 - period, i + 1);
      final highestHigh = slice.map((c) => c.high).reduce(math.max);
      final lowestLow = slice.map((c) => c.low).reduce(math.min);
      final range = highestHigh - lowestLow;
      result[i] = range == 0
          ? -50
          : (highestHigh - candles[i].close) / range * -100;
    }
    return result;
  }

  /// On-Balance Volume
  static List<double?> obv(List<TradingCandle> candles) {
    if (candles.isEmpty) return [];
    final result = List<double?>.filled(candles.length, null);
    result[0] = candles[0].volume;
    for (var i = 1; i < candles.length; i++) {
      final prev = result[i - 1]!;
      if (candles[i].close > candles[i - 1].close) {
        result[i] = prev + candles[i].volume;
      } else if (candles[i].close < candles[i - 1].close) {
        result[i] = prev - candles[i].volume;
      } else {
        result[i] = prev;
      }
    }
    return result;
  }

  /// Average True Range
  static List<double?> atr(List<TradingCandle> candles, int period) {
    if (candles.length < 2) return List.filled(candles.length, null);
    final result = List<double?>.filled(candles.length, null);

    final trValues = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final hl = candles[i].high - candles[i].low;
      final hc = (candles[i].high - candles[i - 1].close).abs();
      final lc = (candles[i].low - candles[i - 1].close).abs();
      trValues.add(math.max(hl, math.max(hc, lc)));
    }

    if (trValues.length < period) return result;

    // First ATR = simple average of first `period` TRs
    double atrVal =
        trValues.sublist(0, period).reduce((a, b) => a + b) / period;
    result[period] = atrVal;

    for (var i = period; i < trValues.length; i++) {
      atrVal = (atrVal * (period - 1) + trValues[i]) / period;
      result[i + 1] = atrVal;
    }
    return result;
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  static int _countForRange(int rangeIndex) {
    switch (rangeIndex) {
      case 0:
        return 78;
      case 1:
        return 84;
      case 2:
        return 90;
      case 3:
        return 120;
      default:
        return 180;
    }
  }

  static int _minutesStepForRange(int rangeIndex) {
    switch (rangeIndex) {
      case 0:
        return 5;
      case 1:
        return 30;
      case 2:
        return 120;
      case 3:
        return 360;
      default:
        return 1440;
    }
  }

  static int _seed(String symbol, int rangeIndex) {
    var value = 0;
    for (final unit in symbol.codeUnits) {
      value = ((value * 31) + unit) & 0x7fffffff;
    }
    return value + (rangeIndex * 101);
  }

  static double? _sma(List<double> values, int index, int period) {
    if (index + 1 < period) {
      return null;
    }
    var sum = 0.0;
    for (var i = index; i > index - period; i--) {
      sum += values[i];
    }
    return sum / period;
  }

  static double _rsi(List<double> closes, int period) {
    if (closes.length <= period) {
      return 50;
    }

    var gain = 0.0;
    var loss = 0.0;
    for (var i = 1; i <= period; i++) {
      final diff = closes[i] - closes[i - 1];
      if (diff >= 0) {
        gain += diff;
      } else {
        loss += diff.abs();
      }
    }

    var avgGain = gain / period;
    var avgLoss = loss / period;

    for (var i = period + 1; i < closes.length; i++) {
      final diff = closes[i] - closes[i - 1];
      final currentGain = diff > 0 ? diff : 0.0;
      final currentLoss = diff < 0 ? diff.abs() : 0.0;
      avgGain = ((avgGain * (period - 1)) + currentGain) / period;
      avgLoss = ((avgLoss * (period - 1)) + currentLoss) / period;
    }

    if (avgLoss == 0) {
      return 100;
    }

    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }
}
