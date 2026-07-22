import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

enum _CriteriaType { priceRange, changePercent, volume, marketCap }

extension _CriteriaTypeLabel on _CriteriaType {
  String get label {
    switch (this) {
      case _CriteriaType.priceRange:
        return 'Price Range (₹)';
      case _CriteriaType.changePercent:
        return 'Change%';
      case _CriteriaType.volume:
        return 'Volume (L)';
      case _CriteriaType.marketCap:
        return 'Market Cap (Cr)';
    }
  }
}

class _ScreenerCriteria {
  _CriteriaType type;
  double? min;
  double? max;

  _ScreenerCriteria({required this.type, this.min, this.max});
}

class StockScreenerScreen extends StatefulWidget {
  const StockScreenerScreen({super.key});

  @override
  State<StockScreenerScreen> createState() => _StockScreenerScreenState();
}

class _StockScreenerScreenState extends State<StockScreenerScreen> {
  final List<_ScreenerCriteria> _criteria = [];
  List<Stock>? _results;

  void _addCriteria() {
    setState(() {
      _criteria.add(_ScreenerCriteria(type: _CriteriaType.priceRange));
    });
  }

  void _removeCriteria(int index) {
    setState(() {
      _criteria.removeAt(index);
      _results = null;
    });
  }

  void _applyFilter(List<Stock> all) {
    var filtered = List<Stock>.from(all);

    for (final c in _criteria) {
      filtered = filtered.where((s) {
        double? value;
        switch (c.type) {
          case _CriteriaType.priceRange:
            value = s.currentPrice;
          case _CriteriaType.changePercent:
            value = s.changePercentage;
          case _CriteriaType.volume:
            value = s.volume != null ? s.volume! / 100000 : null;
          case _CriteriaType.marketCap:
            value = s.marketCap != null ? s.marketCap! / 10000000 : null;
        }
        if (value == null) return false;
        if (c.min != null && value < c.min!) return false;
        if (c.max != null && value > c.max!) return false;
        return true;
      }).toList();
    }

    setState(() => _results = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final all = store.knownStocks.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Screener'),
        leading: const BackButton(),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Criteria',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_criteria.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.border,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'No criteria added. Tap "Add Criteria" to start.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ...List.generate(_criteria.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CriteriaRow(
                          criteria: _criteria[i],
                          onRemove: () => _removeCriteria(i),
                          onChanged: () => setState(() => _results = null),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addCriteria,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Add Criteria'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _criteria.isEmpty
                          ? null
                          : () => _applyFilter(all),
                      icon: const Icon(LucideIcons.filter, size: 16),
                      label: const Text('Apply Filter'),
                    ),
                  ),
                  if (_results != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Results',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: '${_results!.length} stocks',
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_results!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No stocks match the criteria.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      CustomCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: _results!.asMap().entries.map((entry) {
                            final i = entry.key;
                            final stock = entry.value;
                            final isPos = stock.changePercentage >= 0;
                            return Column(
                              children: [
                                if (i > 0) const Divider(height: 1),
                                ListTile(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StockDetailScreen(
                                        symbol: stock.symbol,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    stock.symbol,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${stock.name} • ${stock.sector}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₹${stock.currentPrice.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '${isPos ? '+' : ''}${stock.changePercentage.toStringAsFixed(2)}%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isPos
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CriteriaRow extends StatefulWidget {
  final _ScreenerCriteria criteria;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _CriteriaRow({
    required this.criteria,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_CriteriaRow> createState() => _CriteriaRowState();
}

class _CriteriaRowState extends State<_CriteriaRow> {
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(
      text: widget.criteria.min?.toString() ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.criteria.max?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_CriteriaType>(
                    value: widget.criteria.type,
                    isExpanded: true,
                    items: _CriteriaType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => widget.criteria.type = v);
                        widget.onChanged();
                      }
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: AppColors.danger,
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) {
                    widget.criteria.min = double.tryParse(v);
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) {
                    widget.criteria.max = double.tryParse(v);
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
