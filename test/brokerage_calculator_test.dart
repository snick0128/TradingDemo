/// Property 10: Brokerage calculation is deterministic
/// Validates: Requirements 18.2, 18.3
///
/// Tests that calling BrokerageCalculator.compute twice with the same inputs
/// always returns identical results (pure function, no side effects).

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/services/brokerage_calculator.dart';
import 'package:box_trading_web/models/trading_models.dart';

void main() {
  // Representative trade values covering small, medium, and large trades
  const tradeValues = [100.0, 1000.0, 10000.0, 50000.0, 100000.0, 500000.0];
  const productTypes = ProductType.values;

  group('Property 10: Brokerage calculation is deterministic', () {
    for (final tradeValue in tradeValues) {
      for (final productType in productTypes) {
        test(
          'compute($tradeValue, ${productType.name}) returns same result twice',
          () {
            final result1 = BrokerageCalculator.compute(
              tradeValue,
              productType,
            );
            final result2 = BrokerageCalculator.compute(
              tradeValue,
              productType,
            );

            expect(result1.tradeValue, equals(result2.tradeValue));
            expect(result1.brokerage, equals(result2.brokerage));
            expect(result1.stt, equals(result2.stt));
            expect(result1.gst, equals(result2.gst));
            expect(result1.exchangeCharges, equals(result2.exchangeCharges));
            expect(result1.totalCharges, equals(result2.totalCharges));
            expect(result1.netPnl, equals(result2.netPnl));
          },
        );
      }
    }
  });

  group('Brokerage calculation correctness', () {
    test('NRML brokerage is min(20, 0.03% of tradeValue)', () {
      // For small trade: 0.03% of 1000 = 0.3, which is < 20
      final small = BrokerageCalculator.compute(1000.0, ProductType.nrml);
      expect(small.brokerage, closeTo(0.3, 1e-9));

      // For large trade: 0.03% of 100000 = 30, capped at 20
      final large = BrokerageCalculator.compute(100000.0, ProductType.nrml);
      expect(large.brokerage, equals(20.0));
    });

    test('MIS brokerage is always ₹20 flat', () {
      for (final tv in tradeValues) {
        final result = BrokerageCalculator.compute(tv, ProductType.mis);
        expect(result.brokerage, equals(20.0));
      }
    });

    test('Overnight brokerage is always ₹20 flat', () {
      for (final tv in tradeValues) {
        final result = BrokerageCalculator.compute(tv, ProductType.overnight);
        expect(result.brokerage, equals(20.0));
      }
    });

    test('STT is 0.1% of trade value', () {
      final result = BrokerageCalculator.compute(100000.0, ProductType.nrml);
      expect(result.stt, closeTo(100.0, 1e-9));
    });

    test('GST is 18% of brokerage', () {
      final result = BrokerageCalculator.compute(100000.0, ProductType.mis);
      expect(result.gst, closeTo(result.brokerage * 0.18, 1e-9));
    });

    test('Exchange charges are 0.00325% of trade value', () {
      final result = BrokerageCalculator.compute(100000.0, ProductType.nrml);
      expect(result.exchangeCharges, closeTo(3.25, 1e-9));
    });

    test('Total charges equals sum of all components', () {
      for (final tv in tradeValues) {
        for (final pt in productTypes) {
          final r = BrokerageCalculator.compute(tv, pt);
          final expected = r.brokerage + r.stt + r.gst + r.exchangeCharges;
          expect(r.totalCharges, closeTo(expected, 1e-9));
        }
      }
    });

    test('Net P&L equals tradeValue minus totalCharges', () {
      for (final tv in tradeValues) {
        for (final pt in productTypes) {
          final r = BrokerageCalculator.compute(tv, pt);
          expect(r.netPnl, closeTo(tv - r.totalCharges, 1e-9));
        }
      }
    });

    test('Zero or negative trade value returns all zeros', () {
      final zero = BrokerageCalculator.compute(0, ProductType.nrml);
      expect(zero.totalCharges, equals(0.0));
      expect(zero.netPnl, equals(0.0));

      final negative = BrokerageCalculator.compute(-100, ProductType.mis);
      expect(negative.totalCharges, equals(0.0));
    });
  });
}
