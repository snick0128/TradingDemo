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
  ProductType _product = ProductType.cnc;
  OrderVariety _variety = OrderVariety.market;
  bool _showAdvanced = false;

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
      _variety == OrderVariety.limit || _variety == OrderVariety.slLimit;
  bool get _isTriggerEnabled =>
      _variety == OrderVariety.slLimit || _variety == OrderVariety.slMarket;

  double get _effectivePrice =>
      _isPriceEnabled
          ? (double.tryParse(_priceController.text) ?? widget.stock.currentPrice)
          : widget.stock.currentPrice;

  double get _requiredMargin {
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

  double get _totalCost => _qty * _effectivePrice + (_isBuy ? _estimatedCharges : -_estimatedCharges);

  Color get _sideColor => _isBuy ? AppColors.success : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final hasInsufficientMargin = _requiredMargin > store.balance;

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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 52, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Colored side tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _sideColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isBuy ? 'BUY' : 'SELL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
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
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'NSE  ₹${widget.stock.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ─── Product Row ──────────────────────────────────────────────────────────

  Widget _buildProductRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRODUCT'),
        const SizedBox(height: 8),
        Row(
          children: [
            _productChip('CNC', ProductType.cnc),
            const SizedBox(width: 8),
            _productChip('MIS', ProductType.mis),
            const SizedBox(width: 8),
            _productChip('NRML', ProductType.nrml),
          ],
        ),
      ],
    );
  }

  Widget _productChip(String label, ProductType type) {
    final selected = _product == type;
    return GestureDetector(
      onTap: () => setState(() => _product = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _sideColor.withValues(alpha: 0.1) : AppColors.surfaceAlt,
          border: Border.all(color: selected ? _sideColor : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? _sideColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ─── Order Type Row ───────────────────────────────────────────────────────

  Widget _buildOrderTypeRow() {
    final types = [
      (OrderVariety.market, 'Market'),
      (OrderVariety.limit, 'Limit'),
      (OrderVariety.slLimit, 'SL-Limit'),
      (OrderVariety.slMarket, 'SL-Market'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ORDER TYPE'),
        const SizedBox(height: 8),
        Row(
          children: types.map((t) {
            final selected = _variety == t.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _variety = t.$1),
                child: Container(
                  margin: EdgeInsets.only(right: t.$1 != OrderVariety.slMarket ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _sideColor.withValues(alpha: 0.1) : AppColors.surfaceAlt,
                    border: Border.all(color: selected ? _sideColor : AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    t.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? _sideColor : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
            // Quick qty presets
            ...[1, 5, 10, 50].map((q) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _qty = q),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _qty == q ? _sideColor.withValues(alpha: 0.1) : AppColors.surfaceAlt,
                    border: Border.all(color: _qty == q ? _sideColor : AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$q',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _qty == q ? _sideColor : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            )),
            // Stepper
            const Spacer(),
            _stepperButton(LucideIcons.minus, () {
              if (_qty > 1) setState(() => _qty--);
            }),
            Container(
              width: 48,
              alignment: Alignment.center,
              child: Text(
                '$_qty',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.zap, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Market price will be used',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        else
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '₹ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _sideColor, width: 1.5)),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _sideColor, width: 1.5)),
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
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            _showAdvanced ? 'Hide advanced options' : 'Advanced options (AMO, Iceberg, Validity)',
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

  // ─── Advanced Options ─────────────────────────────────────────────────────

  Widget _buildAdvancedOptions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('VALIDITY'),
          const SizedBox(height: 8),
          DropdownButtonFormField<OrderValidity>(
            value: OrderValidity.day,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: const [
              DropdownMenuItem(value: OrderValidity.day, child: Text('Day')),
              DropdownMenuItem(value: OrderValidity.ioc, child: Text('IOC')),
              DropdownMenuItem(value: OrderValidity.gtc, child: Text('GTC')),
            ],
            onChanged: (_) {},
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _advancedChip('AMO', _variety == OrderVariety.amo, () {
                setState(() => _variety = _variety == OrderVariety.amo ? OrderVariety.market : OrderVariety.amo);
              }),
              const SizedBox(width: 8),
              _advancedChip('Iceberg', _variety == OrderVariety.iceberg, () {
                setState(() => _variety = _variety == OrderVariety.iceberg ? OrderVariety.market : OrderVariety.iceberg);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _advancedChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ─── Cost Breakdown ───────────────────────────────────────────────────────

  Widget _buildCostBreakdown() {
    final tradeValue = _qty * _effectivePrice;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _costRow('Trade value', '₹${tradeValue.toStringAsFixed(2)}', AppColors.textPrimary),
          const SizedBox(height: 6),
          _costRow('Est. charges', '₹${_estimatedCharges.toStringAsFixed(2)}', AppColors.textSecondary),
          const Divider(height: 16),
          _costRow(
            _isBuy ? 'Total cost' : 'You receive',
            '₹${_totalCost.toStringAsFixed(2)}',
            _isBuy ? AppColors.danger : AppColors.success,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, Color valueColor, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ─── Sticky Bottom ────────────────────────────────────────────────────────

  Widget _buildStickyBottom(BuildContext context, store, bool hasInsufficientMargin) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Margin row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Required', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    '₹${_requiredMargin.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: hasInsufficientMargin ? AppColors.danger : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Available', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    '₹${store.balance.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (hasInsufficientMargin) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle, size: 13, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Insufficient margin. Add funds to proceed.',
                      style: TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // CTA button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: hasInsufficientMargin
                  ? null
                  : () async => _submitOrder(context, store),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sideColor,
                disabledBackgroundColor: AppColors.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isBuy ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_isBuy ? 'BUY' : 'SELL'} ${widget.stock.symbol} · $_qty qty',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submitOrder(BuildContext context, store) async {
    final price = _isPriceEnabled
        ? (double.tryParse(_priceController.text) ?? 0)
        : null;
    final triggerPrice = _isTriggerEnabled
        ? double.tryParse(_triggerController.text)
        : null;

    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope != null) {
      final sessionUser = appScope.notifier?.user;
      if (sessionUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login again. Session not found.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      final clientOrderId = const Uuid().v4();

      try {
        String varietyStr;
        switch (_variety) {
          case OrderVariety.market: varietyStr = 'MARKET'; break;
          case OrderVariety.limit: varietyStr = 'LIMIT'; break;
          case OrderVariety.slLimit: varietyStr = 'SL'; break;
          case OrderVariety.slMarket: varietyStr = 'SL-M'; break;
          default: varietyStr = 'MARKET';
        }

        final orderId = await appScope.tradingService.placeOrder(
          userId: sessionUser.uid,
          stock: widget.stock.symbol,
          qty: _qty,
          type: _side == OrderType.buy ? 'BUY' : 'SELL',
          variety: varietyStr,
          price: price,
          triggerPrice: triggerPrice,
          clientOrderId: clientOrderId,
        );

        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.checkCircle, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Order processed · $orderId'),
              ],
            ),
            backgroundColor: _sideColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    final result = store.placeOrder(
      symbol: widget.stock.symbol,
      quantity: _qty,
      type: _side,
      variety: _variety,
      product: _product,
      price: price,
      triggerPrice: triggerPrice,
    );

    if (result.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(LucideIcons.checkCircle, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Order placed · ${result.orderId}'),
            ],
          ),
          backgroundColor: _sideColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Order failed'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.8,
    ),
  );
}
