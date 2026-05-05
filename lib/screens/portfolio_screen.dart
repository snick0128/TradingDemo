import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';
import 'holdings_screen.dart';
import 'positions_screen.dart';
import 'realised_pnl_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    if (store.backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Portfolio')),
        body: BackendErrorWidget(
          message: store.backendErrorMessage,
          onRetry: () => store.connectLiveBackend(),
        ),
      );
    }

    final totalValue =
        store.holdings.fold(0.0, (s, h) => s + h.currentValue) +
            store.positions.fold(0.0, (s, p) => s + p.quantity * p.currentPrice);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Portfolio'),
              Text(
                '₹${_fmtValue(totalValue)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Holdings'),
              Tab(text: 'Positions'),
              Tab(text: 'P&L'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            HoldingsScreen(showAppBar: false),
            PositionsScreen(showAppBar: false),
            RealisedPnlScreen(showAppBar: false),
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
