/// Property 7: Price change color coding is consistent
/// Validates: Requirements 5.8, 34.4
///
/// Tests that priceChangeColor returns AppColors.success for non-negative
/// change percentages and AppColors.danger for negative ones.
/// Zero is treated as non-negative (success/green) — this matches the
/// convention used throughout the app where `isPositive` is `changePercentage >= 0`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box_trading_web/screens/market_watch_screen.dart';
import 'package:box_trading_web/theme.dart';

void main() {
  // ─── Property 7: Positive change → success color ──────────────────────────

  group('Positive change% maps to AppColors.success', () {
    const positiveValues = [0.01, 0.5, 1.0, 2.5, 5.0, 10.0, 50.0, 100.0];

    for (final value in positiveValues) {
      test('changePercentage=$value → success', () {
        final color = priceChangeColor(value);
        expect(color, equals(AppColors.success));
      });
    }
  });

  // ─── Property 7: Negative change → danger color ───────────────────────────

  group('Negative change% maps to AppColors.danger', () {
    const negativeValues = [
      -0.01,
      -0.5,
      -1.0,
      -2.5,
      -5.0,
      -10.0,
      -50.0,
      -100.0,
    ];

    for (final value in negativeValues) {
      test('changePercentage=$value → danger', () {
        final color = priceChangeColor(value);
        expect(color, equals(AppColors.danger));
      });
    }
  });

  // ─── Property 7: Zero change → success color (documented choice) ──────────
  // Zero is treated as non-negative (green) consistent with Stock.isPositive
  // which uses `changePercentage >= 0`.

  test('changePercentage=0.0 → success (zero treated as non-negative)', () {
    final color = priceChangeColor(0.0);
    expect(color, equals(AppColors.success));
  });

  // ─── Property 7: Color is always one of the two expected values ───────────

  group('Color is always either success or danger', () {
    const allValues = [-100.0, -10.0, -1.0, -0.01, 0.0, 0.01, 1.0, 10.0, 100.0];

    for (final value in allValues) {
      test('changePercentage=$value is success or danger', () {
        final color = priceChangeColor(value);
        expect(
          color == AppColors.success || color == AppColors.danger,
          isTrue,
          reason: 'Expected success or danger but got $color for value $value',
        );
      });
    }
  });

  // ─── Property 7: Consistency — same input always gives same output ─────────

  group('Color coding is deterministic (same input → same output)', () {
    const testValues = [-5.0, -1.0, 0.0, 1.0, 5.0];

    for (final value in testValues) {
      test('changePercentage=$value is deterministic', () {
        final color1 = priceChangeColor(value);
        final color2 = priceChangeColor(value);
        expect(color1, equals(color2));
      });
    }
  });

  // ─── Property 7: Boundary — values just above/below zero ─────────────────

  test('Very small positive value (1e-10) → success', () {
    expect(priceChangeColor(1e-10), equals(AppColors.success));
  });

  test('Very small negative value (-1e-10) → danger', () {
    expect(priceChangeColor(-1e-10), equals(AppColors.danger));
  });
}
