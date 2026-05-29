import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../theme.dart';

/// Modal dialog for confirming and executing a batch square-off.
///
/// Phases:
///   confirm  → list of selected items + Cancel/Confirm buttons
///   executing → progress indicator per order
///   done      → success/failure summary
///
/// Usage:
///   MultiSquareOffDialog.show(context,
///     selectedPositions: [...],
///     selectedHoldings: [...],
///     resolvedLtp: (symbol, stored) => ...,
///     onCompleted: () { clearSelection(); },
///   );
class MultiSquareOffDialog {
  MultiSquareOffDialog._();

  static Future<void> show(
    BuildContext context, {
    required List<Position> selectedPositions,
    required List<Holding> selectedHoldings,
    required double Function(String symbol, double storedPrice) resolvedLtp,
    required VoidCallback onCompleted,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => _MultiSquareOffWidget(
        selectedPositions: selectedPositions,
        selectedHoldings: selectedHoldings,
        resolvedLtp: resolvedLtp,
        onCompleted: onCompleted,
      ),
    );
  }
}

// ─── Dialog states ────────────────────────────────────────────────────────────

enum _Phase { confirm, executing, done }

class _SquareOffResult {
  final String symbol;
  final int qty;
  final bool success;
  final String? error;
  const _SquareOffResult({
    required this.symbol,
    required this.qty,
    required this.success,
    this.error,
  });
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _MultiSquareOffWidget extends StatefulWidget {
  final List<Position> selectedPositions;
  final List<Holding> selectedHoldings;
  final double Function(String, double) resolvedLtp;
  final VoidCallback onCompleted;

  const _MultiSquareOffWidget({
    required this.selectedPositions,
    required this.selectedHoldings,
    required this.resolvedLtp,
    required this.onCompleted,
  });

  @override
  State<_MultiSquareOffWidget> createState() => _MultiSquareOffWidgetState();
}

class _MultiSquareOffWidgetState extends State<_MultiSquareOffWidget> {
  _Phase _phase = _Phase.confirm;
  final List<_SquareOffResult> _results = [];
  int _completedCount = 0;
  int get _totalCount =>
      widget.selectedPositions.length + widget.selectedHoldings.length;

  String? _currentSymbol;

