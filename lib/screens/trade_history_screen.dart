import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DOMAIN MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum _TradeStatus { open, closed, rejected, pending }

enum _SortOrder {
  latestFirst,
  highestProfit,
  highestLoss,
  longestDuration;

  String get label {
    switch (this) {
      case latestFirst:     return 'Latest First';
      case highestProfit:   return 'Highest Profit';
      case highestLoss:     return 'Highest Loss';
      case longestDuration: return 'Longest Duration';
    }
  }
}

class UserTrade {
  final String id;
  final String symbol;
  final String symbolName;
  final String exchange;
  final String product;
  final String variety;
  final OrderType direction;
  final int quantity;

  // Entry leg — always present
  final double entryPrice;
  final DateTime entryTime;
  final String entryOrderId;

  // Exit leg — null when position is still open
  final double? exitPrice;
  final DateTime? exitTime;
  final String? exitOrderId;

  // Financials
  final double grossPnl;
  final double brokerage;
  final double netPnl;
  final double pointsCaptured; // price movement per unit (signed)

  // Meta
  final _TradeStatus status;
  final Duration holdingDuration;
  final List<Order> sourceOrders;

  const UserTrade({
    required this.id,
    required this.symbol,
    required this.symbolName,
    required this.exchange,
    required this.product,
    required this.variety,
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
    required this.pointsCaptured,
    required this.status,
    required this.holdingDuration,
    required this.sourceOrders,
  });

  // Sort by most recent activity
  DateTime get sortTime => exitTime ?? entryTime;
  // Date bucket for grouping
  DateTime get dateKey {
    final t = sortTime;
    return DateTime(t.year, t.month, t.day);
  }
  bool get isProfitable => netPnl > 0;

  // ── Factories ────────────────────────────────────────────────────────────────

  static UserTrade _pending(Order o) => UserTrade(
    id: 'pend_${o.id}',
    symbol: o.symbol, symbolName: o.name,
    exchange: o.exchange ?? 'NSE',
    product: _productLabel(o.product), variety: _varietyLabel(o.variety),
    direction: o.type, quantity: o.quantity,
    entryPrice: o.price, entryTime: o.dateTime, entryOrderId: o.id,
    grossPnl: 0, brokerage: 0, netPnl: 0, pointsCaptured: 0,
    status: _TradeStatus.pending,
    holdingDuration: Duration.zero, sourceOrders: [o],
  );

  static UserTrade _rejected(Order o) => UserTrade(
    id: 'rej_${o.id}',
    symbol: o.symbol, symbolName: o.name,
    exchange: o.exchange ?? 'NSE',
    product: _productLabel(o.product), variety: _varietyLabel(o.variety),
    direction: o.type, quantity: o.quantity,
    entryPrice: o.price, entryTime: o.dateTime, entryOrderId: o.id,
    grossPnl: 0, brokerage: 0, netPnl: 0, pointsCaptured: 0,
    status: _TradeStatus.rejected,
    holdingDuration: Duration.zero, sourceOrders: [o],
  );

  static UserTrade _open(Order o, {int? qty}) {
    final fillTime  = o.executedAt ?? o.dateTime;
    final fillPrice = o.executedPrice ?? o.price;
    final fillQty   = qty ?? o.executedQuantity ?? o.quantity;
    final notional  = fillPrice * fillQty;
    final brok      = fillQty == (o.executedQuantity ?? o.quantity)
        ? (o.chargesApplied ?? 0.0)
        : (o.chargesApplied != null
            ? o.chargesApplied! * fillQty / (o.executedQuantity ?? o.quantity)
            : notional * 0.0003);
    final duration  = _isUnknownTime(fillTime)
        ? Duration.zero
        : DateTime.now().difference(fillTime);
    return UserTrade(
      id: 'open_${o.id}_q$fillQty',
      symbol: o.symbol, symbolName: o.name,
      exchange: o.exchange ?? 'NSE',
      product: _productLabel(o.product), variety: _varietyLabel(o.variety),
      direction: o.type, quantity: fillQty,
      entryPrice: fillPrice, entryTime: fillTime, entryOrderId: o.id,
      grossPnl: 0, brokerage: brok, netPnl: -brok, pointsCaptured: 0,
      status: _TradeStatus.open,
      holdingDuration: duration, sourceOrders: [o],
    );
  }

