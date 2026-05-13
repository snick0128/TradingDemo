import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/backend_error_widget.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

// ─── Sort options ─────────────────────────────────────────────────────────────

enum WatchlistSort { symbol, price, change, volume }

// ─── Pure logic helper (also used by property test) ──────────────────────────

Color priceChangeColor(double changePercentage) {
  return changePercentage >= 0
      ? const Color(0xFF00C853)
      : const Color(0xFFD50000);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class MarketWatchScreen extends StatefulWidget {
  const MarketWatchScreen({super.key});

  @override
  State<MarketWatchScreen> createState() => _MarketWatchScreenState();
}

class _MarketWatchScreenState extends State<MarketWatchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late List<Watchlist> _watchlists;
  bool _initialized = false;

  bool _compactView = false;
  WatchlistSort _sort = WatchlistSort.symbol;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only initialize watchlists once — never rebuild on subsequent dependency changes
    if (!_initialized) {
      _initialized = true;
      _initWatchlists();
    }
  }

  void _initWatchlists() {
    final store = TradingScope.of(context);
    final allSymbols = store.watchlist.map((s) => s.symbol).toList();
    final nifty50Symbols = allSymbols.take(4).toList();

    _watchlists = [
      Watchlist(
        id: 'wl-1',
        name: 'My Watchlist',
        symbols: allSymbols,
        order: 0,
      ),
      Watchlist(
        id: 'wl-2',
        name: 'Nifty 50',
        symbols: nifty50Symbols,
        order: 1,
      ),
    ];

    _rebuildTabController();
  }

  void _rebuildTabController() {
    final old = _tabController;
    _tabController = TabController(length: _watchlists.length, vsync: this);
    old.dispose();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  List<Stock> _stocksForWatchlist(int index, List<Stock> allStocks) {
    final wl = _watchlists[index];
    final stocks = wl.symbols
        .map((sym) => allStocks.where((s) => s.symbol == sym).firstOrNull)
        .whereType<Stock>()
        .toList();

    switch (_sort) {
      case WatchlistSort.symbol:
        stocks.sort((a, b) => a.symbol.compareTo(b.symbol));
        break;
      case WatchlistSort.price:
        stocks.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
        break;
      case WatchlistSort.change:
        stocks.sort((a, b) => b.changePercentage.compareTo(a.changePercentage));
        break;
      case WatchlistSort.volume:
        stocks.sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0));
        break;
    }

    return stocks;
  }

  void _openOrderSheet(Stock stock, OrderType side) {
    OrderFormSheet.show(context, stock: stock, initialSide: side);
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showAddWatchlistDialog() async {
    if (_watchlists.length >= Watchlist.maxWatchlists) {
      AppToast.warning(context, 'Maximum 5 watchlists allowed.');
      return;
    }

    AppDialog.input(
      context,
      title: 'New Watchlist',
      hint: 'Watchlist name',
      confirmLabel: 'Create',
      onSubmit: (name) {
        setState(() {
          _watchlists.add(
            Watchlist(
              id: 'wl-${DateTime.now().millisecondsSinceEpoch}',
              name: name,
              symbols: const [],
              order: _watchlists.length,
            ),
          );
          _rebuildTabController();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tabController.animateTo(_watchlists.length - 1);
          });
        });
      },
    );
  }

  Future<void> _showImportExportDialog(int tabIndex) async {
    final wl = _watchlists[tabIndex];
    final json = jsonEncode({'name': wl.name, 'symbols': wl.symbols});
    final controller = TextEditingController(text: json);

    AppDialog.confirm(
      context,
      title: 'Import / Export — ${wl.name}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'JSON symbols array',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: controller.text));
              AppToast.info(context, 'Copied to clipboard');
            },
            icon: const Icon(LucideIcons.copy, size: 14),
            label: const Text('Copy'),
          ),
        ],
      ),
      confirmLabel: 'Import',
      onConfirm: () {
        try {
          final decoded = jsonDecode(controller.text) as Map<String, dynamic>;
          final symbols = (decoded['symbols'] as List).cast<String>();
          setState(() {
            _watchlists[tabIndex] = _watchlists[tabIndex].copyWith(
              symbols: symbols,
            );
          });
        } catch (_) {
          AppToast.error(context, 'Invalid JSON format');
        }
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final allStocks = store.watchlist.toList();

    // ── Error state ───────────────────────────────────────────────────────────
    if (store.backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Market Watch')),
        body: BackendErrorWidget(
          message: store.backendErrorMessage,
          onRetry: () => store.connectLiveBackend(),
        ),
      );
    }

    // ── Loading state ─────────────────────────────────────────────────────────
    if (allStocks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Market Watch')),
        body: const BackendLoadingWidget(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Watchlist',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1565C0),
          unselectedLabelColor: const Color(0xFF757575),
          indicatorColor: const Color(0xFF1565C0),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: _watchlists.map((wl) => Tab(text: wl.name)).toList(),
        ),
        actions: [
          // Sort popup
          PopupMenuButton<WatchlistSort>(
            tooltip: 'Sort',
            icon: const Icon(LucideIcons.arrowUpDown, size: 20),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: WatchlistSort.symbol, child: Text('Symbol')),
              PopupMenuItem(value: WatchlistSort.price, child: Text('Price')),
              PopupMenuItem(
                value: WatchlistSort.change,
                child: Text('Change %'),
              ),
              PopupMenuItem(value: WatchlistSort.volume, child: Text('Volume')),
            ],
          ),
          // Add stock to current watchlist
          IconButton(
            tooltip: 'Add stock to watchlist',
            icon: const Icon(LucideIcons.plus, size: 22),
            onPressed: () => _showAddStockSheet(context, allStocks),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(_watchlists.length, (i) {
          final stocks = _stocksForWatchlist(i, allStocks);
          return _WatchlistTab(
            key: ValueKey(_watchlists[i].id),
            stocks: stocks,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final sym = _watchlists[i].symbols[oldIndex];
                final newSymbols = List<String>.from(_watchlists[i].symbols)
                  ..removeAt(oldIndex)
                  ..insert(newIndex, sym);
                _watchlists[i] = _watchlists[i].copyWith(symbols: newSymbols);
              });
            },
            onBuy: (stock) => _openOrderSheet(stock, OrderType.buy),
            onSell: (stock) => _openOrderSheet(stock, OrderType.sell),
            onTap: (stock) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StockDetailScreen(symbol: stock.symbol),
              ),
            ),
            onRemove: (stock) {
              setState(() {
                _watchlists[i] = _watchlists[i].copyWith(
                  symbols: _watchlists[i].symbols
                      .where((s) => s != stock.symbol)
                      .toList(),
                );
              });
            },
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddWatchlistDialog(),
        backgroundColor: const Color(0xFF1565C0),
        elevation: 2,
        tooltip: 'Create new watchlist',
        child: const Icon(Icons.playlist_add, color: Colors.white, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ─── Add stock bottom sheet ───────────────────────────────────────────────

  void _showAddStockSheet(BuildContext context, List<Stock> allStocks) {
    final currentTabIndex = _tabController.index;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddStockSheet(
        allStocks: allStocks,
        currentSymbols: _watchlists[currentTabIndex].symbols,
        onAdd: (symbol) {
          setState(() {
            final current = _watchlists[currentTabIndex].symbols;
            if (!current.contains(symbol)) {
              _watchlists[currentTabIndex] = _watchlists[currentTabIndex]
                  .copyWith(symbols: [...current, symbol]);
            }
          });
        },
      ),
    );
  }
}

