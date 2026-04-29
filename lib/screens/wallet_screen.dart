import 'package:flutter/material.dart';

import '../theme.dart';
import 'funds_screen.dart';
import 'add_funds_screen.dart';
import 'withdraw_funds_screen.dart';
import 'transaction_ledger_screen.dart';
import 'brokerage_statement_screen.dart';
import 'brokerage_calculator_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Funds'),
            Tab(text: 'Add Funds'),
            Tab(text: 'Withdraw'),
            Tab(text: 'Ledger'),
            Tab(text: 'Statement'),
            Tab(text: 'Calculator'),
          ],
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
