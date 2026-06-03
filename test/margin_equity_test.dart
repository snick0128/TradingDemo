/// Margin & Equity unit tests
///
/// Tests that availableMargin = max(0, equity − usedMargin),
/// marginShortfall = max(0, usedMargin − equity), and the
/// status classification (Healthy / Shortfall / Auto Square-Off Risk)
/// all behave correctly across the four canonical scenarios.
///
/// Test harness:
///   1. Create TradingStore (offline path — no Firebase needed).
///   2. Call placeOrder() to block margin via the transaction ledger.
///   3. Call replacePositions() to inject a position with a specific
///      currentPrice, which drives unrealizedPnl and therefore equity.
///
/// Formulas under test:
///   equity          = balance + usedMargin + runningPnL
///   availableMargin = max(0, equity − usedMargin)
///   marginShortfall = max(0, usedMargin − equity)
///   isCritical      = equity > 0 && equity ≤ safeLevelRupees

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/models/trading_models.dart';
import 'package:box_trading_web/models/platform_settings.dart';
import 'package:box_trading_web/state/trading_store.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Opens a BUY MIS position: blocks margin via the transaction ledger.
/// Returns the margin amount blocked (tradeValue / 5x leverage).
double _openMisBuy(TradingStore store, {
  required double balance,
  required int quantity,
  required double price,
}) {
  store.setOptimisticBalance(balance);
  store.placeOrder(
    symbol: 'TEST',
    quantity: quantity,
    type: OrderType.buy,
    product: ProductType.mis,
    price: price,
  );
  // margin = quantity * price / intradayLeverage (default 5x)
  return quantity * price / store.intradayLeverage;
}