// ─── Add Stock Bottom Sheet ───────────────────────────────────────────────────

class _AddStockSheet extends StatefulWidget {
  final List<Stock> allStocks;
  final List<String> currentSymbols;
  final void Function(String symbol) onAdd;

  const _AddStockSheet({
    required this.allStocks,
    required this.currentSymbols,
    required this.onAdd,
  });

  @override
  State<_AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<_AddStockSheet> {
  final _controller = TextEditingController();
  String _query = '';

  List<Stock> get _filtered {
    if (_query.isEmpty) return widget.allStocks;
    final q = _query.toLowerCase();
    return widget.allStocks
        .where(
          (s) =>
              s.symbol.toLowerCase().contains(q) ||
              s.name.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Add to Watchlist',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search stocks, eg. INFY, RELIANCE',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9E9E9E),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: Color(0xFF757575),
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'No stocks available'
                            : 'No results for "$_query"',
                        style: const TextStyle(color: Color(0xFF757575)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final stock = _filtered[i];
                        final alreadyAdded = widget.currentSymbols.contains(
                          stock.symbol,
                        );
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            stock.symbol,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0D0D0D),
                            ),
                          ),
                          subtitle: Text(
                            stock.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  stock.exchange,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              alreadyAdded
                                  ? const Icon(
                                      Icons.check_circle,
                                      size: 20,
                                      color: Color(0xFF00C853),
                                    )
                                  : const Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                      color: Color(0xFF1565C0),
                                    ),
                            ],
                          ),
                          onTap: alreadyAdded
                              ? () => AppToast.info(
                                  context,
                                  '${stock.symbol} already in watchlist',
                                )
                              : () {
                                  widget.onAdd(stock.symbol);
                                  Navigator.pop(ctx);
                                  AppToast.success(
                                    context,
                                    '${stock.symbol} added to watchlist',
                                  );
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Watchlist Tab ────────────────────────────────────────────────────────────

class _WatchlistTab extends StatefulWidget {
  final List<Stock> stocks;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(Stock) onBuy;
  final void Function(Stock) onSell;
  final void Function(Stock) onTap;
  final void Function(Stock) onRemove;

  const _WatchlistTab({
    super.key,
    required this.stocks,
    required this.onReorder,
    required this.onBuy,
    required this.onSell,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<_WatchlistTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.stocks
        : widget.stocks
              .where(
                (s) =>
                    s.symbol.toLowerCase().contains(_query.toLowerCase()) ||
                    s.name.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search in watchlist...',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9E9E9E),
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF757575),
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFF757575),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.playlist_add,
                        size: 48,
                        color: Color(0xFFE0E0E0),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? 'No stocks in this watchlist.\nTap + to add stocks.'
                            : 'No results for "$_query"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF757575),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: filtered.length,
                  onReorder: widget.onReorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final stock = filtered[index];
                    return _StockRow(
                      key: ValueKey(stock.symbol),
                      stock: stock,
                      index: index,
                      onTap: () => widget.onTap(stock),
                      onBuy: () => widget.onBuy(stock),
                      onSell: () => widget.onSell(stock),
                      onRemove: () => widget.onRemove(stock),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Stock Row ────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final Stock stock;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onRemove;

  const _StockRow({
    super.key,
    required this.stock,
    required this.index,
    required this.onTap,
    required this.onBuy,
    required this.onSell,
    required this.onRemove,
  });

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    stock.symbol,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹${stock.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF757575),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.trending_up,
                color: Color(0xFF00C853),
                size: 22,
              ),
              title: const Text(
                'Buy',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF00C853),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                onBuy();
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.trending_down,
                color: Color(0xFFD50000),
                size: 22,
              ),
              title: const Text(
                'Sell',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFD50000),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                onSell();
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.notifications_outlined,
                color: Color(0xFF757575),
                size: 22,
              ),
              title: const Text(
                'Set Alert',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFF757575),
                size: 22,
              ),
              title: const Text(
                'Remove from watchlist',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                onRemove();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    final changeColor = isPos
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final changeBg = isPos ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final arrow = isPos ? '▲' : '▼';
    final sign = isPos ? '+' : '';

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showContextMenu(context),
      child: SizedBox(
        height: 68,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFF5F5F5), width: 1),
            ),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.drag_handle,
                    size: 20,
                    color: Color(0xFFBDBDBD),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stock.symbol,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0D0D0D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // For MCX futures: show expiry date instead of just name
                    if (stock.isFutures && stock.expiry != null)
                      _ExpirySubtitle(stock: stock)
                    else
                      Text(
                        stock.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PriceFlashWidget(
                    price: stock.currentPrice,
                    child: Text(
                      '₹${stock.currentPrice.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D0D0D),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: changeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$arrow $sign${stock.changePercentage.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: changeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Expiry subtitle for MCX futures rows ────────────────────────────────────

class _ExpirySubtitle extends StatelessWidget {
  final Stock stock;
  const _ExpirySubtitle({required this.stock});

  @override
  Widget build(BuildContext context) {
    final expiry = stock.expiry!;
    final days = stock.daysToExpiry!;
    final months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr =
        '${expiry.day.toString().padLeft(2, '0')} ${months[expiry.month - 1]} ${expiry.year}';

    // Colour: red ≤7 days, amber ≤30 days, grey otherwise
    final Color color;
    if (days <= 7) {
      color = const Color(0xFFD32F2F);
    } else if (days <= 30) {
      color = const Color(0xFFE65100);
    } else {
      color = const Color(0xFF757575);
    }

    return Row(
      children: [
        Icon(Icons.event_outlined, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          'Exp $dateStr',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: days <= 30 ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (days <= 30) ...[
          const SizedBox(width: 4),
          Text(
            '· $days d left',
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.75)),
          ),
        ],
      ],
    );
  }
}
