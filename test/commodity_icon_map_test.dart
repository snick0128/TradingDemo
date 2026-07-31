/// CommodityIconMap: maps MCX commodity tickers to bundled PNG assets.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/services/commodity_icon_map.dart';

void main() {
  group('CommodityIconMap.assetFor', () {
    const expected = {
      'GOLD': 'assets/images/gold.png',
      'SILVER': 'assets/images/silver.png',
      'CRUDEOIL': 'assets/images/crudeoil.png',
      'NATURALGAS': 'assets/images/naturalgas.png',
      'COPPER': 'assets/images/copper.png',
      'ZINC': 'assets/images/zinc.png',
      'LEAD': 'assets/images/lead.png',
      'ALUMINIUM': 'assets/images/aluminium.png',
      'NICKEL': 'assets/images/nickel.png',
      'COTTON': 'assets/images/cotton.png',
    };

    expected.forEach((ticker, asset) {
      test('$ticker -> $asset', () {
        expect(CommodityIconMap.assetFor(ticker), asset);
      });
    });

    test('is case-insensitive', () {
      expect(CommodityIconMap.assetFor('gold'), 'assets/images/gold.png');
    });

    test('returns null for a listed equity ticker', () {
      expect(CommodityIconMap.assetFor('RELIANCE'), isNull);
    });

    test('returns null for an index ticker', () {
      expect(CommodityIconMap.assetFor('NIFTY'), isNull);
    });

    test('returns null for a commodity variant not tracked by this app', () {
      // GOLDM/GOLDPETAL etc. are explicitly excluded in symbols.js —
      // only the base MCX_DEFINITIONS prefixes should resolve.
      expect(CommodityIconMap.assetFor('GOLDM'), isNull);
    });
  });
}