  static UserTrade _closed({required Order entry, required Order exit, int? qty}) {
    final entryFill = entry.executedPrice ?? entry.price;
    final exitFill  = exit.executedPrice  ?? exit.price;
    final entryTime = entry.executedAt ?? entry.dateTime;
    final exitTime  = exit.executedAt  ?? exit.dateTime;
    final isLong    = entry.type == OrderType.buy;

    // Quantity for this matched slice — may be less than the full order qty
    // when the FIFO engine splits a large order across multiple counterparts.
    final fullEntryQty = entry.executedQuantity ?? entry.quantity;
    final fullExitQty  = exit.executedQuantity  ?? exit.quantity;
    final matchQty     = qty ?? fullEntryQty;

    // Duration: always positive
    final rawDuration = exitTime.difference(entryTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;

    final points   = isLong ? (exitFill - entryFill) : (entryFill - exitFill);
    final grossPnl = points * matchQty;
    final turnover = entryFill * matchQty + exitFill * matchQty;

    // Prorate charges by the fraction of each order this slice represents.
    // Distinction: chargesApplied=null means "not provided → use fallback rate".
    //              chargesApplied=0.0 means "explicitly no charges" (e.g. paper trading).
    final entryChargesSet = entry.chargesApplied != null;
    final exitChargesSet  = exit.chargesApplied  != null;
    final entryChargesFull = entry.chargesApplied ?? 0.0;
    final exitChargesFull  = exit.chargesApplied  ?? 0.0;
    final entryBrok = entryChargesSet && fullEntryQty > 0
        ? entryChargesFull * matchQty / fullEntryQty
        : 0.0;
    final exitBrok  = exitChargesSet && fullExitQty > 0
        ? exitChargesFull  * matchQty / fullExitQty
        : (exitChargesSet ? 0.0 : turnover * 0.0003);
    final brok    = entryBrok + exitBrok;

    // Backend stores pnl = GROSS P&L (before charges) on the closing order.
    // This is the same convention as realised_pnl_screen and orderEngine.
    // Prorate by match fraction if only part of the exit order is matched.
    final serverGross = exit.pnl != null && exit.pnl != 0.0
        ? (fullExitQty > 0 ? exit.pnl! * matchQty / fullExitQty : exit.pnl!)
        : null;
    final effectiveGross = serverGross ?? grossPnl;
    final netPnl = effectiveGross - brok;

    return UserTrade(
      id: 'closed_${entry.id}_${exit.id}_q$matchQty',
      symbol: entry.symbol, symbolName: entry.name,
      exchange: entry.exchange ?? exit.exchange ?? 'NSE',
      product: _productLabel(entry.product), variety: _varietyLabel(entry.variety),
      direction: entry.type, quantity: matchQty,
      entryPrice: entryFill, entryTime: entryTime, entryOrderId: entry.id,
      exitPrice: exitFill, exitTime: exitTime, exitOrderId: exit.id,
      grossPnl: grossPnl, brokerage: brok, netPnl: netPnl, pointsCaptured: points,
      status: _TradeStatus.closed,
      holdingDuration: duration, sourceOrders: [entry, exit],
    );
  }

  static String _productLabel(ProductType p) {
    switch (p) {
      case ProductType.mis:       return 'MIS';
      case ProductType.nrml:      return 'NRML';
      case ProductType.overnight: return 'OVERNIGHT';
      case ProductType.mtf:       return 'MTF';
    }
  }

  static String _varietyLabel(OrderVariety v) {
    switch (v) {
      case OrderVariety.market:   return 'MARKET';
      case OrderVariety.limit:    return 'LIMIT';
      case OrderVariety.sl:       return 'SL';
      case OrderVariety.amo:      return 'AMO';
      case OrderVariety.iceberg:  return 'ICEBERG';
    }
  }
}

// ── Timestamp helpers ──────────────────────────────────────────────────────────

bool _isUnknownTime(DateTime dt) => dt.year < 2000;

/// Full format: "03 Jun 2026, 10:15:22 AM"
String _fmtTimestampFull(DateTime dt) {
  if (_isUnknownTime(dt)) return 'Timestamp unavailable';
  return DateFormat('dd MMM yyyy, hh:mm:ss a').format(dt);
}

/// Compact format: "10:15 AM" for table rows
String _fmtTimestampCompact(DateTime dt) {
  if (_isUnknownTime(dt)) return '—';
  return DateFormat('h:mm:ss a').format(dt);
}

// ── Date group ─────────────────────────────────────────────────────────────────

class _DateGroup {
  final DateTime date;
  final List<UserTrade> trades;
  const _DateGroup({required this.date, required this.trades});

