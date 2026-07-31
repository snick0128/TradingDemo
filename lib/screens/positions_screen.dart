import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/instrument_logo.dart';
import '../widgets/multi_square_off_dialog.dart';
import '../widgets/position_detail_sheet.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/trading_bottom_nav_bar.dart';

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
  final Set<String> _selected = {};
  final Set<String> _pending = {};

  // positionsVersion listener — rebuilds only when positions/holdings change,
  // never on price ticks (which flow through per-symbol ltpNotifier VLBs).
  TradingStore? _store;
  List<Position> _positions = const [];
  List<Holding>  _holdings  = const [];
  List<Order>    _orders    = const [];

  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  @override
  void initState() {
    super.initState();
    _settingsSub = _settingsService.stream.listen((s) {
      if (mounted) setState(() => _marketSettings = s);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.positionsVersion.removeListener(_onPositionsChanged);
      _store?.ordersVersion.removeListener(_onOrdersForReservedChanged);
      _store = store;
      store.positionsVersion.addListener(_onPositionsChanged);
      store.ordersVersion.addListener(_onOrdersForReservedChanged);
      _syncFromStore(store);
    }
  }

  void _syncFromStore(TradingStore store) {
    _positions = store.positions.toList();
    _holdings  = store.holdings.toList();
    _orders    = store.orders.toList();
  }

  // Fires only when replacePositions/replaceHoldings/convertPositionProduct
  // increment positionsVersion — never on price ticks.
  void _onPositionsChanged() {
    if (_store == null || !mounted) return;
    _syncFromStore(_store!);
    setState(() {});
  }

  void _onOrdersForReservedChanged() {
    if (_store == null || !mounted) return;
    _orders = _store!.orders.toList();
    setState(() {});
  }

  @override
  void dispose() {
    _store?.positionsVersion.removeListener(_onPositionsChanged);
    _store?.ordersVersion.removeListener(_onOrdersForReservedChanged);
    _settingsSub?.cancel();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

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

    // Market hours guard — same validation as Buy/Sell orders.
    final marketReason = _marketSettings.checkAction(
      p.exchange,
      isBuy: p.side == OrderType.sell, // square-off BUYs a short, SELLs a long
    );
    if (marketReason != null) {
      if (ctx.mounted) {
        AppToast.error(
          ctx,
          'Market is closed. Positions can only be squared off during market hours.',
        );
      }
      if (mounted) setState(() => _pending.remove(key));
      return;
    }

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

    // Market hours guard — holdings are always equity (CNC SELL).
    final holdingExchange =
        TradingScope.read(ctx).stockBySymbolOrNull(h.symbol)?.exchange ?? 'NSE';
    final holdingMarketReason = _marketSettings.checkAction(
      holdingExchange,
      isBuy: false,
    );
    if (holdingMarketReason != null) {
      if (ctx.mounted) {
        AppToast.error(
          ctx,
          'Market is closed. Positions can only be squared off during market hours.',
        );
      }
      if (mounted) setState(() => _pending.remove(key));
      return;
    }

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

  Future<void> squareOffPositionLimit(
    BuildContext ctx,
    Position p,
    int qty,
    double limitPrice,
  ) async {
    final key = _posKey(p);
    if (_pending.contains(key)) return;
    setState(() => _pending.add(key));

    final marketReason = _marketSettings.checkAction(
      p.exchange,
      isBuy: p.side == OrderType.sell,
    );
    if (marketReason != null) {
      if (ctx.mounted) {
        AppToast.error(ctx, 'Market is closed. Limit exits can only be placed during market hours.');
      }
      if (mounted) setState(() => _pending.remove(key));
      return;
    }

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
        final ltp = resolvedLtp(store, p.symbol, p.currentPrice, avgPriceFallback: p.avgPrice);
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: p.symbol,
          qty: qty,
          type: exitType,
          productType: productStr,
          exchange: p.exchange,
          variety: 'LIMIT',
          limitPrice: limitPrice,
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId: '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_lsq',
        );
        if (ctx.mounted) {
          AppToast.success(ctx, '${p.symbol} limit exit @ ₹${limitPrice.toStringAsFixed(2)} placed');
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

  Future<void> squareOffPositionSL(
    BuildContext ctx,
    Position p,
    int qty,
    double triggerPrice,
  ) async {
    final key = _posKey(p);
    if (_pending.contains(key)) return;
    setState(() => _pending.add(key));

    final marketReason = _marketSettings.checkAction(
      p.exchange,
      isBuy: p.side == OrderType.sell,
    );
    if (marketReason != null) {
      if (ctx.mounted) {
        AppToast.error(ctx, 'Market is closed. Stop-loss exits can only be placed during market hours.');
      }
      if (mounted) setState(() => _pending.remove(key));
      return;
    }

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
        final ltp = resolvedLtp(store, p.symbol, p.currentPrice, avgPriceFallback: p.avgPrice);
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: p.symbol,
          qty: qty,
          type: exitType,
          productType: productStr,
          exchange: p.exchange,
          variety: 'SL_MARKET',
          triggerPrice: triggerPrice,
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId: '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_slsq',
        );
        if (ctx.mounted) {
          AppToast.success(ctx, '${p.symbol} SL exit @ ₹${triggerPrice.toStringAsFixed(2)} placed');
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
      marketSettings: _marketSettings,
      onCompleted: () {
        if (mounted) _deselectAll();
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = _store ?? TradingScope.read(context);
    final positions = _positions;
    final holdings = _holdings;

    // Shimmer guard — wait for first data
    if (store.knownStocks.isEmpty && !store.backendError) {
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
                      padding: EdgeInsets.fromLTRB(12, 4, 12, TradingBottomNavBar.bottomInset(context) + 72),
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
                                store: store,
                                orders: _orders,
                                isSelected: _selected.contains(_posKey(position)),
                                isPending: _pending.contains(_posKey(position)),
                                onToggle: () => _toggle(_posKey(position)),
                                onSquareOff: () async {
                                  final exitSide = position.side == OrderType.buy ? OrderType.sell : OrderType.buy;
                                  final reserved = _orders
                                      .where((o) =>
                                          o.status == OrderStatus.pending &&
                                          o.symbol == position.symbol &&
                                          o.type == exitSide)
                                      .fold<int>(0, (s, o) => s + o.quantity);
                                  final available = (position.quantity - reserved).clamp(0, position.quantity);
                                  if (!ctx.mounted) return;
                                  if (available <= 0) {
                                    AppToast.error(ctx, 'All qty is reserved in pending exit orders');
                                    return;
                                  }
                                  final result = await _ExitPositionDialog.show(ctx, position, store, available);
                                  if (result == null || !ctx.mounted) return;
                                  switch (result.kind) {
                                    case _ExitKind.market:
                                      await squareOffPosition(ctx, position, result.qty);
                                    case _ExitKind.limit:
                                      await squareOffPositionLimit(ctx, position, result.qty, result.limitPrice!);
                                    case _ExitKind.sl:
                                      await squareOffPositionSL(ctx, position, result.qty, result.triggerPrice!);
                                  }
                                },
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
                                store: store,
                                isSelected: _selected.contains(_hldKey(holding)),
                                isPending: _pending.contains(_hldKey(holding)),
                                onToggle: () => _toggle(_hldKey(holding)),
                                onSquareOff: () => squareOffHolding(ctx, holding),
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
          bottom: TradingBottomNavBar.bottomInset(context) + 8,
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

  double sectionPnl(List<Position> ps, String groupName) {
    final headerPnl = ps.fold<double>(0, (sum, p) => sum + p.unrealizedPnl);
    final positionPnls = ps.map((p) => p.unrealizedPnl).toList();
    debugPrint('[GROUP_PNL] group=$groupName count=${ps.length} headerPnl=${headerPnl.toStringAsFixed(2)} positionPnls=$positionPnls');
    return headerPnl;
  }

  double holdingsSectionPnl(List<Holding> hs) {
    return hs.fold(0.0, (s, h) {
      final ltp = _PositionsScreenState.resolvedLtp(
        store,
        h.symbol,
        h.currentPrice,
        avgPriceFallback: h.avgPrice,
      );
      return s + h.calculatePnL(ltp);
    });
  }

  if (intraday.isNotEmpty) {
    items.add(_SectionItem('INTRADAY', intraday.length, sectionPnl(intraday, 'INTRADAY')));
    items.addAll(intraday.map(_PositionItem.new));
  }

  if (overnight.isNotEmpty) {
    items.add(
      _SectionItem('OVERNIGHT', overnight.length, sectionPnl(overnight, 'OVERNIGHT')),
    );
    items.addAll(overnight.map(_PositionItem.new));
  }

  if (mtf.isNotEmpty) {
    items.add(_SectionItem('MTF', mtf.length, sectionPnl(mtf, 'MTF')));
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

// _PortfolioSummaryBar: static invested figure; live P&L via runningPnlNotifier
// so the bar updates on every tick without rebuilding the full positions list.
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
    // Invested is static between position changes
    double totalInvested = 0;
    for (final p in positions) totalInvested += p.avgPrice * p.quantity;
    for (final h in holdings) totalInvested += h.avgPrice * h.quantity;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _summaryCell('Invested', '₹${_compact(totalInvested)}', AppColors.textPrimary),
          _divider(),
          // Live current value and P&L — rebuilt only when runningPnlNotifier fires
          Expanded(
            child: ListenableBuilder(
              listenable: store.runningPnlNotifier,
              builder: (_, __) {
                double totalPnl = 0;
                for (final p in positions) {
                  final ltp = store.lastValidLtp(p.symbol);
                  totalPnl += p.calculatePnL(ltp);
                }
                for (final h in holdings) {
                  final ltp = store.lastValidLtp(h.symbol);
                  totalPnl += h.calculatePnL(ltp);
                }
                final totalCurrent = totalInvested + totalPnl;
                final isProfit = totalPnl >= 0;
                final pnlPct   = totalInvested == 0 ? 0.0 : (totalPnl / totalInvested) * 100;
                final pnlColor = isProfit ? AppColors.success : AppColors.danger;

                return Row(
                  children: [
                    _summaryCell('Current', '₹${_compact(totalCurrent)}', AppColors.textPrimary),
                    _divider(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('P&L', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
                );
              },
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
        ],
      ),
    );
  }
}

// ─── Position Card ────────────────────────────────────────────────────────────

// _PositionCard: symbol/meta/checkbox are static; only the 4-metric row (LTP,
// P&L, RMS bar) lives inside a ValueListenableBuilder so it rebuilds per-tick
// for this symbol only, not for the whole list.
class _PositionCard extends StatelessWidget {
  final Position position;
  final TradingStore store;
  final List<Order> orders;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onSquareOff;

  const _PositionCard({
    required this.position,
    required this.store,
    required this.orders,
    required this.isSelected,
    required this.isPending,
    required this.onToggle,
    required this.onTap,
    required this.onSquareOff,
  });

  @override
  Widget build(BuildContext context) {
    final p = position;
    final isLong = p.side == OrderType.buy;
    final exitType = isLong ? OrderType.sell : OrderType.buy;
    final reservedQty = orders
        .where((o) =>
            o.status == OrderStatus.pending &&
            o.symbol == p.symbol &&
            o.type == exitType)
        .fold<int>(0, (s, o) => s + o.quantity);
    final availableQty = (p.quantity - reservedQty).clamp(0, p.quantity);

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
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: side badge + symbol + exit button + checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLong ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isLong ? Icons.arrow_upward : Icons.arrow_downward, size: 9, color: isLong ? AppColors.success : AppColors.danger),
                      const SizedBox(width: 2),
                      Text(isLong ? 'BUY' : 'SHORT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isLong ? AppColors.success : AppColors.danger)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InstrumentLogo(symbol: p.symbol, exchange: p.exchange, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                GestureDetector(
                  onTap: isPending ? null : onSquareOff,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: isPending ? AppColors.border : AppColors.danger),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPending ? '…' : 'Exit',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isPending ? AppColors.textSecondary : AppColors.danger),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => onToggle(),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      side: const BorderSide(color: Color(0xFFBBBBBB), width: 1.5),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${p.exchange} · ${_productSubtitle(p.product)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.2),
            ),
            const SizedBox(height: 10),

            // 4-metric row — rebuilds only when this symbol's LTP changes
            ValueListenableBuilder<double>(
              valueListenable: store.ltpNotifier(p.symbol),
              builder: (_, livePrice, __) {
                final ltp = _PositionsScreenState.resolvedLtp(
                  store, p.symbol, p.currentPrice, avgPriceFallback: p.avgPrice);
                final effectiveLtp = livePrice > 0 ? livePrice : ltp;
                final pnl = p.calculatePnL(effectiveLtp);
                final pnlPct = p.avgPrice == 0 ? 0.0 : (pnl / (p.avgPrice * p.quantity)) * 100;
                final isProfit = pnl >= 0;
                final pnlColor = isProfit ? AppColors.success : AppColors.danger;
                final ltpIsStale = p.currentPrice == 0 && livePrice == 0;

                final invested = p.avgPrice * p.quantity;
                final current  = effectiveLtp * p.quantity;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MetricCol(
                          label: 'Qty',
                          value: '${p.quantity}',
                          sub: reservedQty > 0 ? 'Avail: $availableQty' : null,
                          subColor: reservedQty > 0 ? const Color(0xFFE65100) : null,
                          flex: 1,
                        ),
                        _MetricCol(label: 'Avg', value: p.avgPrice.toStringAsFixed(2), flex: 2),
                        _MetricCol(label: ltpIsStale ? 'LTP*' : 'LTP', value: effectiveLtp.toStringAsFixed(2), flex: 2),
                        _MetricCol(
                          label: 'P&L',
                          value: isPending ? '…' : '${isProfit ? '+' : '−'}₹${pnl.abs().toStringAsFixed(0)}',
                          sub: isPending ? null : '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                          valueColor: pnlColor,
                          subColor: pnlColor,
                          align: CrossAxisAlignment.end,
                          flash: pnl,
                          flex: 2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MetricCol(label: 'Invested', value: '₹${invested.toStringAsFixed(0)}', flex: 3),
                        _MetricCol(label: 'Current', value: '₹${current.toStringAsFixed(0)}', flex: 3, valueColor: isProfit ? AppColors.success : AppColors.danger),
                        const Spacer(),
                      ],
                    ),
                    if (ltpIsStale) ...[
                      const SizedBox(height: 3),
                      Text(
                        '* Showing last known price',
                        style: TextStyle(fontSize: 9, color: AppColors.textSecondary.withValues(alpha: 0.6), fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Holding Card ─────────────────────────────────────────────────────────────

// _HoldingCard: same pattern as _PositionCard — static header, VLB metrics row.
class _HoldingCard extends StatelessWidget {
  final Holding holding;
  final TradingStore store;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onSquareOff;

  const _HoldingCard({
    required this.holding,
    required this.store,
    required this.isSelected,
    required this.isPending,
    required this.onToggle,
    required this.onTap,
    required this.onSquareOff,
  });

  @override
  Widget build(BuildContext context) {
    final h = holding;

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
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: BUY badge + symbol + exit button + checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(4)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_upward, size: 9, color: AppColors.success),
                      SizedBox(width: 2),
                      Text('BUY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InstrumentLogo(symbol: h.symbol, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    h.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                GestureDetector(
                  onTap: isPending ? null : onSquareOff,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: isPending ? AppColors.border : AppColors.danger),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPending ? '…' : 'Exit',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isPending ? AppColors.textSecondary : AppColors.danger),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => onToggle(),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      side: const BorderSide(color: Color(0xFFBBBBBB), width: 1.5),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text('NSE · Delivery', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.2)),
            const SizedBox(height: 10),

            // 4-metric row — rebuilds only when this symbol's LTP changes
            ValueListenableBuilder<double>(
              valueListenable: store.ltpNotifier(h.symbol),
              builder: (_, livePrice, __) {
                final ltp = _PositionsScreenState.resolvedLtp(
                  store, h.symbol, h.currentPrice, avgPriceFallback: h.avgPrice);
                final effectiveLtp = livePrice > 0 ? livePrice : ltp;
                final pnl = (effectiveLtp - h.avgPrice) * h.quantity;
                final pnlPct = h.avgPrice == 0 ? 0.0 : (pnl / (h.avgPrice * h.quantity)) * 100;
                final isProfit = pnl >= 0;
                final pnlColor = isProfit ? AppColors.success : AppColors.danger;
                final ltpIsStale = h.currentPrice == 0 && livePrice == 0;

                final invested = h.avgPrice * h.quantity;
                final current  = effectiveLtp * h.quantity;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MetricCol(label: 'Qty', value: '${h.quantity}', flex: 1),
                        _MetricCol(label: 'Avg', value: h.avgPrice.toStringAsFixed(2), flex: 2),
                        _MetricCol(label: ltpIsStale ? 'LTP*' : 'LTP', value: effectiveLtp.toStringAsFixed(2), flex: 2),
                        _MetricCol(
                          label: 'P&L',
                          value: isPending ? '…' : '${isProfit ? '+' : '−'}₹${pnl.abs().toStringAsFixed(0)}',
                          sub: isPending ? null : '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                          valueColor: pnlColor,
                          subColor: pnlColor,
                          align: CrossAxisAlignment.end,
                          flash: pnl,
                          flex: 2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MetricCol(label: 'Invested', value: '₹${invested.toStringAsFixed(0)}', flex: 3),
                        _MetricCol(label: 'Current', value: '₹${current.toStringAsFixed(0)}', flex: 3, valueColor: isProfit ? AppColors.success : AppColors.danger),
                        const Spacer(),
                      ],
                    ),
                    if (ltpIsStale) ...[
                      const SizedBox(height: 3),
                      Text(
                        '* Showing last known price',
                        style: TextStyle(fontSize: 9, color: AppColors.textSecondary.withValues(alpha: 0.6), fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                );
              },
            ),
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

// ─── Exit Position Dialog ─────────────────────────────────────────────────────

enum _ExitKind { market, limit, sl }

class _ExitResult {
  final int qty;
  final _ExitKind kind;
  final double? limitPrice;
  final double? triggerPrice;
  const _ExitResult({required this.qty, required this.kind, this.limitPrice, this.triggerPrice});
}

class _ExitPositionDialog extends StatefulWidget {
  final Position position;
  final TradingStore store;
  final int maxQty;

  const _ExitPositionDialog({
    required this.position,
    required this.store,
    required this.maxQty,
  });

  static Future<_ExitResult?> show(
    BuildContext ctx,
    Position position,
    TradingStore store,
    int maxQty,
  ) {
    return showDialog<_ExitResult>(
      context: ctx,
      builder: (_) => _ExitPositionDialog(position: position, store: store, maxQty: maxQty),
    );
  }

  @override
  State<_ExitPositionDialog> createState() => _ExitPositionDialogState();
}

class _ExitPositionDialogState extends State<_ExitPositionDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _triggerCtrl;
  _ExitKind _kind = _ExitKind.market;
  String? _inputError;

  Position get p => widget.position;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.maxQty}');
    final ltp = widget.store.lastValidLtp(p.symbol);
    final seed = ltp > 0 ? ltp : (p.currentPrice > 0 ? p.currentPrice : p.avgPrice);
    final seedText = seed > 0 ? seed.toStringAsFixed(2) : p.avgPrice.toStringAsFixed(2);
    _priceCtrl = TextEditingController(text: seedText);
    _triggerCtrl = TextEditingController(text: seedText);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _triggerCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0 || qty > widget.maxQty) {
      setState(() => _inputError = 'Enter qty between 1 and ${widget.maxQty}');
      return;
    }
    switch (_kind) {
      case _ExitKind.limit:
        final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
        if (price <= 0) {
          setState(() => _inputError = 'Enter a valid limit price');
          return;
        }
        Navigator.pop(context, _ExitResult(qty: qty, kind: _ExitKind.limit, limitPrice: price));
      case _ExitKind.sl:
        final trigger = double.tryParse(_triggerCtrl.text.trim()) ?? 0;
        if (trigger <= 0) {
          setState(() => _inputError = 'Enter a valid trigger price');
          return;
        }
        Navigator.pop(context, _ExitResult(qty: qty, kind: _ExitKind.sl, triggerPrice: trigger));
      case _ExitKind.market:
        Navigator.pop(context, _ExitResult(qty: qty, kind: _ExitKind.market));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLong = p.side == OrderType.buy;
    final exitLabel = isLong ? 'EXIT LONG' : 'EXIT SHORT';
    final exitColor = isLong ? AppColors.danger : AppColors.success;
    final exitBg    = isLong ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: exitBg, borderRadius: BorderRadius.circular(5)),
            child: Text(exitLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: exitColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p.symbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Held: ${p.quantity} qty  ·  Avg ₹${p.avgPrice.toStringAsFixed(2)}  ·  ${p.exchange}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text('Quantity (max ${widget.maxQty})', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              errorText: _inputError,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Order Type', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              _TypeBtn(label: 'Market', selected: _kind == _ExitKind.market, onTap: () => setState(() { _kind = _ExitKind.market; _inputError = null; })),
              const SizedBox(width: 8),
              _TypeBtn(label: 'Limit', selected: _kind == _ExitKind.limit, onTap: () => setState(() { _kind = _ExitKind.limit; _inputError = null; })),
              const SizedBox(width: 8),
              _TypeBtn(label: 'SL', selected: _kind == _ExitKind.sl, onTap: () => setState(() { _kind = _ExitKind.sl; _inputError = null; })),
            ],
          ),
          if (_kind == _ExitKind.limit) ...[
            const SizedBox(height: 12),
            const Text('Exit at Price (₹)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
              decoration: const InputDecoration(
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'A pending exit order will be placed. Position stays open until filled.',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ],
          if (_kind == _ExitKind.sl) ...[
            const SizedBox(height: 12),
            const Text('Trigger Price (₹)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            TextField(
              controller: _triggerCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
              decoration: const InputDecoration(
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isLong
                  ? 'Squares off automatically at market price when the price falls to or below this level.'
                  : 'Squares off automatically at market price when the price rises to or above this level.',
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: exitColor, foregroundColor: Colors.white),
          onPressed: _confirm,
          child: Text(switch (_kind) {
            _ExitKind.limit => 'Place Limit Exit',
            _ExitKind.sl => 'Place SL Exit',
            _ExitKind.market => 'Exit Position',
          }),
        ),
      ],
    );
  }
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
