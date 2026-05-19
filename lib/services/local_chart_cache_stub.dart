import 'trading_chart_service.dart';

class LocalChartCache {
  const LocalChartCache();

  TradingChartSeries? readSeries(String key) => null;

  void writeSeries(String key, TradingChartSeries series) {}
}
