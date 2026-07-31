import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Transaction;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/platform_settings.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../services/subscription_manager.dart';
import '../theme.dart';
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

// Absolute last-resort hardcoded leverage — only used when both category
// lookup AND admin global settings are unavailable.
const _fallbackLeverage = {
  'NSE': {'MIS': {'buy': 5.0, 'sell': 5.0}, 'NRML': {'buy': 1.0, 'sell': 1.0}},
  'MCX': {'MIS': {'buy': 10.0, 'sell': 10.0}, 'NRML': {'buy': 1.0, 'sell': 1.0}},
  'BSE': {'MIS': {'buy': 5.0, 'sell': 5.0}, 'NRML': {'buy': 1.0, 'sell': 1.0}},
};

class _OrderFormSheetContentState extends State<_OrderFormSheetContent> {
  late OrderType _side;
  ProductType _product = ProductType.mis;
  OrderVariety _variety = OrderVariety.market;
  bool _submitting = false;
  int _qty = 1;
  final _priceController = TextEditingController();
  final _triggerController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  final _settingsService = MarketSettingsService();
  StreamSubscription<MarketSettings>? _settingsSub;
  MarketSettings _marketSettings = MarketSettings.defaults;

  // Admin-configured leverage — real-time stream from category_leverage collection
  Map<String, Map<String, dynamic>> _categoryLeverageMap = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leverageSub;

  // Global admin defaults — cached from TradingStore via didChangeDependencies
  PlatformRmsSettings _rmsSettings = PlatformRmsSettings.defaults;

  // Live price tracking
  TradingStore? _store;
  ValueNotifier<double>? _ltpNotifier; // per-symbol notifier — fires on every tick
  double _livePrice = 0;
  DateTime? _lastTickAt; // when the most recent valid WS tick arrived

  static const _staleTickThreshold = Duration(seconds: 30);

  double get _effectiveLtp =>
      _livePrice > 0 ? _livePrice : widget.stock.currentPrice;

