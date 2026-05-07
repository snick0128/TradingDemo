import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'app_dialog.dart';

/// Simplified, beginner-friendly order form.
/// Keeps only: Product (Intraday/Delivery), Quantity, Price summary, CTA.
/// Removed: After Market, Iceberg, Advanced options, Validity dropdowns.
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
  // Only Intraday / Delivery
  ProductType _product = ProductType.mis;
  // Only Market / Limit / Stop Loss
  OrderVariety _variety = OrderVariety.market;
  bool _submitting = false;
  int _qty = 1;
  final _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _priceController.text = widget.stock.currentPrice.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  bool get _isBuy => _side == OrderType.buy;
  bool get _isMarket => _variety == OrderVariety.market;
  bool get _isPriceEnabled => _variety == OrderVariety.limit || _variety == OrderVariety.sl;

  double get _effectivePrice => _isPriceEnabled
      ? (double.tryParse(_priceController.text) ?? widget.stock.currentPrice)
      : widget.stock.currentPrice;

  double get _estimatedCharges {
    final tradeValue = _qty * _effectivePrice;
    const brokerage = 20.0;
    final stt = tradeValue * 0.001;
    final gst = brokerage * 0.18;
    return brokerage + stt + gst;
  }

  double get _totalCost =>
      _qty * _effectivePrice + (_isBuy ? _estimatedCharges : -_estimatedCharges);

  Color get _sideColor => _isBuy ? const Color(0xFF00C853) : const Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final hasInsufficientMargin = _isBuy &&
        (_qty * _effectivePrice) > store.balance;

    return Drawer(
      width: 360,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductRow(),
                  const SizedBox(height: 20),
                  _buildOrderTypeRow(),
                  const SizedBox(height: 20),
                  _buildQuantityRow(),
                  const SizedBox(height: 20),
                  _buildPriceField(),
                  const SizedBox(height: 20),
                  _buildCostBreakdown(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildStickyBottom(context, store, hasInsufficientMargin),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final tagBg = _isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final tagText = _isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
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
                  '₹${widget.stock.currentPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
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
              child: const Icon(Icons.close, size: 16, color: Color(0xFF666666)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Product row: Intraday / Delivery only ──────────────────────────────────

  Widget _buildProductRow() {
    const chips = [
      (ProductType.mis, 'Intraday'),
      (ProductType.nrml, 'Delivery'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRODUCT'),
        const SizedBox(height: 8),
        Row(
          children: chips.map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _pill(
              label: c.$2,
              selected: _product == c.$1,
              onTap: () => setState(() => _product = c.$1),
            ),
          )).toList(),
        ),
      ],
    );
  }

  // ── Order type: Market / Limit / Stop Loss only ────────────────────────────

  Widget _buildOrderTypeRow() {
    const types = [
      (OrderVariety.market, 'Market'),
      (OrderVariety.limit, 'Limit'),
      (OrderVariety.sl, 'Stop Loss'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ORDER TYPE'),
        const SizedBox(height: 8),
        Row(
          children: types.map((t) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _pill(
              label: t.$2,
              selected: _variety == t.$1,
              onTap: () => setState(() => _variety = t.$1),
            ),
          )).toList(),
        ),
      ],
    );
  }

  // ── Quantity ───────────────────────────────────────────────────────────────

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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            _stepperBtn(LucideIcons.minus, () {
              if (_qty > 1) setState(() => _qty--);
            }),
            SizedBox(
              width: 40,
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
            _stepperBtn(LucideIcons.plus, () => setState(() => _qty++)),
          ],
        ),
      ],
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap) {
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

  // ── Price field ────────────────────────────────────────────────────────────

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

  // ── Cost breakdown ─────────────────────────────────────────────────────────

  Widget _buildCostBreakdown() {
    final tradeValue = _qty * _effectivePrice;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          _costRow('Trade value', '₹${tradeValue.toStringAsFixed(2)}', const Color(0xFF111111)),
          const SizedBox(height: 8),
          _costRow('Est. charges', '₹${_estimatedCharges.toStringAsFixed(2)}', const Color(0xFF666666)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
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

  Widget _costRow(String label, String value, Color valueColor, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
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

  // ── Sticky bottom ──────────────────────────────────────────────────────────

  Widget _buildStickyBottom(BuildContext context, store, bool hasInsufficientMargin) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Balance row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available  ₹${store.balance.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  color: hasInsufficientMargin
                      ? const Color(0xFFD50000)
                      : const Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_qty} qty × ₹${_effectivePrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
          if (hasInsufficientMargin) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: Color(0xFFD50000)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Insufficient funds.',
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
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (hasInsufficientMargin || _submitting)
                  ? null
                  : () => _submitOrder(context, store),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sideColor,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      '${_isBuy ? 'Buy' : 'Sell'} ${widget.stock.symbol}  ·  $_qty qty',
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
          SizedBox(
            width: double.infinity,
            height: 36,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF9E9E9E)),
              ),
            ),
          ),
        ],
      ),
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

      // Capture navigator before async gap — context may be stale after await
      final nav = Navigator.of(context);

      setState(() => _submitting = true);
      try {
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        final result = await api.placeOrder(
          userId: sessionUser.uid,
          symbol: widget.stock.symbol,
          qty: _qty,
          type: _isBuy ? 'BUY' : 'SELL',
        );

        // Dismiss the drawer first, then show toast above it
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
        if (msg.contains('Insufficient balance')) msg = 'Insufficient balance.';
        else if (msg.contains('No position') || msg.contains('Insufficient quantity')) msg = 'Insufficient holdings.';
        else if (msg.contains('No market data') || msg.contains('Market may be closed')) msg = 'Market data unavailable.';
        if (context.mounted) AppToast.error(context, msg);
      } catch (e) {
        if (mounted) setState(() => _submitting = false);
        if (context.mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
      }
      // No finally setState — widget is already popped on success
      return;
    }

    // Offline/mock path
    final nav = Navigator.of(context);
    final result = store.placeOrder(
      symbol: widget.stock.symbol,
      quantity: _qty,
      type: _side,
      variety: _variety,
      product: _product,
      price: _isPriceEnabled ? _effectivePrice : null,
    );
    nav.pop();
    if (result.success) {
      if (context.mounted) AppToast.success(context, 'Order placed · ${result.orderId}');
    } else {
      if (context.mounted) AppToast.error(context, result.errorMessage ?? 'Order failed');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _pill({required String label, required bool selected, required VoidCallback onTap}) {
    final selBg = _isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final selText = _isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final selBorder = _isBuy ? const Color(0xFF81C784) : const Color(0xFFEF9A9A);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? selBg : Colors.white,
          border: Border.all(color: selected ? selBorder : const Color(0xFFE0E0E0)),
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
