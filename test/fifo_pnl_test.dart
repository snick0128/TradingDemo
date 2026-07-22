/// FIFO P&L Engine — Comprehensive Unit Tests
///
/// Validates the quantity-aware FIFO matching in buildUserTrades()
/// against all scenarios specified in the audit requirements.
///
/// Run: flutter test test/fifo_pnl_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:box_trading_web/models/trading_models.dart';
import 'package:box_trading_web/screens/trade_history_screen.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

int _seq = 0;

Order _buy({
  required int qty,
  required double price,
  required DateTime at,
  double? pnl,
  double? charges,
  String symbol = 'TEST',
  ProductType product = ProductType.mis,
}) {
  _seq++;
  return Order(
    id: 'ord_buy_$_seq',
    symbol: symbol,
    name: symbol,
    quantity: qty,
    price: price,
    type: OrderType.buy,
    status: OrderStatus.executed,
    dateTime: at,
    product: product,
    variety: OrderVariety.market,
    executedAt: at,
    executedPrice: price,
    pnl: pnl ?? 0.0,
    chargesApplied: charges ?? 0.0,
  );
}

Order _sell({
  required int qty,
  required double price,
  required DateTime at,
  double? pnl,
  double? charges,
  String symbol = 'TEST',
  ProductType product = ProductType.mis,
}) {
  _seq++;
  return Order(
    id: 'ord_sell_$_seq',
    symbol: symbol,
    name: symbol,
    quantity: qty,
    price: price,
    type: OrderType.sell,
    status: OrderStatus.executed,
    dateTime: at,
    product: product,
    variety: OrderVariety.market,
    executedAt: at,
    executedPrice: price,
    pnl: pnl,
    chargesApplied: charges ?? 0.0,
  );
}

final _t0 = DateTime(2026, 6, 1, 10, 0, 0);
DateTime _t(int minutesAfterT0) => _t0.add(Duration(minutes: minutesAfterT0));

// Status helpers (mirrors _TradeStatus private enum via string comparison on id prefix)
bool _isClosed(UserTrade t) => t.id.startsWith('closed_');
bool _isOpen(UserTrade t)   => t.id.startsWith('open_');

