import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/order_form_sheet.dart';

// ─── Mock Data ────────────────────────────────────────────────────────────────

List<DateTime> _upcomingMonthlyExpiries([DateTime? from]) {
  final now = from ?? DateTime.now();
  final expiries = <DateTime>[];
  var month = DateTime(now.year, now.month);
  while (expiries.length < 3) {
    final expiry = _lastThursday(month.year, month.month);
    if (!expiry.isBefore(DateTime(now.year, now.month, now.day))) {
      expiries.add(expiry);
    }
    month = DateTime(month.year, month.month + 1);
  }
  return expiries;
}

DateTime _lastThursday(int year, int month) {
  var d = DateTime(year, month + 1, 0);
  while (d.weekday != DateTime.thursday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

OptionsChain _buildChain(Stock stock, DateTime expiry) {
  final rawPrice = stock.currentPrice;
  final underlying = (rawPrice.isFinite && rawPrice > 0)
      ? rawPrice
      : _basePriceFor(stock.symbol);
  final step = _strikeStepFor(stock.symbol, underlying);
  final atmStrike = (underlying / step).round() * step;
  final strikes = List<double>.generate(9, (i) => atmStrike + (i - 4) * step);
  final daysToExpiry = expiry.difference(DateTime.now()).inDays.clamp(1, 90);

  final strikesData = strikes.map((s) {
    final distFromAtm = (s - atmStrike).abs();
    final timeValue =
        ((underlying * 0.012) * (daysToExpiry / 30)).clamp(0.5, double.infinity);
    final ceIntrinsic = (underlying - s).clamp(0, double.infinity);
    final peIntrinsic = (s - underlying).clamp(0, double.infinity);
    final decay = (distFromAtm / step).clamp(0, 6);
    final tv = (timeValue * (1 - decay * 0.12)).clamp(0.5, timeValue);
    final ceLtp = ceIntrinsic + tv;
    final peLtp = peIntrinsic + tv;
    final baseOi = (250000 + (6 - decay) * 42000).round();
    final ivBase = stock.exchange.toUpperCase() == 'NFO' ? 16.0 : 20.0;

    return OptionStrike(
      strike: s,
      isAtm: s == atmStrike,
      ce: OptionData(
        ltp: ceLtp.clamp(0.05, underlying * 0.35).toDouble(),
        oi: baseOi,
        changeInOi: ((4 - decay) * 900).round(),
        iv: ivBase + decay * 1.2,
        volume: (baseOi * 0.32).round(),
        delta: s <= atmStrike ? 0.58 : 0.34,
        gamma: 0.002,
        theta: -8.5,
        vega: 12.0,
        bid: ceLtp.clamp(0.05, underlying * 0.35).toDouble() - 0.5,
        ask: ceLtp.clamp(0.05, underlying * 0.35).toDouble() + 0.5,
      ),
      pe: OptionData(
        ltp: peLtp.clamp(0.05, underlying * 0.35).toDouble(),
        oi: (baseOi * 0.94).round(),
        changeInOi: ((3.5 - decay) * 850).round(),
        iv: ivBase + 0.7 + decay,
        volume: (baseOi * 0.28).round(),
        delta: s >= atmStrike ? -0.58 : -0.34,
        gamma: 0.002,
        theta: -8.0,
        vega: 11.5,
        bid: peLtp.clamp(0.05, underlying * 0.35).toDouble() - 0.5,
        ask: peLtp.clamp(0.05, underlying * 0.35).toDouble() + 0.5,
      ),
    );
  }).toList();

  return OptionsChain(
    underlying: stock.symbol,
    expiry: expiry,
    underlyingPrice: underlying,
    strikes: strikesData,
    maxPain: atmStrike.toDouble(),
  );
}

double _basePriceFor(String symbol) {
  final s = symbol.toUpperCase();
  if (s.contains('CRUDEOILM')) return 10000.0;
  if (s.contains('CRUDEOIL')) return 10000.0;
  if (s.contains('GOLDM') || s.contains('GOLDPETAL') || s.contains('GOLDGUINEA')) return 160000.0;
  if (s.contains('GOLD')) return 160000.0;
  if (s.contains('SILVERM') || s.contains('SILVERMIC')) return 100000.0;
  if (s.contains('SILVER')) return 270000.0;
  if (s.contains('NATURALGAS')) return 300.0;
  if (s.contains('COPPER')) return 1350.0;
  if (s.contains('ZINC')) return 280.0;
  if (s.contains('LEAD')) return 195.0;
  if (s.contains('ALUMINIUM')) return 240.0;
  if (s.contains('NICKEL')) return 1700.0;
  if (s.contains('BANKNIFTY')) return 54000.0;
  if (s.contains('FINNIFTY')) return 24000.0;
  if (s.contains('MIDCPNIFTY')) return 12500.0;
  if (s.contains('NIFTY')) return 24500.0;
  if (s.contains('SENSEX')) return 82000.0;
  if (s.contains('BANKEX')) return 55000.0;
  return 1000.0;
}

double _strikeStepFor(String symbol, double price) {
  final s = symbol.toUpperCase();
  if (s.contains('CRUDEOIL')) return 50;
  if (s.contains('GOLD')) return 100;
  if (s.contains('SILVER')) return 250;
  if (s.contains('NATURALGAS')) return 5;
  if (s.contains('COPPER')) return 10;
  if (s.contains('ZINC') || s.contains('LEAD') || s.contains('ALUMINIUM')) return 5;
  if (s.contains('NICKEL')) return 10;

  if (price >= 20000) return 100;
  if (price >= 5000) return 50;
  if (price >= 1000) return 20;
  if (price >= 250) return 10;
  return 5;
}

// ─── Colors ──────────────────────────────────────────────────────────────────
const _kCallItmBg  = Color(0xFFFFF9E6);  // call ITM: light yellow
const _kPutItmBg   = Color(0xFFFFF1F1);  // put  ITM: light pink
const _kAtmBg      = Color(0xFFEFF6FF);  // ATM strike: light blue
const _kSpotBg     = Color(0xFFE8F5E9);  // spot-price row: light green
const _kBorderGray = Color(0xFFEEEEEE);
const _kCallColor  = Color(0xFF00796B);
const _kPutColor   = Color(0xFFB71C1C);
const _kStrikePrimary = Color(0xFF1565C0);

// ─── Exchange underlyings ─────────────────────────────────────────────────────
const _kMcxUnderlyings  = ['CRUDEOIL', 'CRUDEOILM', 'GOLD', 'GOLDM', 'SILVER', 'SILVERM', 'NATURALGAS', 'COPPER', 'ZINC', 'NICKEL'];
const _kNfoUnderlyings  = ['NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY', 'SENSEX'];
const _kBfoUnderlyings  = ['SENSEX', 'BANKEX'];

// ─── Screen ───────────────────────────────────────────────────────────────────

class OptionsChainScreen extends StatefulWidget {
  final bool showAppBar;

  /// Underlying symbol to show the chain for (e.g. "NIFTY", "RELIANCE").
  final String symbol;

  /// Exchange segment: 'NFO' | 'BFO' | 'MCX'. Defaults to 'NFO'.
  final String exchange;

  const OptionsChainScreen({
    super.key,
    this.showAppBar = true,
    this.symbol = 'NIFTY',
    this.exchange = 'NFO',
  });

  @override
  State<OptionsChainScreen> createState() => _OptionsChainScreenState();
}

class _OptionsChainScreenState extends State<OptionsChainScreen>
    with SingleTickerProviderStateMixin {
  late List<DateTime> _expiries;
  late DateTime _selectedExpiry;
  late String _selectedSymbol;
  late List<String> _underlyings;
  bool _isLoadingChain = false;
  String? _error;
  final Map<String, OptionsChain?> _chainCache = {};

  // Skeleton pulse animation
  late AnimationController _skeletonController;
  late Animation<double> _skeletonOpacity;

  String get _resolvedExchange {
    final ex = widget.exchange.toUpperCase();
    if (ex == 'MCX' || ex == 'BFO') return ex;
    return 'NFO';
  }

  @override
  void initState() {
    super.initState();
    final ex = widget.exchange.toUpperCase();
    _underlyings = ex == 'MCX'
        ? List.of(_kMcxUnderlyings)
        : ex == 'BFO'
            ? List.of(_kBfoUnderlyings)
            : List.of(_kNfoUnderlyings);
    if (!_underlyings.contains(widget.symbol)) {
      _underlyings.insert(0, widget.symbol);
    }
    _selectedSymbol = widget.symbol;
    _expiries = _upcomingMonthlyExpiries();
    _selectedExpiry = _expiries.first;

    // Skeleton pulse
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _skeletonOpacity = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _skeletonController, curve: Curves.easeInOut),
    );

    _loadRealExpiriesAndChain();
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    super.dispose();
  }

  Future<void> _loadRealExpiriesAndChain() async {
    setState(() {
      _isLoadingChain = true;
      _error = null;
    });
    try {
      final dates = await BackendApiService().getFnoExpiryDates(
        _selectedSymbol,
        exchange: _resolvedExchange,
        typeFilter: 'OPT',  // only option expiries — avoids futures dates in chain dropdown
      );
      if (!mounted) return;
      if (dates.isNotEmpty) {
        final realExpiries = dates
            .map((d) {
              try {
                return DateTime.parse(d);
              } catch (_) {
                return null;
              }
            })
            .whereType<DateTime>()
            .toList();
        if (realExpiries.isNotEmpty) {
          setState(() {
            _expiries = realExpiries;
            _selectedExpiry = realExpiries.first;
          });
        }
      }
    } catch (_) {
      // Fall back to mock expiries already set in initState
    }
    await _loadOptionsChain(_selectedSymbol, _selectedExpiry);
  }

  Future<void> _loadOptionsChain(String symbol, DateTime expiry) async {
    final expiryStr = DateFormat('yyyy-MM-dd').format(expiry);
    // Only skip if we have a REAL chain; null entries (prior failures) get retried
    if (_chainCache['$symbol-$expiryStr'] != null) {
      if (mounted) setState(() => _isLoadingChain = false);
      return;
    }

    if (mounted) setState(() => _isLoadingChain = true);
    try {
      final raw = await BackendApiService().getOptionsChainData(
        symbol,
        expiryStr,
        exchange: _resolvedExchange,
      );
      final chain = _parseChain(raw, symbol, expiry);
      debugPrint(
        '[OptionsChain] $symbol/$expiryStr: ${chain.strikes.length} strikes, '
        'underlyingLtp=${raw['underlyingLtp']}',
      );
      if (mounted) {
        _chainCache['$symbol-$expiryStr'] =
            chain.strikes.isEmpty ? null : chain;
        setState(() {
          _isLoadingChain = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('[OptionsChain] API error for $symbol/$expiryStr: $e');
      if (mounted) {
        _chainCache['$symbol-$expiryStr'] = null;
        setState(() {
          _isLoadingChain = false;
          // Only set error when we also have no mock fallback (stock is valid)
          _error = null; // always fall back to mock, never show error
        });
      }
    }
  }

  OptionsChain _parseChain(
    Map<String, dynamic> raw,
    String symbol,
    DateTime expiry,
  ) {
    final underlyingLtp =
        (raw['underlyingLtp'] as num?)?.toDouble() ?? _basePriceFor(symbol);
    final apiStrikes = raw['strikes'] as List? ?? [];
    final step = _strikeStepFor(symbol, underlyingLtp);
    final atmStrike = (underlyingLtp / step).round() * step;

    if (apiStrikes.isNotEmpty) {
      final hasRealPrice = apiStrikes.any((s) {
        final row = s as Map<String, dynamic>;
        return (row['ceLtp'] as num?) != null || (row['peLtp'] as num?) != null;
      });
      if (!hasRealPrice) {
        return OptionsChain(
          underlying: symbol,
          expiry: expiry,
          underlyingPrice: underlyingLtp,
          strikes: [],
          maxPain: atmStrike.toDouble(),
        );
      }
    }

    final mockFallbackStock = Stock(
      symbol: symbol,
      name: symbol,
      currentPrice: underlyingLtp,
      changePercentage: 0,
      sector: '',
      exchange: _resolvedExchange,
    );
    final mockFallbackChain = _buildChain(mockFallbackStock, expiry);
    final daysToExpiry = expiry.difference(DateTime.now()).inDays.clamp(1, 90);
    final timeValue =
        ((underlyingLtp * 0.012) * (daysToExpiry / 30)).clamp(0.5, double.infinity);
    final ivBase = _resolvedExchange == 'NFO' ? 16.0 : 20.0;

    OptionData mockCe(double strike) {
      final intrinsic = (underlyingLtp - strike).clamp(0, double.infinity);
      final decay = ((strike - atmStrike).abs() / step).clamp(0.0, 6.0);
      final tv = (timeValue * (1 - decay * 0.12)).clamp(0.5, timeValue);
      final ltp = (intrinsic + tv).clamp(0.05, underlyingLtp * 0.35);
      final oi = (250000 + (6 - decay) * 42000).round();
      return OptionData(
        ltp: ltp,
        oi: oi,
        changeInOi: ((4 - decay) * 900).round(),
        iv: ivBase + decay * 1.2,
        volume: (oi * 0.32).round(),
        delta: strike <= atmStrike ? 0.58 : 0.34,
        gamma: 0.002,
        theta: -8.5,
        vega: 12.0,
        bid: (ltp - 0.5).clamp(0.05, double.infinity),
        ask: ltp + 0.5,
      );
    }

    OptionData mockPe(double strike) {
      final intrinsic = (strike - underlyingLtp).clamp(0, double.infinity);
      final decay = ((strike - atmStrike).abs() / step).clamp(0.0, 6.0);
      final tv = (timeValue * (1 - decay * 0.12)).clamp(0.5, timeValue);
      final ltp = (intrinsic + tv).clamp(0.05, underlyingLtp * 0.35);
      final oi = (250000 * 0.94 + (6 - decay) * 39480).round();
      return OptionData(
        ltp: ltp,
        oi: oi,
        changeInOi: ((3.5 - decay) * 850).round(),
        iv: ivBase + 0.7 + decay,
        volume: (oi * 0.28).round(),
        delta: strike >= atmStrike ? -0.58 : -0.34,
        gamma: 0.002,
        theta: -8.0,
        vega: 11.5,
        bid: (ltp - 0.5).clamp(0.05, double.infinity),
        ask: ltp + 0.5,
      );
    }

    final strikesData = apiStrikes.map<OptionStrike>((s) {
      final m = s as Map<String, dynamic>;
      final strike = (m['strike'] as num).toDouble();

      final mockStrike = mockFallbackChain.strikes.firstWhere(
        (ms) => ms.strike == strike,
        orElse: () => OptionStrike(
          strike: strike,
          isAtm: strike == atmStrike,
          ce: mockCe(strike),
          pe: mockPe(strike),
        ),
      );

      final ceLtp = (m['ceLtp'] as num?)?.toDouble() ?? mockStrike.ce.ltp;
      final ceOi = (m['ceOi'] as num?)?.toInt() ?? mockStrike.ce.oi;
      final ceIv = (m['ceIv'] as num?)?.toDouble() ?? mockStrike.ce.iv;
      final peLtp = (m['peLtp'] as num?)?.toDouble() ?? mockStrike.pe.ltp;
      final peOi = (m['peOi'] as num?)?.toInt() ?? mockStrike.pe.oi;
      final peIv = (m['peIv'] as num?)?.toDouble() ?? mockStrike.pe.iv;

      return OptionStrike(
        strike: strike,
        isAtm: strike == atmStrike,
        ceToken: m['ceToken']?.toString() ?? '',
        peToken: m['peToken']?.toString() ?? '',
        ce: OptionData(
          ltp: ceLtp,
          oi: ceOi,
          changeInOi: mockStrike.ce.changeInOi,
          iv: ceIv,
          volume: mockStrike.ce.volume,
          delta: mockStrike.ce.delta,
          gamma: mockStrike.ce.gamma,
          theta: mockStrike.ce.theta,
          vega: mockStrike.ce.vega,
          bid: (ceLtp - 0.5).clamp(0.05, double.infinity),
          ask: ceLtp + 0.5,
        ),
        pe: OptionData(
          ltp: peLtp,
          oi: peOi,
          changeInOi: mockStrike.pe.changeInOi,
          iv: peIv,
          volume: mockStrike.pe.volume,
          delta: mockStrike.pe.delta,
          gamma: mockStrike.pe.gamma,
          theta: mockStrike.pe.theta,
          vega: mockStrike.pe.vega,
          bid: (peLtp - 0.5).clamp(0.05, double.infinity),
          ask: peLtp + 0.5,
        ),
      );
    }).toList();

    strikesData.sort((a, b) => a.strike.compareTo(b.strike));

    return OptionsChain(
      underlying: symbol,
      expiry: expiry,
      underlyingPrice: underlyingLtp,
      strikes: strikesData,
      maxPain: atmStrike.toDouble(),
    );
  }

  void _onSymbolChanged(String sym) {
    if (sym == _selectedSymbol) return;
    _chainCache.removeWhere((k, v) => k.startsWith('$sym-') && v == null);
    setState(() {
      _selectedSymbol = sym;
      _expiries = _upcomingMonthlyExpiries();
      _selectedExpiry = _expiries.first;
      _isLoadingChain = false;
      _error = null;
    });
    _loadRealExpiriesAndChain();
  }

  String _monthName(int month) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month];
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.read(context);
    final stock = store.stockBySymbol(_selectedSymbol);
    final expiryStr = DateFormat('yyyy-MM-dd').format(_selectedExpiry);
    final cachedChain = _chainCache['$_selectedSymbol-$expiryStr'];
    final chain = cachedChain ?? _buildChain(stock, _selectedExpiry);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(color: Colors.black87),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedSymbol,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Options Chain · $_resolvedExchange',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
      // Market summary in bottomNavigationBar — no Stack/Positioned overlay
      bottomNavigationBar: _BottomSummaryBar(stock: stock),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Symbol scroller ──────────────────────────────────────────────
            _buildUnderlyingScroller(store),
            // ── Expiry selector row ──────────────────────────────────────────
            _buildExpiryRow(context),
            // ── Loading progress bar ─────────────────────────────────────────
            if (_isLoadingChain)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: _kStrikePrimary,
              )
            else
              const SizedBox(height: 2),
            // ── Table header ─────────────────────────────────────────────────
            _buildTableHeader(),
            // ── Options body ─────────────────────────────────────────────────
            Expanded(
              child: _isLoadingChain && cachedChain == null
                  ? _buildSkeletonLoader()
                  : _error != null
                      ? _buildErrorState()
                      : _buildChainBody(stock, chain),
            ),
          ],
        ),
      ),
    );
  }

  // ── Symbol horizontal scroller ───────────────────────────────────────────────

  Widget _buildUnderlyingScroller(TradingStore store) {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorderGray)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _underlyings.length,
        itemBuilder: (context, i) {
          final sym = _underlyings[i];
          final s = store.stockBySymbol(sym);
          final selected = sym == _selectedSymbol;
          final price = s.currentPrice > 0 ? s.currentPrice : _basePriceFor(sym);
          final isUp = s.changePercentage >= 0;

          return GestureDetector(
            onTap: () => _onSymbolChanged(sym),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              constraints: const BoxConstraints(minWidth: 72),
              decoration: BoxDecoration(
                color: selected
                    ? _kStrikePrimary.withOpacity(0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _kStrikePrimary : _kBorderGray,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sym,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? _kStrikePrimary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        price >= 1000
                            ? price.toStringAsFixed(0)
                            : price.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isUp
                              ? const Color(0xFF00897B)
                              : const Color(0xFFC62828),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${isUp ? '+' : ''}${s.changePercentage.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 8, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Expiry selector row ───────────────────────────────────────────────────────

  Widget _buildExpiryRow(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        border: Border(bottom: BorderSide(color: _kBorderGray)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined,
              size: 15, color: Colors.grey[500]),
          const SizedBox(width: 6),
          const Text(
            'Expiry:',
            style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showExpiryPicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorderGray),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_selectedExpiry.day} ${_monthName(_selectedExpiry.month)} ${_selectedExpiry.year}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kStrikePrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more,
                      size: 15, color: _kStrikePrimary),
                ],
              ),
            ),
          ),
          const Spacer(),
          // PCR hint label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBorderGray),
            ),
            child: const Text(
              'CALL ← Strike → PUT',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF9E9E9E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Table header ──────────────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    const labelStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: Color(0xFF9E9E9E),
      letterSpacing: 0.6,
    );
    return Container(
      color: const Color(0xFFF8F9FB),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // CALL side header
          Expanded(
            child: Row(
              children: const [
                SizedBox(width: 14),
                Text(
                  'CALLS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _kCallColor,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(width: 6),
                Text('LTP   OI', style: labelStyle),
              ],
            ),
          ),
          // Strike column
          Container(
            width: 80,
            alignment: Alignment.center,
            child: const Text('STRIKE', style: labelStyle),
          ),
          // PUT side header
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text('OI   LTP', style: labelStyle),
                SizedBox(width: 6),
                Text(
                  'PUTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _kPutColor,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(width: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chain body ────────────────────────────────────────────────────────────────

  Widget _buildChainBody(Stock stock, OptionsChain chain) {
    final selectedExpiry = _selectedExpiry;

    if (chain.strikes.isEmpty) {
      return _buildEmptyState();
    }

    final sortedStrikes = chain.strikes.toList()
      ..sort((a, b) => a.strike.compareTo(b.strike));
    final underlying = chain.underlyingPrice;

    // Find where to insert the spot price row
    int spotIndex = sortedStrikes.indexWhere((s) => s.strike > underlying);
    if (spotIndex == -1) spotIndex = sortedStrikes.length;

    final itemCount = sortedStrikes.length + 1; // +1 for spot row

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Insert spot price row at the right position
        if (index == spotIndex) {
          return _SpotPriceRow(
            price: underlying,
            symbol: _selectedSymbol,
            stock: stock,
          );
        }
        final strikeIdx = index > spotIndex ? index - 1 : index;
        final s = sortedStrikes[strikeIdx];
        return _StrikeRow(
          strike: s,
          callItm: s.strike < underlying,
          putItm: s.strike > underlying,
          onTap: (strike, optType, ltp, token) {
            final sc = TradingScope.read(context);
            final optTypeStr =
                optType == InstrumentType.optionCE ? 'CE' : 'PE';
            final dateStr =
                DateFormat('ddMMMyy').format(selectedExpiry).toUpperCase();
            final sym =
                '${stock.symbol}$dateStr${strike.toStringAsFixed(0)}$optTypeStr';
            sc.registerSearchResult(
              symbol: sym,
              displayName:
                  '${stock.symbol} ${strike.toStringAsFixed(0)} $optTypeStr',
              instrumentType: optType,
              exchange: _resolvedExchange,
              ltp: ltp,
              token: token,
            );
            final optStock = sc.stockBySymbol(sym);
            OrderFormSheet.show(
              context,
              stock: optStock,
              initialSide: OrderType.buy,
            );
          },
        );
      },
    );
  }

  // ── Skeleton loader ───────────────────────────────────────────────────────────

  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _skeletonOpacity,
      builder: (context, _) {
        return Opacity(
          opacity: _skeletonOpacity.value,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: List.generate(8, (_) => _SkeletonStrikeRow()),
            ),
          ),
        );
      },
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: Color(0xFFE57373)),
            const SizedBox(height: 16),
            const Text(
              'Failed to load options chain',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF424242)),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unexpected error occurred',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadRealExpiriesAndChain,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kStrikePrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 52, color: Color(0xFFBDBDBD)),
            const SizedBox(height: 16),
            const Text(
              'No options data available',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Market may be closed or data is loading.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadRealExpiriesAndChain,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Reload'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kStrikePrimary,
                side: const BorderSide(color: _kStrikePrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Expiry picker ─────────────────────────────────────────────────────────────

  void _showExpiryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Expiry',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...List.generate(_expiries.length, (i) {
                final e = _expiries[i];
                final selected = _selectedExpiry == e;
                return ListTile(
                  title: Text(
                    '${e.day} ${_monthName(e.month)} ${e.year}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? _kStrikePrimary : Colors.black87,
                    ),
                  ),
                  selected: selected,
                  selectedTileColor: _kAtmBg,
                  onTap: () {
                    setState(() => _selectedExpiry = e);
                    _loadOptionsChain(_selectedSymbol, e);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ─── Spot Price Row ───────────────────────────────────────────────────────────

class _SpotPriceRow extends StatelessWidget {
  final double price;
  final String symbol;
  final Stock stock;

  const _SpotPriceRow({
    required this.price,
    required this.symbol,
    required this.stock,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = stock.changePercentage >= 0;
    final changeColor =
        isUp ? const Color(0xFF00897B) : const Color(0xFFC62828);
    final changeSign = isUp ? '+' : '';

    return Container(
      color: _kSpotBg,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: changeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SPOT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: changeColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: changeColor,
            size: 18,
          ),
          Text(
            price >= 1000
                ? price.toStringAsFixed(2)
                : price.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: changeColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$changeSign${stock.changePercentage.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: changeColor.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Strike Row ───────────────────────────────────────────────────────────────

class _StrikeRow extends StatelessWidget {
  final OptionStrike strike;
  final bool callItm;
  final bool putItm;
  final void Function(double strike, InstrumentType side, double ltp, String token) onTap;

  const _StrikeRow({
    required this.strike,
    required this.callItm,
    required this.putItm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAtm = strike.isAtm;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: _kBorderGray, width: 0.5),
          top: isAtm
              ? const BorderSide(color: Color(0xFFBBDEFB), width: 1)
              : BorderSide.none,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Call side ────────────────────────────────────────────────────
            Expanded(
              child: Material(
                color: callItm
                    ? _kCallItmBg
                    : isAtm
                        ? _kAtmBg
                        : Colors.white,
                child: InkWell(
                  splashColor: _kCallColor.withOpacity(0.08),
                  highlightColor: _kCallColor.withOpacity(0.04),
                  onTap: () =>
                      onTap(strike.strike, InstrumentType.optionCE, strike.ce.ltp, strike.ceToken),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        // LTP + IV
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '₹${_fmtPrice(strike.ce.ltp)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kCallColor,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'IV ${strike.ce.iv.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xFFAAAAAA)),
                              ),
                            ],
                          ),
                        ),
                        // OI bar
                        _OiBar(
                          oi: strike.ce.oi,
                          color: _kCallColor,
                          alignRight: false,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Strike price column ───────────────────────────────────────────
            Container(
              width: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isAtm ? _kAtmBg : Colors.white,
                border: const Border.symmetric(
                  vertical: BorderSide(color: _kBorderGray, width: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      strike.strike.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isAtm ? FontWeight.w800 : FontWeight.w600,
                        color: isAtm ? _kStrikePrimary : const Color(0xFF212121),
                      ),
                    ),
                    if (isAtm) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kStrikePrimary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ATM',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── Put side ─────────────────────────────────────────────────────
            Expanded(
              child: Material(
                color: putItm
                    ? _kPutItmBg
                    : isAtm
                        ? _kAtmBg
                        : Colors.white,
                child: InkWell(
                  splashColor: _kPutColor.withOpacity(0.08),
                  highlightColor: _kPutColor.withOpacity(0.04),
                  onTap: () =>
                      onTap(strike.strike, InstrumentType.optionPE, strike.pe.ltp, strike.peToken),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        // OI bar (mirrored)
                        _OiBar(
                          oi: strike.pe.oi,
                          color: _kPutColor,
                          alignRight: true,
                        ),
                        // LTP + IV
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${_fmtPrice(strike.pe.ltp)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kPutColor,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'IV ${strike.pe.iv.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xFFAAAAAA)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPrice(double p) {
    if (p >= 10000) return p.toStringAsFixed(0);
    if (p >= 100) return p.toStringAsFixed(1);
    return p.toStringAsFixed(2);
  }
}

// ─── OI Bar ───────────────────────────────────────────────────────────────────

class _OiBar extends StatelessWidget {
  final int oi;
  final Color color;
  final bool alignRight;

  const _OiBar({required this.oi, required this.color, required this.alignRight});

  String _compact(int v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (oi / 500000).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          _compact(oi),
          style: TextStyle(
            fontSize: 9,
            color: color.withOpacity(0.65),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 36,
            height: 4,
            child: Stack(
              children: [
                Container(color: color.withOpacity(0.1)),
                FractionallySizedBox(
                  widthFactor: fraction,
                  alignment: alignRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(color: color.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Skeleton Strike Row ──────────────────────────────────────────────────────

class _SkeletonStrikeRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderGray, width: 0.5)),
      ),
      child: Row(
        children: [
          // Call side skeleton
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bone(60, 10),
                      const SizedBox(height: 5),
                      _bone(36, 7),
                    ],
                  ),
                  const Spacer(),
                  _bone(36, 14),
                ],
              ),
            ),
          ),
          // Strike skeleton
          Container(
            width: 80,
            alignment: Alignment.center,
            child: _bone(48, 13),
          ),
          // Put side skeleton
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _bone(36, 14),
                  const Spacer(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _bone(60, 10),
                      const SizedBox(height: 5),
                      _bone(36, 7),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bone(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─── Bottom Summary Bar ───────────────────────────────────────────────────────

class _BottomSummaryBar extends StatelessWidget {
  final Stock stock;
  const _BottomSummaryBar({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isUp = stock.isPositive;
    final priceColor = isUp ? AppColors.success : AppColors.danger;
    final price = stock.currentPrice > 0
        ? stock.currentPrice
        : _basePriceFor(stock.symbol);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorderGray)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Instrument icon badge
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isUp ? Icons.trending_up : Icons.trending_down,
                  color: priceColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              // Symbol + exchange
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.symbol,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                  Text(
                    'Underlying Spot',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Price + change
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${price >= 1000 ? price.toStringAsFixed(2) : price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: priceColor,
                    ),
                  ),
                  Text(
                    '${isUp ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: priceColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
