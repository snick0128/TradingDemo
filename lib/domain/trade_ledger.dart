// Trade Ledger domain logic.
//
// Groups raw AdminOrderRecord executions into complete trade units by FIFO
// matching BUYs with SELLs for the same (userId, symbol, product) key.
//
// P&L is derived entirely from real fill prices — no synthetic multipliers.
// Brokerage = actual chargesApplied from the order document (backend-computed);
// falls back to 0.03% of turnover per leg for pre-migration orders that lack the field.

import '../models/trading_models.dart';
import '../state/admin_store.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

enum TradeStatus { open, closed, rejected, pending }

enum TradeHealth { profit, loss, risk, large, neutral }

// ── Model ──────────────────────────────────────────────────────────────────────

class TradeLedgerEntry {
  final String id;
  final String userId;
  final String userClientId;
  final String symbol;
  final String exchange;
  final String product;
  final OrderType direction; // buy = long-initiated, sell = short-initiated
  final int quantity;

  // Entry leg
  final double entryPrice;
  final DateTime entryTime;
  final String entryOrderId;

  // Exit leg (null when position is still open)
  final double? exitPrice;
  final DateTime? exitTime;
  final String? exitOrderId;

  // Financials — all derived from real fill prices
  final double grossPnl;    // (exit - entry) * qty for long; (entry - exit) * qty for short
  final double brokerage;   // 0.03% * total turnover (both legs)
  final double netPnl;      // grossPnl - brokerage
  final double marginUsed;  // actual margin blocked (0 for closed/pending entries)

  // Meta
  final TradeStatus status;
  final TradeHealth health;
  final Duration holdingDuration;

  // Raw source orders kept for the expandable drawer
  final List<AdminOrderRecord> sourceOrders;

  const TradeLedgerEntry({
    required this.id,
    required this.userId,
    required this.userClientId,
    required this.symbol,
    required this.exchange,
    required this.product,
    required this.direction,
    required this.quantity,
    required this.entryPrice,
    required this.entryTime,
    required this.entryOrderId,
    this.exitPrice,
    this.exitTime,
    this.exitOrderId,
    required this.grossPnl,
    required this.brokerage,
    required this.netPnl,
    this.marginUsed = 0.0,
    required this.status,
    required this.health,
    required this.holdingDuration,
    required this.sourceOrders,
  });

  double get entryValue => entryPrice * quantity;
  double get exitValue  => (exitPrice ?? 0.0) * quantity;

  // Sort key: use exit time when closed so recently-closed trades surface first.
  DateTime get sortTime => exitTime ?? entryTime;

  // ── Factories ────────────────────────────────────────────────────────────────

  static TradeLedgerEntry pending(AdminOrderRecord o) {
    return TradeLedgerEntry(
      id: 'pend_${o.id}',
      userId: o.userId,
      userClientId: o.userClientId,
      symbol: o.symbol,
      exchange: o.exchange,
      product: o.product,
      direction: o.type,
      quantity: o.quantity,
      entryPrice: o.price,
      entryTime: o.dateTime,
      entryOrderId: o.id,
      grossPnl: 0,
      brokerage: 0,
      netPnl: 0,
      status: TradeStatus.pending,
      health: TradeHealth.neutral,
      holdingDuration: Duration.zero,
      sourceOrders: [o],
    );
  }

  static TradeLedgerEntry rejected(AdminOrderRecord o) {
    return TradeLedgerEntry(
      id: 'rej_${o.id}',
      userId: o.userId,
      userClientId: o.userClientId,
      symbol: o.symbol,
      exchange: o.exchange,
      product: o.product,
      direction: o.type,
      quantity: o.quantity,
      entryPrice: o.price,
      entryTime: o.dateTime,
      entryOrderId: o.id,
      grossPnl: 0,
      brokerage: 0,
      netPnl: 0,
      status: TradeStatus.rejected,
      health: TradeHealth.neutral,
      holdingDuration: Duration.zero,
      sourceOrders: [o],
    );
  }

