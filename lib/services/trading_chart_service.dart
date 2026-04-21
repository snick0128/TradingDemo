import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';

enum ChartType { candles, line, area }

class TradingChartSeries {
  final List<FlSpot> closeSpots;
  final List<CandlestickSpot> candlestickSpots;
  final List<FlSpot> sma20Spots;
  final List<FlSpot> sma50Spots;
  final List<BarChartGroupData> volumeBars;
  final List<String> xLabels;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double vwap;
  final double rsi14;

  const TradingChartSeries({
    required this.closeSpots,
    required this.candlestickSpots,
    required this.sma20Spots,
    required this.sma50Spots,
    required this.volumeBars,
    required this.xLabels,
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
  static TradingChartSeries buildSeries({
    required String symbol,
    required double basePrice,
    required int rangeIndex,
  }) {
    final count = _countForRange(rangeIndex);
    final minutesStep = _minutesStepForRange(rangeIndex);
    final seed = _seed(symbol, rangeIndex);
    final random = math.Random(seed);

    final closes = <double>[];
    final highs = <double>[];
    final lows = <double>[];
    final opens = <double>[];
    final volumes = <double>[];

    var previousClose = basePrice * (0.985 + random.nextDouble() * 0.03);
    for (var i = 0; i < count; i++) {
      final trend = (rangeIndex - 1.5) * 0.035;
      final cyclical = math.sin((i + seed % 11) / (4.0 + rangeIndex)) * 0.55;
      final noise = (random.nextDouble() - 0.5) * (1.2 + rangeIndex * 0.28);
      final delta = (trend + cyclical + noise) * math.max(1, previousClose * 0.0018);

      final open = previousClose;
      var close = (open + delta).clamp(1.0, double.infinity);
      if (close == open) {
        close += (random.nextDouble() - 0.5) * 0.4;
      }

      final wickUp = random.nextDouble() * (0.3 + rangeIndex * 0.1);
      final wickDown = random.nextDouble() * (0.3 + rangeIndex * 0.1);
      final high = math.max(open, close) + wickUp;
      final low = math.max(0.1, math.min(open, close) - wickDown);
      final volume = (90000 + random.nextDouble() * 240000) * (1 + i / (count * 3));

      opens.add(open);
      closes.add(close);
      highs.add(high);
      lows.add(low);
      volumes.add(volume);
      previousClose = close;
    }

    final closeSpots = <FlSpot>[];
    final candlestickSpots = <CandlestickSpot>[];
    final sma20Spots = <FlSpot>[];
    final sma50Spots = <FlSpot>[];
    final volumeBars = <BarChartGroupData>[];

    for (var i = 0; i < count; i++) {
      final x = i.toDouble();
      closeSpots.add(FlSpot(x, closes[i]));
      candlestickSpots.add(
        CandlestickSpot(
          x: x,
          open: opens[i],
          high: highs[i],
          low: lows[i],
          close: closes[i],
        ),
      );
      final sma20 = _sma(closes, i, 20);
      final sma50 = _sma(closes, i, 50);
      if (sma20 != null) sma20Spots.add(FlSpot(x, sma20));
      if (sma50 != null) sma50Spots.add(FlSpot(x, sma50));

      volumeBars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: volumes[i],
              width: 3,
              color: closes[i] >= opens[i] ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              borderRadius: BorderRadius.zero,
            ),
          ],
        ),
      );
    }

    final seriesHigh = highs.reduce(math.max);
    final seriesLow = lows.reduce(math.min);
    final totalVolume = volumes.fold<double>(0, (sum, item) => sum + item);

    var vwapNumerator = 0.0;
    for (var i = 0; i < count; i++) {
      final typicalPrice = (highs[i] + lows[i] + closes[i]) / 3;
      vwapNumerator += typicalPrice * volumes[i];
    }

    return TradingChartSeries(
      closeSpots: closeSpots,
      candlestickSpots: candlestickSpots,
      sma20Spots: sma20Spots,
      sma50Spots: sma50Spots,
      volumeBars: volumeBars,
      xLabels: _buildLabels(count: count, minutesStep: minutesStep),
      open: opens.first,
      high: seriesHigh,
      low: seriesLow,
      close: closes.last,
      volume: totalVolume,
      vwap: totalVolume == 0 ? closes.last : vwapNumerator / totalVolume,
      rsi14: _rsi(closes, 14),
    );
  }

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

  static List<String> _buildLabels({required int count, required int minutesStep}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final start = end.subtract(Duration(minutes: minutesStep * (count - 1)));

    return List.generate(count, (index) {
      final time = start.add(Duration(minutes: minutesStep * index));
      if (minutesStep < 120) {
        final hh = time.hour.toString().padLeft(2, '0');
        final mm = time.minute.toString().padLeft(2, '0');
        return '$hh:$mm';
      }
      final day = time.day.toString().padLeft(2, '0');
      final month = time.month.toString().padLeft(2, '0');
      return '$day/$month';
    });
  }
}
