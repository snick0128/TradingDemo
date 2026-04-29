import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_drawer.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

// ─── Sort options ─────────────────────────────────────────────────────────────

enum WatchlistSort { symbol, price, change, volume }

// ─── Pure logic helper (also used by property test) ──────────────────────────

Color priceChangeColor(double changePercentage) {
  return changePercentage >= 0 ? AppColors.success : AppColors.danger;
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

  Stock? _drawerStock;
  OrderType _drawerSide = OrderType.buy;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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

  void _openOrderDrawer(Stock stock, OrderType side) {
    setState(() {
      _drawerStock = stock;
      _drawerSide = side;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showAddWatchlistDialog() async {
    if (_watchlists.length >= Watchlist.maxWatchlists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 watchlists allowed.')),
      );
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Watchlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Watchlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
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
        // Jump to the new tab
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tabController.animateTo(_watchlists.length - 1);
        });
      });
    }
  }

  Future<void> _showImportExportDialog(int tabIndex) async {
    final wl = _watchlists[tabIndex];
    final json = jsonEncode({'name': wl.name, 'symbols': wl.symbols});
    final controller = TextEditingController(text: json);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import / Export — ${wl.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'JSON symbols array',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: controller.text));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                final decoded =
                    jsonDecode(controller.text) as Map<String, dynamic>;
                final symbols = (decoded['symbols'] as List).cast<String>();
                setState(() {
                  _watchlists[tabIndex] = _watchlists[tabIndex].copyWith(
                    symbols: symbols,
                  );
                });
                Navigator.pop(ctx);
              } catch (_) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Invalid JSON format')),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final allStocks = store.watchlist.toList();

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _drawerStock != null
          ? OrderFormDrawer(stock: _drawerStock!, initialSide: _drawerSide)
          : null,
      appBar: AppBar(
        title: const Text('Market Watch'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _watchlists.map((wl) => Tab(text: wl.name)).toList(),
        ),
        actions: [
          // Compact / Detailed toggle
          IconButton(
            tooltip: _compactView ? 'Detailed view' : 'Compact view',
            icon: Icon(
              _compactView ? LucideIcons.layoutList : LucideIcons.alignJustify,
              size: 20,
            ),
            onPressed: () => setState(() => _compactView = !_compactView),
          ),
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
          // Import / Export for current tab
          AnimatedBuilder(
            animation: _tabController,
            builder: (_, __) => IconButton(
              tooltip: 'Import / Export',
              icon: const Icon(LucideIcons.share2, size: 20),
              onPressed: () => _showImportExportDialog(_tabController.index),
            ),
          ),
          // Add watchlist
          IconButton(
            tooltip: 'New watchlist',
            icon: const Icon(LucideIcons.plus, size: 20),
            onPressed: _showAddWatchlistDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return TabBarView(
            controller: _tabController,
            children: List.generate(_watchlists.length, (i) {
              final stocks = _stocksForWatchlist(i, allStocks);
              return _WatchlistTab(
                key: ValueKey(_watchlists[i].id),
                stocks: stocks,
                compactView: _compactView,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final sym = _watchlists[i].symbols[oldIndex];
                    final newSymbols = List<String>.from(_watchlists[i].symbols)
                      ..removeAt(oldIndex)
                      ..insert(newIndex, sym);
                    _watchlists[i] = _watchlists[i].copyWith(
                      symbols: newSymbols,
                    );
                  });
                },
                onBuy: (stock) => _openOrderDrawer(stock, OrderType.buy),
                onSell: (stock) => _openOrderDrawer(stock, OrderType.sell),
                onTap: (stock) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(symbol: stock.symbol),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Watchlist Tab ────────────────────────────────────────────────────────────

class _WatchlistTab extends StatefulWidget {
  final List<Stock> stocks;
  final bool compactView;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(Stock) onBuy;
  final void Function(Stock) onSell;
  final void Function(Stock) onTap;

  const _WatchlistTab({
    super.key,
    required this.stocks,
    required this.compactView,
    required this.onReorder,
    required this.onBuy,
    required this.onSell,
    required this.onTap,
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
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search stocks...',
              prefixIcon: const Icon(
                LucideIcons.search,
                size: 16,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),
        // List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No stocks in this watchlist.\nUse Import to add symbols.'
                        : 'No results for "$_query"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: filtered.length,
                  onReorder: widget.onReorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final stock = filtered[index];
                    return widget.compactView
                        ? _CompactRow(
                            key: ValueKey(stock.symbol),
                            stock: stock,
                            index: index,
                            onBuy: () => widget.onBuy(stock),
                            onSell: () => widget.onSell(stock),
                            onTap: () => widget.onTap(stock),
                          )
                        : _DetailedRow(
                            key: ValueKey(stock.symbol),
                            stock: stock,
                            index: index,
                            onBuy: () => widget.onBuy(stock),
                            onSell: () => widget.onSell(stock),
                            onTap: () => widget.onTap(stock),
                          );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Compact Row ──────────────────────────────────────────────────────────────

class _CompactRow extends StatelessWidget {
  final Stock stock;
  final int index;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onTap;

  const _CompactRow({
    super.key,
    required this.stock,
    required this.index,
    required this.onBuy,
    required this.onSell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = priceChangeColor(stock.changePercentage);
    final sign = stock.changePercentage >= 0 ? '+' : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Drag handle — left, explicit
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Symbol
            Expanded(
              flex: 3,
              child: Text(
                stock.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // Price
            Expanded(
              flex: 3,
              child: PriceFlashWidget(
                price: stock.currentPrice,
                child: Text(
                  '₹${stock.currentPrice.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            // Change %
            Expanded(
              flex: 2,
              child: Text(
                '$sign${stock.changePercentage.toStringAsFixed(2)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _BuySellButtons(onBuy: onBuy, onSell: onSell),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Detailed Row ─────────────────────────────────────────────────────────────

class _DetailedRow extends StatelessWidget {
  final Stock stock;
  final int index;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onTap;

  const _DetailedRow({
    super.key,
    required this.stock,
    required this.index,
    required this.onBuy,
    required this.onSell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = priceChangeColor(stock.changePercentage);
    final sign = stock.changePercentage >= 0 ? '+' : '';
    final isPos = stock.changePercentage >= 0;

    String volText = '';
    if (stock.volume != null) {
      final v = stock.volume!;
      if (v >= 10000000)
        volText = 'Vol: ${(v / 10000000).toStringAsFixed(1)}Cr';
      else if (v >= 100000)
        volText = 'Vol: ${(v / 100000).toStringAsFixed(1)}L';
      else if (v >= 1000)
        volText = 'Vol: ${(v / 1000).toStringAsFixed(1)}K';
      else
        volText = 'Vol: ${v.toStringAsFixed(0)}';
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: const BorderSide(color: AppColors.border, width: 0.5),
            left: BorderSide(
              color: isPos
                  ? AppColors.success.withValues(alpha: 0.6)
                  : AppColors.danger.withValues(alpha: 0.6),
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drag handle — explicit, left side
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Symbol + Name + exchange badge + volume
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          stock.symbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'NSE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stock.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (volText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        volText,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Price + change chip
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PriceFlashWidget(
                  price: stock.currentPrice,
                  child: Text(
                    '₹${stock.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: changeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$sign${stock.changePercentage.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: changeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            // Buy / Sell buttons
            const SizedBox(width: 10),
            _BuySellButtons(onBuy: onBuy, onSell: onSell),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

// ─── Buy / Sell Buttons ───────────────────────────────────────────────────────

class _BuySellButtons extends StatelessWidget {
  final VoidCallback onBuy;
  final VoidCallback onSell;

  const _BuySellButtons({required this.onBuy, required this.onSell});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(label: 'BUY', color: AppColors.success, onTap: onBuy),
        const SizedBox(width: 4),
        _ActionButton(label: 'SELL', color: AppColors.danger, onTap: onSell),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
