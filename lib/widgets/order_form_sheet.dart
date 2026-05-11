import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import 'app_dialog.dart';

/// Shows the buy/sell order form as a modal bottom sheet.
///
/// Usage:
///   OrderFormSheet.show(context, stock: stock, initialSide: OrderType.buy);
class OrderFormSheet {
  static Future<void> show(
    BuildContext context, {
    required Stock stock,
    OrderType initialSide = OrderType.buy,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderFormSheetContent(
        stock: stock,
        initialSide: initialSide,
      ),
    );
  }
}

class _OrderFormSheetContent extends StatefulWidget {
  final Stock stock;
  final OrderType initialSide;

  const _OrderFormSheetContent({
    required this.stock,
    required this.initialSide,
  });

  @override
  State<_OrderFormSheetContent> createState() => _OrderFormSheetContentState();
}

// MCX lot sizes — must match backend MCX_LOT_SIZES
const _mcxLotSizes = {
  'GOLD': 1,
  'SILVER': 30,
  'CRUDEOIL': 100,
  'NATURALGAS': 1250,
  'COPPER': 2500,
  'ZINC': 5000,
  'LEAD': 5000,
  'ALUMINIUM': 5000,
  'NICKEL': 1500,
  'COTTON': 25,
};

// Default leverage per exchange/product — mirrors backend DEFAULT_LEVERAGE
const _defaultLeverage = {
  'NSE': {'MIS': 5,  'CNC': 1, 'NRML': 1},
  'MCX': {'MIS': 10, 'CNC': 1, 'NRML': 1},
  'BSE': {'MIS': 5,  'CNC': 1, 'NRML': 1},
};

