import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_drawer.dart';
import '../widgets/shared_widgets.dart';

// ─── Mock Data ────────────────────────────────────────────────────────────────

final _expiries = [
  DateTime(2025, 1, 30),
  DateTime(2025, 2, 27),
  DateTime(2025, 3, 27),
];

OptionsChain _buildChain(DateTime expiry) {
  const strikes = [22600.0, 22700.0, 22800.0, 22900.0, 23000.0];
  const atmStrike = 22800.0;

  final strikesData = strikes.map((s) {
    final distFromAtm = (s - atmStrike).abs();
    final ceIv = 12.0 + distFromAtm / 100;
    final peIv = 11.5 + distFromAtm / 100;
    final ceLtp = s < atmStrike ? (atmStrike - s) + 50 : 50.0 - (s - atmStrike) * 0.3;
    final peLtp = s > atmStrike ? (s - atmStrike) + 50 : 50.0 - (atmStrike - s) * 0.3;

    return OptionStrike(
      strike: s,
      isAtm: s == atmStrike,
      ce: OptionData(
        ltp: ceLtp.clamp(5, 500),
        oi: (500000 - distFromAtm * 10).round(),
        changeInOi: (distFromAtm * 2).round(),
        iv: ceIv,
        volume: (200000 - distFromAtm * 5).round(),
        delta: s <= atmStrike ? 0.55 : 0.35,
        gamma: 0.002,
        theta: -8.5,
        vega: 12.0,
        bid: ceLtp.clamp(5, 500) - 0.5,
        ask: ceLtp.clamp(5, 500) + 0.5,
      ),
      pe: OptionData(
        ltp: peLtp.clamp(5, 500),
        oi: (480000 - distFromAtm * 8).round(),
        changeInOi: (distFromAtm * 1.5).round(),
        iv: peIv,
        volume: (190000 - distFromAtm * 4).round(),
        delta: s >= atmStrike ? -0.55 : -0.35,
        gamma: 0.002,
        theta: -8.0,
        vega: 11.5,
        bid: peLtp.clamp(5, 500) - 0.5,
        ask: peLtp.clamp(5, 500) + 0.5,
      ),
    );
  }).toList();

  return OptionsChain(
    underlying: 'NIFTY',
    expiry: expiry,
    underlyingPrice: 22814.65,
    strikes: strikesData,
    maxPain: 22800.0,
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class OptionsChainScreen extends StatefulWidget {
  final bool showAppBar;
  const OptionsChainScreen({super.key, this.showAppBar = true});

  @override
  State<OptionsChainScreen> createState() => _OptionsChainScreenState();
}

class _OptionsChainScreenState extends State<OptionsChainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _orderSymbol = '';
  OrderType _orderSide = OrderType.buy;

  @override
  void initState() {
    super.initState();
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

    final body = Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            tabs: _expiries
                .map((e) => Tab(text: '${e.day} ${_monthName(e.month)} ${e.year}'))
                .toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _expiries
                .map((e) => _OptionsChainView(
                      chain: _buildChain(e),
                      onStrikeTap: (strike, side) {
                        setState(() {
                          _orderSymbol = 'NIFTY';
                          _orderSide = side;
                        });
                        Scaffold.of(context).openEndDrawer();
                      },
                    ))
                .toList(),
          ),
        ),
      ],
    );

    if (!widget.showAppBar) {
      return Scaffold(
        body: body,
        endDrawer: _orderSymbol.isNotEmpty
            ? OrderFormDrawer(
                stock: store.stockBySymbol(_orderSymbol),
                initialSide: _orderSide,
              )
            : null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Options Chain — NIFTY'),
      ),
      endDrawer: _orderSymbol.isNotEmpty
          ? OrderFormDrawer(
              stock: store.stockBySymbol(_orderSymbol),
              initialSide: _orderSide,
            )
          : null,
      body: body,
    );
  }

  String _monthName(int month) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month];
  }
}

// ─── Options Chain View ───────────────────────────────────────────────────────

class _OptionsChainView extends StatelessWidget {
  final OptionsChain chain;
  final void Function(double strike, OrderType side) onStrikeTap;

