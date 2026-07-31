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
import '../widgets/instrument_logo.dart';
import '../widgets/shared_widgets.dart';
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

  String _filter = 'all'; // 'all' | 'open' | 'closed' — labels shown as Today/Pending/Executed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onSegmentChanged);
    _isActiveTab = activeTabNotifier.value == 2;
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  void _onSegmentChanged() {
    // Rebuilds the header's segmented control when the TabBarView is swiped
    // directly, not just when the segmented control itself is tapped.
    if (!_tabController.indexIsChanging) setState(() {});
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header — title only, plus a small link to Basket so that
            // feature stays reachable without competing with the title.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Orders',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                  _TabLink(
                    label: _tabController.index == 0 ? 'Basket' : 'Order Book',
                    icon: _tabController.index == 0 ? LucideIcons.shoppingCart : LucideIcons.listChecks,
                    onTap: () => _tabController.animateTo(_tabController.index == 0 ? 1 : 0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
                  _OrderBookTab(
                    orders: _orders,
                    store: _store,
                    filter: _filter,
                    onFilterChanged: (v) => setState(() => _filter = v),
                  ),
                  const BasketOrdersScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A quiet text+icon link that switches between Order Book and Basket without
// occupying header space — Basket stays fully reachable, just not part of
// the primary header row.
class _TabLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _TabLink({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Order Book Tab — 4 clear sections + filter ──────────────────────────────

class _OrderBookTab extends StatelessWidget {
  final List<Order> orders;
  final TradingStore? store;
  final String filter;
  final ValueChanged<String> onFilterChanged;

  const _OrderBookTab({
    required this.orders,
    required this.store,
    required this.filter,
    required this.onFilterChanged,
  });

  static bool isOpen(Order o) =>
      o.status == OrderStatus.pending || o.status == OrderStatus.partiallyExecuted;

  @override
  Widget build(BuildContext context) {
    final sorted = orders.toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final displayed = switch (filter) {
      'open' => sorted.where(isOpen).toList(),
      'closed' => sorted.where((o) => !isOpen(o)).toList(),
      _ => sorted,
    };

    final pending = displayed.where((o) => o.status == OrderStatus.pending).toList();
    final executed = displayed.where((o) => o.status == OrderStatus.executed || o.status == OrderStatus.approved).toList();
    final cancelled = displayed.where((o) => o.status == OrderStatus.cancelled).toList();
    final rejected = displayed.where((o) => o.status == OrderStatus.rejected).toList();

    if (orders.isEmpty) {
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
      items.add(_SectionHeaderItem('Pending Orders', pending.length, AppColors.primary));
      items.addAll(pending.map((o) => _OrderItem(o, isPending: true)));
    }
    if (executed.isNotEmpty) {
      items.add(_SectionHeaderItem('Closed Trades', executed.length, AppColors.success));
      items.addAll(executed.map((o) => _OrderItem(o, isPending: false)));
    }
    if (cancelled.isNotEmpty) {
      items.add(_SectionHeaderItem('Cancelled', cancelled.length, AppColors.textTertiary));
      items.addAll(cancelled.map((o) => _OrderItem(o, isPending: false)));
    }
    if (rejected.isNotEmpty) {
      items.add(_SectionHeaderItem('Rejected', rejected.length, AppColors.danger));
      items.addAll(rejected.map((o) => _OrderItem(o, isPending: false)));
    }

    return Column(
      children: [
        // ── Filter chips ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(child: _FilterPill(label: 'Today', selected: filter == 'all', onTap: () => onFilterChanged('all'))),
              const SizedBox(width: 8),
              Expanded(child: _FilterPill(label: 'Pending', selected: filter == 'open', onTap: () => onFilterChanged('open'))),
              const SizedBox(width: 8),
              Expanded(child: _FilterPill(label: 'Executed', selected: filter == 'closed', onTap: () => onFilterChanged('closed'))),
            ],
          ),
        ),

        // ── Order list ────────────────────────────────────────────────────
        Expanded(
          child: displayed.isEmpty
              ? Center(
                  child: Text(
                    filter == 'open' ? 'No open orders' : 'No closed orders',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, TradingBottomNavBar.bottomInset(context) + 16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    if (item is _SectionHeaderItem) return _SectionHeader(item: item);
                    final oi = item as _OrderItem;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderCard(order: oi.order, isPendingSection: oi.isPending, store: store),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
  _SectionHeaderItem(this.title, this.count, this.color);
}

class _OrderItem extends _BookItem {
  final Order order;
  final bool isPending;
  _OrderItem(this.order, {required this.isPending});
}

// ─── Section Header ───────────────────────────────────────────────────────────
// A proper section header, not a floating badge: neutral typography carries
// the hierarchy, a small colored dot preserves the status color-coding, and
// a subtle divider separates sections — matches Dashboard's _SectionHeader.

class _SectionHeader extends StatelessWidget {
  final _SectionHeaderItem item;
  const _SectionHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                item.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Text(
                '(${item.count})',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }
}

// ─── Order Card — trading-ticket hierarchy ────────────────────────────────────

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
  bool _pressed = false;

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
                  color: AppColors.surfaceAlt,
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
    final isBuy = o.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;

    // Status-based accent color — same semantics as before, now on tokens.
    final Color barColor;
    switch (o.status) {
      case OrderStatus.pending:
        barColor = AppColors.primary;
      case OrderStatus.executed:
      case OrderStatus.approved:
        final pnl = o.pnl ?? 0;
        barColor = pnl > 0 ? AppColors.success : (pnl < 0 ? AppColors.danger : AppColors.warning);
      case OrderStatus.cancelled:
        barColor = AppColors.textTertiary;
      case OrderStatus.rejected:
        barColor = AppColors.danger;
      case OrderStatus.partiallyExecuted:
        barColor = AppColors.warning;
    }

    final isExecuted = o.status == OrderStatus.executed || o.status == OrderStatus.approved;
    final pnl = o.pnl;
    final hasPnl = pnl != null && pnl != 0;
    final execTime = o.executedAt ?? o.dateTime;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.floatingShadow,
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header row: accent · symbol+side (left) — time+P&L (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 4,
                    height: 36,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: InstrumentLogo(
                      symbol: o.symbol,
                      exchange: o.exchange ?? 'NSE',
                      size: 28,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                o.symbol,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SideChip(isBuy: isBuy, color: sideColor),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              '${o.executedQuantity ?? o.quantity} qty',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 8),
                            if (isExecuted && o.executedPrice != null && o.executedPrice != o.price) ...[
                              Text(
                                '₹${o.price.toStringAsFixed(2)}',
                                style: AppTheme.mono(fontSize: 12, color: AppColors.textTertiary)
                                    .copyWith(decoration: TextDecoration.lineThrough),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '₹${o.executedPrice!.toStringAsFixed(2)}',
                                style: AppTheme.mono(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                            ] else
                              Text(
                                '₹${(o.executedPrice ?? o.price).toStringAsFixed(2)}',
                                style: AppTheme.mono(
                                  fontSize: 13,
                                  fontWeight: isExecuted ? FontWeight.w700 : FontWeight.w500,
                                  color: isExecuted ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat(isExecuted ? 'HH:mm:ss' : 'HH:mm').format(execTime),
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                      ),
                      if (hasPnl) ...[
                        const SizedBox(height: 4),
                        PriceFlashWidget(
                          price: pnl,
                          child: Text(
                            '${(pnl >= 0) ? '+' : '−'}₹${pnl.abs().toStringAsFixed(2)}',
                            style: AppTheme.mono(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: pnl >= 0 ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Metadata chips — one quiet neutral style; only genuinely
              // risk-relevant info (Auto SQ / Trigger) gets an accent tint.
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (o.isAutoSquareOff) _MetaChip('Auto SQ', color: AppColors.warning),
                    _MetaChip(o.product.name.toUpperCase()),
                    if (o.variety != OrderVariety.market) _MetaChip(_varietyLabel(o.variety)),
                    if (o.triggerPrice != null && o.triggerPrice! > 0)
                      _MetaChip('Trg ₹${o.triggerPrice!.toStringAsFixed(2)}', color: AppColors.warning),
                    if (o.exchange?.isNotEmpty == true) _MetaChip(o.exchange!),
                  ],
                ),
              ),

              // ── Pending order actions
              if (widget.isPendingSection) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      _ActionBtn(label: 'Modify', icon: LucideIcons.pencil, color: AppColors.primary, onTap: _loading ? null : _modify),
                      const SizedBox(width: 8),
                      _ActionBtn(label: 'Cancel', icon: LucideIcons.x, color: AppColors.danger, onTap: _loading ? null : _cancel),
                      const SizedBox(width: 8),
                      _ActionBtn(label: '→ Market', icon: LucideIcons.zap, color: AppColors.warning, onTap: _loading ? null : _convertToMarket),
                      if (_loading) ...[
                        const Spacer(),
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _varietyLabel(OrderVariety v) => switch (v) {
    OrderVariety.sl => 'SL',
    OrderVariety.amo => 'AMO',
    OrderVariety.iceberg => 'ICEBERG',
    _ => 'LIMIT',
  };
}

class _SideChip extends StatelessWidget {
  final bool isBuy;
  final Color color;
  const _SideChip({required this.isBuy, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isBuy ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: color),
          const SizedBox(width: 2),
          Text(isBuy ? 'BUY' : 'SELL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  const _MetaChip(this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textSecondary;
    final bg = color != null ? color!.withOpacity(0.10) : AppColors.surfaceAlt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
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
    const color = AppColors.danger;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
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
