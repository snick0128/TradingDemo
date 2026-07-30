import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'brokerage_calculator_screen.dart';
import 'brokerage_statement_screen.dart';
import 'funds_screen.dart';
import 'ipo_history_screen.dart';
import 'wallet_ledger_screen.dart';

/// Wallet screen — a single Overview (balance, Add Funds / Withdraw CTAs,
/// recent activity), with wallet History as a dedicated top-right action.
/// IPO History / Statement / Calculator live in the overflow menu since
/// they're used far less often than History.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Funds'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.history),
            tooltip: 'Wallet History',
            onPressed: () => _open(context, const WalletLedgerScreen()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'ipo':
                  _open(context, const IpoHistoryScreen());
                case 'statement':
                  _open(context, const BrokerageStatementScreen());
                case 'calculator':
                  _open(context, const BrokerageCalculatorScreen());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'ipo', child: Text('IPO History')),
              PopupMenuItem(value: 'statement', child: Text('Brokerage Statement')),
              PopupMenuItem(value: 'calculator', child: Text('Brokerage Calculator')),
            ],
          ),
        ],
      ),
      body: const FundsScreen(showAppBar: false),
    );
  }
}
