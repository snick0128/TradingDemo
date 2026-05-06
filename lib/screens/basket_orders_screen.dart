import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/shared_widgets.dart';

class BasketOrdersScreen extends StatelessWidget {
  const BasketOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final baskets = store.basketOrders;

    return Scaffold(
      appBar: AppBar(title: const Text('Basket Orders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateBasketDialog(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Basket'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: baskets.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.shoppingCart,
                    size: 48,
                    color: AppColors.border,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No baskets yet',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: baskets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _BasketTile(basket: baskets[index]);
              },
            ),
    );
  }

  void _showCreateBasketDialog(BuildContext context) {
    AppDialog.input(
      context,
      title: 'New Basket',
      hint: 'Basket name',
      confirmLabel: 'Create',
      onSubmit: (name) {
        final store = TradingScope.of(context);
        store.createBasket(
          BasketOrder(
            id: 'BASKET-${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            entries: [],
            createdAt: DateTime.now(),
          ),
        );
      },
    );
  }
}

class _BasketTile extends StatelessWidget {
  final BasketOrder basket;
  const _BasketTile({required this.basket});

  @override
  Widget build(BuildContext context) {
    final isExecuted = basket.executedAt != null;

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      basket.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${basket.entries.length} order${basket.entries.length == 1 ? '' : 's'} • '
                      'Created ${DateFormat('dd MMM yyyy').format(basket.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isExecuted)
                StatusBadge(label: 'EXECUTED', color: AppColors.success)
              else
                StatusBadge(label: 'PENDING', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 12),

          // Entries list
          if (basket.entries.isNotEmpty) ...[
            ...basket.entries.map((e) => _EntryRow(entry: e)),
            const Divider(height: 16),
          ],

          // Total margin + actions
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Margin',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '₹${basket.totalMargin.toStringAsFixed(2)}',
                    style: AppTheme.tabular(
                      const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!isExecuted) ...[
                OutlinedButton.icon(
                  onPressed: () => _addEntry(context),
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: const Text('Add Order'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _executeBasket(context),
                  icon: const Icon(LucideIcons.zap, size: 14),
                  label: const Text('Execute'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _addEntry(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddEntryForm(basket: basket),
    );
  }

  void _executeBasket(BuildContext context) {
    final store = TradingScope.of(context);
    final result = store.executeBasket(basket.id);
    if (result.success) {
      AppDialog.success(
        context,
        title: 'Basket Executed',
        message: 'All orders were submitted successfully.\nReference: ${result.orderId ?? basket.id}',
        closeLabel: 'Done',
      );
      return;
    }

    AppToast.error(context, result.errorMessage ?? 'Execution failed');
  }
}

class _EntryRow extends StatelessWidget {
  final BasketOrderEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isBuy = entry.type == OrderType.buy;
    final color = isBuy ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Text(
              isBuy ? 'BUY' : 'SELL',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.symbol,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text(
            '${entry.quantity} qty',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.product.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${entry.estimatedMargin.toStringAsFixed(0)}',
            style: AppTheme.tabular(
              const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEntryForm extends StatefulWidget {
  final BasketOrder basket;
  const _AddEntryForm({required this.basket});

  @override
  State<_AddEntryForm> createState() => _AddEntryFormState();
}

class _AddEntryFormState extends State<_AddEntryForm> {
  final _symbolController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _priceController = TextEditingController();

  OrderType _type = OrderType.buy;
  OrderVariety _variety = OrderVariety.market;
  ProductType _product = ProductType.nrml;

  @override
  void dispose() {
    _symbolController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Order to Basket',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('SYMBOL'),
            const SizedBox(height: 6),
            TextField(
              controller: _symbolController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. INFY'),
            ),
            const SizedBox(height: 14),
            _label('ORDER TYPE'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _sideBtn('BUY', OrderType.buy, AppColors.success),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sideBtn('SELL', OrderType.sell, AppColors.danger),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _label('VARIETY'),
            const SizedBox(height: 6),
            DropdownButtonFormField<OrderVariety>(
              value: _variety,
              decoration: const InputDecoration(),
              items: OrderVariety.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                  .toList(),
              onChanged: (v) => setState(() => _variety = v!),
            ),
            const SizedBox(height: 14),
            _label('PRODUCT'),
            const SizedBox(height: 6),
            DropdownButtonFormField<ProductType>(
              value: _product,
              decoration: const InputDecoration(),
              items: ProductType.values
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (p) => setState(() => _product = p!),
            ),
            const SizedBox(height: 14),
            _label('QUANTITY'),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0'),
            ),
            const SizedBox(height: 14),
            _label('PRICE (optional)'),
            const SizedBox(height: 6),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0.00'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Add to Basket'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.5,
    ),
  );

  Widget _sideBtn(String label, OrderType side, Color color) {
    final selected = _type == side;
    return GestureDetector(
      onTap: () => setState(() => _type = side),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(color: selected ? color : AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _submit() {
    final symbol = _symbolController.text.trim().toUpperCase();
    final qty = int.tryParse(_qtyController.text) ?? 0;
    final price = double.tryParse(_priceController.text);

    if (symbol.isEmpty || qty <= 0) {
      AppToast.error(context, 'Symbol and quantity are required');
      return;
    }

    final store = TradingScope.of(context);
    final effectivePrice = price ?? 0;
    final margin = store.requiredMargin(
      qty,
      effectivePrice > 0 ? effectivePrice : 100,
      _product,
    );

    final entry = BasketOrderEntry(
      symbol: symbol,
      type: _type,
      quantity: qty,
      variety: _variety,
      price: price,
      product: _product,
      estimatedMargin: margin,
    );

    final updatedBasket = widget.basket.copyWith(
      entries: [...widget.basket.entries, entry],
    );
    store.saveBasket(updatedBasket);

    Navigator.pop(context);
    AppToast.success(context, 'Order added to basket');
  }
}
