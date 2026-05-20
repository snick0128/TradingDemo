import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Transaction;
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
/// Automatically routes to the correct form layout based on [stock.instrumentType]:
///   - equity / unknown   → standard equity form
///   - futures            → futures-specific form (lot size, expiry, margin)
///   - options CE/PE      → options-specific form (premium, lot size, OI)
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
      builder: (_) =>
          _OrderFormSheetContent(stock: stock, initialSide: initialSide),
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

// NSE F&O lot sizes (approximate; updated quarterly by NSE)
const _nseFnoLotSizes = {
  'NIFTY': 25,
  'BANKNIFTY': 15,
  'FINNIFTY': 40,
  'MIDCPNIFTY': 75,
  'SENSEX': 10,
  'RELIANCE': 250,
  'TCS': 150,
  'INFY': 300,
  'HDFCBANK': 550,
  'ICICIBANK': 700,
  'SBIN': 1500,
  'WIPRO': 1500,
  'AXISBANK': 1200,
  'BAJFINANCE': 125,
  'HINDUNILVR': 300,
  'TATASTEEL': 5500,
  'ADANIENT': 625,
  'LTIM': 150,
  'SUNPHARMA': 700,
  'BAJAJFINSV': 500,
};

// Default leverage per exchange/product — mirrors backend DEFAULT_LEVERAGE
// NRML (Overnight) can now have leverage > 1 if admin configures it.
const _defaultLeverage = {
  'NSE': {'MIS': 5, 'NRML': 1},
  'MCX': {'MIS': 10, 'NRML': 1},
  'BSE': {'MIS': 5, 'NRML': 1},
};

