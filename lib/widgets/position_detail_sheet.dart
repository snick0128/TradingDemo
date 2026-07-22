import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_sheet.dart';

/// Draggable detail bottom sheet for a single position or holding.
///
/// Usage:
///   PositionDetailSheet.showPosition(context, position: p, resolvedLtp: ltp,
///     onSquareOff: (qty) { ... });
///   PositionDetailSheet.showHolding(context, holding: h, resolvedLtp: ltp,
///     onSquareOff: () { ... });
class PositionDetailSheet {
  PositionDetailSheet._();

  static Future<void> showPosition(
    BuildContext context, {
    required Position position,
    required double resolvedLtp,
    required Future<void> Function(int qty) onSquareOff,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PositionDetailContent(
        position: position,
        resolvedLtp: resolvedLtp,
        onSquareOff: onSquareOff,
      ),
    );
  }

  static Future<void> showHolding(
    BuildContext context, {
    required Holding holding,
    required double resolvedLtp,
    required Future<void> Function() onSquareOff,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HoldingDetailContent(
        holding: holding,
        resolvedLtp: resolvedLtp,
        onSquareOff: onSquareOff,
      ),
    );
  }
}

// ─── Position detail content ──────────────────────────────────────────────────

class _PositionDetailContent extends StatelessWidget {
  final Position position;
  final double resolvedLtp;
  final Future<void> Function(int qty) onSquareOff;

  const _PositionDetailContent({
    required this.position,
    required this.resolvedLtp,
    required this.onSquareOff,
  });

