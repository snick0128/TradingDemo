import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';

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
  final underlying = stock.currentPrice > 0 
      ? stock.currentPrice 
      : _basePriceFor(stock.symbol);
  final step = _strikeStepFor(stock.symbol, underlying);
  final atmStrike = (underlying / step).round() * step;
  final strikes = List<double>.generate(9, (i) => atmStrike + (i - 4) * step);
  final daysToExpiry = expiry.difference(DateTime.now()).inDays.clamp(1, 90);

  final strikesData = strikes.map((s) {
    final distFromAtm = (s - atmStrike).abs();
    final timeValue = (underlying * 0.012) * (daysToExpiry / 30);
    final ceIntrinsic = (underlying - s).clamp(0, double.infinity);
    final peIntrinsic = (s - underlying).clamp(0, double.infinity);
    final decay = (distFromAtm / step).clamp(0, 6);
    final ceLtp =
        ceIntrinsic + (timeValue * (1 - decay * 0.12)).clamp(1, timeValue);
    final peLtp =
        peIntrinsic + (timeValue * (1 - decay * 0.12)).clamp(1, timeValue);
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
  if (s.contains('CRUDEOIL')) return 6500.0;
  if (s.contains('GOLD')) return 72000.0;
  if (s.contains('SILVER')) return 85000.0;
  if (s.contains('NATURALGAS')) return 185.0;
  if (s.contains('NIFTY')) return 22450.0;
  if (s.contains('BANKNIFTY')) return 48200.0;
  return 1000.0;
}

double _strikeStepFor(String symbol, double price) {
  final s = symbol.toUpperCase();
  if (s.contains('CRUDEOIL')) return 100;
  if (s.contains('GOLD')) return 500;
  if (s.contains('SILVER')) return 1000;
  if (s.contains('NATURALGAS')) return 5;
  
  if (price >= 20000) return 100;
  if (price >= 5000) return 50;
  if (price >= 1000) return 20;
  if (price >= 250) return 10;
  return 5;
}

// ─── Colors matching screenshot ─────────────────────────────────────────────
const _kCallItmBg = Color(0xFFFFF9E6); // Light yellow
const _kPutItmBg = Color(0xFFFFF1F1); // Light red/pink
const _kSpotBg = Color(0xFFF1F5FB);    // Light blue for spot price row
const _kLabelGray = Color(0xFF757575);
const _kBorderGray = Color(0xFFEEEEEE);

// ─── Screen ───────────────────────────────────────────────────────────────────

class OptionsChainScreen extends StatefulWidget {
  final bool showAppBar;

  /// Underlying symbol to show the chain for (e.g. "NIFTY", "RELIANCE").
  /// Defaults to "NIFTY" for backward compat; real symbol passed from nav.
  final String symbol;

  const OptionsChainScreen({
    super.key,
    this.showAppBar = true,
    this.symbol = 'NIFTY',
  });

  @override
  State<OptionsChainScreen> createState() => _OptionsChainScreenState();
}

class _OptionsChainScreenState extends State<OptionsChainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final List<DateTime> _expiries;
  String _selectedSymbol = 'CRUDEOIL';
  final List<String> _underlyings = [
    'CRUDEOIL',
    'CRUDEOILM',
    'GOLD',
    'SILVER',
    'NATURALGAS',
    'NIFTY',
    'BANKNIFTY',
  ];
  bool _showOi = false;
  int _selectedExpiryIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedSymbol = widget.symbol;
    _expiries = _upcomingMonthlyExpiries();
    _tabController = TabController(length: _expiries.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final stock = store.stockBySymbol(_selectedSymbol);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: const BackButton(color: Colors.black),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedSymbol,
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              stock.name,
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildUnderlyingScroller(store),
              _buildFilterRow(),
              const Divider(height: 1, color: _kBorderGray),
              _buildTableHeader(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _expiries
                      .map(
                        (e) => _OptionsChainView(
                          chain: _buildChain(stock, e),
                          showOi: _showOi,
                          underlying: stock,
                          expiry: e,
                          onStrikeTap: (strike, optType, ltp) {
                            final store = TradingScope.of(context);
                            final optTypeStr = optType == InstrumentType.optionCE ? 'CE' : 'PE';
                            final dateStr = DateFormat('ddMMMyy').format(e).toUpperCase();
                            final sym = '${stock.symbol}$dateStr${strike.toStringAsFixed(0)}$optTypeStr';
                            
                            // Register the option in the store so order form can find it
                            store.registerSearchResult(
                              symbol: sym,
                              displayName: '${stock.symbol} ${strike.toStringAsFixed(0)} $optTypeStr',
                              instrumentType: optType,
                              exchange: stock.exchange == 'NSE' || stock.exchange == 'NFO' ? 'NFO' : 'MCX',
                              ltp: ltp,
                              token: '',
                            );

                            final optStock = store.stockBySymbol(sym);

                            OrderFormSheet.show(
                              context,
                              stock: optStock,
                              initialSide: OrderType.buy,
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 120), // Spacer for bottom bar
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomSummaryBar(stock: stock),
          ),
        ],
      ),
    );
  }

  Widget _buildUnderlyingScroller(TradingStore store) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _underlyings.length,
        itemBuilder: (context, i) {
          final sym = _underlyings[i];
          final s = store.stockBySymbol(sym);
          final selected = sym == _selectedSymbol;
          return GestureDetector(
            onTap: () => setState(() => _selectedSymbol = sym),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected ? const Color(0xFF1565C0) : _kBorderGray,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        sym,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: selected ? const Color(0xFF1565C0) : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Expiry Thu',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        (s.currentPrice > 0 ? s.currentPrice : _basePriceFor(sym)).toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: s.isPositive ? const Color(0xFF00C853) : const Color(0xFFD50000),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${s.isPositive ? '+' : ''}${s.changePercentage.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[600],
                        ),
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

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: () => _showExpiryPicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _kBorderGray),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text(
                    '${_expiries[_tabController.index].day} ${_monthName(_expiries[_tabController.index].month)} ${_expiries[_tabController.index].year}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('M', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF1565C0)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: const [
          Expanded(child: Center(child: Text('Call LTP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
          Expanded(child: Center(child: Text('Strike Price', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
          Expanded(child: Center(child: Text('Put LTP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  void _showExpiryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Expiry',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...List.generate(_expiries.length, (i) {
                final e = _expiries[i];
                final selected = _tabController.index == i;
                return ListTile(
                  title: Text(
                    '${e.day} ${_monthName(e.month)} ${e.year}',
                    textAlign: TextAlign.center,
                  ),
                  selected: selected,
                  onTap: () {
                    setState(() => _tabController.index = i);
                    Navigator.pop(context);
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

  String _monthName(int month) {
    const names = [
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
    return names[month];
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1565C0) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

// ─── Options Chain View ───────────────────────────────────────────────────────

enum _ChainView { calls, both, puts }

class _OptionsChainView extends StatelessWidget {
  final OptionsChain chain;
  final bool showOi;
  final Stock underlying;
  final DateTime expiry;
  final void Function(double strike, InstrumentType optType, double ltp) onStrikeTap;

  const _OptionsChainView({
    required this.chain,
    required this.showOi,
    required this.underlying,
    required this.expiry,
    required this.onStrikeTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sort strikes to ensure middle-out structure
    final sortedStrikes = chain.strikes.toList()..sort((a, b) => a.strike.compareTo(b.strike));
    final underlying = chain.underlyingPrice;

    // Find spot to insert "Spot Price" row
    int spotIndex = sortedStrikes.indexWhere((s) => s.strike > underlying);
    if (spotIndex == -1) spotIndex = sortedStrikes.length;

    return ListView.builder(
      itemCount: sortedStrikes.length + 1,
      itemBuilder: (context, i) {
        if (i == spotIndex) {
          return _buildSpotRow();
        }
        final strikeIdx = i > spotIndex ? i - 1 : i;
        final s = sortedStrikes[strikeIdx];
        final callItm = s.strike < underlying;
        final putItm = s.strike > underlying;

        return _StrikeRow(
          strike: s,
          callItm: callItm,
          putItm: putItm,
          onTap: onStrikeTap,
        );
      },
    );
  }

  Widget _buildSpotRow() {
    final changeText = '+354.00 (+3.78%)'; // Mocked for design
    return Container(
      color: _kSpotBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            chain.underlyingPrice.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00796B),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_up, color: Color(0xFF00796B), size: 18),
          Text(
            changeText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF00796B),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrikeRow extends StatelessWidget {
  final OptionStrike strike;
  final bool callItm;
  final bool putItm;
  final void Function(double strike, InstrumentType side, double ltp) onTap;

  const _StrikeRow({
    required this.strike,
    required this.callItm,
    required this.putItm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Call LTP
        Expanded(
          child: GestureDetector(
            onTap: () => onTap(strike.strike, InstrumentType.optionCE, strike.ce.ltp),
            child: Container(
              height: 60,
              color: callItm ? _kCallItmBg : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${strike.ce.ltp.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00C853),
                    ),
                  ),
                  Text(
                    '+58.30%', // Mocked for design
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Strike
        Container(
          width: 80,
          height: 60,
          color: Colors.white,
          alignment: Alignment.center,
          child: Text(
            strike.strike.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
        // Put LTP
        Expanded(
          child: GestureDetector(
            onTap: () => onTap(strike.strike, InstrumentType.optionPE, strike.pe.ltp),
            child: Container(
              height: 60,
              color: putItm ? _kPutItmBg : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${strike.pe.ltp.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD50000),
                    ),
                  ),
                  Text(
                    '-65.14%', // Mocked for design
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomSummaryBar extends StatelessWidget {
  final Stock stock;
  const _BottomSummaryBar({required this.stock});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorderGray)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Market summary row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.surfaceAlt,
              child: Row(
                children: [
                  Icon(
                    stock.isPositive ? Icons.trending_up : Icons.trending_down,
                    color: stock.isPositive ? AppColors.success : AppColors.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${stock.symbol} Market Summary",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    "₹${stock.currentPrice.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: stock.isPositive ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: _kBorderGray),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: Colors.black54),
            ],
          ],
        ),
      ),
    );
  }
}
