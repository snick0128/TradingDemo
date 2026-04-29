import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_scope.dart';
import '../../state/trading_scope.dart';
import '../common/app_scaffold.dart';

/// Customer dashboard — reads orders from TradingStore (already subscribed
/// in main.dart). No extra Firestore streams opened here.
class AppDashboardPage extends StatefulWidget {
  const AppDashboardPage({super.key});

  @override
  State<AppDashboardPage> createState() => _AppDashboardPageState();
}

class _AppDashboardPageState extends State<AppDashboardPage> {
  final _stock = TextEditingController(text: 'RELIANCE');
  final _qty = TextEditingController(text: '1');
  String _type = 'BUY';
  bool _placing = false;

  @override
  void dispose() {
    _stock.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final scope = AppScope.of(context);
    final user = scope.notifier!.user;
    if (user == null) return;
    setState(() => _placing = true);
    try {
      final clientOrderId = const Uuid().v4();
      await scope.tradingService.placeOrder(
        userId: user.uid,
        stock: _stock.text.trim(),
        qty: int.tryParse(_qty.text.trim()) ?? 0,
        type: _type,
        clientOrderId: clientOrderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Order failed: $e')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.notifier!;
    final user = session.user!;
    // Read from TradingStore — already subscribed in main.dart, no new stream
    final store = TradingScope.of(context);
    final orders = store.orders;

    return AppScaffold(
      title: 'Customer Dashboard',
      actions: [
        IconButton(
          onPressed: () => context.go('/app/orders'),
          icon: const Icon(Icons.list_alt_outlined),
        ),
        IconButton(
          onPressed: () => context.go('/app/portfolio'),
          icon: const Icon(Icons.pie_chart_outline),
        ),
        IconButton(
          onPressed: () async {
            await scope.authService.logout();
            session.setUser(null);
            if (!mounted) return;
            context.go('/app/login');
          },
          icon: const Icon(Icons.logout),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome ${user.name} (${user.role})'),
          const SizedBox(height: 8),
          Text('Balance: ₹${user.balance.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          const Text('Place Order'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stock,
                  decoration: const InputDecoration(labelText: 'Stock'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                  DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'BUY'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _placing ? null : _placeOrder,
                child: _placing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Live Orders (Realtime)'),
          const SizedBox(height: 8),
          Expanded(
            child: orders.isEmpty
                ? const Center(child: Text('No orders yet.'))
                : ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final o = orders[index];
                      return ListTile(
                        title: Text(
                            '${o.symbol} • ${o.type.name.toUpperCase()} ${o.quantity}'),
                        subtitle: Text('Status: ${o.status.name.toUpperCase()}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
