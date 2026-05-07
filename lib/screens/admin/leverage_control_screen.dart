import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import 'admin_ui.dart';

// ── Per-symbol leverage options ───────────────────────────────────────────────
// Each symbol has a max leverage cap based on its exchange/type.
// Admin can set any value up to the platform max for that symbol.

class _SymbolLevConfig {
  final String symbol;
  final String exchange;
  final String description;
  final List<int> options; // allowed leverage multipliers, descending

  const _SymbolLevConfig({
    required this.symbol,
    required this.exchange,
    required this.description,
    required this.options,
  });
}

// Platform-max leverage per symbol (matches the image reference)
const _kSymbolLevConfigs = [
  // NSE Equities — NSE Spot: max 20x
  _SymbolLevConfig(symbol: 'RELIANCE',   exchange: 'NSE', description: 'Reliance Industries', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'TCS',        exchange: 'NSE', description: 'Tata Consultancy Services', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'INFY',       exchange: 'NSE', description: 'Infosys', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'HDFCBANK',   exchange: 'NSE', description: 'HDFC Bank', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'ICICIBANK',  exchange: 'NSE', description: 'ICICI Bank', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'SBIN',       exchange: 'NSE', description: 'State Bank of India', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'WIPRO',      exchange: 'NSE', description: 'Wipro', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'AXISBANK',   exchange: 'NSE', description: 'Axis Bank', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'BAJFINANCE', exchange: 'NSE', description: 'Bajaj Finance', options: [20, 15, 10, 5, 2, 1]),
  _SymbolLevConfig(symbol: 'HINDUNILVR', exchange: 'NSE', description: 'Hindustan Unilever', options: [20, 15, 10, 5, 2, 1]),
  // MCX Commodities — MCX Futures: max 500x
  _SymbolLevConfig(symbol: 'GOLD',       exchange: 'MCX', description: 'Gold 1kg', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'SILVER',     exchange: 'MCX', description: 'Silver 30kg', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'CRUDEOIL',   exchange: 'MCX', description: 'Crude Oil 100bbl', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'NATURALGAS', exchange: 'MCX', description: 'Natural Gas', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'COPPER',     exchange: 'MCX', description: 'Copper 1MT', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'ZINC',       exchange: 'MCX', description: 'Zinc 5MT', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'LEAD',       exchange: 'MCX', description: 'Lead 5MT', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'ALUMINIUM',  exchange: 'MCX', description: 'Aluminium 5MT', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'NICKEL',     exchange: 'MCX', description: 'Nickel 250kg', options: [500, 200, 100, 50, 20, 10, 5, 1]),
  _SymbolLevConfig(symbol: 'COTTON',     exchange: 'MCX', description: 'Cotton 25 bales', options: [500, 200, 100, 50, 20, 10, 5, 1]),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class LeverageControlScreen extends StatefulWidget {
  const LeverageControlScreen({super.key});

  @override
  State<LeverageControlScreen> createState() => _LeverageControlScreenState();
}

class _LeverageControlScreenState extends State<LeverageControlScreen> {
  String _query = '';
  String _exchangeFilter = 'All';

  // Working draft: symbol → leverage (null = platform default/max)
  final Map<String, int?> _draft = {};
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draft.isEmpty) _loadDraft();
  }

  void _loadDraft() {
    final admin = AdminScope.of(context);
    for (final cfg in _kSymbolLevConfigs) {
      final stored = admin.getStockLeverage(cfg.symbol);
      _draft[cfg.symbol] = stored?.toInt();
    }
  }

  List<_SymbolLevConfig> get _filtered {
    return _kSymbolLevConfigs.where((cfg) {
      if (_exchangeFilter != 'All' && cfg.exchange != _exchangeFilter) {
        return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return cfg.symbol.toLowerCase().contains(q) ||
          cfg.description.toLowerCase().contains(q);
    }).toList();
  }

  int _customCount() => _draft.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Leverage Control',
            subtitle: 'Set leverage multiplier per symbol. ${_customCount()} custom overrides active.',
            trailing: _dirty
                ? ElevatedButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(LucideIcons.save, size: 14),
                    label: const Text('Save All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // ── Filters ───────────────────────────────────────────────────────
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search symbol...',
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _filterChip('All'),
                    const SizedBox(width: 8),
                    _filterChip('NSE'),
                    const SizedBox(width: 8),
                    _filterChip('MCX'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          for (final cfg in _filtered) {
                            _draft[cfg.symbol] = null;
                          }
                          _dirty = true;
                        });
                      },
                      icon: const Icon(LucideIcons.rotateCcw, size: 13),
                      label: const Text('Reset Visible'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Info banner ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 14, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Leverage is applied platform-wide per symbol. '
                      '"Default" uses the platform maximum for that symbol. '
                      'Lower values reduce risk exposure for all users.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary.withOpacity(0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Symbol list ───────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No symbols match.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _SymbolLevRow(
                        cfg: filtered[i],
                        value: _draft[filtered[i].symbol],
                        onChanged: (v) => setState(() {
                          _draft[filtered[i].symbol] = v;
                          _dirty = true;
                        }),
                      ),
                    ),
                  ),
          ),

          // ── Sticky save bar ───────────────────────────────────────────────
          if (_dirty)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_customCount()} symbol${_customCount() == 1 ? '' : 's'} with custom leverage',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _loadDraft();
                      _dirty = false;
                    }),
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(LucideIcons.save, size: 14),
                    label: const Text('Save All Changes'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _saveAll() {
    final admin = AdminScope.of(context);
    // Build map of symbol → leverage (only non-null = custom)
    final toSave = <String, double>{};
    for (final entry in _draft.entries) {
      if (entry.value != null) {
        toSave[entry.key] = entry.value!.toDouble();
      }
    }
    admin.setStockLeverages(toSave);
    setState(() => _dirty = false);
    AppToast.success(context, 'Leverage settings saved for ${toSave.length} symbol(s).');
  }

  Widget _filterChip(String label) {
    final selected = _exchangeFilter == label;
    return AdminFilterChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _exchangeFilter = label),
    );
  }
}

