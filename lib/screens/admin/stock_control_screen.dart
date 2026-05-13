import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

// ── All tradable symbols — mirrors paper_trading_backend/src/config/symbols.js
// This is the single source of truth for what the admin can enable/disable.
// When you add a symbol to symbols.js, add it here too.
class _SymbolInfo {
  final String symbol;
  final String exchange;
  final String description;
  const _SymbolInfo(this.symbol, this.exchange, this.description);
}

const _kAllSymbols = [
  // NSE Equities
  _SymbolInfo('RELIANCE', 'NSE', 'Reliance Industries'),
  _SymbolInfo('TCS', 'NSE', 'Tata Consultancy Services'),
  _SymbolInfo('INFY', 'NSE', 'Infosys'),
  _SymbolInfo('HDFCBANK', 'NSE', 'HDFC Bank'),
  _SymbolInfo('ICICIBANK', 'NSE', 'ICICI Bank'),
  _SymbolInfo('SBIN', 'NSE', 'State Bank of India'),
  _SymbolInfo('WIPRO', 'NSE', 'Wipro'),
  _SymbolInfo('AXISBANK', 'NSE', 'Axis Bank'),
  _SymbolInfo('BAJFINANCE', 'NSE', 'Bajaj Finance'),
  _SymbolInfo('HINDUNILVR', 'NSE', 'Hindustan Unilever'),
  // MCX Commodities
  _SymbolInfo('GOLD', 'MCX', 'Gold 1kg'),
  _SymbolInfo('SILVER', 'MCX', 'Silver 30kg'),
  _SymbolInfo('CRUDEOIL', 'MCX', 'Crude Oil 100bbl'),
  _SymbolInfo('NATURALGAS', 'MCX', 'Natural Gas 1250mmBtu'),
  _SymbolInfo('COPPER', 'MCX', 'Copper 1MT'),
  _SymbolInfo('ZINC', 'MCX', 'Zinc 5MT'),
  _SymbolInfo('LEAD', 'MCX', 'Lead 5MT'),
  _SymbolInfo('ALUMINIUM', 'MCX', 'Aluminium 5MT'),
  _SymbolInfo('NICKEL', 'MCX', 'Nickel 250kg'),
  _SymbolInfo('COTTON', 'MCX', 'Cotton 25 bales'),
];

class StockControlScreen extends StatefulWidget {
  const StockControlScreen({super.key});
  @override
  State<StockControlScreen> createState() => _StockControlScreenState();
}

class _StockControlScreenState extends State<StockControlScreen> {
  String _query = '';
  String _exchangeFilter = 'All'; // All | NSE | MCX

  List<_SymbolInfo> get _filtered {
    return _kAllSymbols.where((s) {
      // Exchange filter
      if (_exchangeFilter != 'All' && s.exchange != _exchangeFilter) {
        return false;
      }
      // Text search — symbol or description
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return s.symbol.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final stocks = _filtered;

    final enabledCount = _kAllSymbols
        .where((s) => admin.isStockEnabled(s.symbol))
        .length;

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Stock Control',
            subtitle:
                '$enabledCount / ${_kAllSymbols.length} instruments enabled.',
          ),
          const SizedBox(height: 12),

          // ── Search + exchange filter ──────────────────────────────────────
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search symbol or name...',
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
                    // Bulk actions
                    TextButton.icon(
                      onPressed: () {
                        for (final s in _filtered) {
                          admin.enableStock(s.symbol);
                        }
                      },
                      icon: const Icon(LucideIcons.checkCircle, size: 14),
                      label: const Text('Enable All'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        for (final s in _filtered) {
                          admin.disableStock(s.symbol);
                        }
                      },
                      icon: const Icon(LucideIcons.xCircle, size: 14),
                      label: const Text('Disable All'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Symbol list ───────────────────────────────────────────────────
          Expanded(
            child: stocks.isEmpty
                ? const Center(
                    child: Text(
                      'No symbols match your search.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: stocks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = stocks[i];
                        final enabled = admin.isStockEnabled(s.symbol);
                        return _SymbolRow(
                          info: s,
                          enabled: enabled,
                          onToggle: (v) {
                            if (v) {
                              admin.enableStock(s.symbol);
                            } else {
                              admin.disableStock(s.symbol);
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
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

// ── Symbol row ────────────────────────────────────────────────────────────────

class _SymbolRow extends StatelessWidget {
  final _SymbolInfo info;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _SymbolRow({
    required this.info,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Exchange badge color
    final exColor = info.exchange == 'MCX'
        ? const Color(0xFF7B1FA2)
        : AppColors.primary;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: exColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            info.symbol.substring(0, info.symbol.length.clamp(0, 2)),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: exColor,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            info.symbol,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: exColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: exColor.withOpacity(0.3)),
            ),
            child: Text(
              info.exchange,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: exColor,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        info.description,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            label: enabled ? 'Enabled' : 'Disabled',
            color: enabled ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 8),
          Switch(
            value: enabled,
            onChanged: onToggle,
            activeColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}