  static TradeLedgerEntry openPosition(AdminOrderRecord o, {int? qty}) {
    final fillTime  = o.executedAt ?? o.dateTime;
    final fillQty   = qty ?? o.quantity;
    final duration  = _isUnknownTime(fillTime)
        ? Duration.zero
        : DateTime.now().difference(fillTime);
    final notional  = o.price * fillQty;
    // Open positions have no exit yet — no brokerage is charged until the trade closes.
    const brokerage = 0.0;
    final health    = notional > 500000 ? TradeHealth.large : TradeHealth.neutral;
    return TradeLedgerEntry(
      id: 'open_${o.id}_q$fillQty',
      userId: o.userId,
      userClientId: o.userClientId,
      symbol: o.symbol,
      exchange: o.exchange,
      product: o.product,
      direction: o.type,
      quantity: fillQty,
      entryPrice: o.price,
      entryTime: fillTime,
      entryOrderId: o.id,
      grossPnl: 0,
      brokerage: brokerage,
      netPnl: 0,
      marginUsed: o.marginUsed,
      status: TradeStatus.open,
      health: health,
      holdingDuration: duration,
      sourceOrders: [o],
    );
  }

  static TradeLedgerEntry closedTrade({
    required AdminOrderRecord entry,
    required AdminOrderRecord exit,
    int? matchQty,
  }) {
    final isLong = entry.type == OrderType.buy;
    // Use caller-supplied match quantity (from quantity-aware FIFO) or min of both orders.
    final qty = matchQty ?? (entry.quantity < exit.quantity ? entry.quantity : exit.quantity);
    final grossPnl = isLong
        ? (exit.price - entry.price) * qty
        : (entry.price - exit.price) * qty;
    // H-03: use the actual brokerage the backend charged rather than a hardcoded rate.
    // chargesApplied is prorated by matchQty/filledQty when a partial FIFO match is used.
    // filledQty is the actually-executed qty the backend used to compute chargesApplied;
    // fall back to quantity for pre-migration orders where filledQty is zero.
    // Fall back to 0.03% of each leg's turnover for pre-migration orders that lack the field.
    final entryFilled = entry.filledQty > 0 ? entry.filledQty : entry.quantity;
    final exitFilled  = exit.filledQty  > 0 ? exit.filledQty  : exit.quantity;
    final entryBrok = (entry.chargesApplied != null && entryFilled > 0)
        ? entry.chargesApplied! * qty / entryFilled
        : entry.price * qty * 0.0003;
    final exitBrok  = (exit.chargesApplied != null && exitFilled > 0)
        ? exit.chargesApplied! * qty / exitFilled
        : exit.price * qty * 0.0003;
    final brokerage = entryBrok + exitBrok;
    final netPnl    = grossPnl - brokerage;
    final entryFillTime = entry.executedAt ?? entry.dateTime;
    final exitFillTime  = exit.executedAt  ?? exit.dateTime;
    final rawDuration = (_isUnknownTime(entryFillTime) || _isUnknownTime(exitFillTime))
        ? Duration.zero
        : exitFillTime.difference(entryFillTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;
    final notional = entry.price * qty;

    TradeHealth health;
    if (notional > 1000000) {
      health = TradeHealth.large;
    } else if (netPnl > 0) {
      health = TradeHealth.profit;
    } else {
      final lossPct = notional > 0 ? (-netPnl / notional) : 0.0;
      health = lossPct > 0.03 ? TradeHealth.risk : TradeHealth.loss;
    }

    return TradeLedgerEntry(
      id: 'closed_${entry.id}_${exit.id}',
      userId: entry.userId,
      userClientId: entry.userClientId.isNotEmpty
          ? entry.userClientId
          : exit.userClientId,
      symbol: entry.symbol,
      exchange: entry.exchange,
      product: entry.product,
      direction: entry.type,
      quantity: qty,
      entryPrice: entry.price,
      entryTime: entryFillTime,
      entryOrderId: entry.id,
      exitPrice: exit.price,
      exitTime: exitFillTime,
      exitOrderId: exit.id,
      grossPnl: grossPnl,
      brokerage: brokerage,
      netPnl: netPnl,
      status: TradeStatus.closed,
      health: health,
      holdingDuration: duration,
      sourceOrders: [entry, exit],
    );
  }
}

bool _isUnknownTime(DateTime dt) => dt.year < 2000;

// ── Builder ────────────────────────────────────────────────────────────────────

/// Converts a flat list of order records into a sorted trade ledger.
///
/// Algorithm:
///   1. Rejected/cancelled → individual rejected rows.
///   2. Pending           → individual pending rows.
///   3. Executed          → group by (userId, symbol, product), then FIFO-match
///                          BUYs with SELLs. Unmatched orders become open positions.
///
/// Sort order: most recent activity first (exitTime ?? entryTime, descending).
List<TradeLedgerEntry> buildTradeLedger(
    Iterable<AdminOrderRecord> orders) {
  final result = <TradeLedgerEntry>[];

  // Step 1 — rejected / cancelled
  for (final o in orders) {
    if (o.status == OrderStatus.rejected ||
        o.status == OrderStatus.cancelled) {
      result.add(TradeLedgerEntry.rejected(o));
    }
  }

  // Step 2 — pending
  for (final o in orders) {
    if (o.status == OrderStatus.pending) {
      result.add(TradeLedgerEntry.pending(o));
    }
  }

  // Step 3 — executed: group then match.
  // Admin ISSUE 1/2: exclude 'approved' — those are still-pending limit orders that
  // haven't executed yet and carry no executedPrice, so including them produced
  // phantom closed-trade entries with wrong entry/exit prices.
  final executed = orders.where((o) =>
      o.status == OrderStatus.executed ||
      o.status == OrderStatus.partiallyExecuted).toList();

  final groups = <String, List<AdminOrderRecord>>{};
  for (final o in executed) {
    final key = '${o.userId}::${o.symbol}::${o.product}';
    groups.putIfAbsent(key, () => []).add(o);
  }

  for (final group in groups.values) {
    // Sort by actual fill time ascending (oldest first) for FIFO matching.
    // L-02: executedAt is set by the backend at execution time; dateTime (createdAt)
    // is the fallback for legacy orders created before executedAt was added. Both
    // fields are always present on current orders; the fallback is for pre-migration
    // records only and will be removed once all orders have been migrated.
    group.sort((a, b) {
      final ta = a.executedAt ?? a.dateTime;
      final tb = b.executedAt ?? b.dateTime;
      return ta.compareTo(tb);
    });

    final buys  = group.where((o) => o.type == OrderType.buy).toList();
    final sells = group.where((o) => o.type == OrderType.sell).toList();

    // Quantity-aware FIFO: each order tracks its own remaining fill qty so
    // partial closes (e.g. BUY 100 + SELL 80) produce one closed slice (80)
    // and one open remainder (20) instead of marking the whole BUY as closed.
    // Use filledQty (actually-executed qty) when available; fall back to
    // quantity (requested qty) for pre-migration orders that lack the field.
    final buyRem  = List<int>.from(buys.map((o) => o.filledQty > 0 ? o.filledQty : o.quantity));
    final sellRem = List<int>.from(sells.map((o) => o.filledQty > 0 ? o.filledQty : o.quantity));

    // Long FIFO: each BUY absorbs earliest subsequent SELL(s).
    for (int bi = 0; bi < buys.length; bi++) {
      if (buyRem[bi] <= 0) continue;
      final buyTime = buys[bi].executedAt ?? buys[bi].dateTime;
      for (int si = 0; si < sells.length; si++) {
        if (sellRem[si] <= 0) continue;
        final sellTime = sells[si].executedAt ?? sells[si].dateTime;
        if (sellTime.isBefore(buyTime)) continue;
        final mq = buyRem[bi] < sellRem[si] ? buyRem[bi] : sellRem[si];
        buyRem[bi]  -= mq;
        sellRem[si] -= mq;
        result.add(TradeLedgerEntry.closedTrade(
            entry: buys[bi], exit: sells[si], matchQty: mq));
        if (buyRem[bi] <= 0) break;
      }
    }

    // Short FIFO: remaining SELLs match earliest subsequent BUY(s).
    for (int si = 0; si < sells.length; si++) {
      if (sellRem[si] <= 0) continue;
      final sellTime = sells[si].executedAt ?? sells[si].dateTime;
      for (int bi = 0; bi < buys.length; bi++) {
        if (buyRem[bi] <= 0) continue;
        final buyTime = buys[bi].executedAt ?? buys[bi].dateTime;
        if (buyTime.isBefore(sellTime)) continue;
        final mq = sellRem[si] < buyRem[bi] ? sellRem[si] : buyRem[bi];
        sellRem[si] -= mq;
        buyRem[bi]  -= mq;
        result.add(TradeLedgerEntry.closedTrade(
            entry: sells[si], exit: buys[bi], matchQty: mq));
        if (sellRem[si] <= 0) break;
      }
    }

    // Remaining unmatched quantity → open positions.
    for (int bi = 0; bi < buys.length; bi++) {
      if (buyRem[bi] > 0) result.add(TradeLedgerEntry.openPosition(buys[bi], qty: buyRem[bi]));
    }
    for (int si = 0; si < sells.length; si++) {
      if (sellRem[si] > 0) result.add(TradeLedgerEntry.openPosition(sells[si], qty: sellRem[si]));
    }
  }

  // Most-recent activity first.
  result.sort((a, b) => b.sortTime.compareTo(a.sortTime));
  return result;
}

// ── Aggregate helpers (used by store + analytics) ─────────────────────────────

class LedgerSummary {
  final List<TradeLedgerEntry> all;

