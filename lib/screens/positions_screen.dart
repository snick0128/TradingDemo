import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/multi_square_off_dialog.dart';
import '../widgets/position_detail_sheet.dart';
import '../widgets/shared_widgets.dart';

// ─── List item types ──────────────────────────────────────────────────────────

sealed class _ListItem {}

final class _SectionItem extends _ListItem {
  final String title;
  final int count;
  final double totalPnl;
  _SectionItem(this.title, this.count, this.totalPnl);
}

final class _PositionItem extends _ListItem {
  final Position position;
  _PositionItem(this.position);
}

final class _HoldingItem extends _ListItem {
  final Holding holding;
  _HoldingItem(this.holding);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PositionsScreen extends StatefulWidget {
  final bool showAppBar;
  const PositionsScreen({super.key, this.showAppBar = true});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  Timer? _squareOffTimer;
  final Set<String> _selected = {};
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _scheduleMisWarning();
  }

  @override
  void dispose() {
    _squareOffTimer?.cancel();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _scheduleMisWarning() {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, 15, 20);
    final delay = target.isAfter(now) ? target.difference(now) : Duration.zero;
    _squareOffTimer = Timer(delay, () {
      if (!mounted) return;
      final store = TradingScope.of(context);
      if (store.positions.any((p) => p.product == ProductType.mis)) {
        store.setMisSquareOffWarning(true);
      }
    });
  }

  /// Returns the best available price for a symbol, never falling back to 0.
  /// Priority: live WS tick → stock universe → stored Firestore price → prevClose → avgPrice
  ///
  /// Stored (Firestore) price is intentionally checked AFTER the live sources.
  /// Holdings/positions get their currentPrice set once when the Firestore stream
  /// fires and may become stale; lastValidLtp() is updated on every WS tick so
  /// it always reflects the most recent traded price.
  static double resolvedLtp(
    TradingStore store,
    String symbol,
    double storedPrice, {
    double avgPriceFallback = 0,
  }) {
    final cached = store.lastValidLtp(symbol);
    if (cached > 0) return cached;
    final liveStock = store.stockBySymbolOrNull(symbol);
    final live = liveStock?.currentPrice ?? 0;
    if (live > 0) return live;
    if (storedPrice > 0) return storedPrice;
    final prev = liveStock?.prevClose ?? 0;
    if (prev > 0) return prev;
    return avgPriceFallback > 0 ? avgPriceFallback : storedPrice;
  }

  String _posKey(Position p) =>
      'pos:${p.symbol}:${p.product.name}:${p.side.name}';
  String _hldKey(Holding h) => 'hld:${h.symbol}';

  List<String> _allKeys(List<Position> positions, List<Holding> holdings) => [
    ...positions.map(_posKey),
    ...holdings.map(_hldKey),
  ];