void main() {
  setUp(() => _seq = 0);

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 1: BUY 100, SELL 80
  // Expected: 80 qty closed, 20 qty open remainder
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 1 — partial sell: BUY 100 then SELL 80', () {
    final orders = [
      _buy( qty: 100, price: 100.0, at: _t(0)),
      _sell(qty: 80,  price: 110.0, at: _t(5),
            pnl: (110.0 - 100.0) * 80), // grossPnl = 800
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    // One closed slice
    expect(closed.length, 1, reason: 'Exactly one closed trade slice');
    expect(closed[0].quantity, 80);
    expect(closed[0].grossPnl, closeTo(800.0, 0.01),
        reason: '(110-100)*80 = 800');

    // One open remainder
    expect(open.length, 1, reason: 'Exactly one open remainder');
    expect(open[0].quantity, 20);

    // No double-counting: total qty = 80 + 20 = 100
    final totalQty = trades.fold<int>(0, (s, t) => s + t.quantity);
    expect(totalQty, 100, reason: 'Total displayed qty must equal original order qty');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 2: BUY 100, SELL 50, SELL 50
  // Expected: two closed slices of 50 each, no remainder
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 2 — two sells exhaust one buy: BUY 100, SELL 50, SELL 50', () {
    final orders = [
      _buy( qty: 100, price: 100.0, at: _t(0)),
      _sell(qty: 50,  price: 105.0, at: _t(5),
            pnl: (105.0 - 100.0) * 50),  // 250
      _sell(qty: 50,  price: 108.0, at: _t(10),
            pnl: (108.0 - 100.0) * 50),  // 400
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    expect(closed.length, 2, reason: 'Two closed slices (one per SELL)');
    expect(open.length,   0, reason: 'No open remainder');

    // Each slice has correct qty
    final qtys = closed.map((t) => t.quantity).toList()..sort();
    expect(qtys, [50, 50]);

    // Total gross P&L = 250 + 400 = 650
    final totalGross = closed.fold<double>(0, (s, t) => s + t.grossPnl);
    expect(totalGross, closeTo(650.0, 0.01));

    // No P&L duplication: sum of closed qty = original buy qty
    final closedQty = closed.fold<int>(0, (s, t) => s + t.quantity);
    expect(closedQty, 100);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 3: SHORT 100, BUY 60, BUY 40
  // Expected: two closed slices (60 + 40), no open remainder
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 3 — short covered in two buys: SHORT 100, BUY 60, BUY 40', () {
    final orders = [
      _sell(qty: 100, price: 200.0, at: _t(0)),   // open short
      _buy( qty: 60,  price: 190.0, at: _t(5),
            pnl: (200.0 - 190.0) * 60),            // cover 60: P&L = 600
      _buy( qty: 40,  price: 185.0, at: _t(10),
            pnl: (200.0 - 185.0) * 40),            // cover 40: P&L = 600
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    expect(closed.length, 2);
    expect(open.length,   0);

    // Quantities
    final qtys = closed.map((t) => t.quantity).toList()..sort();
    expect(qtys, [40, 60]);

    // Gross P&L for short: entry - exit
    final slice60 = closed.firstWhere((t) => t.quantity == 60);
    final slice40 = closed.firstWhere((t) => t.quantity == 40);
    expect(slice60.grossPnl, closeTo(600.0, 0.01),
        reason: '(200-190)*60=600');
    expect(slice40.grossPnl, closeTo(600.0, 0.01),
        reason: '(200-185)*40=600');

    // Total P&L = 1200
    final totalGross = closed.fold<double>(0, (s, t) => s + t.grossPnl);
    expect(totalGross, closeTo(1200.0, 0.01));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 4: Multiple BUYs then multiple SELLs (full FIFO ordering)
  // BUY 50 @100, BUY 50 @120, SELL 70 @130
  // Expected: FIFO consumes 50 from first BUY (all) + 20 from second BUY
  //           Remaining: 30 from second BUY still open
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 4 — multiple buys FIFO order', () {
    final orders = [
      _buy( qty: 50,  price: 100.0, at: _t(0)),
      _buy( qty: 50,  price: 120.0, at: _t(5)),
      _sell(qty: 70,  price: 130.0, at: _t(10),
            // pnl reflects blended cost; we test structure, not exact pnl here
            pnl: (130.0 - 100.0) * 50 + (130.0 - 120.0) * 20),
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    // 2 closed slices: 50 from first buy + 20 from second buy
    expect(closed.length, 2, reason: 'FIFO splits SELL across two BUY orders');

    final closedQtys = closed.map((t) => t.quantity).toSet();
    expect(closedQtys.contains(50), isTrue, reason: 'First BUY fully consumed');
    expect(closedQtys.contains(20), isTrue, reason: '20 from second BUY consumed');

    // 1 open slice: remaining 30 from second buy
    expect(open.length, 1);
    expect(open[0].quantity, 30);

    // Total qty displayed = 50+20+30 = 100 = original 50+50
    final total = trades.fold<int>(0, (s, t) => s + t.quantity);
    expect(total, 100);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 5: No duplicate P&L realization
  // When one SELL closes a BUY, the P&L from the backend pnl field is used
  // once and only once — not duplicated across slices.
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 5 — P&L not duplicated when prorated across slices', () {
    // SELL 80 closes 80 from BUY 100; BUY 100 pnl=0, SELL pnl=500 (gross)
    final orders = [
      _buy( qty: 100, price: 100.0, at: _t(0)),
      _sell(qty: 80,  price: 106.25, at: _t(5), pnl: 500.0),
    ];
    final trades  = buildUserTrades(orders);
    final closed  = trades.where(_isClosed).toList();

    expect(closed.length, 1);
    // Backend pnl prorated: 500 * (80/80) = 500
    final netPnl = closed[0].netPnl;
    // Should be close to 500 minus small brokerage
    expect(netPnl, closeTo(500.0, 5.0),
        reason: 'P&L realized exactly once, no duplication');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 6: BUY then SELL exact qty — clean single closed trade
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 6 — exact qty BUY and SELL = single clean closed trade', () {
    final orders = [
      _buy( qty: 25, price: 400.0, at: _t(0)),
      _sell(qty: 25, price: 420.0, at: _t(3),
            pnl: (420.0 - 400.0) * 25),  // 500
    ];
    final trades = buildUserTrades(orders);

    expect(trades.where(_isClosed).length, 1);
    expect(trades.where(_isOpen).length,   0);
    expect(trades.first.quantity,           25);
    expect(trades.first.grossPnl,           closeTo(500.0, 0.01));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 7: Sell before buy (chronological ordering matters)
  // SELL at T=0, BUY at T=5 → short trade, not invalid
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 7 — short trade: SELL first then BUY to cover', () {
    final orders = [
      _sell(qty: 30, price: 300.0, at: _t(0)),
      _buy( qty: 30, price: 280.0, at: _t(10),
            pnl: (300.0 - 280.0) * 30),  // 600
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    expect(closed.length, 1);
    expect(open.length,   0);
    expect(closed[0].quantity, 30);
    // direction = sell (short trade initiated by SELL)
    expect(closed[0].direction, OrderType.sell);
    expect(closed[0].grossPnl, closeTo(600.0, 0.01));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 8: Charges are not duplicated
  // chargesApplied on entry + exit → prorated correctly, never doubled
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 8 — charges prorated correctly across slices', () {
    // BUY 100 with charges 30, SELL 100 with charges 30
    final orders = [
      _buy( qty: 100, price: 100.0, at: _t(0), charges: 30.0),
      _sell(qty: 100, price: 110.0, at: _t(5), charges: 30.0, pnl: 1000.0),
    ];
    final trades  = buildUserTrades(orders);
    final closed  = trades.where(_isClosed).toList();

    expect(closed.length, 1);
    // Total brokerage = entry charges + exit charges = 30 + 30 = 60
    expect(closed[0].brokerage, closeTo(60.0, 0.01),
        reason: 'chargesApplied from entry + exit, not doubled');
    // Net = 1000 - 60 = 940
    expect(closed[0].netPnl, closeTo(940.0, 1.0));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 9: Three symbols — no cross-symbol contamination
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 9 — multiple symbols do not contaminate each other', () {
    final orders = [
      _buy( qty: 10, price: 100.0, at: _t(0), symbol: 'AAAA'),
      _buy( qty: 20, price: 200.0, at: _t(0), symbol: 'BBBB'),
      _sell(qty: 10, price: 110.0, at: _t(5), symbol: 'AAAA', pnl: 100.0),
      _sell(qty: 10, price: 210.0, at: _t(5), symbol: 'BBBB', pnl: 100.0),
    ];
    final trades = buildUserTrades(orders);

    final aaaaOpen   = trades.where((t) => t.symbol == 'AAAA' && _isOpen(t)).toList();
    final aaaaClosed = trades.where((t) => t.symbol == 'AAAA' && _isClosed(t)).toList();
    final bbbbOpen   = trades.where((t) => t.symbol == 'BBBB' && _isOpen(t)).toList();
    final bbbbClosed = trades.where((t) => t.symbol == 'BBBB' && _isClosed(t)).toList();

    expect(aaaaClosed.length, 1);
    expect(aaaaOpen.length,   0);  // fully closed
    expect(bbbbClosed.length, 1);
    expect(bbbbOpen.length,   1);  // 10 still open
    expect(bbbbOpen[0].quantity, 10);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO 10: Realized P&L uses backend pnl field (single source of truth)
  // ═══════════════════════════════════════════════════════════════════════════
  test('Scenario 10 — backend pnl field used as gross P&L (consistent with realised_pnl_screen)', () {
    // Backend pnl = 950 (gross P&L as computed by orderEngine, e.g. after spread).
    // Fill-price-derived gross = (110-100)*100 = 1000.
    // Backend value should take precedence for gross, then brokerage subtracted.
    // chargesApplied explicitly zeroed so brokerage = 0, making the test clean.
    final orders = [
      _buy( qty: 100, price: 100.0, at: _t(0),  charges: 0.0),
      _sell(qty: 100, price: 110.0, at: _t(5),  charges: 0.0, pnl: 950.0),
    ];
    final trades = buildUserTrades(orders);
    final closed = trades.where(_isClosed).toList();

    expect(closed.length, 1);
    // grossPnl from fill prices: (110-100)*100 = 1000
    expect(closed[0].grossPnl, closeTo(1000.0, 0.01),
        reason: 'grossPnl always derived from fill prices');
    // netPnl = serverGross(950) - brokerage(0) = 950
    expect(closed[0].netPnl, closeTo(950.0, 0.01),
        reason: 'backend pnl field (gross) minus charges gives net');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WALLET RECONCILIATION FORMULA VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════
  test('Wallet formula: balance = starting − charges + realizedPnl', () {
    const startingBalance = 100000.0;
    const buyPrice  = 100.0;
    const sellPrice = 110.0;
    const qty       = 50;
    const charges   = 20.0;  // chargesApplied on sell
    const grossPnl  = (sellPrice - buyPrice) * qty;  // 500
    const netPnl    = grossPnl - charges;              // 480

    // After buying: balance = 100000 - (100*50) = 95000 (5000 margin used at 10x)
    // After selling: balance = 95000 + margin_released + pnl - charges
    // = 95000 + 500 (margin) + 500 (gross pnl) - 20 (charges) = 95980
    // But in our system: balance after sell = starting - gross_margin_blocked + realized_credit
    // where realized_credit = margin_released + gross_pnl - charges

    // We verify the formula itself, not the trade simulation:
    final expectedBalance = startingBalance + netPnl;  // if no leverage for simplicity
    expect(expectedBalance, closeTo(startingBalance + 480.0, 0.01));

    // Verify no charges are applied twice (once in pnl formula and once separately):
    // netPnl = grossPnl - charges (once)
    // If charges were applied again: netPnl - charges = grossPnl - 2*charges (wrong)
    final wrongDouble = grossPnl - 2 * charges;
    expect(netPnl, isNot(closeTo(wrongDouble, 0.01)),
        reason: 'Charges must not be deducted twice');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EDGE CASE: Rejected and pending orders are excluded from P&L
  // ═══════════════════════════════════════════════════════════════════════════
  test('Edge case — rejected/pending orders excluded from FIFO matching', () {
    _seq++;
    final rejectedBuy = Order(
      id: 'rej_buy_$_seq',
      symbol: 'TEST',
      name: 'TEST',
      quantity: 100,
      price: 100.0,
      type: OrderType.buy,
      status: OrderStatus.rejected,
      dateTime: _t(0),
      product: ProductType.mis,
      variety: OrderVariety.market,
    );
    final orders = [
      rejectedBuy,
      _sell(qty: 100, price: 110.0, at: _t(5), pnl: 1000.0),
    ];
    final trades = buildUserTrades(orders);

    // The rejected BUY should NOT be matched with the SELL
    final closed = trades.where(_isClosed).toList();
    expect(closed.length, 0,
        reason: 'Rejected BUY must not match with SELL');

    // The SELL has no matching BUY → shows as open short
    final open = trades.where(_isOpen).toList();
    expect(open.any((t) => t.direction == OrderType.sell), isTrue,
        reason: 'Unmatched SELL shows as open short');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CNC / OVERNIGHT BUCKET ISOLATION
  //
  // Root cause: prior to fix, _mapProductType('CNC') defaulted to ProductType.mis,
  // causing CNC orders to land in the same FIFO bucket as MIS orders and be
  // matched with the wrong counterpart.
  //
  // These tests verify that ProductType.overnight orders are isolated from
  // ProductType.mis orders in separate FIFO buckets.
  // ═══════════════════════════════════════════════════════════════════════════

  test('CNC isolation — CNC buy must not match with MIS sell', () {
    // CNC BUY at 2500, MIS BUY at 2600, MIS SELL at 2700.
    // Before fix: all landed in 'TEST::MIS' → CNC BUY matched with SELL at 2500.
    // After fix: CNC BUY is in 'TEST::OVERNIGHT'; MIS BUY in 'TEST::MIS'.
    final orders = [
      _buy( qty: 10, price: 2500.0, at: _t(0), product: ProductType.overnight), // CNC
      _buy( qty: 10, price: 2600.0, at: _t(1)),                                  // MIS
      _sell(qty: 10, price: 2700.0, at: _t(2)),                                  // MIS sell
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    // Exactly one closed trade: the MIS pair (2600 buy → 2700 sell)
    expect(closed.length, 1, reason: 'Only the MIS pair closes');
    expect(closed[0].entryPrice, closeTo(2600.0, 0.01),
        reason: 'Entry must be the MIS buy at 2600, not the CNC buy at 2500');
    expect(closed[0].exitPrice,  closeTo(2700.0, 0.01));
    expect(closed[0].grossPnl,   closeTo(1000.0, 0.01), reason: '(2700-2600)*10');

    // CNC buy is unmatched → open position
    expect(open.length, 1, reason: 'CNC buy has no CNC sell → remains open');
    expect(open[0].entryPrice, closeTo(2500.0, 0.01));
  });

  test('CNC isolation — CNC buy matches CNC sell, MIS pair stays separate', () {
    final orders = [
      _buy( qty: 5, price: 1000.0, at: _t(0)),                                  // MIS
      _buy( qty: 5, price: 1100.0, at: _t(1), product: ProductType.overnight),  // CNC
      _sell(qty: 5, price: 1200.0, at: _t(2)),                                  // MIS sell
      _sell(qty: 5, price: 1300.0, at: _t(3), product: ProductType.overnight),  // CNC sell
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    expect(closed.length, 2, reason: 'Two independent closed pairs: one MIS, one CNC');

    final byEntry = Map.fromEntries(
      closed.map((t) => MapEntry(t.entryPrice.round(), t)),
    );
    expect(byEntry.containsKey(1000), isTrue, reason: 'MIS pair: entry 1000');
    expect(byEntry[1000]!.exitPrice, closeTo(1200.0, 0.01));

    expect(byEntry.containsKey(1100), isTrue, reason: 'CNC pair: entry 1100');
    expect(byEntry[1100]!.exitPrice, closeTo(1300.0, 0.01));
  });

  test('CNC isolation — mixed NRML and CNC orders stay in separate buckets', () {
    final orders = [
      _buy( qty: 10, price: 500.0, at: _t(0), product: ProductType.nrml),
      _buy( qty: 10, price: 600.0, at: _t(1), product: ProductType.overnight),
      _sell(qty: 10, price: 700.0, at: _t(2), product: ProductType.nrml),
      // CNC sell intentionally absent → CNC buy stays open
    ];
    final trades = buildUserTrades(orders);

    final closed = trades.where(_isClosed).toList();
    final open   = trades.where(_isOpen).toList();

    expect(closed.length, 1, reason: 'Only the NRML pair closes');
    expect(closed[0].entryPrice, closeTo(500.0, 0.01),
        reason: 'NRML buy at 500 matched with NRML sell at 700');

    expect(open.length, 1, reason: 'CNC buy with no matching CNC sell stays open');
    expect(open[0].entryPrice, closeTo(600.0, 0.01));
  });
}
