import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class GttOrdersScreen extends StatelessWidget {
  const GttOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final orders = store.gttOrders;

    return Stack(
      children: [
        orders.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.clock, size: 48, color: AppColors.border),
                    SizedBox(height: 16),
                    Text(
                      'No GTT orders',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return _GttOrderTile(
                    order: order,
                    onEdit: () => _showGttForm(context, existing: order),
                    onCancel: () => _cancelGttOrder(context, order.id),
                  );
                },
              ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showGttForm(context),
            icon: const Icon(LucideIcons.plus),
            label: const Text('New GTT'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _cancelGttOrder(BuildContext context, String id) async {
    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope != null) {
      try {
        await appScope.tradingService.cancelGttOrder(id);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel GTT: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    TradingScope.of(context).cancelGTTOrder(id);
  }

  void _showGttForm(BuildContext context, {GTTOrder? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _GttOrderForm(existing: existing),
    );
  }
}

class _GttOrderTile extends StatelessWidget {
  final GTTOrder order;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  const _GttOrderTile({
    required this.order,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = order.orderType == OrderType.buy;
    final typeColor = isBuy ? AppColors.success : AppColors.danger;
    final statusColor = order.isActive ? AppColors.warning : AppColors.success;
    final statusLabel = order.isActive ? 'ACTIVE' : 'TRIGGERED';

    return CustomCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        order.symbol,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      label: order.type.name.toUpperCase(),
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    StatusBadge(label: statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _infoChip(isBuy ? 'BUY' : 'SELL', typeColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Qty: ${order.quantity}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Trigger: ₹${order.triggerPrice.toStringAsFixed(2)}',
                        style: AppTheme.tabular(
                          const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (order.secondTriggerPrice != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '2nd: ₹${order.secondTriggerPrice!.toStringAsFixed(2)}',
                          style: AppTheme.tabular(
                            const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd MMM yyyy').format(order.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              LucideIcons.pencil,
              size: 16,
              color: AppColors.primary,
            ),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.danger,
            ),
            onPressed: onCancel,
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
    ),
  );
}

class _GttOrderForm extends StatefulWidget {
  final GTTOrder? existing;
  const _GttOrderForm({this.existing});

  @override
  State<_GttOrderForm> createState() => _GttOrderFormState();
}

class _GttOrderFormState extends State<_GttOrderForm> {
  final _symbolController = TextEditingController();
  final _triggerController = TextEditingController();
  final _secondTriggerController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _limitPriceController = TextEditingController();

  GTTType _gttType = GTTType.single;
  OrderType _orderType = OrderType.buy;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _symbolController.text = e.symbol;
      _triggerController.text = e.triggerPrice.toStringAsFixed(2);
      _secondTriggerController.text =
          e.secondTriggerPrice?.toStringAsFixed(2) ?? '';
      _qtyController.text = e.quantity.toString();
      _limitPriceController.text = e.limitPrice?.toStringAsFixed(2) ?? '';
      _gttType = e.type;
      _orderType = e.orderType;
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _triggerController.dispose();
    _secondTriggerController.dispose();
    _qtyController.dispose();
    _limitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
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
                Text(
                  isEdit ? 'Edit GTT Order' : 'New GTT Order',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
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
              decoration: const InputDecoration(hintText: 'e.g. RELIANCE'),
            ),
            const SizedBox(height: 14),
            _label('GTT TYPE'),
            const SizedBox(height: 6),
            SegmentedButton<GTTType>(
              segments: const [
                ButtonSegment(value: GTTType.single, label: Text('Single')),
                ButtonSegment(value: GTTType.oco, label: Text('OCO')),
              ],
              selected: {_gttType},
              onSelectionChanged: (s) => setState(() => _gttType = s.first),
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
            _label('TRIGGER PRICE'),
            const SizedBox(height: 6),
            TextField(
              controller: _triggerController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0.00'),
            ),
            if (_gttType == GTTType.oco) ...[
              const SizedBox(height: 14),
              _label('SECOND TRIGGER PRICE'),
              const SizedBox(height: 6),
              TextField(
                controller: _secondTriggerController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '0.00'),
              ),
            ],
            const SizedBox(height: 14),
            _label('QUANTITY'),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0'),
            ),
            const SizedBox(height: 14),
            _label('LIMIT PRICE (optional)'),
            const SizedBox(height: 6),
            TextField(
              controller: _limitPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0.00'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(isEdit ? 'Update GTT Order' : 'Create GTT Order'),
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
    final selected = _orderType == side;
    return GestureDetector(
      onTap: () => setState(() => _orderType = side),
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

  Future<void> _submit() async {
    final symbol = _symbolController.text.trim().toUpperCase();
    final trigger = double.tryParse(_triggerController.text) ?? 0;
    final secondTrigger = double.tryParse(_secondTriggerController.text);
    final qty = int.tryParse(_qtyController.text) ?? 0;
    final limitPrice = double.tryParse(_limitPriceController.text);

    if (symbol.isEmpty || trigger <= 0 || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope != null) {
      final sessionUser = appScope.notifier?.user;
      if (sessionUser == null) return;

      try {
        await appScope.tradingService.placeGttOrder(
          userId: sessionUser.uid,
          symbol: symbol,
          gttType: _gttType.name.toUpperCase(),
          triggerPrice: trigger,
          secondTriggerPrice: _gttType == GTTType.oco ? secondTrigger : null,
          side: _orderType.name.toUpperCase(),
          qty: qty,
          limitPrice: limitPrice,
        );
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GTT order created'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create GTT: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    final store = TradingScope.of(context);
    final now = DateTime.now();

    if (widget.existing != null) {
      store.editGTTOrder(
        widget.existing!.id,
        widget.existing!.copyWith(
          symbol: symbol,
          type: _gttType,
          triggerPrice: trigger,
          secondTriggerPrice: _gttType == GTTType.oco ? secondTrigger : null,
          orderType: _orderType,
          quantity: qty,
          limitPrice: limitPrice,
        ),
      );
    } else {
      store.createGTTOrder(
        GTTOrder(
          id: 'GTT-${now.millisecondsSinceEpoch}',
          symbol: symbol,
          type: _gttType,
          triggerPrice: trigger,
          secondTriggerPrice: _gttType == GTTType.oco ? secondTrigger : null,
          orderType: _orderType,
          quantity: qty,
          limitPrice: limitPrice,
          createdAt: now,
        ),
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.existing != null ? 'GTT order updated' : 'GTT order created',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
