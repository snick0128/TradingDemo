import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../state/trading_scope.dart';
import '../common/app_scaffold.dart';

/// Orders page — reads from TradingStore (already subscribed in main.dart).
/// No extra Firestore streams opened here.
class AppOrdersPage extends StatelessWidget {
  const AppOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final orders = store.orders;

    return AppScaffold(
      title: 'My Orders',
      actions: [
        IconButton(
          onPressed: () => context.go('/app/dashboard'),
          icon: const Icon(Icons.dashboard_outlined),
        ),
      ],
      body: orders.isEmpty
          ? const Center(child: Text('No orders.'))
          : ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final o = orders[index];
                return ListTile(
                  title: Text(
                    '${o.symbol}  ${o.type.name.toUpperCase()} ${o.quantity}',
                  ),
                  subtitle: Text('Status: ${o.status.name.toUpperCase()}'),
                  trailing: o.executedPrice != null
                      ? Text('₹${o.executedPrice!.toStringAsFixed(2)}')
                      : null,
                );
              },
            ),
    );
  }
}