class _OrderFormSheetContentState extends State<_OrderFormSheetContent> {
  late OrderType _side;
  ProductType _product = ProductType.mis;
  OrderVariety _variety = OrderVariety.market;
  bool _submitting = false;
  int _qty = 1;
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  // Admin-configured leverage loaded from Firestore
  Map<String, Map<String, dynamic>> _categoryLeverageMap = {};

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _priceController.text = widget.stock.currentPrice.toStringAsFixed(2);
    // Futures & options default to NRML (carry-forward); equities default to MIS
    if (_isFuturesOrOptions) _product = ProductType.nrml;
    // Default qty to lot size so MCX/F&O orders are valid from the start
    _qty = _lotSize;
    _qtyController.text = '$_qty';
    _settingsSub = _settingsService.stream.listen((s) {
      if (mounted) setState(() => _marketSettings = s);
    });
    _loadCategoryLeverage();
  }

  Future<void> _loadCategoryLeverage() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('category_leverage')
          .get();
      if (!mounted) return;
      final map = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        map[doc.id] = doc.data();
      }
      setState(() => _categoryLeverageMap = map);
    } catch (_) {
      // Silently fall back to hardcoded defaults
    }
  }

  /// Resolves which category_leverage document applies to this stock.
  /// Mirrors the backend _resolveCategoryKey logic.
  String _resolveCategoryKey() {
    final ex = widget.stock.exchange.toUpperCase();
    final sym = widget.stock.symbol.toUpperCase();

    if (ex == 'MCX') {
      if (['GOLD', 'GOLDM', 'GOLDPETAL'].contains(sym)) return 'mcx_gold';
      if (['SILVER', 'SILVERM'].contains(sym)) return 'mcx_silver';
      if (['CRUDEOIL', 'NATURALGAS'].contains(sym)) return 'mcx_energy';
      if (['COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL'].contains(sym))
        return 'mcx_base_metals';
      if (['COTTON', 'KAPAS'].contains(sym)) return 'mcx_agri';
      return 'mcx_energy';
    }

    const nifty50 = {
      'RELIANCE',
      'TCS',
      'INFY',
      'HDFCBANK',
      'SBIN',
      'BHARTIARTL',
      'ICICIBANK',
      'KOTAKBANK',
      'LT',
      'ITC',
      'AXISBANK',
      'ASIANPAINT',
      'MARUTI',
      'TITAN',
      'NESTLEIND',
      'ULTRACEMCO',
      'WIPRO',
      'ONGC',
      'HCLTECH',
      'POWERGRID',
      'TECHM',
      'NTPC',
      'SUNPHARMA',
      'TATAMOTORS',
      'TATASTEEL',
      'JSWSTEEL',
      'M&M',
      'ADANIENT',
      'HDFC',
      'BAJAJFINSV',
    };
    if (nifty50.contains(sym)) return 'nifty50';

    const bankNifty = {
      'HDFCBANK',
      'ICICIBANK',
      'SBIN',
      'AXISBANK',
      'KOTAKBANK',
      'BANKBARODA',
      'PNB',
      'INDUSINDBK',
      'IDFCFIRSTB',
      'FEDERALBNK',
      'BANKINDIA',
    };
    if (bankNifty.contains(sym)) return 'banknifty';

    const midcap = {
      'BAJFINANCE',
      'WIPRO',
      'HINDUNILVR',
      'MARICO',
      'DABUR',
      'MPHASIS',
      'PERSISTENT',
      'COFORGE',
      'LTIM',
      'INDUSTOWER',
      'ALKEM',
      'VOLTAS',
    };
    if (midcap.contains(sym)) return 'nifty_midcap';

    return 'nse_equity';
  }

  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool get _isBuy => _side == OrderType.buy;
  bool get _isMarket => _variety == OrderVariety.market;
  bool get _isPriceEnabled =>
      _variety == OrderVariety.limit || _variety == OrderVariety.sl;

  /// Lot size for this instrument.
  /// MCX commodities and NSE F&O instruments both have known lot sizes.
  int get _lotSize {
    final type = widget.stock.instrumentType;
    final sym = widget.stock.symbol.toUpperCase();
    final ex = widget.stock.exchange.toUpperCase();

    if (ex == 'MCX' || type == InstrumentType.futuresCom) {
      return _mcxLotSizes[sym] ?? 1;
    }
    if (type.isFuturesContract || type.isOption) {
      // NSE futures/options — look up by underlying symbol
      final underlying = sym
          .replaceAll(
            RegExp(r'\d{2}[A-Z]{3}\d{2,5}(CE|PE|FUT)$', caseSensitive: false),
            '',
          )
          .trim();
      return _nseFnoLotSizes[underlying] ?? _nseFnoLotSizes[sym] ?? 1;
    }
    return 1;
  }

  bool get _isFuturesOrOptions =>
      widget.stock.instrumentType.isFuturesContract ||
      widget.stock.instrumentType.isOption;

  /// Effective leverage — mirrors backend resolveLeverage with buy/sell split.
  /// Reads admin-configured values from Firestore; falls back to hardcoded defaults.
  double get _leverage => _getLeverageForProduct(_product);

  double _getLeverageForProduct(ProductType product) {
    final categoryKey = _resolveCategoryKey();
    final catData =
        _categoryLeverageMap[categoryKey] ?? _categoryLeverageMap['nse_equity'];

    if (catData != null) {
      final pStr = product == ProductType.mis ? 'mis' : 'nrml';
      final side = _isBuy ? 'buy' : 'sell';
      final lev =
          (catData['${pStr}_${side}_leverage'] as num?)?.toDouble() ??
          (catData['${pStr}_leverage'] as num?)?.toDouble() ??
          (catData['leverage'] as num?)?.toDouble();
      if (lev != null && lev > 0) return lev;
    }

    // Fallback to hardcoded defaults
    final ex = widget.stock.exchange.toUpperCase().isEmpty
        ? 'NSE'
        : widget.stock.exchange.toUpperCase();
    final pStr = product == ProductType.mis ? 'MIS' : 'NRML';
    return (_defaultLeverage[ex]?[pStr] ?? _defaultLeverage['NSE']!['MIS'])!
        .toDouble();
  }

  /// Formatted leverage string — avoids trailing ".0"
  String _fmtLeverage(double lev) {
    return lev == lev.truncateToDouble()
        ? '${lev.toInt()}x'
        : '${lev.toStringAsFixed(1)}x';
  }

  String get _leverageLabel => _fmtLeverage(_leverage);

  /// Required margin for this order — same formula as backend.
  double get _requiredMargin {
    final tradeValue = _qty * _effectivePrice;
    return tradeValue / _leverage;
  }

  String? get _marketBlockReason =>
      _marketSettings.checkAction(widget.stock.exchange, isBuy: _isBuy);

  double get _effectivePrice => _isPriceEnabled
      ? (double.tryParse(_priceController.text) ?? widget.stock.currentPrice)
      : widget.stock.currentPrice;

  double get _estimatedCharges {
    final categoryKey = _resolveCategoryKey();
    final catData =
        _categoryLeverageMap[categoryKey] ?? _categoryLeverageMap['nse_equity'];
    if (catData == null) return 0.0;

    final pStr = _product == ProductType.mis ? 'mis' : 'nrml';
    final side = _isBuy ? 'buy' : 'sell';

    final fixed =
        (catData['${pStr}_${side}_fixed_charge'] as num?)?.toDouble() ?? 0.0;
    final percent =
        (catData['${pStr}_${side}_percent_charge'] as num?)?.toDouble() ?? 0.0;
    final other =
        (catData['${pStr}_${side}_other_charge'] as num?)?.toDouble() ?? 0.0;
    final trade =
        (catData['${pStr}_${side}_trade_charge'] as num?)?.toDouble() ?? 0.0;

    final tv = _qty * _effectivePrice;
    return trade + fixed + (tv * percent / 100) + (tv * other / 100);
  }

  /// Quick-select qty chips — multiples of lot size.
  List<int> get _qtyChips {
    final lot = _lotSize;
    if (lot == 1) return [1, 5, 10, 50];
    return [lot, lot * 2, lot * 5, lot * 10];
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

    // Determine if this is a futures/options/MIS instrument that allows short selling.
    // For such instruments we skip the "insufficient holdings" check on SELL.
    final ex = widget.stock.exchange.toUpperCase();
    final sym = widget.stock.symbol.toUpperCase();
    final isFnoOrMis =
        _isFuturesOrOptions ||
        ex == 'MCX' ||
        ex == 'NFO' ||
        ex == 'BFO' ||
        sym.endsWith('FUT') ||
        sym.endsWith('CE') ||
        sym.endsWith('PE') ||
        _product == ProductType.mis;

    // SELL: find available qty from both holdings (CNC) and positions (MIS)
    final holdingQty = store.holdings
        .where((h) => h.symbol == widget.stock.symbol)
        .fold(0, (s, h) => s + h.quantity);
    final positionQty = store.positions
        .where((p) => p.symbol == widget.stock.symbol)
        .fold(0, (s, p) => s + p.quantity);
    final availableQty = holdingQty + positionQty;

    // For F&O/MIS: allow naked short selling — never block on qty check.
    // For CNC equity: require sufficient holdings before selling.
    final hasInsufficientQty = !_isBuy && !isFnoOrMis && _qty > availableQty;

    // For short-sell info display: show margin needed when selling beyond
    // the currently available quantity.
    final isShortSell = !_isBuy && isFnoOrMis && _qty > availableQty;

    // BUY and short SELL both block margin. Exit SELL only needs quantity.
    final hasInsufficientFunds =
        (_isBuy || isShortSell) && _requiredMargin > balance;

    final blockReason = _marketBlockReason;
    final isBlocked = blockReason != null;
    final bottomPad =
        MediaQuery.of(context).viewInsets.bottom +
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
          _buildHeader(context),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isFuturesOrOptions) ...[
                    _buildDerivativeContextBanner(),
                    const SizedBox(height: 12),
                  ],
                  _buildSideToggle(),
                  const SizedBox(height: 16),
                  if (_isBuy) ...[
                    _buildProductRow(),
                    const SizedBox(height: 12),
                  ],
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
          if (isBlocked)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFFB300).withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.clock,
                    size: 13,
                    color: Color(0xFFE65100),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      blockReason,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Info footer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_isBuy)
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _leverage > 1
                                        ? 'Margin needed'
                                        : 'Cash needed',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black.withOpacity(0.4),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '₹${_requiredMargin.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: hasInsufficientFunds
                                            ? const Color(0xFFD50000)
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isFnoOrMis ? 'Position' : 'Available',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black.withOpacity(0.4),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isShortSell
                                          ? const Color(0xFFFFF3E0)
                                          : availableQty > 0
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFFFEBEE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isShortSell
                                          ? 'Short'
                                          : '$availableQty qty',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isShortSell
                                            ? const Color(0xFFE65100)
                                            : availableQty > 0
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFD50000),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 16),
                          Container(
                            height: 30,
                            width: 1,
                            color: const Color(0xFFE9ECEF),
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isBuy ? 'Balance' : 'Breakdown',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black.withOpacity(0.4),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _isBuy
                                        ? '₹${balance.toStringAsFixed(2)}'
                                        : '$_qty @ ₹${_effectivePrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (hasInsufficientFunds || hasInsufficientQty) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFE9ECEF)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 14,
                              color: Color(0xFFD50000),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasInsufficientFunds
                                    ? 'Insufficient funds. Please add money.'
                                    : (availableQty == 0
                                          ? 'No ${widget.stock.symbol} to sell.'
                                          : 'Only $availableQty qty available.'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFD50000),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (isShortSell) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFE9ECEF)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Color(0xFFE65100),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Opening short position — margin will be blocked.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_lotSize > 1) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 13,
                        color: Colors.black.withOpacity(0.4),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Lot size: $_lotSize${_isBuy && _leverage > 1 ? '  ·  $_leverageLabel leverage' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.5),
                          ),
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
                    onPressed:
                        (hasInsufficientFunds ||
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
                            isBlocked
                                ? (_isBuy
                                      ? 'Buy Unavailable'
                                      : 'Sell Unavailable')
                                : isShortSell
                                ? 'Short ${widget.stock.symbol}  ·  $_qty qty'
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

  // ── Derivative context banner ──────────────────────────────────────────────

  Widget _buildDerivativeContextBanner() {
    final stock = widget.stock;
    final type = stock.instrumentType;
    final daysLeft = stock.daysToExpiry;
    final expiryStr = stock.expiry != null
        ? '${stock.expiry!.day.toString().padLeft(2, '0')} '
              '${_monthAbbr(stock.expiry!.month)} ${stock.expiry!.year}'
        : null;

    // CE/PE badge color
    final bool isCE = type == InstrumentType.optionCE;
    final bool isPE = type == InstrumentType.optionPE;
    final cepeColor = isCE
        ? const Color(0xFF1565C0)
        : isPE
        ? const Color(0xFFD50000)
        : const Color(0xFF7B1FA2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cepeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cepeColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Instrument type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cepeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCE
                      ? 'CALL'
                      : isPE
                      ? 'PUT'
                      : 'FUTURES',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Strike price for options
              if (stock.strikePrice != null)
                Flexible(
                  child: Text(
                    'Strike ₹${stock.strikePrice!.toStringAsFixed(0)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cepeColor,
                    ),
                  ),
                ),
              const Spacer(),
              // Lot size indicator
              if (_lotSize > 1)
                Text(
                  'Lot: $_lotSize',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
            ],
          ),
          // Expiry + days left
          if (expiryStr != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: Colors.black.withOpacity(0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  'Expiry: $expiryStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
                const Spacer(),
                if (daysLeft != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: daysLeft <= 7
                          ? const Color(0xFFFFEBEE)
                          : daysLeft <= 30
                          ? const Color(0xFFFFF8E1)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      daysLeft == 0 ? 'Expires today' : '$daysLeft d left',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: daysLeft <= 7
                            ? const Color(0xFFD32F2F)
                            : daysLeft <= 30
                            ? const Color(0xFFE65100)
                            : const Color(0xFF757575),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _monthAbbr(int month) {
    const m = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m[month.clamp(1, 12)];
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
                    color: Color(0xFF111111),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'LTP ₹${widget.stock.currentPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isMarket
                          ? 'Exec ₹${(_isBuy ? widget.stock.currentPrice * 1.0002 : widget.stock.currentPrice * 0.9998).toStringAsFixed(2)}'
                          : '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isBuy
                            ? const Color(0xFF00A020)
                            : const Color(0xFFCC2200),
                      ),
                    ),
                  ],
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
  Widget _buildProductRow() {
    // Hide for F&O (already NRML by default) — show for both equity BUY and SELL
    if (_isFuturesOrOptions) return const SizedBox.shrink();

    final misLev = _getLeverageForProduct(ProductType.mis);
    final nrmlLev = _getLeverageForProduct(ProductType.nrml);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRODUCT'),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _productChip(
                'Intraday',
                misLev,
                _product == ProductType.mis,
                () => setState(() => _product = ProductType.mis),
              ),
              const SizedBox(width: 8),
              _productChip(
                'Overnight',
                nrmlLev,
                _product == ProductType.nrml,
                () => setState(() => _product = ProductType.nrml),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _productChip(
    String label,
    double leverage,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E9) : Colors.white,
          border: Border.all(
            color: selected ? const Color(0xFF00C853) : const Color(0xFFE0E0E0),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF666666),
              ),
            ),
            if (leverage > 1) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF00C853)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _fmtLeverage(leverage),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF888888),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
            _chip(
              'Market',
              _variety == OrderVariety.market,
              () => setState(() => _variety = OrderVariety.market),
            ),
            const SizedBox(width: 6),
            _chip(
              'Limit',
              _variety == OrderVariety.limit,
              () => setState(() => _variety = OrderVariety.limit),
            ),
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
            for (final q in _qtyChips) ...[
              GestureDetector(
                onTap: () => setState(() {
                  _qty = q;
                  _qtyController.text = '$_qty';
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _qty == q
                        ? _sideColor.withOpacity(0.1)
                        : Colors.white,
                    border: Border.all(
                      color: _qty == q ? _sideColor : const Color(0xFFE0E0E0),
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$q',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _qty == q ? _sideColor : const Color(0xFF666666),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            const Spacer(),
            _stepBtn(LucideIcons.minus, () {
              final next = _qty - lot;
              if (next >= lot) {
                setState(() {
                  _qty = next;
                  _qtyController.text = '$_qty';
                });
              }
            }),
            SizedBox(
              width: 56,
              child: TextField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null && parsed > 0) {
                    setState(() => _qty = parsed);
                  }
                },
                onTap: () => _qtyController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _qtyController.text.length,
                ),
              ),
            ),
            _stepBtn(
              LucideIcons.plus,
              () => setState(() {
                _qty = _qty + lot;
                _qtyController.text = '$_qty';
              }),
            ),
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: '₹ ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _sideColor, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
          _row(
            'Trade value',
            '₹${tv.toStringAsFixed(2)}',
            const Color(0xFF111111),
          ),
          const SizedBox(height: 6),
          if (_isBuy && lev > 1) ...[
            _row('Leverage', _leverageLabel, const Color(0xFF1565C0)),
            const SizedBox(height: 6),
            _row(
              'Margin required',
              '₹${margin.toStringAsFixed(2)}',
              const Color(0xFF111111),
            ),
            const SizedBox(height: 6),
          ],
          if (_estimatedCharges > 0) ...[
            const SizedBox(height: 6),
            _row(
              'Est. charges',
              '₹${_estimatedCharges.toStringAsFixed(2)}',
              const Color(0xFF888888),
            ),
          ],
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

  Widget _row(
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
          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (_isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE))
              : Colors.white,
          border: Border.all(
            color: selected
                ? (_isBuy ? const Color(0xFF81C784) : const Color(0xFFEF9A9A))
                : const Color(0xFFE0E0E0),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? (_isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828))
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

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitOrder(BuildContext context, store) async {
    if (_submitting) return;
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();

    if (appScope == null) {
      AppToast.error(context, 'Session unavailable. Please log in again.');
      return;
    }

    final sessionUser = appScope.notifier?.user;
    if (sessionUser == null) {
      AppToast.error(context, 'Please login again.');
      return;
    }

    // Snapshot all order parameters before closing the sheet
    final nav = Navigator.of(context);
    final sm = ScaffoldMessenger.of(context);
    final qty = _qty;
    final isBuy = _isBuy;
    final symbol = widget.stock.symbol;
    final productType = _product == ProductType.mis ? 'MIS' : 'NRML';
    final exchange = widget.stock.exchange.isNotEmpty
        ? widget.stock.exchange
        : 'NSE';
    final requestId =
        '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}';

    // Optimistic: deduct margin from balance immediately so the UI feels instant
    final holdingQty = store.holdings
        .where((h) => h.symbol == widget.stock.symbol)
        .fold(0, (s, h) => s + h.quantity);
    final positionQty = store.positions
        .where((p) => p.symbol == widget.stock.symbol)
        .fold(0, (s, p) => s + p.quantity);
    final isShortSell = !isBuy && qty > (holdingQty + positionQty);
    final optimisticDebit = (isBuy || isShortSell)
        ? _requiredMargin + _estimatedCharges
        : 0.0;
    if (optimisticDebit > 0) {
      store.setOptimisticBalance(store.balance - optimisticDebit);
    }

    // Close the sheet right away — perceived latency drops to ~0ms
    setState(() => _submitting = true);
    nav.pop();

    sm.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isBuy ? 'Buying' : 'Selling'} $qty × $symbol…',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        duration: const Duration(seconds: 15),
        backgroundColor: const Color(0xFF1565C0),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Background API call — sheet is already dismissed.
    // Retries up to 3 times on transient network failures (not on BackendException).
    // The clientRequestId ensures the backend deduplicates any double-delivery.
    try {
      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      Map<String, dynamic> result = {};
      for (int attempt = 0; ; attempt++) {
        try {
          result = await api.placeOrder(
            userId: sessionUser.uid,
            symbol: symbol,
            qty: qty,
            type: isBuy ? 'BUY' : 'SELL',
            productType: productType,
            exchange: exchange,
            // Pass current price so backend can execute F&O contracts that are
            // not in the live WebSocket feed (options, futures).
            lockedLtp: widget.stock.currentPrice > 0
                ? widget.stock.currentPrice
                : null,
            clientRequestId: requestId,
          );
          break; // success
        } on BackendException {
          rethrow; // business error — never retry (balance check, no position, etc.)
        } catch (_) {
          if (attempt >= 2) rethrow; // 3 total attempts exhausted
          sm.clearSnackBars();
          sm.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Retrying ${isBuy ? 'buy' : 'sell'} $symbol… (${attempt + 2}/3)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              duration: const Duration(seconds: 15),
              backgroundColor: const Color(0xFF1565C0),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await Future.delayed(Duration(seconds: 2 << attempt)); // 2s, 4s
        }
      }

      final newBal = (result['newBalance'] as num?)?.toDouble();
      if (newBal != null) store.setOptimisticBalance(newBal);

      sm.clearSnackBars();
      final executed = result['executedPrice'] ?? result['price'];
      sm.showSnackBar(
        SnackBar(
          content: Text(
            '${isBuy ? 'Bought' : 'Sold'} $qty × $symbol'
            '${executed != null ? ' @ ₹${(executed as num).toStringAsFixed(2)}' : ''}',
            style: const TextStyle(fontSize: 13),
          ),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } on BackendException catch (e) {
      // Undo optimistic balance deduction on failure
      if (optimisticDebit > 0) {
        store.setOptimisticBalance(store.balance + optimisticDebit);
      }

      String msg = e.message;
      if (msg.contains('Insufficient balance') ||
          msg.contains('Not enough funds')) {
        msg = 'Insufficient balance.';
      } else if (msg.contains('No position') ||
          msg.contains('Insufficient quantity') ||
          msg.contains("don't have any")) {
        msg = 'Not enough holdings to sell.';
      } else if (msg.contains('market data') ||
          msg.contains('Market may be closed') ||
          msg.contains('not available right now')) {
        msg = 'Live price unavailable. Please try again.';
      }

      sm.clearSnackBars();
      sm.showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          backgroundColor: const Color(0xFFD50000),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (optimisticDebit > 0) {
        store.setOptimisticBalance(store.balance + optimisticDebit);
      }
      sm.clearSnackBars();
      sm.showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(fontSize: 13),
          ),
          backgroundColor: const Color(0xFFD50000),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