  int get totalTrades  => trades.length;
  int get winCount     => trades.where((t) => t.status == _TradeStatus.closed && t.netPnl > 0).length;
  int get lossCount    => trades.where((t) => t.status == _TradeStatus.closed && t.netPnl < 0).length;
  double get grossPnl  => trades.fold(0.0, (s, t) => s + t.grossPnl);
  double get brokerage => trades.fold(0.0, (s, t) => s + t.brokerage);
  double get netPnl    => trades.fold(0.0, (s, t) => s + t.netPnl);
}

// ── FIFO ledger builder ────────────────────────────────────────────────────────

List<UserTrade> buildUserTrades(List<Order> orders) {
  final result = <UserTrade>[];

  // 1. Rejected / cancelled
  for (final o in orders) {
    if (o.status == OrderStatus.rejected || o.status == OrderStatus.cancelled) {
      result.add(UserTrade._rejected(o));
    }
  }

  // 2. Pending
  for (final o in orders) {
    if (o.status == OrderStatus.pending) {
      result.add(UserTrade._pending(o));
    }
  }

  // 3. Executed — FIFO match by (symbol, product)
  final executed = orders.where((o) =>
      o.status == OrderStatus.executed ||
      o.status == OrderStatus.approved ||
      o.status == OrderStatus.partiallyExecuted).toList();

  final groups = <String, List<Order>>{};
  for (final o in executed) {
    final key = '${o.symbol}::${UserTrade._productLabel(o.product)}';
    groups.putIfAbsent(key, () => []).add(o);
  }

  for (final group in groups.values) {
    // Sort by actual execution time for correct FIFO ordering
    group.sort((a, b) {
      final ta = a.executedAt ?? a.dateTime;
      final tb = b.executedAt ?? b.dateTime;
      return ta.compareTo(tb);
    });

    final buys  = group.where((o) => o.type == OrderType.buy).toList();
    final sells = group.where((o) => o.type == OrderType.sell).toList();

    // Quantity-aware FIFO: track remaining fill quantity per order so a
    // single large order can be partially matched across multiple counterparts.
    // e.g. BUY 100 + SELL 80 → one closed slice (80 qty) + open remainder (20).
    final buyRem  = List<int>.generate(buys.length,  (i) => buys[i].executedQuantity  ?? buys[i].quantity);
    final sellRem = List<int>.generate(sells.length, (i) => sells[i].executedQuantity ?? sells[i].quantity);

    // Long FIFO: each BUY matches with earliest subsequent SELL(s)
    for (int bi = 0; bi < buys.length; bi++) {
      if (buyRem[bi] <= 0) continue;
      final buyTime = buys[bi].executedAt ?? buys[bi].dateTime;
      for (int si = 0; si < sells.length; si++) {
        if (sellRem[si] <= 0) continue;
        final sellTime = sells[si].executedAt ?? sells[si].dateTime;
        if (sellTime.isBefore(buyTime)) continue;
        final matchQty = buyRem[bi] < sellRem[si] ? buyRem[bi] : sellRem[si];
        buyRem[bi]  -= matchQty;
        sellRem[si] -= matchQty;
        result.add(UserTrade._closed(entry: buys[bi], exit: sells[si], qty: matchQty));
        if (buyRem[bi] <= 0) break;
      }
    }

    // Short FIFO: each remaining SELL matches with earliest subsequent BUY(s)
    for (int si = 0; si < sells.length; si++) {
      if (sellRem[si] <= 0) continue;
      final sellTime = sells[si].executedAt ?? sells[si].dateTime;
      for (int bi = 0; bi < buys.length; bi++) {
        if (buyRem[bi] <= 0) continue;
        final buyTime = buys[bi].executedAt ?? buys[bi].dateTime;
        if (buyTime.isBefore(sellTime)) continue;
        final matchQty = sellRem[si] < buyRem[bi] ? sellRem[si] : buyRem[bi];
        sellRem[si] -= matchQty;
        buyRem[bi]  -= matchQty;
        result.add(UserTrade._closed(entry: sells[si], exit: buys[bi], qty: matchQty));
        if (sellRem[si] <= 0) break;
      }
    }

    // Remaining unmatched quantity → open positions
    for (int bi = 0; bi < buys.length; bi++) {
      if (buyRem[bi] > 0) result.add(UserTrade._open(buys[bi], qty: buyRem[bi]));
    }
    for (int si = 0; si < sells.length; si++) {
      if (sellRem[si] > 0) result.add(UserTrade._open(sells[si], qty: sellRem[si]));
    }
  }

  // Most-recent activity first
  result.sort((a, b) => b.sortTime.compareTo(a.sortTime));
  return result;
}

// ── Group builder ──────────────────────────────────────────────────────────────

List<_DateGroup> groupByDate(List<UserTrade> trades) {
  final map = <DateTime, List<UserTrade>>{};
  for (final t in trades) {
    map.putIfAbsent(t.dateKey, () => []).add(t);
  }
  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return keys.map((d) => _DateGroup(date: d, trades: map[d]!)).toList();
}

// ── Summary ────────────────────────────────────────────────────────────────────

class _OverallSummary {
  final int totalTrades;
  final int wins;
  final int losses;
  final double grossPnl;
  final double brokerage;
  final double netPnl;

  const _OverallSummary({
    required this.totalTrades, required this.wins, required this.losses,
    required this.grossPnl, required this.brokerage, required this.netPnl,
  });

  factory _OverallSummary.from(List<UserTrade> trades) {
    final closed = trades.where((t) => t.status == _TradeStatus.closed);
    return _OverallSummary(
      totalTrades: trades.length,
      wins:     closed.where((t) => t.netPnl > 0).length,
      losses:   closed.where((t) => t.netPnl < 0).length,
      grossPnl: trades.fold(0.0, (s, t) => s + t.grossPnl),
      brokerage: trades.fold(0.0, (s, t) => s + t.brokerage),
      netPnl:   trades.fold(0.0, (s, t) => s + t.netPnl),
    );
  }

  double get winRate {
    final closed = wins + losses;
    return closed == 0 ? 0 : wins / closed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class TradeHistoryScreen extends StatefulWidget {
  const TradeHistoryScreen({super.key});

  @override
  State<TradeHistoryScreen> createState() => _TradeHistoryScreenState();
}

class _TradeHistoryScreenState extends State<TradeHistoryScreen> {
  DateTimeRange? _dateRange;
  String _symbolQuery = '';
  String _exchange = 'ALL';
  String _pnlFilter = 'all';   // all | profit | loss
  String _statusFilter = 'all'; // all | open | closed
  _SortOrder _sort = _SortOrder.latestFirst;
  String? _expandedId;

  // ── Filter logic ─────────────────────────────────────────────────────────────

  List<UserTrade> _applyFilters(List<UserTrade> all) {
    var list = all;

    if (_dateRange != null) {
      list = list.where((t) {
        final d = t.dateKey;
        return !d.isBefore(_dateRange!.start) && !d.isAfter(_dateRange!.end);
      }).toList();
    }

    final q = _symbolQuery.trim().toUpperCase();
    if (q.isNotEmpty) {
      list = list.where((t) => t.symbol.toUpperCase().contains(q)).toList();
    }

    if (_exchange != 'ALL') {
      list = list.where((t) => t.exchange.toUpperCase() == _exchange).toList();
    }

    switch (_pnlFilter) {
      case 'profit': list = list.where((t) => t.netPnl > 0).toList(); break;
      case 'loss':   list = list.where((t) => t.netPnl < 0).toList(); break;
    }

    switch (_statusFilter) {
      case 'open':   list = list.where((t) => t.status == _TradeStatus.open).toList();   break;
      case 'closed': list = list.where((t) => t.status == _TradeStatus.closed).toList(); break;
    }

    return list;
  }

  List<UserTrade> _applySortOrder(List<UserTrade> list) {
    final copy = List<UserTrade>.from(list);
    switch (_sort) {
      case _SortOrder.latestFirst:
        copy.sort((a, b) => b.sortTime.compareTo(a.sortTime));
        break;
      case _SortOrder.highestProfit:
        copy.sort((a, b) => b.netPnl.compareTo(a.netPnl));
        break;
      case _SortOrder.highestLoss:
        copy.sort((a, b) => a.netPnl.compareTo(b.netPnl));
        break;
      case _SortOrder.longestDuration:
        copy.sort((a, b) =>
            b.holdingDuration.inSeconds.compareTo(a.holdingDuration.inSeconds));
        break;
    }
    return copy;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final allTrades = buildUserTrades(store.orders.toList());
    final filtered  = _applyFilters(allTrades);
    final sorted    = _applySortOrder(filtered);
    final groups    = groupByDate(sorted);
    final summary   = _OverallSummary.from(allTrades);
    final isWide    = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        _SummaryStrip(summary: summary),
        _FilterBar(
          dateRange:    _dateRange,
          symbolQuery:  _symbolQuery,
          exchange:     _exchange,
          pnlFilter:    _pnlFilter,
          statusFilter: _statusFilter,
          sort:         _sort,
          onDateRange:      (r) => setState(() => _dateRange    = r),
          onSymbolQuery:    (v) => setState(() => _symbolQuery  = v),
          onExchange:       (v) => setState(() => _exchange     = v),
          onPnlFilter:      (v) => setState(() => _pnlFilter    = v),
          onStatusFilter:   (v) => setState(() => _statusFilter = v),
          onSort:           (v) => setState(() => _sort         = v),
          onClearDate:      ()  => setState(() => _dateRange    = null),
        ),
        Expanded(
          child: groups.isEmpty
              ? _EmptyState(hasFilters: _hasAnyFilter())
              : _TradeList(
                  groups:     groups,
                  isWide:     isWide,
                  expandedId: _expandedId,
                  onExpand:   (id) => setState(() =>
                      _expandedId = _expandedId == id ? null : id),
                ),
        ),
      ]),
    );
  }