  Future<void> _executeAll() async {
    setState(() {
      _phase = _Phase.executing;
      _results.clear();
      _completedCount = 0;
    });

    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final sessionUser = appScope?.notifier?.user;

    if (sessionUser == null) {
      setState(() {
        _results.add(const _SquareOffResult(
          symbol: 'ALL',
          qty: 0,
          success: false,
          error: 'Session expired. Please login.',
        ));
        _phase = _Phase.done;
      });
      return;
    }

    final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

    // Execute positions
    for (final p in widget.selectedPositions) {
      if (!mounted) break;
      setState(() => _currentSymbol = p.symbol);

      final exitType = p.side == OrderType.buy ? 'SELL' : 'BUY';
      final productStr = switch (p.product) {
        ProductType.nrml => 'NRML',
        ProductType.overnight => 'CNC',
        ProductType.mtf => 'MTF',
        _ => 'MIS',
      };

      try {
        final ltp = widget.resolvedLtp(p.symbol, p.currentPrice);
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: p.symbol,
          qty: p.quantity,
          type: exitType,
          productType: productStr,
          exchange: p.exchange,
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId:
              '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_msq',
        );
        _results.add(
          _SquareOffResult(symbol: p.symbol, qty: p.quantity, success: true),
        );
      } on BackendException catch (e) {
        _results.add(
          _SquareOffResult(
            symbol: p.symbol,
            qty: p.quantity,
            success: false,
            error: e.message,
          ),
        );
      } catch (e) {
        _results.add(
          _SquareOffResult(
            symbol: p.symbol,
            qty: p.quantity,
            success: false,
            error: e.toString().replaceAll('Exception: ', ''),
          ),
        );
      }

      if (mounted) setState(() => _completedCount++);

      // Small delay between orders to avoid rate limiting
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    // Execute holdings
    for (final h in widget.selectedHoldings) {
      if (!mounted) break;
      setState(() => _currentSymbol = h.symbol);

      try {
        // Exchange defaults to 'NSE'; backend MCX-symbol inference corrects it
        // for commodity holdings that have no exchange field in the model.
        final ltp = widget.resolvedLtp(h.symbol, h.currentPrice);
        await api.placeOrder(
          userId: sessionUser.uid,
          symbol: h.symbol,
          qty: h.quantity,
          type: 'SELL',
          productType: 'CNC',
          exchange: 'NSE',
          lockedLtp: ltp > 0 ? ltp : null,
          clientRequestId:
              '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}_mhq',
        );
        _results.add(
          _SquareOffResult(symbol: h.symbol, qty: h.quantity, success: true),
        );
      } on BackendException catch (e) {
        _results.add(
          _SquareOffResult(
            symbol: h.symbol,
            qty: h.quantity,
            success: false,
            error: e.message,
          ),
        );
      } catch (e) {
        _results.add(
          _SquareOffResult(
            symbol: h.symbol,
            qty: h.quantity,
            success: false,
            error: e.toString().replaceAll('Exception: ', ''),
          ),
        );
      }

      if (mounted) setState(() => _completedCount++);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (mounted) setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 48,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: switch (_phase) {
            _Phase.confirm => _buildConfirm(),
            _Phase.executing => _buildExecuting(),
            _Phase.done => _buildDone(),
          },
        ),
      ),
    );
  }

  // ─── Confirm phase ─────────────────────────────────────────────────────────

  Widget _buildConfirm() {
    final positions = widget.selectedPositions;
    final holdings = widget.selectedHoldings;
    final n = _totalCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          child: Column(
            children: [
              // Warning icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.alertTriangle,
                  color: AppColors.danger,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$n position${n == 1 ? '' : 's'} will be squared off at market price.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Position list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...positions.map((p) {
                      final ltp = widget.resolvedLtp(p.symbol, p.currentPrice);
                      final pnl = p.side == OrderType.buy
                          ? (ltp - p.avgPrice) * p.quantity
                          : (p.avgPrice - ltp) * p.quantity;
                      return _ConfirmRow(
                        symbol: p.symbol,
                        qty: p.quantity,
                        productLabel: _productLabel(p.product),
                        pnl: pnl,
                        isLong: p.side == OrderType.buy,
                      );
                    }),
                    ...holdings.map((h) {
                      final ltp = widget.resolvedLtp(h.symbol, h.currentPrice);
                      final pnl = (ltp - h.avgPrice) * h.quantity;
                      return _ConfirmRow(
                        symbol: h.symbol,
                        qty: h.quantity,
                        productLabel: 'DELIVERY',
                        pnl: pnl,
                        isLong: true,
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Buttons
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _DialogBtn(
                  label: 'Cancel',
                  color: AppColors.textSecondary,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFFF0F0F0)),
              Expanded(
                child: _DialogBtn(
                  label: 'Confirm →',
                  color: AppColors.danger,
                  bold: true,
                  onTap: _executeAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Executing phase ────────────────────────────────────────────────────────

  Widget _buildExecuting() {
    final progress = _totalCount > 0 ? _completedCount / _totalCount : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Squaring off positions…',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentSymbol != null
                ? 'Processing $_currentSymbol…'
                : 'Preparing orders…',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_completedCount / $_totalCount',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Done phase ─────────────────────────────────────────────────────────────

  Widget _buildDone() {
    final succeeded = _results.where((r) => r.success).length;
    final failed = _results.where((r) => !r.success).length;
    final allGood = failed == 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: allGood
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  allGood ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                  color: allGood ? AppColors.success : AppColors.warning,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                allGood ? 'All Squared Off' : 'Partially Done',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                allGood
                    ? '$succeeded order${succeeded == 1 ? '' : 's'} executed successfully.'
                    : '$succeeded succeeded · $failed failed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Per-order results
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: _results.map((r) => _ResultRow(result: r)).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        _DialogBtn(
          label: 'Done',
          color: AppColors.primary,
          bold: true,
          onTap: () {
            Navigator.of(context).pop();
            widget.onCompleted();
          },
        ),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ConfirmRow extends StatelessWidget {
  final String symbol;
  final int qty;
  final String productLabel;
  final double pnl;
  final bool isLong;

  const _ConfirmRow({
    required this.symbol,
    required this.qty,
    required this.productLabel,
    required this.pnl,
    required this.isLong,
  });

  @override
  Widget build(BuildContext context) {
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$qty qty',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        productLabel,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isProfit ? '+' : ''}₹${pnl.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
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

class _ResultRow extends StatelessWidget {
  final _SquareOffResult result;
  const _ResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: result.success
            ? AppColors.success.withValues(alpha: 0.06)
            : AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.success
              ? AppColors.success.withValues(alpha: 0.25)
              : AppColors.danger.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? LucideIcons.checkCircle : LucideIcons.xCircle,
            size: 14,
            color: result.success ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.symbol,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!result.success && result.error != null)
                  Text(
                    result.error!,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.danger.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            result.success ? '${result.qty} qty' : 'Failed',
            style: TextStyle(
              fontSize: 11,
              color: result.success
                  ? AppColors.textSecondary
                  : AppColors.danger,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool bold;
  final VoidCallback? onTap;

  const _DialogBtn({
    required this.label,
    required this.color,
    this.bold = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ),
    ),
  );
}

// ─── Utilities ────────────────────────────────────────────────────────────────

String _productLabel(ProductType p) => switch (p) {
  ProductType.mis => 'INTRADAY',
  ProductType.nrml => 'OVERNIGHT',
  ProductType.overnight => 'DELIVERY',
  ProductType.mtf => 'MTF',
};
