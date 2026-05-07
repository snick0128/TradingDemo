import 'package:flutter/material.dart';

import '../theme.dart';
import 'funds_screen.dart';
import 'add_funds_screen.dart';
import 'withdraw_funds_screen.dart';
import 'transaction_ledger_screen.dart';
import 'brokerage_statement_screen.dart';
import 'brokerage_calculator_screen.dart';

/// Clean wallet screen — single AppBar, no duplicate "Funds" heading inside.
/// Tabs: Overview · Add · Withdraw · Ledger · Statement · Calculator
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    Tab(text: 'Overview'),
    Tab(text: 'Add Funds'),
    Tab(text: 'Withdraw'),
    Tab(text: 'Ledger'),
    Tab(text: 'Statement'),
    Tab(text: 'Calculator'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Funds'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FundsScreen(showAppBar: false),
          AddFundsScreen(showAppBar: false),
          WithdrawFundsScreen(showAppBar: false),
          TransactionLedgerScreen(showAppBar: false),
          BrokerageStatementScreen(showAppBar: false),
          BrokerageCalculatorScreen(showAppBar: false),
        ],
      ),
    );
  }
}