  bool _hasAnyFilter() =>
      _dateRange != null || _symbolQuery.isNotEmpty ||
      _exchange != 'ALL' || _pnlFilter != 'all' || _statusFilter != 'all';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY STRIP
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryStrip extends StatelessWidget {
  final _OverallSummary summary;
  const _SummaryStrip({required this.summary});

  static String _fmtV(double v) {
    final a = v.abs();
    if (a >= 10000000) return '₹${(a / 10000000).toStringAsFixed(1)}Cr';
    if (a >= 100000)   return '₹${(a / 100000).toStringAsFixed(1)}L';
    if (a >= 1000)     return '₹${(a / 1000).toStringAsFixed(1)}K';
    return '₹${a.toStringAsFixed(0)}';
  }

  static String _fmtPnl(double v) {
    final s = _fmtV(v);
    return v > 0 ? '+$s' : v < 0 ? '-${_fmtV(v.abs())}' : s;
  }

  @override
  Widget build(BuildContext context) {
    final pnlColor = summary.netPnl >= 0 ? AppColors.success : AppColors.danger;
    final winRate  = summary.winRate;
    final winColor = winRate >= 0.5 ? AppColors.success : AppColors.danger;
    final isWide   = MediaQuery.of(context).size.width >= 600;

    final items = [
      _SChip(label: 'Trades',    value: '${summary.totalTrades}',
          color: AppColors.primary),
      _SChip(label: 'Win Rate',  value: '${(winRate * 100).toStringAsFixed(1)}%',
          color: winColor),
      _SChip(label: 'P&L',       value: _fmtPnl(summary.netPnl),
          color: pnlColor),
      _SChip(label: 'Brokerage', value: '-${_fmtV(summary.brokerage)}',
          color: AppColors.textSecondary),
      _SChip(label: 'Wins',      value: '${summary.wins}',
          color: AppColors.success),
      _SChip(label: 'Losses',    value: '${summary.losses}',
          color: AppColors.danger),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: isWide
          ? Row(children: items.map((c) => Expanded(child: c)).toList())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: items.map((c) =>
                  SizedBox(width: 110, child: c)).toList()),
            ),
    );
  }
}

