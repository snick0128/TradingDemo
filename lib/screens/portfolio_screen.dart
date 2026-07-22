import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../widgets/backend_error_widget.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import 'positions_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool _backendError = false;
  String _backendErrorMessage = '';
  double _totalValue = 0;

  bool _isActiveTab = false;
  TradingStore? _store;

  @override
  void initState() {
    super.initState();
    _isActiveTab = activeTabNotifier.value == 3;
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.positionsVersion.removeListener(_onPositionsChanged);
      _store = store;
      store.positionsVersion.addListener(_onPositionsChanged);
      _syncFromStore(store);
    }
  }

  void _syncFromStore(TradingStore store) {
    _backendError = store.backendError;
    _backendErrorMessage = store.backendErrorMessage;
    _totalValue =
        store.holdings.fold(0.0, (s, h) => s + h.currentValue) +
        store.positions.fold(0.0, (s, p) => s + p.currentValue);
  }

  void _onPositionsChanged() {
    if (_store == null) return;
    _syncFromStore(_store!);
    if (_isActiveTab) setState(() {});
  }

  void _onTabVisibilityChanged() {
    final active = activeTabNotifier.value == 3;
    if (active == _isActiveTab) return;
    _isActiveTab = active;
    if (active) setState(() {});
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabVisibilityChanged);
    _store?.positionsVersion.removeListener(_onPositionsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Portfolio')),
        body: BackendErrorWidget(
          message: _backendErrorMessage,
          onRetry: () => TradingScope.read(context).connectLiveBackend(),
        ),
      );
    }

    // Count pending orders for the tab badge
    final pendingCount = (_store?.orders ?? [])
        .where((o) => o.status == OrderStatus.pending)
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Portfolio'),
              Text(
                '₹${_fmtValue(_totalValue)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          bottom: TabBar(
            isScrollable: false,
            tabs: [
              const Tab(text: 'Positions'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pending'),
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
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PositionsScreen(showAppBar: false),
            _PendingOrdersTab(),
          ],
        ),
      ),
    );
  }

  String _fmtValue(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    return v.toStringAsFixed(0);
  }
}

// ─── Pending Orders Tab ───────────────────────────────────────────────────────

class _PendingOrdersTab extends StatefulWidget {
  const _PendingOrdersTab();

  @override
  State<_PendingOrdersTab> createState() => _PendingOrdersTabState();
}

