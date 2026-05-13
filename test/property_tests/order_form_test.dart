/// Property 8: Order form field states match order type
/// Validates: Requirements 8.5, 8.6
///
/// Tests that the helper function isFieldEnabled correctly determines which
/// fields are enabled/disabled for each OrderVariety, and that the disclosed
/// quantity field visibility follows the Iceberg variety rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/models/trading_models.dart';

/// Returns whether a given field is enabled for the specified [variety].
///
/// Fields:
///   - 'price'           : enabled for Limit and SL
///   - 'triggerPrice'    : enabled for SL
///   - 'disclosedQty'    : shown/enabled only for Iceberg
bool isFieldEnabled(OrderVariety variety, String field) {
  switch (field) {
    case 'price':
      return variety == OrderVariety.limit || variety == OrderVariety.sl;
    case 'triggerPrice':
      return variety == OrderVariety.sl;
    case 'disclosedQty':
      return variety == OrderVariety.iceberg;
    default:
      return false;
  }
}

void main() {
  // ── Market variety ────────────────────────────────────────────────────────

  group('Market variety', () {
    test('price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.market, 'price'), isFalse);
    });

    test('trigger price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.market, 'triggerPrice'), isFalse);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.market, 'disclosedQty'), isFalse);
    });
  });

  // ── Limit variety ─────────────────────────────────────────────────────────

  group('Limit variety', () {
    test('price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.limit, 'price'), isTrue);
    });

    test('trigger price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.limit, 'triggerPrice'), isFalse);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.limit, 'disclosedQty'), isFalse);
    });
  });

  // ── SL variety ────────────────────────────────────────────────────────────

  group('SL variety', () {
    test('price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.sl, 'price'), isTrue);
    });

    test('trigger price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.sl, 'triggerPrice'), isTrue);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.sl, 'disclosedQty'), isFalse);
    });
  });

  // ── AMO variety ───────────────────────────────────────────────────────────

  group('AMO variety', () {
    test('price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.amo, 'price'), isFalse);
    });

    test('trigger price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.amo, 'triggerPrice'), isFalse);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.amo, 'disclosedQty'), isFalse);
    });
  });

  // ── Iceberg variety ───────────────────────────────────────────────────────

  group('Iceberg variety', () {
    test('price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.iceberg, 'price'), isFalse);
    });

    test('trigger price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.iceberg, 'triggerPrice'), isFalse);
    });

    test('disclosed quantity field is shown', () {
      expect(isFieldEnabled(OrderVariety.iceberg, 'disclosedQty'), isTrue);
    });
  });

  // ── Exhaustive property: exactly the right varieties enable each field ────

  group('Property: price field enabled only for Limit and SL', () {
    for (final variety in OrderVariety.values) {
      test('variety=${variety.name}', () {
        final expected =
            variety == OrderVariety.limit || variety == OrderVariety.sl;
        expect(isFieldEnabled(variety, 'price'), equals(expected));
      });
    }
  });

  group('Property: trigger field enabled only for SL', () {
    for (final variety in OrderVariety.values) {
      test('variety=${variety.name}', () {
        final expected = variety == OrderVariety.sl;
        expect(isFieldEnabled(variety, 'triggerPrice'), equals(expected));
      });
    }
  });

  group('Property: disclosed qty shown only for Iceberg', () {
    for (final variety in OrderVariety.values) {
      test('variety=${variety.name}', () {
        final expected = variety == OrderVariety.iceberg;
        expect(isFieldEnabled(variety, 'disclosedQty'), equals(expected));
      });
    }
  });
}
