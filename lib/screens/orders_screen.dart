import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/tab_notifier.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import 'basket_orders_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Order> _orders = const [];
  List<AppNotification> _notifications = const [];

  bool _isActiveTab = false;
  TradingStore? _store;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isActiveTab = activeTabNotifier.value == 2;
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.ordersVersion.removeListener(_onOrdersChanged);
      _store = store;
      store.ordersVersion.addListener(_onOrdersChanged);
      _syncFromStore(store);
    }
  }

  void _syncFromStore(TradingStore store) {
    _orders = store.orders.toList();
    _notifications = store.notifications.toList();
  }

  void _onOrdersChanged() {
    if (_store == null) return;
    _syncFromStore(_store!);
    if (_isActiveTab) setState(() {});
  }

  void _onTabVisibilityChanged() {
    final active = activeTabNotifier.value == 2;
    if (active == _isActiveTab) return;
    _isActiveTab = active;
    if (active) setState(() {});
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabVisibilityChanged);
    _store?.ordersVersion.removeListener(_onOrdersChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppNotification? sqOffNotif;
    for (final n in _notifications) {
      if (n.relatedAlertType == AlertType.autoSquareOffWarning && !n.isRead) {
        sqOffNotif = n;
        break;
      }
    }

    // Badge counts
    final pendingCount = _orders.where((o) => o.status == OrderStatus.pending).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1565C0),
          unselectedLabelColor: const Color(0xFF9E9E9E),
          indicatorColor: const Color(0xFF1565C0),
          indicatorWeight: 2,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Order Book'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Basket'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (sqOffNotif != null)
            _AutoSquareOffBanner(
              title: sqOffNotif.title,
              message: sqOffNotif.message,
              onDismiss: () => TradingScope.read(context).markNotificationRead(sqOffNotif!.id),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OrderBookTab(orders: _orders, store: _store),
                const BasketOrdersScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Order Book Tab — 4 clear sections + filter ──────────────────────────────

class _OrderBookTab extends StatefulWidget {
  final List<Order> orders;
  final TradingStore? store;

  const _OrderBookTab({required this.orders, required this.store});

  @override
  State<_OrderBookTab> createState() => _OrderBookTabState();
}

class _OrderBookTabState extends State<_OrderBookTab> {
  String _filter = 'all'; // 'all' | 'open' | 'closed'

  static bool _isOpen(Order o) =>
      o.status == OrderStatus.pending || o.status == OrderStatus.partiallyExecuted;

  @override
  Widget build(BuildContext context) {
    final sorted = widget.orders.toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final displayed = switch (_filter) {
      'open'   => sorted.where(_isOpen).toList(),
      'closed' => sorted.where((o) => !_isOpen(o)).toList(),
      _        => sorted,
    };

    final pending   = displayed.where((o) => o.status == OrderStatus.pending).toList();
    final executed  = displayed.where((o) => o.status == OrderStatus.executed || o.status == OrderStatus.approved).toList();
    final cancelled = displayed.where((o) => o.status == OrderStatus.cancelled).toList();
    final rejected  = displayed.where((o) => o.status == OrderStatus.rejected).toList();

    if (sorted.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.inbox, size: 56, color: AppColors.border),
            const SizedBox(height: 16),
            const Text(
              'No orders yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place your first trade to see orders here.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Build flat item list for the single scrollable list
    final items = <_BookItem>[];

    if (pending.isNotEmpty) {
      items.add(_SectionHeaderItem('Pending Orders', pending.length, const Color(0xFF1565C0), const Color(0xFFE3F2FD)));
      items.addAll(pending.map((o) => _OrderItem(o, isPending: true)));
    }
    if (executed.isNotEmpty) {
      items.add(_SectionHeaderItem('Closed Trades', executed.length, const Color(0xFF2E7D32), const Color(0xFFE8F5E9)));
      items.addAll(executed.map((o) => _OrderItem(o, isPending: false)));
    }
    if (cancelled.isNotEmpty) {
      items.add(_SectionHeaderItem('Cancelled', cancelled.length, const Color(0xFF757575), const Color(0xFFF5F5F5)));
      items.addAll(cancelled.map((o) => _OrderItem(o, isPending: false)));
    }
    if (rejected.isNotEmpty) {
      items.add(_SectionHeaderItem('Rejected', rejected.length, AppColors.danger, const Color(0xFFFFEBEE)));
      items.addAll(rejected.map((o) => _OrderItem(o, isPending: false)));
    }

    final openCount   = sorted.where(_isOpen).length;
    final closedCount = sorted.length - openCount;

    return Column(
      children: [
        // ── Filter chips ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _filterChip('All',    'all',    sorted.length),
              const SizedBox(width: 8),
              _filterChip('Open',   'open',   openCount),
              const SizedBox(width: 8),
              _filterChip('Closed', 'closed', closedCount),
            ],
          ),
        ),

        // ── Order list ────────────────────────────────────────────────────────
        Expanded(
          child: displayed.isEmpty
              ? Center(
                  child: Text(
                    _filter == 'open' ? 'No open orders' : 'No closed orders',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, TradingBottomNavBar.bottomInset(context) + 16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    if (item is _SectionHeaderItem) return _SectionHeader(item: item);
                    final oi = item as _OrderItem;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _OrderCard(order: oi.order, isPendingSection: oi.isPending, store: widget.store),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value, int count) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count > 0 ? '$label ($count)' : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Section item types ───────────────────────────────────────────────────────

sealed class _BookItem {}

class _SectionHeaderItem extends _BookItem {
  final String title;
  final int count;
  final Color color;
  final Color bg;
  _SectionHeaderItem(this.title, this.count, this.color, this.bg);
}

class _OrderItem extends _BookItem {
  final Order order;
  final bool isPending;
  _OrderItem(this.order, {required this.isPending});
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final _SectionHeaderItem item;
  const _SectionHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: item.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: item.color.withValues(alpha: 0.3)),
            ),
            child: Text(
              item.title,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: item.color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.count}',
            style: TextStyle(fontSize: 12, color: item.color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─── Order Card — compact, clear visual hierarchy ─────────────────────────────

class _OrderCard extends StatefulWidget {
  final Order order;
  final bool isPendingSection;
  final TradingStore? store;

  const _OrderCard({required this.order, required this.isPendingSection, required this.store});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _loading = false;

  Order get o => widget.order;

  Future<void> _cancel() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      if (appScope != null) {
        final userId = appScope.notifier?.user?.uid ?? '';
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        await api.cancelPendingOrder(userId: userId, orderId: o.id);
        if (mounted) AppToast.success(context, 'Order cancelled');
      } else {
        TradingScope.read(context).cancelOrder(o.id);
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _modify() async {
    if (_loading) return;
    // Stop-loss pending orders must stay SL when modified — resubmitting as a
    // plain LIMIT would silently drop the trigger and change the order's risk
    // profile without the user asking for that.
    final isStop = o.variety == OrderVariety.sl;
    final seed = isStop ? (o.triggerPrice ?? o.price) : o.price;
    final controller = TextEditingController(text: seed.toStringAsFixed(2));
    final newPrice = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Modify ${o.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${o.type == OrderType.buy ? 'BUY' : 'SELL'} ${o.quantity} qty — new ${isStop ? 'trigger' : 'limit'} price:',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: isStop ? 'New trigger price (₹)' : 'New limit price (₹)',
                prefixText: '₹ ',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null && val > 0) Navigator.pop(context, val);
            },
            child: const Text('Modify'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newPrice == null || !mounted || newPrice == seed) return;

    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      final userId = appScope?.notifier?.user?.uid;
      if (userId == null) throw Exception('Session expired.');

      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      await api.cancelPendingOrder(userId: userId, orderId: o.id);
      if (!mounted) return;

      await api.placeOrder(
        userId: userId,
        symbol: o.symbol,
        qty: o.quantity,
        type: o.type == OrderType.buy ? 'BUY' : 'SELL',
        productType: o.product.name.toUpperCase(),
        exchange: o.exchange ?? 'NSE',
        variety: isStop ? 'SL_MARKET' : 'LIMIT',
        limitPrice: isStop ? null : newPrice,
        triggerPrice: isStop ? newPrice : null,
        clientRequestId: '${userId}_${DateTime.now().microsecondsSinceEpoch}_mod',
      );
      if (mounted) AppToast.success(context, 'Modified to ₹${newPrice.toStringAsFixed(2)}');
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _convertToMarket() async {
    if (_loading) return;
    final ltp = widget.store?.lastValidLtp(o.symbol) ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Market'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${o.type == OrderType.buy ? 'BUY' : 'SELL'} ${o.quantity} × ${o.symbol}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (ltp > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Current Price: ₹${ltp.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 10),
            const Text(
              'Will execute immediately at best available market price.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Convert')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      final userId = appScope?.notifier?.user?.uid;
      if (userId == null) throw Exception('Session expired.');

      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      await api.cancelPendingOrder(userId: userId, orderId: o.id);
      if (!mounted) return;

      await api.placeOrder(
        userId: userId,
        symbol: o.symbol,
        qty: o.quantity,
        type: o.type == OrderType.buy ? 'BUY' : 'SELL',
        productType: o.product.name.toUpperCase(),
        exchange: o.exchange ?? 'NSE',
        variety: 'MARKET',
        lockedLtp: ltp > 0 ? ltp : null,
        clientRequestId: '${userId}_${DateTime.now().microsecondsSinceEpoch}_mkt',
      );
      if (mounted) AppToast.success(context, 'Converted to market order');
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBuy    = o.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final sideBg    = isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

    // Status-based left bar color
    final Color barColor;
    switch (o.status) {
      case OrderStatus.pending:
        barColor = const Color(0xFF1565C0);
      case OrderStatus.executed:
      case OrderStatus.approved:
        final pnl = o.pnl ?? 0;
        barColor = pnl > 0 ? AppColors.success : (pnl < 0 ? AppColors.danger : const Color(0xFFFF9800));
      case OrderStatus.cancelled:
        barColor = const Color(0xFF9E9E9E);
      case OrderStatus.rejected:
        barColor = AppColors.danger;
      case OrderStatus.partiallyExecuted:
        barColor = const Color(0xFFFF9800);
    }

    final isExecuted = o.status == OrderStatus.executed || o.status == OrderStatus.approved;
    final pnl = o.pnl;
    final hasPnl = pnl != null && pnl != 0;
    final execTime = o.executedAt ?? o.dateTime;

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: side badge + symbol + time/status
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: sideBg, borderRadius: BorderRadius.circular(5)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isBuy ? Icons.arrow_upward : Icons.arrow_downward, size: 9, color: sideColor),
                              const SizedBox(width: 2),
                              Text(isBuy ? 'BUY' : 'SELL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: sideColor)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            o.symbol,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (o.isAutoSquareOff)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _chip('Auto SQ', const Color(0xFFFFF3E0), const Color(0xFFE65100)),
                          ),
                        Text(
                          DateFormat(isExecuted ? 'HH:mm:ss' : 'HH:mm').format(execTime),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Row 2: qty + price + product
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${o.executedQuantity ?? o.quantity} qty',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              Text('·', style: TextStyle(color: AppColors.border)),
                              if (isExecuted && o.executedPrice != null && o.executedPrice != o.price) ...[
                                Text(
                                  '₹${o.price.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, decoration: TextDecoration.lineThrough),
                                ),
                                Text(
                                  '₹${o.executedPrice!.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                ),
                              ] else
                                Text(
                                  '₹${(o.executedPrice ?? o.price).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isExecuted ? FontWeight.w500 : FontWeight.w400,
                                    color: isExecuted ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              Text('·', style: TextStyle(color: AppColors.border)),
                              _chip(o.product.name.toUpperCase(), const Color(0xFFF3F3F3), AppColors.textSecondary),
                              if (o.variety != OrderVariety.market)
                                _chip(_varietyLabel(o.variety), const Color(0xFFF3E5F5), const Color(0xFF6A1B9A)),
                              if (o.triggerPrice != null && o.triggerPrice! > 0)
                                _chip(
                                  'Trg ₹${o.triggerPrice!.toStringAsFixed(2)}',
                                  const Color(0xFFFFF3E0),
                                  const Color(0xFFE65100),
                                ),
                              if (o.exchange?.isNotEmpty == true)
                                _chip(o.exchange!, const Color(0xFFF3F3F3), AppColors.textSecondary),
                            ],
                          ),
                        ),
                        // P&L on the right
                        if (hasPnl) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${(pnl >= 0) ? '+' : '−'}₹${pnl.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: pnl >= 0 ? AppColors.success : AppColors.danger,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Row 3: Pending order actions
                    if (widget.isPendingSection) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _actionBtn('Modify', LucideIcons.pencil, const Color(0xFF1565C0), _loading ? null : _modify),
                          const SizedBox(width: 6),
                          _actionBtn('Cancel', LucideIcons.x, AppColors.danger, _loading ? null : _cancel),
                          const SizedBox(width: 6),
                          _actionBtn('→ Market', LucideIcons.zap, const Color(0xFF6A1B9A), _loading ? null : _convertToMarket),
                          if (_loading) ...[
                            const Spacer(),
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
  );

  static String _varietyLabel(OrderVariety v) => switch (v) {
    OrderVariety.sl => 'SL',
    OrderVariety.amo => 'AMO',
    OrderVariety.iceberg => 'ICEBERG',
    _ => 'LIMIT',
  };

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Auto Square-Off Banner ───────────────────────────────────────────────────

class _AutoSquareOffBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onDismiss;
  const _AutoSquareOffBanner({required this.title, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB71C1C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: const Border(bottom: BorderSide(color: Color(0x33B71C1C))),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
                Text(message, style: const TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 16, color: color),
          ),
        ],
      ),
    );
  }
}
