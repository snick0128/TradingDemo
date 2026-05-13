import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/shared_widgets.dart';

class PositionsScreen extends StatefulWidget {
  final bool showAppBar;
  const PositionsScreen({super.key, this.showAppBar = true});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  Timer? _squareOffTimer;
  final Set<String> _pendingSquareOff = <String>{};

  @override
  void initState() {
    super.initState();
    _scheduleMisSquareOffWarning();
  }

  @override
  void dispose() {
    _squareOffTimer?.cancel();
    super.dispose();
  }

  void _scheduleMisSquareOffWarning() {
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

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final positions = store.positions.toList();
    final hasMis = positions.any((p) => p.product == ProductType.mis);

    final body = Column(
      children: [
        // MIS warning — subtle, not dominating
        if (store.showMisSquareOffWarning && hasMis)
          _MisWarningBanner(
            onDismiss: () => store.setMisSquareOffWarning(false),
          ),

        // Summary header
        if (positions.isNotEmpty)
          _SummaryHeader(
            positions: positions,
            onSquareOffAll: () => _squareOffAll(context, store),
          ),

        // List
        Expanded(
          child: positions.isEmpty
              ? _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: positions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _PositionCard(
                    position: positions[i],
                    onExit: (p) =>
                        _squareOffPosition(context, store, p, p.quantity),
                    onPartialExit: (p) =>
                        _showPartialExitDialog(context, store, p),
                    onConvert: (p) => _convertPosition(context, store, p),
                  ),
                ),
        ),
      ],
    );

    if (!widget.showAppBar) return Scaffold(body: body);

    return Scaffold(
      appBar: AppBar(title: Text('Positions (${positions.length})')),
      body: body,
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _squareOffPosition(
    BuildContext context,
    TradingStore store,
    Position p,
    int qty,
  ) async {
    final pendingKey = '${p.symbol}_${qty}_${p.side.name}';
    if (_pendingSquareOff.contains(pendingKey)) return;
    _pendingSquareOff.add(pendingKey);
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();

    if (appScope != null) {
      final sessionUser = appScope.notifier?.user;
      if (sessionUser == null) {
        AppToast.error(context, 'Session expired. Please login again.');
        return;
      }
      try {
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        // Sell = exit a long position; Buy = exit a short position
        final exitType = p.side == OrderType.buy ? 'SELL' : 'BUY';
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: p.symbol,
          qty: qty,
          type: exitType,
          clientRequestId:
              '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_sq',
        );
        if (context.mounted) {
          AppToast.success(context, '${p.symbol} exited ($qty qty)');
        }
      } on BackendException catch (e) {
        if (context.mounted) AppToast.error(context, e.message);
      } catch (e) {
        if (context.mounted) {
          AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
        }
      } finally {
        _pendingSquareOff.remove(pendingKey);
      }
      return;
    }

    // Offline/mock path
    final result = store.placeOrder(
      symbol: p.symbol,
      quantity: qty,
      type: p.side == OrderType.buy ? OrderType.sell : OrderType.buy,
      variety: OrderVariety.market,
      product: p.product,
    );
    final msg = result.success
        ? '${p.symbol} exited'
        : (result.errorMessage ?? 'Failed');
    if (result.success) {
      AppToast.success(context, msg);
    } else {
      AppToast.error(context, msg);
    }
    _pendingSquareOff.remove(pendingKey);
  }

  void _squareOffAll(BuildContext context, TradingStore store) {
    AppDialog.destructive(
      context,
      title: 'Square Off All',
      message: 'Close all open positions at market price?',
      confirmLabel: 'Square Off All',
      onConfirm: () {
        for (final p in List<Position>.from(store.positions)) {
          _squareOffPosition(context, store, p, p.quantity);
        }
      },
    );
  }

  void _showPartialExitDialog(
    BuildContext context,
    TradingStore store,
    Position p,
  ) {
    final ctrl = TextEditingController(text: '${p.quantity}');
    AppDialog.confirm(
      context,
      title: 'Exit ${p.symbol}',
      message: 'Available: ${p.quantity} qty',
      body: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Quantity to exit'),
      ),
      confirmLabel: 'Exit',
      onConfirm: () {
        final qty = int.tryParse(ctrl.text) ?? 0;
        if (qty <= 0 || qty > p.quantity) return;
        _squareOffPosition(context, store, p, qty);
      },
    );
  }

  void _convertPosition(BuildContext context, TradingStore store, Position p) {
    final to = p.product == ProductType.mis
        ? ProductType.overnight
        : ProductType.mis;
    store.convertPositionProduct(p.symbol, p.product, to);
    AppToast.info(context, '${p.symbol} → ${to.name.toUpperCase()}');
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
      color: AppColors.warning.withOpacity(0.08),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 13, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚠ Auto square-off at 3:20 PM for MIS positions',
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

// ─── Summary Header ───────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final List<Position> positions;
  final VoidCallback onSquareOffAll;

  const _SummaryHeader({required this.positions, required this.onSquareOffAll});

  @override
  Widget build(BuildContext context) {
    final totalInvested = positions.fold(0.0, (s, p) => s + p.investedValue);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          Text(
            '${positions.length} open position${positions.length == 1 ? '' : 's'} · Invested ₹${_fmt(totalInvested)}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSquareOffAll,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD50000)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Square Off All',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFD50000),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    return v.toStringAsFixed(0);
  }
}

// ─── Position Card ────────────────────────────────────────────────────────────

class _PositionCard extends StatelessWidget {
  final Position position;
  final void Function(Position) onExit;
  final void Function(Position) onPartialExit;
  final void Function(Position) onConvert;

  const _PositionCard({
    required this.position,
    required this.onExit,
    required this.onPartialExit,
    required this.onConvert,
  });

  @override
  Widget build(BuildContext context) {
    final p = position;
    final isPos = p.unrealizedPnl >= 0;
    final pnlColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);
    final barColor = pnlColor;
    final isLong = p.side == OrderType.buy;
    final arrow = isPos ? '▲' : '▼';
    final canConvert =
        p.product == ProductType.mis || p.product == ProductType.overnight;
    final convertLabel = p.product == ProductType.mis ? '→Overnight' : '→MIS';

    return IntrinsicHeight(
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left 3dp color bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: symbol + LONG/SHORT badge left · P&L right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Symbol + badge
                        Row(
                          children: [
                            Text(
                              p.symbol,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0D0D0D),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isLong
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isLong ? 'LONG' : 'SHORT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isLong
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFC62828),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // P&L value
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            PriceFlashWidget(
                              price: p.unrealizedPnl,
                              child: Text(
                                '$arrow ₹${p.unrealizedPnl.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: pnlColor,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              '$arrow ${p.pnlPercentage.abs().toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF757575),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Mid row: LTP + qty
                    Row(
                      children: [
                        PriceFlashWidget(
                          price: p.currentPrice,
                          child: Text(
                            '₹${p.currentPrice.toStringAsFixed(2)} LTP',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0D0D0D),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${p.quantity} qty',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF757575),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Bottom row: avg + product badge + EXIT button
                    Row(
                      children: [
                        Text(
                          'Avg ₹${p.avgPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.product == ProductType.mis
                                ? const Color(0xFFFFF8E1)
                                : const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p.product.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: p.product == ProductType.mis
                                  ? const Color(0xFFF57F17)
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (canConvert) ...[
                          GestureDetector(
                            onTap: () => onConvert(p),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE0E0E0),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                convertLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF757575),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // EXIT button
                        GestureDetector(
                          onTap: () => onExit(p),
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD50000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'EXIT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ), // IntrinsicHeight
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
            'Your intraday and overnight positions will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
