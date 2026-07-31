import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/add_funds_flow.dart';
import 'wallet_ledger_screen.dart';
import '../widgets/withdraw_funds_flow.dart';

// ── Indian currency formatter ─────────────────────────────────────────────────
String _fmt(double v) {
  final formatter = NumberFormat('#,##,##0.00', 'en_IN');
  return '₹${formatter.format(v)}';
}

// ── FundsScreen ───────────────────────────────────────────────────────────────
//
// Converted from StatelessWidget to StatefulWidget so it explicitly subscribes
// to TradingStore via addListener(). This guarantees live updates on every
// price tick and Firestore change regardless of TabBarView mount/unmount cycles.
// A StatelessWidget relying on InheritedWidget can silently lose its dependency
// subscription when the tab is scrolled out of the PageView cache range.

class FundsScreen extends StatefulWidget {
  final bool showAppBar;
  const FundsScreen({super.key, this.showAppBar = true});

  @override
  State<FundsScreen> createState() => _FundsScreenState();
}

class _FundsScreenState extends State<FundsScreen>
    with AutomaticKeepAliveClientMixin {
  TradingStore? _store;

  // Keep this tab alive inside TabBarView so the store subscription is
  // never dropped when the user switches to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store == store) return;
    _store?.removeListener(_onStoreUpdate);
    _store = store;
    store.addListener(_onStoreUpdate);
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreUpdate);
    super.dispose();
  }

  void _onStoreUpdate() {
    if (mounted) setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final store = _store ?? TradingScope.read(context);

    // ── Live values (always from streaming store, never from stale cache) ──
    final balance         = store.balance;                          // free cash after margin blocked
    final usedMargin      = store.usedMargin;                       // sum of marginUsed on open positions
    final availableMargin = store.availableMargin;                  // max(0, equity - usedMargin)
    final marginShortfall = store.marginShortfall;                  // max(0, usedMargin - equity)
    final totalFunds      = balance + usedMargin;                   // total deposited funds
    final stockHoldings    = store.totalCurrentValue;                // holdings at current market value
    final collateral      = store.marginBreakdown.collateralValue;  // haircut-adjusted pledge value

    final body = Container(
      color: const Color(0xFFFAFAFA),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _HeroCard(
              availableMargin: availableMargin,
              usedMargin:      usedMargin,
              totalFunds:      totalFunds,
            ),
            const SizedBox(height: 16),
            _ActionButtonsRow(),
            if (marginShortfall > 0) ...[
              const SizedBox(height: 16),
              _ShortfallBanner(marginShortfall: marginShortfall),
            ],
            const SizedBox(height: 20),
            _AccountBreakdownCard(
              cashBalance:    balance,
              stockHoldings:  stockHoldings,
              fnoMargin:      usedMargin,
              collateral:     collateral,
            ),
            const SizedBox(height: 24),
            const _PendingRequestsBanner(),
            _RecentTransactionsSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Funds')),
      body: body,
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final double availableMargin;
  final double usedMargin;
  final double totalFunds;

  const _HeroCard({
    required this.availableMargin,
    required this.usedMargin,
    required this.totalFunds,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B6B), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Margin',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _fmt(availableMargin),
              style: GoogleFonts.inter(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroPill(label: 'Used Margin', value: usedMargin),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroPill(label: 'Total Funds', value: totalFunds),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String label;
  final double value;

  const _HeroPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _fmt(value),
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add Funds / Withdraw buttons — sit below the hero card, not inside it ────

class _ActionButtonsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => showAddFundsFlow(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add Funds', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => showWithdrawFundsFlow(context),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text('Withdraw', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D0D0D),
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shortfall risk banner ──────────────────────────────────────────────────────

class _ShortfallBanner extends StatelessWidget {
  final double marginShortfall;
  const _ShortfallBanner({required this.marginShortfall});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.06),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Margin Shortfall: ${_fmt(marginShortfall)} — add funds or reduce positions',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Account breakdown card ─────────────────────────────────────────────────────

class _AccountBreakdownCard extends StatelessWidget {
  final double cashBalance;
  final double stockHoldings;
  final double fnoMargin;
  final double collateral;

  const _AccountBreakdownCard({
    required this.cashBalance,
    required this.stockHoldings,
    required this.fnoMargin,
    required this.collateral,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _BreakdownRow('Cash Balance', 'Available for trading', cashBalance),
          const _Sep(),
          _BreakdownRow('Stock Holdings', 'Pledged value', stockHoldings),
          const _Sep(),
          _BreakdownRow('F&O Margin', 'Used in F&O positions', fnoMargin),
          const _Sep(),
          _BreakdownRow('Collateral', 'From pledged securities', collateral),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;

  const _BreakdownRow(this.title, this.subtitle, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0D0D0D)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
          Text(
            _fmt(value),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0D0D0D),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFF5F5F5));
}

// ── Pending deposit/withdrawal requests — compact banner above transactions ──
//
// Ledger entries are only written once a request is approved, so a pending
// admin-approval request never shows up in the unified transaction feed
// below. This keeps that "is my withdrawal still processing" visibility
// without reintroducing the old separate pending/recent split.

class _PendingRequestsBanner extends StatelessWidget {
  const _PendingRequestsBanner();

  @override
  Widget build(BuildContext context) {
    final uid = AppScope.of(context).notifier?.user?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      stream: _combineStreams([
        FirebaseFirestore.instance
            .collection('deposit_requests')
            .where('userId', isEqualTo: uid)
            .where('status', isEqualTo: 'PENDING')
            .snapshots(),
        FirebaseFirestore.instance
            .collection('withdrawal_requests')
            .where('userId', isEqualTo: uid)
            .where('status', isEqualTo: 'PENDING')
            .snapshots(),
      ]),
      builder: (context, snapshot) {
        final snaps = snapshot.data;
        if (snaps == null) return const SizedBox.shrink();
        final pendingCount = snaps.fold<int>(0, (sum, s) => sum + s.docs.length);
        if (pendingCount == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.clock, size: 15, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pendingCount == 1
                        ? '1 request pending approval'
                        : '$pendingCount requests pending approval',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Merges the latest snapshot from each stream into one combined list,
  /// firing whenever any single stream updates.
  Stream<List<QuerySnapshot<Map<String, dynamic>>>> _combineStreams(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
  ) {
    final latest = List<QuerySnapshot<Map<String, dynamic>>?>.filled(streams.length, null);
    late final StreamController<List<QuerySnapshot<Map<String, dynamic>>>> controller;
    final subs = <StreamSubscription>[];

    controller = StreamController.broadcast(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subs.add(streams[i].listen((snap) {
            latest[i] = snap;
            if (latest.every((s) => s != null)) {
              controller.add(latest.cast<QuerySnapshot<Map<String, dynamic>>>());
            }
          }));
        }
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return controller.stream;
  }
}

// ── Recent transactions — unified ledger feed ─────────────────────────────────

class _RecentTransactionsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = AppScope.of(context).notifier?.user?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ledger')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Transactions',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0D0D0D)),
                  ),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletLedgerScreen()),
                    ),
                    child: Text(
                      'View All',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'No transactions yet',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9E9E9E)),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < docs.length; i++) ...[
                      if (i > 0) const _Sep(),
                      _TransactionRow(
                        entry: WalletLedgerEntry.fromFirestore(docs[i].id, docs[i].data()),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WalletLedgerEntry entry;
  const _TransactionRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.credit > 0;
    final color = isCredit ? AppColors.success : AppColors.danger;
    final icon = isCredit ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight;
    final title = entry.remarks.isNotEmpty ? entry.remarks : entry.type.displayName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF0D0D0D)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _relativeDate(entry.createdAt),
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isCredit ? '+' : '-'}${_fmt(entry.amount)}',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _relativeDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diffDays = today.difference(that).inDays;

    if (diffDays == 0) return 'Today ${DateFormat('h:mm a').format(d)}';
    if (diffDays == 1) return 'Yesterday ${DateFormat('h:mm a').format(d)}';
    return DateFormat('MMM d, yyyy').format(d);
  }
}