// ── Symbol leverage row ───────────────────────────────────────────────────────

class _SymbolLevRow extends StatelessWidget {
  final _SymbolLevConfig cfg;
  final int? value;       // null = default (platform max)
  final ValueChanged<int?> onChanged;

  const _SymbolLevRow({
    required this.cfg,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = value != null;
    final exColor = cfg.exchange == 'MCX'
        ? const Color(0xFF7B1FA2)
        : AppColors.primary;
    final platformMax = cfg.options.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Symbol avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: exColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                cfg.symbol.substring(0, cfg.symbol.length.clamp(0, 2)),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: exColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Symbol info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cfg.symbol,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isCustom
                            ? AppColors.textPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: exColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: exColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        cfg.exchange,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: exColor),
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.warning.withOpacity(0.4)),
                        ),
                        child: const Text(
                          'CUSTOM',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  cfg.description,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Leverage dropdown
          SizedBox(
            width: 160,
            child: _LevDropdown(
              options: cfg.options,
              platformMax: platformMax,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Leverage dropdown ─────────────────────────────────────────────────────────

class _LevDropdown extends StatelessWidget {
  final List<int> options;
  final int platformMax;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _LevDropdown({
    required this.options,
    required this.platformMax,
    required this.value,
    required this.onChanged,
  });

  String _fmt(int v) {
    final pct = (100 / v).toStringAsFixed(2);
    return '${v}x ($pct%)';
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = value != null;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isCustom
            ? AppColors.warning.withOpacity(0.06)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCustom
              ? AppColors.warning.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown, size: 13),
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCustom ? FontWeight.w700 : FontWeight.normal,
            color: isCustom ? AppColors.warning : AppColors.textSecondary,
          ),
          items: [
            // Default = platform max
            DropdownMenuItem<int?>(
              value: null,
              child: Text(
                'Default (${_fmt(platformMax)})',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            // All allowed values
            ...options.map(
              (v) => DropdownMenuItem<int?>(
                value: v,
                child: Text(
                  _fmt(v),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