  void _toggle(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected.contains(key) ? _selected.remove(key) : _selected.add(key);
    });
  }

  void _selectAll(List<String> keys) =>
      setState(() => _selected.addAll(keys));

  void _deselectAll() => setState(() => _selected.clear());

  // ─── Square-off execution ──────────────────────────────────────────────────

  Future<void> squareOffPosition(
    BuildContext ctx,
    Position p,
    int qty,
  ) async {
    final key = _posKey(p);
    if (_pending.contains(key)) return;
    setState(() => _pending.add(key));

    final appScope = ctx.dependOnInheritedWidgetOfExactType<AppScope>();
    final sessionUser = appScope?.notifier?.user;

    if (sessionUser != null) {
      try {
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        final store = TradingScope.read(ctx);
        final exitType = p.side == OrderType.buy ? 'SELL' : 'BUY';
        final productStr = switch (p.product) {
          ProductType.nrml => 'NRML',
          ProductType.overnight => 'CNC',
          ProductType.mtf => 'MTF',
          _ => 'MIS',
        };
        // Resolve the best available price — critical for F&O symbols not in
        // the live WebSocket feed so the backend can execute at a valid price.
        final ltp = resolvedLtp(
          store, p.symbol, p.currentPrice, avgPriceFallback: p.avgPrice,
        );
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: p.symbol,
          qty: qty,
          type: exitType,
          productType: productStr,
          exchange: p.exchange,
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId:
              '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_sq',
        );
        if (ctx.mounted) {
          AppToast.success(ctx, '${p.symbol} exited ($qty qty)');
          _selected.discard(key);
        }
      } on BackendException catch (e) {
        if (ctx.mounted) AppToast.error(ctx, e.message);
      } catch (e) {
        if (ctx.mounted) {
          AppToast.error(ctx, e.toString().replaceAll('Exception: ', ''));
        }
      } finally {
        if (mounted) setState(() => _pending.remove(key));
      }
      return;
    }

    // Offline / mock path
    final store = TradingScope.read(ctx);
    final result = store.placeOrder(
      symbol: p.symbol,
      quantity: qty,
      type: p.side == OrderType.buy ? OrderType.sell : OrderType.buy,
      variety: OrderVariety.market,
      product: p.product,
    );
    if (ctx.mounted) {
      result.success
          ? AppToast.success(ctx, '${p.symbol} exited')
          : AppToast.error(ctx, result.errorMessage ?? 'Failed');
      if (result.success) _selected.discard(key);
    }
    if (mounted) setState(() => _pending.remove(key));
  }

  Future<void> squareOffHolding(BuildContext ctx, Holding h) async {
    final key = _hldKey(h);
    if (_pending.contains(key)) return;
    setState(() => _pending.add(key));

    final appScope = ctx.dependOnInheritedWidgetOfExactType<AppScope>();
    final sessionUser = appScope?.notifier?.user;

    if (sessionUser != null) {
      try {
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        final store = TradingScope.read(ctx);
        // Prefer exchange from the live stock universe; the backend also
        // auto-corrects MCX symbols if 'NSE' arrives incorrectly.
        final exchange =
            store.stockBySymbolOrNull(h.symbol)?.exchange ?? 'NSE';
        final ltp = resolvedLtp(
          store, h.symbol, h.currentPrice, avgPriceFallback: h.avgPrice,
        );
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: h.symbol,
          qty: h.quantity,
          type: 'SELL',
          productType: 'CNC',
          exchange: exchange,
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId:
              '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_hq',
        );
        if (ctx.mounted) {
          AppToast.success(ctx, '${h.symbol} sold (${h.quantity} qty)');
          _selected.discard(key);
        }
      } on BackendException catch (e) {
        if (ctx.mounted) AppToast.error(ctx, e.message);
      } catch (e) {
        if (ctx.mounted) {
          AppToast.error(ctx, e.toString().replaceAll('Exception: ', ''));
        }
      } finally {
        if (mounted) setState(() => _pending.remove(key));
      }
    } else {
      if (mounted) setState(() => _pending.remove(key));
      if (ctx.mounted) AppToast.error(ctx, 'Session expired. Please login.');
    }
  }

  void _openMultiSquareOff(
    BuildContext ctx,
    List<Position> positions,
    List<Holding> holdings,
  ) {
    final selPositions = positions
        .where((p) => _selected.contains(_posKey(p)))
        .toList();
    final selHoldings = holdings
        .where((h) => _selected.contains(_hldKey(h)))
        .toList();
    if (selPositions.isEmpty && selHoldings.isEmpty) return;

    MultiSquareOffDialog.show(
      ctx,
      selectedPositions: selPositions,
      selectedHoldings: selHoldings,
      resolvedLtp: (symbol, stored) =>
          resolvedLtp(TradingScope.read(ctx), symbol, stored),
      onCompleted: () {
        if (mounted) _deselectAll();
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final positions = store.positions;
    final holdings = store.holdings;

    // Shimmer guard — wait for first data
    if (store.watchlist.isEmpty && !store.backendError) {
      final shimmerBody = ShimmerWrapper(
        child: Column(
          children: [
            const ShimmerSummaryStrip(count: 3),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: 8,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                itemBuilder: (_, __) => const ShimmerPositionTile(),
              ),
            ),
          ],
        ),
      );
      if (!widget.showAppBar) return shimmerBody;
      return Scaffold(
        appBar: AppBar(title: const Text('Positions')),
        body: shimmerBody,
      );
    }

    final items = _buildFlatList(store, positions, holdings);
    final allKeys = _allKeys(positions, holdings);
    final hasContent = positions.isNotEmpty || holdings.isNotEmpty;
    final selCount = _selected.length;

    final body = Stack(
      children: [
        Column(
          children: [
            // MIS warning
            if (store.showMisSquareOffWarning &&
                positions.any((p) => p.product == ProductType.mis))
              _MisWarningBanner(
                onDismiss: () => store.setMisSquareOffWarning(false),
              ),

            // Portfolio summary
            if (hasContent)
              _PortfolioSummaryBar(
                positions: positions,
                holdings: holdings,
                store: store,
              ),

            // Select all row
            if (hasContent)
              _SelectAllRow(
                total: allKeys.length,
                selected: selCount,
                onSelectAll: () => _selectAll(allKeys),
                onDeselect: _deselectAll,
              ),

            // Positions + Holdings list
            Expanded(
              child: !hasContent
                  ? _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final item = items[i];
                        return switch (item) {
                          _SectionItem() => _SectionHeader(item: item),
                          _PositionItem(:final position) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RepaintBoundary(
                              child: _PositionCard(
                                position: position,
                                resolvedLtp: resolvedLtp(
                                  store,
                                  position.symbol,
                                  position.currentPrice,
                                  avgPriceFallback: position.avgPrice,
                                ),
                                isSelected: _selected.contains(_posKey(position)),
                                isPending: _pending.contains(_posKey(position)),
                                onToggle: () => _toggle(_posKey(position)),
                                onTap: () => PositionDetailSheet.showPosition(
                                  ctx,
                                  position: position,
                                  resolvedLtp: resolvedLtp(
                                    store,
                                    position.symbol,
                                    position.currentPrice,
                                    avgPriceFallback: position.avgPrice,
                                  ),
                                  onSquareOff: (qty) =>
                                      squareOffPosition(ctx, position, qty),
                                ),
                              ),
                            ),
                          ),
                          _HoldingItem(:final holding) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RepaintBoundary(
                              child: _HoldingCard(
                                holding: holding,
                                resolvedLtp: resolvedLtp(
                                  store,
                                  holding.symbol,
                                  holding.currentPrice,
                                  avgPriceFallback: holding.avgPrice,
                                ),
                                isSelected: _selected.contains(_hldKey(holding)),
                                isPending: _pending.contains(_hldKey(holding)),
                                onToggle: () => _toggle(_hldKey(holding)),
                                onTap: () => PositionDetailSheet.showHolding(
                                  ctx,
                                  holding: holding,
                                  resolvedLtp: resolvedLtp(
                                    store,
                                    holding.symbol,
                                    holding.currentPrice,
                                    avgPriceFallback: holding.avgPrice,
                                  ),
                                  onSquareOff: () => squareOffHolding(ctx, holding),
                                ),
                              ),
                            ),
                          ),
                        };
                      },
                    ),
            ),
          ],
        ),

        // Floating Square Off button
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: _FloatingSquareOffFab(
            count: selCount,
            onTap: () => _openMultiSquareOff(context, positions, holdings),
          ),
        ),
      ],
    );

    // When embedded inside another Scaffold (e.g. TabBarView in PortfolioScreen),
    // do NOT wrap in a second Scaffold — it creates nested Scaffolds that violate
    // Flutter's constraint model and cause box.dart assertion failures on Expanded
    // and double.infinity children. Return the body directly; the parent Scaffold
    // already provides the background colour and bounded constraints.
    if (!widget.showAppBar) return body;
    final total = positions.length + holdings.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(total > 0 ? 'Positions ($total)' : 'Positions'),
      ),
      body: body,
    );
  }
}

