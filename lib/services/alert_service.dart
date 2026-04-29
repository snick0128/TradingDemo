import 'dart:async';
import '../models/trading_models.dart';
import '../state/trading_store.dart';
import 'market_data_service.dart';

class AlertService {
  final TradingStore _store;
  final MarketDataService _marketData;
  StreamSubscription? _priceSubscription;

  AlertService(this._store, this._marketData) {
    _priceSubscription = _marketData.priceUpdates.listen(_checkAlerts);
  }

  void _checkAlerts(Map<String, double> prices) {
    final activeAlerts = _store.alerts.where((a) => a.isActive).toList();

    for (final alert in activeAlerts) {
      final currentPrice = prices[alert.symbol];
      if (currentPrice == null) continue;

      bool triggered = false;
      String message = '';

      switch (alert.type) {
        case AlertType.priceAbove:
          if (alert.targetPrice != null && currentPrice >= alert.targetPrice!) {
            triggered = true;
            message = '${alert.symbol} is above ${alert.targetPrice}';
          }
          break;
        case AlertType.priceBelow:
          if (alert.targetPrice != null && currentPrice <= alert.targetPrice!) {
            triggered = true;
            message = '${alert.symbol} is below ${alert.targetPrice}';
          }
          break;
        // Add more types as needed
        case AlertType.percentageMove:
          if (alert.percentageThreshold != null && alert.basePrice != null) {
            final move = ((currentPrice - alert.basePrice!) / alert.basePrice!).abs() * 100;
            if (move >= alert.percentageThreshold!) {
              triggered = true;
              message = '${alert.symbol} moved by ${move.toStringAsFixed(2)}%';
            }
          }
          break;
        default:
          break;
      }

      if (triggered) {
        _triggerAlert(alert, message);
      }
    }
  }

  void _triggerAlert(Alert alert, String message) {
    // 1. Mark alert as triggered/inactive in store
    _store.deleteAlert(alert.id); // Or update it to inactive

    // 2. Add notification to store
    _store.addNotification(
      AppNotification(
        id: 'NOTIF-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Price Alert Triggered',
        message: message,
        timestamp: DateTime.now(),
        relatedAlertType: alert.type,
        relatedSymbol: alert.symbol,
      ),
    );
  }

  void dispose() {
    _priceSubscription?.cancel();
  }
}