class _OrderFormSheetContentState extends State<_OrderFormSheetContent> {
  late OrderType _side;
  ProductType _product = ProductType.mis;
  OrderVariety _variety = OrderVariety.market;
  bool _submitting = false;
  int _qty = 1;
  final _priceController = TextEditingController();

  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _priceController.text = widget.stock.currentPrice.toStringAsFixed(2);
    // Default qty to lot size so MCX orders are valid from the start
    _qty = _lotSize;
    _settingsSub = _settingsService.stream.listen((s) {
      if (mounted) setState(() => _marketSettings = s);
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool get _isBuy => _side == OrderType.buy;
  bool get _isMarket => _variety == OrderVariety.market;
  bool get _isPriceEnabled =>
      _variety == OrderVariety.limit || _variety == OrderVariety.sl;

  /// MCX lot size for this symbol, or 1 for NSE equities.
  int get _lotSize {
    if (widget.stock.exchange.toUpperCase() == 'MCX') {
      return _mcxLotSizes[widget.stock.symbol.toUpperCase()] ?? 1;
    }
    return 1;
  }

  /// Effective leverage for this order — mirrors backend resolveLeverage.
  int get _leverage {
    final ex = widget.stock.exchange.toUpperCase().isEmpty
        ? 'NSE'
        : widget.stock.exchange.toUpperCase();
    final prod = _product == ProductType.mis ? 'MIS' : 'NRML';
    return (_defaultLeverage[ex]?[prod] ?? _defaultLeverage['NSE']!['MIS'])!;
  }

  /// Required margin for a BUY order — same formula as backend processBuy.
  double get _requiredMargin {
    final tradeValue = _qty * _effectivePrice;
    return tradeValue / _leverage;
  }

  /// Quick-select qty chips — multiples of lot size.
  List<int> get _qtyChips {
    final lot = _lotSize;
    if (lot == 1) return [1, 5, 10, 50];
    return [lot, lot * 2, lot * 5, lot * 10];
  }

  String? get _marketBlockReason =>
      _marketSettings.checkAction(widget.stock.exchange, isBuy: _isBuy);

  double get _effectivePrice => _isPriceEnabled
      ? (double.tryParse(_priceController.text) ?? widget.stock.currentPrice)
      : widget.stock.currentPrice;

  double get _estimatedCharges {
    final tv = _qty * _effectivePrice;
    const brokerage = 20.0;
    return brokerage + tv * 0.001 + brokerage * 0.18;
  }

  double get _totalCost =>
      _qty * _effectivePrice +
      (_isBuy ? _estimatedCharges : -_estimatedCharges);

  Color get _sideColor =>
      _isBuy ? const Color(0xFF00C853) : const Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final balance = store.balance;

    // BUY: check margin (leverage-adjusted), not full trade value
    final hasInsufficientFunds = _isBuy && _requiredMargin > balance;

    // SELL: find available qty from both holdings (CNC) and positions (MIS)
    final holdingQty = store.holdings
        .where((h) => h.symbol == widget.stock.symbol)
        .fold(0, (s, h) => s + h.quantity);
    final positionQty = store.positions
        .where((p) => p.symbol == widget.stock.symbol)
        .fold(0, (s, p) => s + p.quantity);
    final availableQty = holdingQty + positionQty;
    final hasInsufficientQty = !_isBuy && _qty > availableQty;

    final blockReason = _marketBlockReason;
    final isBlocked = blockReason != null;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),

          // ── Header ───────────────────────────────────────────────────────
          _buildHeader(context),

          // ── Scrollable body ──────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BUY / SELL toggle
                  _buildSideToggle(),
                  const SizedBox(height: 16),
                  // Product (buy only) + Order type
                  if (_isBuy)
                    Row(
                      children: [
                        Expanded(child: _buildProductRow()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildOrderTypeRow()),
                      ],
                    )
                  else
                    _buildOrderTypeRow(),
                  const SizedBox(height: 16),
                  _buildQuantityRow(availableQty),
                  const SizedBox(height: 16),
                  if (!_isMarket) ...[
                    _buildPriceField(),
                    const SizedBox(height: 16),
                  ],
                  _buildCostBreakdown(balance),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Market closed banner ─────────────────────────────────────────
          if (isBlocked)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFB300).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.clock,
                      size: 13, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(blockReason,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

          // ── CTA ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                // Balance row (buy) or Holdings qty row (sell)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_isBuy)
                      Text(
                        _leverage > 1
                            ? 'Margin needed  ₹${_requiredMargin.toStringAsFixed(2)}  ·  Cash ₹${balance.toStringAsFixed(2)}'
                            : 'Cash available  ₹${balance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: hasInsufficientFunds
                              ? const Color(0xFFD50000)
                              : const Color(0xFF9E9E9E),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text(
                            'Holdings: ',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9E9E9E)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: availableQty > 0
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$availableQty qty available',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: availableQty > 0
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFD50000),
                              ),
                            ),
                          ),
                        ],
                      ),
                    Text(
                      '$_qty qty × ₹${_effectivePrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                  ],
                ),
                if (hasInsufficientFunds) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFFD50000)),
                      const SizedBox(width: 4),
                      Text(
                        'Need ₹${_requiredMargin.toStringAsFixed(2)} margin, have ₹${balance.toStringAsFixed(2)}.',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFD50000)),
                      ),
                    ],
                  ),
                ],
                if (hasInsufficientQty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFFD50000)),
                      const SizedBox(width: 4),
                      Text(
                        availableQty == 0
                            ? 'You have no ${widget.stock.symbol} to sell.'
                            : 'You only have $availableQty qty to sell.',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFD50000)),
                      ),
                    ],
                  ),
                ],
                if (_lotSize > 1) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFF1565C0)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Lot size: $_lotSize${_isBuy && _leverage > 1 ? '  ·  ${_leverage}x leverage applied' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF1565C0)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (hasInsufficientFunds ||
                            hasInsufficientQty ||
                            _submitting ||
                            isBlocked)
                        ? null
                        : () => _submitOrder(context, store),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _sideColor,
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(
                            isBlocked
                                ? (_isBuy
                                    ? 'Buy Unavailable'
                                    : 'Sell Unavailable')
                                : '${_isBuy ? 'Buy' : 'Sell'} ${widget.stock.symbol}  ·  $_qty qty',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.stock.symbol,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111)),
                ),
                Text(
                  '₹${widget.stock.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close,
                  size: 16, color: Color(0xFF666666)),
            ),
          ),
        ],
      ),
    );
  }

  // ── BUY / SELL toggle ──────────────────────────────────────────────────────

  Widget _buildSideToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _side = OrderType.buy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 40,
              decoration: BoxDecoration(
                color: _side == OrderType.buy
                    ? const Color(0xFF00C853)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                'BUY',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _side == OrderType.buy
                      ? Colors.white
                      : const Color(0xFF9E9E9E),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _side = OrderType.sell),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 40,
              decoration: BoxDecoration(
                color: _side == OrderType.sell
                    ? const Color(0xFFE53935)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                'SELL',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _side == OrderType.sell
                      ? Colors.white
                      : const Color(0xFF9E9E9E),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Product ────────────────────────────────────────────────────────────────
  // On SELL, product type is irrelevant — you're exiting an existing position.
  // Only show product selector on BUY.

  Widget _buildProductRow() {
    if (!_isBuy) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRODUCT'),
        const SizedBox(height: 6),
        Row(
          children: [
            _chip('Intraday', _product == ProductType.mis,
                () => setState(() => _product = ProductType.mis)),
            const SizedBox(width: 6),
            _chip('Delivery', _product == ProductType.nrml,
                () => setState(() => _product = ProductType.nrml)),
          ],
        ),
      ],
    );
  }

  // ── Order type ─────────────────────────────────────────────────────────────

  Widget _buildOrderTypeRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ORDER TYPE'),
        const SizedBox(height: 6),
        Row(
          children: [
            _chip('Market', _variety == OrderVariety.market,
                () => setState(() => _variety = OrderVariety.market)),
            const SizedBox(width: 6),
            _chip('Limit', _variety == OrderVariety.limit,
                () => setState(() => _variety = OrderVariety.limit)),
          ],
        ),
      ],
    );
  }

  // ── Quantity ───────────────────────────────────────────────────────────────

  Widget _buildQuantityRow(int availableQty) {
    final lot = _lotSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('QUANTITY'),
            if (!_isBuy && availableQty > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'You have $availableQty',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Quick-select chips — lot-size aware
            for (final q in _qtyChips) ...[
              GestureDetector(
                onTap: () => setState(() => _qty = q),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _qty == q
                        ? _sideColor.withOpacity(0.1)
                        : Colors.white,
                    border: Border.all(
                        color: _qty == q
                            ? _sideColor
                            : const Color(0xFFE0E0E0)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('$q',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _qty == q
                              ? _sideColor
                              : const Color(0xFF666666))),
                ),
              ),
              const SizedBox(width: 5),
            ],
            const Spacer(),
            // Stepper — snaps to lot size multiples
            _stepBtn(LucideIcons.minus, () {
              final next = _qty - lot;
              if (next >= lot) setState(() => _qty = next);
            }),
            SizedBox(
              width: 36,
              child: Text('$_qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            _stepBtn(LucideIcons.plus,
                () => setState(() => _qty = _qty + lot)),
          ],
        ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF111111)),
        ),
      );

  // ── Price field ────────────────────────────────────────────────────────────

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('LIMIT PRICE'),
        const SizedBox(height: 6),
        TextField(
          controller: _priceController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: '₹ ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _sideColor, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  // ── Cost breakdown ─────────────────────────────────────────────────────────

  Widget _buildCostBreakdown(double balance) {
    final tv = _qty * _effectivePrice;
    final margin = _requiredMargin;
    final lev = _leverage;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          _row('Trade value', '₹${tv.toStringAsFixed(2)}',
              const Color(0xFF111111)),
          const SizedBox(height: 6),
          if (_isBuy && lev > 1) ...[
            _row('Leverage', '${lev}x', const Color(0xFF1565C0)),
            const SizedBox(height: 6),
            _row('Margin required', '₹${margin.toStringAsFixed(2)}',
                const Color(0xFF111111)),
            const SizedBox(height: 6),
          ],
          _row('Est. charges',
              '₹${_estimatedCharges.toStringAsFixed(2)}',
              const Color(0xFF888888)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
          ),
          _row(
            _isBuy ? 'Total deducted' : 'You receive',
            _isBuy
                ? '₹${(margin + _estimatedCharges).toStringAsFixed(2)}'
                : '₹${_totalCost.toStringAsFixed(2)}',
            _isBuy ? const Color(0xFFD50000) : const Color(0xFF00C853),
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF666666))),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 14 : 12,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor)),
      ],
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitOrder(BuildContext context, store) async {
    if (_submitting) return;
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();

    if (appScope != null) {
      final sessionUser = appScope.notifier?.user;
      if (sessionUser == null) {
        AppToast.error(context, 'Please login again.');
        return;
      }

      final nav = Navigator.of(context);
      setState(() => _submitting = true);

      try {
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        final result = await api.placeOrder(
          userId:      sessionUser.uid,
          symbol:      widget.stock.symbol,
          qty:         _qty,
          type:        _isBuy ? 'BUY' : 'SELL',
          productType: _product == ProductType.mis ? 'MIS' : 'NRML',
          exchange:    widget.stock.exchange.isNotEmpty
                           ? widget.stock.exchange
                           : 'NSE',
        );

        // Optimistic balance update — don't wait for Firestore stream.
        // The Firestore stream will correct it within ~1s anyway.
        final newBal = (result['newBalance'] as num?)?.toDouble();
        if (newBal != null) {
          store.setOptimisticBalance(newBal);
        }

        nav.pop();

        if (context.mounted) {
          final executed = result['executedPrice'] ?? result['price'];
          AppToast.success(
            context,
            '${_isBuy ? 'Bought' : 'Sold'} $_qty × ${widget.stock.symbol}'
            '${executed != null ? ' @ ₹${(executed as num).toStringAsFixed(2)}' : ''}',
          );
        }
      } on BackendException catch (e) {
        if (mounted) setState(() => _submitting = false);
        String msg = e.message;
        if (msg.contains('Insufficient balance') ||
            msg.contains('Not enough funds')) {
          msg = 'Insufficient balance.';
        } else if (msg.contains('No position') ||
            msg.contains('Insufficient quantity') ||
            msg.contains("don't have any")) {
          msg = 'You don\'t have enough holdings to sell.';
        } else if (msg.contains('market data') ||
            msg.contains('Market may be closed') ||
            msg.contains('not available right now')) {
          msg = 'Live price unavailable. Please try again.';
        } else if (msg.contains('lot size') ||
            msg.contains('multiple of')) {
          // Pass through lot size errors as-is — they're already user-friendly
        }
        if (context.mounted) AppToast.error(context, msg);
      } catch (e) {
        if (mounted) setState(() => _submitting = false);
        if (context.mounted) {
          AppToast.error(context,
              e.toString().replaceAll('Exception: ', ''));
        }
      }
      return;
    }

    // Offline/mock path
    final nav = Navigator.of(context);
    final result = store.placeOrder(
      symbol:   widget.stock.symbol,
      quantity: _qty,
      type:     _side,
      variety:  _variety,
      product:  _product,
      price:    _isPriceEnabled ? _effectivePrice : null,
    );
    nav.pop();
    if (result.success) {
      if (context.mounted) {
        AppToast.success(context, 'Order placed · ${result.orderId}');
      }
    } else {
      if (context.mounted) {
        AppToast.error(context, result.errorMessage ?? 'Order failed');
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (_isBuy
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFEBEE))
              : Colors.white,
          border: Border.all(
              color: selected
                  ? (_isBuy
                      ? const Color(0xFF81C784)
                      : const Color(0xFFEF9A9A))
                  : const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? (_isBuy
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828))
                : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9E9E9E),
          letterSpacing: 0.8,
        ),
      );
}