  bool get _isTickStale {
    if (_livePrice <= 0) return true;
    final last = _lastTickAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > _staleTickThreshold;
  }

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _priceController.text = widget.stock.currentPrice.toStringAsFixed(2);
    _triggerController.text = widget.stock.currentPrice.toStringAsFixed(2);
    // Futures & options default to NRML (carry-forward); equities default to MIS
    if (_isFuturesOrOptions) _product = ProductType.nrml;
    // Default qty to lot size so MCX/F&O orders are valid from the start
    _qty = _lotSize;
    _qtyController.text = '$_qty';
    _settingsSub = _settingsService.stream.listen((s) {
      if (mounted) setState(() => _marketSettings = s);
    });
    _subscribeCategoryLeverage();
  }

  String get _screenId => 'order_form_${widget.stock.symbol}';
  int? _subGen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rmsSettings = TradingScope.of(context).rmsSettings;

    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.removeListener(_onStoreTick);
      _ltpNotifier?.removeListener(_onLtpTick);
      _store = store;
      // Global store listener — fires on balance/position/order updates (not ticks).
      store.addListener(_onStoreTick);
      // Per-symbol ltpNotifier — fires on EVERY price tick without a global rebuild.
      // This is the only correct way to get live LTP in the order form because
      // TradingStore intentionally omits notifyListeners() on price ticks.
      _ltpNotifier = store.ltpNotifier(widget.stock.symbol);
      _ltpNotifier!.addListener(_onLtpTick);
      _subGen = SubscriptionManager.instance.subscribeForScreen(_screenId, {widget.stock.symbol});
      _onLtpTick(); // prime with current value
    }
  }

  /// Called on every price tick for this symbol via the per-symbol ltpNotifier.
  void _onLtpTick() {
    if (!mounted) return;
    final ltp = _ltpNotifier?.value ?? 0;
    if (ltp > 0 && ltp != _livePrice) {
      setState(() {
        _livePrice = ltp;
        _lastTickAt = DateTime.now();
      });
    }
  }

  /// Called when the global store notifies (balance, positions, orders, etc.).
  /// Does NOT fire on price ticks — use _onLtpTick for that.
  void _onStoreTick() {
    if (!mounted) return;
    setState(() {}); // refresh balance / margin display
  }

  void _subscribeCategoryLeverage() {
    _leverageSub?.cancel();
    _leverageSub = FirebaseFirestore.instance
        .collection('category_leverage')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final map = <String, Map<String, dynamic>>{};
          for (final doc in snap.docs) {
            map[doc.id] = Map<String, dynamic>.from(doc.data());
          }
          setState(() => _categoryLeverageMap = map);
        }, onError: (_) {});
  }

  /// Resolves which category_leverage document applies to this stock.
  /// Exactly mirrors the backend _resolveCategoryKey logic so lookups match.
  String _resolveCategoryKey() {
    final ex  = widget.stock.exchange.toUpperCase();
    final sym = widget.stock.symbol.toUpperCase();

    if (ex == 'MCX') {
      if (sym.endsWith('FUT')) { return 'mcx_futures'; }
      if (sym.endsWith('CE') || sym.endsWith('PE')) {
        return _isBuy ? 'mcx_option_buying' : 'mcx_option_selling';
      }
      return 'mcx_futures';
    }

    if (ex == 'NFO' || ex == 'BFO') {
      if (sym.endsWith('FUT')) { return 'nse_futures'; }
      if (sym.endsWith('CE') || sym.endsWith('PE')) {
        return _isBuy ? 'nse_option_buying' : 'nse_option_selling';
      }
      return 'nse_futures';
    }

    // NSE / BSE equity spot
    return 'nse_spot';
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreTick);
    _ltpNotifier?.removeListener(_onLtpTick);
    SubscriptionManager.instance.unsubscribeScreen(_screenId, _subGen);
    _priceController.dispose();
    _triggerController.dispose();
    _qtyController.dispose();
    _settingsSub?.cancel();
    _leverageSub?.cancel();
    super.dispose();
  }

  bool get _isBuy => _side == OrderType.buy;
  bool get _isMarket => _variety == OrderVariety.market;
  bool get _isSL => _variety == OrderVariety.sl;
  // Limit-price field applies to LIMIT only; the single SL option is SL-Market
  // (trigger price only, no separate limit price).
  bool get _isPriceEnabled => _variety == OrderVariety.limit;

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
  /// Priority: (1) category_leverage Firestore doc → (2) admin global defaults
  /// from trading store → (3) absolute hardcoded last-resort.
  double get _leverage => _getLeverageForProduct(_product);

  double _getLeverageForProduct(ProductType product) {
    final categoryKey = _resolveCategoryKey();
    final catData = _categoryLeverageMap[categoryKey]
                 ?? _categoryLeverageMap['nse_spot'];

    if (catData != null) {
      final pStr = product == ProductType.mis ? 'mis' : 'nrml';
      final side = _isBuy ? 'buy' : 'sell';
      final lev =
          (catData['${pStr}_${side}_leverage'] as num?)?.toDouble() ??
          (catData['${pStr}_leverage'] as num?)?.toDouble() ??
          (catData['leverage'] as num?)?.toDouble();
      if (lev != null && lev > 0) return lev;
    }

    // Fallback to admin-configured global defaults from trading store.
    // BUY → intradayLeverage / nrmlBuyLeverage
    // SELL (short) → shortSellLeverage / nrmlSellLeverage
    if (product == ProductType.mis || product == ProductType.mtf) {
      return _isBuy
          ? _rmsSettings.intradayLeverage
          : _rmsSettings.shortSellLeverage;
    }
    if (product == ProductType.nrml) {
      return _isBuy
          ? _rmsSettings.nrmlBuyLeverage
          : _rmsSettings.nrmlSellLeverage;
    }

    // Absolute last resort
    final ex   = widget.stock.exchange.toUpperCase().isEmpty ? 'NSE' : widget.stock.exchange.toUpperCase();
    final pStr = product == ProductType.mis ? 'MIS' : 'NRML';
    final side = _isBuy ? 'buy' : 'sell';
    return (_fallbackLeverage[ex]?[pStr]?[side] ?? 5.0);
  }

  /// Formatted leverage string — avoids trailing ".0"
  String _fmtLeverage(double lev) {
    return lev == lev.truncateToDouble()
        ? '${lev.toInt()}x'
        : '${lev.toStringAsFixed(1)}x';
  }

  String get _leverageLabel => _fmtLeverage(_leverage);

  /// Required margin for this order — same formula as backend.
  ///
  /// A BUY that covers an existing SHORT position releases margin instead of
  /// consuming it, so only the qty beyond the short (a flip to long) needs
  /// margin — mirrors the backend pre-flight gate in orderEngine.placeOrder.
  double get _requiredMargin {
    var marginQty = _qty;
    if (_isBuy) {
      final store = TradingScope.read(context);
      final shortQty = store.positions
          .where((p) =>
              p.symbol == widget.stock.symbol &&
              p.product == _product &&
              p.side == OrderType.sell)
          .fold(0, (s, p) => s + p.quantity);
      marginQty = _qty > shortQty ? _qty - shortQty : 0;
    }
    final tradeValue = marginQty * _effectivePrice;
    return tradeValue / _leverage;
  }

  String? get _marketBlockReason =>
      _marketSettings.checkAction(widget.stock.exchange, isBuy: _isBuy);

  double get _effectivePrice => _isPriceEnabled
      ? (double.tryParse(_priceController.text) ?? _effectiveLtp)
      : _effectiveLtp;

  double get _estimatedCharges {
    final categoryKey = _resolveCategoryKey();
    final catData =
        _categoryLeverageMap[categoryKey] ?? _categoryLeverageMap['nse_spot'];
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
      _isBuy ? AppColors.success : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.read(context);
    final balance = store.balance;

    // Use freeMargin for validation (equity-aware — accounts for running losses).
    // For users with no open positions, freeMargin == balance.
    final freeMargin = store.freeMargin;

    // Guard: Firestore balance arrives asynchronously after auth.
    // Before the first snapshot, _balance is 0.0 (a stub, not a real balance).
    // Never treat 0.0 stub as "insufficient funds" — wait for real data first.
    final isUserDataLoaded = store.isUserDataLoaded;

    // Determine if this is an instrument that allows short selling.
    // F&O, MCX, MIS, and NRML all support naked shorts (NRML subject to the
    // backend's block_overnight_short_sell flag per category).
    // CNC/delivery equity does not allow short selling.
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
        _product == ProductType.mis ||
        _product == ProductType.nrml;

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

    // BUY and short SELL both block margin — validate against freeMargin (not raw balance).
    // freeMargin = equity - usedMargin, so it correctly reflects running losses.
    // Only evaluate after user data has loaded — otherwise freeMargin is 0.0 stub.
    final hasInsufficientFunds =
        isUserDataLoaded && (_isBuy || isShortSell) && _requiredMargin > freeMargin;

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
                  _buildProductRow(),
                  const SizedBox(height: 12),
                  // SL is only offered when selling out of actual (CNC/delivery)
                  // holdings — never for intraday short-selling, an open short
                  // position, or a symbol with zero holdings.
                  _buildOrderTypeRow(showSl: !_isBuy && holdingQty > 0),
                  const SizedBox(height: 16),
                  _buildQuantityRow(availableQty),
                  const SizedBox(height: 16),
                  if (_isPriceEnabled) ...[
                    _buildPriceField(),
                    const SizedBox(height: 16),
                  ],
                  if (_isSL) ...[
                    _buildTriggerField(),
                    const SizedBox(height: 16),
                  ],
                  _buildCostBreakdown(freeMargin, isShortSell: isShortSell),
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
                          if (_isBuy || isShortSell)
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
                                            ? AppColors.danger
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
                                            : AppColors.danger,
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
                                  (_isBuy || isShortSell) ? 'Free Margin' : 'Breakdown',
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
                                    (_isBuy || isShortSell)
                                        ? '₹${freeMargin.toStringAsFixed(2)}'
                                        : '$_qty @ ₹${_effectivePrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: hasInsufficientFunds
                                          ? AppColors.danger
                                          : const Color(0xFF666666),
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
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasInsufficientFunds
                                    ? 'Insufficient free margin (₹${freeMargin.toStringAsFixed(2)} available). Add funds or reduce size.'
                                    : (availableQty == 0
                                          ? 'No ${widget.stock.symbol} to sell.'
                                          : 'Only $availableQty qty available.'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.danger,
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
                          'Lot size: $_lotSize${(_isBuy || isShortSell) && _leverage > 1 ? '  ·  $_leverageLabel leverage' : ''}',
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
                      disabledBackgroundColor: AppColors.border,
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
    final e = stock.expiry;
    final expiryStr = e != null
        ? '${e.day.toString().padLeft(2, '0')} ${_monthAbbr(e.month)} ${e.year}'
        : null;

    // CE/PE badge color
    final bool isCE = type == InstrumentType.optionCE;
    final bool isPE = type == InstrumentType.optionPE;
    final cepeColor = isCE
        ? const Color(0xFF1565C0)
        : isPE
        ? AppColors.danger
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
                Text(
                  'LTP ₹${_effectiveLtp.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
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

  // ── BUY / SELL toggle ──────────────────────────────────────────────────────

  Widget _buildSideToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _side = OrderType.buy;
              // Stop-loss orders are only offered when selling out of an
              // existing holding — switching to BUY drops any SL selection.
              if (_variety == OrderVariety.sl) {
                _variety = OrderVariety.market;
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 40,
              decoration: BoxDecoration(
                color: _side == OrderType.buy
                    ? AppColors.success
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
                    ? AppColors.danger
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
  // Shown for both BUY and SELL, equity and F&O alike: SELL needs product
  // selection because it determines whether this is a new MIS or NRML short
  // (or which position to exit), and F&O traders need the same Intraday vs
  // Overnight choice — the backend already fully supports MIS for F&O
  // (per-lot margin, RMS, and 15:25/23:25 auto square-off), this was purely a
  // frontend gap where the selector was hidden and NRML silently forced.
  Widget _buildProductRow() {
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
            color: selected ? AppColors.success : AppColors.border,
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
                      ? AppColors.success
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

  // SL is only offered when selling out of an existing holding — buys never
  // need a stop-loss entry, and a sell with nothing held has no SL use case.
  Widget _buildOrderTypeRow({required bool showSl}) {
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
            if (showSl) ...[
              const SizedBox(width: 6),
              _chip(
                'SL',
                _variety == OrderVariety.sl,
                () => setState(() => _variety = OrderVariety.sl),
              ),
            ],
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
                      color: _qty == q ? _sideColor : AppColors.border,
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
        border: Border.all(color: AppColors.border),
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

  // ── Trigger price field (SL / SL-M) ────────────────────────────────────────

  Widget _buildTriggerField() {
    // BUY SL triggers when price RISES to the trigger; SELL SL when it FALLS.
    final hint = _isBuy
        ? 'Triggers when price rises to this level'
        : 'Triggers when price falls to this level';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TRIGGER PRICE'),
        const SizedBox(height: 6),
        TextField(
          controller: _triggerController,
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
        const SizedBox(height: 4),
        Text(
          hint,
          style: const TextStyle(fontSize: 10, color: Color(0xFF888888)),
        ),
      ],
    );
  }

  // ── Cost breakdown ─────────────────────────────────────────────────────────

  Widget _buildCostBreakdown(double freeMargin, {bool isShortSell = false}) {
    final tv = _qty * _effectivePrice;
    final margin = _requiredMargin;
    final lev = _leverage;
    final marginsMargin = _isBuy || isShortSell;
    final afterMargin = freeMargin - margin - _estimatedCharges;
    // Margin utilization = (margin blocked + charges) as % of current free margin.
    // Clamped at 999% to avoid overflow display on edge cases.
    final utilization = freeMargin > 0
        ? ((margin + _estimatedCharges) / freeMargin * 100).clamp(0.0, 999.0)
        : 0.0;

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
          // Show leverage + required margin for both BUY and SHORT SELL when
          // leverage > 1.  Previously this block was gated on _isBuy only,
          // which meant short-sell orders showed no leverage or margin info.
          if (marginsMargin && lev > 1) ...[
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
          // BUY → "Total deducted" (margin + charges)
          // SHORT SELL → "Margin blocked" (same amount — NOT gross proceeds)
          // Regular SELL (closing long) → "You receive" (gross proceeds - charges)
          _row(
            _isBuy
                ? 'Total deducted'
                : isShortSell
                    ? 'Margin blocked'
                    : 'You receive',
            marginsMargin
                ? '₹${(margin + _estimatedCharges).toStringAsFixed(2)}'
                : '₹${_totalCost.toStringAsFixed(2)}',
            marginsMargin ? AppColors.danger : AppColors.success,
            bold: true,
          ),
          if (marginsMargin) ...[
            const SizedBox(height: 4),
            _row(
              'Free Margin after',
              '₹${afterMargin.toStringAsFixed(2)}',
              afterMargin >= 0
                  ? const Color(0xFF888888)
                  : AppColors.danger,
            ),
            const SizedBox(height: 4),
            _row(
              'Margin utilization',
              '${utilization.toStringAsFixed(1)}%',
              utilization > 80
                  ? AppColors.danger
                  : utilization > 50
                      ? const Color(0xFFE65100)
                      : const Color(0xFF888888),
            ),
          ],
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
                : AppColors.border,
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
    final exchange = widget.stock.exchange.isNotEmpty
        ? widget.stock.exchange
        : 'NSE';

    // For SELL orders: use the existing position/holding's product type so
    // the backend writes the same productType that the original BUY had.
    // This ensures FIFO matching works (groups by symbol+product).
    // Without this, NRML positions closed via the order form got tagged as
    // 'MIS' SELL orders → different FIFO group → trade always showed as OPEN.
    String productType;
    if (!isBuy) {
      Holding? existingHolding;
      for (final h in store.holdings) {
        if (h.symbol == symbol) { existingHolding = h; break; }
      }
      Position? existingPosition;
      for (final p in store.positions) {
        if (p.symbol == symbol) { existingPosition = p; break; }
      }
      if (existingHolding != null) {
        // Holdings are always delivery/CNC — no product field needed.
        productType = 'CNC';
      } else if (existingPosition != null) {
        productType = switch (existingPosition.product) {
          ProductType.nrml     => 'NRML',
          ProductType.overnight => 'CNC',
          ProductType.mtf       => 'MTF',
          _                     => 'MIS',
        };
      } else {
        // Opening a new short — use user-selected product
        productType = _product == ProductType.mis ? 'MIS' : 'NRML';
      }
    } else {
      productType = _product == ProductType.mis ? 'MIS' : 'NRML';
    }
    // Snapshot variety, limit price and trigger price before the sheet is dismissed
    final snapshotVariety = _variety;
    final snapshotLimitPriceText = _priceController.text;
    final snapshotTriggerPriceText = _triggerController.text;

    // ── Pre-flight field validation (sheet still open — errors keep it open) ──
    final isSLVariety = snapshotVariety == OrderVariety.sl;
    // SL always behaves as SL-Market — trigger price only, no limit price.
    final needsLimitPrice = snapshotVariety == OrderVariety.limit;
    if (needsLimitPrice) {
      final lp = double.tryParse(snapshotLimitPriceText);
      if (lp == null || lp <= 0) {
        AppToast.error(context, 'Please enter a valid limit price.');
        return;
      }
    }
    if (isSLVariety) {
      final tp = double.tryParse(snapshotTriggerPriceText);
      if (tp == null || tp <= 0) {
        AppToast.error(context, 'Please enter a valid trigger price.');
        return;
      }
    }
    final requestId =
        '${sessionUser.uid}_${DateTime.now().microsecondsSinceEpoch}';

    // ── Fresh price guard ──────────────────────────────────────────────────────
    // If the WS price is missing or the last tick is older than 30 s, fetch a
    // fresh REST quote so execution always uses the latest available rate.
    // This is done BEFORE nav.pop() so the sheet is still mounted and the
    // refreshed _livePrice is captured by _effectiveLtp below.
    String priceSource = _livePrice > 0 ? 'websocket' : 'initial';
    if (_isTickStale) {
      try {
        final refreshApi =
            BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        final detail = await refreshApi
            .getStockDetail(widget.stock.symbol.toUpperCase())
            .timeout(const Duration(seconds: 2));
        final freshLtp = (detail['ltp'] as num?)?.toDouble() ?? 0.0;
        if (freshLtp > 0) {
          _livePrice = freshLtp;
          _lastTickAt = DateTime.now();
          priceSource = 'rest-refresh';
          debugPrint('[OrderForm] Refreshed stale price: '
              '${widget.stock.symbol} ₹$freshLtp (source: rest-refresh)');
        } else {
          debugPrint('[OrderForm] REST refresh returned 0 for '
              '${widget.stock.symbol}, using existing ₹${_effectiveLtp.toStringAsFixed(2)} (source: $priceSource)');
        }
      } catch (e) {
        debugPrint('[OrderForm] REST refresh failed: $e — using '
            '$priceSource price ₹${_effectiveLtp.toStringAsFixed(2)}');
      }
    }
    final executionLtp = _effectiveLtp; // snapshot after potential refresh
    debugPrint('[OrderForm] Submit ${isBuy ? "BUY" : "SELL"} '
        '${widget.stock.symbol} qty=$qty ltp=₹${executionLtp.toStringAsFixed(2)} source=$priceSource');

    // ── SL trigger-direction guard ──────────────────────────────────────────
    // A stop-loss only makes sense on the far side of the current price: a
    // SELL SL protects a long and must fire when price FALLS to the trigger,
    // so the trigger must be below the current LTP. A BUY SL covers a short
    // and must fire when price RISES, so the trigger must be above the LTP.
    // If the trigger is already past the current price, the backend treats
    // the condition as already met and fills it at market immediately instead
    // of queueing it as pending — which looks like the order "vanished".
    // Catch that here so the user gets a clear message instead of a surprise
    // instant execution.
    if (isSLVariety && executionLtp > 0) {
      final tp = double.tryParse(snapshotTriggerPriceText) ?? 0;
      final alreadyBreached = isBuy ? tp <= executionLtp : tp >= executionLtp;
      if (alreadyBreached) {
        AppToast.error(
          context,
          isBuy
              ? 'Trigger ₹${tp.toStringAsFixed(2)} must be above the current price (₹${executionLtp.toStringAsFixed(2)}) — otherwise it fires immediately at market.'
              : 'Trigger ₹${tp.toStringAsFixed(2)} must be below the current price (₹${executionLtp.toStringAsFixed(2)}) — otherwise it fires immediately at market.',
        );
        return;
      }
    }

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
          final varietyStr = switch (snapshotVariety) {
            OrderVariety.limit => 'LIMIT',
            OrderVariety.sl => 'SL_MARKET',
            _ => 'MARKET',
          };
          final limitPriceValue = snapshotVariety == OrderVariety.limit
              ? double.tryParse(snapshotLimitPriceText)
              : null;
          final triggerPriceValue = isSLVariety
              ? double.tryParse(snapshotTriggerPriceText)
              : null;

          result = await api.placeOrder(
            userId: sessionUser.uid,
            symbol: symbol,
            qty: qty,
            type: isBuy ? 'BUY' : 'SELL',
            productType: productType,
            exchange: exchange,
            variety: varietyStr,
            limitPrice: limitPriceValue,
            triggerPrice: triggerPriceValue,
            // Pass the freshest available price so backend can execute F&O
            // contracts not in the live WebSocket feed (options, futures).
            lockedLtp: executionLtp > 0 ? executionLtp : null,
            // Token is persisted in Firestore holdings so future position
            // lookups can use token-based indexing (globally unique per contract).
            symbolToken: widget.stock.token.isNotEmpty
                ? widget.stock.token
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

      final isPending = (result['status'] as String?)?.toUpperCase() == 'PENDING';

      if (isPending) {
        // Order queued — undo optimistic balance deduction (no margin blocked yet)
        if (optimisticDebit > 0) store.setOptimisticBalance(store.balance + optimisticDebit);
        final lp = (result['limitPrice'] as num?)?.toDouble();
        final tp = (result['triggerPrice'] as num?)?.toDouble();
        // LIMIT: BUY fills when price falls (≤), SELL when it rises (≥).
        // SL: inverse — BUY triggers when price rises (≥), SELL when it falls (≤).
        final String queuedMsg;
        if (isSLVariety && tp != null) {
          queuedMsg = 'Stop loss queued — '
              '${isBuy ? 'will buy' : 'will sell'} $qty × $symbol '
              'when price ${isBuy ? '≥' : '≤'} ₹${tp.toStringAsFixed(2)}';
        } else {
          queuedMsg = 'Limit order queued — '
              '${isBuy ? 'will buy' : 'will sell'} $qty × $symbol'
              '${lp != null ? ' when price ${isBuy ? '≤' : '≥'} ₹${lp.toStringAsFixed(2)}' : ''}';
        }
        sm.clearSnackBars();
        sm.showSnackBar(
          SnackBar(
            content: Text(
              queuedMsg,
              style: const TextStyle(fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1565C0),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
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
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
          backgroundColor: AppColors.danger,
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
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