class _SChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: GoogleFonts.jetBrainsMono(
          fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: GoogleFonts.inter(
          fontSize: 9, color: AppColors.textSecondary)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  final DateTimeRange? dateRange;
  final String symbolQuery, exchange, pnlFilter, statusFilter;
  final _SortOrder sort;
  final ValueChanged<DateTimeRange?> onDateRange;
  final ValueChanged<String> onSymbolQuery, onExchange, onPnlFilter, onStatusFilter;
  final ValueChanged<_SortOrder> onSort;
  final VoidCallback onClearDate;

  const _FilterBar({
    required this.dateRange, required this.symbolQuery,
    required this.exchange, required this.pnlFilter,
    required this.statusFilter, required this.sort,
    required this.onDateRange, required this.onSymbolQuery,
    required this.onExchange, required this.onPnlFilter,
    required this.onStatusFilter, required this.onSort,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        const SizedBox(height: 10),
        // Row 1: search + date + sort
        Row(children: [
          // Symbol search
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: onSymbolQuery,
                decoration: InputDecoration(
                  hintText: 'Search symbol…',
                  hintStyle: GoogleFonts.inter(fontSize: 12),
                  prefixIcon: const Icon(LucideIcons.search, size: 14),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: symbolQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 14),
                          onPressed: () => onSymbolQuery(''),
                          padding: EdgeInsets.zero)
                      : null,
                ),
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Date range picker
          GestureDetector(
            onTap: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: dateRange,
                builder: (ctx, child) => Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primary),
                  ),
                  child: child!,
                ),
              );
              onDateRange(r);
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: dateRange != null
                    ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: dateRange != null ? AppColors.primary : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.calendar, size: 14,
                    color: dateRange != null ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 5),
                Text(
                  dateRange != null
                      ? '${DateFormat('dd MMM').format(dateRange!.start)} – ${DateFormat('dd MMM').format(dateRange!.end)}'
                      : 'Date Range',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500,
                      color: dateRange != null ? AppColors.primary : AppColors.textSecondary),
                ),
                if (dateRange != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(onTap: onClearDate,
                    child: const Icon(Icons.close, size: 13, color: AppColors.primary)),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Sort dropdown
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(7),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_SortOrder>(
                value: sort,
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textPrimary),
                items: _SortOrder.values.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label))).toList(),
                onChanged: (v) => v != null ? onSort(v) : null,
                icon: const Icon(LucideIcons.chevronsUpDown, size: 12),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Row 2: filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            // Exchange
            ...['ALL', 'NSE', 'BSE', 'MCX'].map((ex) => _FChip(
              label: ex, selected: exchange == ex,
              color: _exchColor(ex),
              onTap: () => onExchange(ex),
            )),
            const SizedBox(width: 10),
            const _Divider(),
            const SizedBox(width: 10),
            // P&L
            _FChip(label: 'All P&L', selected: pnlFilter == 'all',
                color: AppColors.primary, onTap: () => onPnlFilter('all')),
            _FChip(label: 'Profit', selected: pnlFilter == 'profit',
                color: AppColors.success, onTap: () => onPnlFilter('profit')),
            _FChip(label: 'Loss', selected: pnlFilter == 'loss',
                color: AppColors.danger, onTap: () => onPnlFilter('loss')),
            const SizedBox(width: 10),
            const _Divider(),
            const SizedBox(width: 10),
            // Status
            _FChip(label: 'All', selected: statusFilter == 'all',
                color: AppColors.primary, onTap: () => onStatusFilter('all')),
            _FChip(label: 'Open', selected: statusFilter == 'open',
                color: const Color(0xFFFF6D00), onTap: () => onStatusFilter('open')),
            _FChip(label: 'Closed', selected: statusFilter == 'closed',
                color: AppColors.textSecondary, onTap: () => onStatusFilter('closed')),
          ]),
        ),
      ]),
    );
  }

  static Color _exchColor(String ex) {
    switch (ex) {
      case 'BSE': return const Color(0xFF1565C0);
      case 'MCX': return const Color(0xFF6A1B9A);
      case 'NSE': return AppColors.primary;
      default:    return AppColors.textSecondary;
    }
  }
}

class _FChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FChip({required this.label, required this.selected,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(label, style: GoogleFonts.inter(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 18, color: AppColors.border);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRADE LIST  (virtualized CustomScrollView with sticky date headers)
// ═══════════════════════════════════════════════════════════════════════════════

class _TradeList extends StatelessWidget {
  final List<_DateGroup> groups;
  final bool isWide;
  final String? expandedId;
  final ValueChanged<String> onExpand;
  const _TradeList({
    required this.groups, required this.isWide,
    required this.expandedId, required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      // Desktop: show table header once, then sticky date sections
      return Column(children: [
        _DesktopTableHeader(),
        Expanded(
          child: CustomScrollView(
            slivers: [
              for (final group in groups) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DateSectionHeaderDelegate(group: group, isWide: true),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final trade = group.trades[i];
                      return Column(children: [
                        _DesktopTradeRow(
                          trade: trade,
                          isExpanded: expandedId == trade.id,
                          onTap: () => onExpand(trade.id),
                        ),
                        if (expandedId == trade.id)
                          _TradeDetailDrawer(trade: trade),
                      ]);
                    },
                    childCount: group.trades.length,
                  ),
                ),
              ],
            ],
          ),
        ),
      ]);
    } else {
      // Mobile: cards with sticky date headers
      return CustomScrollView(
        slivers: [
          for (final group in groups) ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _DateSectionHeaderDelegate(group: group, isWide: false),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final trade = group.trades[i];
                    return Column(children: [
                      _MobileTradeCard(
                        trade: trade,
                        isExpanded: expandedId == trade.id,
                        onTap: () => onExpand(trade.id),
                      ),
                      if (expandedId == trade.id)
                        _TradeDetailDrawer(trade: trade, mobile: true),
                    ]);
                  },
                  childCount: group.trades.length,
                ),
              ),
            ),
          ],
        ],
      );
    }
  }
}

// ── Sticky date section header ─────────────────────────────────────────────────

