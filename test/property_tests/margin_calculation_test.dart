/// Property 9: Required margin calculation is correct
/// Validates: Requirements 8.7, 8.8, 8.9
///
/// Tests that TradingStore.requiredMargin computes the correct margin for each
/// product type across a representative range of quantities and prices.

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/state/trading_store.dart';
import 'package:box_trading_web/models/trading_models.dart';

void main() {
  late TradingStore store;

  setUp(() {
    store = TradingStore();
  });

  // Representative values that cover typical trading scenarios
  const quantities = [1, 5, 10, 100];
  const prices = [100.0, 500.0, 1000.0, 2945.50];

  // ─── Property 1: CNC full margin ──────────────────────────────────────────

  group('Overnight product uses full margin (qty * price)', () {
    for (final qty in quantities) {
      for (final price in prices) {
        test('qty=$qty, price=$price', () {
          final margin = store.requiredMargin(
            qty,
            price,
            ProductType.overnight,
          );
          expect(margin, equals(qty * price));
        });
      }
    }
  });

  // ─── Property 1 (cont.): NRML full margin ─────────────────────────────────

  group('NRML product uses full margin (qty * price)', () {
    for (final qty in quantities) {
      for (final price in prices) {
        test('qty=$qty, price=$price', () {
          final margin = store.requiredMargin(qty, price, ProductType.nrml);
          expect(margin, equals(qty * price));
        });
      }
    }
  });

  // ─── Property 2: MIS reduced margin ───────────────────────────────────────

  group('MIS product uses 1/5 margin ((qty * price) / 5)', () {
    for (final qty in quantities) {
      for (final price in prices) {
        test('qty=$qty, price=$price', () {
          final margin = store.requiredMargin(qty, price, ProductType.mis);
          expect(margin, closeTo((qty * price) / 5, 1e-9));
        });
      }
    }
  });

  // ─── Property 2 (cont.): MTF reduced margin ───────────────────────────────

  group('MTF product uses 1/5 margin ((qty * price) / 5)', () {
    for (final qty in quantities) {
      for (final price in prices) {
        test('qty=$qty, price=$price', () {
          final margin = store.requiredMargin(qty, price, ProductType.mtf);
          expect(margin, closeTo((qty * price) / 5, 1e-9));
        });
      }
    }
  });

  // ─── Property 3: MIS margin is always less than CNC margin ────────────────

  group('MIS margin < Overnight margin for positive qty and price', () {
    for (final qty in quantities) {
      for (final price in prices) {
        test('qty=$qty, price=$price', () {
          final misMargin = store.requiredMargin(qty, price, ProductType.mis);
          final overnightMargin = store.requiredMargin(
            qty,
            price,
            ProductType.overnight,
          );
          expect(misMargin, lessThan(overnightMargin));
        });
      }
    }
  });

  // ─── Property 4: Zero quantity gives zero margin ──────────────────────────

  group('Zero quantity gives zero margin for all product types', () {
    for (final price in prices) {
      for (final product in ProductType.values) {
        test('price=$price, product=${product.name}', () {
          final margin = store.requiredMargin(0, price, product);
          expect(margin, equals(0.0));
        });
      }
    }
  });

  // ─── Property 5: Margin scales linearly with quantity ─────────────────────

  group(
    'Margin scales linearly: requiredMargin(2*qty) == 2 * requiredMargin(qty)',
    () {
      for (final qty in quantities) {
        for (final price in prices) {
          for (final product in ProductType.values) {
            test('qty=$qty, price=$price, product=${product.name}', () {
              final single = store.requiredMargin(qty, price, product);
              final doubled = store.requiredMargin(qty * 2, price, product);
              expect(doubled, closeTo(2 * single, 1e-9));
            });
          }
        }
      }
    },
  );
}
