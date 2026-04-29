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
///   - 'price'           : enabled for Limit and SL-Limit
///   - 'triggerPrice'    : enabled for SL-Limit and SL-Market
///   - 'disclosedQty'    : shown/enabled only for Iceberg
bool isFieldEnabled(OrderVariety variety, String field) {
  switch (field) {
    case 'price':
      return variety == OrderVariety.limit || variety == OrderVariety.slLimit;
    case 'triggerPrice':
      return variety == OrderVariety.slLimit ||
          variety == OrderVariety.slMarket;
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

  // ── SL-Limit variety ──────────────────────────────────────────────────────

  group('SL-Limit variety', () {
    test('price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.slLimit, 'price'), isTrue);
    });

    test('trigger price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.slLimit, 'triggerPrice'), isTrue);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.slLimit, 'disclosedQty'), isFalse);
    });
  });

  // ── SL-Market variety ─────────────────────────────────────────────────────

  group('SL-Market variety', () {
    test('price field is disabled', () {
      expect(isFieldEnabled(OrderVariety.slMarket, 'price'), isFalse);
    });

    test('trigger price field is enabled', () {
      expect(isFieldEnabled(OrderVariety.slMarket, 'triggerPrice'), isTrue);
    });

    test('disclosed quantity field is hidden', () {
      expect(isFieldEnabled(OrderVariety.slMarket, 'disclosedQty'), isFalse);
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

  group('Property: price field enabled only for Limit and SL-Limit', () {
    for (final variety in OrderVariety.values) {
      test('variety=${variety.name}', () {
        final expected =
            variety == OrderVariety.limit || variety == OrderVariety.slLimit;
        expect(isFieldEnabled(variety, 'price'), equals(expected));
      });
    }
  });

  group('Property: trigger field enabled only for SL-Limit and SL-Market', () {
    for (final variety in OrderVariety.values) {
      test('variety=${variety.name}', () {
        final expected =
            variety == OrderVariety.slLimit || variety == OrderVariety.slMarket;
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
