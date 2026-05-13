import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class DerivativeItem {
  final String tradingSymbol;
  final String symbolToken;
  final double percentChange;
  final double openInterest;
  final double netChangeOI;
  final double ltp;
  final double netChange;

  const DerivativeItem({
    required this.tradingSymbol,
    required this.symbolToken,
    required this.percentChange,
    required this.openInterest,
    required this.netChangeOI,
    this.ltp = 0,
    this.netChange = 0,
  });

  factory DerivativeItem.fromJson(Map<String, dynamic> j) => DerivativeItem(
    tradingSymbol: (j['tradingSymbol'] ?? j['tradingsymbol'] ?? '') as String,
    symbolToken: (j['symbolToken'] ?? j['symboltoken'] ?? '').toString(),
    percentChange: (j['percentChange'] as num?)?.toDouble() ?? 0,
    openInterest: (j['openInterest'] as num?)?.toDouble() ?? 0,
    netChangeOI: (j['netChangeOpenInterest'] as num?)?.toDouble() ?? 0,
    ltp: (j['ltp'] as num?)?.toDouble() ?? 0,
    netChange: (j['netChange'] as num?)?.toDouble() ?? 0,
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TopGainersLosersScreen extends StatefulWidget {
  const TopGainersLosersScreen({super.key});

  @override
  State<TopGainersLosersScreen> createState() => _TopGainersLosersScreenState();
}

class _TopGainersLosersScreenState extends State<TopGainersLosersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  String _mode = 'OI %'; // 'OI %' or 'Price %'
  String _expiry = 'NEAR';

  List<DerivativeItem> _gainers = [];
  List<DerivativeItem> _losers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _gainersType =>
      _mode == 'OI %' ? 'PercOIGainers' : 'PercPriceGainers';
  String get _losersType =>
      _mode == 'OI %' ? 'PercOILosers' : 'PercPriceLosers';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getDerivativeGainersLosers(
          datatype: _gainersType,
          expiry: _expiry,
        ),
        _api.getDerivativeGainersLosers(datatype: _losersType, expiry: _expiry),
      ]);
      setState(() {
        _gainers = results[0].map(DerivativeItem.fromJson).toList();
        _losers = results[1].map(DerivativeItem.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('BackendException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Gainers & Losers'),
        leading: const BackButton(),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Gainers (${_gainers.length})'),
            Tab(text: 'Losers (${_losers.length})'),
          ],
        ),
        actions: [
          // Mode toggle: OI % vs Price %
          _DropdownChip(
            value: _mode,
            items: const ['OI %', 'Price %'],
            onChanged: (v) {
              setState(() => _mode = v);
              _fetch();
            },
          ),
          const SizedBox(width: 4),
          // Expiry selector
          _DropdownChip(
            value: _expiry,
            items: const ['NEAR', 'NEXT', 'FAR'],
            onChanged: (v) {
              setState(() => _expiry = v);
              _fetch();
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _fetch,
            tooltip: 'Refresh',
          ),
        ],
      ),
      // ── Use a nested structure so TabBarView always renders ──────────────────
      body: Column(
        children: [
          if (_loading)
            const Expanded(
              child: BackendLoadingWidget(
                message: 'Loading derivatives data...',
              ),
            )
          else if (_error != null)
            Expanded(
              child: BackendErrorWidget(message: _error, onRetry: _fetch),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _DerivativeList(
                    items: _gainers,
                    isGainers: true,
                    showOI: _mode == 'OI %',
                  ),
                  _DerivativeList(
                    items: _losers,
                    isGainers: false,
                    showOI: _mode == 'OI %',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── List ─────────────────────────────────────────────────────────────────────

class _DerivativeList extends StatelessWidget {
  final List<DerivativeItem> items;
  final bool isGainers;
  final bool showOI;

  const _DerivativeList({
    required this.items,
    required this.isGainers,
    required this.showOI,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No data available.\nDerivatives data is only available during market hours\n(9:15 AM – 3:30 PM IST, Mon–Fri).',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
              const SizedBox(width: 28),
              const Expanded(
                flex: 4,
                child: Text(
                  'Symbol',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  showOI ? 'OI Chg%' : 'Price%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (showOI)
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Open Interest',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final isPos = item.percentChange >= 0;
              final color = isPos ? AppColors.success : AppColors.danger;
              final sign = isPos ? '+' : '';

              // Strip expiry/type suffix: HDFCBANK25MAY25FUT → HDFCBANK
              final underlying = item.tradingSymbol.replaceAll(
                RegExp(r'\d{2}[A-Z]{3}\d{2}(FUT|CE|PE)$'),
                '',
              );

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            underlying.isNotEmpty
                                ? underlying
                                : item.tradingSymbol,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            item.tradingSymbol,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$sign${item.percentChange.toStringAsFixed(2)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    if (showOI)
                      Expanded(
                        flex: 3,
                        child: Text(
                          _fmtOI(item.openInterest),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _fmtOI(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ─── Dropdown chip ────────────────────────────────────────────────────────────

class _DropdownChip extends StatelessWidget {
  final String value;
  final List<String> items;
  final void Function(String) onChanged;

  const _DropdownChip({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