/// Injects a replacement position with a specific current price,
/// which drives unrealizedPnl (and therefore runningPnL + equity).
void _setCurrentPrice(
  TradingStore store, {
  required int quantity,
  required double avgPrice,
  required double currentPrice,
}) {
  store.replacePositions([
    Position(
      symbol: 'TEST',
      name: 'Test Stock',
      product: ProductType.mis,
      quantity: quantity,
      avgPrice: avgPrice,
      currentPrice: currentPrice,
      side: OrderType.buy,
      openedAt: DateTime(2026, 6, 2),
      marginUsed: 0, // offline path reads usedMargin from transactions
    ),
  ]);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Margin & Equity — availableMargin and marginShortfall', () {

    // ── Scenario 1: Profitable position ──────────────────────────────────────
    //
    // Setup:
    //   balance   = ₹1,00,000
    //   BUY 100 shares @ ₹100 (MIS 5x) → margin = ₹2,000
    //   free cash after margin block = ₹98,000
    //   currentPrice = ₹110 → unrealizedPnl = +₹1,000
    //
    // Expected:
    //   usedMargin      = ₹2,000
    //   equity          = 98,000 + 2,000 + 1,000 = ₹1,01,000
    //   availableMargin = ₹99,000  (≥ 0, so no clamp needed)
    //   marginShortfall = ₹0

    test('profitable position — availableMargin > 0, shortfall = 0', () {
      final store = TradingStore();

      _openMisBuy(store, balance: 100000, quantity: 100, price: 100);
      _setCurrentPrice(store, quantity: 100, avgPrice: 100, currentPrice: 110);

      expect(store.usedMargin,       closeTo(2000,  1e-6));
      expect(store.equity,           closeTo(101000, 1e-6));
      expect(store.availableMargin,  closeTo(99000,  1e-6));
      expect(store.marginShortfall,  closeTo(0,      1e-6));
    });

    // ── Scenario 2: Losing position — available margin still positive ─────────
    //
    // Setup:
    //   balance   = ₹1,00,000
    //   BUY 100 @ ₹100 (MIS 5x) → margin = ₹2,000, free cash = ₹98,000
    //   currentPrice = ₹90 → unrealizedPnl = −₹1,000
    //
    // Expected:
    //   equity          = 98,000 + 2,000 − 1,000 = ₹99,000
    //   availableMargin = ₹97,000   (still positive — equity > usedMargin)
    //   marginShortfall = ₹0

    test('losing position with positive available margin — shortfall = 0', () {
      final store = TradingStore();

      _openMisBuy(store, balance: 100000, quantity: 100, price: 100);
      _setCurrentPrice(store, quantity: 100, avgPrice: 100, currentPrice: 90);

      expect(store.usedMargin,       closeTo(2000,  1e-6));
      expect(store.equity,           closeTo(99000,  1e-6));
      expect(store.availableMargin,  closeTo(97000,  1e-6));
      expect(store.marginShortfall,  closeTo(0,      1e-6));
    });

    // ── Scenario 3: Losing position — margin shortfall ────────────────────────
    //
    // Setup:
    //   balance   = ₹5,000  (small account)
    //   BUY 100 @ ₹100 (MIS 5x) → margin = ₹2,000, free cash = ₹3,000
    //   currentPrice = ₹60 → unrealizedPnl = −₹4,000
    //
    // Expected:
    //   equity          = 3,000 + 2,000 − 4,000 = ₹1,000
    //   availableMargin = max(0, 1,000 − 2,000) = ₹0   ← clamped
    //   marginShortfall = max(0, 2,000 − 1,000) = ₹1,000

    test('losing position with margin shortfall — availableMargin clamped to 0', () {
      final store = TradingStore();

      _openMisBuy(store, balance: 5000, quantity: 100, price: 100);
      _setCurrentPrice(store, quantity: 100, avgPrice: 100, currentPrice: 60);

      expect(store.usedMargin,       closeTo(2000,  1e-6));
      expect(store.equity,           closeTo(1000,  1e-6));
      expect(store.availableMargin,  closeTo(0,     1e-6));   // never negative
      expect(store.marginShortfall,  closeTo(1000,  1e-6));
    });

    // ── Scenario 4: Auto square-off threshold ─────────────────────────────────
    //
    // Setup:
    //   safeLevel = ₹500
    //   balance   = ₹5,000
    //   BUY 100 @ ₹100 (MIS 5x) → margin = ₹2,000, free cash = ₹3,000
    //   currentPrice = ₹52.5 → unrealizedPnl = −₹4,750
    //
    // Expected:
    //   equity          = 3,000 + 2,000 − 4,750 = ₹250
    //   availableMargin = ₹0
    //   marginShortfall = ₹1,750
    //   isCritical      = equity (250) > 0 AND equity (250) ≤ safeLevel (500) → true

    test('equity ≤ safe level — auto square-off threshold triggers', () {
      final store = TradingStore();
      store.updateRmsSettings(
        const PlatformRmsSettings(safeLevelRupees: 500),
      );

      _openMisBuy(store, balance: 5000, quantity: 100, price: 100);
      _setCurrentPrice(store, quantity: 100, avgPrice: 100, currentPrice: 52.5);

      expect(store.usedMargin,       closeTo(2000,  1e-6));
      expect(store.equity,           closeTo(250,   1e-6));
      expect(store.availableMargin,  closeTo(0,     1e-6));
      expect(store.marginShortfall,  closeTo(1750,  1e-6));

      // Auto square-off condition (same as isCritical in the UI)
      final safeLevel    = store.rmsSettings.safeLevelRupees;
      final equity       = store.equity;
      final isAtRisk     = equity > 0 && equity <= safeLevel;
      expect(isAtRisk, isTrue);
    });

    // ── Sanity check: equity > safeLevel is not flagged ──────────────────────

    test('equity above safe level — auto square-off does not trigger', () {
      final store = TradingStore();
      store.updateRmsSettings(
        const PlatformRmsSettings(safeLevelRupees: 500),
      );

      _openMisBuy(store, balance: 100000, quantity: 100, price: 100);
      // No position price change — equity stays at walletBalance
      // No positions replace, so runningPnL = 0 from the position added by placeOrder
      // (currentPrice = 0 → uses avgPrice fallback → unrealizedPnl = 0)

      final safeLevel = store.rmsSettings.safeLevelRupees;
      final equity    = store.equity;
      final isAtRisk  = equity > 0 && equity <= safeLevel;
      expect(isAtRisk, isFalse);
    });

  });

  // ── Pure formula checks ───────────────────────────────────────────────────
  //
  // Verify the formulas hold as pure math, independent of TradingStore wiring.

  group('Margin formulas — pure mathematical correctness', () {

    double availableMargin(double equity, double usedMargin) =>
        (equity - usedMargin).clamp(0.0, double.infinity);

    double marginShortfall(double equity, double usedMargin) =>
        (usedMargin - equity).clamp(0.0, double.infinity);

    test('availableMargin is never negative', () {
      expect(availableMargin(500, 2000), 0);
      expect(availableMargin(0, 2000), 0);
      expect(availableMargin(-100, 2000), 0);
    });

    test('marginShortfall is never negative', () {
      expect(marginShortfall(99000, 2000), 0);
      expect(marginShortfall(2000, 2000), 0);
    });

    test('availableMargin + marginShortfall = |equity - usedMargin|', () {
      // When equity > usedMargin: availableMargin = equity - usedMargin, shortfall = 0
      expect(availableMargin(99000, 2000) + marginShortfall(99000, 2000),
          closeTo(97000, 1e-9));

      // When equity < usedMargin: availableMargin = 0, shortfall = usedMargin - equity
      expect(availableMargin(1000, 2000) + marginShortfall(1000, 2000),
          closeTo(1000, 1e-9));
    });

    test('at breakeven equity = usedMargin: both are 0', () {
      expect(availableMargin(2000, 2000), 0);
      expect(marginShortfall(2000, 2000), 0);
    });
  });
}
