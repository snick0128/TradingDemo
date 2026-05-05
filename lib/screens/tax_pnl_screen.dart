import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class TaxPnlScreen extends StatefulWidget {
  final bool showAppBar;

  const TaxPnlScreen({super.key, this.showAppBar = true});

  @override
  State<TaxPnlScreen> createState() => _TaxPnlScreenState();
}

class _TaxPnlScreenState extends State<TaxPnlScreen> {
  late String _selectedFy;
  late List<String> _fyOptions;

  @override
  void initState() {
    super.initState();
    _fyOptions = _buildFyOptions();
    _selectedFy = _fyOptions.first;
  }

  List<String> _buildFyOptions() {
    final now = DateTime.now();
    // FY runs April to March
    final currentFyStart = now.month >= 4 ? now.year : now.year - 1;
    return [
      'FY $currentFyStart-${(currentFyStart + 1).toString().substring(2)}',
      'FY ${currentFyStart - 1}-${currentFyStart.toString().substring(2)}',
      'FY ${currentFyStart - 2}-${(currentFyStart - 1).toString().substring(2)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final holdings = store.holdings;

    final gains = _computeCapitalGains(holdings, _selectedFy);

    final body = SingleChildScrollView(
      child: Column(
        children: [
          _FilterBar(
            fyOptions: _fyOptions,
            selectedFy: _selectedFy,
            onFyChanged: (fy) => setState(() => _selectedFy = fy),
            totalTaxableGains: gains.totalTaxableGains,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _GainsSection(
                  title: 'Short-Term Capital Gains (STCG)',
                  subtitle: 'Holdings held < 1 year — taxed at 15%',
                  items: gains.shortTerm,
                  taxRate: 0.15,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 24),
                _GainsSection(
                  title: 'Long-Term Capital Gains (LTCG)',
                  subtitle:
                      'Holdings held ≥ 1 year — taxed at 10% above ₹1 lakh',
                  items: gains.longTerm,
                  taxRate: 0.10,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Tax P&L')),
      body: body,
    );
  }

  _CapitalGainsResult _computeCapitalGains(List<Holding> holdings, String fy) {
    final now = DateTime.now();
    final shortTerm = <_GainItem>[];
    final longTerm = <_GainItem>[];

    for (final h in holdings) {
      final daysHeld = now.difference(h.purchaseDate).inDays;
      final gain = h.pnl;
      final item = _GainItem(
        symbol: h.symbol,
        name: h.name,
        quantity: h.quantity,
        avgPrice: h.avgPrice,
        currentPrice: h.currentPrice,
        purchaseDate: h.purchaseDate,
        daysHeld: daysHeld,
        gain: gain,
      );

      if (daysHeld < 365) {
        shortTerm.add(item);
      } else {
        longTerm.add(item);
      }
    }

    final stcgTotal = shortTerm.fold(0.0, (s, i) => s + i.gain);
    final ltcgTotal = longTerm.fold(0.0, (s, i) => s + i.gain);

    // LTCG: taxable only above ₹1 lakh
    final ltcgTaxable = (ltcgTotal - 100000).clamp(0.0, double.infinity);
    final stcgTax = stcgTotal > 0 ? stcgTotal * 0.15 : 0.0;
    final ltcgTax = ltcgTaxable * 0.10;
    final totalTaxableGains = stcgTotal + ltcgTaxable;

    return _CapitalGainsResult(
      shortTerm: shortTerm,
      longTerm: longTerm,
      stcgTotal: stcgTotal,
      ltcgTotal: ltcgTotal,
      stcgTax: stcgTax,
      ltcgTax: ltcgTax,
      totalTaxableGains: totalTaxableGains,
    );
  }
}

// ─── Filter Bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final List<String> fyOptions;
  final String selectedFy;
  final ValueChanged<String> onFyChanged;
  final double totalTaxableGains;

  const _FilterBar({
    required this.fyOptions,
    required this.selectedFy,
    required this.onFyChanged,
    required this.totalTaxableGains,
  });

  @override
  Widget build(BuildContext context) {
    final isPos = totalTaxableGains >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Taxable Gains',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                '${isPos ? '+' : ''}₹${totalTaxableGains.abs().toStringAsFixed(2)}',
                style: AppTheme.tabular(
                  TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: isPos ? AppColors.success : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Financial Year',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedFy,
                underline: const SizedBox.shrink(),
                items: fyOptions
                    .map(
                      (fy) => DropdownMenuItem(
                        value: fy,
                        child: Text(
                          fy,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onFyChanged(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Gains Section ────────────────────────────────────────────────────────────

class _GainsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_GainItem> items;
  final double taxRate;
  final Color color;

  const _GainsSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.taxRate,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final totalGain = items.fold(0.0, (s, i) => s + i.gain);
    final taxableGain = title.contains('Long')
        ? (totalGain - 100000).clamp(0.0, double.infinity)
        : totalGain.clamp(0.0, double.infinity);
    final estimatedTax = taxableGain * taxRate;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
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
                      'Total Gain',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${totalGain >= 0 ? '+' : ''}₹${totalGain.toStringAsFixed(2)}',
                      style: AppTheme.tabular(
                        TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: totalGain >= 0
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Est. Tax (${(taxRate * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '₹${estimatedTax.toStringAsFixed(2)}',
                      style: AppTheme.tabular(
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Table
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.fileText,
                      size: 32,
                      color: AppColors.border,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No holdings in this category',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _tableHeader(),
            const Divider(height: 1),
            ...items.map((item) => _GainRow(item: item)),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: AppColors.surfaceAlt.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Instrument', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Qty', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Avg Cost', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Current', style: _headerStyle)),
          Expanded(flex: 2, child: Text('Days Held', style: _headerStyle)),
          Expanded(
            flex: 2,
            child: Text(
              'Gain/Loss',
              style: _headerStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
  );
}

// ─── Gain Row ─────────────────────────────────────────────────────────────────

class _GainRow extends StatelessWidget {
  final _GainItem item;

  const _GainRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isPos = item.gain >= 0;
    final pnlColor = isPos ? AppColors.success : AppColors.danger;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${item.quantity}',
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.avgPrice.toStringAsFixed(2),
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.currentPrice.toStringAsFixed(2),
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${item.daysHeld}d',
                  style: AppTheme.tabular(const TextStyle(fontSize: 13)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${isPos ? '+' : ''}₹${item.gain.abs().toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: AppTheme.tabular(
                    TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: pnlColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

// ─── Data Models ──────────────────────────────────────────────────────────────

class _GainItem {
  final String symbol;
  final String name;
  final int quantity;
  final double avgPrice;
  final double currentPrice;
  final DateTime purchaseDate;
  final int daysHeld;
  final double gain;

  _GainItem({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.purchaseDate,
    required this.daysHeld,
    required this.gain,
  });
}

class _CapitalGainsResult {
  final List<_GainItem> shortTerm;
  final List<_GainItem> longTerm;
  final double stcgTotal;
  final double ltcgTotal;
  final double stcgTax;
  final double ltcgTax;
  final double totalTaxableGains;

  _CapitalGainsResult({
    required this.shortTerm,
    required this.longTerm,
    required this.stcgTotal,
    required this.ltcgTotal,
    required this.stcgTax,
    required this.ltcgTax,
    required this.totalTaxableGains,
  });
}