  const _OptionsChainView({required this.chain, required this.onStrikeTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Underlying price info
          Row(
            children: [
              Text('NIFTY: ', style: Theme.of(context).textTheme.bodySmall),
              Text(
                chain.underlyingPrice.toStringAsFixed(2),
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 16),
              Text('Max Pain: ', style: Theme.of(context).textTheme.bodySmall),
              Text(
                chain.maxPain.toStringAsFixed(0),
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Table
          CustomCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _tableHeader(context),
                const Divider(height: 1),
                ...chain.strikes.map((s) => _strikeRow(context, s)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // OI Bar Chart
          Text('Open Interest', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          CustomCard(
            child: SizedBox(
              height: 200,
              child: SfCartesianChart(
                enableAxisAnimation: false,
                plotAreaBorderWidth: 0,
                primaryXAxis: NumericAxis(
                  labelStyle: Theme.of(context).textTheme.bodySmall,
                  majorGridLines: const MajorGridLines(width: 0),
                ),
                primaryYAxis: NumericAxis(
                  labelStyle: Theme.of(context).textTheme.bodySmall,
                  majorGridLines: MajorGridLines(
                    width: 0.5,
                    color: AppColors.border,
                  ),
                ),
                legend: const Legend(isVisible: true),
                series: <CartesianSeries>[
                  ColumnSeries<OptionStrike, double>(
                    name: 'CE OI',
                    dataSource: chain.strikes,
                    xValueMapper: (s, _) => s.strike,
                    yValueMapper: (s, _) => s.ce.oi,
                    color: AppColors.danger.withOpacity(0.7),
                    animationDuration: 0,
                  ),
                  ColumnSeries<OptionStrike, double>(
                    name: 'PE OI',
                    dataSource: chain.strikes,
                    xValueMapper: (s, _) => s.strike,
                    yValueMapper: (s, _) => s.pe.oi,
                    color: AppColors.success.withOpacity(0.7),
                    animationDuration: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(BuildContext context) {
    const style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.3,
    );
    return Container(
      color: AppColors.surfaceAlt.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // CE side
          Expanded(child: Text('OI', style: style)),
          Expanded(child: Text('ChgOI', style: style)),
          Expanded(child: Text('IV', style: style)),
          Expanded(child: Text('Vol', style: style)),
          Expanded(child: Text('LTP', style: style, textAlign: TextAlign.right)),
          Expanded(child: Text('Δ', style: style, textAlign: TextAlign.right)),
          // Strike
          const SizedBox(width: 80, child: Center(child: Text('STRIKE', style: style))),
          // PE side
          Expanded(child: Text('Δ', style: style)),
          Expanded(child: Text('LTP', style: style)),
          Expanded(child: Text('Vol', style: style)),
          Expanded(child: Text('IV', style: style)),
          Expanded(child: Text('ChgOI', style: style)),
          Expanded(child: Text('OI', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _strikeRow(BuildContext context, OptionStrike s) {
    final isAtm = s.isAtm;
    final bg = isAtm
        ? AppColors.primary.withOpacity(0.08)
        : Colors.transparent;

    return Column(
      children: [
        InkWell(
          onTap: () => onStrikeTap(s.strike, OrderType.buy),
          child: Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                // CE columns
                Expanded(child: _mono(_fmtOi(s.ce.oi), AppColors.textPrimary)),
                Expanded(child: _mono('+${s.ce.changeInOi}', AppColors.success)),
                Expanded(child: _mono('${s.ce.iv.toStringAsFixed(1)}%', AppColors.textPrimary)),
                Expanded(child: _mono(_fmtOi(s.ce.volume), AppColors.textPrimary)),
                Expanded(child: _mono(s.ce.ltp.toStringAsFixed(1), AppColors.danger, align: TextAlign.right)),
                Expanded(child: _mono(s.ce.delta.toStringAsFixed(2), AppColors.textSecondary, align: TextAlign.right)),
                // Strike
                SizedBox(
                  width: 80,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAtm ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.strike.toStringAsFixed(0),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isAtm ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                // PE columns
                Expanded(child: _mono(s.pe.delta.toStringAsFixed(2), AppColors.textSecondary)),
                Expanded(child: _mono(s.pe.ltp.toStringAsFixed(1), AppColors.success)),
                Expanded(child: _mono(_fmtOi(s.pe.volume), AppColors.textPrimary)),
                Expanded(child: _mono('${s.pe.iv.toStringAsFixed(1)}%', AppColors.textPrimary)),
                Expanded(child: _mono('+${s.pe.changeInOi}', AppColors.success)),
                Expanded(child: _mono(_fmtOi(s.pe.oi), AppColors.textPrimary, align: TextAlign.right)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _mono(String text, Color color, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      textAlign: align,
      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color),
    );
  }

  String _fmtOi(int oi) {
    if (oi >= 100000) return '${(oi / 100000).toStringAsFixed(1)}L';
    if (oi >= 1000) return '${(oi / 1000).toStringAsFixed(1)}K';
    return '$oi';
  }
}
