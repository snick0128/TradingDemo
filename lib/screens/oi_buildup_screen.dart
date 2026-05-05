import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';

class OIBuildupScreen extends StatefulWidget {
  const OIBuildupScreen({super.key});

  @override
  State<OIBuildupScreen> createState() => _OIBuildupScreenState();
}

class _OIBuildupScreenState extends State<OIBuildupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  static const _datatypes = [
    'Long Built Up',
    'Short Built Up',
    'Short Covering',
    'Long Unwinding',
  ];

  String _expiry = 'NEAR';
  final Map<String, List<Map<String, dynamic>>> _cache = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _datatypes.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _fetchCurrent();
    });
    _fetchCurrent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentDatatype => _datatypes[_tabController.index];

  String _cacheKey(String datatype) => '$datatype|$_expiry';

  Future<void> _fetchCurrent() async {
    final datatype = _currentDatatype;
    final key = _cacheKey(datatype);
    if (_cache.containsKey(key)) return; // already loaded

    setState(() { _loading[key] = true; _errors[key] = null; });
    try {
      final data = await _api.getOIBuildup(datatype: datatype, expiry: _expiry);
      setState(() { _cache[key] = data; _loading[key] = false; });
    } catch (e) {
      setState(() {
        _errors[key] = e.toString().replaceFirst('BackendException: ', '');
        _loading[key] = false;
      });
    }
  }

  void _onExpiryChanged(String expiry) {
    setState(() {
      _expiry = expiry;
      _cache.clear(); // invalidate cache for new expiry
    });
    _fetchCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OI Buildup'),
        leading: const BackButton(),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _datatypes.map((d) => Tab(text: d)).toList(),
        ),
        actions: [
          // Expiry selector
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _expiry,
                isDense: true,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                items: ['NEAR', 'NEXT', 'FAR']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) { if (v != null) _onExpiryChanged(v); },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cache.remove(_cacheKey(_currentDatatype));
              _fetchCurrent();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: _datatypes.map((datatype) {
          final key = _cacheKey(datatype);
          final isLoading = _loading[key] == true;
          final error = _errors[key];
          final data = _cache[key] ?? [];

          if (isLoading) {
            return const BackendLoadingWidget(message: 'Loading OI data...');
          }
          if (error != null) {
            return BackendErrorWidget(
              message: error,
              onRetry: () {
                _cache.remove(key);
                _fetchCurrent();
              },
            );
          }

          return _OIBuildupList(
            datatype: datatype,
            items: data,
          );
        }).toList(),
      ),
    );
  }
}

// ─── OI Buildup List ──────────────────────────────────────────────────────────

class _OIBuildupList extends StatelessWidget {
  final String datatype;
  final List<Map<String, dynamic>> items;

  const _OIBuildupList({required this.datatype, required this.items});

  Color get _accentColor {
    switch (datatype) {
      case 'Long Built Up':    return AppColors.success;
      case 'Short Built Up':   return AppColors.danger;
      case 'Short Covering':   return AppColors.warning;
      case 'Long Unwinding':   return const Color(0xFFFF6B35);
      default:                 return AppColors.primary;
    }
  }

  String get _description {
    switch (datatype) {
      case 'Long Built Up':  return 'Price ↑ + OI ↑ — Bullish momentum';
      case 'Short Built Up': return 'Price ↓ + OI ↑ — Bearish momentum';
      case 'Short Covering': return 'Price ↑ + OI ↓ — Bears exiting';
      case 'Long Unwinding': return 'Price ↓ + OI ↓ — Bulls exiting';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No $datatype data available.\nOI data is only available during market hours.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        // Description banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _accentColor.withValues(alpha: 0.08),
          child: Text(
            _description,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: _accentColor),
          ),
        ),
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceAlt,
          child: const Row(
            children: [
              SizedBox(width: 28),
              Expanded(flex: 4, child: Text('Symbol',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('LTP',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Chg%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
              Expanded(flex: 3, child: Text('OI Chg',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
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
              final symbol = item['tradingSymbol'] as String? ?? '';
              final underlying = symbol.replaceAll(
                  RegExp(r'\d{2}[A-Z]{3}\d{2}(FUT|CE|PE)$'), '');
              final ltp = (item['ltp'] as num?)?.toDouble() ?? 0;
              final pct = (item['percentChange'] as num?)?.toDouble() ?? 0;
              final oiChg = (item['netChangeOpenInterest'] as num?)?.toDouble() ?? 0;
              final isPos = pct >= 0;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${index + 1}',
                          style: const TextStyle(fontSize: 12,
                              color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(underlying,
                              style: const TextStyle(fontWeight: FontWeight.w700,
                                  fontSize: 14, color: AppColors.textPrimary)),
                          Text(symbol,
                              style: const TextStyle(fontSize: 10,
                                  color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₹${ltp.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${isPos ? '+' : ''}${pct.toStringAsFixed(2)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: isPos ? AppColors.success : AppColors.danger),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _fmtOI(oiChg),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: oiChg >= 0 ? AppColors.success : AppColors.danger,
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
    final sign = v >= 0 ? '+' : '';
    final abs = v.abs();
    if (abs >= 10000000) return '$sign${(v / 10000000).toStringAsFixed(2)}Cr';
    if (abs >= 100000)   return '$sign${(v / 100000).toStringAsFixed(2)}L';
    if (abs >= 1000)     return '$sign${(v / 1000).toStringAsFixed(1)}K';
    return '$sign${v.toStringAsFixed(0)}';
  }
}