  LedgerSummary(Iterable<AdminOrderRecord> orders)
      : all = buildTradeLedger(orders);

  List<TradeLedgerEntry> get closed =>
      all.where((t) => t.status == TradeStatus.closed).toList();

  List<TradeLedgerEntry> get open =>
      all.where((t) => t.status == TradeStatus.open).toList();

  /// Total brokerage collected — real: 0.03% per leg of actual fill prices.
  double get brokerageRevenue =>
      all.fold(0.0, (s, t) => s + t.brokerage);

  /// Sum of user profits (positive net P&L trades). Zero if no closed trades.
  double get userProfitsPaid =>
      closed.where((t) => t.netPnl > 0).fold(0.0, (s, t) => s + t.netPnl);

  /// Sum of user losses (absolute). Zero if no closed trades.
  double get userLossesIncurred =>
      closed.where((t) => t.netPnl < 0).fold(0.0, (s, t) => s + t.netPnl.abs());

  /// Net admin P&L = brokerage collected − user profits paid.
  /// (Admin keeps brokerage; profits paid out come from the pool.)
  double get netAdminPnl => brokerageRevenue - userProfitsPaid;

  /// Win rate over closed trades only.
  double get winRate {
    if (closed.isEmpty) return 0.0;
    return closed.where((t) => t.netPnl > 0).length / closed.length;
  }