  @override
  Widget build(BuildContext context) {
    final p = position;
    final ltp = resolvedLtp;
    final isLong = p.side == OrderType.buy;
    final pnl = p.calculatePnL(ltp);
    final pnlPct =
        p.avgPrice == 0 ? 0.0 : (pnl / (p.avgPrice * p.quantity)) * 100;
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.symbol,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _Badge(
                          label: isLong ? 'LONG' : 'SHORT',
                          bg: isLong
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          fg: isLong
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                        _Badge(
                          label: _productLabel(p.product),
                          bg: p.product == ProductType.mis
                              ? const Color(0xFFFFF8E1)
                              : const Color(0xFFE3F2FD),
                          fg: p.product == ProductType.mis
                              ? const Color(0xFFF57F17)
                              : const Color(0xFF1565C0),
                        ),
                        _Badge(
                          label: p.exchange,
                          bg: const Color(0xFFF3F3F3),
                          fg: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 20),

          // Price panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DetailCell(
                    label: 'Current Price',
                    value: '₹${ltp.toStringAsFixed(2)}',
                    valueColor: AppColors.textPrimary,
                    large: true,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Expanded(
                  child: _DetailCell(
                    label: 'Unrealized P&L',
                    value:
                        '${isProfit ? '+' : ''}₹${pnl.abs().toStringAsFixed(2)}',
                    valueColor: pnlColor,
                    large: true,
                    sublabel: '${isProfit ? '+' : ''}${pnlPct.abs().toStringAsFixed(2)}%',
                    sublabelColor: pnlColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Details grid
          const Text(
            'Position Details',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          _DetailsGrid(
            cells: [
              _DetailCell(
                label: 'Quantity',
                value: '${p.quantity}',
              ),
              _DetailCell(
                label: isLong ? 'Avg Buy Price' : 'Avg Sell Price',
                value: '₹${p.avgPrice.toStringAsFixed(2)}',
              ),
              _DetailCell(
                label: 'Total Value',
                value: '₹${_fmt(p.avgPrice * p.quantity)}',
              ),
              if (p.marginUsed > 0)
                _DetailCell(
                  label: 'Margin Used',
                  value: '₹${_fmt(p.marginUsed)}',
                ),
            ],
          ),

          const SizedBox(height: 28),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Buy More
              Expanded(
                child: _ActionButton(
                  label: 'Buy More',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    final store = TradingScope.read(context);
                    Stock stock;
                    try {
                      stock = store.stockBySymbol(p.symbol);
                    } catch (_) {
                      stock = Stock(
                        symbol: p.symbol,
                        name: p.name,
                        currentPrice: ltp,
                        changePercentage: 0,
                        sector: '',
                        exchange: p.exchange,
                        token: p.token,
                      );
                    }
                    OrderFormSheet.show(context, stock: stock, initialSide: OrderType.buy);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Sell
              Expanded(
                child: _ActionButton(
                  label: 'Sell',
                  color: AppColors.danger,
                  outlined: true,
                  onTap: () {
                    Navigator.pop(context);
                    final store = TradingScope.read(context);
                    Stock stock;
                    try {
                      stock = store.stockBySymbol(p.symbol);
                    } catch (_) {
                      stock = Stock(
                        symbol: p.symbol,
                        name: p.name,
                        currentPrice: ltp,
                        changePercentage: 0,
                        sector: '',
                        exchange: p.exchange,
                        token: p.token,
                      );
                    }
                    OrderFormSheet.show(context, stock: stock, initialSide: OrderType.sell);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Square Off — shows partial qty picker before executing
              Expanded(
                child: _ActionButton(
                  label: 'Square Off',
                  color: AppColors.danger,
                  onTap: () {
                    _PartialSquareOffDialog.show(
                      context,
                      symbol:     p.symbol,
                      totalQty:   p.quantity,
                      onConfirm:  (qty) {
                        Navigator.pop(context);
                        onSquareOff(qty);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Partial Square-Off Dialog ────────────────────────────────────────────────

class _PartialSquareOffDialog extends StatefulWidget {
  final String symbol;
  final int totalQty;
  final void Function(int qty) onConfirm;

  const _PartialSquareOffDialog({
    required this.symbol,
    required this.totalQty,
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required String symbol,
    required int totalQty,
    required void Function(int qty) onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PartialSquareOffDialog(
        symbol: symbol,
        totalQty: totalQty,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<_PartialSquareOffDialog> createState() =>
      _PartialSquareOffDialogState();
}

class _PartialSquareOffDialogState extends State<_PartialSquareOffDialog> {
  late int _selectedQty;
  late final TextEditingController _customCtrl;
  String? _error;

  // Quick-select fractions: 25%, 50%, 75%, 100%
  static const _fractions = [0.25, 0.50, 0.75, 1.00];
  static const _labels    = ['25%', '50%', '75%', '100%'];

  @override
  void initState() {
    super.initState();
    _selectedQty = widget.totalQty; // default: full close
    _customCtrl  = TextEditingController(text: '${widget.totalQty}');
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  int _qtyForFraction(double f) =>
      (widget.totalQty * f).round().clamp(1, widget.totalQty);

  void _selectPreset(double f) {
    final qty = _qtyForFraction(f);
    setState(() {
      _selectedQty = qty;
      _customCtrl.text = '$qty';
      _error = null;
    });
  }

  void _onCustomChanged(String v) {
    final n = int.tryParse(v.trim());
    if (n == null || n <= 0) {
      setState(() { _error = 'Enter a valid quantity'; _selectedQty = 0; });
    } else if (n > widget.totalQty) {
      setState(() { _error = 'Max allowed: ${widget.totalQty}'; _selectedQty = 0; });
    } else {
      setState(() { _error = null; _selectedQty = n; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    final isFullClose = _selectedQty == widget.totalQty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Square Off ${widget.symbol}',
                      style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Open: ${widget.totalQty} qty',
                      style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick-select buttons
          const Text(
            'Quick Select',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary, letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(_fractions.length, (i) {
              final qty     = _qtyForFraction(_fractions[i]);
              final active  = _selectedQty == qty;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < _fractions.length - 1 ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => _selectPreset(_fractions[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      height: 44,
                      decoration: BoxDecoration(
                        color: active ? AppColors.danger : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active ? AppColors.danger : AppColors.border,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _labels[i],
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: active ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '$qty',
                            style: TextStyle(
                              fontSize: 10,
                              color: active
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Custom quantity
          const Text(
            'Custom Quantity',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary, letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: _onCustomChanged,
            decoration: InputDecoration(
              hintText: 'Enter qty (1 – ${widget.totalQty})',
              errorText: _error,
              filled: true,
              fillColor: AppColors.surfaceAlt,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.danger),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedQty > 0 ? () => widget.onConfirm(_selectedQty) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                isFullClose
                    ? 'Close Full Position (${widget.totalQty} qty)'
                    : 'Square Off $_selectedQty of ${widget.totalQty} qty',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Holding detail content ───────────────────────────────────────────────────

class _HoldingDetailContent extends StatelessWidget {
  final Holding holding;
  final double resolvedLtp;
  final Future<void> Function() onSquareOff;

  const _HoldingDetailContent({
    required this.holding,
    required this.resolvedLtp,
    required this.onSquareOff,
  });

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final ltp = resolvedLtp;
    final pnl = h.calculatePnL(ltp);
    final pnlPct =
        h.avgPrice == 0 ? 0.0 : (pnl / (h.avgPrice * h.quantity)) * 100;
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppColors.success : AppColors.danger;

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.symbol,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _Badge(
                          label: 'DELIVERY',
                          bg: const Color(0xFFE8F5E9),
                          fg: const Color(0xFF2E7D32),
                        ),
                        _Badge(
                          label: 'LONG',
                          bg: const Color(0xFFE8F5E9),
                          fg: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 20),

          // Price panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DetailCell(
                    label: 'Current Price',
                    value: '₹${ltp.toStringAsFixed(2)}',
                    valueColor: AppColors.textPrimary,
                    large: true,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Expanded(
                  child: _DetailCell(
                    label: 'Total P&L',
                    value:
                        '${isProfit ? '+' : ''}₹${pnl.abs().toStringAsFixed(2)}',
                    valueColor: pnlColor,
                    large: true,
                    sublabel: '${isProfit ? '+' : ''}${pnlPct.abs().toStringAsFixed(2)}%',
                    sublabelColor: pnlColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Holding Details',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          _DetailsGrid(
            cells: [
              _DetailCell(label: 'Quantity', value: '${h.quantity}'),
              _DetailCell(
                label: 'Avg Buy Price',
                value: '₹${h.avgPrice.toStringAsFixed(2)}',
              ),
              _DetailCell(
                label: 'Invested',
                value: '₹${_fmt(h.avgPrice * h.quantity)}',
              ),
              _DetailCell(
                label: 'Current Value',
                value: '₹${_fmt(ltp * h.quantity)}',
              ),
              if ((h.dividendReceived ?? 0) > 0)
                _DetailCell(
                  label: 'Dividends',
                  value: '₹${h.dividendReceived!.toStringAsFixed(2)}',
                  valueColor: AppColors.primary,
                ),
            ],
          ),

          const SizedBox(height: 28),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Buy More',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    final store = TradingScope.read(context);
                    Stock stock;
                    try {
                      stock = store.stockBySymbol(h.symbol);
                    } catch (_) {
                      stock = Stock(
                        symbol: h.symbol,
                        name: h.name,
                        currentPrice: ltp,
                        changePercentage: 0,
                        sector: '',
                      );
                    }
                    OrderFormSheet.show(context, stock: stock, initialSide: OrderType.buy);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Sell',
                  color: AppColors.danger,
                  outlined: true,
                  onTap: () {
                    Navigator.pop(context);
                    final store = TradingScope.read(context);
                    Stock stock;
                    try {
                      stock = store.stockBySymbol(h.symbol);
                    } catch (_) {
                      stock = Stock(
                        symbol: h.symbol,
                        name: h.name,
                        currentPrice: ltp,
                        changePercentage: 0,
                        sector: '',
                      );
                    }
                    OrderFormSheet.show(context, stock: stock, initialSide: OrderType.sell);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Square Off',
                  color: AppColors.danger,
                  onTap: () {
                    Navigator.pop(context);
                    onSquareOff();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Shared sheet widgets ─────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  final Widget child;
  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 20),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    ),
  );
}

class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool large;
  final String? sublabel;
  final Color? sublabelColor;

  const _DetailCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.large = false,
    this.sublabel,
    this.sublabelColor,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: TextStyle(
          fontSize: large ? 17 : 14,
          fontWeight: large ? FontWeight.w700 : FontWeight.w600,
          color: valueColor ?? AppColors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (sublabel != null)
        Text(
          sublabel!,
          style: TextStyle(
            fontSize: 12,
            color: sublabelColor ?? AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
    ],
  );
}

class _DetailsGrid extends StatelessWidget {
  final List<_DetailCell> cells;
  const _DetailsGrid({required this.cells});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final half = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cells.map((c) => SizedBox(width: half, child: c)).toList(),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    this.outlined = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(10),
        border: outlined ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: outlined ? color : Colors.white,
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

// Returns a compact number string WITHOUT a currency symbol.
// Callers must prepend '₹' themselves so the symbol is never doubled.
String _fmt(double v) {
  if (v.abs() >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(2);
}