// ─── Build flat item list ─────────────────────────────────────────────────────

List<_ListItem> _buildFlatList(
  TradingStore store,
  List<Position> positions,
  List<Holding> holdings,
) {
  final items = <_ListItem>[];

  // Group positions by product type
  final intraday = positions.where((p) => p.product == ProductType.mis).toList();
  final overnight = positions
      .where(
        (p) =>
            p.product == ProductType.nrml ||
            p.product == ProductType.overnight,
      )
      .toList();
  final mtf = positions.where((p) => p.product == ProductType.mtf).toList();

  double sectionPnl(List<Position> ps) {
    return ps.fold(0.0, (s, p) {
      final ltp = _PositionsScreenState.resolvedLtp(
        store,
        p.symbol,
        p.currentPrice,
        avgPriceFallback: p.avgPrice,
      );
      return s + (p.side == OrderType.buy
          ? (ltp - p.avgPrice) * p.quantity
          : (p.avgPrice - ltp) * p.quantity);
    });
  }

  double holdingsSectionPnl(List<Holding> hs) {
    return hs.fold(0.0, (s, h) {
      final ltp = _PositionsScreenState.resolvedLtp(
        store,
        h.symbol,
        h.currentPrice,
        avgPriceFallback: h.avgPrice,
      );
      return s + (ltp - h.avgPrice) * h.quantity;
    });
  }

  if (intraday.isNotEmpty) {
    items.add(_SectionItem('INTRADAY', intraday.length, sectionPnl(intraday)));
    items.addAll(intraday.map(_PositionItem.new));
  }

  if (overnight.isNotEmpty) {
    items.add(
      _SectionItem('OVERNIGHT', overnight.length, sectionPnl(overnight)),
    );
    items.addAll(overnight.map(_PositionItem.new));
  }

  if (mtf.isNotEmpty) {
    items.add(_SectionItem('MTF', mtf.length, sectionPnl(mtf)));
    items.addAll(mtf.map(_PositionItem.new));
  }

  if (holdings.isNotEmpty) {
    items.add(
      _SectionItem('HOLDINGS', holdings.length, holdingsSectionPnl(holdings)),
    );
    items.addAll(holdings.map(_HoldingItem.new));
  }

  return items;
}