class _DateSectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final _DateGroup group;
  final bool isWide;
  const _DateSectionHeaderDelegate({required this.group, required this.isWide});

  static double get _h => 48.0;

  @override double get maxExtent => _h;
  @override double get minExtent => _h;

  @override
  bool shouldRebuild(_DateSectionHeaderDelegate old) =>
      old.group.date != group.date || old.group.trades.length != group.trades.length;

  static String _fmtPnl(double v) {
    final a = v.abs();
    final s = a >= 100000 ? '₹${(a / 100000).toStringAsFixed(1)}L'
            : a >= 1000   ? '₹${(a / 1000).toStringAsFixed(1)}K'
            : '₹${a.toStringAsFixed(0)}';
    return v > 0 ? '+$s' : v < 0 ? '-$s' : s;
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final today     = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final isToday   = group.date.day == today.day &&
                      group.date.month == today.month &&
                      group.date.year == today.year;
    final isYest    = group.date.day == yesterday.day &&
                      group.date.month == yesterday.month &&
                      group.date.year == yesterday.year;
    final dateLabel = isToday ? 'Today'
                    : isYest  ? 'Yesterday'
                    : DateFormat('dd MMM yyyy').format(group.date);
    final pnlColor  = group.netPnl > 0 ? AppColors.success
                    : group.netPnl < 0 ? AppColors.danger
                    : AppColors.textSecondary;

    return Container(
      height: _h,
      decoration: BoxDecoration(
        color: overlapsContent
            ? AppColors.surfaceAlt.withOpacity(0.97)
            : AppColors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
          top:    BorderSide(color: AppColors.border.withOpacity(0.3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        // Date
        Text(dateLabel, style: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w800,
            color: AppColors.textPrimary)),
        const SizedBox(width: 12),
        // Stats row
        _DayStat('${group.totalTrades}', 'Trades', AppColors.primary),
        const SizedBox(width: 10),
        _DayStat('${group.winCount}', 'W', AppColors.success),
        const SizedBox(width: 6),
        _DayStat('${group.lossCount}', 'L', AppColors.danger),
        const Spacer(),
        if (isWide) ...[
          _DayPnl('Gross', group.grossPnl),
          const SizedBox(width: 14),
          _DayPnl('Brok', -group.brokerage),
          const SizedBox(width: 14),
        ],
        // Net P&L — always visible
        Text(_fmtPnl(group.netPnl), style: GoogleFonts.jetBrainsMono(
            fontSize: 13, fontWeight: FontWeight.w800, color: pnlColor)),
        const SizedBox(width: 4),
        Text('Net', style: GoogleFonts.inter(
            fontSize: 9, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _DayStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _DayStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    const SizedBox(width: 3),
    Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
  ]);
}

class _DayPnl extends StatelessWidget {
  final String label;
  final double value;
  const _DayPnl(this.label, this.value);

  static String _fmt(double v) {
    final a = v.abs();
    final s = a >= 100000 ? '₹${(a/100000).toStringAsFixed(1)}L'
            : a >= 1000   ? '₹${(a/1000).toStringAsFixed(1)}K'
            : '₹${a.toStringAsFixed(0)}';
    return v >= 0 ? s : '-$s';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(_fmt(value), style: GoogleFonts.jetBrainsMono(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: value >= 0 ? AppColors.success : AppColors.danger)),
      Text(label, style: GoogleFonts.inter(
          fontSize: 8, color: AppColors.textSecondary)),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DESKTOP TABLE
// ═══════════════════════════════════════════════════════════════════════════════

class _DesktopTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: const Row(children: [
      _TH('Symbol',   3),
      _TH('Direction',2),
      _TH('Qty',      1, right: true),
      _TH('Entry',    2, right: true),
      _TH('Exit',     2, right: true),
      _TH('Points',   2, right: true),
      _TH('Gross P&L',2, right: true),
      _TH('Net P&L',  2, right: true),
      _TH('Duration', 2),
      _TH('Status',   2),
      SizedBox(width: 32),
    ]),
  );
}

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool right;
  const _TH(this.label, this.flex, {this.right = false});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.textSecondary, letterSpacing: 0.3)),
  );
}

class _DesktopTradeRow extends StatelessWidget {
  final UserTrade trade;
  final bool isExpanded;
  final VoidCallback onTap;
  const _DesktopTradeRow({required this.trade, required this.isExpanded, required this.onTap});

  static String _fmtPnl(double v) {
    final a = v.abs();
    final s = a >= 100000 ? '₹${(a/100000).toStringAsFixed(1)}L'
            : a >= 1000   ? '₹${(a/1000).toStringAsFixed(1)}K'
            : '₹${a.toStringAsFixed(2)}';
    return v > 0 ? '+$s' : v < 0 ? '-$s' : s;
  }

  static Color _statusColor(_TradeStatus s) {
    switch (s) {
      case _TradeStatus.open:     return const Color(0xFFFF6D00);
      case _TradeStatus.closed:   return AppColors.textSecondary;
      case _TradeStatus.rejected: return AppColors.danger;
      case _TradeStatus.pending:  return AppColors.primary;
    }
  }

