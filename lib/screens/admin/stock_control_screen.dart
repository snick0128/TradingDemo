import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../state/admin_scope.dart';
import '../../state/trading_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class StockControlScreen extends StatefulWidget {
  const StockControlScreen({super.key});
  @override
  State<StockControlScreen> createState() => _StockControlScreenState();
}

class _StockControlScreenState extends State<StockControlScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final admin = AdminScope.of(context);
    final stocks = store.watchlist.where((s) {
      if (_query.isEmpty) return true;
      return s.symbol.toLowerCase().contains(_query.toLowerCase()) ||
          s.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title: 'Stock Control',
            subtitle: 'Enable or disable instruments for trading.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search symbol or name...',
                prefixIcon: Icon(LucideIcons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AdminPanel(
              child: ListView.separated(
                itemCount: stocks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = stocks[i];
                  final enabled = admin.isStockEnabled(s.symbol);
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          s.symbol.substring(0, s.symbol.length.clamp(0, 2)),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      s.symbol,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      s.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
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
                          onChanged: (v) {
                            if (v) {
                              admin.enableStock(s.symbol);
                            } else {
                              admin.disableStock(s.symbol);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${s.symbol} ${v ? 'enabled' : 'disabled'}',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          activeColor: AppColors.success,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
