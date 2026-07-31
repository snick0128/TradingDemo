import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../search/search_index.dart';
import '../services/subscription_manager.dart';
import '../state/tab_notifier.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/backend_error_widget.dart';
import '../widgets/instrument_logo.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import 'stock_detail_screen.dart';

// ─── Sort options ─────────────────────────────────────────────────────────────

// `manual` preserves insertion/drag order — newly added stocks land at the top.
enum WatchlistSort { manual, symbol, price, change, volume }

// ─── Pure logic helper (also used by property test) ──────────────────────────

Color priceChangeColor(double changePercentage) {
  return changePercentage >= 0 ? AppColors.success : AppColors.danger;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class MarketWatchScreen extends StatefulWidget {
  const MarketWatchScreen({super.key});

  /// Set to true by main_shell when the Markets tab is selected; false otherwise.
  /// Market Watch subscribes/unsubscribes its symbols based on this flag.
  static final ValueNotifier<bool> isActiveNotifier = ValueNotifier(false);

  @override
  State<MarketWatchScreen> createState() => _MarketWatchScreenState();
}

class _MarketWatchScreenState extends State<MarketWatchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _initialized = false;

  bool _compactView = false;
  WatchlistSort _sort = WatchlistSort.manual;

  bool _isActiveTab = false;
  TradingStore? _store;

  // Named watchlists live in TradingStore — the single source of truth shared
  // with Stock Detail's save button and any other screen that reads/writes them.
  List<Watchlist> get _watchlists => _store?.watchlists ?? const [];

  // Structural snapshot used to gate unnecessary rebuilds from store events
  // that don't affect the watchlist display (e.g. balance updates, P&L ticks).
  bool _lastBackendError = false;
  int _lastKnownStocksLength = -1;
  int _lastWatchlistsFingerprint = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _isActiveTab = activeTabNotifier.value == 1;
    MarketWatchScreen.isActiveNotifier.addListener(_onVisibilityChanged);
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      store.addListener(_onStoreChanged);
    }
    // Only build the tab controller once — never rebuild on subsequent
    // dependency changes. Later watchlist-count changes are handled by
    // _onStoreChanged, which rebuilds the controller when needed.
    if (!_initialized) {
      _initialized = true;
      _lastWatchlistsFingerprint = _computeWatchlistsFingerprint(store.watchlists);
      _rebuildTabController();
    }
  }

  void _onStoreChanged() {
    if (!_isActiveTab) return;
    final store = _store;
    if (store == null) return;
    // Only rebuild on structural changes that affect what the watchlist displays.
    // Price ticks never call notifyListeners() — this guard eliminates rebuilds
    // from balance/equity events that don't change the watchlist content.
    final nowWlFp = _computeWatchlistsFingerprint(store.watchlists);
    if (nowWlFp != _lastWatchlistsFingerprint) {
      _lastWatchlistsFingerprint = nowWlFp;
      if (store.watchlists.length != _tabController.length) {
        _rebuildTabController();
      }
      setState(() {});
      return;
    }
    final nowError = store.backendError;
    final nowLen   = store.knownStocks.length;
    if (nowError == _lastBackendError && nowLen == _lastKnownStocksLength) return;
    _lastBackendError       = nowError;
    _lastKnownStocksLength  = nowLen;
    setState(() {});
  }

  // Cheap order-sensitive fingerprint so we only rebuild when a watchlist's
  // name/count/symbol-order actually changed (mutations can come from other
  // screens, e.g. Stock Detail's save button, not just from this screen).
  int _computeWatchlistsFingerprint(List<Watchlist> wls) {
    var fp = wls.length;
    for (final w in wls) {
      fp = fp * 31 + w.symbols.length;
      for (final s in w.symbols) {
        fp = fp * 31 + s.hashCode;
      }
    }
    return fp;
  }

  void _onTabVisibilityChanged() {
    final active = activeTabNotifier.value == 1;
    if (active == _isActiveTab) return;
    _isActiveTab = active;
    if (active) setState(() {});
  }

  void _rebuildTabController() {
    final old = _tabController;
    _tabController = TabController(length: _watchlists.length, vsync: this)
      ..addListener(_onTabChanged);
    old.dispose();
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabVisibilityChanged);
    _store?.removeListener(_onStoreChanged);
    MarketWatchScreen.isActiveNotifier.removeListener(_onVisibilityChanged);
    SubscriptionManager.instance.unsubscribeScreen('market_watch');
    _tabController.dispose();
    super.dispose();
  }

  // ─── Subscription management ─────────────────────────────────────────────────

  void _onVisibilityChanged() {
    if (MarketWatchScreen.isActiveNotifier.value) {
      _subscribeCurrentTab();
    } else {
      SubscriptionManager.instance.unsubscribeScreen('market_watch');
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (MarketWatchScreen.isActiveNotifier.value) _subscribeCurrentTab();
  }

  void _subscribeCurrentTab() {
    if (!_initialized || _watchlists.isEmpty) return;
    final idx = _tabController.index.clamp(0, _watchlists.length - 1);
    final symbols = _watchlists[idx].symbols.toSet();
    SubscriptionManager.instance.subscribeForScreen('market_watch', symbols);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  List<Stock> _stocksForWatchlist(int index, TradingStore store) {
    final wl = _watchlists[index];
    final stocks = wl.symbols
        .map((sym) => store.stockBySymbolOrNull(sym))
        .whereType<Stock>()
        .toList();

    switch (_sort) {
      case WatchlistSort.manual:
        // Preserve wl.symbols order as-is — newly added stocks were prepended
        // to the front in _showAddStockSheet, so they show up on top here.
        break;
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
    final store = _store!;
    if (store.watchlists.length >= Watchlist.maxWatchlists) {
      AppToast.warning(context, 'Maximum 5 watchlists allowed.');
      return;
    }

    AppDialog.input(
      context,
      title: 'New Watchlist',
      message: 'Give your list a name — e.g. "Tech Stocks" or "Banking".',
      hint: 'Watchlist name',
      confirmLabel: 'Create',
      icon: LucideIcons.listPlus,
      onSubmit: (name) {
        store.createWatchlist(name);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tabController.animateTo(store.watchlists.length - 1);
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
          _store!.replaceWatchlistSymbols(wl.id, symbols);
        } catch (_) {
          AppToast.error(context, 'Invalid JSON format');
        }
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = _store ?? TradingScope.read(context);

    // ── Error state ───────────────────────────────────────────────────────────
    if (store.backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Markets')),
        body: BackendErrorWidget(
          message: store.backendErrorMessage,
          onRetry: () => store.connectLiveBackend(),
        ),
      );
    }

    // ── Loading state ─────────────────────────────────────────────────────────
    if (store.knownStocks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Markets')),
        body: const BackendLoadingWidget(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Markets',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                  AppHeaderAction(
                    icon: LucideIcons.arrowUpDown,
                    tooltip: 'Sort',
                    label: 'Sort',
                    onTap: _showSortSheet,
                  ),
                  const SizedBox(width: 10),
                  AppHeaderAction(
                    icon: LucideIcons.plus,
                    tooltip: 'Add stock to watchlist',
                    label: 'Add',
                    onTap: () => _showAddStockSheet(context, store),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_watchlists.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 2,
                  labelPadding: const EdgeInsets.only(right: 24),
                  labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  tabs: _watchlists.map((wl) => Tab(text: wl.name)).toList(),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: List.generate(_watchlists.length, (i) {
                  final stocks = _stocksForWatchlist(i, store);
                  return _WatchlistTab(
                    key: ValueKey(_watchlists[i].id),
                    stocks: stocks,
                    onReorder: (oldIndex, newIndex) {
                      _store!.reorderWatchlistSymbol(_watchlists[i].id, oldIndex, newIndex);
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
                      _store!.removeSymbolFromWatchlist(_watchlists[i].id, stock.symbol);
                    },
                  );
                }),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: TradingBottomNavBar.bottomInset(context) + 16,
        ),
        child: FloatingActionButton(
          onPressed: () => _showAddWatchlistDialog(),
          backgroundColor: AppColors.primary,
          elevation: 2,
          tooltip: 'Create new watchlist',
          child: const Icon(Icons.playlist_add, color: Colors.white, size: 26),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showSortSheet() {
    const options = [
      (WatchlistSort.manual, 'Manual (recently added first)', LucideIcons.gripVertical),
      (WatchlistSort.symbol, 'Symbol', LucideIcons.type),
      (WatchlistSort.price, 'Price', LucideIcons.indianRupee),
      (WatchlistSort.change, 'Change %', LucideIcons.percent),
      (WatchlistSort.volume, 'Volume', LucideIcons.barChart2),
    ];
    AppBottomSheet.show<void>(
      context,
      title: 'Sort by',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = _sort == o.$1;
          return ListTile(
            leading: Icon(o.$3, size: 18, color: selected ? AppColors.primary : AppColors.textSecondary),
            title: Text(
              o.$2,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            trailing: selected ? const Icon(Icons.check, size: 18, color: AppColors.primary) : null,
            onTap: () {
              setState(() => _sort = o.$1);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  // ─── Add stock bottom sheet ───────────────────────────────────────────────

  void _showAddStockSheet(BuildContext context, TradingStore store) {
    final currentTabIndex = _tabController.index;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddStockSheet(
        store: store,
        currentSymbols: _watchlists[currentTabIndex].symbols,
        onAdd: (symbol) {
          _store!.addSymbolToWatchlist(_watchlists[currentTabIndex].id, symbol);
        },
      ),
    );
  }
}

// ─── Add Stock Bottom Sheet ───────────────────────────────────────────────────
// Searches the SAME data source as Universal Search (lib/screens/universal_
// search_screen.dart): the shared SearchIndex trie, backed by the backend
// /search endpoint via BackendApiService.searchUniversal(). Remote results are
// ingested into SearchIndex.instance so both screens benefit from each other's
// searches for the rest of the session.

class _AddStockSheet extends StatefulWidget {
  final TradingStore store;
  final List<String> currentSymbols;
  final void Function(String symbol) onAdd;

  const _AddStockSheet({
    required this.store,
    required this.currentSymbols,
    required this.onAdd,
  });

  @override
  State<_AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<_AddStockSheet> {
  final _controller = TextEditingController();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  String _query = '';
  List<Instrument> _localResults = [];
  bool _remoteLoading = false;
  Timer? _debounce;
  int _reqGen = 0;

  // Default view (empty query): stocks already known to the live price
  // universe — same fallback this sheet always showed before.
  List<Instrument> get _defaultResults => widget.store.knownStocks
      .map((s) => Instrument(
            symbol: s.symbol,
            displayName: s.symbol,
            name: s.name,
            exchange: s.exchange,
            segment: InstrumentSegment.eq,
          ))
      .toList();

  List<Instrument> get _filtered => _query.isEmpty ? _defaultResults : _localResults;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _query = q;
        _localResults = [];
        _remoteLoading = false;
      });
      return;
    }

    // Instant local hit — same shared trie Universal Search uses.
    final local = SearchIndex.instance.search(q, limit: 20);
    setState(() {
      _query = q;
      _localResults = local;
      _remoteLoading = q.length >= 2;
    });

    if (q.length < 2) return;
    final gen = ++_reqGen;
    _debounce = Timer(const Duration(milliseconds: 150), () => _fetchRemote(q, gen));
  }

  Future<void> _fetchRemote(String q, int gen) async {
    if (!mounted || gen != _reqGen) return;
    try {
      final results = await _api.searchUniversal(q);
      if (!mounted || gen != _reqGen) return;
      // Ingest into the shared trie — next keystroke (here or in Universal
      // Search) is served instantly, and both screens see the same catalog.
      SearchIndex.instance.ingestRemoteResults(results);
      setState(() {
        _localResults = SearchIndex.instance.search(q, limit: 20);
        _remoteLoading = false;
      });
    } catch (_) {
      if (mounted && gen == _reqGen) setState(() => _remoteLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.borderDark : AppColors.divider;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppColors.heroRadius)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  const Text(
                    'Add to Watchlist',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
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
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search stocks, eg. INFY, RELIANCE',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceAltDark : AppColors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: borderColor),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: _remoteLoading
                          ? const CircularProgressIndicator()
                          : Text(
                              _query.isEmpty
                                  ? 'No stocks available'
                                  : 'No results for "$_query"',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(top: 4),
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
                          leading: InstrumentLogo(
                            symbol: stock.symbol,
                            exchange: stock.exchange,
                            size: 36,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  stock.symbol,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AppTagChip.neutral(stock.exchange),
                            ],
                          ),
                          subtitle: Text(
                            stock.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _AddStockButton(added: alreadyAdded),
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

class _AddStockButton extends StatelessWidget {
  final bool added;
  const _AddStockButton({required this.added});

  @override
  Widget build(BuildContext context) {
    if (added) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check, size: 14, color: AppColors.success),
            SizedBox(width: 4),
            Text('Added', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
      ),
      child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────
// Total / Gainers / Losers / Overall Change — computed live from whatever
// the tab is currently showing (so it reflects an active search filter too).

class _WatchlistSummaryCard extends StatelessWidget {
  final List<Stock> stocks;
  const _WatchlistSummaryCard({required this.stocks});

  @override
  Widget build(BuildContext context) {
    final total = stocks.length;
    final gainers = stocks.where((s) => s.changePercentage > 0).length;
    final losers = stocks.where((s) => s.changePercentage < 0).length;
    final overall = total == 0
        ? 0.0
        : stocks.fold<double>(0, (sum, s) => sum + s.changePercentage) / total;
    final overallColor = overall >= 0 ? AppColors.success : AppColors.danger;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.lineChart,
                iconColor: AppColors.primary,
                value: '$total',
                label: 'Total',
              ),
            ),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4, color: AppColors.divider),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.arrowUp,
                iconColor: AppColors.success,
                value: '$gainers',
                label: 'Gainers',
              ),
            ),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4, color: AppColors.divider),
            Expanded(
              child: _SummaryStat(
                icon: LucideIcons.arrowDown,
                iconColor: AppColors.danger,
                value: '$losers',
                label: 'Losers',
              ),
            ),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4, color: AppColors.divider),
            Expanded(
              child: _SummaryStat(
                value: '${overall >= 0 ? '+' : ''}${overall.toStringAsFixed(2)}%',
                valueColor: overallColor,
                label: 'Overall Change',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String value;
  final Color? valueColor;
  final String label;

  const _SummaryStat({
    this.icon,
    this.iconColor,
    required this.value,
    this.valueColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 4),
        ],
        Text(
          value,
          style: AppTheme.mono(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor ?? AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      ],
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
                color: AppColors.textTertiary,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppColors.cardRadius),
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
        if (filtered.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _WatchlistSummaryCard(stocks: filtered),
          ),
        ],
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.playlist_add,
                        size: 48,
                        color: AppColors.border,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? 'No stocks in this watchlist.\nTap + to add stocks.'
                            : 'No results for "$_query"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: EdgeInsets.only(bottom: TradingBottomNavBar.bottomInset(context)),
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
    final store = TradingScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
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
                color: AppColors.border,
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
                  ValueListenableBuilder<double>(
                    valueListenable: store.ltpNotifier(stock.symbol),
                    builder: (_, liveLtp, __) => Text(
                      '₹${(liveLtp > 0 ? liveLtp : stock.currentPrice).toStringAsFixed(2)}',
                      style: AppTheme.mono(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.trending_up,
                color: AppColors.success,
                size: 22,
              ),
              title: const Text(
                'Buy',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.success,
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
                color: AppColors.danger,
                size: 22,
              ),
              title: const Text(
                'Sell',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.danger,
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
                color: AppColors.textSecondary,
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
                color: AppColors.textSecondary,
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
    final changeColor = isPos ? AppColors.success : AppColors.danger;
    final arrow = isPos ? '▲' : '▼';
    final sign = isPos ? '+' : '';
    final store = TradingScope.read(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InstrumentLogo.forStock(stock, size: 30),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stock.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // For MCX futures: show expiry date instead of just name
                  if (stock.isFutures && stock.expiry != null)
                    _ExpirySubtitle(stock: stock)
                  else
                    Text(
                      stock.exchange.isNotEmpty ? stock.exchange : stock.name,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                LivePriceText(
                  symbol: stock.symbol,
                  store: store,
                  style: AppTheme.mono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '$arrow $sign${stock.changePercentage.toStringAsFixed(2)}%',
                  style: AppTheme.mono(fontSize: 12, fontWeight: FontWeight.w600, color: changeColor),
                ),
              ],
            ),
          ],
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
    final expiry = stock.expiry;       // DateTime? — safe nullable access
    final days   = stock.daysToExpiry; // int?       — safe nullable access

    // Hide subtitle entirely when expiry is unavailable (commodity roll-over, etc.)
    if (expiry == null) return const SizedBox.shrink();

    final int safeDays = days ?? 0;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr =
        '${expiry.day.toString().padLeft(2, '0')} ${months[expiry.month - 1]} ${expiry.year}';

    // Colour: red ≤7 days, amber ≤30 days, grey otherwise
    final Color color;
    if (safeDays <= 7) {
      color = AppColors.danger;
    } else if (safeDays <= 30) {
      color = AppColors.warning;
    } else {
      color = AppColors.textSecondary;
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
            fontWeight: safeDays <= 30 ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (safeDays <= 30) ...[
          const SizedBox(width: 4),
          Text(
            '· $safeDays d left',
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.75)),
          ),
        ],
      ],
    );
  }
}