  static String _fmtDur(Duration d) {
    if (d.inSeconds == 0)  return '< 1s';
    if (d.inDays > 0)      return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0)     return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0)   return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final isLong   = trade.direction == OrderType.buy;
    final dirColor = isLong ? AppColors.success : AppColors.danger;
    final pnlColor = trade.netPnl > 0 ? AppColors.success
                   : trade.netPnl < 0 ? AppColors.danger
                   : AppColors.textSecondary;
    final leftBorderColor = trade.status == _TradeStatus.open
        ? const Color(0xFFFF6D00)
        : trade.netPnl > 0 ? AppColors.success
        : trade.netPnl < 0 ? AppColors.danger
        : AppColors.border;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isExpanded ? AppColors.primary.withOpacity(0.025) : null,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withOpacity(0.4)),
            left: BorderSide(color: leftBorderColor, width: 2),
          ),
        ),
        child: Row(children: [
          // Symbol
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trade.symbol, style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('${trade.exchange} · ${trade.product}', style: GoogleFonts.inter(
                fontSize: 9, color: AppColors.textSecondary)),
          ])),
          // Direction
          Expanded(flex: 2, child: Container(
            constraints: const BoxConstraints(maxWidth: 70),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: dirColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(isLong ? 'LONG' : 'SHORT',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: dirColor)),
          )),
          // Qty
          Expanded(flex: 1, child: Text('${trade.quantity}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(fontSize: 11))),
          // Entry
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${trade.entryPrice.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textPrimary)),
            Text(_fmtTimestampCompact(trade.entryTime),
                style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
          ])),
          // Exit
          Expanded(flex: 2, child: trade.exitPrice != null
              ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹${trade.exitPrice!.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textPrimary)),
                  Text(_fmtTimestampCompact(trade.exitTime!),
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                ])
              : Text('—', textAlign: TextAlign.right,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11))),
          // Points captured
          Expanded(flex: 2, child: trade.status == _TradeStatus.closed
              ? Text(
                  '${trade.pointsCaptured >= 0 ? '+' : ''}${trade.pointsCaptured.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: trade.pointsCaptured >= 0 ? AppColors.success : AppColors.danger))
              : Text('—', textAlign: TextAlign.right,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
          // Gross P&L
          Expanded(flex: 2, child: trade.status == _TradeStatus.closed
              ? Text(_fmtPnl(trade.grossPnl), textAlign: TextAlign.right,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600,
                      color: trade.grossPnl > 0 ? AppColors.success : AppColors.danger))
              : Text('—', textAlign: TextAlign.right,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
          // Net P&L
          Expanded(flex: 2, child: trade.status == _TradeStatus.closed
              ? Text(_fmtPnl(trade.netPnl), textAlign: TextAlign.right,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w800,
                      color: pnlColor))
              : _StatusPill(status: trade.status)),
          // Duration
          Expanded(flex: 2, child: Text(_fmtDur(trade.holdingDuration),
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textSecondary))),
          // Status
          Expanded(flex: 2, child: _StatusPill(status: trade.status)),
          // Expand chevron
          SizedBox(width: 32, child: Icon(
            isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 14, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOBILE TRADE CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileTradeCard extends StatelessWidget {
  final UserTrade trade;
  final bool isExpanded;
  final VoidCallback onTap;
  const _MobileTradeCard({required this.trade, required this.isExpanded, required this.onTap});

  static String _fmtPnl(double v) {
    final a = v.abs();
    final s = a >= 100000 ? '₹${(a/100000).toStringAsFixed(1)}L'
            : a >= 1000   ? '₹${(a/1000).toStringAsFixed(1)}K'
            : '₹${a.toStringAsFixed(2)}';
    return v > 0 ? '+$s' : v < 0 ? '-$s' : s;
  }

  static String _fmtDur(Duration d) {
    if (d.inSeconds == 0)  return '< 1s';
    if (d.inDays > 0)      return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0)     return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0)   return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final isLong   = trade.direction == OrderType.buy;
    final dirColor = isLong ? AppColors.success : AppColors.danger;
    final pnlColor = trade.netPnl > 0 ? AppColors.success
                   : trade.netPnl < 0 ? AppColors.danger
                   : AppColors.textSecondary;
    final borderColor = trade.status == _TradeStatus.open
        ? const Color(0xFFFF6D00)
        : trade.netPnl > 0 ? AppColors.success.withOpacity(0.3)
        : trade.netPnl < 0 ? AppColors.danger.withOpacity(0.3)
        : AppColors.border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            // Row 1: symbol + direction + status
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dirColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(isLong ? 'LONG' : 'SHORT',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: dirColor)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(trade.symbol, style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              Text('${trade.exchange} · ${trade.product}', style: GoogleFonts.inter(
                  fontSize: 9, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              _StatusPill(status: trade.status),
            ]),
            const SizedBox(height: 10),
            // Row 2: entry | points | exit
            Row(children: [
              // Entry
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Entry', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                Text('₹${trade.entryPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700,
                        color: dirColor)),
                Text(_fmtTimestampCompact(trade.entryTime),
                    style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
              ])),
              // Points
              if (trade.status == _TradeStatus.closed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (trade.pointsCaptured >= 0 ? AppColors.success : AppColors.danger)
                        .withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(children: [
                    Text('${trade.pointsCaptured >= 0 ? '+' : ''}${trade.pointsCaptured.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w700,
                            color: trade.pointsCaptured >= 0 ? AppColors.success : AppColors.danger)),
                    Text('pts', style: GoogleFonts.inter(fontSize: 8, color: AppColors.textSecondary)),
                  ]),
                ),
              // Exit
              Expanded(child: trade.exitPrice != null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Exit', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                      Text('₹${trade.exitPrice!.toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700,
                              color: trade.netPnl >= 0 ? AppColors.success : AppColors.danger)),
                      Text(_fmtTimestampCompact(trade.exitTime!),
                          style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Exit', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                      Text('OPEN', style: GoogleFonts.inter(fontSize: 12,
                          fontWeight: FontWeight.w700, color: const Color(0xFFFF6D00))),
                    ])),
            ]),
            const SizedBox(height: 8),
            // Row 3: qty + duration + net P&L
            Row(children: [
              Text('${trade.quantity} qty',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              const Icon(LucideIcons.clock, size: 10, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(_fmtDur(trade.holdingDuration),
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textSecondary)),
              const Spacer(),
              if (trade.status == _TradeStatus.closed) ...[
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtPnl(trade.netPnl), style: GoogleFonts.jetBrainsMono(
                      fontSize: 14, fontWeight: FontWeight.w900, color: pnlColor)),
                  Text('Net P&L', style: GoogleFonts.inter(
                      fontSize: 8, color: AppColors.textSecondary)),
                ]),
              ],
              const SizedBox(width: 8),
              Icon(isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 14, color: AppColors.textSecondary),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPANDED DETAIL DRAWER
// ═══════════════════════════════════════════════════════════════════════════════

class _TradeDetailDrawer extends StatelessWidget {
  final UserTrade trade;
  final bool mobile;
  const _TradeDetailDrawer({required this.trade, this.mobile = false});

  static String _fmtFull(double v) {
    final a = v.abs();
    final s = a >= 100000 ? '₹${(a/100000).toStringAsFixed(2)}L'
            : a >= 1000   ? '₹${(a/1000).toStringAsFixed(2)}K'
            : '₹${a.toStringAsFixed(2)}';
    return v >= 0 ? s : '-$s';
  }

  static String _fmtPnl(double v) {
    final s = _fmtFull(v.abs());
    return v > 0 ? '+$s' : v < 0 ? '-$s' : s;
  }