// ─── Portfolio Summary Bar ────────────────────────────────────────────────────

class _PortfolioSummaryBar extends StatelessWidget {
  final List<Position> positions;
  final List<Holding> holdings;
  final TradingStore store;

  const _PortfolioSummaryBar({
    required this.positions,
    required this.holdings,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    double totalInvested = 0;
    double totalCurrent = 0;

    for (final p in positions) {
      final ltp = _PositionsScreenState.resolvedLtp(
        store,
        p.symbol,
        p.currentPrice,
        avgPriceFallback: p.avgPrice,
      );
      totalInvested += p.avgPrice * p.quantity;
      totalCurrent += ltp * p.quantity;
    }

    for (final h in holdings) {
      final ltp = _PositionsScreenState.resolvedLtp(
        store,
        h.symbol,
        h.currentPrice,
        avgPriceFallback: h.avgPrice,
      );
      totalInvested += h.avgPrice * h.quantity;
      totalCurrent += ltp * h.quantity;
    }

    final totalPnl = totalCurrent - totalInvested;
    final isProfit = totalPnl >= 0;
    final pnlPct =
        totalInvested == 0 ? 0.0 : (totalPnl / totalInvested) * 100;
    final pnlColor =
        isProfit ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Invested
          _summaryCell(
            'Invested',
            '₹${_compact(totalInvested)}',
            AppColors.textPrimary,
          ),
          _divider(),
          // Current
          _summaryCell(
            'Current',
            '₹${_compact(totalCurrent)}',
            AppColors.textPrimary,
          ),
          _divider(),
          // P&L
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'P&L',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                PriceFlashWidget(
                  price: totalPnl,
                  child: Text(
                    '${isProfit ? '+' : ''}₹${_compact(totalPnl.abs())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: pnlColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 10, color: pnlColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: AppColors.border,
  );

  String _compact(double v) {
    if (v.abs() >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v.abs() >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ─── Select All Row ───────────────────────────────────────────────────────────

class _SelectAllRow extends StatelessWidget {
  final int total;
  final int selected;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselect;

  const _SelectAllRow({
    required this.total,
    required this.selected,
    required this.onSelectAll,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selected == total && total > 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: allSelected ? onDeselect : onSelectAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: allSelected,
                    tristate: selected > 0 && !allSelected,
                    onChanged: (_) =>
                        allSelected ? onDeselect() : onSelectAll(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: const BorderSide(color: Color(0xFFBBBBBB), width: 1.5),
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  allSelected
                      ? 'Deselect all'
                      : selected > 0
                      ? 'Select all ($total)'
                      : 'Select all',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (selected > 0)
            Text(
              '$selected selected',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final _SectionItem item;
  const _SectionHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final isProfit = item.totalPnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              item.title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.count}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '${isProfit ? '+' : ''}₹${item.totalPnl.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: pnlColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Position Card ────────────────────────────────────────────────────────────

class _PositionCard extends StatelessWidget {
  final Position position;
  final double resolvedLtp;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _PositionCard({
    required this.position,
    required this.resolvedLtp,
    required this.isSelected,
    required this.isPending,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = position;
    final ltp = resolvedLtp;
    final isLong = p.side == OrderType.buy;
    final pnl = isLong
        ? (ltp - p.avgPrice) * p.quantity
        : (p.avgPrice - ltp) * p.quantity;
    final pnlPct = p.avgPrice == 0
        ? 0.0
        : (pnl / (p.avgPrice * p.quantity)) * 100;
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;
    final ltpIsStale = p.currentPrice == 0 && ltp == p.avgPrice;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F7FF) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Symbol + checkbox ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    p.symbol,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggle(),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                        side: const BorderSide(
                          color: Color(0xFFBBBBBB),
                          width: 1.5,
                        ),
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 3),

            // ── Subtitle: exchange · product ───────────────────────────────
            Text(
              '${p.exchange} · ${_productSubtitle(p.product)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.2,
              ),
            ),

            const SizedBox(height: 10),

            // ── 4-column metrics: Qty | Avg | LTP | P&L ──────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricCol(label: 'Qty', value: '${p.quantity}', flex: 1),
                _MetricCol(
                  label: isLong ? 'Buy Avg' : 'Sell Avg',
                  value: p.avgPrice.toStringAsFixed(2),
                  flex: 2,
                ),
                _MetricCol(
                  label: ltpIsStale ? 'LTP*' : 'LTP',
                  value: ltp.toStringAsFixed(2),
                  flex: 2,
                ),
                _MetricCol(
                  label: 'P&L',
                  value: isPending ? '…' : '₹${pnl.toStringAsFixed(2)}',
                  sub: isPending ? null : '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                  valueColor: pnlColor,
                  subColor: pnlColor,
                  align: CrossAxisAlignment.end,
                  flash: pnl,
                  flex: 2,
                ),
              ],
            ),

            if (p.product == ProductType.mis && p.marginUsed > 0) ...[
              const SizedBox(height: 6),
              _RmsBar(pnl: pnl, marginUsed: p.marginUsed),
            ],

            if (ltpIsStale) ...[
              const SizedBox(height: 3),
              Text(
                '* Showing last known price',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Holding Card ─────────────────────────────────────────────────────────────

class _HoldingCard extends StatelessWidget {
  final Holding holding;
  final double resolvedLtp;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _HoldingCard({
    required this.holding,
    required this.resolvedLtp,
    required this.isSelected,
    required this.isPending,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final ltp = resolvedLtp;
    final pnl = (ltp - h.avgPrice) * h.quantity;
    final pnlPct =
        h.avgPrice == 0 ? 0.0 : (pnl / (h.avgPrice * h.quantity)) * 100;
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;
    final ltpIsStale = h.currentPrice == 0 && ltp == h.avgPrice;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F7FF) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Symbol + checkbox ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    h.symbol,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggle(),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                        side: const BorderSide(
                          color: Color(0xFFBBBBBB),
                          width: 1.5,
                        ),
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 3),

            // ── Subtitle: exchange · Delivery ──────────────────────────────
            Text(
              'NSE · Delivery',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.2,
              ),
            ),

            const SizedBox(height: 10),

            // ── 4-column metrics: Qty | Buy Avg | LTP | P&L ──────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricCol(label: 'Qty', value: '${h.quantity}', flex: 1),
                _MetricCol(
                  label: 'Buy Avg',
                  value: h.avgPrice.toStringAsFixed(2),
                  flex: 2,
                ),
                _MetricCol(
                  label: ltpIsStale ? 'LTP*' : 'LTP',
                  value: ltp.toStringAsFixed(2),
                  flex: 2,
                ),
                _MetricCol(
                  label: 'P&L',
                  value: isPending ? '…' : '₹${pnl.toStringAsFixed(2)}',
                  sub: isPending ? null : '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                  valueColor: pnlColor,
                  subColor: pnlColor,
                  align: CrossAxisAlignment.end,
                  flash: pnl,
                  flex: 2,
                ),
              ],
            ),

            if (ltpIsStale) ...[
              const SizedBox(height: 3),
              Text(
                '* Showing last known price',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Floating Square Off FAB ──────────────────────────────────────────────────

class _FloatingSquareOffFab extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FloatingSquareOffFab({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: count > 0 ? Offset.zero : const Offset(0, 1.6),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: count > 0 ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.zap, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Square Off ($count)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MIS Warning Banner ───────────────────────────────────────────────────────

class _MisWarningBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _MisWarningBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 13, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Intraday positions will be auto squared-off before 3:30 PM.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(LucideIcons.x, size: 14, color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.trendingUp, size: 48, color: AppColors.border),
          const SizedBox(height: 16),
          const Text(
            'No open positions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your intraday positions, overnight trades,\nand holdings will all appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Aligned metric column ────────────────────────────────────────────────────
//
// Matches the reference broker UI: label on top (10px gray), value below
// (13px medium), optional sub-value for P&L percentage (10px colored).
// The last column uses CrossAxisAlignment.end so P&L sits flush right.
//
// [flash] triggers PriceFlashWidget animation on tick updates.

class _MetricCol extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String? sub;
  final Color? subColor;
  final CrossAxisAlignment align;
  final double? flash;
  /// Flex weight for this column (default 2). Use 1 for Qty, 2 for prices/P&L.
  final int flex;

  const _MetricCol({
    required this.label,
    required this.value,
    this.valueColor,
    this.sub,
    this.subColor,
    this.align = CrossAxisAlignment.start,
    this.flash,
    this.flex = 2,
  });

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: valueColor ?? AppColors.textPrimary,
        height: 1.25,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      softWrap: false,            // numbers must never wrap mid-digit
      overflow: TextOverflow.ellipsis,
    );

    return Expanded(
      flex: flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              height: 1.2,
            ),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          flash != null
              ? PriceFlashWidget(price: flash!, child: valueWidget)
              : valueWidget,
          if (sub != null)
            Text(
              sub!,
              style: TextStyle(
                fontSize: 10,
                color: subColor ?? AppColors.textSecondary,
                height: 1.2,
              ),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _RmsBar extends StatelessWidget {
  final double pnl;
  final double marginUsed;
  const _RmsBar({required this.pnl, required this.marginUsed});

  @override
  Widget build(BuildContext context) {
    final loss = pnl < 0 ? pnl.abs() : 0.0;
    final riskPct =
        marginUsed > 0 ? (loss / marginUsed * 100).clamp(0.0, 100.0) : 0.0;

    final Color barColor;
    final String label;
    if (riskPct >= 80) {
      barColor = AppColors.danger;
      label = 'DANGER';
    } else if (riskPct >= 50) {
      barColor = AppColors.warning;
      label = 'WARNING';
    } else {
      barColor = AppColors.success;
      label = 'SAFE';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Risk ${riskPct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: barColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: barColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: riskPct / 100,
            minHeight: 3,
            backgroundColor: const Color(0xFFE0E0E0),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

/// Human-readable subtitle segment: "Intraday", "Overnight", "Delivery", "MTF"
String _productSubtitle(ProductType p) => switch (p) {
  ProductType.mis => 'Intraday',
  ProductType.nrml => 'Overnight',
  ProductType.overnight => 'Delivery',
  ProductType.mtf => 'MTF',
};


extension _SetDiscard<T> on Set<T> {
  void discard(T item) => remove(item);
}
