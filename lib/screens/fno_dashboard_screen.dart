import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';


class _FnoPosition {
  final String symbol;
  final String expiry;
  final double strike;
  final String optionType; // CE / PE / FUT
  final int qty;
  final double avgPrice;
  final double ltp;
  final OrderType side;
  final DateTime expiryDate;

  const _FnoPosition({
    required this.symbol,
    required this.expiry,
    required this.strike,
    required this.optionType,
    required this.qty,
    required this.avgPrice,
    required this.ltp,
    required this.side,
    required this.expiryDate,
  });

  double get pnl => calculateTradingPnL(
        side: side,
        ltp: ltp,
        avgPrice: avgPrice,
        quantity: qty,
      );

  bool get isExpiringSoon => expiryDate.difference(DateTime.now()).inDays <= 7;
}

// Local UI projection from live/store positions (no hardcoded F&O positions).

_FnoPosition _mapFromPosition(Position p) {
  final symbol = p.symbol.toUpperCase();
  final isIndex = symbol.contains('NIFTY');
  final inferredOptionType = isIndex ? 'CE' : 'FUT';
  final inferredStrike = isIndex ? p.avgPrice.roundToDouble() : 0.0;
  final expiryDate = DateTime.now().add(const Duration(days: 7));

  return _FnoPosition(
    symbol: p.symbol,
    expiry: DateFormat('dd MMM yyyy').format(expiryDate),
    strike: inferredStrike,
    optionType: inferredOptionType,
    qty: p.quantity,
    avgPrice: p.avgPrice,
    ltp: p.currentPrice,
    side: p.side,
    expiryDate: expiryDate,
  );
}

// ─── Strategy Leg ─────────────────────────────────────────────────────────────

class _StrategyLeg {
  String symbol;
  String expiry;
  double strike;
  String optionType;
  OrderType side;
  int qty;

  _StrategyLeg()
    : symbol = 'NIFTY',
      expiry = '30 Jan 2025',
      strike = 22800,
      optionType = 'CE',
      side = OrderType.buy,
      qty = 50;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class FnoDashboardScreen extends StatefulWidget {
  final bool showAppBar;
  const FnoDashboardScreen({super.key, this.showAppBar = true});

  @override
  State<FnoDashboardScreen> createState() => _FnoDashboardScreenState();
}

class _FnoDashboardScreenState extends State<FnoDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<_StrategyLeg> _legs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final nrmlPositions = store.positions
        .where(
          (p) => p.product == ProductType.nrml || p.product == ProductType.mis,
        )
        .toList();
    final fnoPositions = nrmlPositions.map(_mapFromPosition).toList();

    final body = Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Positions'),
              Tab(text: 'Rollover'),
              Tab(text: 'Strategy Builder'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPositionsTab(fnoPositions),
              _buildRolloverTab(fnoPositions),
              _buildStrategyBuilder(),
            ],
          ),
        ),
      ],
    );

    if (!widget.showAppBar) return Scaffold(body: body);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('F&O Dashboard'),
      ),
      body: body,
    );
  }

  Widget _buildPositionsTab(List<_FnoPosition> positions) {
    if (positions.isEmpty) {
      return const Center(
        child: Text(
          'No F&O positions available.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final totalPnl = positions.fold(0.0, (sum, p) => sum + p.pnl);
    final totalMargin = positions.fold(
      0.0,
      (sum, p) => sum + p.avgPrice * p.qty * 0.1,
    );
    final isPos = totalPnl >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Row(
            children: [
              Expanded(
                child: CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total F&O P&L',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isPos ? '+' : ''}₹${totalPnl.abs().toStringAsFixed(2)}',
                        style: AppTheme.mono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isPos ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Margin Used',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${totalMargin.toStringAsFixed(0)}',
                        style: AppTheme.mono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Open Positions (${positions.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...positions.map((p) => _positionCard(p)),
        ],
      ),
    );
  }

  Widget _positionCard(_FnoPosition p) {
    final isPos = p.pnl >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CustomCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        p.strike > 0
                            ? '${p.symbol} ${p.strike.toStringAsFixed(0)} ${p.optionType}'
                            : '${p.symbol} ${p.optionType}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: p.side == OrderType.buy ? 'BUY' : 'SELL',
                        color: p.side == OrderType.buy
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                      if (p.isExpiringSoon) ...[
                        const SizedBox(width: 6),
                        StatusBadge(
                          label: 'Expiring Soon',
                          color: AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expiry: ${p.expiry}  •  Qty: ${p.qty}  •  Avg: ₹${p.avgPrice}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${p.ltp.toStringAsFixed(2)}',
                  style: AppTheme.mono(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${isPos ? '+' : ''}₹${p.pnl.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isPos ? AppColors.success : AppColors.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolloverTab(List<_FnoPosition> positions) {
    final expiringSoon = positions.where((p) => p.isExpiringSoon).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expiringSoon.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No positions expiring within 7 days.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertTriangle,
                    color: AppColors.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${expiringSoon.length} position(s) expiring within 7 days',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...expiringSoon.map((p) => _rolloverCard(p)),
          ],
        ],
      ),
    );
  }

  Widget _rolloverCard(_FnoPosition p) {
    final daysLeft = p.expiryDate.difference(DateTime.now()).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CustomCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.strike > 0
                        ? '${p.symbol} ${p.strike.toStringAsFixed(0)} ${p.optionType}'
                        : '${p.symbol} ${p.optionType}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Expires: ${p.expiry}  •  $daysLeft days left',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Rollover for ${p.symbol} initiated')),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(80, 36),
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Rollover'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyBuilder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Strategy Legs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => setState(() => _legs.add(_StrategyLeg())),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Leg'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 36),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_legs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Add legs to build your strategy.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._legs.asMap().entries.map((e) => _legCard(e.key, e.value)),
          if (_legs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPayoffSummary(),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Strategy order placed!')),
              ),
              child: const Text('Place Strategy Order'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legCard(int index, _StrategyLeg leg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CustomCard(
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Leg ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _legs.removeAt(index)),
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: leg.optionType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'CE', child: Text('CE')),
                      DropdownMenuItem(value: 'PE', child: Text('PE')),
                      DropdownMenuItem(value: 'FUT', child: Text('FUT')),
                    ],
                    onChanged: (v) => setState(() => leg.optionType = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<OrderType>(
                    value: leg.side,
                    decoration: const InputDecoration(labelText: 'Side'),
                    items: const [
                      DropdownMenuItem(
                        value: OrderType.buy,
                        child: Text('Buy'),
                      ),
                      DropdownMenuItem(
                        value: OrderType.sell,
                        child: Text('Sell'),
                      ),
                    ],
                    onChanged: (v) => setState(() => leg.side = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: leg.qty.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (v) =>
                        setState(() => leg.qty = int.tryParse(v) ?? leg.qty),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayoffSummary() {
    final maxProfit = _legs
        .where((l) => l.side == OrderType.sell)
        .fold(0.0, (sum, l) => sum + l.qty * 50.0);
    final maxLoss = _legs
        .where((l) => l.side == OrderType.buy)
        .fold(0.0, (sum, l) => sum + l.qty * 80.0);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payoff Summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: 'Max Profit',
            value: '₹${maxProfit.toStringAsFixed(0)}',
            valueColor: AppColors.success,
          ),
          InfoRow(
            label: 'Max Loss',
            value: '-₹${maxLoss.toStringAsFixed(0)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'Legs',
            value: '${_legs.length}',
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
