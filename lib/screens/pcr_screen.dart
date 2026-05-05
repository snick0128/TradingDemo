import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';

class PCRScreen extends StatefulWidget {
  const PCRScreen({super.key});

  @override
  State<PCRScreen> createState() => _PCRScreenState();
}

class _PCRScreenState extends State<PCRScreen> {
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  String? _error;
  String _sort = 'pcr_desc'; // pcr_desc | pcr_asc | symbol

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getPCR();
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('BackendException: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _sorted {
    final list = List<Map<String, dynamic>>.from(_data);
    switch (_sort) {
      case 'pcr_asc':
        list.sort((a, b) => (a['pcr'] as num).compareTo(b['pcr'] as num));
        break;
      case 'symbol':
        list.sort((a, b) => (a['tradingSymbol'] as String)
            .compareTo(b['tradingSymbol'] as String));
        break;
      default: // pcr_desc
        list.sort((a, b) => (b['pcr'] as num).compareTo(a['pcr'] as num));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Put-Call Ratio (PCR)'),
        leading: const BackButton(),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pcr_desc', child: Text('PCR: High → Low')),
              PopupMenuItem(value: 'pcr_asc',  child: Text('PCR: Low → High')),
              PopupMenuItem(value: 'symbol',   child: Text('Symbol A → Z')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _loading
          ? const BackendLoadingWidget(message: 'Loading PCR data...')
          : _error != null
              ? BackendErrorWidget(message: _error, onRetry: _fetch)
              : Column(
                  children: [
                    // Legend
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: AppColors.surfaceAlt,
                      child: const Row(
                        children: [
                          _LegendDot(color: AppColors.success, label: 'PCR > 1.2  Bearish'),
                          SizedBox(width: 16),
                          _LegendDot(color: AppColors.warning, label: 'PCR 0.8–1.2  Neutral'),
                          SizedBox(width: 16),
                          _LegendDot(color: AppColors.danger,  label: 'PCR < 0.8  Bullish'),
                        ],
                      ),
                    ),
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: AppColors.surface,
                      child: const Row(
                        children: [
                          Expanded(flex: 5, child: Text('Symbol',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text('PCR',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary))),
                          Expanded(flex: 3, child: Text('Sentiment',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary))),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _data.isEmpty
                          ? const Center(
                              child: Text(
                                'No PCR data available.\nPCR is only available during market hours.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _sorted.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _sorted[index];
                                final pcr = (item['pcr'] as num).toDouble();
                                final symbol = item['tradingSymbol'] as String;
                                final underlying = symbol.replaceAll(
                                    RegExp(r'\d{2}[A-Z]{3}\d{2}(FUT|CE|PE)$'), '');

                                Color pcrColor;
                                String sentiment;
                                if (pcr > 1.2) {
                                  pcrColor = AppColors.success;
                                  sentiment = 'Bearish';
                                } else if (pcr < 0.8) {
                                  pcrColor = AppColors.danger;
                                  sentiment = 'Bullish';
                                } else {
                                  pcrColor = AppColors.warning;
                                  sentiment = 'Neutral';
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(underlying,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: AppColors.textPrimary)),
                                            Text(symbol,
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.textSecondary),
                                                overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          pcr.toStringAsFixed(2),
                                          textAlign: TextAlign.right,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: pcrColor,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: pcrColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            sentiment,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: pcrColor,
                                            ),
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
                ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