  /// Real P&L per user (userId → netPnl sum of closed trades).
  Map<String, double> get pnlByUser {
    final m = <String, double>{};
    for (final t in closed) {
      m[t.userId] = (m[t.userId] ?? 0) + t.netPnl;
    }
    return m;
  }

  /// Real P&L per symbol (symbol → netPnl sum of closed trades).
  Map<String, double> get pnlBySymbol {
    final m = <String, double>{};
    for (final t in closed) {
      m[t.symbol] = (m[t.symbol] ?? 0) + t.netPnl;
    }
    return m;
  }

  /// Trade count per exchange.
  Map<String, int> get countByExchange {
    final m = <String, int>{};
    for (final t in all) {
      final ex = t.exchange.isEmpty ? 'NSE' : t.exchange;
      m[ex] = (m[ex] ?? 0) + 1;
    }
    return m;
  }

  /// Daily brokerage revenue (date → brokerage sum).
  Map<DateTime, double> get dailyBrokerage {
    final m = <DateTime, double>{};
    for (final t in all) {
      if (t.brokerage == 0) continue;
      final d = DateTime(t.entryTime.year, t.entryTime.month, t.entryTime.day);
      m[d] = (m[d] ?? 0) + t.brokerage;
    }
    return m;
  }

  /// Daily net admin P&L (date → netAdminPnl contribution).
  Map<DateTime, double> get dailyAdminPnl {
    final m = <DateTime, double>{};
    for (final t in closed) {
      final d = DateTime(t.entryTime.year, t.entryTime.month, t.entryTime.day);
      // Admin earns brokerage; pays out user profit.
      final contribution = t.brokerage - (t.netPnl > 0 ? t.netPnl : 0.0);
      m[d] = (m[d] ?? 0) + contribution;
    }
    return m;
  }

  /// Cumulative equity curve from daily admin P&L.
  List<({DateTime date, double cumulative})> get equityCurve {
    final byDay = dailyAdminPnl;
    if (byDay.isEmpty) return [];
    final days = byDay.keys.toList()..sort();
    var cum = 0.0;
    return [
      for (final d in days)
        (date: d, cumulative: cum += byDay[d]!),
    ];
  }

  /// Traded volume per hour (0–23).
  Map<int, double> get volumeByHour {
    final m = <int, double>{};
    for (final t in all) {
      if (t.status == TradeStatus.closed || t.status == TradeStatus.open) {
        m[t.entryTime.hour] =
            (m[t.entryTime.hour] ?? 0) + t.entryValue;
      }
    }
    return m;
  }
}
