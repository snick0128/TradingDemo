import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../state/trading_scope.dart';
import '../common/app_scaffold.dart';

/// Portfolio page — reads from TradingStore (already subscribed in main.dart).
/// No extra Firestore streams opened here.
class AppPortfolioPage extends StatelessWidget {
  const AppPortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final holdings = store.holdings;

    return AppScaffold(
      title: 'My Portfolio',
      actions: [
        IconButton(
          onPressed: () => context.go('/app/dashboard'),
          icon: const Icon(Icons.dashboard_outlined),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Holdings (Realtime)'),
          const SizedBox(height: 8),
          Expanded(
            child: holdings.isEmpty
                ? const Center(child: Text('No holdings yet.'))
                : ListView.separated(
                    itemCount: holdings.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final h = holdings[index];
                      return ListTile(
                        title: Text(h.symbol),
                        subtitle: Text(
                          'Qty: ${h.quantity}  Avg: ₹${h.avgPrice.toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          '₹${h.currentPrice.toStringAsFixed(2)}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