class _PendingOrdersTabState extends State<_PendingOrdersTab> {
  TradingStore? _store;
  List<Order> _pending = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.ordersVersion.removeListener(_onOrdersChanged);
      _store = store;
      store.ordersVersion.addListener(_onOrdersChanged);
      _sync(store);
    }
  }

  void _sync(TradingStore store) {
    _pending = store.orders
        .where((o) => o.status == OrderStatus.pending)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  void _onOrdersChanged() {
    if (_store == null || !mounted) return;
    _sync(_store!);
    setState(() {});
  }

  @override
  void dispose() {
    _store?.ordersVersion.removeListener(_onOrdersChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.clock, size: 48, color: AppColors.border),
            const SizedBox(height: 16),
            const Text(
              'No pending orders',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Limit orders waiting for execution\nwill appear here.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 16, 16, TradingBottomNavBar.bottomInset(context) + 16),
      itemCount: _pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _PendingCard(
        order: _pending[i],
        store: _store!,
        onRefresh: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

// ─── Pending Order Card ───────────────────────────────────────────────────────

class _PendingCard extends StatefulWidget {
  final Order order;
  final TradingStore store;
  final VoidCallback onRefresh;

  const _PendingCard({required this.order, required this.store, required this.onRefresh});

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  bool _loading = false;

  Order get o => widget.order;
  TradingStore get store => widget.store;

  Future<void> _cancel() async {
    if (_loading) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text('Cancel ${o.type == OrderType.buy ? 'BUY' : 'SELL'} ${o.quantity} × ${o.symbol} @ ₹${o.price.toStringAsFixed(2)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      if (appScope != null) {
        final userId = appScope.notifier?.user?.uid ?? '';
        final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
        await api.cancelPendingOrder(userId: userId, orderId: o.id);
      } else {
        TradingScope.read(context).cancelOrder(o.id);
      }
      if (mounted) AppToast.success(context, 'Order cancelled');
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _modify() async {
    if (_loading) return;
    final controller = TextEditingController(text: o.price.toStringAsFixed(2));
    final newPrice = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Modify ${o.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${o.type == OrderType.buy ? 'BUY' : 'SELL'} ${o.quantity} qty — change limit price:',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'New limit price (₹)',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
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
    if (newPrice == null || !mounted) return;
    if (newPrice == o.price) return;

    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      final userId = appScope?.notifier?.user?.uid;
      if (userId == null) throw Exception('Session expired — please log in again.');

      print('[MODIFY_ORDER_START] orderId=${o.id} symbol=${o.symbol} oldPrice=${o.price} newPrice=$newPrice userId=$userId');

      // Cancel then re-place at new limit price
      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      print('[MODIFY_ORDER_CANCEL] Calling backend cancelPendingOrder for orderId=${o.id}');
      await api.cancelPendingOrder(userId: userId, orderId: o.id);
      print('[MODIFY_ORDER_CANCEL] cancelPendingOrder succeeded for orderId=${o.id}');
      if (!mounted) return;

      print('[MODIFY_ORDER_CREATE] Calling backend placeOrder LIMIT symbol=${o.symbol} qty=${o.quantity} limitPrice=$newPrice');
      await api.placeOrder(
        userId: userId,
        symbol: o.symbol,
        qty: o.quantity,
        type: o.type == OrderType.buy ? 'BUY' : 'SELL',
        productType: o.product.name.toUpperCase(),
        exchange: o.exchange ?? 'NSE',
        variety: 'LIMIT',
        limitPrice: newPrice,
        clientRequestId: '${userId}_${DateTime.now().microsecondsSinceEpoch}_mod',
      );
      print('[MODIFY_ORDER_SUCCESS] New LIMIT order placed at ₹$newPrice');
      if (mounted) AppToast.success(context, 'Order modified to ₹${newPrice.toStringAsFixed(2)}');
    } catch (e, stack) {
      print('[MODIFY_ORDER_ERROR] type=${e.runtimeType} message=$e');
      print('[MODIFY_ORDER_ERROR] stack=$stack');
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _convertToMarket() async {
    if (_loading) return;
    final ltp = store.lastValidLtp(o.symbol);
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
              'This order will execute immediately at best available market price.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      final userId = appScope?.notifier?.user?.uid;
      if (userId == null) throw Exception('Session expired — please log in again.');

      print('[MODIFY_ORDER_START] convertToMarket orderId=${o.id} symbol=${o.symbol} ltp=$ltp userId=$userId');
      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      // Cancel limit order then place market order
      print('[MODIFY_ORDER_CANCEL] Calling backend cancelPendingOrder for orderId=${o.id}');
      await api.cancelPendingOrder(userId: userId, orderId: o.id);
      print('[MODIFY_ORDER_CANCEL] cancelPendingOrder succeeded for orderId=${o.id}');
      if (!mounted) return;

      print('[MODIFY_ORDER_CREATE] Calling backend placeOrder MARKET symbol=${o.symbol} qty=${o.quantity} ltp=$ltp');
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
      print('[MODIFY_ORDER_SUCCESS] Market order placed for ${o.symbol}');
      if (mounted) AppToast.success(context, '${o.symbol} converted to market order');
    } catch (e, stack) {
      print('[MODIFY_ORDER_ERROR] type=${e.runtimeType} message=$e');
      print('[MODIFY_ORDER_ERROR] stack=$stack');
      if (mounted) AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = o.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final sideBg    = isBuy ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBDEFB)), // blue tint for pending
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 0),
            child: Row(
              children: [
                // Side badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: sideBg, borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isBuy ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: sideColor),
                      const SizedBox(width: 3),
                      Text(isBuy ? 'BUY' : 'SELL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sideColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    o.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Product + exchange chips
                _chip(o.product.name.toUpperCase(), const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
                const SizedBox(width: 4),
                if (o.exchange?.isNotEmpty == true)
                  _chip(o.exchange!, const Color(0xFFF3E5F5), const Color(0xFF6A1B9A)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('HH:mm').format(o.dateTime),
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // ── Qty + Limit price + Live price ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: [
                Text(
                  '${o.quantity} qty  ·  Limit @ ₹${o.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                // Live LTP
                ValueListenableBuilder<double>(
                  valueListenable: store.ltpNotifier(o.symbol),
                  builder: (_, ltp, __) {
                    final effectiveLtp = ltp > 0 ? ltp : store.lastValidLtp(o.symbol);
                    if (effectiveLtp <= 0) return const SizedBox.shrink();
                    final condMet = isBuy ? effectiveLtp <= o.price : effectiveLtp >= o.price;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LTP ₹${effectiveLtp.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: condMet ? AppColors.success : AppColors.textSecondary,
                            fontWeight: condMet ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: condMet ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            condMet ? 'Ready To Execute' : 'Waiting For Trigger',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: condMet ? AppColors.success : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Margin reserved (BUY orders only) ───────────────────────────────
          if (isBuy && (o.marginUsed ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 11, color: Color(0xFF1565C0)),
                  const SizedBox(width: 4),
                  Text(
                    'Margin Reserved ₹${o.marginUsed!.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                  ),
                ],
              ),
            ),

          // ── Action buttons ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              children: [
                _actionBtn('Modify', LucideIcons.pencil, const Color(0xFF1565C0), _loading ? null : _modify),
                const SizedBox(width: 8),
                _actionBtn('Cancel', LucideIcons.x, AppColors.danger, _loading ? null : _cancel),
                const SizedBox(width: 8),
                _actionBtn('→ Market', LucideIcons.zap, const Color(0xFF6A1B9A), _loading ? null : _convertToMarket),
                if (_loading) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
  );

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}
