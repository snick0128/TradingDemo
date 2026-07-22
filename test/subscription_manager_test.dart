import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/data/services/backend_api_service.dart';
import 'package:box_trading_web/data/services/live_market_service.dart';
import 'package:box_trading_web/services/subscription_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background registration cannot replace visible screen subscriptions', () {
    final service = LiveMarketService(
      api: BackendApiService(baseUrl: 'http://127.0.0.1:1'),
    );
    final manager = SubscriptionManager.instance;
    manager.detach();
    manager.attach(service);

    manager.replaceScreenSubscriptions('dashboard', {'NIFTY', 'BANKNIFTY'});
    manager.replaceScreenSubscriptions('portfolio', {});

    expect(service.subscribedSymbolsForDiagnostics, isEmpty);

    manager.switchTab('dashboard', {'NIFTY', 'BANKNIFTY'});
    expect(
      service.subscribedSymbolsForDiagnostics,
      {'NIFTY', 'BANKNIFTY'},
    );

    manager.replaceScreenSubscriptions('portfolio', {'RELIANCE'});
    expect(
      service.subscribedSymbolsForDiagnostics,
      {'NIFTY', 'BANKNIFTY'},
      reason: 'refreshing an invisible portfolio must not steal the live feed',
    );

    manager.detach();
    service.dispose();
  });
}
