import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class PositionsScreen extends StatefulWidget {
  final bool showAppBar;
  const PositionsScreen({super.key, this.showAppBar = true});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  Timer? _squareOffTimer;

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

  void _squareOffPosition(
    BuildContext context,
    TradingStore store,
    Position p,
    int qty,
  ) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: result.success ? AppColors.success : AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _squareOffAll(BuildContext context, TradingStore store) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Square Off All'),
        content: const Text('Close all open positions at market price?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              for (final p in List<Position>.from(store.positions)) {
                _squareOffPosition(context, store, p, p.quantity);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Square Off All'),
          ),
        ],
      ),
    );
  }

  void _showPartialExitDialog(
    BuildContext context,
    TradingStore store,
    Position p,
  ) {
    final ctrl = TextEditingController(text: '${p.quantity}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit ${p.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available: ${p.quantity} qty',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Quantity to exit'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(ctrl.text) ?? 0;
              if (qty <= 0 || qty > p.quantity) return;
              Navigator.pop(ctx);
              _squareOffPosition(context, store, p, qty);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _convertPosition(BuildContext context, TradingStore store, Position p) {
    final to = p.product == ProductType.mis ? ProductType.cnc : ProductType.mis;
    store.convertPositionProduct(p.symbol, p.product, to);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.symbol} → ${to.name.toUpperCase()}'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final totalPnl = positions.fold(0.0, (s, p) => s + p.unrealizedPnl);
    final totalInvested = positions.fold(0.0, (s, p) => s + p.investedValue);
    final isPos = totalPnl >= 0;
    final pnlPct = totalInvested == 0 ? 0.0 : (totalPnl / totalInvested) * 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: counts + invested
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${positions.length} Open Position${positions.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Invested ₹${_fmt(totalInvested)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Right: P&L (dominant) + Square Off All
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPos ? '+' : ''}₹${totalPnl.abs().toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isPos ? AppColors.success : AppColors.danger,
                ),
              ),
              Text(
                '${isPos ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPos ? AppColors.success : AppColors.danger,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onSquareOffAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Square Off All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ),
            ],
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
    final pnlColor = isPos ? AppColors.success : AppColors.danger;
    final isLong = p.side == OrderType.buy;
    final canConvert =
        p.product == ProductType.mis || p.product == ProductType.cnc;
    final convertLabel = p.product == ProductType.mis ? '→CNC' : '→MIS';

    return GestureDetector(
      onTap: () => onPartialExit(p),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Symbol + P&L (primary) ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Symbol + side tag
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        p.symbol,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (isLong ? AppColors.success : AppColors.danger)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isLong ? 'LONG' : 'SHORT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isLong
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // P&L — dominant, right-aligned
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PriceFlashWidget(
                      price: p.unrealizedPnl,
                      child: Text(
                        '${isPos ? '+' : ''}₹${p.unrealizedPnl.abs().toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: pnlColor,
                        ),
                      ),
                    ),
                    Text(
                      '${isPos ? '+' : ''}${p.pnlPercentage.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pnlColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Row 2: LTP + Qty (secondary) ───────────────────────────
            Row(
              children: [
                PriceFlashWidget(
                  price: p.currentPrice,
                  child: Text(
                    '₹${p.currentPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'LTP',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${p.quantity} qty',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // ── Row 3: Avg + Product (tertiary) ────────────────────────
            Row(
              children: [
                Text(
                  'Avg ₹${p.avgPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.product == ProductType.mis
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p.product.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: p.product == ProductType.mis
                          ? AppColors.warning
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Row 4: Actions ──────────────────────────────────────────
            Row(
              children: [
                // Convert — secondary, small
                if (canConvert) ...[
                  GestureDetector(
                    onTap: () => onConvert(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        convertLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                // Exit — primary, filled
                GestureDetector(
                  onTap: () => onExit(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'EXIT',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
            'Your intraday and overnight positions will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
