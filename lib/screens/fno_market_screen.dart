import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/order_form_sheet.dart';
import '../widgets/shared_widgets.dart';
import 'options_chain_screen.dart';

// Exchange display metadata
const _kExchanges = [
  _ExchangeMeta(label: 'NSE F&O', exchange: 'NFO', color: Color(0xFF1565C0)),
  _ExchangeMeta(label: 'BSE F&O', exchange: 'BFO', color: Color(0xFFE65100)),
  _ExchangeMeta(label: 'MCX F&O', exchange: 'MCX', color: Color(0xFF2E7D32)),
];

class _ExchangeMeta {
  final String label;
  final String exchange;
  final Color color;
  const _ExchangeMeta({
    required this.label,
    required this.exchange,
    required this.color,
  });
}

class FnoMarketScreen extends StatefulWidget {
  final bool showAppBar;

  const FnoMarketScreen({super.key, this.showAppBar = true});

  @override
  State<FnoMarketScreen> createState() => _FnoMarketScreenState();
}

class _FnoMarketScreenState extends State<FnoMarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Per-exchange state
  final Map<String, List<Map<String, dynamic>>> _underlyings = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, String?> _error = {};
  final Map<String, String> _searchQuery = {};
  final Map<String, String> _typeFilter = {};

  // Track which tabs have been initialised to avoid duplicate loads
  final Set<int> _loadedTabs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kExchanges.length, vsync: this);
    for (final ex in _kExchanges) {
      _isLoading[ex.exchange] = false;
      _error[ex.exchange] = null;
      _searchQuery[ex.exchange] = '';
      _typeFilter[ex.exchange] = 'ALL';
    }
    _tabController.addListener(_onTabChanged);
    // Load first tab immediately
    _loadTab(0);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadTab(_tabController.index);
    }
  }

  Future<void> _loadTab(int index) async {
    if (_loadedTabs.contains(index)) return;
    _loadedTabs.add(index);
    await _fetchUnderlyings(_kExchanges[index].exchange);
  }

  Future<void> _fetchUnderlyings(String exchange, {bool forceRefresh = false}) async {
    if (_isLoading[exchange] == true) return;
    if (forceRefresh) {
      BackendApiService.invalidate('/derivatives/fno-underlyings');
      _loadedTabs.removeWhere(
        (i) => _kExchanges[i].exchange == exchange,
      );
    }
    setState(() {
      _isLoading[exchange] = true;
      _error[exchange] = null;
    });
    try {
      final data = await BackendApiService().getFnoUnderlyings(exchange: exchange);
      if (mounted) {
        setState(() {
          _underlyings[exchange] = data;
          _isLoading[exchange] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading[exchange] = false;
          _error[exchange] = e.toString().replaceFirst('BackendException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('F&O Markets'),
              bottom: _buildTabBar(),
            )
          : null,
      body: widget.showAppBar
          ? _buildTabBarView()
          : Column(
              children: [
                Material(
                  color: AppColors.surface,
                  child: _buildTabBar(),
                ),
                Expanded(child: _buildTabBarView()),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: _kExchanges
          .map((ex) => Tab(text: ex.label))
          .toList(),
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: _kExchanges
          .map((ex) => _ExchangeTab(
                meta: ex,
                underlyings: _underlyings[ex.exchange] ?? [],
                isLoading: _isLoading[ex.exchange] ?? false,
                error: _error[ex.exchange],
                searchQuery: _searchQuery[ex.exchange] ?? '',
                typeFilter: _typeFilter[ex.exchange] ?? 'ALL',
                onSearchChanged: (q) =>
                    setState(() => _searchQuery[ex.exchange] = q),
                onTypeFilterChanged: (t) =>
                    setState(() => _typeFilter[ex.exchange] = t),
                onRetry: () => _fetchUnderlyings(ex.exchange, forceRefresh: true),
                onUnderlyingTap: (underlying) =>
                    _showUnderlyingSheet(context, underlying, ex),
              ))
          .toList(),
    );
  }

  void _showUnderlyingSheet(
    BuildContext context,
    Map<String, dynamic> underlying,
    _ExchangeMeta ex,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnderlyingBottomSheet(
        underlying: underlying,
        meta: ex,
      ),
    );
  }
}

// ─── Per-exchange tab content ──────────────────────────────────────────────────

class _ExchangeTab extends StatelessWidget {
  final _ExchangeMeta meta;
  final List<Map<String, dynamic>> underlyings;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String typeFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeFilterChanged;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>> onUnderlyingTap;

  const _ExchangeTab({
    required this.meta,
    required this.underlyings,
    required this.isLoading,
    required this.error,
    required this.searchQuery,
    required this.typeFilter,
    required this.onSearchChanged,
    required this.onTypeFilterChanged,
    required this.onRetry,
    required this.onUnderlyingTap,
  });

  List<Map<String, dynamic>> get _filtered {
    var list = underlyings;
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toUpperCase();
      list = list
          .where((u) =>
              (u['name'] as String? ?? '').toUpperCase().contains(q))
          .toList();
    }
    if (typeFilter != 'ALL') {
      list = list.where((u) {
        final types = List<String>.from(u['types'] as List? ?? []);
        if (typeFilter == 'FUT') {
          return types.any((t) => t.toUpperCase().contains('FUT'));
        }
        if (typeFilter == 'OPT') {
          return types.any((t) =>
              t.toUpperCase().contains('OPT') ||
              t.toUpperCase() == 'CE' ||
              t.toUpperCase() == 'PE');
        }
        return true;
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(context),
        _buildTypeFilter(),
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        onChanged: onSearchChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search ${meta.label} underlyings…',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: AppColors.textSecondary,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _TypeChip(
            label: 'All',
            value: 'ALL',
            selected: typeFilter == 'ALL',
            onTap: onTypeFilterChanged,
          ),
          const SizedBox(width: 8),
          _TypeChip(
            label: 'Futures',
            value: 'FUT',
            selected: typeFilter == 'FUT',
            onTap: onTypeFilterChanged,
          ),
          const SizedBox(width: 8),
          _TypeChip(
            label: 'Options',
            value: 'OPT',
            selected: typeFilter == 'OPT',
            onTap: onTypeFilterChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return ListView.builder(
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ShimmerListTile(),
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No instruments found',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
      itemBuilder: (context, i) => _UnderlyingTile(
        data: items[i],
        exchangeMeta: meta,
        onTap: () => onUnderlyingTap(items[i]),
      ),
    );
  }
}

// ─── Type chip ────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  const _TypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
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

// ─── Underlying tile ──────────────────────────────────────────────────────────

class _UnderlyingTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final _ExchangeMeta exchangeMeta;
  final VoidCallback onTap;

  const _UnderlyingTile({
    required this.data,
    required this.exchangeMeta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final count = data['count'] as int? ?? 0;
    final types = List<String>.from(data['types'] as List? ?? []);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Exchange badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: exchangeMeta.color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: exchangeMeta.color.withValues(alpha:0.3),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                exchangeMeta.exchange,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: exchangeMeta.color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count instruments',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Type badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: types.map((t) => _TypeBadge(type: t)).toList(),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  Color get _color {
    final t = type.toUpperCase();
    if (t.contains('FUT')) return const Color(0xFF1565C0);
    if (t.contains('OPT') || t == 'CE') return const Color(0xFF2E7D32);
    if (t == 'PE') return const Color(0xFFB71C1C);
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha:0.4)),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

// ─── Underlying bottom sheet ──────────────────────────────────────────────────

class _UnderlyingBottomSheet extends StatefulWidget {
  final Map<String, dynamic> underlying;
  final _ExchangeMeta meta;

  const _UnderlyingBottomSheet({
    required this.underlying,
    required this.meta,
  });

  @override
  State<_UnderlyingBottomSheet> createState() => _UnderlyingBottomSheetState();
}

class _UnderlyingBottomSheetState extends State<_UnderlyingBottomSheet> {
  List<String> _expiries = [];
  String? _selectedExpiry;
  bool _isLoadingExpiries = true;
  String? _expiriesError;

  @override
  void initState() {
    super.initState();
    _loadExpiries();
  }

  Future<void> _loadExpiries() async {
    setState(() {
      _isLoadingExpiries = true;
      _expiriesError = null;
    });
    try {
      final symbol = widget.underlying['name'] as String? ?? '';
      final expiries = await BackendApiService().getFnoExpiryDates(
        symbol,
        exchange: widget.meta.exchange,
      );
      if (mounted) {
        setState(() {
          _expiries = expiries;
          _selectedExpiry = expiries.isNotEmpty ? expiries.first : null;
          _isLoadingExpiries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingExpiries = false;
          _expiriesError =
              e.toString().replaceFirst('BackendException: ', '');
        });
      }
    }
  }

  String _formatExpiry(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.underlying['name'] as String? ?? '';
    final types = List<String>.from(
      widget.underlying['types'] as List? ?? [],
    );
    final hasFut = types.any((t) => t.toUpperCase().contains('FUT'));
    final hasOpt = types.any((t) =>
        t.toUpperCase().contains('OPT') ||
        t.toUpperCase() == 'CE' ||
        t.toUpperCase() == 'PE');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: widget.meta.color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.meta.exchange,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.meta.color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Select Expiry',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildExpirySelector(),
          const SizedBox(height: 24),
          if (hasOpt) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedExpiry == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OptionsChainScreen(
                              symbol: name,
                              exchange: widget.meta.exchange,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('View Options Chain'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (hasFut) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _selectedExpiry == null
                    ? null
                    : () {
                        final expiry = _selectedExpiry!;
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _FuturesContractsScreen(
                              symbol: name,
                              expiry: expiry,
                              exchange: widget.meta.exchange,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.candlestick_chart, size: 18),
                label: const Text('Trade Futures'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpirySelector() {
    if (_isLoadingExpiries) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_expiriesError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha:0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withValues(alpha:0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _expiriesError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                ),
              ),
            ),
            TextButton(
              onPressed: _loadExpiries,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_expiries.isEmpty) {
      return const Text(
        'No expiry dates available',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedExpiry,
          isExpanded: true,
          items: _expiries
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    _formatExpiry(e),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedExpiry = v),
        ),
      ),
    );
  }
}

// ─── Futures Contracts Screen ─────────────────────────────────────────────────

class _FuturesContractsScreen extends StatefulWidget {
  final String symbol;
  final String expiry;
  final String exchange;

  const _FuturesContractsScreen({
    required this.symbol,
    required this.expiry,
    required this.exchange,
  });

  @override
  State<_FuturesContractsScreen> createState() =>
      _FuturesContractsScreenState();
}

class _FuturesContractsScreenState extends State<_FuturesContractsScreen> {
  List<Map<String, dynamic>> _contracts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  Future<void> _loadContracts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = BackendApiService();
      final instruments = await api.getFnoInstruments(
        exchange: widget.exchange,
        type: 'FUT',
        underlying: widget.symbol,
        limit: 30,
      );
      // Filter by expiry if possible, otherwise show all futures
      final expiryDate = widget.expiry.split('T').first;
      final filtered = instruments.where((i) {
        final expiry = (i['expiry'] as String? ?? '').split('T').first;
        return expiry == expiryDate;
      }).toList();

      if (mounted) {
        setState(() {
          _contracts = filtered.isNotEmpty ? filtered : instruments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceFirst('BackendException: ', '');
        });
      }
    }
  }

  String _formatExpiry(String iso) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedExpiry = _formatExpiry(widget.expiry);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.symbol} Futures',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${widget.exchange} · Expiry: $formattedExpiry',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: ShimmerListTile(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadContracts,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_contracts.isEmpty) {
      return const Center(
        child: Text(
          'No futures contracts found',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _contracts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _FutureContractTile(contract: _contracts[i], exchange: widget.exchange),
    );
  }
}

class _FutureContractTile extends StatelessWidget {
  final Map<String, dynamic> contract;
  final String exchange;

  const _FutureContractTile({
    required this.contract,
    required this.exchange,
  });

  @override
  Widget build(BuildContext context) {
    final tradingSymbol = contract['tradingSymbol'] as String? ??
        contract['symbol'] as String? ?? '';
    final ltp = (contract['ltp'] as num?)?.toDouble() ?? 0;
    final change = (contract['percentChange'] as num?)?.toDouble() ??
        (contract['change'] as num?)?.toDouble() ?? 0;
    final token = contract['symbolToken'] as String? ??
        contract['token'] as String? ?? '';
    final isPos = change >= 0;
    final changeColor = isPos ? const Color(0xFF00C853) : const Color(0xFFD50000);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Contract info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tradingSymbol,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D0D0D),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      ltp > 0 ? '₹${ltp.toStringAsFixed(2)}' : '—',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0D0D0D),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (change != 0)
                      Text(
                        '${isPos ? '+' : ''}${change.toStringAsFixed(2)}%',
                        style: TextStyle(fontSize: 12, color: changeColor),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // BUY / SELL buttons
          Row(
            children: [
              _tradeButton(
                context,
                label: 'BUY',
                color: const Color(0xFF00C853),
                symbol: tradingSymbol,
                token: token,
                ltp: ltp,
                side: OrderType.buy,
              ),
              const SizedBox(width: 8),
              _tradeButton(
                context,
                label: 'SELL',
                color: const Color(0xFFD50000),
                symbol: tradingSymbol,
                token: token,
                ltp: ltp,
                side: OrderType.sell,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tradeButton(
    BuildContext context, {
    required String label,
    required Color color,
    required String symbol,
    required String token,
    required double ltp,
    required OrderType side,
  }) {
    return GestureDetector(
      onTap: () {
        final store = TradingScope.of(context);
        Stock stock;
        try {
          stock = store.stockBySymbol(symbol);
        } catch (_) {
          stock = Stock(
            symbol: symbol,
            name: symbol,
            currentPrice: ltp,
            changePercentage: 0,
            sector: '',
            exchange: exchange,
            token: token,
          );
        }
        OrderFormSheet.show(
          context,
          stock: stock,
          initialSide: side,
        );
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: side == OrderType.buy
              ? const Color(0xFF00C853).withOpacity(0.08)
              : const Color(0xFFD50000).withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
