import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class TimeAndSalesScreen extends StatefulWidget {
  final String? symbol;
  final bool showAppBar;

  const TimeAndSalesScreen({super.key, this.symbol, this.showAppBar = true});

  @override
  State<TimeAndSalesScreen> createState() => _TimeAndSalesScreenState();
}

class _TimeAndSalesScreenState extends State<TimeAndSalesScreen> {
  final List<Trade> _trades = [];
  StreamSubscription<Trade>? _subscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    final store = TradingScope.of(context);
    final sym = widget.symbol ?? 'NIFTY';
    _subscription = store.marketDataService.tradeUpdates(sym).listen((trade) {
      if (!mounted) return;
      setState(() {
        _trades.insert(0, trade);
        if (_trades.length > 100) _trades.removeLast();
      });
      // Auto-scroll to top
      if (_scrollController.hasClients && _scrollController.offset < 50) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sym = widget.symbol ?? 'NIFTY';
    final timeFmt = DateFormat('HH:mm:ss');

    final body = Column(
      children: [
        // Header row
        Container(
          color: AppColors.surfaceAlt.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'Time',
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
                  'Price',
                  textAlign: TextAlign.center,
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
                  'Qty',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Dir',
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
          child: _trades.isEmpty
              ? const Center(
                  child: Text(
                    'Waiting for trades...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  controller: _scrollController,
                  itemCount: _trades.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final trade = _trades[index];
                    final color = trade.isBuyerInitiated
                        ? AppColors.success
                        : AppColors.danger;
                    return Container(
                      color: index == 0
                          ? color.withOpacity(0.05)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              timeFmt.format(trade.time),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              trade.price.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${trade.quantity}',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Icon(
                              trade.isBuyerInitiated
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 14,
                              color: color,
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

    if (!widget.showAppBar) return Scaffold(body: body);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Time & Sales — $sym'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