  static String _fmtDurFull(Duration d) {
    if (d.inSeconds == 0) return '< 1 second';
    if (d.inDays > 0)
      return '${d.inDays}d ${d.inHours.remainder(24)}h ${d.inMinutes.remainder(60)}m';
    if (d.inHours > 0)
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    if (d.inMinutes > 0)
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final isLong   = trade.direction == OrderType.buy;
    final pnlColor = trade.netPnl > 0 ? AppColors.success
                   : trade.netPnl < 0 ? AppColors.danger
                   : AppColors.textSecondary;
    final ptColor  = trade.pointsCaptured >= 0 ? AppColors.success : AppColors.danger;

    final detailSections = [
      // Execution prices
      _DetailSection(title: 'EXECUTION', color: AppColors.primary, rows: [
        _DR('Entry Price',  '₹${trade.entryPrice.toStringAsFixed(2)}'),
        _DR('Exit Price',   trade.exitPrice != null ? '₹${trade.exitPrice!.toStringAsFixed(2)}' : '—'),
        _DR('Points',
            trade.status == _TradeStatus.closed
                ? '${trade.pointsCaptured >= 0 ? '+' : ''}${trade.pointsCaptured.toStringAsFixed(4)}'
                : '—',
            valueColor: trade.status == _TradeStatus.closed ? ptColor : null),
        _DR('Quantity',     '${trade.quantity}'),
      ]),
      // P&L
      _DetailSection(title: 'P&L', color: pnlColor, rows: [
        _DR('Gross P&L',    trade.status == _TradeStatus.closed ? _fmtPnl(trade.grossPnl) : '—',
            valueColor: trade.status == _TradeStatus.closed
                ? (trade.grossPnl >= 0 ? AppColors.success : AppColors.danger) : null),
        _DR('Brokerage',    '-${_fmtFull(trade.brokerage)}', valueColor: AppColors.danger),
        _DR('Net P&L',      trade.status == _TradeStatus.closed ? _fmtPnl(trade.netPnl) : '—',
            valueColor: trade.status == _TradeStatus.closed ? pnlColor : null),
      ]),
      // Order meta
      _DetailSection(title: 'ORDER', color: AppColors.textSecondary, rows: [
        _DR('Exchange',     trade.exchange),
        _DR('Product',      trade.product),
        _DR('Order Type',   trade.variety),
        _DR('Direction',    isLong ? 'Long (BUY)' : 'Short (SELL)'),
      ]),
      // Timestamps
      _DetailSection(title: 'TIME', color: AppColors.textSecondary, rows: [
        _DR('Entry Time',   _fmtTimestampFull(trade.entryTime)),
        _DR('Exit Time',    trade.exitTime != null
                ? _fmtTimestampFull(trade.exitTime!) : '—'),
        _DR('Duration',     _isUnknownTime(trade.entryTime)
                ? 'Timestamp unavailable'
                : _fmtDurFull(trade.holdingDuration)),
        if (trade.sourceOrders.isNotEmpty)
          _DR('Entry ID',   _short(trade.entryOrderId)),
        if (trade.exitOrderId != null)
          _DR('Exit ID',    _short(trade.exitOrderId!)),
      ]),
    ];

    if (mobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (final s in detailSections) ...[
            _MobileDetailSection(section: s),
            const SizedBox(height: 12),
          ],
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detailSections.map((s) => Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _DesktopDetailSection(section: s),
        ))).toList(),
      ),
    );
  }

  static String _short(String s) => s.length > 16 ? '${s.substring(0, 16)}…' : s;
}

// Detail section model
class _DetailSection {
  final String title;
  final Color color;
  final List<_DR> rows;
  const _DetailSection({required this.title, required this.color, required this.rows});
}

class _DR {
  final String label, value;
  final Color? valueColor;
  const _DR(this.label, this.value, {this.valueColor});
}

class _DesktopDetailSection extends StatelessWidget {
  final _DetailSection section;
  const _DesktopDetailSection({required this.section});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: section.color.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(section.title, style: GoogleFonts.inter(
          fontSize: 9, fontWeight: FontWeight.w800,
          color: section.color, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      ...section.rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 80, child: Text(r.label,
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary))),
          Expanded(child: Text(r.value, style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: r.valueColor ?? AppColors.textPrimary),
              overflow: TextOverflow.ellipsis)),
        ]),
      )),
    ]),
  );
}

class _MobileDetailSection extends StatelessWidget {
  final _DetailSection section;
  const _MobileDetailSection({required this.section});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(section.title, style: GoogleFonts.inter(
          fontSize: 9, fontWeight: FontWeight.w800,
          color: section.color, letterSpacing: 0.8)),
      const SizedBox(height: 6),
      ...section.rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 100, child: Text(r.label,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
          Expanded(child: Text(r.value, style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: r.valueColor ?? AppColors.textPrimary))),
        ]),
      )),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusPill extends StatelessWidget {
  final _TradeStatus status;
  const _StatusPill({required this.status});

  static Color _c(_TradeStatus s) {
    switch (s) {
      case _TradeStatus.open:     return const Color(0xFFFF6D00);
      case _TradeStatus.closed:   return AppColors.textSecondary;
      case _TradeStatus.rejected: return AppColors.danger;
      case _TradeStatus.pending:  return AppColors.primary;
    }
  }

  static String _l(_TradeStatus s) {
    switch (s) {
      case _TradeStatus.open:     return 'OPEN';
      case _TradeStatus.closed:   return 'CLOSED';
      case _TradeStatus.rejected: return 'REJECTED';
      case _TradeStatus.pending:  return 'PENDING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(_l(status), style: TextStyle(
          fontSize: 8, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(hasFilters ? LucideIcons.searchX : LucideIcons.clipboardList,
          size: 52, color: AppColors.border),
      const SizedBox(height: 16),
      Text(hasFilters ? 'No trades match your filters.' : 'No trades yet.',
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(
        hasFilters
            ? 'Try clearing some filters.'
            : 'Your executed trades will appear here.',
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
      ),
    ]),
  );
}
