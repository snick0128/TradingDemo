import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class OrderFormDrawer extends StatefulWidget {
  final Stock stock;
  final OrderType initialSide;

  const OrderFormDrawer({
    super.key,
    required this.stock,
    this.initialSide = OrderType.buy,
  });

  @override
  State<OrderFormDrawer> createState() => _OrderFormDrawerState();
}

class _OrderFormDrawerState extends State<OrderFormDrawer> {
  late OrderType _side;
  ProductType _product = ProductType.mis;
  OrderVariety _variety = OrderVariety.market;
  bool _showAdvanced = false;
  bool _submitting = false;

  int _qty = 1;
  final _priceController = TextEditingController();
  final _triggerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _priceController.text = widget.stock.currentPrice.toStringAsFixed(2);
    _triggerController.text = widget.stock.currentPrice.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _triggerController.dispose();
    super.dispose();
  }

  bool get _isBuy => _side == OrderType.buy;
  bool get _isMarket => _variety == OrderVariety.market;
  bool get _isPriceEnabled =>
      _variety == OrderVariety.limit || _variety == OrderVariety.sl;
  bool get _isTriggerEnabled => _variety == OrderVariety.sl;

  double get _effectivePrice => _isPriceEnabled
      ? (double.tryParse(_priceController.text) ?? widget.stock.currentPrice)
      : widget.stock.currentPrice;

  double get _requiredMargin {
    // Exit orders (SELL) never require additional margin — the user is
    // releasing an existing position, not opening a new one.
    if (!_isBuy) return 0;
    final store = TradingScope.of(context);
    return store.requiredMargin(_qty, _effectivePrice, _product);
  }

  double get _estimatedCharges {
    final tradeValue = _qty * _effectivePrice;
    final brokerage = 20.0;
    final stt = tradeValue * 0.001;
    final gst = brokerage * 0.18;
    return brokerage + stt + gst;
  }

  double get _totalCost =>
      _qty * _effectivePrice +
      (_isBuy ? _estimatedCharges : -_estimatedCharges);

  Color get _sideColor => _isBuy ? AppColors.success : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    // SELL orders never require margin — only BUY orders do.
    final hasInsufficientMargin = _isBuy && _requiredMargin > store.balance;

    return Drawer(
      width: 380,
      child: Column(
        children: [
          // ── Clean white header ──────────────────────────────────────────
          _buildHeader(context),

          // ── Scrollable form ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product type (CNC / MIS / NRML)
                  _buildProductRow(),
                  const SizedBox(height: 20),

                  // Order type (Market / Limit)
                  _buildOrderTypeRow(),
                  const SizedBox(height: 20),

                  // Quantity with +/- controls
                  _buildQuantityRow(),
                  const SizedBox(height: 20),

                  // Price field (only for Limit/SL)
                  _buildPriceField(),

                  // Trigger field (only for SL types)
                  if (_isTriggerEnabled) ...[
                    const SizedBox(height: 16),
                    _buildTriggerField(),
                  ],

                  // Advanced options toggle
                  const SizedBox(height: 16),
                  _buildAdvancedToggle(),

                  if (_showAdvanced) ...[
                    const SizedBox(height: 16),
                    _buildAdvancedOptions(),
                  ],

                  const SizedBox(height: 20),

                  // Estimated cost breakdown
                  _buildCostBreakdown(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Sticky bottom CTA ───────────────────────────────────────────
          _buildStickyBottom(context, store, hasInsufficientMargin),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final tagBg = _isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final tagText = _isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 12, 14),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isBuy ? 'BUY' : 'SELL',
              style: TextStyle(
                color: tagText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.stock.symbol,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                  ),
                ),
                Text(
                  'NSE  ·  ₹${widget.stock.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                  ),
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
              child: const Icon(
                Icons.close,
                size: 16,
                color: Color(0xFF666666),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Product Row ──────────────────────────────────────────────────────────

  Widget _buildProductRow() {
    const chips = [
      (ProductType.mis, 'Intraday'),
      (ProductType.nrml, 'Delivery'),
      (ProductType.overnight, 'F&O'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRODUCT'),
        const SizedBox(height: 8),
        Row(
          children: chips.map((c) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _pill(
                label: c.$2,
                selected: _product == c.$1,
                onTap: () => setState(() => _product = c.$1),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _productChip(String label, ProductType type) {
    // kept for compatibility — delegates to _pill
    return _pill(
      label: label,
      selected: _product == type,
      onTap: () => setState(() => _product = type),
    );
  }

  // ─── Order Type Row ───────────────────────────────────────────────────────

  Widget _buildOrderTypeRow() {
    const types = [
      (OrderVariety.market, 'Instant'),
      (OrderVariety.limit, 'Set Price'),
      (OrderVariety.sl, 'Stop Loss'),
      (OrderVariety.amo, 'After Market'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ORDER TYPE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types
              .map(
                (t) => _pill(
                  label: t.$2,
                  selected: _variety == t.$1,
                  onTap: () => setState(() => _variety = t.$1),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  // ─── Shared pill ──────────────────────────────────────────────────────────

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final selBg = _isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final selText = _isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final selBorder = _isBuy
        ? const Color(0xFF81C784)
        : const Color(0xFFEF9A9A);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? selBg : Colors.white,
          border: Border.all(
            color: selected ? selBorder : const Color(0xFFE0E0E0),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? selText : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  // ─── Quantity Row ─────────────────────────────────────────────────────────

  Widget _buildQuantityRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('QUANTITY'),
        const SizedBox(height: 8),
        Row(
          children: [
            ...[1, 5, 10, 50].map((q) {
              final sel = _qty == q;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _qty = q),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _sideColor.withOpacity(0.08) : Colors.white,
                      border: Border.all(
                        color: sel ? _sideColor : const Color(0xFFE0E0E0),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$q',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? _sideColor : const Color(0xFF666666),
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            _stepperButton(LucideIcons.minus, () {
              if (_qty > 1) setState(() => _qty--);
            }),
            SizedBox(
              width: 44,
              child: Text(
                '$_qty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
            ),
            _stepperButton(LucideIcons.plus, () => setState(() => _qty++)),
          ],
        ),
      ],
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: const Color(0xFF111111)),
      ),
    );
  }

  // ─── Price Field ──────────────────────────────────────────────────────────

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRICE'),
        const SizedBox(height: 8),
        if (_isMarket)
          Row(
            children: [
              Icon(LucideIcons.zap, size: 13, color: _sideColor),
              const SizedBox(width: 6),
              Text(
                'Best available market price',
                style: TextStyle(
                  fontSize: 13,
                  color: _sideColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
        else
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '₹ ',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _sideColor, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Trigger Field ────────────────────────────────────────────────────────

  Widget _buildTriggerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TRIGGER PRICE'),
        const SizedBox(height: 8),
        TextField(
          controller: _triggerController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: '₹ ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _sideColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Advanced Toggle ──────────────────────────────────────────────────────

  Widget _buildAdvancedToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      child: Row(
        children: [
          Icon(
            _showAdvanced ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 13,
            color: const Color(0xFF9E9E9E),
          ),
          const SizedBox(width: 5),
          Text(
            _showAdvanced ? 'Hide advanced options' : 'More options',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9E9E9E),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Advanced Options ─────────────────────────────────────────────────────

  Widget _buildAdvancedOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('VALIDITY'),
        const SizedBox(height: 8),
        DropdownButtonFormField<OrderValidity>(
          value: OrderValidity.day,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: const [
            DropdownMenuItem(value: OrderValidity.day, child: Text('Day')),
            DropdownMenuItem(value: OrderValidity.ioc, child: Text('IOC')),
            DropdownMenuItem(value: OrderValidity.gtc, child: Text('GTC')),
          ],
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _advancedChip('After Market', _variety == OrderVariety.amo, () {
              setState(
                () => _variety = _variety == OrderVariety.amo
                    ? OrderVariety.market
                    : OrderVariety.amo,
              );
            }),
            _advancedChip('Iceberg', _variety == OrderVariety.iceberg, () {
              setState(
                () => _variety = _variety == OrderVariety.iceberg
                    ? OrderVariety.market
                    : OrderVariety.iceberg,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _advancedChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE0E0E0),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? AppColors.primary : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  // ─── Cost Breakdown ───────────────────────────────────────────────────────

  Widget _buildCostBreakdown() {
    final tradeValue = _qty * _effectivePrice;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          _costRow(
            'Trade value',
            '₹${tradeValue.toStringAsFixed(2)}',
            const Color(0xFF111111),
          ),
          const SizedBox(height: 8),
          _costRow(
            'Est. charges',
            '₹${_estimatedCharges.toStringAsFixed(2)}',
            const Color(0xFF666666),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF0F0F0)),
          ),
          _costRow(
            _isBuy ? 'Total cost' : 'You receive',
            '₹${_totalCost.toStringAsFixed(2)}',
            _isBuy ? const Color(0xFFD50000) : const Color(0xFF00C853),
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _costRow(
    String label,
    String value,
    Color valueColor, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ─── Sticky Bottom ────────────────────────────────────────────────────────

  Widget _buildStickyBottom(
    BuildContext context,
    store,
    bool hasInsufficientMargin,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Margin row — inline, compact
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'Inter'),
                  children: [
                    const TextSpan(
                      text: 'Required  ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                    TextSpan(
                      text: '\u20b9${_requiredMargin.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: hasInsufficientMargin
                            ? const Color(0xFFD50000)
                            : const Color(0xFF111111),
                      ),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'Inter'),
                  children: [
                    const TextSpan(
                      text: 'Available  ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                    TextSpan(
                      text: '\u20b9${store.balance.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00C853),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (hasInsufficientMargin) ...[
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.info_outline, size: 13, color: Color(0xFFD50000)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Insufficient funds. Please add money to proceed.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD50000),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Primary CTA — full width, dominant
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (hasInsufficientMargin || _submitting)
                  ? null
                  : () async => _submitOrder(context, store),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sideColor,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '${_isBuy ? 'Buy' : 'Sell'} ${widget.stock.symbol}  \u00b7  $_qty qty',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 6),

          // Cancel — low visual weight text button
          SizedBox(
            width: double.infinity,
            height: 36,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9E9E9E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOrder(BuildContext context, store) async {
    if (_submitting) return;

    final price = _isPriceEnabled
        ? (double.tryParse(_priceController.text) ?? 0)
        : null;
    final triggerPrice = _isTriggerEnabled
        ? double.tryParse(_triggerController.text)
        : null;

    final messenger = ScaffoldMessenger.of(context);
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();

    if (appScope != null) {
      final sessionUser = appScope.notifier?.user;
      if (sessionUser == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Please login again. Session not found.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      setState(() => _submitting = true);

      try {
        final clientOrderId = const Uuid().v4();
        await appScope.tradingService.placeOrder(
          userId: sessionUser.uid,
          stock: widget.stock.symbol,
          qty: _qty,
          type: _side == OrderType.buy ? 'BUY' : 'SELL',
          variety: _variety.name.toUpperCase(),
          product: _product.name.toUpperCase(),
          validity: 'DAY',
          price: price,
          triggerPrice: triggerPrice,
          clientOrderId: clientOrderId,
        );

        if (context.mounted) Navigator.pop(context);

        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('Order submitted successfully')),
              ],
            ),
            backgroundColor: _sideColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _submitting = false);
        final raw = e.toString();
        String msg = raw.replaceAll('Exception: ', '').split('\n').first.trim();

        if (raw.contains("Insufficient balance")) {
          msg = 'Insufficient balance for this trade.';
        } else if (raw.contains("Not enough shares")) {
          msg = 'Insufficient holdings to sell.';
        }

        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }

    // ── Mock / offline path ───────────────────────────────────────────────
    final result = store.placeOrder(
      symbol: widget.stock.symbol,
      quantity: _qty,
      type: _side,
      variety: _variety,
      product: _product,
      price: price,
      triggerPrice: triggerPrice,
    );

    if (context.mounted) Navigator.pop(context);

    if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                LucideIcons.checkCircle,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Order placed · ${result.orderId}')),
            ],
          ),
          backgroundColor: _sideColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                LucideIcons.alertCircle,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(result.errorMessage ?? 'Order failed')),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
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
